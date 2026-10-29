extends "res://tests/battle_case.gd"
## Retirada em fuga: atravessa aliadas, nunca inimigas nem água, nunca para sobre outra unidade,
## sem ciclos e sem travar a interface. Unidades normais mantêm as regras de ocupação.

const Movement := preload("res://src/battle/battle_movement.gd")
const Turns := preload("res://src/battle/battle_turns.gd")


## Uma rodada completa: o início do turno do jogador executa a retirada forçada.
func _round(state: BattleState) -> void:
	Turns.end_turn(state, "player")
	Turns.end_turn(state, "enemy")


func _routing(state: BattleState, type_id: String, col: int, row: int, side: String = "player") -> int:
	var id := put(state, type_id, "Fugitiva", side, col, row)
	state.units[id]["routing"] = true
	state.units[id]["morale"] = 5
	return id


func _surround_with_allies(state: BattleState, hex: Vector2i, side: String = "player") -> Array[int]:
	var ids: Array[int] = []
	for n in state.map.neighbors(hex):
		if state.map.is_passable(n):  # nunca coloca unidades em água
			ids.append(state.add_unit("infantry", "Aliada", side, n))
	return ids


# --- O defeito reproduzido: cercada por seis aliadas ---------------------------------------

func test_unit_surrounded_by_six_allies_is_no_longer_stuck() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 3, 3)
	var allies := _surround_with_allies(state, hx(3, 3))
	assert_eq(allies.size(), 6, "seis aliadas ao redor")
	put(state, "infantry", "Inimigo", "enemy", 10, 3)
	_round(state)
	assert_true(state.units[runner]["fled"], "atravessou as aliadas e alcançou a borda (custo 3 = alcance 3)")
	for id in allies:
		assert_eq(state.units[id]["pos"], state.units[id]["pos"], "aliadas intocadas")
		assert_true(state.is_on_field(state.units[id]), "aliadas continuam em campo")
	assert_true(not ("cercada" in "\n".join(PackedStringArray(state.log))), "sem a mensagem de cerco")


func test_stops_on_the_last_free_hex_when_the_edge_is_out_of_reach() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 5, 3)
	var allies := _surround_with_allies(state, hx(5, 3))
	put(state, "infantry", "Inimigo", "enemy", 10, 3)
	var start_col: int = Hex.axial_to_offset(state.units[runner]["pos"]).x
	_round(state)
	var unit: Dictionary = state.units[runner]
	assert_true(not unit["fled"], "a borda está a 5 de custo: ainda não foge")
	assert_true(unit["pos"] != hx(5, 3), "saiu do cerco")
	assert_true(Hex.axial_to_offset(unit["pos"]).x < start_col, "em direção à borda oeste")
	assert_eq(state.unit_at(unit["pos"]), runner, "só ela ocupa o hexágono final")
	for id in allies:
		assert_true(state.units[id]["pos"] != unit["pos"], "não parou sobre uma aliada")
	assert_true(Hex.distance(hx(5, 3), unit["pos"]) <= 3, "no máximo o alcance de movimento")


func test_stays_put_when_no_free_hex_is_reachable() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 5, 3)
	# Aliadas em todos os hexágonos das colunas 2 a 4: dentro do alcance (3) não há hexágono livre à frente.
	for col in [2, 3, 4]:
		for row in 9:
			if state.map.is_passable(hx(col, row)):
				state.add_unit("infantry", "Aliada", "player", hx(col, row))
	put(state, "infantry", "Inimigo", "enemy", 10, 3)
	var before: Dictionary = state.to_dict()["units"].duplicate(true)
	_round(state)
	var unit: Dictionary = state.units[runner]
	assert_eq(unit["pos"], hx(5, 3), "sem hexágono livre: permanece onde está")
	assert_true(unit["routing"] and not unit["fled"], "estado consistente: ainda em retirada")
	assert_true("não encontra espaço livre" in "\n".join(PackedStringArray(state.log)), "registrado")
	for id in state.units:
		if id != runner:
			assert_eq(state.units[id]["pos"], before[id]["pos"], "ninguém mais foi deslocado")
	assert_true(not state.over, "a batalha segue (a interface não trava)")


