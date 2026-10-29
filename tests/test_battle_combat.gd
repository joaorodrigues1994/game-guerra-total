extends "res://tests/battle_case.gd"
## Ataques, terreno, perdas, artilharia, cavalaria, moral e retirada.

const Combat := preload("res://src/battle/battle_combat.gd")
const Morale := preload("res://src/battle/battle_morale.gd")
const Movement := preload("res://src/battle/battle_movement.gd")
const Turns := preload("res://src/battle/battle_turns.gd")


func _duel(attacker_type: String = "infantry", target_type: String = "infantry") -> Array:
	var state := new_battle()
	var a := put(state, attacker_type, "Atacante", "player", 3, 3)
	var b := put(state, target_type, "Alvo", "enemy", 4, 3)
	return [state, a, b]


# --- Ataque básico ----------------------------------------------------------------

func test_valid_melee_attack_causes_losses_and_retaliation() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	var result := Combat.attack(state, "player", d[1], d[2])
	assert_true(result["ok"], result["message"])
	# poder 6 × 1 / defesa 6 = 1 -> 22% de 500 = 110 baixas.
	assert_eq(result["losses"], 110, "baixas do alvo")
	assert_eq(state.units[d[2]]["strength"], 390, "efetivo do alvo")
	# Retaliação: poder 6 × 0,78 / 6 = 0,78; 22% × 0,78 × 0,5 = 8,58% de 500 = 42,9 -> 43.
	assert_eq(result["counter_losses"], 43, "contra-ataque")
	assert_eq(state.units[d[1]]["strength"], 457, "efetivo do atacante")
	assert_true(state.units[d[1]]["attacked"], "ação de ataque consumida")
	assert_true(not result["destroyed"] and not result["battle_over"], "ninguém destruído")
	assert_true("110 baixas" in result["message"] and "contra-ataca" in result["message"], result["message"])


func test_attack_is_logged() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	Combat.attack(state, "player", d[1], d[2])
	var text := "\n".join(PackedStringArray(state.log))
	assert_true("Atacante ataca Alvo (corpo a corpo)" in text and "110 baixas" in text, text)


func test_attack_out_of_range_is_rejected_without_changes() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 6, 3)
	var before := state.to_dict()
	var result := Combat.attack(state, "player", a, b)
	assert_true(not result["ok"] and "fora do alcance" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_attack_against_ally_is_rejected() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "player", 4, 3)
	var before := state.to_dict()
	var result := Combat.attack(state, "player", a, b)
	assert_true(not result["ok"] and "aliada" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_attack_with_missing_or_removed_units_is_rejected() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	assert_true("inexistente" in Combat.check_attack(state, "player", 999, d[2]), "atacante inexistente")
	assert_true("inexistente" in Combat.check_attack(state, "player", d[1], 999), "alvo inexistente")
	state.units[d[2]]["destroyed"] = true
	assert_true("fora de combate" in Combat.check_attack(state, "player", d[1], d[2]), "alvo destruído")


func test_minimum_damage_is_always_positive() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "Fraco", "player", 3, 3, {"strength": 1})  # poder quase nulo
	var b := put(state, "infantry", "Forte", "enemy", 4, 3)
	state.units[b]["defense"] = 1000.0
	var result := Combat.attack(state, "player", a, b)
	assert_true(result["ok"] and result["losses"] >= 1, "ao menos 1 baixa: %s" % str(result["losses"]))


func test_losses_never_exceed_the_cap_or_the_strength() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	state.units[a]["attack"] = 1000.0  # poder absurdo
	var b := put(state, "infantry", "B", "enemy", 4, 3)
	var result := Combat.attack(state, "player", a, b)
	assert_eq(result["losses"], 300, "limitado a 60% de 500")
	assert_true(state.units[b]["strength"] >= 0, "efetivo não negativo")


# --- Terreno -----------------------------------------------------------------------

