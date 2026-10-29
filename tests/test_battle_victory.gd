extends "res://tests/battle_case.gd"
## Retirada automática, condições de vitória, fim da batalha e reinício.

const Combat := preload("res://src/battle/battle_combat.gd")
const Movement := preload("res://src/battle/battle_movement.gd")
const Turns := preload("res://src/battle/battle_turns.gd")


# --- Retirada ------------------------------------------------------------------------

func test_routing_unit_retreats_toward_its_home_edge_without_teleporting() -> void:
	var state := new_battle()
	var runner := put(state, "infantry", "Fugitiva", "player", 5, 3)
	put(state, "infantry", "Reserva", "player", 3, 6)
	put(state, "infantry", "Inimigo", "enemy", 9, 3)
	state.units[runner]["morale"] = 10
	state.units[runner]["routing"] = true
	var before: Vector2i = state.units[runner]["pos"]
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")  # início do turno do jogador: retirada forçada
	var after: Vector2i = state.units[runner]["pos"]
	assert_true(after != before, "recuou")
	assert_true(Hex.distance(before, after) <= state.units[runner]["move_range"], "sem teletransporte: no máximo o alcance de movimento")
	assert_true(Hex.axial_to_offset(after).x < Hex.axial_to_offset(before).x, "em direção à borda oeste")
	assert_true(state.units[runner]["moved"] and state.units[runner]["attacked"], "não age no turno")


func test_routing_unit_leaves_the_field_at_the_edge() -> void:
	var state := new_battle()
	var runner := put(state, "infantry", "Fugitiva", "player", 1, 3)
	put(state, "infantry", "Reserva", "player", 3, 6)
	put(state, "infantry", "Inimigo", "enemy", 9, 3)
	state.units[runner]["morale"] = 5
	state.units[runner]["routing"] = true
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")
	assert_true(state.units[runner]["fled"], "chegou à borda: abandona o campo")
	assert_eq(state.unit_at(state.units[runner]["pos"]), 0, "hexágono liberado")
	assert_eq(state.status_of(state.units[runner]), "fled", "estado fugiu")
	assert_true(not (runner in state.live_units()), "fora de campo")


func test_boxed_in_routing_unit_stays_put_and_does_not_loop() -> void:
	var state := new_battle()
	var runner := put(state, "infantry", "Cercada", "player", 5, 3)
	put(state, "infantry", "Reserva", "player", 3, 6)
	for n in state.map.neighbors(hx(5, 3)):
		state.add_unit("infantry", "Parede", "enemy", n)
	state.units[runner]["morale"] = 5
	state.units[runner]["routing"] = true
	var before: Vector2i = state.units[runner]["pos"]
	for i in 3:
		Turns.end_turn(state, "player")
		Turns.end_turn(state, "enemy")
	assert_eq(state.units[runner]["pos"], before, "sem caminho: permanece parada")
	assert_true(state.units[runner]["routing"], "continua em retirada")
	assert_true("cercada" in "\n".join(PackedStringArray(state.log)), "registrado")


func test_routing_unit_rallies_when_safe() -> void:
	var state := new_battle()
	var runner := put(state, "infantry", "Fugitiva", "player", 1, 7)
	put(state, "infantry", "Reserva", "player", 3, 6)
	put(state, "infantry", "Inimigo", "enemy", 11, 3)
	state.units[runner]["morale"] = 30
	state.units[runner]["routing"] = true
	state.units[runner]["move_range"] = 0  # para o teste: não anda, só recupera moral (recua 0)
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")  # +8 -> 38 (ainda em retirada)
	assert_true(state.units[runner]["routing"], "38 < 40: ainda em retirada")
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")  # +8 -> 46 >= 40: reagrupa
	assert_true(not state.units[runner]["routing"], "reagrupada")
	assert_eq(state.status_of(state.units[runner]), "shaken", "e abalada (46 <= 50)")


