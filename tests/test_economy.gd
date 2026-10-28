extends "res://tests/test_case.gd"
## Receitas, despesas e efeitos de construções concluídas.

const EconomyCalculator := preload("res://src/economy/economy_calculator.gd")


func test_province_income_sums_base_buildings_and_manpower() -> void:
	var game := new_game()
	var income := EconomyCalculator.province_income(game["registry"], game["state"], "prov_paris")
	assert_eq(income["gold"], 17, "12 de base + 5 do Mercado")
	assert_eq(income["food"], 8, "alimentos de base")
	assert_eq(income["materials"], 5, "materiais de base")
	assert_eq(income["manpower"], 120, "60.000 habitantes * 0,002")
	assert_eq(income["prestige"], 0, "sem prestígio")


func test_country_income_sums_owned_provinces() -> void:
	var game := new_game()
	var income := EconomyCalculator.country_income(game["registry"], game["state"], "fra")
	assert_eq(income["gold"], 22, "Paris 17 + Alsácia 5")
	assert_eq(income["food"], 14, "8 + 6")
	assert_eq(income["materials"], 8, "5 + 3")
	assert_eq(income["manpower"], 170, "120 + 50")


func test_foreign_provinces_do_not_contribute() -> void:
	var game := new_game()
	var registry = game["registry"]
	var state = game["state"]
	var fra_before := EconomyCalculator.country_income(registry, state, "fra")
	var aus_before := EconomyCalculator.country_income(registry, state, "aus")
	# Mudar o dono de uma província de Baviera para a Áustria não pode afetar a França.
	state.provinces["prov_franconia"]["owner"] = "aus"
	assert_eq(EconomyCalculator.country_income(registry, state, "fra"), fra_before, "França inalterada")
	assert_eq(EconomyCalculator.country_income(registry, state, "aus")["gold"], aus_before["gold"] + 5, "Áustria ganha a província")
	# E perder uma província tira a receita do antigo dono.
	state.provinces["prov_strasbourg"]["owner"] = "bav"
	assert_eq(EconomyCalculator.country_income(registry, state, "fra")["gold"], 17, "só Paris")


func test_completed_buildings_add_effects_but_queued_ones_do_not() -> void:
	var game := new_game()
	var registry = game["registry"]
	var state = game["state"]
	state.provinces["prov_strasbourg"]["constructions"].append({"building": "farm", "remaining": 1})
	assert_eq(EconomyCalculator.province_income(registry, state, "prov_strasbourg")["food"], 6, "em construção não rende")
	state.provinces["prov_strasbourg"]["buildings"].append("farm")
	assert_eq(EconomyCalculator.province_income(registry, state, "prov_strasbourg")["food"], 10, "concluída rende +4")
	state.provinces["prov_strasbourg"]["buildings"].append("workshop")
	assert_eq(EconomyCalculator.province_income(registry, state, "prov_strasbourg")["materials"], 6, "Oficina +3")


func test_unit_upkeep_and_net() -> void:
	var game := new_game()
	var registry = game["registry"]
	var state = game["state"]
	state.units.append({"id": 1, "type": "unit_line_inf", "owner": "fra", "province": "prov_paris", "strength": 500})
	state.units.append({"id": 2, "type": "unit_line_inf", "owner": "aus", "province": "prov_vienna", "strength": 500})
	var upkeep := EconomyCalculator.country_upkeep(registry, state, "fra")
	assert_eq(upkeep["gold"], 4, "só as unidades do próprio país")
	assert_eq(upkeep["food"], 5, "alimentos")
	var net := EconomyCalculator.net(EconomyCalculator.country_income(registry, state, "fra"), upkeep)
	assert_eq(net["gold"], 18, "22 - 4")
	assert_eq(net["food"], 9, "14 - 5")


func test_defense_bonus_and_recruit_capacity_come_from_buildings() -> void:
	var game := new_game()
	var registry = game["registry"]
	var state = game["state"]
	assert_eq(EconomyCalculator.recruit_capacity(registry, state, "prov_paris"), 2, "Quartel de Paris")
	assert_eq(EconomyCalculator.recruit_capacity(registry, state, "prov_strasbourg"), 0, "sem Quartel")
	assert_eq(EconomyCalculator.defense_bonus(registry, state, "prov_paris"), 0, "sem Fortificação")
	state.provinces["prov_paris"]["buildings"].append("fortification")
	assert_eq(EconomyCalculator.defense_bonus(registry, state, "prov_paris"), 2, "Fortificação +2")