func test_terrain_changes_the_targets_defense() -> void:
	var results := {}
	for entry in [["plains", 5, 3], ["forest", 0, 0], ["hills", 10, 0]]:
		var state := new_battle()
		var a := put(state, "infantry", "A", "player", entry[1] + 1 if entry[0] == "forest" else entry[1] - 1, entry[2])
		var b := put(state, "infantry", "B", "enemy", entry[1], entry[2])
		assert_eq(state.map.terrain_id_at(state.units[b]["pos"]), entry[0], "alvo em %s" % entry[0])
		var fraction := Combat.loss_fraction(state, state.units[a], state.units[b], true, 1.0, 0.0)
		results[entry[0]] = fraction
	assert_true(is_equal_approx(results["plains"], 0.22), "planície: 22%")
	assert_true(is_equal_approx(results["forest"], 0.22 / 1.3), "floresta: defesa +30%%: %s" % results["forest"])
	assert_true(is_equal_approx(results["hills"], 0.22 / 1.2), "colina: defesa +20%%: %s" % results["hills"])
	assert_true(results["forest"] < results["hills"] and results["hills"] < results["plains"], "floresta > colina > planície em proteção")


func test_terrain_bonus_applies_to_actual_losses() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 1, 0)
	var b := put(state, "infantry", "B", "enemy", 0, 0)  # floresta
	var result := Combat.attack(state, "player", a, b)
	assert_eq(result["losses"], 85, "ceil(500 × 0,22 / 1,3) = 85 na floresta (contra 110 na planície)")


func test_attacker_terrain_only_matters_for_retaliation() -> void:
	var on_plains := new_battle()
	var a1 := put(on_plains, "infantry", "A", "player", 3, 3)
	var b1 := put(on_plains, "infantry", "B", "enemy", 4, 3)
	var plains_result := Combat.attack(on_plains, "player", a1, b1)
	var in_forest := new_battle()
	var a2 := put(in_forest, "infantry", "A", "player", 0, 1)  # atacante na floresta
	var b2 := put(in_forest, "infantry", "B", "enemy", 1, 1)   # alvo em planície
	assert_eq(in_forest.map.terrain_id_at(in_forest.units[a2]["pos"]), "forest", "atacante em floresta")
	assert_eq(in_forest.map.terrain_id_at(in_forest.units[b2]["pos"]), "plains", "alvo em planície")
	var forest_result := Combat.attack(in_forest, "player", a2, b2)
	assert_eq(forest_result["losses"], plains_result["losses"], "o terreno do atacante não aumenta o seu dano")
	assert_eq(plains_result["counter_losses"], 43, "retaliação contra atacante em planície")
	assert_eq(forest_result["counter_losses"], 33, "retaliação contra atacante na floresta (defesa ×1,3)")


# --- Tipos militares -----------------------------------------------------------------

func test_artillery_fires_at_range_without_retaliation() -> void:
	var state := new_battle()
	var art := put(state, "artillery", "Canhões", "player", 3, 3)
	var target := put(state, "infantry", "Alvo", "enemy", 5, 3)  # distância 2
	var result := Combat.attack(state, "player", art, target)
	assert_true(result["ok"], result["message"])
	assert_eq(result["losses"], 105, "poder 9 / defesa 6 = 1,5; 14% × 1,5 = 21% de 500")
	assert_eq(result["counter_losses"], 0, "sem retaliação contra tiro à distância")
	assert_eq(state.units[art]["strength"], 80, "artilharia intacta")
	assert_true("à distância" in result["message"], result["message"])


func test_artillery_range_limits() -> void:
	var state := new_battle()
	var art := put(state, "artillery", "Canhões", "player", 3, 3)
	var adjacent := put(state, "infantry", "Perto", "enemy", 4, 3)
	var far := put(state, "infantry", "Longe", "enemy", 7, 3)
	var ok := put(state, "infantry", "Alcance", "enemy", 6, 3)  # distância 3
	assert_true("perto demais" in Combat.check_attack(state, "player", art, adjacent), "mínimo de 2")
	assert_true("fora do alcance" in Combat.check_attack(state, "player", art, far), "máximo de 3")
	assert_eq(Combat.check_attack(state, "player", art, ok), "", "distância 3 vale")


func test_artillery_cannot_attack_after_moving() -> void:
	var state := new_battle()
	var art := put(state, "artillery", "Canhões", "player", 3, 3)
	var target := put(state, "infantry", "Alvo", "enemy", 6, 3)
	Movement.move_unit(state, "player", art, hx(4, 3))
	var reason := Combat.check_attack(state, "player", art, target)
	assert_true("não pode atacar no turno em que se moveu" in reason, reason)