func test_no_recovery_next_to_an_enemy() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	put(state, "infantry", "B", "enemy", 4, 3)
	state.units[a]["morale"] = 60
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")
	assert_eq(state.units[a]["morale"], 60, "adjacente a inimigo: sem recuperação")
	state.units[a]["pos"] = hx(1, 3)
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")
	assert_eq(state.units[a]["morale"], 65, "longe do inimigo: +5")


# --- Vitória -----------------------------------------------------------------------------

func _finish_state() -> Array:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 4, 3, {"strength": 1})
	return [state, a, b]


func test_victory_by_elimination() -> void:
	var s := _finish_state()
	var state: BattleState = s[0]
	var result := Combat.attack(state, "player", s[1], s[2])
	assert_true(result["battle_over"] and state.over, "batalha encerrada")
	assert_eq(state.result["winner"], "player", "vencedor")
	assert_eq(state.result["reason"], "elimination", "motivo")
	assert_true("eliminação" in state.result["text"], state.result["text"])


func test_victory_by_rout_when_every_remaining_unit_is_routing() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 4, 3)
	var c := put(state, "infantry", "C", "enemy", 9, 5)
	state.units[c]["routing"] = true
	state.units[c]["morale"] = 10
	state.units[b]["morale"] = 30  # um golpe o põe em fuga
	Combat.attack(state, "player", a, b)
	assert_true(state.units[b]["routing"], "B em retirada")
	assert_true(state.over, "todas as unidades do inimigo estão em retirada: acabou")
	assert_eq(state.result["winner"], "player", "vencedor")
	assert_eq(state.result["reason"], "rout", "motivo: quebra por retirada")


func test_a_single_routing_unit_among_firm_ones_does_not_end_the_battle() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 4, 3)
	put(state, "infantry", "C", "enemy", 9, 5)  # firme
	state.units[b]["morale"] = 30
	Combat.attack(state, "player", a, b)
	assert_true(state.units[b]["routing"] and not state.over, "ainda há unidades efetivas do inimigo")


func test_units_without_actions_left_do_not_count_as_defeat() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	put(state, "infantry", "B", "enemy", 9, 3)
	state.units[a]["moved"] = true
	state.units[a]["attacked"] = true
	assert_true(not Turns.evaluate_victory(state), "ter gasto as ações não é derrota")


func test_fled_units_do_not_count_as_effective() -> void:
	var state := new_battle()
	put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 9, 3)
	state.units[b]["fled"] = true
	assert_true(Turns.evaluate_victory(state), "sem unidades efetivas: acabou")
	assert_eq(state.result["winner"], "player", "vitória do jogador")
	assert_eq(state.result["reason"], "elimination", "todos deixaram o campo")


func test_mutual_break_is_a_draw() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 9, 3)
	state.units[a]["routing"] = true
	state.units[b]["routing"] = true
	Turns.evaluate_victory(state)
	assert_eq(state.result["winner"], "draw", "empate")
	assert_eq(state.result["reason"], "mutual_break", "motivo")


func test_turn_limit_decides_by_effective_strength() -> void:
	var state := new_battle()
	state.max_turns = 2
	put(state, "infantry", "A", "player", 1, 3)
	put(state, "infantry", "B", "enemy", 10, 3, {"strength": 300})
	for i in 2:
		Turns.end_turn(state, "player")
		Turns.end_turn(state, "enemy")
	assert_true(state.over, "limite de turnos atingido")
	assert_eq(state.result["reason"], "turn_limit", "motivo")
	assert_eq(state.result["winner"], "player", "mais efetivos vence (500 x 300)")
	assert_eq(state.turn, 2, "o número do turno não passa do limite")


func test_no_actions_are_accepted_after_the_end() -> void:
	var s := _finish_state()
	var state: BattleState = s[0]
	var extra := put(state, "cavalry", "Extra", "player", 2, 3)
	Combat.attack(state, "player", s[1], s[2])
	assert_true(state.over, "terminou")
	var before := state.to_dict()
	var move := Movement.move_unit(state, "player", extra, hx(2, 4))
	var attack := Combat.attack(state, "player", extra, s[2])
	var end := Turns.end_turn(state, "player")
	for result in [move, attack, end]:
		assert_true(not result["ok"] and "terminou" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "nada mudou depois do fim")


