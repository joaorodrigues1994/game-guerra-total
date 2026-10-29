extends Control
## Cena independente da batalha tática (cenário de teste). Pode ser executada direto, sem a campanha:
##   Godot_v4.7.2-stable_win64.exe --path <projeto> res://scenes/battle.tscn
## (ou abrir scenes/battle.tscn no editor e usar "Executar cena atual", F6).

const BattleRegistry := preload("res://src/battle/battle_registry.gd")
const BattleController := preload("res://src/battle/battle_controller.gd")
const BattleScreen := preload("res://src/ui/battle/battle_screen.gd")

var controller: BattleController
var screen: BattleScreen


func _ready() -> void:
	var registry := BattleRegistry.new()
	controller = BattleController.new()
	if not registry.load_from_dir() or not controller.setup(registry, BattleRegistry.DEFAULT_SCENARIO):
		var label := Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.text = "Erro ao carregar os dados da batalha:\n" + "\n".join(registry.errors)
		add_child(label)
		for message in registry.errors:
			push_error(message)
		return
	screen = BattleScreen.new()
	add_child(screen)
	screen.setup(controller, false)