func test_artillery_does_not_retaliate_in_melee() -> void:
	var state := new_battle()
	var inf := put(state, "infantry", "Infantaria", "player", 3, 3)
	var art := put(state, "artillery", "Canhões", "enemy", 4, 3)
	var result := Combat.attack(state, "player", inf, art)
	assert_true(result["ok"], result["message"])
	assert_eq(result["counter_losses"], 0, "artilharia não é unidade corpo a corpo: não retalia")
	assert_eq(state.units[inf]["strength"], 500, "atacante ileso")


func test_cavalry_charge_needs_movement_and_adds_damage() -> void:
	var still := new_battle()
	var c1 := put(still, "cavalry", "Cav", "player", 3, 3)
	var t1 := put(still, "infantry", "Alvo", "enemy", 4, 3)
	var plain := Combat.attack(still, "player", c1, t1)
	assert_true(not plain["charge"], "sem movimento prévio não há carga")
	assert_eq(plain["losses"], 147, "8/6 × 22% × 500 = 146,7")

	var charging := new_battle()
	var c2 := put(charging, "cavalry", "Cav", "player", 1, 3)
	var t2 := put(charging, "infantry", "Alvo", "enemy", 4, 3)
	assert_true(Movement.move_unit(charging, "player", c2, hx(3, 3))["ok"], "avança 2 hexágonos")
	var result := Combat.attack(charging, "player", c2, t2)
	assert_true(result["charge"], "carga")
	assert_eq(result["losses"], 198, "×1,35: 10,8/6 × 22% × 500 = 198")
	assert_true("carga" in result["message"], result["message"])


func test_cavalry_moves_farther_than_infantry() -> void:
	var state := new_battle()
	var cav := put(state, "cavalry", "Cav", "player", 3, 3)
	var inf := put(state, "infantry", "Inf", "player", 3, 5)
	var art := put(state, "artillery", "Art", "player", 2, 7)
	var reach := func(id: int) -> int: return Movement.reachable_for(state, id)["cost"].size()
	assert_true(reach.call(cav) > reach.call(inf) and reach.call(inf) > reach.call(art), "mobilidade: cavalaria > infantaria > artilharia")


# --- Moral e retirada ---------------------------------------------------------------

func test_morale_drops_with_losses_and_changes_state() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	assert_eq(state.status_of(state.units[d[2]]), "firm", "começa firme")
	Combat.attack(state, "player", d[1], d[2])
	# 110/500 = 22% -> 22 + 3 (golpe) + 2 (corpo a corpo) = 27.
	assert_eq(state.units[d[2]]["morale"], 73, "moral do alvo")
	assert_eq(state.units[d[1]]["morale"], 86, "moral do atacante após o contra-ataque (9 + 3 + 2)")
	Morale.change(state, state.units[d[2]], -30)
	assert_eq(state.units[d[2]]["morale"], 43, "queda adicional")
	assert_eq(state.status_of(state.units[d[2]]), "shaken", "abaixo de 50: abalada")
	Morale.change(state, state.units[d[2]], -30)
	assert_eq(state.status_of(state.units[d[2]]), "routing", "abaixo de 25: em retirada")


func test_shaken_units_deal_less_damage() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	var firm := Combat.loss_fraction(state, state.units[d[1]], state.units[d[2]], true, 1.0, 0.0)
	state.units[d[1]]["morale"] = 40
	var shaken := Combat.loss_fraction(state, state.units[d[1]], state.units[d[2]], true, 1.0, 0.0)
	assert_true(is_equal_approx(shaken, firm * 0.8), "ataque ×0,8 quando abalada")
	state.units[d[2]]["morale"] = 40
	var shaken_target := Combat.loss_fraction(state, state.units[d[1]], state.units[d[2]], true, 1.0, 0.0)
	assert_true(is_equal_approx(shaken_target, firm * 0.8 / 0.9), "alvo abalado defende ×0,9")


func test_routing_units_cannot_attack_and_are_easier_to_hit() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	state.units[d[1]]["routing"] = true
	var reason := Combat.check_attack(state, "player", d[1], d[2])
	assert_true("retirada" in reason, reason)
	var result := Combat.attack(state, "player", d[1], d[2])
	assert_true(not result["ok"], "ataque normal recusado")
	state.units[d[1]]["routing"] = false
	state.units[d[2]]["routing"] = true
	var against_routed := Combat.loss_fraction(state, state.units[d[1]], state.units[d[2]], true, 1.0, 0.0)
	assert_true(is_equal_approx(against_routed, 0.44), "em retirada, a defesa cai pela metade")


