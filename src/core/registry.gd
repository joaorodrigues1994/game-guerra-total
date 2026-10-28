extends RefCounted
## Carrega e valida os dados estáticos de data/*.json.
## Somente leitura e validação: nenhuma regra de jogo vive aqui.

const MapGeometry := preload("res://src/provinces/map_geometry.gd")

## Área mínima (em unidades do mapa) para um polígono não ser considerado degenerado.
const MIN_POLYGON_AREA := 500.0

const DATA_FILES := {
	"rules": "rules.json",
	"countries": "countries.json",
	"provinces": "provinces.json",
	"units": "units.json",
	"buildings": "buildings.json",
	"generals": "generals.json",
	"armies": "armies.json",
}

var rules: Dictionary = {}
var countries: Dictionary = {}  # id -> definição
var provinces: Dictionary = {}
var units: Dictionary = {}
var buildings: Dictionary = {}
var generals: Dictionary = {}
## Exércitos iniciais (lista, na ordem do arquivo). O GameState cria as instâncias.
var armies: Array = []

var errors: PackedStringArray = PackedStringArray()
## Dados brutos da última leitura de diretório (útil para testes).
var raw_data: Dictionary = {}


func load_from_dir(dir_path: String) -> bool:
	_reset()
	var raw := {}
	for key in DATA_FILES:
		var path := dir_path.path_join(DATA_FILES[key])
		if not FileAccess.file_exists(path):
			errors.append("Arquivo ausente: %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			errors.append("JSON inválido: %s" % path)
			continue
		raw[key] = parsed
	if not errors.is_empty():
		return false
	raw_data = raw
	return load_from_data(raw)


## Valida e indexa os dados. Retorna true se não houver erros.
func load_from_data(raw: Dictionary) -> bool:
	_reset()
	for key in DATA_FILES:
		if not raw.has(key):
			errors.append("Seção ausente: %s" % key)
	if not errors.is_empty():
		return false

	if not _validate_rules(raw["rules"]):
		return false
	rules = raw["rules"]

	countries = _index(raw["countries"], "país")
	provinces = _index(raw["provinces"], "província")
	units = _index(raw["units"], "unidade")
	buildings = _index(raw["buildings"], "construção")
	generals = _index(raw["generals"], "general")

	for id in buildings:
		_validate_building(buildings[id])
	for id in countries:
		_validate_country(countries[id])
	for id in provinces:
		_validate_province(provinces[id])
	for id in units:
		_validate_unit(units[id])
	for id in generals:
		_validate_general(generals[id])
	_validate_armies(raw["armies"])
	return errors.is_empty()


func _reset() -> void:
	rules = {}
	countries = {}
	provinces = {}
	units = {}
	buildings = {}
	generals = {}
	armies = []
	errors = PackedStringArray()


# --- Indexação -------------------------------------------------------------

func _index(entries: Variant, label: String) -> Dictionary:
	var result := {}
	if typeof(entries) != TYPE_ARRAY:
		errors.append("Lista de %s deve ser um array" % label)
		return result
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("Entrada de %s não é um objeto" % label)
			continue
		var id: Variant = entry.get("id")
		if typeof(id) != TYPE_STRING or (id as String).is_empty():
			errors.append("Entrada de %s sem id válido" % label)
			continue
		if result.has(id):
			errors.append("Id duplicado (%s): %s" % [label, id])
			continue
		result[id] = entry
	return result


# --- Validação por tipo ----------------------------------------------------

func _validate_rules(r: Variant) -> bool:
	if typeof(r) != TYPE_DICTIONARY:
		errors.append("rules deve ser um objeto")
		return false
	for key in ["resources", "terrains", "unit_categories", "link_types"]:
		if typeof(r.get(key)) != TYPE_ARRAY or (r[key] as Array).is_empty():
			errors.append("rules.%s deve ser uma lista não vazia" % key)
	for key in ["start_year", "start_month", "months_per_turn"]:
		if typeof(r.get(key)) != TYPE_FLOAT:
			errors.append("rules.%s deve ser numérico" % key)
	var map_size: Variant = r.get("map_size")
	if not _is_point(map_size) or map_size[0] <= 0 or map_size[1] <= 0:
		errors.append("rules.map_size deve ser [largura, altura] positivos")
	_check_number(r, "max_concurrent_constructions", "rules", 1.0)
	_check_number(r, "manpower_rate", "rules")
	_check_number(r, "max_army_units", "rules", 1.0)
	if typeof(r.get("effect_names")) != TYPE_DICTIONARY:
		errors.append("rules.effect_names deve ser um objeto")
	if errors.is_empty():
		_check_names(r, "resource_names", "resources")
		_check_names(r, "terrain_names", "terrains")
		_check_names(r, "link_type_names", "link_types")
	return errors.is_empty()


## Todo id da lista deve ter um nome de exibição no dicionário correspondente.
func _check_names(r: Dictionary, names_field: String, list_field: String) -> void:
	var names: Variant = r.get(names_field)
	if typeof(names) != TYPE_DICTIONARY:
		errors.append("rules.%s deve ser um objeto" % names_field)
		return
	for id in r[list_field]:
		if typeof(names.get(id)) != TYPE_STRING or (names[id] as String).is_empty():
			errors.append("rules.%s sem nome para '%s'" % [names_field, str(id)])


func _validate_country(c: Dictionary) -> void:
	var ctx := "país %s" % c["id"]
	_require_string(c, "name", ctx)
	var color: Variant = c.get("color")
	if typeof(color) != TYPE_STRING or not Color.html_is_valid(color):
		errors.append("%s: cor inválida" % ctx)
	var capital: Variant = c.get("capital")
	if typeof(capital) != TYPE_STRING or not provinces.has(capital):
		errors.append("%s: capital inexistente (%s)" % [ctx, str(capital)])
	_check_resource_dict(c, "starting_resources", ctx)


func _validate_province(p: Dictionary) -> void:
	var ctx := "província %s" % p["id"]
	_require_string(p, "name", ctx)
	if typeof(p.get("owner")) != TYPE_STRING or not countries.has(p["owner"]):
		errors.append("%s: dono inexistente (%s)" % [ctx, str(p.get("owner"))])
	if not (p.get("terrain") in rules["terrains"]):
		errors.append("%s: terreno inválido (%s)" % [ctx, str(p.get("terrain"))])
	for field in ["population", "economic_value", "garrison", "strategic_value"]:
		_check_number(p, field, ctx)
	_check_resource_dict(p, "production", ctx, false)
	var city: Variant = p.get("city")
	if city != null and (typeof(city) != TYPE_DICTIONARY or typeof(city.get("name")) != TYPE_STRING):
		errors.append("%s: city deve ser null ou objeto com name" % ctx)
	_check_id_list(p, "buildings", buildings, ctx)
	_validate_map(p, ctx)
	_validate_neighbors(p, ctx)


## Geometria de desenho/seleção: polígono simples dentro do mapa e rótulo dentro do polígono.
func _validate_map(p: Dictionary, ctx: String) -> void:
	var map: Variant = p.get("map")
	if typeof(map) != TYPE_DICTIONARY:
		errors.append("%s: 'map' deve ser um objeto" % ctx)
		return
	var raw_points: Variant = map.get("polygon")
	if typeof(raw_points) != TYPE_ARRAY or (raw_points as Array).size() < 3:
		errors.append("%s: map.polygon precisa de ao menos 3 pontos" % ctx)
		return
	for point in raw_points:
		if not _is_point(point):
			errors.append("%s: map.polygon com ponto inválido (esperado [x, y])" % ctx)
			return
	var poly := MapGeometry.to_polygon(raw_points)
	var size := Vector2(rules["map_size"][0], rules["map_size"][1])
	for vertex in poly:
		if vertex.x < 0.0 or vertex.y < 0.0 or vertex.x > size.x or vertex.y > size.y:
			errors.append("%s: vértice fora do mapa (%s)" % [ctx, str(vertex)])
			return
	if MapGeometry.has_duplicate_vertices(poly):
		errors.append("%s: map.polygon com vértices repetidos" % ctx)
	elif absf(MapGeometry.signed_area(poly)) < MIN_POLYGON_AREA:
		errors.append("%s: map.polygon com área degenerada" % ctx)
	elif not MapGeometry.is_simple(poly):
		errors.append("%s: map.polygon com auto-interseção" % ctx)
		return
	if not _is_point(map.get("label")) \
			or not Geometry2D.is_point_in_polygon(Vector2(map["label"][0], map["label"][1]), poly):
		errors.append("%s: map.label ausente ou fora do polígono" % ctx)


func _validate_neighbors(p: Dictionary, ctx: String) -> void:
	if typeof(p.get("neighbors")) != TYPE_ARRAY:
		errors.append("%s: neighbors deve ser uma lista" % ctx)
		return
	for link in p["neighbors"]:
		if typeof(link) != TYPE_DICTIONARY:
			errors.append("%s: vizinho inválido" % ctx)
			continue
		var other_id: Variant = link.get("id")
		var type: Variant = link.get("type")
		if other_id == p["id"]:
			errors.append("%s: vizinha de si mesma" % ctx)
		elif typeof(other_id) != TYPE_STRING or not provinces.has(other_id):
			errors.append("%s: vizinho inexistente (%s)" % [ctx, str(other_id)])
			continue
		if not (type in rules["link_types"]):
			errors.append("%s: tipo de ligação inválido (%s)" % [ctx, str(type)])
			continue
		if not _has_link(provinces[other_id], p["id"], type):
			errors.append("%s: ligação com %s não é recíproca" % [ctx, other_id])
		elif not _share_border(p, provinces[other_id]):
			errors.append("%s: não compartilha fronteira com %s" % [ctx, other_id])


## Verdadeiro quando os polígonos (se válidos) têm ao menos uma aresta em comum.
func _share_border(a: Dictionary, b: Dictionary) -> bool:
	var poly_a := _polygon_of(a)
	var poly_b := _polygon_of(b)
	if poly_a.size() < 3 or poly_b.size() < 3:
		return true  # geometria inválida já é reportada em _validate_map
	return not MapGeometry.shared_edges(poly_a, poly_b).is_empty()


func _polygon_of(province: Dictionary) -> PackedVector2Array:
	var map: Variant = province.get("map")
	if typeof(map) != TYPE_DICTIONARY or typeof(map.get("polygon")) != TYPE_ARRAY:
		return PackedVector2Array()
	for point in map["polygon"]:
		if not _is_point(point):
			return PackedVector2Array()
	return MapGeometry.to_polygon(map["polygon"])


func _has_link(province: Dictionary, target_id: String, type: String) -> bool:
	var links: Variant = province.get("neighbors")
	if typeof(links) != TYPE_ARRAY:
		return false
	for link in links:
		if typeof(link) == TYPE_DICTIONARY and link.get("id") == target_id and link.get("type") == type:
			return true
	return false


func _validate_unit(u: Dictionary) -> void:
	var ctx := "unidade %s" % u["id"]
	_require_string(u, "name", ctx)
	if not (u.get("category") in rules["unit_categories"]):
		errors.append("%s: categoria inválida (%s)" % [ctx, str(u.get("category"))])
	for field in ["strength", "attack", "defense", "mobility", "range", "morale", "experience"]:
		_check_number(u, field, ctx)
	_check_resource_dict(u, "recruit_cost", ctx, false)
	_check_resource_dict(u, "upkeep", ctx, false)
	_check_bool(u, "recruitable", ctx)
	_check_number(u, "recruit_turns", ctx, 1.0)
	var req: Variant = u.get("requirements")
	if typeof(req) != TYPE_DICTIONARY:
		errors.append("%s: requirements deve ser um objeto" % ctx)
	else:
		_check_id_list(req, "buildings", buildings, "%s.requirements" % ctx)


func _validate_building(b: Dictionary) -> void:
	var ctx := "construção %s" % b["id"]
	_require_string(b, "name", ctx)
	_check_number(b, "build_turns", ctx, 1.0)
	_check_resource_dict(b, "cost", ctx, false)
	_check_bool(b, "buildable", ctx)
	var effects: Variant = b.get("effects")
	if typeof(effects) != TYPE_DICTIONARY:
		errors.append("%s: effects deve ser um objeto" % ctx)
	else:
		for key in effects:
			if not (key in rules["resources"]) and not rules["effect_names"].has(key):
				errors.append("%s: efeito desconhecido (%s)" % [ctx, key])
			elif typeof(effects[key]) != TYPE_FLOAT or effects[key] < 0.0:
				errors.append("%s: valor inválido em effects.%s" % [ctx, key])
	_check_id_list(b, "requires", buildings, ctx)


func _validate_general(g: Dictionary) -> void:
	var ctx := "general %s" % g["id"]
	_require_string(g, "name", ctx)
	if typeof(g.get("nationality")) != TYPE_STRING or not countries.has(g["nationality"]):
		errors.append("%s: nacionalidade inexistente (%s)" % [ctx, str(g.get("nationality"))])
	_check_number(g, "command", ctx, 1.0)
	_check_number(g, "experience", ctx)


## Exércitos iniciais: dono, província própria, unidades conhecidas dentro do limite e general livre.
func _validate_armies(entries: Variant) -> void:
	if typeof(entries) != TYPE_ARRAY:
		errors.append("Lista de exércitos deve ser um array")
		return
	armies = entries
	var used_generals := {}
	for i in entries.size():
		var a: Variant = entries[i]
		var ctx := "exército inicial #%d" % (i + 1)
		if typeof(a) != TYPE_DICTIONARY:
			errors.append("%s: não é um objeto" % ctx)
			continue
		_require_string(a, "name", ctx)
		var owner_id: Variant = a.get("owner")
		if typeof(owner_id) != TYPE_STRING or not countries.has(owner_id):
			errors.append("%s: dono inexistente (%s)" % [ctx, str(owner_id)])
			continue
		var province_id: Variant = a.get("province")
		if typeof(province_id) != TYPE_STRING or not provinces.has(province_id):
			errors.append("%s: província inexistente (%s)" % [ctx, str(province_id)])
		elif provinces[province_id].get("owner") != owner_id:
			errors.append("%s: deve começar em província do próprio país" % ctx)
		var members: Variant = a.get("units")
		if typeof(members) != TYPE_ARRAY or (members as Array).is_empty():
			errors.append("%s: units deve ser uma lista não vazia" % ctx)
		else:
			if members.size() > int(rules["max_army_units"]):
				errors.append("%s: excede o limite de %d unidades" % [ctx, int(rules["max_army_units"])])
			for unit_id in members:
				if typeof(unit_id) != TYPE_STRING or not units.has(unit_id):
					errors.append("%s: unidade desconhecida (%s)" % [ctx, str(unit_id)])
		var general_id: Variant = a.get("general")
		if general_id != null:
			if typeof(general_id) != TYPE_STRING or not generals.has(general_id):
				errors.append("%s: general desconhecido (%s)" % [ctx, str(general_id)])
			elif generals[general_id].get("nationality") != owner_id:
				errors.append("%s: general de outra nacionalidade (%s)" % [ctx, general_id])
			elif used_generals.has(general_id):
				errors.append("%s: general já comanda outro exército (%s)" % [ctx, general_id])
			else:
				used_generals[general_id] = true


# --- Auxiliares ------------------------------------------------------------

func _require_string(d: Dictionary, field: String, ctx: String) -> void:
	if typeof(d.get(field)) != TYPE_STRING or (d[field] as String).is_empty():
		errors.append("%s: campo '%s' ausente ou vazio" % [ctx, field])


func _check_number(d: Dictionary, field: String, ctx: String, min_value: float = 0.0) -> void:
	var value: Variant = d.get(field)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s: campo '%s' deve ser numérico" % [ctx, field])
	elif value < min_value:
		errors.append("%s: campo '%s' menor que %s" % [ctx, field, min_value])


## Valida um dicionário recurso -> quantidade (>= 0, chaves conhecidas).
func _check_resource_dict(d: Dictionary, field: String, ctx: String, require_all: bool = true) -> void:
	var res: Variant = d.get(field)
	if typeof(res) != TYPE_DICTIONARY:
		errors.append("%s: '%s' deve ser um objeto" % [ctx, field])
		return
	for key in res:
		if not (key in rules["resources"]):
			errors.append("%s: recurso desconhecido em '%s' (%s)" % [ctx, field, key])
		elif typeof(res[key]) != TYPE_FLOAT or res[key] < 0.0:
			errors.append("%s: valor inválido em '%s.%s'" % [ctx, field, key])
	if require_all:
		for key in rules["resources"]:
			if not res.has(key):
				errors.append("%s: '%s' sem o recurso %s" % [ctx, field, key])


func _check_bool(d: Dictionary, field: String, ctx: String) -> void:
	if typeof(d.get(field)) != TYPE_BOOL:
		errors.append("%s: campo '%s' deve ser booleano" % [ctx, field])


func _is_point(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return false
	for coord in value:
		if typeof(coord) != TYPE_FLOAT and typeof(coord) != TYPE_INT:
			return false
	return true


func _check_id_list(d: Dictionary, field: String, known: Dictionary, ctx: String) -> void:
	var list: Variant = d.get(field)
	if typeof(list) != TYPE_ARRAY:
		errors.append("%s: '%s' deve ser uma lista" % [ctx, field])
		return
	for id in list:
		if typeof(id) != TYPE_STRING or not known.has(id):
			errors.append("%s: id desconhecido em '%s' (%s)" % [ctx, field, str(id)])
