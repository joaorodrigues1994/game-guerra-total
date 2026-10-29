extends RefCounted
## Pedido de batalha: lê um ENCONTRO PENDENTE da campanha e valida tudo o que a batalha precisa
## (encontro, província, exatamente 2 países, exércitos, unidades). É SOMENTE LEITURA: não consome o
## encontro, não trava exércitos e não altera força, moral, províncias nem turnos.
##
## Convenção de retorno: {ok: bool, request: Dictionary, errors: PackedStringArray, message: String}
## (message = erros unidos; vazio se ok). O pedido (`request`) é o instantâneo que as etapas seguintes
## usarão para reconciliar o resultado:
##   encounter_id, province_id, countries [jogador, adversário]
##   sides: {player|enemy: {country, armies [ids ordenados], units [ids ordenados por exército e id]}}
##   unit_army: {id da unidade -> id do exército de origem}
##   units: {id da unidade -> {type, category, owner, strength, morale}}   (valores ANTES da batalha)
##
## Regras (D1): um encontro pendente é o gatilho; só batalhas com exatamente 2 países, um deles o do jogador.


static func find_encounter(state: RefCounted, encounter_id: int) -> Dictionary:
	for encounter in state.encounters:
		if encounter.get("id") == encounter_id:
			return encounter
	return {}


static func build(registry: RefCounted, state: RefCounted, encounter_id: int) -> Dictionary:
	var encounter := find_encounter(state, encounter_id)
	if encounter.is_empty():
		return _result({}, PackedStringArray(["Encontro #%d inexistente ou já resolvido." % encounter_id]))

	var errors := PackedStringArray()
	var province_id := str(encounter.get("province", ""))
	if not registry.provinces.has(province_id) or not state.provinces.has(province_id):
		errors.append("Província do encontro inexistente: '%s'." % province_id)

	var countries := _distinct_countries(encounter, registry, errors)
	if countries.size() != 2:
		return _result({}, errors)
	var player_country: String = state.player_country_id
	if not (player_country in countries):
		errors.append("O país do jogador (%s) não participa do encontro: batalha entre terceiros ainda não é suportada." % player_country)
		return _result({}, errors)

	var enemy_country: String = countries[0] if countries[1] == player_country else countries[1]
	var side_of := {player_country: "player", enemy_country: "enemy"}
	var request := {
		"encounter_id": encounter_id,
		"province_id": province_id,
		"countries": [player_country, enemy_country],
		"sides": {
			"player": {"country": player_country, "armies": [], "units": []},
			"enemy": {"country": enemy_country, "armies": [], "units": []},
		},
		"unit_army": {},
		"units": {},
	}
	_collect_armies(registry, state, encounter, province_id, side_of, request, errors)
	for side in ["player", "enemy"]:
		if request["sides"][side]["units"].is_empty() and errors.is_empty():
			errors.append("O lado %s (%s) não tem exército com unidades no encontro." % [side, request["sides"][side]["country"]])
	return _result(request if errors.is_empty() else {}, errors)


## Países distintos do encontro (exatamente 2, ambos existentes). Problemas vão para `errors`.
static func _distinct_countries(encounter: Dictionary, registry: RefCounted, errors: PackedStringArray) -> Array:
	var raw: Variant = encounter.get("countries")
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		errors.append("O encontro não lista os países envolvidos.")
		return result
	for country_id in raw:
		if typeof(country_id) != TYPE_STRING or not registry.countries.has(country_id):
			errors.append("País desconhecido no encontro: '%s'." % str(country_id))
		elif not (country_id in result):
			result.append(country_id)
	if errors.is_empty() and result.size() != 2:
		errors.append("O encontro precisa envolver exatamente 2 países (envolve %d)." % result.size())
	return result


static func _collect_armies(registry: RefCounted, state: RefCounted, encounter: Dictionary, province_id: String,
		side_of: Dictionary, request: Dictionary, errors: PackedStringArray) -> void:
	var army_ids: Array[int] = []
	var raw: Variant = encounter.get("armies")
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		errors.append("O encontro não lista exércitos.")
		return
	for army_id in raw:
		if typeof(army_id) != TYPE_INT:
			errors.append("Id de exército inválido no encontro: %s." % str(army_id))
		elif army_id in army_ids:
			errors.append("Exército %d listado mais de uma vez no encontro." % army_id)
		else:
			army_ids.append(army_id)
	army_ids.sort()

	# Quantas instâncias existem por id no estado: mais de uma = colisão de ids de origem.
	var instances := {}
	for unit in state.units:
		instances[unit["id"]] = instances.get(unit["id"], 0) + 1

	for army_id in army_ids:
		if not state.armies.has(army_id):
			errors.append("Exército %d do encontro não existe." % army_id)
			continue
		var army: Dictionary = state.armies[army_id]
		var label := "Exército %d (%s)" % [army_id, army["name"]]
		if army["province"] != province_id:
			errors.append("%s não está na província do encontro (%s)." % [label, army["province"]])
		if not side_of.has(army["owner"]):
			errors.append("%s pertence a %s, que não participa do encontro." % [label, army["owner"]])
			continue
		for other in state.encounters:
			if other.get("id") != encounter.get("id") and army_id in other.get("armies", []):
				errors.append("%s também consta de outro encontro pendente (#%s): ambíguo." % [label, str(other.get("id"))])
		if army["units"].is_empty():
			errors.append("%s não tem unidades." % label)
			continue
		var side: String = side_of[army["owner"]]
		request["sides"][side]["armies"].append(army_id)
		var unit_ids: Array[int] = []
		for unit_id in army["units"]:
			unit_ids.append(unit_id)
		unit_ids.sort()
		for unit_id in unit_ids:
			_collect_unit(registry, state, army, unit_id, instances, request, side, label, errors)


static func _collect_unit(registry: RefCounted, state: RefCounted, army: Dictionary, unit_id: int, instances: Dictionary,
		request: Dictionary, side: String, label: String, errors: PackedStringArray) -> void:
	if unit_id < 1:
		errors.append("%s: id de unidade inválido (%d); ids de origem devem ser >= 1." % [label, unit_id])
		return
	if request["unit_army"].has(unit_id):
		errors.append("%s: unidade %d já pertence ao exército %d." % [label, unit_id, request["unit_army"][unit_id]])
		return
	var count: int = instances.get(unit_id, 0)
	if count == 0:
		errors.append("%s: unidade %d inexistente." % [label, unit_id])
		return
	if count > 1:
		errors.append("%s: id de unidade %d colide: existem %d instâncias com esse id." % [label, unit_id, count])
		return
	var unit: Dictionary = state.unit_by_id(unit_id)
	if unit["owner"] != army["owner"]:
		errors.append("%s: unidade %d pertence a %s, não ao dono do exército (%s)." % [label, unit_id, unit["owner"], army["owner"]])
		return
	if not registry.units.has(unit["type"]):
		errors.append("%s: unidade %d com tipo desconhecido '%s'." % [label, unit_id, str(unit["type"])])
		return
	request["unit_army"][unit_id] = army["id"]
	request["sides"][side]["units"].append(unit_id)
	request["units"][unit_id] = {
		"type": unit["type"],
		"category": registry.units[unit["type"]]["category"],
		"owner": unit["owner"],
		"strength": unit["strength"],
		"morale": unit["morale"],
	}


static func _result(request: Dictionary, errors: PackedStringArray) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"request": request,
		"errors": errors,
		"message": "; ".join(errors),
	}
