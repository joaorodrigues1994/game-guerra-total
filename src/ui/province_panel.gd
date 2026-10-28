extends PanelContainer
## Painel lateral com os detalhes da província selecionada e as ações de construção/recrutamento.
## Mostra apenas o que o controlador entrega (province_view); não guarda dados de jogo.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

signal clear_requested

var controller: CampaignController

var empty_label: Label
var title_label: Label
var owner_label: Label
var capital_label: Label
var info_label: Label
var production_label: Label  # receita por turno da província
var buildings_label: Label
var constructions_label: Label
var recruitments_label: Label
var units_label: Label
var connections_label: Label
var actions_note_label: Label
var encounter_label: Label
## id do exército / da unidade de guarnição -> botão, reconstruídos a cada atualização.
var army_buttons: Dictionary = {}
var form_army_buttons: Dictionary = {}
var clear_button: Button
## id da construção/unidade -> botão, reconstruídos a cada atualização.
var build_buttons: Dictionary = {}
var recruit_buttons: Dictionary = {}

var _owner_swatch: ColorRect
var _content: VBoxContainer
var _actions: VBoxContainer
var _military: VBoxContainer
var _province_id: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(330, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_LEFT]))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	empty_label = UiStyle.make_label(15, UiStyle.TEXT_DIM, true)
	empty_label.text = "Nenhuma província selecionada.\nClique em uma província do mapa para ver seus detalhes."
	root.add_child(empty_label)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	title_label = UiStyle.make_label(24, UiStyle.ACCENT, true)
	_content.add_child(title_label)

	var owner_row := HBoxContainer.new()
	owner_row.add_theme_constant_override("separation", 8)
	_owner_swatch = ColorRect.new()
	_owner_swatch.custom_minimum_size = Vector2(18, 18)
	owner_row.add_child(_owner_swatch)
	owner_label = UiStyle.make_label(16)
	owner_row.add_child(owner_label)
	_content.add_child(owner_row)

	capital_label = UiStyle.make_label(14, UiStyle.ACCENT, true)
	_content.add_child(capital_label)
	encounter_label = UiStyle.make_label(14, UiStyle.ERROR, true)
	_content.add_child(encounter_label)
	info_label = UiStyle.make_label(15, UiStyle.TEXT, true)
	_content.add_child(info_label)
	# Exércitos presentes e unidades de guarnição, logo abaixo dos dados básicos.
	_military = VBoxContainer.new()
	_military.add_theme_constant_override("separation", 4)
	_content.add_child(_military)
	# Ações logo abaixo dos dados básicos, para ficarem visíveis sem rolar o painel.
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	_content.add_child(_actions)

	constructions_label = _add_section("Construções em andamento")
	recruitments_label = _add_section("Recrutamentos em andamento")
	buildings_label = _add_section("Construções concluídas")
	production_label = _add_section("Receita por turno")
	units_label = _add_section("Unidades na província")

	connections_label = _add_section("Conexões")

	clear_button = Button.new()
	clear_button.text = "Limpar seleção"
	clear_button.pressed.connect(func() -> void: clear_requested.emit())
	root.add_child(clear_button)

	show_province({})


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.selection_changed.connect(func(_id: String) -> void: _refresh())
	controller.state_changed.connect(_refresh)
	controller.army_selection_changed.connect(func(_id: int) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	show_province(controller.province_view(controller.selected_province_id))


## Preenche o painel com uma visão de província (ver CampaignController.province_view); vazio = sem seleção.
func show_province(view: Dictionary) -> void:
	var has_view := not view.is_empty()
	_content.visible = has_view
	empty_label.visible = not has_view
	clear_button.disabled = not has_view
	_clear_actions()
	_clear_military()
	if not has_view:
		_province_id = ""
		return
	_province_id = view["id"]

	title_label.text = view["name"]
	owner_label.text = "Controlada por %s" % view["owner_name"]
	_owner_swatch.color = view["owner_color"]
	capital_label.visible = not view["capital_of"].is_empty()
	capital_label.text = "★ Capital de %s" % view["capital_of"]

	var info := PackedStringArray()
	if not view["city"].is_empty():
		info.append("Cidade principal: %s" % view["city"])
	info.append("Terreno: %s" % view["terrain_name"])
	info.append("População: %s" % format_int(view["population"]))
	info.append("Valor econômico: %d" % view["economic_value"])
	info.append("Valor estratégico: %d" % view["strategic_value"])
	info.append("Guarnição: %s" % format_int(view["garrison"]))
	if view["defense_bonus"] > 0:
		info.append("Bônus defensivo: +%d" % view["defense_bonus"])
	info_label.text = "\n".join(info)
	encounter_label.visible = not view["encounters"].is_empty()
	encounter_label.text = "\n".join(PackedStringArray(view["encounters"]))

	var income := PackedStringArray()
	for entry in view["income"]:
		income.append("%s: +%s" % [entry["name"], format_int(entry["amount"])])
	production_label.text = _lines_or(income, "—")
	buildings_label.text = _lines_or(PackedStringArray(view["buildings"]), "Nenhuma")

	var constructions := PackedStringArray()
	for entry in view["constructions"]:
		constructions.append("%s — %s" % [entry["name"], _turns_text(entry["remaining"])])
	constructions_label.text = _lines_or(constructions, "Nenhuma")
	var recruitments := PackedStringArray()
	for entry in view["recruitments"]:
		recruitments.append("%s — %s" % [entry["name"], _turns_text(entry["remaining"])])
	recruitments_label.text = _lines_or(recruitments, "Nenhum")
	units_label.text = _lines_or(PackedStringArray(view["units"]), "Nenhuma")

	var links := PackedStringArray()
	for neighbor in view["neighbors"]:
		links.append("%s (%s)" % [neighbor["name"], neighbor["link"]])
	connections_label.text = _lines_or(links, "Nenhuma")

	_build_military(view)
	_build_actions(view)


## Inteiro com separador de milhar em português (60000 -> "60.000").
static func format_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += "."
		out += digits[i]
	return ("-" if value < 0 else "") + out


# --- Exércitos e guarnição ---------------------------------------------------

func _build_military(view: Dictionary) -> void:
	if not view["armies"].is_empty():
		_military_heading("Exércitos na província")
	for army in view["armies"]:
		var tag := "seu" if army["is_player"] else "estrangeiro (%s)" % army["owner_name"]
		var button := Button.new()
		button.text = "%s — %s" % [army["name"], tag]
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "Selecionar este exército"
		button.pressed.connect(controller.select_army.bind(army["id"]))
		_military.add_child(button)
		army_buttons[army["id"]] = button
		var detail := "%d unidades · %s homens%s" % [army["unit_count"], format_int(army["strength"]),
			" · encontro pendente" if army["engaged"] else ""]
		_military_note(detail)
	if not view["garrison_units"].is_empty():
		_military_heading("Guarnição (unidades fora de exércitos)")
	for unit in view["garrison_units"]:
		var button := Button.new()
		button.text = "Formar exército: %s #%d (%s homens)" % [unit["name"], unit["id"], format_int(unit["strength"])]
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not unit["reason"].is_empty()
		button.tooltip_text = unit["reason"]
		button.pressed.connect(controller.form_army.bind(view["id"], unit["id"]))
		_military.add_child(button)
		form_army_buttons[unit["id"]] = button


func _military_heading(text: String) -> void:
	var label := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	label.text = text.to_upper()
	_military.add_child(label)


func _military_note(text: String) -> void:
	var label := UiStyle.make_label(13, UiStyle.TEXT_DIM, true)
	label.text = text
	_military.add_child(label)


func _clear_military() -> void:
	army_buttons = {}
	form_army_buttons = {}
	for child in _military.get_children():
		_military.remove_child(child)
		child.queue_free()


# --- Ações ------------------------------------------------------------------

func _build_actions(view: Dictionary) -> void:
	if not view["owned_by_player"]:
		actions_note_label = _action_note("Província de outro país: construção e recrutamento indisponíveis.")
		return
	_action_heading("Construir")
	for option in view["build_options"]:
		var detail := "Custo: %s
Efeito: %s" % [option["cost"], option["effects"]]
		build_buttons[option["id"]] = _action_button(
			"%s — %s" % [option["name"], _turns_text(option["turns"])], detail, option,
			controller.build.bind(view["id"], option["id"]))
	if view["build_options"].is_empty():
		_action_note("Nada mais a construir.")
	_action_heading("Recrutar")
	for option in view["recruit_options"]:
		var detail := "Custo: %s
Manutenção por turno: %s" % [option["cost"], option["upkeep"]]
		recruit_buttons[option["id"]] = _action_button(
			"%s (%d homens) — %s" % [option["name"], option["strength"], _turns_text(option["turns"])], detail, option,
			controller.recruit.bind(view["id"], option["id"]))


func _action_button(text: String, detail: String, option: Dictionary, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not option["available"]
	button.tooltip_text = detail if option["available"] else option["reason"]
	button.pressed.connect(on_pressed)
	_actions.add_child(button)
	_action_note(detail)
	if not option["available"]:
		_action_note(option["reason"], UiStyle.ERROR)
	return button


func _action_heading(text: String) -> void:
	var label := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	label.text = text.to_upper()
	_actions.add_child(label)


func _action_note(text: String, color: Color = UiStyle.TEXT_DIM) -> Label:
	var label := UiStyle.make_label(13, color, true)
	label.text = text
	_actions.add_child(label)
	return label


func _clear_actions() -> void:
	build_buttons = {}
	recruit_buttons = {}
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()  # adiado: o botão pode estar emitindo "pressed" neste momento


# --- Auxiliares -------------------------------------------------------------

static func _turns_text(turns: int) -> String:
	return "1 turno" if turns == 1 else "%d turnos" % turns


static func _lines_or(lines: PackedStringArray, fallback: String) -> String:
	return "\n".join(lines) if not lines.is_empty() else fallback


## Adiciona um título de seção e devolve o Label do conteúdo.
func _add_section(heading: String) -> Label:
	var title := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	title.text = heading.to_upper()
	_content.add_child(title)
	var body := UiStyle.make_label(15, UiStyle.TEXT, true)
	_content.add_child(body)
	return body
