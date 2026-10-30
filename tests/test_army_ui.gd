extends "res://tests/test_case.gd"
## Marcadores, seleção de exércitos e painel de exército na interface de campanha.

const MAIN_SCENE := "res://scenes/main.tscn"
const INFANTRY := "unit_line_inf"


func _main() -> Control:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)  # dispara _ready
	main.screen.map_view.size = Vector2(950, 541)  # tamanho real da área do mapa em 1280x720
	return main


func _click_at(view: Control, button: MouseButton, screen_point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = screen_point
	view._gui_input(event)


func _add_fra_army(main: Control, province_id: String = "prov_paris") -> int:
	var army_id: int = main.state.create_army("Exército %d" % main.state.next_army_id, "fra", province_id)
	main.state.armies[army_id]["units"].append(main.state.add_unit(main.registry, INFANTRY, "fra", province_id))
	return army_id


func _recruit_army_in_paris(main: Control) -> int:
	main.controller.recruit("prov_paris", INFANTRY)
	main.controller.end_turn()
	main.controller.end_turn()
	return main.state.armies_in("prov_paris", "fra")[0]


func test_markers_show_armies_on_the_map() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	assert_eq(view.marker_rects("prov_bohemia").size(), 1, "exército da Boêmia")
	assert_eq(view.marker_rects("prov_bavaria").size(), 1, "exército da Baviera")
	assert_eq(view.marker_rects("prov_paris").size(), 0, "França sem exército no início")
	var rect: Rect2 = view.marker_rects("prov_vienna")[0]["rect"]
	assert_true(Rect2(Vector2.ZERO, view.size).encloses(rect), "marcador dentro da área do mapa")
	var polygon: PackedVector2Array = main.controller.province_map.polygons["prov_vienna"]
	assert_true(Geometry2D.is_point_in_polygon(view.screen_to_map(rect.get_center()), polygon), "marcador dentro da própria província")
	main.free()


func test_click_on_foreign_marker_selects_army_and_shows_read_only_panel() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	var marker: Dictionary = view.marker_rects("prov_bohemia")[0]
	_click_at(view, MOUSE_BUTTON_LEFT, marker["rect"].get_center())
	var army_id: int = main.state.armies_in("prov_bohemia")[0]
	assert_eq(main.controller.selected_army_id, army_id, "exército selecionado")
	assert_eq(main.controller.selected_province_id, "prov_bohemia", "a província dele também")
	var panel = main.screen.army_panel
	assert_true(panel.visible, "painel de exército visível")
	assert_eq(panel.title_label.text, "Exército da Boêmia", "nome")
	assert_true("estrangeiro" in panel.owner_label.text and "Áustria" in panel.owner_label.text, panel.owner_label.text)
	assert_true("Unidades: 2 de 4" in panel.info_label.text and "1.000 homens" in panel.info_label.text, panel.info_label.text)
	assert_true("Boêmia" in panel.info_label.text, "província atual")
	assert_true("Arquiduque Carlos" in panel.general_label.text, panel.general_label.text)
	assert_true(panel.foreign_note_label.visible, "aviso de exército estrangeiro")
	assert_true(panel.move_buttons.is_empty() and panel.detach_buttons.is_empty(), "sem ordens para exército estrangeiro")
	assert_eq(main.screen.province_panel.title_label.text, "Boêmia", "painel da província continua funcionando")
	main.free()


func test_own_army_move_flow_through_the_interface() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	var army_id := _recruit_army_in_paris(main)
	var marker: Dictionary = view.marker_rects("prov_paris")[0]
	_click_at(view, MOUSE_BUTTON_LEFT, marker["rect"].get_center())
	var panel = main.screen.army_panel
	assert_eq(main.controller.selected_army_id, army_id, "selecionou o exército próprio")
	assert_true("Seu exército" in panel.owner_label.text, panel.owner_label.text)
	assert_true(not panel.foreign_note_label.visible, "sem aviso de estrangeiro")
	assert_true("Pode se mover" in panel.status_label.text, panel.status_label.text)
	assert_true(panel.move_buttons.has("prov_strasbourg") and not panel.move_buttons["prov_strasbourg"].disabled, "Alsácia liberada")
	assert_true(panel.move_buttons["prov_franconia"].disabled, "Francônia (outro país) bloqueada")
	assert_true("Sem acesso" in panel.move_buttons["prov_franconia"].tooltip_text, "motivo no botão")
	assert_eq(main.controller.army_destination_ids(), ["prov_strasbourg"] as Array[String], "destinos destacados no mapa")

	panel.move_buttons["prov_strasbourg"].pressed.emit()
	assert_eq(main.state.armies[army_id]["province"], "prov_strasbourg", "estado atualizado")
	assert_eq(view.marker_rects("prov_paris").size(), 0, "marcador saiu de Paris")
	assert_eq(view.marker_rects("prov_strasbourg").size(), 1, "marcador apareceu em Alsácia")
	assert_eq(main.controller.selected_province_id, "prov_strasbourg", "seleção acompanha o exército")
	assert_eq(main.controller.selected_army_id, army_id, "exército continua selecionado")
	assert_eq(main.screen.province_panel.title_label.text, "Alsácia", "painel da província atualizado")
	assert_true("moveu-se" in main.screen.status_bar.message_label.text, main.screen.status_bar.message_label.text)
	assert_true("Já se moveu" in panel.status_label.text, panel.status_label.text)
	assert_true(panel.move_buttons["prov_paris"].disabled and "já se moveu" in panel.move_buttons["prov_paris"].tooltip_text, "movimento já usado")

	main.screen.top_bar.end_turn_button.pressed.emit()
	assert_true("Pode se mover" in panel.status_label.text, "movimento reiniciado no novo turno: " + panel.status_label.text)
	assert_true(not panel.move_buttons["prov_paris"].disabled, "pode voltar")
	main.free()


func test_invalid_order_shows_a_clear_message() -> void:
	var main := _main()
	_recruit_army_in_paris(main)
	var army_id: int = main.state.armies_in("prov_paris", "fra")[0]
	var before: Dictionary = main.state.to_dict()
	var result: Dictionary = main.controller.move_army(army_id, "prov_hungary")
	assert_true(not result["ok"], "rejeitada")
	assert_true("Destino inválido" in main.screen.status_bar.message_label.text, main.screen.status_bar.message_label.text)
	assert_eq(main.state.to_dict(), before, "estado intacto")
	var foreign: Dictionary = main.controller.move_army(main.state.armies_in("prov_bohemia")[0], "prov_moravia")
	assert_true(not foreign["ok"] and "outro país" in main.screen.status_bar.message_label.text, "exército estrangeiro")
	main.free()


func test_several_armies_in_one_province_are_all_selectable() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	var ids: Array[int] = [_add_fra_army(main), _add_fra_army(main), _add_fra_army(main)]
	var markers: Array[Dictionary] = view.marker_rects("prov_paris")
	assert_eq(markers.size(), 3, "um marcador por exército")
	for i in markers.size():
		for j in range(i + 1, markers.size()):
			assert_true(not markers[i]["rect"].intersects(markers[j]["rect"]), "marcadores %d e %d não se sobrepõem" % [i, j])
	for marker in markers:
		_click_at(view, MOUSE_BUTTON_LEFT, marker["rect"].get_center())
		assert_eq(main.controller.selected_army_id, marker["army_id"], "clique seleciona o exército do marcador")
		assert_true(marker["army_id"] in ids, "exército conhecido")
	main.free()


func test_overflow_marker_selects_the_province_and_panel_lists_all_armies() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	var made: Array[int] = []
	for i in 8:
		made.append(_add_fra_army(main, "prov_strasbourg"))
	var markers: Array[Dictionary] = view.marker_rects("prov_strasbourg")
	assert_eq(markers.size(), view.MAX_MARKERS, "limite de marcadores")
	var last: Dictionary = markers[-1]
	assert_true(last["overflow"] and last["army_id"] == 0 and last["hidden_count"] == 8 - (view.MAX_MARKERS - 1), "último é '+N'")
	main.controller.select_army(made[0])
	_click_at(view, MOUSE_BUTTON_LEFT, last["rect"].get_center())
	assert_eq(main.controller.selected_province_id, "prov_strasbourg", "o '+N' seleciona a província")
	assert_eq(main.screen.province_panel.army_buttons.size(), 8, "o painel lista todos os exércitos")
	var pick: int = made[7]  # um exército que não tem marcador próprio
	main.screen.province_panel.army_buttons[pick].pressed.emit()
	assert_eq(main.controller.selected_army_id, pick, "seleção pela lista do painel")
	main.free()


func test_markers_fit_inside_the_narrowest_province() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	for i in 6:
		_add_fra_army(main, "prov_hungary")  # a menor província; território da Áustria, mas serve de layout
	var polygon: PackedVector2Array = main.controller.province_map.polygons["prov_hungary"]
	for marker in view.marker_rects("prov_hungary"):
		var rect: Rect2 = marker["rect"]
		for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			assert_true(Geometry2D.is_point_in_polygon(view.screen_to_map(corner), polygon), "canto %s dentro de Hungria" % corner)
	main.free()


func test_province_click_keeps_army_only_when_it_is_there() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	var army_id := _add_fra_army(main)
	main.controller.select_army(army_id)
	_click_at(view, MOUSE_BUTTON_LEFT, view.map_to_screen(main.controller.province_map.label_points["prov_paris"]) + Vector2(0, -40))
	assert_eq(main.controller.selected_province_id, "prov_paris", "clique na própria província")
	assert_eq(main.controller.selected_army_id, army_id, "exército continua selecionado")
	_click_at(view, MOUSE_BUTTON_LEFT, view.map_to_screen(main.controller.province_map.label_points["prov_strasbourg"]) + Vector2(0, -40))
	assert_eq(main.controller.selected_province_id, "prov_strasbourg", "outra província selecionada")
	assert_eq(main.controller.selected_army_id, 0, "o exército deixa de estar selecionado")
	assert_true(not main.screen.army_panel.visible, "painel de exército oculto")
	main.free()


func test_escape_and_right_click_clear_army_selection_too() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	var army_id := _add_fra_army(main)
	main.controller.select_army(army_id)
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	main.screen._unhandled_input(key)
	assert_eq(main.controller.selected_army_id, 0, "Esc limpa o exército")
	assert_eq(main.controller.selected_province_id, "", "e a província")
	main.controller.select_army(army_id)
	_click_at(view, MOUSE_BUTTON_RIGHT, Vector2(400, 300))
	assert_eq(main.controller.selected_army_id, 0, "botão direito limpa o exército")
	main.controller.select_army(army_id)
	main.screen.army_panel.deselect_button.pressed.emit()
	assert_eq(main.controller.selected_army_id, 0, "botão desmarca o exército")
	assert_eq(main.controller.selected_province_id, "prov_paris", "a província continua selecionada")
	main.free()


func test_province_panel_lists_armies_and_garrison_actions() -> void:
	var main := _main()
	var army_id := _add_fra_army(main)
	var garrison_unit: int = main.state.add_unit(main.registry, INFANTRY, "fra", "prov_paris")
	main.controller.select_province("prov_paris")
	var panel = main.screen.province_panel
	assert_true(panel.army_buttons.has(army_id), "exército listado")
	assert_true(panel.form_army_buttons.has(garrison_unit), "unidade de guarnição com botão de formar exército")
	panel.form_army_buttons[garrison_unit].pressed.emit()
	assert_eq(main.state.army_of_unit(garrison_unit) != 0, true, "novo exército formado pela interface")
	assert_true(main.screen.army_panel.visible, "o novo exército fica selecionado")
	main.controller.select_province("prov_bohemia")
	assert_true(panel.army_buttons.size() == 1 and panel.form_army_buttons.is_empty(), "província estrangeira: só a lista, sem organização")
	main.free()


func test_army_panel_organization_and_general_buttons() -> void:
	var main := _main()
	var army_id := _add_fra_army(main)
	var garrison_unit: int = main.state.add_unit(main.registry, INFANTRY, "fra", "prov_paris")
	main.controller.select_army(army_id)
	var panel = main.screen.army_panel
	assert_true(panel.join_buttons.has(garrison_unit), "unidade da guarnição pode ser incorporada")
	panel.join_buttons[garrison_unit].pressed.emit()
	assert_eq(main.state.armies[army_id]["units"].size(), 2, "incorporada")
	assert_true("Unidades: 2 de 4" in panel.info_label.text and "1.000 homens" in panel.info_label.text, panel.info_label.text)

	assert_true(panel.general_buttons.has("gen_davout"), "general livre oferecido")
	assert_true(not panel.general_buttons.has("gen_charles"), "general estrangeiro não é oferecido")
	panel.general_buttons["gen_davout"].pressed.emit()
	assert_true("Louis-Nicolas Davout" in panel.general_label.text, panel.general_label.text)
	assert_true(panel.unassign_button != null and panel.general_buttons.is_empty(), "agora só há 'Remover'")

	var unit_id: int = main.state.armies[army_id]["units"][0]
	panel.detach_buttons[unit_id].pressed.emit()
	assert_eq(main.state.armies[army_id]["units"].size(), 1, "unidade separada")
	assert_true("Unidades: 1 de 4" in panel.info_label.text, "painel atualizado")
	main.free()


func test_full_army_blocks_joining_with_visible_reason() -> void:
	var main := _main()
	var army_id := _add_fra_army(main)
	for i in 3:
		main.state.armies[army_id]["units"].append(main.state.add_unit(main.registry, INFANTRY, "fra", "prov_paris"))
	var garrison_unit: int = main.state.add_unit(main.registry, INFANTRY, "fra", "prov_paris")
	main.controller.select_army(army_id)
	var panel = main.screen.army_panel
	assert_true(panel.join_buttons[garrison_unit].disabled, "exército cheio")
	assert_true("Limite de unidades" in panel.join_buttons[garrison_unit].tooltip_text, panel.join_buttons[garrison_unit].tooltip_text)
	main.controller.add_unit_to_army(army_id, garrison_unit)
	assert_true("Limite de unidades" in main.screen.status_bar.message_label.text, "mensagem de limite excedido")
	assert_eq(main.state.armies[army_id]["units"].size(), 4, "nada mudou")
	main.free()


func test_encounter_is_visible_in_the_interface() -> void:
	var main := _main()
	var mine := _add_fra_army(main)
	declare_war_between({"registry": main.registry, "state": main.state}, "fra", "aus")
	var intruder: int = main.state.create_army("Intruso", "aus", "prov_strasbourg")
	main.state.armies[intruder]["units"].append(main.state.add_unit(main.registry, INFANTRY, "aus", "prov_strasbourg"))
	main.controller.select_army(mine)
	main.screen.army_panel.move_buttons["prov_strasbourg"].pressed.emit()
	assert_true("Encontro pendente" in main.screen.status_bar.message_label.text, main.screen.status_bar.message_label.text)
	assert_true("Encontro pendente" in main.screen.army_panel.status_label.text, main.screen.army_panel.status_label.text)
	assert_true(main.screen.province_panel.encounter_label.visible and "Áustria" in main.screen.province_panel.encounter_label.text, "alerta no painel da província")
	assert_true(main.screen.army_panel.move_buttons["prov_paris"].disabled, "exército parado pelo encontro")
	main.free()


func test_layout_with_both_side_panels_fits_the_window() -> void:
	var main := _main()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.size = Vector2i(1280, 720)
	main.controller.select_army(main.state.armies_in("prov_bohemia")[0])
	await tree.process_frame
	await tree.process_frame
	var screen = main.screen
	assert_true(screen.army_panel.visible, "painel de exército visível")
	assert_eq(screen.army_panel.size.x, 330.0, "largura do painel de exército")
	assert_true(screen.province_panel.size.y >= 150 and screen.army_panel.size.y >= 150,
		"alturas utilizáveis: %s / %s" % [screen.province_panel.size, screen.army_panel.size])
	assert_true(screen.map_view.size.x >= 900, "mapa mantém a largura: %s" % screen.map_view.size)
	assert_true(screen.province_panel.size.y + screen.army_panel.size.y <= 720.0, "painéis cabem na janela")
	main.free()
