extends PanelContainer
## Barra superior: nome do jogo, nação em foco (com recursos) e data da campanha.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvincePanel := preload("res://src/ui/province_panel.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

var controller: CampaignController

var title_label: Label
var nation_label: Label
var resources_label: Label
var date_label: Label

var _swatch: ColorRect


func _init() -> void:
	custom_minimum_size = Vector2(0, 52)
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_BOTTOM]))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	title_label = UiStyle.make_label(22, UiStyle.ACCENT)
	title_label.text = str(ProjectSettings.get_setting("application/config/name"))
	row.add_child(title_label)

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(18, 18)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)

	nation_label = UiStyle.make_label(16)
	row.add_child(nation_label)
	resources_label = UiStyle.make_label(13, UiStyle.TEXT_DIM)
	resources_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resources_label.clip_text = true  # em janelas estreitas corta o texto em vez de estourar a barra
	row.add_child(resources_label)

	date_label = UiStyle.make_label(15)
	row.add_child(date_label)


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.selection_changed.connect(func(_id: String) -> void: refresh())
	refresh()


func refresh() -> void:
	var view := controller.country_view(controller.focus_country_id())
	if view.is_empty():
		return
	_swatch.color = view["color"]
	var prefix := "Sua nação" if view["is_player"] else "Nação selecionada"
	nation_label.text = "%s: %s" % [prefix, view["name"]]
	var parts := PackedStringArray()
	for entry in view["resources"]:
		parts.append("%s %s" % [entry["name"], ProvincePanel.format_int(entry["amount"])])
	resources_label.text = " · ".join(parts)
	date_label.text = controller.date_text()
