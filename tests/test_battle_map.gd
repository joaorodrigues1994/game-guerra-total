extends "res://tests/battle_case.gd"
## Dados da batalha, mapa de terrenos e caminhos de custo mínimo.

const BattleMap := preload("res://src/battle/battle_map.gd")
const Pathfinding := preload("res://src/battle/battle_pathfinding.gd")


# --- Dados ---------------------------------------------------------------------

func _raw() -> Dictionary:
	var registry := battle_registry()
	var raw := {
		"terrains": registry.terrains.values(),
		"unit_types": registry.unit_types.values(),
		"rules": registry.rules.duplicate(true),
		"scenarios": registry.scenarios.values(),
	}
	return raw.duplicate(true)


func _errors(raw: Dictionary) -> PackedStringArray:
	var registry := BattleRegistry.new()
	assert_true(not registry.load_from_data(raw), "dados inválidos devem falhar")
	return registry.errors


func test_battle_data_loads() -> void:
	var registry := battle_registry()
	assert_eq(registry.terrains.size(), 4, "4 terrenos")
	assert_eq(registry.unit_types.size(), 3, "3 tipos militares")
	assert_true(registry.scenarios.has("test_battle"), "cenário de teste")
	assert_eq(registry.scenarios["test_battle"]["units"].size(), 10, "10 unidades no cenário")
	for id in ["plains", "forest", "hills", "water"]:
		assert_true(registry.terrains.has(id), "terreno %s" % id)


func test_battle_data_is_separate_from_campaign_data() -> void:
	var campaign := Registry.new()
	assert_true(campaign.load_from_dir("res://data"), str(campaign.errors))
	assert_true(not campaign.units.has("infantry"), "tipos táticos não entram no registro da campanha")
	assert_true(FileAccess.file_exists("res://data/battle/unit_types.json"), "dados da batalha em data/battle/")


func test_invalid_battle_data_is_rejected() -> void:
	var raw := _raw()
	raw["scenarios"][0]["map"]["rows"][2] = "...."
	assert_has_error(_errors(raw), "mesma largura")

	raw = _raw()
	raw["scenarios"][0]["map"]["rows"][0] = "ff....~...hX"
	assert_has_error(_errors(raw), "caractere de terreno desconhecido")

	raw = _raw()
	raw["scenarios"][0]["units"][0]["at"] = [6, 0]  # água
	assert_has_error(_errors(raw), "intransponível")

	raw = _raw()
	raw["scenarios"][0]["units"][1]["at"] = raw["scenarios"][0]["units"][0]["at"]
	assert_has_error(_errors(raw), "já ocupada")

	raw = _raw()
	raw["scenarios"][0]["units"][0]["type"] = "dragao"
	assert_has_error(_errors(raw), "tipo desconhecido")

	raw = _raw()
	raw["scenarios"][0]["units"][0]["at"] = [99, 0]
	assert_has_error(_errors(raw), "fora do mapa")

	raw = _raw()
	raw["rules"]["rout_threshold"] = 60.0
	assert_has_error(_errors(raw), "rout_threshold")

	raw = _raw()
	raw["unit_types"][2]["min_range"] = 9.0
	assert_has_error(_errors(raw), "min_range maior")

	raw = _raw()
	raw["scenarios"][0]["sides"]["enemy"]["home_edge"] = "west"
	assert_has_error(_errors(raw), "bordas de origem diferentes")

	raw = _raw()
	raw["scenarios"][0]["units"] = raw["scenarios"][0]["units"].filter(func(u: Dictionary) -> bool: return u["side"] == "player")
	assert_has_error(_errors(raw), "não tem unidades")


# --- Mapa ----------------------------------------------------------------------

func test_map_dimensions_and_terrain_layout() -> void:
	var state := new_battle()
	var map: BattleMap = state.map
	assert_eq(map.width, 12, "largura")
	assert_eq(map.height, 9, "altura")
	assert_eq(map.all_hexes().size(), 108, "108 hexágonos")
	assert_eq(map.terrain_id_at(hx(0, 0)), "forest", "floresta no canto")
	assert_eq(map.terrain_id_at(hx(6, 0)), "water", "rio")
	assert_eq(map.terrain_id_at(hx(10, 0)), "hills", "colina")
	assert_eq(map.terrain_id_at(hx(5, 3)), "plains", "planície")
	assert_eq(map.terrain_id_at(hx(6, 3)), "plains", "vau do rio")
	assert_eq(map.terrain_id_at(Vector2i(99, 99)), "", "fora do mapa")
	assert_true(not map.in_bounds(Vector2i(-5, -5)), "fora dos limites")


func test_terrain_properties() -> void:
	var map: BattleMap = new_battle().map
	assert_eq(map.move_cost(hx(5, 3)), 1, "planície custa 1")
	assert_eq(map.move_cost(hx(0, 0)), 2, "floresta custa 2")
	assert_eq(map.move_cost(hx(10, 0)), 2, "colina custa 2")
	assert_eq(map.move_cost(hx(6, 0)), 0, "água sem custo (intransponível)")
	assert_true(not map.is_passable(hx(6, 0)) and map.is_passable(hx(5, 0)), "água bloqueia")
	assert_true(not map.is_passable(Vector2i(50, 50)), "fora do mapa não é transitável")
	assert_eq(map.defense_bonus(hx(5, 3)), 0.0, "planície sem bônus")
	assert_eq(map.defense_bonus(hx(0, 0)), 0.3, "floresta +30%")
	assert_eq(map.defense_bonus(hx(10, 0)), 0.2, "colina +20%")


