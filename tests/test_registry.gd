extends "res://tests/test_case.gd"



func _valid_raw() -> Dictionary:
	var reg := Registry.new()
	assert_true(reg.load_from_dir("res://data"), "dados de exemplo devem carregar: %s" % str(reg.errors))
	return reg.raw_data.duplicate(true)


func test_sample_data_loads() -> void:
	var reg := Registry.new()
	assert_true(reg.load_from_dir("res://data"), str(reg.errors))
	assert_eq(reg.countries.size(), 3, "países")
	assert_eq(reg.provinces.size(), 9, "províncias")
	assert_eq(reg.units.size(), 3, "unidades")
	assert_eq(reg.buildings.size(), 6, "construções")
	assert_eq(reg.errors.size(), 0, "sem erros")


func test_missing_directory_fails() -> void:
	var reg := Registry.new()
	assert_true(not reg.load_from_dir("res://nao_existe"), "diretório ausente deve falhar")
	assert_has_error(reg.errors, "Arquivo ausente")


func test_duplicate_id_rejected() -> void:
	var raw := _valid_raw()
	raw["countries"].append(raw["countries"][0].duplicate(true))
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "id duplicado deve falhar")
	assert_has_error(reg.errors, "Id duplicado")


func test_unknown_owner_rejected() -> void:
	var raw := _valid_raw()
	raw["provinces"][0]["owner"] = "xxx"
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "dono inexistente deve falhar")
	assert_has_error(reg.errors, "dono inexistente")


func test_non_reciprocal_link_rejected() -> void:
	var raw := _valid_raw()
	raw["provinces"][0]["neighbors"] = []  # Paris deixa de listar Estrasburgo
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "ligação não recíproca deve falhar")
	assert_has_error(reg.errors, "não é recíproca")


func test_unknown_terrain_rejected() -> void:
	var raw := _valid_raw()
	raw["provinces"][1]["terrain"] = "lava"
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "terreno inválido deve falhar")
	assert_has_error(reg.errors, "terreno inválido")


func test_negative_resource_rejected() -> void:
	var raw := _valid_raw()
	raw["countries"][0]["starting_resources"]["gold"] = -1.0
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "recurso negativo deve falhar")
	assert_has_error(reg.errors, "valor inválido")


func test_unknown_building_requirement_rejected() -> void:
	var raw := _valid_raw()
	raw["units"][0]["requirements"]["buildings"] = ["castelo_inexistente"]
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "requisito inexistente deve falhar")
	assert_has_error(reg.errors, "id desconhecido")


func test_economy_rules_and_definitions_are_validated() -> void:
	var raw := _valid_raw()
	raw["buildings"][0]["effects"]["magia"] = 3.0
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "efeito desconhecido")
	assert_has_error(reg.errors, "efeito desconhecido")

	raw = _valid_raw()
	raw["buildings"][0].erase("buildable")
	reg = Registry.new()
	assert_true(not reg.load_from_data(raw), "buildable ausente")
	assert_has_error(reg.errors, "buildable")

	raw = _valid_raw()
	raw["units"][0]["recruit_turns"] = 0.0
	reg = Registry.new()
	assert_true(not reg.load_from_data(raw), "duração inválida")
	assert_has_error(reg.errors, "recruit_turns")

	raw = _valid_raw()
	raw["rules"].erase("manpower_rate")
	reg = Registry.new()
	assert_true(not reg.load_from_data(raw), "regra ausente")
	assert_has_error(reg.errors, "manpower_rate")


func test_recruitable_unit_and_buildable_buildings_exist_in_data() -> void:
	var reg := Registry.new()
	assert_true(reg.load_from_dir("res://data"), str(reg.errors))
	assert_true(reg.units["unit_line_inf"]["recruitable"], "infantaria de linha recrutável")
	assert_true(not reg.units["unit_light_cav"]["recruitable"], "cavalaria ainda não")
	for id in ["farm", "market", "workshop", "barracks", "fortification"]:
		assert_true(reg.buildings[id]["buildable"], "%s construível" % id)
