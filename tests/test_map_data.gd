extends "res://tests/test_case.gd"
## Geometria e consistência dos dados do mapa de campanha.

const MapGeometry := preload("res://src/provinces/map_geometry.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")


func _registry() -> Registry:
	var reg := Registry.new()
	assert_true(reg.load_from_dir("res://data"), "dados devem carregar: %s" % str(reg.errors))
	return reg


func _raw() -> Dictionary:
	return _registry().raw_data.duplicate(true)


func _load_raw(raw: Dictionary) -> Registry:
	var reg := Registry.new()
	reg.load_from_data(raw)
	return reg


func test_scope_of_sample_map() -> void:
	var reg := _registry()
	assert_eq(reg.countries.size(), 3, "3 países")
	assert_true(reg.provinces.size() >= 6 and reg.provinces.size() <= 10, "6 a 10 províncias")


func test_every_province_has_valid_owner() -> void:
	var reg := _registry()
	for id in reg.provinces:
		assert_true(reg.countries.has(reg.provinces[id]["owner"]), "dono válido em %s" % id)


func test_every_country_owns_its_capital() -> void:
	var reg := _registry()
	for id in reg.countries:
		var capital: String = reg.countries[id]["capital"]
		assert_eq(reg.provinces[capital]["owner"], id, "capital de %s pertence ao país" % id)


func test_polygons_are_valid_for_drawing_and_picking() -> void:
	var reg := _registry()
	var pmap := ProvinceMap.new()
	pmap.build(reg)
	for id in pmap.ids:
		var poly: PackedVector2Array = pmap.polygons[id]
		assert_true(poly.size() >= 3, "%s: ao menos 3 vértices" % id)
		assert_true(MapGeometry.is_simple(poly), "%s: polígono simples" % id)
		assert_true(absf(MapGeometry.signed_area(poly)) >= Registry.MIN_POLYGON_AREA, "%s: área" % id)
		assert_true(not Geometry2D.triangulate_polygon(poly).is_empty(), "%s: triangulável" % id)
		assert_true(Geometry2D.is_point_in_polygon(pmap.label_points[id], poly), "%s: rótulo dentro" % id)
		var rect := Rect2(Vector2.ZERO, pmap.size)
		assert_true(rect.encloses(MapGeometry.bounds(poly)), "%s: dentro do mapa" % id)


func test_polygons_do_not_overlap() -> void:
	var pmap := ProvinceMap.new()
	pmap.build(_registry())
	for i in pmap.ids.size():
		for j in range(i + 1, pmap.ids.size()):
			var overlap := Geometry2D.intersect_polygons(pmap.polygons[pmap.ids[i]], pmap.polygons[pmap.ids[j]])
			var area := 0.0
			for piece in overlap:
				area += absf(MapGeometry.signed_area(piece))
			assert_true(area < 1.0, "%s e %s não se sobrepõem (área %s)" % [pmap.ids[i], pmap.ids[j], area])


func test_neighbors_share_a_border() -> void:
	var reg := _registry()
	var pmap := ProvinceMap.new()
	pmap.build(reg)
	for id in reg.provinces:
		for link in reg.provinces[id]["neighbors"]:
			var segments := MapGeometry.shared_edges(pmap.polygons[id], pmap.polygons[link["id"]])
			assert_true(not segments.is_empty(), "%s e %s compartilham fronteira" % [id, link["id"]])


func test_shared_borders_are_declared_as_neighbors() -> void:
	var reg := _registry()
	var pmap := ProvinceMap.new()
	pmap.build(reg)
	for border in pmap.borders:
		var linked := false
		for link in reg.provinces[border["a"]]["neighbors"]:
			linked = linked or link["id"] == border["b"]
		assert_true(linked, "%s e %s têm fronteira comum mas não são vizinhas" % [border["a"], border["b"]])


func test_bowtie_polygon_rejected() -> void:
	var raw := _raw()
	raw["provinces"][0]["map"]["polygon"] = [[14, 52], [252, 292], [262, 30], [0, 306]]
	assert_has_error(_load_raw(raw).errors, "auto-interseção")


func test_polygon_with_too_few_points_rejected() -> void:
	var raw := _raw()
	raw["provinces"][0]["map"]["polygon"] = [[14, 52], [262, 30]]
	assert_has_error(_load_raw(raw).errors, "ao menos 3 pontos")


func test_polygon_outside_map_rejected() -> void:
	var raw := _raw()
	raw["provinces"][0]["map"]["polygon"][0] = [-5, 52]
	assert_has_error(_load_raw(raw).errors, "fora do mapa")


func test_degenerate_polygon_rejected() -> void:
	var raw := _raw()
	raw["provinces"][0]["map"]["polygon"] = [[10, 10], [20, 20], [30, 30]]
	assert_has_error(_load_raw(raw).errors, "degenerada")


func test_label_outside_polygon_rejected() -> void:
	var raw := _raw()
	raw["provinces"][0]["map"]["label"] = [900, 500]
	assert_has_error(_load_raw(raw).errors, "fora do polígono")


func test_missing_map_rejected() -> void:
	var raw := _raw()
	raw["provinces"][0].erase("map")
	assert_has_error(_load_raw(raw).errors, "'map' deve ser um objeto")


func test_neighbors_without_shared_border_rejected() -> void:
	var raw := _raw()
	# Paris (0) e Hungria (8) não se tocam, mesmo que a ligação seja declarada nos dois lados.
	raw["provinces"][0]["neighbors"].append({"id": "prov_hungary", "type": "land"})
	raw["provinces"][8]["neighbors"].append({"id": "prov_paris", "type": "land"})
	assert_has_error(_load_raw(raw).errors, "não compartilha fronteira")


func test_missing_display_names_rejected() -> void:
	var raw := _raw()
	raw["rules"]["terrain_names"].erase("forest")
	assert_has_error(_load_raw(raw).errors, "sem nome para 'forest'")


func test_no_absolute_machine_paths_in_sources() -> void:
	# Letra de unidade (C:\ ou D:/) que não faça parte de uma palavra, como o "s:/" de "res://".
	var pattern := RegEx.create_from_string("(^|[^A-Za-z])[A-Za-z]:[\\\\/]")
	var checked := 0
	for dir in ["res://src", "res://scenes", "res://data"]:
		for path in _files_under(dir):
			if path.get_extension() in ["gd", "tscn", "json"]:
				checked += 1
				var text := FileAccess.get_file_as_string(path)
				assert_true(pattern.search(text) == null, "caminho absoluto em %s" % path)
	assert_true(checked > 10, "arquivos verificados: %d" % checked)


func _files_under(dir: String) -> PackedStringArray:
	var result := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		result.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		result.append_array(_files_under(dir.path_join(d)))
	return result
