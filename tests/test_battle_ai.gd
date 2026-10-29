extends "res://tests/battle_case.gd"
## Rotina do inimigo, batalhas completas e controlador (turno inimigo automático).

const AI := preload("res://src/battle/battle_ai.gd")
const Combat := preload("res://src/battle/battle_combat.gd")
const Turns := preload("res://src/battle/battle_turns.gd")


func test_enemy_attacks_when_a_target_is_in_range() -> void:
	var state := new_battle()
	var mine := put(state, "infantry", "Minha", "player", 3, 3)
	put(state, "infantry", "Inimiga", "enemy", 4, 3)
	Turns.end_turn(state, "player")
	var actions := AI.play_turn(state, "enemy")
	assert_eq(actions, 1, "uma ação: atacar")
	assert_true(state.units[mine]["strength"] < 500, "a unidade do jogador sofreu baixas")


func test_enemy_moves_then_attacks_when_it_can_reach_a_target() -> void:
	var state := new_battle()
	var mine := put(state, "infantry", "Minha", "player", 3, 3)
	var enemy := put(state, "infantry", "Inimiga", "enemy", 5, 3)  # distância 2
	Turns.end_turn(state, "player")
	var actions := AI.play_turn(state, "enemy")
	assert_eq(actions, 2, "mover + atacar")
	assert_eq(state.units[enemy]["pos"], hx(4, 3), "ficou adjacente")
	assert_true(state.units[mine]["strength"] < 500, "atacou")


func test_enemy_approaches_when_nothing_is_reachable() -> void:
	var state := new_battle()
	put(state, "infantry", "Minha", "player", 1, 3)
	var enemy := put(state, "infantry", "Inimiga", "enemy", 10, 3)
	var before := Hex.distance(state.units[enemy]["pos"], hx(1, 3))
	Turns.end_turn(state, "player")
	AI.play_turn(state, "enemy")
	assert_true(Hex.distance(state.units[enemy]["pos"], hx(1, 3)) < before, "aproximou-se")


func test_enemy_goes_around_water_through_the_ford() -> void:
	var state := new_battle()
	put(state, "infantry", "Minha", "player", 1, 1)
	var enemy := put(state, "infantry", "Inimiga", "enemy", 8, 1)
	Turns.end_turn(state, "player")
	for i in 6:
		AI.play_turn(state, "enemy")
		for id in state.live_units():
			assert_true(state.map.is_passable(state.units[id]["pos"]), "nunca em água")
		Turns.end_turn(state, "enemy")
		Turns.end_turn(state, "player")
	assert_true(Hex.axial_to_offset(state.units[enemy]["pos"]).x < 8, "avançou para o oeste contornando o rio")


func test_enemy_artillery_fires_from_range_and_does_not_fire_after_moving() -> void:
	var state := new_battle()
	var mine := put(state, "infantry", "Minha", "player", 3, 3)
	var gun := put(state, "artillery", "Canhões", "enemy", 6, 3)  # distância 3
	Turns.end_turn(state, "player")
	AI.play_turn(state, "enemy")
	assert_true(state.units[mine]["strength"] < 500, "artilharia atirou sem se mover")
	assert_eq(state.units[gun]["pos"], hx(6, 3), "não se moveu")

	var far := new_battle()
	put(far, "infantry", "Minha", "player", 1, 3)
	var gun2 := put(far, "artillery", "Canhões", "enemy", 9, 3)
	Turns.end_turn(far, "player")
	var actions := AI.play_turn(far, "enemy")
	assert_eq(actions, 1, "só se aproxima")
	assert_true(not far.units[gun2]["attacked"], "e não atira no turno em que se move")


func test_ai_never_controls_routing_units() -> void:
	var state := new_battle()
	put(state, "infantry", "Minha", "player", 3, 3)
	var enemy := put(state, "infantry", "Fugitiva", "enemy", 4, 3)
	state.units[enemy]["routing"] = true
	state.units[enemy]["morale"] = 10
	Turns.end_turn(state, "player")
	assert_eq(AI.play_turn(state, "enemy"), 0, "sem ordens para quem está em retirada")


func test_ai_turn_is_deterministic() -> void:
	var results := []
	for i in 2:
		var controller := new_controller()
		controller.end_turn()
		controller.end_turn()
		results.append(controller.state.to_dict())
	assert_eq(results[0], results[1], "mesmo cenário e semente: mesmo desenrolar")


func test_ai_only_uses_valid_actions() -> void:
	var controller := new_controller()
	var state: BattleState = controller.state
	for turn in 8:
		var before_positions := {}
		for id in state.live_units():
			before_positions[id] = state.units[id]["pos"]
		controller.end_turn()
		for id in state.live_units():
			assert_true(state.map.is_passable(state.units[id]["pos"]), "unidade em hexágono transitável")
			for other in state.live_units():
				if other != id:
					assert_true(state.units[other]["pos"] != state.units[id]["pos"], "duas unidades no mesmo hexágono")
			assert_true(state.units[id]["strength"] <= state.units[id]["max_strength"], "efetivo válido")
		if state.over:
			break


