extends RefCounted
## Converte um ENCONTRO PENDENTE da campanha em um cenário tático (dicionário no formato de
## data/battle/scenarios/, aceito por BattleState.setup_from_scenario). Camada adaptadora: depende da
## campanha (GameState/Registry) E da batalha (BattleRegistry), por isso fica fora de ambos os módulos.
## É SOMENTE LEITURA para a campanha: não inicia batalha, não consome o encontro, não trava exércitos e
## não altera força, moral, províncias nem turnos.
##
## Conversões (documentadas em docs/ARCHITECTURE.md):
##  - Tipo: categoria da unidade de campanha (units.json "category") -> tipo tático com o mesmo
##    "campaign_category" (unit_types.json). Cada categoria deve ter exatamente um tipo tático.
##  - Efetivo: o ATUAL da instância de campanha, limitado ao máximo do tipo tático (1 .. max_strength).
##  - Moral: a ATUAL da instância, sem reescalar, limitada a max_morale (1 .. max_morale).
##  - Ataque, defesa, alcance e mobilidade: dos dados táticos (a batalha é a autoridade); experiência
##    e generais não têm efeito nesta etapa.
##  - source_id: id da instância de unidade da campanha (único e >= 1).
##  - Terreno: data/battle/campaign_mapping.json (explícito e validado); mapa gerado de forma
##    determinística (semente = seed_salt + id do encontro).
##  - Implantação: jogador a oeste, adversário a leste, nas primeiras colunas de cada borda.
##
## Convenção de retorno: {ok, scenario, request, conversion, errors, message}.

const BattleRequest := preload("res://src/integration/battle_request.gd")

const MAPPING_PATH := "res://data/battle/campaign_mapping.json"


# --- Mapeamento --------------------------------------------------------------------------

## Lê data/battle/campaign_mapping.json. Devolve {ok, mapping, errors} (só trata o arquivo; a
## consistência com os registros é checada por validate_mapping).
static func load_mapping(path: String = MAPPING_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "mapping": {}, "errors": PackedStringArray(["Arquivo de mapeamento ausente: %s" % path])}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "mapping": {}, "errors": PackedStringArray(["JSON inválido ou não é um objeto: %s" % path])}
	return {"ok": true, "mapping": parsed, "errors": PackedStringArray()}


## Mapeamento tipo de campanha -> tipo tático, por categoria. Devolve {ok, map, errors}.
static func category_types(registry: RefCounted, battle_registry: RefCounted) -> Dictionary:
	var errors := PackedStringArray()
	var by_category := {}
	for type_id in battle_registry.unit_types:
		var category: Variant = battle_registry.unit_types[type_id].get("campaign_category")
		if typeof(category) != TYPE_STRING or (category as String).is_empty():
			continue
		if by_category.has(category):
			errors.append("Categoria '%s' ambígua: mais de um tipo tático (%s e %s)." % [category, by_category[category], type_id])
		else:
			by_category[category] = type_id
	for category in registry.rules["unit_categories"]:
		if not by_category.has(category):
			errors.append("Categoria de campanha '%s' sem tipo tático (campaign_category)." % category)
	return {"ok": errors.is_empty(), "map": by_category, "errors": errors}


