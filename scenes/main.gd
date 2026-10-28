extends Control
## Cena inicial: carrega os dados, cria o estado e monta a tela de campanha.

const Registry := preload("res://src/core/registry.gd")
const GameState := preload("res://src/core/game_state.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const CampaignScreen := preload("res://src/ui/campaign_screen.gd")

## Fase 1 ainda não tem seleção de nação: o jogador começa com a França.
const DEFAULT_PLAYER_COUNTRY := "fra"

var registry: Registry
var state: GameState
var controller: CampaignController
var screen: CampaignScreen


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

	screen = CampaignScreen.new()
	add_child(screen)
	screen.setup(controller)


func _show_error(errors: PackedStringArray) -> void:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Erro ao carregar os dados:\n" + "\n".join(errors)
	add_child(label)
	for message in errors:
		push_error(message)
