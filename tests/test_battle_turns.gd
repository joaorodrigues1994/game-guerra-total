extends "res://tests/battle_case.gd"
## Movimentação tática, seleção, turnos alternados e restauração das ações.

const Movement := preload("res://src/battle/battle_movement.gd")
const Combat := preload("res://src/battle/battle_combat.gd")
const Turns := preload("res://src/battle/battle_turns.gd")


func _two_sides() -> Array:
	var state := new_battle()
	var mine := put(state, "infantry", "Minha", "player", 3, 3)
	var theirs := put(state, "infantry", "Deles", "enemy", 9, 3)
	return [state, mine, theirs]


func test_move_uses_terrain_cost_and_updates_position() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	var result := Movement.move_unit(state, "player", s[1], hx(5, 3))  # 2 hexágonos de planície
	assert_true(result["ok"], result["message"])
	assert_eq(result["cost"], 2, "custo 2")
	assert_eq(state.units[s[1]]["pos"], hx(5, 3), "nova posição")
	assert_true(state.units[s[1]]["moved"], "movimento consumido")
	assert_eq(result["path"][0], hx(3, 3), "caminho começa na origem")
	assert_eq(result["path"][-1], hx(5, 3), "e termina no destino")
	assert_eq(state.unit_at(hx(3, 3)), 0, "hexágono de origem liberado")
	assert_eq(state.unit_at(hx(5, 3)), s[1], "destino ocupado")


func test_move_is_limited_by_cost_not_distance() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	# Colinas a 1 hexágono de distância custam 2: infantaria (3) alcança 1 colina + 1 planície, mas não 2 colinas.
	state.units[s[1]]["pos"] = hx(3, 4)  # (3,4) planície; (2,4) e (1,4) colinas
	var one_hill := Movement.check_move(state, "player", s[1], hx(2, 4))
	assert_eq(one_hill, "", "1 colina (custo 2) cabe em 3")
	var two_hills := Movement.check_move(state, "player", s[1], hx(1, 4))
	assert_true("Fora do alcance de movimento" in two_hills and "custa 4" in two_hills, two_hills)