## Valida o mapeamento contra os dois registros. Vazio = válido.
static func validate_mapping(mapping: Variant, registry: RefCounted, battle_registry: RefCounted) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(mapping) != TYPE_DICTIONARY:
		errors.append("mapeamento deve ser um objeto")
		return errors
	if not _is_int(mapping.get("seed_salt")) or mapping["seed_salt"] < 0:
		errors.append("mapeamento: seed_salt deve ser um inteiro >= 0")
	var size: Variant = mapping.get("map")
	var deployment: Variant = mapping.get("deployment")
	if typeof(size) != TYPE_DICTIONARY or not _is_int(size.get("width")) or not _is_int(size.get("height")) \
			or size["width"] < 4 or size["height"] < 1:
		errors.append("mapeamento: map.width (>= 4) e map.height (>= 1) devem ser inteiros")
		return errors
	if typeof(deployment) != TYPE_DICTIONARY or not _is_int(deployment.get("columns")) or deployment["columns"] < 1:
		errors.append("mapeamento: deployment.columns deve ser um inteiro >= 1")
		return errors
	if deployment.get("player_edge") != "west" or deployment.get("enemy_edge") != "east":
		errors.append("mapeamento: deployment só suporta player_edge='west' e enemy_edge='east'")
	var width := int(size["width"])
	var height := int(size["height"])
	var columns := int(deployment["columns"])
	if width < columns * 2 + 2:
		errors.append("mapeamento: largura %d pequena demais para 2 zonas de %d colunas e um rio no meio" % [width, columns])

	var terrains: Variant = mapping.get("terrains")
	if typeof(terrains) != TYPE_DICTIONARY:
		errors.append("mapeamento: terrains deve ser um objeto")
		return errors
	for terrain_id in registry.rules["terrains"]:
		if not terrains.has(terrain_id):
			errors.append("Terreno estratégico sem mapeamento: '%s'." % terrain_id)
	for terrain_id in terrains:
		if not (terrain_id in registry.rules["terrains"]):
			errors.append("Mapeamento de terreno desconhecido na campanha: '%s'." % terrain_id)
		elif typeof(terrains[terrain_id]) == TYPE_DICTIONARY:
			_validate_terrain_entry(str(terrain_id), terrains[terrain_id], battle_registry, width, height, columns, errors)
		else:
			errors.append("Mapeamento de '%s' deve ser um objeto." % terrain_id)
	return errors


static func _validate_terrain_entry(terrain_id: String, entry: Dictionary, battle_registry: RefCounted,
		width: int, height: int, columns: int, errors: PackedStringArray) -> void:
	var ctx := "mapeamento '%s'" % terrain_id
	if not _tactical_passable(battle_registry, entry.get("base")):
		errors.append("%s: base deve ser um terreno tático transitável (%s)." % [ctx, str(entry.get("base"))])
	var total := 0.0
	var features: Variant = entry.get("features", [])
	if typeof(features) != TYPE_ARRAY:
		errors.append("%s: features deve ser uma lista." % ctx)
		features = []
	for feature in features:
		if typeof(feature) != TYPE_DICTIONARY or not _tactical_passable(battle_registry, feature.get("terrain")) \
				or not (typeof(feature.get("chance")) in [TYPE_FLOAT, TYPE_INT]) or feature["chance"] < 0 or feature["chance"] > 1:
			errors.append("%s: cada feature precisa de terrain transitável e chance entre 0 e 1." % ctx)
		else:
			total += float(feature["chance"])
	if total > 1.0 + 0.000001:
		errors.append("%s: a soma das chances (%s) passa de 1." % [ctx, total])
	if entry.has("river"):
		var river: Variant = entry["river"]
		if typeof(river) != TYPE_DICTIONARY or not _is_int(river.get("column")) \
				or not battle_registry.terrains.has(river.get("terrain")) \
				or not _tactical_passable(battle_registry, river.get("ford_terrain")) \
				or typeof(river.get("fords")) != TYPE_ARRAY or (river["fords"] as Array).is_empty():
			errors.append("%s: river precisa de column, terrain, ford_terrain transitável e fords." % ctx)
			return
		if river["column"] < columns or river["column"] > width - columns - 1:
			errors.append("%s: a coluna do rio (%d) invade uma zona de implantação." % [ctx, river["column"]])
		for ford in river["fords"]:
			if not _is_int(ford) or ford < 0 or ford >= height:
				errors.append("%s: vau fora do mapa (%s)." % [ctx, str(ford)])


# --- Construção do cenário -------------------------------------------------------------------

