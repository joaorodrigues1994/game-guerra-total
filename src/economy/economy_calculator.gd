extends RefCounted
## Cálculos econômicos puros: não alteram o estado, apenas o leem.
##
## Receita por turno de uma província controlada =
##   produção base da província (provinces.json)
##   + efeitos de recurso das construções CONCLUÍDAS (buildings.json)
##   + recrutáveis: população * rules.manpower_rate
## Despesa por turno de um país = manutenção (upkeep) das unidades que ele possui.
## O crédito/débito efetivo acontece no TurnProcessor (fase income_expenses).


static func zero_resources(registry: RefCounted) -> Dictionary:
	var result := {}
	for res in registry.rules["resources"]:
		result[res] = 0
	return result


static func province_income(registry: RefCounted, state: RefCounted, province_id: String) -> Dictionary:
	var income := zero_resources(registry)
	var base: Dictionary = registry.provinces[province_id]["production"]
	for res in base:
		income[res] += int(base[res])
	for res in registry.rules["resources"]:
		income[res] += building_effect(registry, state, province_id, res)
	var population: int = state.provinces[province_id]["population"]
	income["manpower"] += floori(population * float(registry.rules["manpower_rate"]))
	return income


## Soma da receita de todas as províncias controladas pelo país.
static func country_income(registry: RefCounted, state: RefCounted, country_id: String) -> Dictionary:
	var total := zero_resources(registry)
	for province_id in state.provinces:
		if state.provinces[province_id]["owner"] == country_id:
			var income := province_income(registry, state, province_id)
			for res in total:
				total[res] += income[res]
	return total


## Manutenção por turno das unidades que o país possui.
static func country_upkeep(registry: RefCounted, state: RefCounted, country_id: String) -> Dictionary:
	var total := zero_resources(registry)
	for unit in state.units:
		if unit["owner"] == country_id:
			var upkeep: Dictionary = registry.units[unit["type"]]["upkeep"]
			for res in upkeep:
				total[res] += int(upkeep[res])
	return total


static func net(income: Dictionary, upkeep: Dictionary) -> Dictionary:
	var result := {}
	for res in income:
		result[res] = income[res] - upkeep.get(res, 0)
	return result


## Soma de um efeito (recurso ou outro, como "defense_bonus") das construções concluídas da província.
static func building_effect(registry: RefCounted, state: RefCounted, province_id: String, effect: String) -> int:
	var total := 0
	for building_id in state.provinces[province_id]["buildings"]:
		total += int(registry.buildings[building_id]["effects"].get(effect, 0))
	return total


static func defense_bonus(registry: RefCounted, state: RefCounted, province_id: String) -> int:
	return building_effect(registry, state, province_id, "defense_bonus")


## Quantos recrutamentos simultâneos a província suporta (soma de recruit_capacity).
static func recruit_capacity(registry: RefCounted, state: RefCounted, province_id: String) -> int:
	return building_effect(registry, state, province_id, "recruit_capacity")
