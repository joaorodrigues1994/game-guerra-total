extends PanelContainer
## Painel lateral com os detalhes da província selecionada.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

signal clear_requested

var controller: CampaignController

var empty_label: Label
var title_label: Label
var owner_label: Label
var capital_label: Label
var info_label: Label
var production_label: Label
var buildings_label: Label
var connections_label: Label
var clear_button: Button

var _owner_swatch: ColorRect
var _content: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(320, 0)
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
	production_label = _add_section("Produção")
	buildings_label = _add_section("Construções")
	connections_label = _add_section("Conexões")

	clear_button = Button.new()
	clear_button.text = "Limpar seleção"
	clear_button.pressed.connect(func() -> void: clear_requested.emit())
	root.add_child(clear_button)

	show_province({})


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(controller.selected_province_id)


func _on_selection_changed(province_id: String) -> void:
	show_province(controller.province_view(province_id))


## Preenche o painel com uma visão de província (ver CampaignController.province_view); vazio = sem seleção.
func show_province(view: Dictionary) -> void:
	var has_view := not view.is_empty()
	_content.visible = has_view
	empty_label.visible = not has_view
	clear_button.disabled = not has_view
	if not has_view:
		return

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
	info_label.text = "\n".join(info)

	var production := PackedStringArray()
	for entry in view["production"]:
		production.append("%s: %d" % [entry["name"], entry["amount"]])
	production_label.text = "\n".join(production) if not production.is_empty() else "—"

	var buildings := PackedStringArray(view["buildings"])
	buildings_label.text = "\n".join(buildings) if not buildings.is_empty() else "Nenhuma"

	var links := PackedStringArray()
	for neighbor in view["neighbors"]:
		links.append("%s (%s)" % [neighbor["name"], neighbor["link"]])
	connections_label.text = "\n".join(links) if not links.is_empty() else "Nenhuma"


## Inteiro com separador de milhar em português (60000 -> "60.000").
static func format_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += "."
		out += digits[i]
	return ("-" if value < 0 else "") + out


## Adiciona um título de seção e devolve o Label do conteúdo.
func _add_section(heading: String) -> Label:
	var title := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	title.text = heading.to_upper()
	_content.add_child(title)
	var body := UiStyle.make_label(15, UiStyle.TEXT, true)
	_content.add_child(body)
	return body
