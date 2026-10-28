extends Control
## Tela de campanha: barra superior, mapa + barra de mensagens e painel lateral. Esc limpa a seleção.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const MapView := preload("res://src/ui/map_view.gd")
const ProvincePanel := preload("res://src/ui/province_panel.gd")
const StatusBar := preload("res://src/ui/status_bar.gd")
const TopBar := preload("res://src/ui/top_bar.gd")

var controller: CampaignController
var top_bar: PanelContainer
var map_view: Control
var status_bar: PanelContainer
var province_panel: PanelContainer


func setup(p_controller: CampaignController) -> void:
	controller = p_controller
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	top_bar = TopBar.new()
	top_bar.bind(controller)
	top_bar.end_turn_requested.connect(controller.end_turn)
	root.add_child(top_bar)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	body.add_child(left)

	map_view = MapView.new()
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.bind(controller)
	left.add_child(map_view)

	status_bar = StatusBar.new()
	status_bar.bind(controller)
	left.add_child(status_bar)

	province_panel = ProvincePanel.new()
	province_panel.bind(controller)
	province_panel.clear_requested.connect(controller.clear_selection)
	body.add_child(province_panel)


func _unhandled_input(event: InputEvent) -> void:
	if controller != null and event.is_action_pressed("ui_cancel"):
		controller.clear_selection()
		if is_inside_tree():
			get_viewport().set_input_as_handled()
