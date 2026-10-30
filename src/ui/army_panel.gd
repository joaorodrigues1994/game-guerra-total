extends PanelContainer
## Painel do exército selecionado: composição, general, estado de movimento, destinos e organização.
## Mostra apenas o que o controlador entrega (army_view); as ordens passam por CampaignController.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvincePanel := preload("res://src/ui/province_panel.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

var controller: CampaignController

var title_label: Label
var owner_label: Label
var info_label: Label
var general_label: Label
var status_label: Label
var foreign_note_label: Label
var deselect_button: Button
## Botões reconstruídos a cada atualização: destino/unidade/general -> botão.
var move_buttons: Dictionary = {}
var detach_buttons: Dictionary = {}
var join_buttons: Dictionary = {}
var merge_buttons: Dictionary = {}
var general_buttons: Dictionary = {}
var unassign_button: Button

var _owner_swatch: ColorRect
var _sections: VBoxContainer
var _army_id: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(330, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_LEFT, SIDE_TOP]))
	visible = false

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	title_label = UiStyle.make_label(20, UiStyle.ACCENT, true)
	content.add_child(title_label)

	var owner_row := HBoxContainer.new()
	owner_row.add_theme_constant_override("separation", 8)
	_owner_swatch = ColorRect.new()
	_owner_swatch.custom_minimum_size = Vector2(18, 18)
	owner_row.add_child(_owner_swatch)
	owner_label = UiStyle.make_label(15)
	owner_row.add_child(owner_label)
	content.add_child(owner_row)

	info_label = UiStyle.make_label(14, UiStyle.TEXT, true)
	content.add_child(info_label)
	general_label = UiStyle.make_label(14, UiStyle.TEXT, true)
	content.add_child(general_label)
	status_label = UiStyle.make_label(14, UiStyle.ACCENT, true)
	content.add_child(status_label)
	foreign_note_label = UiStyle.make_label(13, UiStyle.TEXT_DIM, true)
	content.add_child(foreign_note_label)

	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 4)
	content.add_child(_sections)

	deselect_button = Button.new()
	deselect_button.text = "Desmarcar exército"
	deselect_button.pressed.connect(func() -> void: controller.clear_army_selection())
	root.add_child(deselect_button)


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.army_selection_changed.connect(func(_id: int) -> void: _refresh())
	controller.state_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	show_army(controller.army_view(controller.selected_army_id))


## Preenche o painel com uma visão de exército (ver CampaignController.army_view); vazio = oculta o painel.
func show_army(view: Dictionary) -> void:
	_clear_sections()
	visible = not view.is_empty()
	if view.is_empty():
		_army_id = 0
		return
	_army_id = view["id"]

	title_label.text = view["name"]
	owner_label.text = ("Seu exército (%s)" if view["is_player"] else "Exército estrangeiro (%s)") % view["owner_name"]
	_owner_swatch.color = view["owner_color"]
	info_label.text = "Província: %s\nUnidades: %d de %d\nEfetivo total: %s homens" % [
		view["province_name"], view["unit_count"], view["max_units"], ProvincePanel.format_int(view["strength"])]
	var general: Dictionary = view["general"]
	general_label.text = "General: %s (comando %d, experiência %d)" % [general["name"], general["command"], general["experience"]] \
		if not general.is_empty() else "General: nenhum"
	status_label.text = view["status"]
	foreign_note_label.visible = not view["is_player"]
	foreign_note_label.text = "Exército estrangeiro: você não pode dar ordens a ele."

	# Movimento primeiro: é a ação principal e precisa ficar visível sem rolar o painel.
	if view["is_player"]:
		_add_heading("Mover para (1 província por turno)")
		for destination in view["destinations"]:
			move_buttons[destination["id"]] = _add_button("%s (%s)" % [destination["name"], destination["link"]],
				destination["reason"], controller.move_army.bind(view["id"], destination["id"]))

	_add_heading("Composição")
	for unit in view["units"]:
		_add_note("%s #%d — %s homens · moral %d · exp. %d" % [
			unit["name"], unit["id"], ProvincePanel.format_int(unit["strength"]), unit["morale"], unit["experience"]],
			UiStyle.TEXT)
		if view["is_player"]:
			detach_buttons[unit["id"]] = _add_button("Separar para a guarnição", unit["detach_reason"],
				controller.detach_unit.bind(view["id"], unit["id"]))
	if not view["is_player"]:
		return

	_add_heading("General")
	if view["general"].is_empty():
		for candidate in view["free_generals"]:
			general_buttons[candidate["id"]] = _add_button("Atribuir %s (comando %d)" % [candidate["name"], candidate["command"]],
				candidate["reason"], controller.assign_general.bind(view["id"], candidate["id"]))
		if view["free_generals"].is_empty():
			_add_note("Nenhum general livre.")
	else:
		unassign_button = _add_button("Remover %s do comando" % view["general"]["name"], "",
			controller.unassign_general.bind(view["id"]))

	if not view["mergeable_armies"].is_empty():
		_add_heading("Mesclar com outro exército")
		for other in view["mergeable_armies"]:
			merge_buttons[other["id"]] = _add_button("Mesclar %s (%d unidades)" % [other["name"], other["unit_count"]],
				other["reason"], controller.merge_armies.bind(view["id"], other["id"]))

	if not view["joinable_units"].is_empty():
		_add_heading("Incorporar unidade da guarnição")
		for unit in view["joinable_units"]:
			join_buttons[unit["id"]] = _add_button("%s #%d (%s homens)" % [unit["name"], unit["id"], ProvincePanel.format_int(unit["strength"])],
				unit["reason"], controller.add_unit_to_army.bind(view["id"], unit["id"]))


# --- Construção dos controles ------------------------------------------------

## Botão de ação; com `reason` preenchido fica desabilitado e o motivo aparece logo abaixo.
func _add_button(text: String, reason: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason
	button.pressed.connect(on_pressed)
	_sections.add_child(button)
	if not reason.is_empty():
		_add_note(reason, UiStyle.ERROR)
	return button


func _add_heading(text: String) -> void:
	var label := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	label.text = text.to_upper()
	_sections.add_child(label)


func _add_note(text: String, color: Color = UiStyle.TEXT_DIM) -> void:
	var label := UiStyle.make_label(13, color, true)
	label.text = text
	_sections.add_child(label)


func _clear_sections() -> void:
	move_buttons = {}
	detach_buttons = {}
	join_buttons = {}
	merge_buttons = {}
	general_buttons = {}
	unassign_button = null
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()  # adiado: o botão pode estar emitindo "pressed" neste momento