func test_move_beyond_range_is_rejected_without_changes() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	var before := state.to_dict()
	var result := Movement.move_unit(state, "player", s[1], hx(7, 3))  # 4 planícies, alcance 3
	assert_true(not result["ok"] and "Fora do alcance" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_move_into_occupied_hex_is_rejected() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	put(state, "infantry", "B", "player", 4, 3)
	put(state, "infantry", "C", "enemy", 3, 2)
	var before := state.to_dict()
	for target in [hx(4, 3), hx(3, 2)]:
		var result := Movement.move_unit(state, "player", a, target)
		assert_true(not result["ok"] and "ocupado" in result["message"], "%s: %s" % [target, result["message"]])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_units_block_paths_through_them() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	# Cerca a unidade com aliados e inimigos nos seis vizinhos.
	for n in state.map.neighbors(hx(3, 3)):
		state.add_unit("infantry", "Parede", "enemy", n)
	var result := Movement.move_unit(state, "player", a, hx(5, 3))
	assert_true(not result["ok"] and "Sem caminho" in result["message"], result["message"])


func test_water_is_impassable() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	state.units[s[1]]["pos"] = hx(5, 0)
	var result := Movement.move_unit(state, "player", s[1], hx(6, 0))
	assert_true(not result["ok"] and "intransponível" in result["message"], result["message"])
	assert_eq(state.units[s[1]]["pos"], hx(5, 0), "não se moveu")
	# E não atravessa: (7,0) está do outro lado do rio, mas é plano e próximo, ainda assim exige o desvio pelo vau.
	var across := Movement.check_move(state, "player", s[1], hx(7, 0))
	assert_true(across != "", "não atravessa a água para chegar do outro lado: " + across)


func test_destination_out_of_map_or_same_hex_is_rejected() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	assert_true("fora do mapa" in Movement.check_move(state, "player", s[1], Vector2i(99, 99)), "fora do mapa")
	assert_true("já está" in Movement.check_move(state, "player", s[1], hx(3, 3)), "mesmo hexágono")
	assert_true("inexistente" in Movement.check_move(state, "player", 999, hx(4, 3)), "unidade inexistente")


func test_inactive_side_cannot_act() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	var before := state.to_dict()
	var move := Movement.move_unit(state, "enemy", s[2], hx(8, 3))
	assert_true(not move["ok"] and "Não é o turno" in move["message"], move["message"])
	var attack := Combat.attack(state, "enemy", s[2], s[1])
	assert_true(not attack["ok"] and "Não é o turno" in attack["message"], attack["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_unit_of_the_other_side_cannot_be_ordered() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	var result := Movement.move_unit(state, "player", s[2], hx(8, 3))  # unidade inimiga
	assert_true(not result["ok"] and "outro lado" in result["message"], result["message"])


func test_unit_cannot_move_twice_in_the_same_turn() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	assert_true(Movement.move_unit(state, "player", s[1], hx(4, 3))["ok"], "primeiro movimento")
	var before := state.to_dict()
	var second := Movement.move_unit(state, "player", s[1], hx(5, 3))
	assert_true(not second["ok"] and "já se moveu" in second["message"], second["message"])
	assert_eq(state.to_dict(), before, "estado intacto")
	assert_eq(Movement.available_move(state, state.units[s[1]]), 0, "sem movimento disponível")


func test_unit_cannot_attack_twice_in_the_same_turn() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 4, 3)
	assert_true(Combat.attack(state, "player", a, b)["ok"], "primeiro ataque")
	var before := state.to_dict()
	var second := Combat.attack(state, "player", a, b)
	assert_true(not second["ok"] and "já atacou" in second["message"], second["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_unit_may_move_then_attack_once_each() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 5, 3)
	assert_true(not Combat.check_attack(state, "player", a, b).is_empty(), "a 2 hexágonos: ainda fora do alcance corpo a corpo")
	assert_true(Movement.move_unit(state, "player", a, hx(4, 3))["ok"], "move")
	assert_true(Combat.attack(state, "player", a, b)["ok"], "ataca depois de mover")
	assert_true(not Combat.attack(state, "player", a, b)["ok"], "mas só uma vez")


func test_end_turn_alternates_sides_and_counts_rounds() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	assert_eq(state.active_side, "player", "começa o jogador")
	assert_eq(state.turn, 1, "turno 1")
	assert_true(Turns.end_turn(state, "player")["ok"], "jogador encerra")
	assert_eq(state.active_side, "enemy", "vez do inimigo")
	assert_eq(state.turn, 1, "o número só sobe quando a rodada fecha")
	assert_true(Turns.end_turn(state, "enemy")["ok"], "inimigo encerra")
	assert_eq(state.active_side, "player", "volta ao jogador")
	assert_eq(state.turn, 2, "turno 2")


func test_wrong_side_cannot_end_turn() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	var result := Turns.end_turn(state, "enemy")
	assert_true(not result["ok"] and "Não é o turno" in result["message"], result["message"])
	assert_eq(state.active_side, "player", "inalterado")


func test_actions_are_restored_at_the_start_of_the_sides_turn() -> void:
	var s := _two_sides()
	var state: BattleState = s[0]
	var a := put(state, "infantry", "A2", "player", 3, 4)
	var b := put(state, "infantry", "B2", "enemy", 4, 4)
	Movement.move_unit(state, "player", s[1], hx(4, 3))
	Combat.attack(state, "player", a, b)
	assert_true(state.units[s[1]]["moved"] and state.units[a]["attacked"], "ações consumidas")
	Turns.end_turn(state, "player")
	assert_true(state.units[s[1]]["moved"] and state.units[a]["attacked"], "durante o turno inimigo, as do jogador continuam consumidas")
	Turns.end_turn(state, "enemy")
	assert_true(not state.units[s[1]]["moved"] and not state.units[a]["attacked"], "restauradas ao iniciar o turno do jogador")
	assert_eq(state.units[s[1]]["moved_steps"], 0, "passos zerados")
	assert_true(Movement.move_unit(state, "player", s[1], hx(5, 3))["ok"], "pode se mover de novo")


func test_selection_through_the_controller_identifies_the_right_unit() -> void:
	var controller := new_controller()
	var state: BattleState = controller.state
	var player_unit: int = state.unit_at(hx(3, 3))
	var enemy_unit: int = state.unit_at(hx(8, 3))
	assert_eq(state.units[player_unit]["name"], "1º Batalhão de Linha", "unidade do jogador em (3,3)")
	assert_eq(state.units[enemy_unit]["name"], "1º Regimento Austríaco", "unidade inimiga em (8,3)")
	controller.click_hex(hx(3, 3))
	assert_eq(controller.selected_unit_id, player_unit, "clique seleciona a unidade do hexágono")
	assert_eq(controller.unit_view(controller.selected_unit_id)["name"], "1º Batalhão de Linha", "view da unidade")
	controller.click_hex(hx(2, 2))  # outra unidade (cavalaria)
	assert_eq(state.units[controller.selected_unit_id]["type"], "cavalry", "troca a seleção")
	controller.click_hex(hx(8, 3))  # inimigo, sem alvo válido: apenas inspeciona? há unidade própria selecionada -> tenta atacar e é rejeitado
	assert_eq(controller.selected_unit_id, state.unit_at(hx(2, 2)), "a seleção própria é mantida")
	controller.clear_selection()
	assert_eq(controller.selected_unit_id, 0, "seleção limpa")
	controller.click_hex(hx(8, 3))
	assert_eq(controller.selected_unit_id, enemy_unit, "sem unidade própria selecionada, o clique inspeciona o inimigo")
	assert_eq(controller.reachable_hexes(), {}, "unidade inimiga não tem destinos")


func test_reachable_highlight_matches_the_movement_rules() -> void:
	var controller := new_controller()
	controller.click_hex(hx(3, 3))
	var reach: Dictionary = controller.reachable_hexes()
	assert_true(not reach.is_empty(), "há destinos")
	assert_true(not reach.has(hx(3, 3)), "sem o hexágono atual")
	for hex in reach:
		assert_true(reach[hex] <= 3, "dentro do alcance")
		assert_eq(Movement.check_move(controller.state, "player", controller.selected_unit_id, hex), "", "cada destino destacado é válido")
		assert_eq(controller.state.unit_at(hex), 0, "nenhum destino ocupado")
	assert_true(not reach.has(hx(2, 4)) or reach[hx(2, 4)] == 2, "colina custa 2")
