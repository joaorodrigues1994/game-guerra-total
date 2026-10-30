extends Control
## Cena inicial: carrega os dados, cria o estado e monta a tela de campanha.

const Registry := preload("res://src/core/registry.gd")
const GameState := preload("res://src/core/game_state.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const CampaignScreen := preload("res://src/ui/campaign_screen.gd")
const BattleRegistry := preload("res://src/battle/battle_registry.gd")
const BattleController := preload("res://src/battle/battle_controller.gd")
const BattleScreen := preload("res://src/ui/battle/battle_screen.gd")

## Fase 1 ainda não tem seleção de nação: o jogador começa com a França.
const DEFAULT_PLAYER_COUNTRY := "fra"

var registry: Registry
var state: GameState
var controller: CampaignController
var screen: CampaignScreen
## Batalha de teste aberta por cima da campanha (null = fechada). A campanha continua viva por baixo.
var battle_screen: BattleScreen
## Id da batalha REGISTRADA da campanha mostrada em battle_screen (0 = batalha de teste ou nenhuma).
var current_battle_id: int = 0


func _ready() -> void:
	registry = Registry.new()
	state = GameState.new()
	if not registry.load_from_dir("res://data") or not state.setup_from_registry(registry, DEFAULT_PLAYER_COUNTRY):
		_show_error(registry.errors)
		return

	var province_map := ProvinceMap.new()
	province_map.build(registry)
	controller = CampaignController.new()
	controller.setup(registry, state, province_map)
	controller.bus = get_node_or_null("/root/EventBus")  # autoload; ausente em testes sem o projeto completo

	screen = CampaignScreen.new()
	add_child(screen)
	screen.setup(controller)
	screen.battle_requested.connect(open_test_battle)
	controller.battle_started.connect(_on_battle_started)
	controller.battle_resolved.connect(_on_battle_resolved)
	controller.battle_application_failed.connect(_on_battle_application_failed)


## Abre a batalha de teste sobre a campanha, sem descartar o estado dela. Devolve false se já estiver aberta
## ou se os dados da batalha não carregarem.
func open_test_battle() -> bool:
	if battle_screen != null:
		return false
	var battle_registry := BattleRegistry.new()
	var battle := BattleController.new()
	if not battle_registry.load_from_dir() or not battle.setup(battle_registry, BattleRegistry.DEFAULT_SCENARIO):
		controller.message_posted.emit("Não foi possível carregar a batalha de teste.", true)
		for message in battle_registry.errors:
			push_error(message)
		return false
	_show_battle(battle)
	return true


## A campanha registrou uma batalha: abre a cena tática dela sobre a campanha. Se não puder abrir (já há uma
## batalha na tela), CANCELA a batalha registrada, para não deixar exércitos bloqueados sem cena.
func _on_battle_started(battle_id: int, battle: BattleController) -> void:
	if battle_screen != null:
		controller.cancel_battle(battle_id)
		return
	current_battle_id = battle_id
	_show_battle(battle)


## O resultado foi aplicado à campanha: o painel de resultado da cena tática mostra o que mudou.
func _on_battle_resolved(battle_id: int, lines: PackedStringArray) -> void:
	if battle_screen != null and current_battle_id == battle_id:
		battle_screen.result_panel.set_campaign_note("\n".join(lines))


## O resultado NÃO foi aplicado: a cena tática (a campanha está oculta, com o status bar) mostra o erro completo.
func _on_battle_application_failed(battle_id: int, message: String) -> void:
	if battle_screen != null and current_battle_id == battle_id:
		battle_screen.set_application_failed(message)


func _show_battle(battle: BattleController) -> void:
	battle_screen = BattleScreen.new()
	add_child(battle_screen)
	battle_screen.setup(battle, true)
	battle_screen.back_requested.connect(close_battle)
	screen.visible = false
	screen.set_process_unhandled_input(false)  # o Esc da batalha não deve limpar a seleção da campanha


## Fecha a batalha e volta à campanha (o estado dela nunca foi recriado). Batalha da campanha: se a cena tática
## ainda não terminou, a batalha é CANCELADA (exércitos liberados, sem efeito); se terminou, o resultado já foi
## aplicado ao terminar (batalha "applied"); se a aplicação falhou, a batalha continua ativa com o resultado
## guardado e o painel da província oferece aplicar de novo ou cancelar.
func close_battle() -> void:
	if battle_screen == null:
		return
	var battle_id := current_battle_id
	var finished: bool = battle_screen.controller.state.over
	current_battle_id = 0
	remove_child(battle_screen)
	battle_screen.queue_free()
	battle_screen = null
	screen.visible = true
	screen.set_process_unhandled_input(true)
	if battle_id != 0:
		if finished:
			if state.battles[battle_id]["status"] != "applied":
				controller.message_posted.emit("Batalha #%d concluída, mas o resultado NÃO foi aplicado: aplique de novo ou cancele a batalha no painel da província." % battle_id, true)
			controller.state_changed.emit()
		else:
			controller.cancel_battle(battle_id)


func _show_error(errors: PackedStringArray) -> void:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Erro ao carregar os dados:\n" + "\n".join(errors)
	add_child(label)
	for message in errors:
		push_error(message)