func test_result_summary_is_the_future_battle_result_contract() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3, {"source_id": 77})
	var b := put(state, "infantry", "B", "enemy", 4, 3, {"strength": 1})
	Combat.attack(state, "player", a, b)
	var summary := state.result_summary()
	assert_eq(summary["winner"], "player", "vencedor")
	assert_eq(summary["reason"], "elimination", "motivo")
	assert_eq(summary["units"]["player"][0]["source_id"], 77, "id da unidade de campanha de origem preservado")
	assert_eq(summary["units"]["enemy"][0]["status"], "destroyed", "situação de cada unidade")
	assert_eq(summary["units"]["enemy"][0]["strength"], 0, "efetivos finais (base para baixas persistentes)")
	assert_eq(summary["units"]["player"][0]["strength"], 500, "o vencedor não sofreu baixas")
	assert_eq(summary["turns"], 1, "turnos jogados")


# --- Reinício ------------------------------------------------------------------------------

func test_restart_restores_the_whole_scenario() -> void:
	var controller := new_controller()
	var fresh_units: Dictionary = controller.state.units.duplicate(true)
	var fresh_terrain: Dictionary = controller.state.map.terrain.duplicate()
	controller.click_hex(hx(3, 3))
	controller.click_hex(hx(4, 3))  # move a unidade selecionada
	controller.end_turn()
	assert_true(controller.state.units != fresh_units, "a batalha andou")
	controller.restart()
	assert_eq(controller.state.units, fresh_units, "unidades, posições, moral e efetivos restaurados")
	assert_eq(controller.state.map.terrain, fresh_terrain, "terreno restaurado")
	assert_eq(controller.state.turn, 1, "turno 1")
	assert_eq(controller.state.active_side, "player", "começa o jogador")
	assert_true(not controller.state.over and controller.state.result.is_empty(), "sem resultado")
	assert_eq(controller.selected_unit_id, 0, "sem seleção")
	assert_eq(controller.state.units.size(), 10, "nenhuma unidade duplicada")


func test_restart_is_equivalent_to_a_fresh_battle_and_replays_identically() -> void:
	var fresh := new_controller()
	var played := new_controller()
	played.end_turn()
	played.end_turn()
	played.restart()
	assert_eq(played.state.to_dict(), fresh.state.to_dict(), "estado idêntico ao de uma batalha nova (inclui a semente)")
	fresh.end_turn()
	played.end_turn()
	assert_eq(played.state.units, fresh.state.units, "o mesmo turno depois do reinício dá o mesmo resultado")


func test_restart_does_not_duplicate_signal_connections() -> void:
	var controller := new_controller()
	var counts_before := [controller.state_changed.get_connections().size(), controller.log_added.get_connections().size()]
	var seen: Array[int] = []
	controller.state_changed.connect(func() -> void: seen.append(1))
	for i in 3:
		controller.restart()
	assert_eq([controller.state_changed.get_connections().size(), controller.log_added.get_connections().size()],
		[counts_before[0] + 1, counts_before[1]], "reiniciar não cria conexões novas")
	seen.clear()
	controller.end_turn()
	assert_eq(seen.size(), 1, "uma única notificação por ação, mesmo depois de reiniciar")


func test_restart_after_the_end_allows_a_new_battle() -> void:
	var controller := new_controller()
	var finished: Array[Dictionary] = []
	controller.battle_finished.connect(func(summary: Dictionary) -> void: finished.append(summary))
	for id in controller.state.live_units("enemy"):
		controller.state.units[id]["destroyed"] = true
		controller.state.units[id]["strength"] = 0
	Turns.evaluate_victory(controller.state)
	controller.end_turn()  # recusado: acabou; dispara battle_finished uma vez
	assert_true(controller.state.over, "terminou")
	assert_eq(finished.size(), 1, "battle_finished emitido uma vez")
	controller.restart()
	assert_true(not controller.state.over, "nova batalha")
	assert_true(controller.end_turn()["ok"], "o jogo volta a aceitar ordens")
