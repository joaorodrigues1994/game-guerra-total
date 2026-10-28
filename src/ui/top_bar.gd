extends PanelContainer
## Barra superior: nome do jogo, nação em foco, data/turno, recursos, receitas/despesas por turno
## e o botão de encerrar turno. Só lê o estado via controlador.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvincePanel := preload("res://src/ui/province_panel.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

signal end_turn_requested

var controller: CampaignController

var title_label: Label
var nation_label: Label
var date_label: Label
var resources_label: Label
var flows_label: Label
var end_turn_button: Button

var _swatch: ColorRect


func _init() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_BOTTOM]))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)

	title_label = UiStyle.make_label(22, UiStyle.ACCENT)
	title_label.text = str(ProjectSettings.get_setting("application/config/name"))
	row.add_child(title_label)

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(18, 18)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)

	nation_label = UiStyle.make_label(16)
	nation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nation_label.clip_text = true
	row.add_child(nation_label)

	date_label = UiStyle.make_label(15)
	row.add_child(date_label)

	end_turn_button = Button.new()
	end_turn_button.text = "Encerrar turno"
	end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	row.add_child(end_turn_button)

	resources_label = UiStyle.make_label(14)
	resources_label.clip_text = true  # em janelas estreitas corta o texto em vez de estourar a barra
	column.add_child(resources_label)

	flows_label = UiStyle.make_label(13, UiStyle.TEXT_DIM)
	flows_label.clip_text = true
	column.add_child(flows_label)


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.selection_changed.connect(func(_id: String) -> void: refresh())
	controller.state_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var view := controller.country_view(controller.focus_country_id())
	if view.is_empty():
		return
	_swatch.color = view["color"]
	var prefix := "Sua nação" if view["is_player"] else "Nação selecionada"
	nation_label.text = "%s: %s" % [prefix, view["name"]]
	date_label.text = controller.date_text()

	var amounts := PackedStringArray()
	var gains := PackedStringArray()
	var costs := PackedStringArray()
	for entry in view["resources"]:
		amounts.append("%s %s" % [entry["name"], ProvincePanel.format_int(entry["amount"])])
		if entry["income"] != 0:
			gains.append("%s +%s" % [entry["name"], ProvincePanel.format_int(entry["income"])])
		if entry["upkeep"] != 0:
			costs.append("%s -%s" % [entry["name"], ProvincePanel.format_int(entry["upkeep"])])
	resources_label.text = "  ·  ".join(amounts)
	flows_label.text = "Receitas por turno: %s   |   Despesas por turno: %s" % [
		", ".join(gains) if not gains.is_empty() else "—",
		", ".join(costs) if not costs.is_empty() else "—"]
