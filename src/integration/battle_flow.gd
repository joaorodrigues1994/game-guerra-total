extends RefCounted
## Fluxo "encontro da campanha -> batalha tática" (Etapa 5), sem nós e sem interface. Orquestra, sem duplicar
## regras, as peças existentes: BattleScenarioBuilder (pedido + cenário), BattleLifecycle (registro, bloqueios,
## cancelamento) e BattleController (cena tática).
##
## start(): (1) constrói e valida o cenário a partir do encontro; (2) REGISTRA a batalha (bloqueia os exércitos);
## (3) inicializa o controlador tático com o cenário GUARDADO NO REGISTRO (nunca reconstrói outro); se (3) falhar,
## a batalha é cancelada na hora (nada de batalha ativa inacessível nem bloqueio órfão; fica um registro
## "cancelled" no histórico e o id é consumido). Chamadas repetidas para o mesmo encontro são recusadas pelo
## BattleRequest (encontro com batalha ativa).
##
## Resultado: record_result() só guarda o resumo tático em battle["tactical_result"] (a batalha continua "active").
## finish() = record_result() + apply_result(): ao terminar a cena, registra e aplica à campanha UMA vez
## (BattleResolution), levando a batalha a "applied". Se a aplicação falhar, o resultado tático continua guardado
## e a batalha "active", para nova tentativa (apply_result) ou cancelamento.
##
## Convenção de retorno: {ok, battle_id, controller, errors, message}.

const BattleController := preload("res://src/battle/battle_controller.gd")
const BattleRegistry := preload("res://src/battle/battle_registry.gd")
const BattleRequest := preload("res://src/integration/battle_request.gd")
const Builder := preload("res://src/integration/battle_scenario_builder.gd")
const Lifecycle := preload("res://src/integration/battle_lifecycle.gd")
const Resolution := preload("res://src/integration/battle_resolution.gd")


## Carrega o que o fluxo precisa além do estado da campanha: dados da batalha e mapeamento de terrenos.
## Devolve {ok, battle_registry, mapping, errors}.
static func load_context() -> Dictionary:
	var battle_registry := BattleRegistry.new()
	if not battle_registry.load_from_dir():
		return {"ok": false, "battle_registry": null, "mapping": {}, "errors": battle_registry.errors}
	var loaded := Builder.load_mapping()
	if not loaded["ok"]:
		return {"ok": false, "battle_registry": null, "mapping": {}, "errors": loaded["errors"]}
	return {"ok": true, "battle_registry": battle_registry, "mapping": loaded["mapping"], "errors": PackedStringArray()}


## Motivo pelo qual NÃO é possível iniciar a batalha do encontro agora; "" se é possível. Somente leitura.
static func start_reason(registry: RefCounted, state: RefCounted, encounter_id: int) -> String:
	var request := BattleRequest.build(registry, state, encounter_id)
	return "" if request["ok"] else " ".join(PackedStringArray(request["errors"]))


## Inicia a batalha do encontro. `opener` (opcional) substitui a criação do controlador tático a partir do cenário
## registrado: Callable(battle_registry, scenario) -> BattleController ou null (usado para testar a falha).
static func start(registry: RefCounted, state: RefCounted, context: Dictionary, encounter_id: int,
		opener: Callable = Callable()) -> Dictionary:
	if not context.get("ok", false):
		return _fail(context.get("errors", PackedStringArray(["Dados da batalha indisponíveis."])))
	var built := Builder.build(registry, state, context["battle_registry"], context["mapping"], encounter_id)
	if not built["ok"]:
		return _fail(built["errors"])
	var registered := Lifecycle.register(registry, state, built)
	if not registered["ok"]:
		return _fail(registered["errors"])
	var battle_id: int = registered["battle_id"]

	# A partir daqui a batalha está registrada: qualquer falha a CANCELA antes de devolver o erro.
	var scenario: Dictionary = state.battles[battle_id]["scenario"]
	var controller: BattleController = _open(context["battle_registry"], scenario, opener)
	if controller == null:
		Lifecycle.cancel(state, battle_id)
		return _fail(PackedStringArray(["Não foi possível iniciar a cena tática; a batalha #%d foi cancelada e os exércitos liberados." % battle_id]), battle_id)
	controller.linked_battle_id = battle_id
	return {"ok": true, "battle_id": battle_id, "controller": controller, "errors": PackedStringArray(),
		"message": registered["message"]}


## Guarda o resultado tático (BattleState.result_summary) na batalha. A batalha NÃO muda de estado.
static func record_result(state: RefCounted, battle_id: int, summary: Dictionary) -> Dictionary:
	return Lifecycle.record_tactical_result(state, battle_id, summary)


## Aplica à campanha o resultado tático já registrado (também serve para tentar de novo após uma falha).
static func apply_result(registry: RefCounted, state: RefCounted, battle_id: int) -> Dictionary:
	return Resolution.apply(registry, state, battle_id)


## A cena tática terminou: registra o resumo e o aplica. Devolve {ok, recorded, applied, report, errors, message}.
## ok = aplicado. Se registrou mas não aplicou, recorded = true e applied = false.
static func finish(registry: RefCounted, state: RefCounted, battle_id: int, summary: Dictionary) -> Dictionary:
	var recorded := record_result(state, battle_id, summary)
	if not recorded["ok"]:
		return {"ok": false, "recorded": false, "applied": false, "report": {}, "errors": recorded["errors"], "message": recorded["message"]}
	var applied := apply_result(registry, state, battle_id)
	return {"ok": applied["ok"], "recorded": true, "applied": applied["ok"], "report": applied["report"],
		"errors": applied["errors"], "message": applied["message"]}


static func _open(battle_registry: RefCounted, scenario: Dictionary, opener: Callable) -> BattleController:
	if opener.is_valid():
		return opener.call(battle_registry, scenario)
	var controller := BattleController.new()
	return controller if controller.setup_from_scenario(battle_registry, scenario) else null


static func _fail(errors: PackedStringArray, battle_id: int = 0) -> Dictionary:
	return {"ok": false, "battle_id": battle_id, "controller": null, "errors": errors, "message": " ".join(errors)}