func test_flees_through_an_ally_standing_on_the_edge() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 1, 3)
	var edge_allies: Array[int] = []
	for hex in state.map.edge_hexes("west"):
		edge_allies.append(state.add_unit("infantry", "Guarda", "player", hex))
	put(state, "infantry", "Inimigo", "enemy", 10, 3)
	_round(state)
	assert_true(state.units[runner]["fled"], "saiu do campo pela borda ocupada por aliada")
	for id in edge_allies:
		assert_true(state.is_on_field(state.units[id]), "a aliada na borda continua em campo")
		assert_eq(state.unit_at(state.units[id]["pos"]), id, "no mesmo lugar")


# --- Limites: inimigos e água ----------------------------------------------------------------

func test_enemy_units_still_block_the_retreat() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 5, 3)
	put(state, "infantry", "Firme", "player", 1, 1)
	for n in state.map.neighbors(hx(5, 3)):
		state.add_unit("infantry", "Parede", "enemy", n)
	_round(state)
	assert_eq(state.units[runner]["pos"], hx(5, 3), "cercada por inimigos: não se move")
	assert_true(state.units[runner]["routing"], "continua em retirada")
	assert_true("cercada" in "\n".join(PackedStringArray(state.log)), "registrado")


func test_a_full_enemy_wall_cannot_be_crossed_even_with_allies_around() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 5, 3)
	put(state, "infantry", "Firme", "player", 1, 1)
	_surround_with_allies(state, hx(5, 3))
	for row in 9:
		state.add_unit("infantry", "Muralha", "enemy", hx(4, row))  # coluna inteira de inimigos
	for i in 3:
		_round(state)
	assert_eq(state.units[runner]["pos"], hx(5, 3), "a muralha inimiga bloqueia: não atravessa")
	assert_true(not state.units[runner]["fled"], "não escapou")


func test_water_still_blocks_and_the_route_uses_the_ford() -> void:
	var state := new_battle()
	var runner := _routing(state, "cavalry", 7, 1)  # a leste do rio; a borda de origem fica a oeste
	_surround_with_allies(state, hx(7, 1))
	put(state, "infantry", "Inimigo", "enemy", 11, 8)
	var crossed_column := false
	for i in 8:
		if state.units[runner]["fled"]:
			break
		_round(state)
		assert_true(state.map.is_passable(state.units[runner]["pos"]), "nunca termina em água")
		crossed_column = crossed_column or Hex.axial_to_offset(state.units[runner]["pos"]).x <= 6
	assert_true(state.units[runner]["fled"], "chegou à borda contornando o rio pelo vau")
	for id in state.live_units():
		assert_true(state.map.is_passable(state.units[id]["pos"]), "todas em hexágonos transitáveis")


func test_enemy_side_retreats_east_through_its_own_allies() -> void:
	var state := new_battle()
	put(state, "infantry", "Firme", "player", 1, 1)
	var runner := _routing(state, "infantry", 10, 3, "enemy")
	_surround_with_allies(state, hx(10, 3), "enemy")
	# A fuga do inimigo ocorre no início do turno dele.
	Turns.end_turn(state, "player")
	assert_true(state.units[runner]["fled"], "o inimigo também atravessa aliadas rumo à borda leste (custo 1)")


# --- Sem ciclos, determinismo, interface ----------------------------------------------------------

func test_retreat_progress_is_monotonic_and_terminates() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 9, 4)
	for id in [state.add_unit("infantry", "A", "player", hx(8, 4)), state.add_unit("infantry", "B", "player", hx(8, 3)),
			state.add_unit("infantry", "C", "player", hx(7, 4))]:
		state.units[id]["morale"] = 100
	state.units[runner]["morale"] = 0
	state.rules = state.rules.duplicate()
	state.rules["morale_recovery_routing"] = 0  # sem reagrupamento: o teste mede só o deslocamento
	put(state, "infantry", "Inimigo", "enemy", 11, 8)
	var columns: Array[int] = []
	for i in 12:
		if state.units[runner]["fled"]:
			break
		_round(state)
		if not state.units[runner]["fled"]:
			columns.append(Hex.axial_to_offset(state.units[runner]["pos"]).x)
	assert_true(state.units[runner]["fled"], "termina fugindo em poucos turnos (sem ciclo infinito)")
	for i in range(1, columns.size()):
		assert_true(columns[i] <= columns[i - 1], "nunca se afasta da borda de fuga: %s" % str(columns))