## Converte o encontro em cenário tático. Não altera `state` nem os registros.
static func build(registry: RefCounted, state: RefCounted, battle_registry: RefCounted, mapping: Dictionary,
		encounter_id: int) -> Dictionary:
	if battle_registry.terrains.is_empty() or battle_registry.unit_types.is_empty() or battle_registry.rules.is_empty():
		return _fail(PackedStringArray(["Registro de batalha não carregado (terrenos, tipos ou regras ausentes)."]))
	var mapping_errors := validate_mapping(mapping, registry, battle_registry)
	if not mapping_errors.is_empty():
		return _fail(mapping_errors)
	var categories := category_types(registry, battle_registry)
	if not categories["ok"]:
		return _fail(categories["errors"])
	var requested := BattleRequest.build(registry, state, encounter_id)
	if not requested["ok"]:
		return _fail(requested["errors"])
	var request: Dictionary = requested["request"]

	var province_terrain: String = registry.provinces[request["province_id"]]["terrain"]
	if not mapping["terrains"].has(province_terrain):
		return _fail(PackedStringArray(["Terreno estratégico sem mapeamento: '%s' (província %s)." % [province_terrain, request["province_id"]]]))

	var width := int(mapping["map"]["width"])
	var height := int(mapping["map"]["height"])
	var columns := int(mapping["deployment"]["columns"])
	var limit := columns * height

	var errors := PackedStringArray()
	var conversion: Array[Dictionary] = []
	var scenario_units: Array[Dictionary] = []
	for side in ["player", "enemy"]:
		var unit_ids: Array = request["sides"][side]["units"]
		if unit_ids.size() > limit:
			errors.append("O lado %s (%s) tem %d unidades; o limite tático é %d. Nenhuma unidade foi descartada." % [
				side, request["sides"][side]["country"], unit_ids.size(), limit])
			continue
		var slots := deployment_slots(side, width, height, columns)
		for i in unit_ids.size():
			var entry := _convert_unit(registry, state, battle_registry, categories["map"], int(unit_ids[i]), side, slots[i], errors)
			if not entry.is_empty():
				scenario_units.append(entry["unit"])
				conversion.append(entry["info"])
	if not errors.is_empty():
		return _fail(errors)

	var seed_value := int(mapping["seed_salt"]) + encounter_id
	var rows := generate_rows(mapping["terrains"][province_terrain], width, height, battle_registry, seed_value)
	var scenario := {
		"id": "campaign_encounter_%d" % encounter_id,
		"name": "Batalha em %s" % registry.provinces[request["province_id"]]["name"],
		"seed": seed_value,
		"max_turns": int(battle_registry.rules["default_max_turns"]),
		"map": {"rows": rows},
		"sides": {
			"player": _side_info(registry, request["sides"]["player"]["country"], "west"),
			"enemy": _side_info(registry, request["sides"]["enemy"]["country"], "east"),
		},
		"units": scenario_units,
	}
	var scenario_errors: PackedStringArray = battle_registry.validate_scenario(scenario)
	if not scenario_errors.is_empty():
		var prefixed := PackedStringArray()
		for message in scenario_errors:
			prefixed.append("Cenário gerado inválido: %s" % message)
		return _fail(prefixed)
	return {"ok": true, "scenario": scenario, "request": request, "conversion": conversion,
		"errors": PackedStringArray(), "message": ""}


static func _fail(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "scenario": {}, "request": {}, "conversion": [], "errors": errors, "message": "; ".join(errors)}


static func _side_info(registry: RefCounted, country_id: String, edge: String) -> Dictionary:
	return {"name": registry.countries[country_id]["name"], "color": registry.countries[country_id]["color"], "home_edge": edge}


