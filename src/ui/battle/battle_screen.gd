extends Control
## Tela da batalha tática: barra superior (turno, lado ativo, botões), mapa hexagonal, painel da unidade,
## registro de combate e painel de resultado. Esc limpa a seleção.

const BattleController := preload("res://src/battle/battle_controller.gd")
const BattleLogPanel := preload("res://src/ui/battle/battle_log_panel.gd")
const BattlePanel := preload("res://src/ui/battle/battle_panel.gd")
const BattleResultPanel := preload("res://src/ui/battle/battle_result_panel.gd")
const BattleView := preload("res://src/ui/battle/battle_view.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

## Pedido para voltar à tela anterior (a campanha), quando a batalha foi aberta a partir dela.
signal back_requested

var controller: BattleController
var title_label: Label
var turn_label: Label
var end_turn_button: Button
var restart_button: Button
var back_button: Button
var map_view: Control
var unit_panel: PanelContainer
var log_panel: PanelContainer
var result_panel: Control
## Batalha da campanha cujo resultado não pôde ser aplicado (ver set_application_failed).
var application_failed: bool = false


func setup(p_controller: BattleController, allow_back: bool) -> void:
	controller = p_controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_top_bar(allow_back))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	body.add_child(left)

	map_view = BattleView.new()
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.bind(controller)
	left.add_child(map_view)

	log_panel = BattleLogPanel.new()
	log_panel.bind(controller)
	left.add_child(log_panel)

	unit_panel = BattlePanel.new()
	unit_panel.bind(controller)
	body.add_child(unit_panel)

	# Por último, para ficar sobre todo o resto.
	result_panel = BattleResultPanel.new()
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.bind(controller, allow_back)
	result_panel.restart_requested.connect(controller.restart)
	result_panel.back_requested.connect(func() -> void: back_requested.emit())
	add_child(result_panel)

	controller.state_changed.connect(_refresh_top_bar)
	controller.restarted.connect(_refresh_top_bar)
	controller.battle_finished.connect(func(_summary: Dictionary) -> void: _refresh_top_bar())
	_refresh_top_bar()


func _build_top_bar(allow_back: bool) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 52)
	bar.add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_BOTTOM]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	title_label = UiStyle.make_label(22, UiStyle.ACCENT)
	title_label.text = "Batalha tática — %s" % controller.state.scenario_name
	if controller.linked_battle_id != 0:
		title_label.text += " (batalha #%d da campanha)" % controller.linked_battle_id
	row.add_child(title_label)

	turn_label = UiStyle.make_label(16)
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.clip_text = true
	row.add_child(turn_label)

	end_turn_button = Button.new()
	end_turn_button.text = "Encerrar turno"
	end_turn_button.pressed.connect(func() -> void: controller.end_turn())
	row.add_child(end_turn_button)

	restart_button = Button.new()
	restart_button.text = "Reiniciar batalha"
	restart_button.visible = controller.linked_battle_id == 0  # batalha da campanha não reinicia
	restart_button.pressed.connect(func() -> void: controller.restart())
	row.add_child(restart_button)

	back_button = Button.new()
	back_button.text = "Voltar à campanha"
	back_button.visible = allow_back
	back_button.pressed.connect(func() -> void: back_requested.emit())
	row.add_child(back_button)
	return bar


## O resultado da batalha da campanha NÃO foi aplicado: mostra o erro no painel de resultado e sinaliza no botão de voltar
## que a batalha continua pendente (a nova tentativa e o cancelamento ficam no painel da província, na campanha).
func set_application_failed(text: String) -> void:
	application_failed = true
	result_panel.set_application_failure(text)
	_refresh_top_bar()


func _refresh_top_bar() -> void:
	var state: RefCounted = controller.state
	turn_label.text = controller.turn_text() if not state.over else "Batalha encerrada — %s" % controller.result_view()["title"]
	end_turn_button.disabled = state.over or state.active_side != BattleController.PLAYER
	if controller.linked_battle_id != 0:
		# Batalha da campanha: sair antes do fim CANCELA a batalha; depois do fim apenas volta (o resultado fica registrado).
		back_button.text = "Voltar à campanha" if state.over else "Cancelar batalha e voltar"
		if application_failed:
			back_button.text = "Voltar à campanha (resultado pendente)"


func _unhandled_input(event: InputEvent) -> void:
	if controller != null and event.is_action_pressed("ui_cancel"):
		controller.clear_selection()
		if is_inside_tree():
			get_viewport().set_input_as_handled()
