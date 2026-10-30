extends RefCounted
## Ciclo de vida das batalhas no estado da campanha (GameState.battles): registrar, cancelar e transições.
## Camada de integração: usa o resultado do BattleScenarioBuilder (cenário + pedido) e altera SOMENTE o registro
## de batalhas e o campo "battle_id" do encontro; nunca toca efetivo, moral, composição dos exércitos,
## províncias ou turnos. NÃO inicia a cena tática; a aplicação do resultado à campanha é de BattleResolution (Etapa 6), que usa estas transições.
##
## Estados: "active" -> "applied" | "cancelled". "applied" e "cancelled" são finais; o registro nunca é apagado.
## Convenção de retorno: {ok, battle_id, message, errors}.
##
## Encontro pendente (decisão): NÃO é consumido ao registrar. Ele permanece em state.encounters com o campo
## "battle_id" (assim os exércitos continuam em encontro se a batalha for cancelada, e o mesmo encontro não pode
## gerar outra batalha ativa). Ao cancelar, o campo some e o encontro volta a poder iniciar uma batalha.
## Transacional: toda a validação acontece ANTES de qualquer alteração; as alterações são apenas atribuições
## que não falham (o id só é consumido junto com o registro).

const BattleRequest := preload("res://src/integration/battle_request.gd")
const GameState := preload("res://src/core/game_state.gd")

const TRANSITIONS := {
	GameState.BATTLE_ACTIVE: [GameState.BATTLE_APPLIED, GameState.BATTLE_CANCELLED],
	GameState.BATTLE_APPLIED: [],
	GameState.BATTLE_CANCELLED: [],
}


## Registra uma batalha ativa para o encontro, a partir do resultado ok de BattleScenarioBuilder.build().
## Recusa (sem alterar nada) se o pedido estiver desatualizado, o cenário não corresponder ao pedido, o encontro
## já tiver batalha ativa ou algum exército já estiver em batalha ativa.
static func register(registry: RefCounted, state: RefCounted, built: Dictionary) -> Dictionary:
	if not built.get("ok", false) or typeof(built.get("request")) != TYPE_DICTIONARY \
			or typeof(built.get("scenario")) != TYPE_DICTIONARY or built["request"].is_empty() or built["scenario"].is_empty():
		return _fail(PackedStringArray(["O cenário informado não é um resultado válido do adaptador (ok, request e scenario)."]))
	var request: Dictionary = built["request"]
	var scenario: Dictionary = built["scenario"]

	# Revalida contra o estado ATUAL: pega encontro inexistente/usado, exército bloqueado e pedido desatualizado.
	var fresh := BattleRequest.build(registry, state, int(request.get("encounter_id", 0)))
	if not fresh["ok"]:
		return _fail(fresh["errors"])
	if fresh["request"] != request:
		return _fail(PackedStringArray(["O pedido está desatualizado: a campanha mudou desde que o cenário foi gerado."]))
	var mismatches := scenario_mismatches(request, scenario)
	if not mismatches.is_empty():
		return _fail(mismatches)
	if state.battles.has(state.next_battle_id):
		return _fail(PackedStringArray(["Id de batalha %d já está em uso: registro inconsistente." % state.next_battle_id]))

	# --- tudo validado: a partir daqui só atribuições ---
	var battle_id: int = state.next_battle_id
	var participants: Array[int] = []
	for side in ["player", "enemy"]:
		participants.append_array(request["sides"][side]["armies"])
	participants.sort()
	var units := {}
	for unit_id in request["units"]:
		units[unit_id] = request["units"][unit_id].duplicate()
		units[unit_id]["army"] = request["unit_army"][unit_id]
	state.battles[battle_id] = {
		"id": battle_id,
		"encounter_id": request["encounter_id"],
		"province": request["province_id"],
		"turn": state.turn,
		"status": GameState.BATTLE_ACTIVE,
		"countries": request["countries"].duplicate(),
		"sides": request["sides"].duplicate(true),
		"armies": participants,
		"units": units,
		"scenario_id": scenario["id"],
		"scenario": scenario.duplicate(true),
		"result": {},
		"tactical_result": {},
		"history": [{"status": GameState.BATTLE_ACTIVE, "turn": state.turn}],
	}
	state.next_battle_id += 1
	BattleRequest.find_encounter(state, request["encounter_id"])["battle_id"] = battle_id
	return {"ok": true, "battle_id": battle_id, "errors": PackedStringArray(),
		"message": "Batalha #%d registrada em %s; os exércitos participantes estão bloqueados." % [
			battle_id, registry.provinces[request["province_id"]]["name"]]}


## Cancela uma batalha ativa: libera os exércitos e o encontro volta a ser iniciável. Não altera dados estratégicos.
static func cancel(state: RefCounted, battle_id: int) -> Dictionary:
	var result := transition(state, battle_id, GameState.BATTLE_CANCELLED)
	if result["ok"]:
		result["message"] = "Batalha #%d cancelada: exércitos liberados, sem efeito na campanha." % battle_id
	return result