## Converte uma instância de campanha em entrada de cenário. Devolve {unit, info} ou {} (erros em `errors`).
static func _convert_unit(registry: RefCounted, state: RefCounted, battle_registry: RefCounted, category_map: Dictionary,
		unit_id: int, side: String, slot: Vector2i, errors: PackedStringArray) -> Dictionary:
	var unit: Dictionary = state.unit_by_id(unit_id)
	var def: Dictionary = registry.units[unit["type"]]
	var label := "Unidade %d (%s)" % [unit_id, def["name"]]
	var category: String = def["category"]
	if not category_map.has(category):
		errors.append("%s: categoria '%s' sem tipo tático." % [label, category])
		return {}
	var tactical_id: String = category_map[category]
	var tactical: Dictionary = battle_registry.unit_types[tactical_id]
	if typeof(unit["strength"]) != TYPE_INT or unit["strength"] < 1:
		errors.append("%s: efetivo inválido (%s); unidades destruídas não entram em batalha." % [label, str(unit["strength"])])
		return {}
	if typeof(unit["morale"]) != TYPE_INT or unit["morale"] < 1:
		errors.append("%s: moral inválida (%s); esperado um inteiro >= 1." % [label, str(unit["morale"])])
		return {}
	var strength := mini(unit["strength"], int(tactical["max_strength"]))
	var morale := mini(unit["morale"], int(tactical["max_morale"]))
	return {
		"unit": {
			"side": side,
			"type": tactical_id,
			"name": "%s #%d" % [def["name"], unit_id],
			"at": [slot.x, slot.y],
			"source_id": unit_id,
			"strength": strength,
			"morale": morale,
		},
		"info": {
			"source_id": unit_id, "side": side, "campaign_type": unit["type"], "tactical_type": tactical_id,
			"strength_campaign": unit["strength"], "strength": strength, "strength_clamped": strength != unit["strength"],
			"morale_campaign": unit["morale"], "morale": morale, "morale_clamped": morale != unit["morale"],
			"at": [slot.x, slot.y],
		},
	}


# --- Mapa e implantação ------------------------------------------------------------------------

## Linhas de texto do mapa (legend dos terrenos táticos). Determinístico para a mesma semente:
## cada hexágono consome exatamente um sorteio, na ordem linha a linha.
static func generate_rows(entry: Dictionary, width: int, height: int, battle_registry: RefCounted, seed_value: int) -> Array[String]:
	var legend := {}
	for id in battle_registry.terrains:
		legend[id] = battle_registry.terrains[id]["legend"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rows: Array[String] = []
	for row in height:
		var line := ""
		for col in width:
			var roll := rng.randf()
			var terrain_id: String = entry["base"]
			var accumulated := 0.0
			for feature in entry.get("features", []):
				accumulated += float(feature["chance"])
				if roll < accumulated:
					terrain_id = feature["terrain"]
					break
			if entry.has("river") and col == int(entry["river"]["column"]):
				terrain_id = entry["river"]["ford_terrain"] if _is_ford(entry["river"], row) else entry["river"]["terrain"]
			line += legend[terrain_id]
		rows.append(line)
	return rows


## Posições (coluna, linha) de implantação do lado, na ordem de uso: coluna mais próxima do centro primeiro
## e, em cada coluna, do centro para as pontas (exércitos pequenos ficam centralizados).
static func deployment_slots(side: String, width: int, height: int, columns: int) -> Array[Vector2i]:
	var cols: Array[int] = []
	for i in columns:
		cols.append(columns - 1 - i if side == "player" else width - columns + i)
	var rows: Array[int] = []
	for row in height:
		rows.append(row)
	var middle := (height - 1) / 2.0
	rows.sort_custom(func(a: int, b: int) -> bool:
		var da := absf(a - middle)
		var db := absf(b - middle)
		return a < b if is_equal_approx(da, db) else da < db)
	var slots: Array[Vector2i] = []
	for col in cols:
		for row in rows:
			slots.append(Vector2i(col, row))
	return slots


# --- Auxiliares ------------------------------------------------------------------------------------

## Os vaus vêm do JSON como números reais (3.0): compara como inteiros (3 in [3.0] seria falso).
static func _is_ford(river: Dictionary, row: int) -> bool:
	for ford in river["fords"]:
		if int(ford) == row:
			return true
	return false


static func _is_int(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT) or (typeof(value) == TYPE_FLOAT and value == floorf(value))


static func _tactical_passable(battle_registry: RefCounted, terrain_id: Variant) -> bool:
	return typeof(terrain_id) == TYPE_STRING and battle_registry.terrains.has(terrain_id) \
		and battle_registry.terrains[terrain_id]["passable"]
