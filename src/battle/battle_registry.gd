extends RefCounted
## Carrega e valida os dados da batalha tática (data/battle/). Separado do Registry da campanha:
## os dados de teste da batalha não se misturam com os dados permanentes do jogo.

const DEFAULT_SCENARIO := "test_battle"
const DATA_DIR := "res://data/battle"
const SIDES: Array[String] = ["player", "enemy"]
const EDGES: Array[String] = ["west", "east"]

const RULE_KEYS: Array[String] = [
	"default_max_turns", "variation", "melee_rate", "ranged_rate", "retaliation_factor", "max_loss_fraction",
	"charge_min_steps", "morale_loss_per_casualty_percent", "morale_hit_penalty", "morale_melee_extra_penalty",
	"ally_death_radius", "ally_death_morale_penalty", "morale_recovery", "morale_recovery_routing",
	"shaken_threshold", "rally_threshold", "rout_threshold",
	"shaken_attack_multiplier", "shaken_defense_multiplier", "routing_defense_multiplier",
]

var terrains: Dictionary = {}    # id -> definição
var unit_types: Dictionary = {}  # id -> definição
var rules: Dictionary = {}
var scenarios: Dictionary = {}   # id -> cenário
var errors: PackedStringArray = PackedStringArray()


func load_from_dir(dir_path: String = DATA_DIR) -> bool:
	_reset()
	var raw := {"scenarios": []}
	for entry in [["terrains", "terrain.json"], ["unit_types", "unit_types.json"], ["rules", "battle_rules.json"]]:
		var parsed: Variant = _read_json(dir_path.path_join(entry[1]))
		if parsed == null:
			return false
		raw[entry[0]] = parsed
	var scenario_dir := dir_path.path_join("scenarios")
	for file in DirAccess.get_files_at(scenario_dir):
		if file.ends_with(".json"):
			var scenario: Variant = _read_json(scenario_dir.path_join(file))
			if scenario == null:
				return false
			raw["scenarios"].append(scenario)
	return load_from_data(raw)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("Arquivo ausente: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		errors.append("JSON inválido: %s" % path)
	return parsed


## Valida e indexa. raw = {terrains: [], unit_types: [], rules: {}, scenarios: []}.
func load_from_data(raw: Dictionary) -> bool:
	_reset()
	for key in ["terrains", "unit_types", "rules", "scenarios"]:
		if not raw.has(key):
			errors.append("Seção ausente: %s" % key)
	if not errors.is_empty():
		return false
	terrains = _index(raw["terrains"], "terreno")
	unit_types = _index(raw["unit_types"], "tipo de unidade")
	for id in terrains:
		_validate_terrain(terrains[id])
	for id in unit_types:
		_validate_unit_type(unit_types[id])
	_validate_rules(raw["rules"])
	rules = raw["rules"] if typeof(raw["rules"]) == TYPE_DICTIONARY else {}
	scenarios = _index(raw["scenarios"], "cenário")
	if errors.is_empty():
		for id in scenarios:
			_validate_scenario(scenarios[id])
	return errors.is_empty()


func _reset() -> void:
	terrains = {}
	unit_types = {}
	rules = {}
	scenarios = {}
	errors = PackedStringArray()


func _index(entries: Variant, label: String) -> Dictionary:
	var result := {}
	if typeof(entries) != TYPE_ARRAY:
		errors.append("Lista de %s deve ser um array" % label)
		return result
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("id")) != TYPE_STRING or (entry["id"] as String).is_empty():
			errors.append("Entrada de %s sem id válido" % label)
		elif result.has(entry["id"]):
			errors.append("Id duplicado (%s): %s" % [label, entry["id"]])
		else:
			result[entry["id"]] = entry
	return result


