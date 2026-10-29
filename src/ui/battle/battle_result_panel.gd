extends Control
## Painel de resultado da batalha, sobre o mapa: vencedor, motivo, sobreviventes e botões.

const BattleController := preload("res://src/battle/battle_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

signal restart_requested
signal back_requested

var title_label: Label
var reason_label: Label
var player_label: Label
var enemy_label: Label
var restart_button: Button
var back_button: Button


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # impede cliques no mapa por baixo

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	title_label = UiStyle.make_label(30, UiStyle.ACCENT, true)
	column.add_child(title_label)
	reason_label = UiStyle.make_label(15, UiStyle.TEXT, true)
	column.add_child(reason_label)
	player_label = UiStyle.make_label(13, UiStyle.TEXT, true)
	column.add_child(player_label)
	enemy_label = UiStyle.make_label(13, UiStyle.TEXT, true)
	column.add_child(enemy_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	restart_button = Button.new()
	restart_button.text = "Jogar novamente"
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	buttons.add_child(restart_button)
	back_button = Button.new()
	back_button.text = "Voltar à campanha"
	back_button.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back_button)


func bind(controller: BattleController, allow_back: bool) -> void:
	back_button.visible = allow_back
	controller.battle_finished.connect(func(_summary: Dictionary) -> void: show_result(controller.result_view(), controller))
	controller.restarted.connect(func() -> void: visible = false)


func show_result(view: Dictionary, controller: BattleController) -> void:
	if view.is_empty():
		visible = false
		return
	title_label.text = view["title"]
	reason_label.text = view["text"]
	player_label.text = _side_text(controller.state.sides["player"]["name"], view["lines"]["player"])
	enemy_label.text = _side_text(controller.state.sides["enemy"]["name"], view["lines"]["enemy"])
	visible = true


func _side_text(side_name: String, entries: Array) -> String:
	return "%s\n  %s" % [side_name, "\n  ".join(PackedStringArray(entries))]