func test_routing_unit_does_not_retaliate() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	state.units[d[2]]["morale"] = 20
	state.units[d[2]]["routing"] = true
	var result := Combat.attack(state, "player", d[1], d[2])
	assert_eq(result["counter_losses"], 0, "unidade em fuga não contra-ataca")


func test_unit_enters_retreat_when_morale_hits_the_threshold() -> void:
	var d := _duel()
	var state: BattleState = d[0]
	state.units[d[2]]["morale"] = 30
	Combat.attack(state, "player", d[1], d[2])
	assert_true(state.units[d[2]]["routing"], "moral <= 25 -> retirada")
	assert_true("entra em retirada" in "\n".join(PackedStringArray(state.log)), "registrado no log")


func test_destroyed_unit_is_removed_and_frees_the_hex() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 4, 3, {"strength": 1})
	put(state, "infantry", "Outro", "enemy", 9, 3)
	var result := Combat.attack(state, "player", a, b)
	assert_true(result["destroyed"], "destruída")
	assert_true(state.units[b]["destroyed"] and state.units[b]["strength"] == 0, "efetivo zero")
	assert_eq(state.unit_at(hx(4, 3)), 0, "hexágono liberado")
	assert_true(not (b in state.live_units()), "fora da lista de unidades em campo")
	assert_eq(result["counter_losses"], 0, "unidade destruída não contra-ataca")
	assert_eq(state.status_of(state.units[b]), "destroyed", "estado destruída")
	assert_true(Movement.move_unit(state, "player", a, hx(4, 3))["ok"], "o hexágono liberado pode ser ocupado")


func test_destroying_a_unit_shakes_nearby_allies_only() -> void:
	var state := new_battle()
	var a := put(state, "infantry", "A", "player", 3, 3)
	var victim := put(state, "infantry", "Vítima", "enemy", 4, 3, {"strength": 1})
	var near := put(state, "infantry", "Perto", "enemy", 5, 3)   # distância 1 da vítima
	var far := put(state, "infantry", "Longe", "enemy", 9, 5)    # bem distante
	Combat.attack(state, "player", a, victim)
	assert_eq(state.units[near]["morale"], 90, "aliado próximo perde 10")
	assert_eq(state.units[far]["morale"], 100, "aliado distante não perde")


func test_strength_and_morale_stay_within_limits_over_many_attacks() -> void:
	var state := new_battle(true, 0.1)
	var ids := []
	for i in 4:
		ids.append(put(state, "infantry", "P%d" % i, "player", 3, 2 + i))
		ids.append(put(state, "infantry", "E%d" % i, "enemy", 4, 2 + i))
	for turn in 20:
		for id in state.live_units("player"):
			for target in state.live_units("enemy"):
				if Combat.check_attack(state, "player", id, target).is_empty():
					Combat.attack(state, "player", id, target)
		for id in state.units:
			var u: Dictionary = state.units[id]
			assert_true(u["strength"] >= 0 and u["strength"] <= u["max_strength"], "efetivo dentro de [0, máx]")
			assert_true(u["morale"] >= 0 and u["morale"] <= u["max_morale"], "moral dentro de [0, máx]")
		Turns.end_turn(state, "player")
		Turns.end_turn(state, "enemy")


# --- Aleatoriedade com semente ------------------------------------------------------

func _random_duel_losses(seed_value: int) -> Array:
	var state := new_battle(true, 0.1)
	state.rng.seed = seed_value
	var a := put(state, "infantry", "A", "player", 3, 3)
	var b := put(state, "infantry", "B", "enemy", 4, 3)
	var result := Combat.attack(state, "player", a, b)
	return [result["losses"], result["counter_losses"]]


func test_variation_is_reproducible_by_seed() -> void:
	assert_eq(_random_duel_losses(42), _random_duel_losses(42), "mesma semente, mesmo resultado")
	var seen := {}
	for s in range(1, 30):
		seen[_random_duel_losses(s)[0]] = true
	assert_true(seen.size() > 1, "sementes diferentes variam o dano")
	for s in range(1, 30):
		var losses: int = _random_duel_losses(s)[0]
		assert_true(losses >= 99 and losses <= 121, "variação limitada a ±10%%: %d" % losses)