func _validate_terrain(t: Dictionary) -> void:
	var ctx := "terreno %s" % t["id"]
	_string(t, "name", ctx)
	if typeof(t.get("legend")) != TYPE_STRING or (t["legend"] as String).length() != 1:
		errors.append("%s: legend deve ser um único caractere" % ctx)
	if typeof(t.get("passable")) != TYPE_BOOL:
		errors.append("%s: passable deve ser booleano" % ctx)
	elif t["passable"]:
		_number(t, "move_cost", ctx, 1.0)
	_number(t, "defense_bonus", ctx, 0.0)
	if typeof(t.get("color")) != TYPE_STRING or not Color.html_is_valid(t["color"]):
		errors.append("%s: cor inválida" % ctx)


func _validate_unit_type(u: Dictionary) -> void:
	var ctx := "tipo %s" % u["id"]
	_string(u, "name", ctx)
	for field in ["attack", "defense", "move_range", "attack_range", "min_range", "max_strength", "max_morale"]:
		_number(u, field, ctx, 1.0)
	_number(u, "charge_bonus", ctx, 0.0)
	for field in ["melee", "can_retaliate", "can_attack_after_move"]:
		if typeof(u.get(field)) != TYPE_BOOL:
			errors.append("%s: %s deve ser booleano" % [ctx, field])
	if typeof(u.get("attack_range")) == TYPE_FLOAT and typeof(u.get("min_range")) == TYPE_FLOAT \
			and u["min_range"] > u["attack_range"]:
		errors.append("%s: min_range maior que attack_range" % ctx)


func _validate_rules(r: Variant) -> void:
	if typeof(r) != TYPE_DICTIONARY:
		errors.append("battle_rules deve ser um objeto")
		return
	for key in RULE_KEYS:
		_number(r, key, "regras", 0.0)
	if errors.is_empty() and not (r["rout_threshold"] < r["rally_threshold"] and r["rally_threshold"] <= r["shaken_threshold"]):
		errors.append("regras: esperado rout_threshold < rally_threshold <= shaken_threshold")
	if errors.is_empty() and not (r["max_loss_fraction"] > 0.0 and r["max_loss_fraction"] <= 1.0):
		errors.append("regras: max_loss_fraction deve estar em (0, 1]")


## Valida um cenário fornecido em memória (mesmo formato dos arquivos de scenarios/) contra os terrenos,
## tipos e regras JÁ carregados neste registro. Não cadastra o cenário e não altera `errors`.
## Devolve a lista de problemas; vazia = válido.
func validate_scenario(scenario: Variant) -> PackedStringArray:
	var saved := errors
	errors = PackedStringArray()
	if typeof(scenario) != TYPE_DICTIONARY:
		errors.append("cenário deve ser um dicionário")
	elif terrains.is_empty() or unit_types.is_empty() or rules.is_empty():
		errors.append("registro de batalha não carregado (terrenos, tipos de unidade ou regras ausentes)")
	else:
		_validate_scenario(scenario)
	var found := errors
	errors = saved
	return found


func _validate_scenario(s: Dictionary) -> void:
	var ctx := "cenário %s" % str(s.get("id", "(sem id)"))
	_string(s, "id", ctx)
	_string(s, "name", ctx)
	_number(s, "seed", ctx, 0.0)
	_number(s, "max_turns", ctx, 1.0)
	var rows: Variant = s.get("map", {}).get("rows") if typeof(s.get("map")) == TYPE_DICTIONARY else null
	var legend := {}
	for id in terrains:
		legend[terrains[id]["legend"]] = id
	var width := 0
	if typeof(rows) != TYPE_ARRAY or (rows as Array).is_empty():
		errors.append("%s: map.rows deve ser uma lista de linhas" % ctx)
		return
	width = str(rows[0]).length()
	for row in rows:
		if typeof(row) != TYPE_STRING or (row as String).length() != width:
			errors.append("%s: todas as linhas do mapa devem ser texto e ter a mesma largura" % ctx)
			return
		for ch in row:
			if not legend.has(ch):
				errors.append("%s: caractere de terreno desconhecido '%s'" % [ctx, ch])
	var sides: Variant = s.get("sides")
	if typeof(sides) != TYPE_DICTIONARY:
		errors.append("%s: sides deve ser um objeto" % ctx)
		return
	var edges := []
	for side in SIDES:
		var info: Variant = sides.get(side)
		if typeof(info) != TYPE_DICTIONARY:
			errors.append("%s: lado '%s' ausente" % [ctx, side])
			continue
		_string(info, "name", "%s/%s" % [ctx, side])
		if typeof(info.get("color")) != TYPE_STRING or not Color.html_is_valid(info["color"]):
			errors.append("%s/%s: cor inválida" % [ctx, side])
		if not _is_one_of(info.get("home_edge"), EDGES):
			errors.append("%s/%s: home_edge inválida" % [ctx, side])
		edges.append(info.get("home_edge"))
	if edges.size() == 2 and edges[0] == edges[1]:
		errors.append("%s: os lados devem ter bordas de origem diferentes" % ctx)
	_validate_scenario_units(s, ctx, rows, legend, width)


