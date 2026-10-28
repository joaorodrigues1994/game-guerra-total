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
var clear_button: Button
## id da construção/unidade -> botão, reconstruídos a cada atualização.
var build_buttons: Dictionary = {}
var recruit_buttons: Dictionary = {}

var _owner_swatch: ColorRect
var _content: VBoxContainer
var _actions: VBoxContainer
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
	info_label = UiStyle.make_label(15, UiStyle.TEXT, true)
	_content.add_child(info_label)
	# Ações logo abaixo dos dados básicos, para ficarem visíveis sem rolar o painel.
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	_content.add_child(_actions)

	constructions_label = _add_section("Construções em andamento")
	recruitments_label = _add_section("Recrutamentos em andamento")
	buildings_label = _add_section("Construções concluídas")
	production_label = _add_section("Receita por turno")
	units_label = _add_section("Unidades recrutadas")

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