func test_map_neighbors_stay_inside_the_grid() -> void:
	var map: BattleMap = new_battle().map
	assert_eq(map.neighbors(hx(5, 4)).size(), 6, "hexágono interno tem 6 vizinhos")
	assert_true(map.neighbors(hx(0, 0)).size() < 6, "canto tem menos vizinhos")
	for hex in map.all_hexes():
		for n in map.neighbors(hex):
			assert_true(map.in_bounds(n), "vizinho dentro do mapa")


func test_edges() -> void:
	var map: BattleMap = new_battle().map
	assert_eq(map.edge_hexes("west").size(), 9, "borda oeste inteira transitável")
	assert_eq(map.edge_hexes("east").size(), 9, "borda leste inteira transitável")
	assert_true(map.is_edge(hx(0, 4), "west") and not map.is_edge(hx(1, 4), "west"), "borda oeste")
	assert_true(map.is_edge(hx(11, 7), "east") and not map.is_edge(hx(10, 7), "east"), "borda leste")
	for hex in map.edge_hexes("west"):
		assert_eq(Hex.axial_to_offset(hex).x, 0, "coluna 0")


# --- Caminhos ------------------------------------------------------------------

func test_path_cost_uses_terrain_not_straight_distance() -> void:
	var state := new_battle()
	var start := hx(2, 3)
	var reach := Pathfinding.reachable(state.map, start, 10, {})
	var plain_target := hx(4, 3)  # 2 hexágonos de planície
	assert_eq(reach["cost"][plain_target], Hex.distance(start, plain_target) * 1, "planície: custo = distância")
	# (1,4) e (2,4) são colinas (custo 2): entrar em uma colina custa 2, mesmo a 1 hexágono de distância.
	var hill := hx(2, 4)
	assert_eq(Hex.distance(start, hill), 1, "colina adjacente")
	assert_eq(reach["cost"][hill], 2, "mas custa 2")


func test_path_avoids_water_and_goes_through_the_ford() -> void:
	var state := new_battle()
	var start := hx(4, 1)
	var goal := hx(8, 1)
	var reach := Pathfinding.reachable(state.map, start, 100, {})
	var path := Pathfinding.path_to(reach["prev"], start, goal)
	assert_true(not path.is_empty() and path[0] == start and path[-1] == goal, "caminho existe de ponta a ponta")
	for hex in path:
		assert_true(state.map.is_passable(hex), "o caminho nunca pisa em água")
	var straight := Hex.distance(start, goal)
	assert_true(reach["cost"][goal] > straight, "o desvio pelo vau custa mais que a linha reta (%d > %d)" % [reach["cost"][goal], straight])
	var ford_rows := []
	for hex in path:
		var offset := Hex.axial_to_offset(hex)
		if offset.x == 6:
			ford_rows.append(offset.y)
	assert_true(ford_rows.size() >= 1, "o caminho cruza a coluna do rio")
	for row in ford_rows:
		assert_true(row == 3 or row == 6, "e só pelos vaus (linhas 3 e 6), não pela água: linha %d" % row)


func test_budget_limits_reachable_hexes() -> void:
	var state := new_battle()
	var start := hx(2, 3)
	var reach := Pathfinding.reachable(state.map, start, 3, {})
	for hex in reach["cost"]:
		assert_true(reach["cost"][hex] <= 3, "custo dentro do orçamento")
	assert_true(not reach["cost"].has(hx(8, 3)), "destino distante fora do alcance")
	assert_eq(Pathfinding.reachable(state.map, start, 0, {})["cost"].size(), 1, "orçamento 0: só o próprio hexágono")


func test_blocked_hexes_cannot_be_crossed_or_entered() -> void:
	var state := new_battle()
	var start := hx(2, 3)
	var wall := {}
	for n in state.map.neighbors(start):
		wall[n] = true
	var reach := Pathfinding.reachable(state.map, start, 10, wall)
	assert_eq(reach["cost"].size(), 1, "cercada por unidades: não sai do lugar")
	assert_eq(Pathfinding.path_to(reach["prev"], start, hx(5, 3)), [] as Array[Vector2i], "sem caminho")


func test_paths_are_deterministic_and_contiguous() -> void:
	var state := new_battle()
	var start := hx(1, 1)
	var goal := hx(5, 6)
	var first := Pathfinding.path_to(Pathfinding.reachable(state.map, start, 100, {})["prev"], start, goal)
	var second := Pathfinding.path_to(Pathfinding.reachable(state.map, start, 100, {})["prev"], start, goal)
	assert_eq(first, second, "mesmo caminho em execuções repetidas")
	for i in range(1, first.size()):
		assert_eq(Hex.distance(first[i - 1], first[i]), 1, "passos contíguos")


func test_distance_field_wraps_around_water() -> void:
	var state := new_battle()
	var target := hx(8, 1)
	var field := Pathfinding.distance_field(state.map, target)
	assert_eq(field[target], 0, "alvo com custo 0")
	assert_true(not field.has(hx(6, 0)), "água fora do campo")
	assert_true(field[hx(5, 1)] > Hex.distance(hx(5, 1), target), "do outro lado do rio o custo é maior que a distância")