func _validate_scenario_units(s: Dictionary, ctx: String, rows: Array, legend: Dictionary, width: int) -> void:
	if typeof(s.get("units")) != TYPE_ARRAY:
		errors.append("%s: units deve ser uma lista" % ctx)
		return
	var taken := {}
	var per_side := {"player": 0, "enemy": 0}
	for u in s["units"]:
		if typeof(u) != TYPE_DICTIONARY:
			errors.append("%s: unidade inválida" % ctx)
			continue
		var label := "%s/%s" % [ctx, str(u.get("name"))]
		_string(u, "name", ctx)
		if not _is_one_of(u.get("side"), SIDES):
			errors.append("%s: lado inválido" % label)
			continue
		per_side[u["side"]] += 1
		if not unit_types.has(u.get("type")):
			errors.append("%s: tipo desconhecido (%s)" % [label, str(u.get("type"))])
		if u.has("source_id") and (not _is_number(u["source_id"]) or u["source_id"] < 0 or u["source_id"] != floorf(u["source_id"])):
			errors.append("%s: source_id deve ser um inteiro >= 0" % label)
		var at: Variant = u.get("at")
		if typeof(at) != TYPE_ARRAY or (at as Array).size() != 2 \
				or not _is_number(at[0]) or not _is_number(at[1]) \
				or at[0] < 0 or at[0] >= width or at[1] < 0 or at[1] >= rows.size():
			errors.append("%s: posição 'at' inválida ou fora do mapa" % label)
			continue
		if at[0] != floorf(at[0]) or at[1] != floorf(at[1]):
			errors.append("%s: posição 'at' deve ter coordenadas inteiras" % label)
			continue
		var terrain_id: String = legend[str(rows[int(at[1])])[int(at[0])]]
		if not terrains[terrain_id]["passable"]:
			errors.append("%s: posicionada em terreno intransponível" % label)
		if taken.has(Vector2i(int(at[0]), int(at[1]))):
			errors.append("%s: posição já ocupada" % label)
		taken[Vector2i(int(at[0]), int(at[1]))] = true
		if unit_types.has(u.get("type")):
			var def: Dictionary = unit_types[u["type"]]
			for field in ["strength", "morale"]:
				if u.has(field) and (not _is_number(u[field]) or u[field] < 1 or u[field] > def["max_" + field]):
					errors.append("%s: %s fora dos limites" % [label, field])
	for side in SIDES:
		if per_side[side] == 0:
			errors.append("%s: o lado '%s' não tem unidades" % [ctx, side])


## `value in lista` só para textos: valores de outro tipo (ou ausentes) não são buscados na lista tipada.
func _is_one_of(value: Variant, options: Array[String]) -> bool:
	return typeof(value) == TYPE_STRING and value in options


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


func _string(d: Dictionary, field: String, ctx: String) -> void:
	if typeof(d.get(field)) != TYPE_STRING or (d[field] as String).is_empty():
		errors.append("%s: campo '%s' ausente ou vazio" % [ctx, field])


func _number(d: Dictionary, field: String, ctx: String, min_value: float) -> void:
	var value: Variant = d.get(field)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s: campo '%s' deve ser numérico" % [ctx, field])
	elif value < min_value:
		errors.append("%s: campo '%s' menor que %s" % [ctx, field, min_value])