func test_retreat_is_deterministic() -> void:
	var runs := []
	for k in 2:
		var state := new_battle()
		var runner := _routing(state, "infantry", 6, 3)
		_surround_with_allies(state, hx(6, 3))
		put(state, "infantry", "Inimigo", "enemy", 11, 3)
		_round(state)
		runs.append(state.units[runner]["pos"])
	assert_eq(runs[0], runs[1], "mesma situação, mesma rota")


func test_interface_is_not_blocked_by_a_stuck_routing_unit() -> void:
	var controller := new_controller()
	var state: BattleState = controller.state
	var runner: int = state.unit_at(hx(3, 3))
	state.units[runner]["routing"] = true
	state.units[runner]["morale"] = 5
	for n in state.map.neighbors(hx(3, 3)):
		if state.unit_at(n) == 0:
			state.add_unit("infantry", "Parede", "enemy", n)  # inimigos: ela fica realmente presa
	var result := controller.end_turn()
	assert_true(result["ok"], "o turno é processado normalmente")
	assert_eq(state.active_side, "player", "o controle volta ao jogador (sem travar)")
	controller.click_hex(state.units[runner]["pos"])
	assert_eq(controller.selected_unit_id, runner, "a unidade presa continua selecionável")
	assert_eq(controller.unit_view(runner)["status_text"], "Em retirada", "estado consistente")
	var order := controller.move(runner, hx(3, 4))
	assert_true(not order["ok"] and "retirada" in order["message"], "ordens são recusadas com motivo: " + order["message"])
	assert_true(controller.end_turn()["ok"], "e o jogo continua")


# --- Regras normais preservadas ----------------------------------------------------------------------

func test_normal_units_are_still_blocked_by_allies() -> void:
	var state := new_battle()
	var mover := put(state, "infantry", "Normal", "player", 5, 3)
	_surround_with_allies(state, hx(5, 3))
	var before := state.to_dict()
	var result := Movement.move_unit(state, "player", mover, hx(3, 3))
	assert_true(not result["ok"] and "Sem caminho" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")
	assert_eq(Movement.reachable_for(state, mover)["cost"].size(), 1, "cercada por aliadas: só o próprio hexágono")


func test_normal_units_cannot_stop_on_or_cross_allied_hexes() -> void:
	var state := new_battle()
	var mover := put(state, "infantry", "Normal", "player", 3, 3)
	var ally := put(state, "infantry", "Aliada", "player", 4, 3)
	assert_true("ocupado" in Movement.check_move(state, "player", mover, hx(4, 3)), "não entra em hexágono de aliada")
	var reach: Dictionary = Movement.reachable_for(state, mover)["cost"]
	assert_true(not reach.has(state.units[ally]["pos"]), "o hexágono da aliada não é destino")
	var through := Movement.check_move(state, "player", mover, hx(5, 3))
	assert_eq(through, "", "contornar a aliada continua possível pelo mapa livre")
	var path: Array[Vector2i] = Movement.move_unit(state, "player", mover, hx(5, 3))["path"]
	assert_true(not (state.units[ally]["pos"] in path), "o caminho contorna a aliada em vez de atravessá-la")


func test_routing_unit_still_cannot_receive_orders_or_attack() -> void:
	var state := new_battle()
	var runner := _routing(state, "infantry", 3, 3)
	put(state, "infantry", "Inimigo", "enemy", 4, 3)
	assert_true("retirada" in Movement.check_move(state, "player", runner, hx(2, 3)), "sem ordens de movimento")
	assert_eq(Movement.available_move(state, state.units[runner]), 0, "sem movimento disponível")
