extends RefCounted
## Ações do jogador na campanha: construir e recrutar.
## Toda ação valida ANTES de alterar o estado: se algo falhar, o estado permanece intacto
## e o motivo é devolvido em português. Resultado: {ok: bool, message: String}.

const EconomyCalculator := preload("res://src/economy/economy_calculator.gd")


# --- Construção -----------------------------------------------------------------

## Texto do motivo pelo qual a construção não pode ser iniciada; "" se puder.
static func check_build(registry: RefCounted, state: RefCounted, country_id: String,
		province_id: String, building_id: String) -> String:
	if not state.provinces.has(province_id):
		return "Província inexistente."
	if not registry.buildings.has(building_id):
		return "Construção inexistente."
	var def: Dictionary = registry.buildings[building_id]
	var province: Dictionary = state.provinces[province_id]
	if province["owner"] != country_id:
		return "Você não controla esta província."
	if not def["buildable"]:
		return "%s ainda não está disponível." % def["name"]
	if building_id in province["buildings"]:
		return "A província já possui %s." % def["name"]
	for entry in province["constructions"]:
		if entry["building"] == building_id:
			return "%s já está em construção." % def["name"]
	var limit := int(registry.rules["max_concurrent_constructions"])
	if province["constructions"].size() >= limit:
		return "Fila de construção cheia (máximo de %d por província)." % limit
	var missing_buildings := _missing_buildings(registry, province, def["requires"])
	if not missing_buildings.is_empty():
		return "Requer: %s." % ", ".join(missing_buildings)
	return _check_cost(registry, state, country_id, def["cost"])


static func start_construction(registry: RefCounted, state: RefCounted, country_id: String,
		province_id: String, building_id: String) -> Dictionary:
	var reason := check_build(registry, state, country_id, province_id, building_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var def: Dictionary = registry.buildings[building_id]
	_pay(state, country_id, def["cost"])
	state.provinces[province_id]["constructions"].append(
		{"building": building_id, "remaining": int(def["build_turns"])})
	return {"ok": true, "message": "Construção iniciada: %s em %s (%d turnos, custo: %s)." % [
		def["name"], registry.provinces[province_id]["name"], int(def["build_turns"]),
		format_amounts(registry, def["cost"])]}


# --- Recrutamento ---------------------------------------------------------------

static func check_recruit(registry: RefCounted, state: RefCounted, country_id: String,
		province_id: String, unit_id: String) -> String:
	if not state.provinces.has(province_id):
		return "Província inexistente."
	if not registry.units.has(unit_id):
		return "Unidade inexistente."
	var def: Dictionary = registry.units[unit_id]
	var province: Dictionary = state.provinces[province_id]
	if province["owner"] != country_id:
		return "Você não controla esta província."
	if not def["recruitable"]:
		return "%s ainda não pode ser recrutada." % def["name"]
	var missing_buildings := _missing_buildings(registry, province, def["requirements"]["buildings"])
	if not missing_buildings.is_empty():
		return "Requer: %s." % ", ".join(missing_buildings)
	var capacity := EconomyCalculator.recruit_capacity(registry, state, province_id)
	if province["recruitments"].size() >= capacity:
		return "Capacidade de recrutamento esgotada (%d de %d em andamento)." % [
			province["recruitments"].size(), capacity]
	return _check_cost(registry, state, country_id, def["recruit_cost"])


static func start_recruitment(registry: RefCounted, state: RefCounted, country_id: String,
		province_id: String, unit_id: String) -> Dictionary:
	var reason := check_recruit(registry, state, country_id, province_id, unit_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var def: Dictionary = registry.units[unit_id]
	_pay(state, country_id, def["recruit_cost"])
	state.provinces[province_id]["recruitments"].append(
		{"unit": unit_id, "remaining": int(def["recruit_turns"])})
	return {"ok": true, "message": "Recrutamento iniciado: %s em %s (%d turnos, custo: %s)." % [
		def["name"], registry.provinces[province_id]["name"], int(def["recruit_turns"]),
		format_amounts(registry, def["recruit_cost"])]}


# --- Apresentação e utilidades ----------------------------------------------------

## "Ouro 100 · Materiais 20" a partir de um dicionário recurso -> quantidade.
static func format_amounts(registry: RefCounted, amounts: Dictionary) -> String:
	var parts := PackedStringArray()
	for res in registry.rules["resources"]:
		if amounts.has(res) and int(amounts[res]) != 0:
			parts.append("%s %d" % [registry.rules["resource_names"][res], int(amounts[res])])
	return " · ".join(parts)


## "+4 Alimentos, +2 Bônus defensivo" para os efeitos de uma construção.
static func describe_effects(registry: RefCounted, effects: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in effects:
		var label: String = registry.rules["resource_names"].get(key, registry.rules["effect_names"].get(key, key))
		parts.append("+%d %s" % [int(effects[key]), label])
	return ", ".join(parts)


static func _missing_buildings(registry: RefCounted, province: Dictionary, required: Array) -> PackedStringArray:
	var missing := PackedStringArray()
	for building_id in required:
		if not (building_id in province["buildings"]):
			missing.append(registry.buildings[building_id]["name"])
	return missing


static func _check_cost(registry: RefCounted, state: RefCounted, country_id: String, cost: Dictionary) -> String:
	var have: Dictionary = state.resources_of(country_id)
	var lacking := PackedStringArray()
	for res in registry.rules["resources"]:
		var shortfall := int(cost.get(res, 0)) - int(have.get(res, 0))
		if shortfall > 0:
			lacking.append("%d de %s" % [shortfall, registry.rules["resource_names"][res]])
	if lacking.is_empty():
		return ""
	return "Recursos insuficientes: faltam %s." % ", ".join(lacking)


## Desconta o custo. Só deve ser chamada após _check_cost validar (nunca deixa saldo negativo).
static func _pay(state: RefCounted, country_id: String, cost: Dictionary) -> void:
	var have: Dictionary = state.resources_of(country_id)
	for res in cost:
		have[res] = int(have[res]) - int(cost[res])
		assert(have[res] >= 0, "saldo negativo após pagamento")