## Guarda o resultado da cena tática (BattleState.result_summary) na batalha ATIVA, uma única vez. NÃO muda o
## estado da batalha (continua "active": os exércitos seguem bloqueados e o turno travado até a Etapa 6 aplicar
## o resultado ou o jogador cancelar) e NÃO toca "result" nem qualquer dado estratégico.
static func record_tactical_result(state: RefCounted, battle_id: int, summary: Dictionary) -> Dictionary:
	var reason := check_can_record_result(state, battle_id, summary)
	if not reason.is_empty():
		return _fail(PackedStringArray([reason]), battle_id)
	state.battles[battle_id]["tactical_result"] = summary.duplicate(true)
	return {"ok": true, "battle_id": battle_id, "errors": PackedStringArray(),
		"message": "Resultado tático da batalha #%d registrado (ainda não aplicado à campanha)." % battle_id}


## Motivo pelo qual o resultado tático não pode ser registrado; "" se pode. Não altera nada.
static func check_can_record_result(state: RefCounted, battle_id: int, summary: Dictionary) -> String:
	if not state.battles.has(battle_id):
		return "Batalha #%d inexistente." % battle_id
	var battle: Dictionary = state.battles[battle_id]
	if battle["status"] != GameState.BATTLE_ACTIVE:
		return "A batalha #%d está '%s': só uma batalha ativa recebe resultado tático." % [battle_id, battle["status"]]
	if not battle.get("tactical_result", {}).is_empty():
		return "A batalha #%d já tem resultado tático registrado." % battle_id
	if summary.get("scenario_id") != battle["scenario_id"]:
		return "O resultado é do cenário '%s', não do cenário da batalha #%d ('%s')." % [str(summary.get("scenario_id")), battle_id, battle["scenario_id"]]
	if not (summary.get("winner") in ["player", "enemy", "draw"]) or typeof(summary.get("units")) != TYPE_DICTIONARY:
		return "Resultado tático incompleto (vencedor ou unidades ausentes): batalha não concluída."
	return ""


## Única porta de mudança de estado de uma batalha. Valida a transição (active -> applied | cancelled).
## "applied" é usado por BattleResolution quando o resultado é aplicado por inteiro; aqui apenas se protege o ciclo de vida.
static func transition(state: RefCounted, battle_id: int, new_status: String) -> Dictionary:
	var reason := check_transition(state, battle_id, new_status)
	if not reason.is_empty():
		return _fail(PackedStringArray([reason]), battle_id)
	var battle: Dictionary = state.battles[battle_id]
	battle["status"] = new_status
	battle["history"].append({"status": new_status, "turn": state.turn})
	if new_status != GameState.BATTLE_ACTIVE:
		var encounter := BattleRequest.find_encounter(state, battle["encounter_id"])
		if not encounter.is_empty() and encounter.get("battle_id") == battle_id:
			encounter.erase("battle_id")
	return {"ok": true, "battle_id": battle_id, "errors": PackedStringArray(), "message": "Batalha #%d: %s." % [battle_id, new_status]}


## Motivo pelo qual a transição não é permitida; "" se for. Não altera nada.
static func check_transition(state: RefCounted, battle_id: int, new_status: String) -> String:
	if not state.battles.has(battle_id):
		return "Batalha #%d inexistente." % battle_id
	if not TRANSITIONS.has(new_status):
		return "Estado de batalha desconhecido: '%s'." % new_status
	var current: String = state.battles[battle_id]["status"]
	if not (new_status in TRANSITIONS.get(current, [])):
		return "A batalha #%d está '%s' e não pode passar a '%s'." % [battle_id, current, new_status]
	return ""


## Motivo pelo qual o resultado da batalha não pode ser aplicado; "" se ainda pode (batalha ativa). Protege contra
## aplicação duplicada ou sobre batalha cancelada.
static func check_can_apply(state: RefCounted, battle_id: int) -> String:
	return check_transition(state, battle_id, GameState.BATTLE_APPLIED)


## Diferenças entre o cenário e o pedido (vazio = coerentes): mesmas unidades de origem, lados, efetivo e moral.
static func scenario_mismatches(request: Dictionary, scenario: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if typeof(scenario.get("id")) != TYPE_STRING or (scenario["id"] as String).is_empty():
		problems.append("O cenário não tem id.")
	var units: Variant = scenario.get("units")
	if typeof(units) != TYPE_ARRAY:
		problems.append("O cenário não tem lista de unidades.")
		return problems
	var seen := {}
	for u in units:
		var source_id: int = int(u.get("source_id", 0)) if typeof(u) == TYPE_DICTIONARY else 0
		if not request["units"].has(source_id):
			problems.append("O cenário tem uma unidade (source_id %d) que não está no pedido." % source_id)
			continue
		seen[source_id] = true
		var snapshot: Dictionary = request["units"][source_id]
		var expected_side := "player" if source_id in request["sides"]["player"]["units"] else "enemy"
		if u.get("side") != expected_side:
			problems.append("Unidade %d: lado do cenário (%s) difere do pedido (%s)." % [source_id, str(u.get("side")), expected_side])
		if int(u.get("strength", -1)) != snapshot["strength"] or int(u.get("morale", -1)) != snapshot["morale"]:
			problems.append("Unidade %d: efetivo/moral do cenário diferem do instantâneo do pedido." % source_id)
	for source_id in request["units"]:
		if not seen.has(source_id):
			problems.append("A unidade %d do pedido não aparece no cenário." % source_id)
	return problems


static func _fail(errors: PackedStringArray, battle_id: int = 0) -> Dictionary:
	return {"ok": false, "battle_id": battle_id, "errors": errors, "message": "; ".join(errors)}
