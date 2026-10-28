extends "res://tests/test_case.gd"
## Cena principal e interface de campanha (sem renderização: simula eventos diretamente).

const MAIN_SCENE := "res://scenes/main.tscn"
const ProvincePanel := preload("res://src/ui/province_panel.gd")


func _main() -> Control:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)  # dispara _ready
	return main


func _click(view: Control, button: MouseButton, map_point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = view.map_to_screen(map_point)
	view._gui_input(event)


func test_main_scene_builds_campaign_screen() -> void:
	var main := _main()
	assert_true(main.screen != null, "tela de campanha criada")
	assert_true(main.controller != null, "controlador criado")
	assert_eq(main.state.player_country_id, "fra", "jogador padrão")
	assert_true(main.screen.map_view != null and main.screen.province_panel != null and main.screen.top_bar != null, "componentes")
	main.free()


func test_initial_ui_shows_player_nation_and_empty_panel() -> void:
	var main := _main()
	var screen = main.screen
	assert_eq(screen.top_bar.title_label.text, "Estratégia Napoleônica", "título")
	assert_eq(screen.top_bar.nation_label.text, "Sua nação: França", "nação")
	assert_true("Ouro 500" in screen.top_bar.resources_label.text, "recursos: " + screen.top_bar.resources_label.text)
	assert_eq(screen.top_bar.date_label.text, "Janeiro de 1805 · Turno 1", "data")
	assert_true(screen.province_panel.empty_label.visible, "mensagem de painel vazio")
	assert_true(screen.province_panel.clear_button.disabled, "limpar desabilitado")
	main.free()


func test_click_selects_province_and_updates_panel() -> void:
	var main := _main()
	var screen = main.screen
	var view: Control = screen.map_view
	view.size = Vector2(900, 600)
	var panel = screen.province_panel

	_click(view, MOUSE_BUTTON_LEFT, main.controller.province_map.label_points["prov_vienna"])
	assert_eq(main.controller.selected_province_id, "prov_vienna", "seleção por clique")
	assert_eq(panel.title_label.text, "Baixa Áustria", "título do painel")
	assert_eq(panel.owner_label.text, "Controlada por Áustria", "país")
	assert_true(panel.capital_label.visible and "Áustria" in panel.capital_label.text, "capital")
	assert_true("Colinas" in panel.info_label.text, "terreno")
	assert_true("45.000" in panel.info_label.text, "população formatada")
	assert_true("Quartel" in panel.buildings_label.text, "construções")
	assert_eq(screen.top_bar.nation_label.text, "Nação selecionada: Áustria", "barra superior")

	_click(view, MOUSE_BUTTON_LEFT, main.controller.province_map.label_points["prov_strasbourg"])
	assert_eq(panel.title_label.text, "Alsácia", "painel atualizado")
	assert_true(not panel.capital_label.visible, "Alsácia não é capital")
	assert_eq(screen.top_bar.nation_label.text, "Sua nação: França", "província do jogador")
	main.free()


func test_click_on_sea_and_right_click_clear_selection() -> void:
	var main := _main()
	var screen = main.screen
	var view: Control = screen.map_view
	view.size = Vector2(900, 600)

	_click(view, MOUSE_BUTTON_LEFT, main.controller.province_map.label_points["prov_paris"])
	_click(view, MOUSE_BUTTON_LEFT, Vector2(-40, -40))
	assert_eq(main.controller.selected_province_id, "", "clique fora limpa")
	assert_true(screen.province_panel.empty_label.visible, "painel vazio")

	_click(view, MOUSE_BUTTON_LEFT, main.controller.province_map.label_points["prov_paris"])
	_click(view, MOUSE_BUTTON_RIGHT, Vector2(500, 300))
	assert_eq(main.controller.selected_province_id, "", "botão direito limpa")
	main.free()


func test_escape_and_button_clear_selection() -> void:
	var main := _main()
	var screen = main.screen
	main.controller.select_province("prov_paris")

	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	screen._unhandled_input(key)
	assert_eq(main.controller.selected_province_id, "", "Esc limpa")

	main.controller.select_province("prov_paris")
	screen.province_panel.clear_button.pressed.emit()
	assert_eq(main.controller.selected_province_id, "", "botão limpa")
	main.free()


func test_map_transform_roundtrip_and_fit() -> void:
	var main := _main()
	var view: Control = main.screen.map_view
	for window in [Vector2(900, 600), Vector2(640, 600), Vector2(1280, 668)]:
		view.size = window
		var p := Vector2(333, 217)
		assert_true(view.screen_to_map(view.map_to_screen(p)).is_equal_approx(p), "ida e volta em %s" % window)
		var rect := Rect2(view.map_to_screen(Vector2.ZERO), main.controller.province_map.size * view.map_scale())
		assert_true(Rect2(Vector2.ZERO, window).encloses(rect), "mapa cabe em %s" % window)
	main.free()


func test_layout_fills_window_with_usable_map_area() -> void:
	var main := _main()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.size = Vector2i(1280, 720)
	await tree.process_frame
	await tree.process_frame
	var screen = main.screen
	assert_eq(screen.size, Vector2(1280, 720), "tela ocupa a janela")
	assert_true(screen.map_view.size.x >= 900 and screen.map_view.size.y >= 600,
		"área do mapa utilizável: %s" % screen.map_view.size)
	assert_true(screen.province_panel.size.x >= 320, "painel lateral: %s" % screen.province_panel.size)
	assert_eq(screen.top_bar.size.x, 1280.0, "barra superior não estoura a janela")
	assert_true(screen.top_bar.get_combined_minimum_size().x <= 1280.0, "largura mínima da barra superior")
	main.free()


func test_format_int_uses_dot_separator() -> void:
	assert_eq(ProvincePanel.format_int(0), "0", "zero")
	assert_eq(ProvincePanel.format_int(950), "950", "centenas")
	assert_eq(ProvincePanel.format_int(60000), "60.000", "milhar")
	assert_eq(ProvincePanel.format_int(1234567), "1.234.567", "milhão")
