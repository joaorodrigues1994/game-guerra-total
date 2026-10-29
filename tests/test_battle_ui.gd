extends "res://tests/battle_case.gd"
## Interface da batalha: cena independente, mouse -> hexágono, painéis, registro, resultado e integração com a campanha.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const Turns := preload("res://src/battle/battle_turns.gd")


func _battle() -> Control:
	var scene: Control = load(BATTLE_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(scene)  # dispara _ready
	scene.screen.map_view.size = Vector2(950, 515)  # tamanho real da área do mapa em 1280x720
	return scene


func _click(scene: Control, button: MouseButton, screen_point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = screen_point
	scene.screen.map_view._gui_input(event)


func _click_hex(scene: Control, col: int, row: int, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_click(scene, button, scene.screen.map_view.hex_to_screen(hx(col, row)))


func test_standalone_scene_builds_the_battle_screen() -> void:
	var scene := _battle()
	assert_true(scene.screen != null and scene.controller != null, "tela e controlador criados")
	var screen = scene.screen
	assert_true(screen.map_view != null and screen.unit_panel != null and screen.log_panel != null and screen.result_panel != null, "componentes")
	assert_true("Turno 1" in screen.turn_label.text and "Jogador (França)" in screen.turn_label.text, screen.turn_label.text)
	assert_true(not screen.back_button.visible, "cena independente: sem 'Voltar'")
	assert_true(not screen.end_turn_button.disabled, "jogador pode encerrar o turno")
	assert_true(not screen.result_panel.visible, "sem resultado no início")
	scene.free()


func test_hex_layout_fits_and_roundtrips_for_every_hex() -> void:
	var scene := _battle()
	var view: Control = scene.screen.map_view
	for window in [Vector2(950, 515), Vector2(640, 480), Vector2(1100, 600)]:
		view.size = window
		var area := Rect2(Vector2.ZERO, window)
		for hex in scene.controller.state.map.all_hexes():
			assert_eq(view.screen_to_hex(view.hex_to_screen(hex)), hex, "ida e volta de %s em %s" % [hex, window])
			for corner in Hex.corners(view.hex_to_screen(hex), view.hex_size()):
				assert_true(area.grow(0.5).has_point(corner), "o mapa inteiro cabe em %s" % window)
	view.size = Vector2(950, 515)
	assert_true(view.hex_size() >= 25.0, "hexágonos legíveis (raio %s)" % view.hex_size())
	assert_eq(view.screen_to_hex(Vector2(2, 2)), BattleController.NO_HEX, "clique fora do mapa não resolve hexágono")
	scene.free()


func test_click_selects_the_unit_and_fills_the_panels() -> void:
	var scene := _battle()
	var screen = scene.screen
	_click_hex(scene, 3, 3)
	assert_eq(scene.controller.selected_unit_id, scene.controller.state.unit_at(hx(3, 3)), "unidade do hexágono clicado")
	var panel = screen.unit_panel
	assert_eq(panel.unit_title_label.text, "1º Batalhão de Linha", "nome")
	assert_true("Infantaria" in panel.unit_side_label.text and "Jogador (França)" in panel.unit_side_label.text, panel.unit_side_label.text)
	assert_eq(panel.strength_label.text, "Efetivo: 500 / 500", "efetivo")
	assert_eq(panel.strength_bar.value, 500.0, "barra de efetivo")
	assert_true("Ataque: 6" in panel.stats_label.text and "Defesa: 6" in panel.stats_label.text, panel.stats_label.text)
	assert_true("3 disponível de 3" in panel.movement_label.text, panel.movement_label.text)
	assert_true("1 (corpo a corpo)" in panel.range_label.text, panel.range_label.text)
	assert_true("100 / 100" in panel.morale_label.text and "Firme" in panel.morale_label.text, panel.morale_label.text)
	assert_true("coluna 3, linha 3" in panel.hex_label.text and "Planície" in panel.hex_label.text and "1º Batalhão de Linha" in panel.hex_label.text, panel.hex_label.text)
	scene.free()


func test_enemy_unit_can_be_inspected_but_not_commanded() -> void:
	var scene := _battle()
	_click_hex(scene, 8, 3)
	var panel = scene.screen.unit_panel
	assert_eq(panel.unit_title_label.text, "1º Regimento Austríaco", "inimigo consultado")
	assert_true("somente consulta" in panel.unit_side_label.text, panel.unit_side_label.text)
	assert_eq(scene.controller.reachable_hexes(), {}, "sem destinos para o inimigo")
	_click_hex(scene, 7, 3)  # hexágono livre: nada deve se mover
	assert_eq(scene.controller.state.unit_at(hx(8, 3)), scene.controller.selected_unit_id, "o inimigo não se moveu")
	scene.free()


func test_terrain_info_for_forest_hills_and_water() -> void:
	var scene := _battle()
	var panel = scene.screen.unit_panel
	_click_hex(scene, 0, 0)
	assert_true("Floresta" in panel.hex_label.text and "Custo de movimento: 2" in panel.hex_label.text and "+30%" in panel.hex_label.text, panel.hex_label.text)
	_click_hex(scene, 10, 0)
	assert_true("Colina" in panel.hex_label.text and "+20%" in panel.hex_label.text, panel.hex_label.text)
	_click_hex(scene, 6, 0)
	assert_true("Água" in panel.hex_label.text and "Intransponível" in panel.hex_label.text, panel.hex_label.text)
	scene.free()


func test_mouse_move_and_attack_flow_with_messages_and_log() -> void:
	var scene := _battle()
	var screen = scene.screen
	var state = scene.controller.state
	_click_hex(scene, 3, 3)
	_click_hex(scene, 6, 0)  # água, com a unidade ainda sem se mover
	assert_true("intransponível" in screen.log_panel.message_label.text.to_lower(), screen.log_panel.message_label.text)
	assert_eq(state.unit_at(hx(3, 3)), scene.controller.selected_unit_id, "a unidade não saiu do lugar")
	_click_hex(scene, 8, 0)  # além do alcance
	assert_true("Fora do alcance" in screen.log_panel.message_label.text, screen.log_panel.message_label.text)
	_click_hex(scene, 5, 3)  # destino válido
	assert_eq(state.unit_at(hx(5, 3)), scene.controller.selected_unit_id, "a unidade se moveu")
	assert_true("move-se" in screen.log_panel.log_label.text, "ação registrada: " + screen.log_panel.log_label.text)
	_click_hex(scene, 5, 4)
	assert_true("já se moveu" in screen.log_panel.message_label.text, screen.log_panel.message_label.text)
	# Trazer um inimigo ao lado e atacar pelo mouse.
	var enemy: int = state.unit_at(hx(8, 3))
	state.units[enemy]["pos"] = hx(6, 3)
	_click_hex(scene, 5, 3)
	assert_eq(scene.controller.attack_target_ids(), [enemy] as Array[int], "alvo destacado")
	_click_hex(scene, 6, 3)
	assert_true("ataca" in screen.log_panel.log_label.text and "baixas" in screen.log_panel.log_label.text, screen.log_panel.log_label.text)
	assert_true(state.units[enemy]["strength"] < 500, "o inimigo sofreu baixas")
	_click_hex(scene, 6, 3)
	assert_true("já atacou" in screen.log_panel.message_label.text, screen.log_panel.message_label.text)
	scene.free()


func test_end_turn_button_runs_the_enemy_turn() -> void:
	var scene := _battle()
	var screen = scene.screen
	screen.end_turn_button.pressed.emit()
	assert_eq(scene.controller.state.turn, 2, "turno 2")
	assert_eq(scene.controller.state.active_side, "player", "de volta ao jogador")
	assert_true("Turno 2" in screen.turn_label.text, screen.turn_label.text)
	assert_true("Turno 2" in screen.log_panel.message_label.text, screen.log_panel.message_label.text)
	assert_true(screen.log_panel.lines.size() > 3, "o registro mostra o turno inimigo")
	scene.free()


func test_right_click_and_escape_clear_the_selection() -> void:
	var scene := _battle()
	_click_hex(scene, 3, 3)
	_click_hex(scene, 3, 3, MOUSE_BUTTON_RIGHT)
	assert_eq(scene.controller.selected_unit_id, 0, "botão direito limpa")
	assert_true(scene.screen.unit_panel.empty_label.visible, "painel vazio")
	_click_hex(scene, 3, 3)
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	scene.screen._unhandled_input(key)
	assert_eq(scene.controller.selected_unit_id, 0, "Esc limpa")
	scene.free()


func test_result_panel_restart_and_state_after_finish() -> void:
	var scene := _battle()
	var screen = scene.screen
	var controller: BattleController = scene.controller
	var state = controller.state
	var keep: int = state.unit_at(hx(8, 3))
	for id in state.live_units("enemy"):
		if id != keep:
			state.units[id]["destroyed"] = true
	state.units[keep]["strength"] = 1
	state.units[keep]["pos"] = hx(4, 3)
	var attacker: int = state.unit_at(hx(3, 3))
	controller.select_unit(attacker)
	controller.click_hex(hx(4, 3))  # ataque que elimina o último inimigo
	assert_true(state.over, "batalha terminou")
	assert_true(screen.result_panel.visible, "painel de resultado visível")
	assert_eq(screen.result_panel.title_label.text, "Vitória de Jogador (França)", "título")
	assert_true("eliminação" in screen.result_panel.reason_label.text, screen.result_panel.reason_label.text)
	assert_true("1º Batalhão de Linha" in screen.result_panel.player_label.text, "sobreviventes do jogador")
	assert_true("Destruída" in screen.result_panel.enemy_label.text, "situação do inimigo")
	assert_true(screen.end_turn_button.disabled, "encerrar turno desabilitado")
	assert_true("encerrada" in screen.turn_label.text, screen.turn_label.text)
	# Nenhuma ação depois do fim.
	controller.click_hex(hx(4, 3))
	assert_true("terminou" in screen.log_panel.message_label.text, screen.log_panel.message_label.text)

	screen.result_panel.restart_button.pressed.emit()
	assert_true(not screen.result_panel.visible, "painel de resultado fechado")
	assert_true(not controller.state.over and controller.state.turn == 1, "batalha nova")
	assert_eq(controller.state.live_units().size(), 10, "10 unidades, nenhuma duplicada")
	assert_true(not screen.end_turn_button.disabled, "botão reabilitado")
	assert_true("Turno 1" in screen.turn_label.text, screen.turn_label.text)
	assert_eq(screen.log_panel.lines.size(), 0, "registro limpo")
	assert_eq(controller.state.unit_at(hx(8, 3)), keep, "unidade inimiga de volta ao lugar")
	scene.free()


func test_battle_layout_fits_1280_by_720() -> void:
	var scene := _battle()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.size = Vector2i(1280, 720)
	await tree.process_frame
	await tree.process_frame
	var screen = scene.screen
	assert_eq(screen.size, Vector2(1280, 720), "tela ocupa a janela")
	assert_true(screen.map_view.size.x >= 900 and screen.map_view.size.y >= 480, "mapa utilizável: %s" % screen.map_view.size)
	assert_eq(screen.unit_panel.size.x, 330.0, "painel lateral")
	assert_true(screen.log_panel.size.y >= 120, "registro visível: %s" % screen.log_panel.size)
	assert_true(screen.log_panel.get_combined_minimum_size().y <= 200, "registro não empurra o mapa")
	scene.free()


# --- Integração com a campanha ------------------------------------------------------------

func _campaign() -> Control:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func test_campaign_button_opens_the_battle_over_the_campaign_and_back() -> void:
	var main := _campaign()
	assert_true(main.screen.top_bar.battle_button != null, "botão na campanha")
	var turn_before: int = main.state.turn
	var gold_before: int = main.state.resources_of("fra")["gold"]
	main.screen.top_bar.battle_button.pressed.emit()
	assert_true(main.battle_screen != null, "batalha aberta")
	assert_true(not main.screen.visible, "campanha oculta")
	assert_true(main.battle_screen.back_button.visible, "botão de voltar disponível")
	assert_true(not main.open_test_battle(), "não abre duas vezes")
	var battle = main.battle_screen
	battle.map_view.size = Vector2(950, 515)
	battle.controller.click_hex(hx(3, 3))
	assert_true(battle.controller.selected_unit_id != 0, "a batalha responde")
	assert_eq(main.state.turn, turn_before, "a campanha não é afetada pela batalha")

	battle.back_button.pressed.emit()
	assert_true(main.battle_screen == null, "batalha fechada")
	assert_true(main.screen.visible, "campanha de volta")
	assert_eq(main.state.turn, turn_before, "estado da campanha preservado")
	assert_eq(main.state.resources_of("fra")["gold"], gold_before, "recursos preservados")
	main.free()


func test_battle_can_be_reopened_fresh_after_closing() -> void:
	var main := _campaign()
	main.open_test_battle()
	main.battle_screen.controller.end_turn()
	assert_eq(main.battle_screen.controller.state.turn, 2, "batalha andou")
	main.close_battle()
	main.open_test_battle()
	assert_eq(main.battle_screen.controller.state.turn, 1, "nova batalha começa do zero")
	main.free()


func test_battle_does_not_disturb_the_campaign_selection() -> void:
	var main := _campaign()
	main.controller.select_province("prov_paris")
	main.open_test_battle()
	assert_true(not main.screen.is_processing_unhandled_input(), "a campanha não escuta o Esc enquanto a batalha está aberta")
	main.battle_screen.controller.click_hex(hx(3, 3))
	main.battle_screen.controller.clear_selection()
	main.close_battle()
	assert_true(main.screen.is_processing_unhandled_input(), "volta a escutar depois")
	assert_eq(main.controller.selected_province_id, "prov_paris", "seleção da campanha preservada")
	main.free()