func test_ai_versus_ai_battles_always_finish() -> void:
	# Cenário padrão: os dois lados controlados pela mesma rotina, com a semente configurada.
	for seed_value in [1805, 7, 99]:
		var state := new_battle(false, 0.1)
		state.rng.seed = seed_value
		var guard := 0
		while not state.over and guard < 200:
			AI.play_turn(state, state.active_side)
			if not state.over:
				Turns.end_turn(state, state.active_side)
			guard += 1
		assert_true(state.over, "a batalha (semente %d) termina em %d passos" % [seed_value, guard])
		assert_true(state.result["winner"] in ["player", "enemy", "draw"], "tem resultado")
		assert_true(state.turn <= state.max_turns, "dentro do limite de turnos")


# --- Controlador ---------------------------------------------------------------------------

func test_controller_click_flow_move_then_attack() -> void:
	var controller := new_controller()
	var state: BattleState = controller.state
	var messages: Array[Dictionary] = []
	controller.message_posted.connect(func(text: String, is_error: bool) -> void: messages.append({"text": text, "error": is_error}))
	controller.click_hex(hx(3, 3))
	assert_eq(controller.selected_unit_id, state.unit_at(hx(3, 3)), "selecionou")
	controller.click_hex(hx(5, 3))  # destino válido: 2 planícies
	assert_eq(state.unit_at(hx(5, 3)), controller.selected_unit_id, "moveu")
	assert_true(not messages[-1]["error"], messages[-1]["text"])
	controller.click_hex(hx(5, 4))  # outro destino: já se moveu
	assert_true(messages[-1]["error"] and "já se moveu" in messages[-1]["text"], messages[-1]["text"])
	controller.click_hex(hx(8, 3))  # inimigo longe demais
	assert_true(messages[-1]["error"] and "fora do alcance" in messages[-1]["text"], messages[-1]["text"])
	assert_eq(controller.selected_unit_id, state.unit_at(hx(5, 3)), "a seleção própria continua")


func test_controller_end_turn_runs_the_enemy_and_returns_control() -> void:
	var controller := new_controller()
	var state: BattleState = controller.state
	var logged: Array[String] = []
	controller.log_added.connect(func(text: String) -> void: logged.append(text))
	var result := controller.end_turn()
	assert_true(result["ok"], "turno encerrado")
	assert_eq(state.active_side, "player", "controle devolvido ao jogador")
	assert_eq(state.turn, 2, "turno 2")
	var joined := "\n".join(PackedStringArray(logged))
	assert_true("Turno 2" in joined and "Austríaco" in joined or "Hussardos" in joined or "Bateria Austríaca" in joined, "o registro mostra o turno inimigo: " + joined)
	for id in state.live_units("player"):
		assert_true(not state.units[id]["moved"] and not state.units[id]["attacked"], "ações do jogador restauradas")


func test_controller_rejects_actions_during_the_enemy_side() -> void:
	var controller := new_controller()
	controller.state.active_side = "enemy"
	var result := controller.attack(controller.state.unit_at(hx(3, 3)), controller.state.unit_at(hx(8, 3)))
	assert_true(not result["ok"] and "Não é o turno" in result["message"], result["message"])
	assert_eq(controller.reachable_hexes(), {}, "sem destinos enquanto não é a vez do jogador")


func test_controller_attack_targets_highlight() -> void:
	var controller := new_controller()
	var state: BattleState = controller.state
	var mine: int = state.unit_at(hx(3, 3))
	var enemy: int = state.unit_at(hx(8, 3))
	state.units[enemy]["pos"] = hx(4, 3)
	controller.select_unit(mine)
	assert_eq(controller.attack_target_ids(), [enemy] as Array[int], "inimigo adjacente é alvo")
	controller.attack(mine, enemy)
	assert_eq(controller.attack_target_ids(), [] as Array[int], "depois de atacar, sem alvos")


func test_unit_view_exposes_the_required_information() -> void:
	var controller := new_controller()
	var view := controller.unit_view(controller.state.unit_at(hx(1, 4)))
	assert_eq(view["name"], "Bateria de Campanha", "nome")
	assert_eq(view["type_name"], "Artilharia", "tipo")
	assert_eq(view["strength"], 80, "efetivo")
	assert_eq(view["max_strength"], 80, "efetivo máximo")
	assert_eq(view["attack"], 9.0, "ataque")
	assert_eq(view["defense"], 3.0, "defesa")
	assert_eq(view["move_available"], 2, "movimento disponível")
	assert_eq(view["attack_range"], 3, "alcance")
	assert_eq(view["morale"], 100, "moral")
	assert_eq(view["status_text"], "Firme", "estado")
	assert_eq(view["terrain_name"], "Colina", "terreno sob a unidade")
	var hex := controller.hex_view(hx(6, 0))
	assert_eq(hex["terrain_name"], "Água", "hexágono de água")
	assert_true(not hex["passable"], "intransponível")
	assert_eq(hex["col"], 6, "coluna")
