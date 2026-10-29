extends "res://tests/battle_case.gd"
## Camada adaptadora campanha -> batalha (src/integration/): BattleRequest e BattleScenarioBuilder.
## Tudo em memória, sem interface: o encontro nasce do código real da campanha (ArmyActions.move_army).

const ArmyActions := preload("res://src/units/army_actions.gd")
const Builder := preload("res://src/integration/battle_scenario_builder.gd")
const Request := preload("res://src/integration/battle_request.gd")

const PROVINCE := "prov_strasbourg"  # província da França (terreno estratégico: river_valley)


# --- Fixtures ---------------------------------------------------------------------------------

func _mapping() -> Dictionary:
	var loaded := Builder.load_mapping()
	assert_true(loaded["ok"], "mapeamento real deve carregar: %s" % str(loaded["errors"]))
	return loaded["mapping"].duplicate(true)


## Exército que fica na província (como o inimigo já presente).
func _army_in(game: Dictionary, owner_id: String, types: Array, province_id: String = PROVINCE) -> int:
	var state = game["state"]
	var army_id: int = state.create_army("Exército %d de %s" % [state.next_army_id, owner_id], owner_id, province_id)
	for type_id in types:
		state.armies[army_id]["units"].append(state.add_unit(game["registry"], type_id, owner_id, province_id))
	return army_id


## Exército da França criado em Paris e MOVIDO para a província: o encontro é registrado pelo código real.
func _fra_army_arriving(game: Dictionary, types: Array) -> int:
	var army_id := _army_in(game, "fra", types, "prov_paris")
	var moved := ArmyActions.move_army(game["registry"], game["state"], "fra", army_id, PROVINCE)
	assert_true(moved["ok"], moved["message"])
	return army_id


## Encontro padrão: 2 batalhões e 1 cavalaria da França contra 1 batalhão e 1 bateria da Áustria.
func _encounter(game: Dictionary) -> int:
	_army_in(game, "aus", ["unit_line_inf", "unit_field_art"])
	_fra_army_arriving(game, ["unit_line_inf", "unit_line_inf", "unit_light_cav"])
	assert_eq(game["state"].encounters.size(), 1, "um encontro registrado")
	return game["state"].encounters[0]["id"]


func _build(game: Dictionary, encounter_id: int, mapping: Dictionary = {}, battle_registry: BattleRegistry = null) -> Dictionary:
	var m: Dictionary = mapping if not mapping.is_empty() else _mapping()
	var br: BattleRegistry = battle_registry if battle_registry != null else battle_registry()
	return Builder.build(game["registry"], game["state"], br, m, encounter_id)


func _assert_fails(result: Dictionary, fragment: String, label: String) -> void:
	assert_true(not result["ok"], "%s: deve falhar" % label)
	assert_has_error(result["errors"], fragment, label)
	assert_true(result["scenario"].is_empty(), "%s: nenhum cenário parcial" % label)
	assert_true(not result["message"].is_empty(), "%s: mensagem legível" % label)


# --- Conversão válida --------------------------------------------------------------------------------

func test_valid_encounter_becomes_a_valid_tactical_scenario() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var result := _build(game, encounter_id)
	assert_true(result["ok"], result["message"])
	var scenario: Dictionary = result["scenario"]
	assert_eq(scenario["id"], "campaign_encounter_%d" % encounter_id, "id do cenário")
	assert_eq(scenario["name"], "Batalha em Alsácia", "nome com a província")
	assert_eq(scenario["max_turns"], 40, "limite de turnos tático")
	assert_eq(scenario["sides"]["player"]["name"], "França", "lado do jogador")
	assert_eq(scenario["sides"]["player"]["home_edge"], "west", "jogador a oeste")
	assert_eq(scenario["sides"]["enemy"]["name"], "Áustria", "adversário")
	assert_eq(scenario["sides"]["enemy"]["home_edge"], "east", "adversário a leste")
	assert_eq(scenario["sides"]["player"]["color"], game["registry"].countries["fra"]["color"], "cor do país")
	assert_eq(scenario["map"]["rows"].size(), 9, "9 linhas")
	assert_eq(scenario["units"].size(), 5, "3 unidades da França + 2 da Áustria")
	assert_eq(result["request"]["encounter_id"], encounter_id, "o pedido guarda o encontro")
	assert_eq(result["errors"].size(), 0, "sem erros")


func test_scenario_is_accepted_by_the_tactical_validator_and_state() -> void:
	var game := new_game()
	var result := _build(game, _encounter(game))
	var br := battle_registry()
	assert_eq(br.validate_scenario(result["scenario"]), PackedStringArray(), "validador tático existente aceita")
	var state := BattleState.new()
	assert_true(state.setup_from_scenario(br, result["scenario"]), str(state.setup_errors))
	assert_eq(state.units.size(), 5, "unidades criadas")
	assert_true(not br.scenarios.has(result["scenario"]["id"]), "o cenário continua sem estar cadastrado")
	for id in state.units:
		assert_true(state.map.is_passable(state.units[id]["pos"]), "toda unidade nasce em hexágono transitável")


func test_generated_scenario_failing_the_tactical_validator_is_reported() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var br := battle_registry()
	br.rules = br.rules.duplicate()
	br.rules["default_max_turns"] = 0  # o validador tático recusa max_turns < 1
	var result := _build(game, encounter_id, {}, br)
	_assert_fails(result, "Cenário gerado inválido", "validador tático")
	assert_has_error(result["errors"], "max_turns", "o motivo do validador é repassado")


# --- source_id e correspondência -----------------------------------------------------------------------

func test_each_tactical_unit_matches_its_campaign_unit_by_source_id() -> void:
	var game := new_game()
	var state = game["state"]
	var result := _build(game, _encounter(game))
	var seen := {}
	for u in result["scenario"]["units"]:
		var source_id: int = u["source_id"]
		assert_true(source_id >= 1 and not seen.has(source_id), "source_id válido e único: %d" % source_id)
		seen[source_id] = true
		var campaign_unit: Dictionary = state.unit_by_id(source_id)
		assert_true(not campaign_unit.is_empty(), "a unidade de origem existe")
		var expected_side := "player" if campaign_unit["owner"] == "fra" else "enemy"
		assert_eq(u["side"], expected_side, "lado = país do dono")
		var category: String = game["registry"].units[campaign_unit["type"]]["category"]
		assert_eq(battle_registry().unit_types[u["type"]]["campaign_category"], category, "tipo tático = categoria da unidade")
		assert_true(("#%d" % source_id) in u["name"], "o nome identifica a instância")
	assert_eq(seen.size(), 5, "todas as unidades participantes, nenhuma descartada")
	var request: Dictionary = result["request"]
	for source_id in seen:
		assert_true(request["unit_army"].has(source_id), "o pedido liga a unidade ao exército de origem")
		assert_eq(state.army_of_unit(source_id), request["unit_army"][source_id], "exército de origem correto")
	assert_eq(request["sides"]["player"]["country"], "fra", "país do jogador")
	assert_eq(request["sides"]["enemy"]["country"], "aus", "país adversário")
	assert_eq(request["units"][request["sides"]["player"]["units"][0]]["owner"], "fra", "instantâneo por unidade")


func test_type_conversion_examples() -> void:
	var game := new_game()
	var result := _build(game, _encounter(game))
	var by_campaign_type := {}
	for info in result["conversion"]:
		by_campaign_type[info["campaign_type"]] = info["tactical_type"]
	assert_eq(by_campaign_type["unit_line_inf"], "infantry", "Infantaria de linha -> infantaria")
	assert_eq(by_campaign_type["unit_light_cav"], "cavalry", "Cavalaria ligeira -> cavalaria")
	assert_eq(by_campaign_type["unit_field_art"], "artillery", "Artilharia de campanha -> artilharia")


# --- Força e moral -------------------------------------------------------------------------------------------

func test_strength_and_morale_are_taken_from_the_campaign_units() -> void:
	var game := new_game()
	var state = game["state"]
	var enemy_army := _army_in(game, "aus", ["unit_line_inf"])
	var army := _army_in(game, "fra", ["unit_line_inf", "unit_light_cav"], "prov_paris")
	var wounded: int = state.armies[army]["units"][0]
	state.unit_by_id(wounded)["strength"] = 320
	state.unit_by_id(wounded)["morale"] = 55
	ArmyActions.move_army(game["registry"], state, "fra", army, PROVINCE)
	var result := _build(game, state.encounters[0]["id"])
	assert_true(result["ok"], result["message"])
	var tactical: Dictionary = {}
	for u in result["scenario"]["units"]:
		tactical[u["source_id"]] = u
	assert_eq(tactical[wounded]["strength"], 320, "efetivo atual preservado (não o máximo)")
	assert_eq(tactical[wounded]["morale"], 55, "moral atual preservada, sem reescalar")
	var cavalry: int = state.armies[army]["units"][1]
	assert_eq(tactical[cavalry]["strength"], 200, "cavalaria: 200")
	assert_eq(tactical[cavalry]["morale"], 65, "moral inicial da cavalaria (65), não 100")
	var enemy_unit: int = state.armies[enemy_army]["units"][0]
	assert_eq(tactical[enemy_unit]["morale"], 70, "moral inicial da infantaria (70)")
	for info in result["conversion"]:
		if info["source_id"] == wounded:
			assert_true(not info["strength_clamped"] and not info["morale_clamped"], "sem limitação")
	var scenario_state := BattleState.new()
	assert_true(scenario_state.setup_from_scenario(battle_registry(), result["scenario"]), "cenário jogável")
	var tactical_unit: Dictionary = {}
	for id in scenario_state.units:
		if scenario_state.units[id]["source_id"] == wounded:
			tactical_unit = scenario_state.units[id]
	assert_eq(tactical_unit["strength"], 320, "no estado tático: efetivo atual")
	assert_eq(tactical_unit["max_strength"], 500, "e o máximo vem do tipo tático")
	assert_eq(tactical_unit["morale"], 55, "e a moral da campanha")
	assert_eq(tactical_unit["attack"], 6.0, "ataque dos dados táticos")


func test_values_above_the_tactical_maximum_are_clamped_and_reported() -> void:
	var game := new_game()
	var state = game["state"]
	var encounter_id := _encounter(game)
	var unit_id: int = state.armies[state.armies_in(PROVINCE, "fra")[0]]["units"][0]
	state.unit_by_id(unit_id)["strength"] = 900
	state.unit_by_id(unit_id)["morale"] = 150
	var result := _build(game, encounter_id)
	assert_true(result["ok"], result["message"])
	for info in result["conversion"]:
		if info["source_id"] == unit_id:
			assert_eq(info["strength"], 500, "efetivo limitado ao máximo do tipo")
			assert_eq(info["morale"], 100, "moral limitada ao máximo do tipo")
			assert_true(info["strength_clamped"] and info["morale_clamped"], "a limitação é informada")
			assert_eq(info["strength_campaign"], 900, "o valor original fica registrado")


func test_invalid_strength_or_morale_is_rejected_instead_of_dropping_the_unit() -> void:
	for field in ["strength", "morale"]:
		for bad in [0, -5]:
			var game := new_game()
			var state = game["state"]
			var encounter_id := _encounter(game)
			var unit_id: int = state.armies[state.armies_in(PROVINCE, "fra")[0]]["units"][0]
			state.unit_by_id(unit_id)[field] = bad
			var result := _build(game, encounter_id)
			_assert_fails(result, "%s inválid" % ("efetivo" if field == "strength" else "moral"), "%s = %d" % [field, bad])
			assert_has_error(result["errors"], "Unidade %d" % unit_id, "o erro identifica a unidade")


# --- Terreno e mapa ----------------------------------------------------------------------------------------------

func _count(rows: Array, ch: String) -> int:
	var total := 0
	for row in rows:
		total += str(row).count(ch)
	return total


func test_every_strategic_terrain_has_a_tactical_representation() -> void:
	var expected_dominant := {"plains": ".", "hills": "h", "mountains": "h", "forest": "f"}
	for terrain_id in expected_dominant:
		var game := new_game()
		game["registry"].provinces[PROVINCE]["terrain"] = terrain_id
		var result := _build(game, _encounter(game))
		assert_true(result["ok"], "%s: %s" % [terrain_id, result["message"]])
		var rows: Array = result["scenario"]["map"]["rows"]
		var share := float(_count(rows, expected_dominant[terrain_id])) / 108.0
		assert_true(share >= 0.7, "%s: terreno tático predominante '%s' (%.0f%%)" % [terrain_id, expected_dominant[terrain_id], share * 100.0])
		assert_eq(_count(rows, "~"), 0, "%s: sem água" % terrain_id)
	var plains := new_game()
	var plains_rows: Array = _build(plains, _encounter(plains))["scenario"]["map"]["rows"]
	assert_true(_count(plains_rows, "f") + _count(plains_rows, "h") > 0, "planície: com algumas áreas de floresta ou colina")


func test_river_valley_has_a_river_with_fords() -> void:
	var game := new_game()
	assert_eq(game["registry"].provinces[PROVINCE]["terrain"], "river_valley", "a província do teste é vale fluvial")
	var result := _build(game, _encounter(game))
	assert_true(result["ok"], result["message"])
	var rows: Array = result["scenario"]["map"]["rows"]
	for row in rows.size():
		var ch := str(rows[row])[6]
		assert_eq(ch, "." if row == 3 or row == 6 else "~", "linha %d: rio na coluna 6, vaus nas linhas 3 e 6" % row)
	assert_eq(_count(rows, "~"), 7, "7 hexágonos de água")
	for row in rows:
		for col in [0, 1, 10, 11]:
			assert_true(str(row)[col] != "~", "nenhuma água nas zonas de implantação")
	var state := BattleState.new()
	assert_true(state.setup_from_scenario(battle_registry(), result["scenario"]), "jogável")
	var water := 0
	for hex in state.map.all_hexes():
		if not state.map.is_passable(hex):
			water += 1
	assert_eq(water, 7, "o rio existe no mapa tático (hexágonos intransponíveis)")


func test_generation_is_reproducible_and_depends_on_the_encounter() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var first := _build(game, encounter_id)
	var second := _build(game, encounter_id)
	assert_eq(first["scenario"], second["scenario"], "mesmo encontro e dados: cenário idêntico")
	assert_eq(first["conversion"], second["conversion"], "mesma conversão")
	var other := new_game()
	_encounter(other)
	other["state"].encounters[0]["id"] = encounter_id + 6
	var changed := _build(other, encounter_id + 6)
	assert_true(changed["ok"], changed["message"])
	assert_eq(first["scenario"]["seed"], 1000 + encounter_id, "semente = seed_salt + id do encontro")
	assert_eq(changed["scenario"]["seed"], 1000 + encounter_id + 6, "outro encontro, outra semente")
	assert_true(first["scenario"]["map"]["rows"] != changed["scenario"]["map"]["rows"], "outro encontro: mapa diferente")
	assert_eq(first["scenario"]["units"].size(), changed["scenario"]["units"].size(), "mesmas unidades")


# --- Implantação ----------------------------------------------------------------------------------------------------------

func test_deployment_slots_are_deterministic_center_first() -> void:
	var west := Builder.deployment_slots("player", 12, 9, 2)
	var east := Builder.deployment_slots("enemy", 12, 9, 2)
	assert_eq(west.size(), 18, "2 colunas x 9 linhas")
	assert_eq(east.size(), 18, "idem para o inimigo")
	assert_eq(west[0], Vector2i(1, 4), "primeiro espaço: coluna interna, linha central")
	assert_eq(west[1], Vector2i(1, 3), "depois a linha acima (empate: menor linha)")
	assert_eq(west[2], Vector2i(1, 5), "e a abaixo")
	assert_eq(west[9], Vector2i(0, 4), "esgotada a coluna interna, passa à externa")
	assert_eq(east[0], Vector2i(10, 4), "inimigo: coluna interna da borda leste")
	assert_eq(east[9], Vector2i(11, 4), "e depois a externa")
	for slot in west:
		assert_true(slot.x <= 1, "jogador só nas 2 primeiras colunas a oeste")
	for slot in east:
		assert_true(slot.x >= 10, "inimigo só nas 2 últimas colunas a leste")


func test_units_are_deployed_by_sorted_ids_not_by_accidental_order() -> void:
	var game := new_game()
	var state = game["state"]
	var enemy_army := _army_in(game, "aus", ["unit_line_inf", "unit_line_inf", "unit_line_inf"])
	var army := _fra_army_arriving(game, ["unit_line_inf", "unit_line_inf", "unit_light_cav"])
	state.armies[army]["units"].reverse()        # ordem "acidental" na lista do exército
	state.armies[enemy_army]["units"].reverse()
	var result := _build(game, state.encounters[0]["id"])
	assert_true(result["ok"], result["message"])
	var player_ids := []
	var enemy_ids := []
	for u in result["scenario"]["units"]:
		(player_ids if u["side"] == "player" else enemy_ids).append(u["source_id"])
	var sorted_player := player_ids.duplicate()
	sorted_player.sort()
	var sorted_enemy := enemy_ids.duplicate()
	sorted_enemy.sort()
	assert_eq(player_ids, sorted_player, "unidades do jogador em ordem crescente de id")
	assert_eq(enemy_ids, sorted_enemy, "unidades do inimigo em ordem crescente de id")
	var first: Dictionary = result["scenario"]["units"][0]
	assert_eq(first["at"], [1, 4], "a primeira unidade ocupa o primeiro espaço")
	for u in result["scenario"]["units"]:
		var col: int = u["at"][0]
		assert_true(col <= 1 if u["side"] == "player" else col >= 10, "implantação na borda do próprio lado")


func test_army_limit_per_side_is_enforced_without_discarding_units() -> void:
	var game := new_game()
	_army_in(game, "aus", ["unit_line_inf"])
	for i in 4:
		_fra_army_arriving(game, ["unit_line_inf", "unit_line_inf", "unit_line_inf", "unit_line_inf"])  # 16
	_fra_army_arriving(game, ["unit_line_inf", "unit_light_cav"])  # 18: exatamente o limite
	var encounter_id: int = game["state"].encounters[0]["id"]
	var ok := _build(game, encounter_id)
	assert_true(ok["ok"], "18 unidades cabem: %s" % ok["message"])
	assert_eq(ok["scenario"]["units"].size(), 19, "18 + 1 do inimigo")
	_fra_army_arriving(game, ["unit_line_inf"])  # 19
	var over := _build(game, encounter_id)
	_assert_fails(over, "limite tático é 18", "19 unidades")
	assert_has_error(over["errors"], "19 unidades", "informa a quantidade")
	assert_has_error(over["errors"], "Nenhuma unidade foi descartada", "não descarta silenciosamente")


# --- Encontros inválidos ----------------------------------------------------------------------------------------------------

func test_unknown_encounter_is_rejected() -> void:
	var game := new_game()
	_encounter(game)
	_assert_fails(_build(game, 999), "inexistente", "encontro 999")
	assert_true(not Request.build(game["registry"], game["state"], 999)["ok"], "o pedido também recusa")


func test_invalid_encounters_are_rejected() -> void:
	var cases := [
		["província inexistente", func(g: Dictionary) -> void: g["state"].encounters[0]["province"] = "prov_x", "Província do encontro inexistente"],
		["um país só", func(g: Dictionary) -> void: g["state"].encounters[0]["countries"] = ["fra"], "exatamente 2 países"],
		["país desconhecido", func(g: Dictionary) -> void: g["state"].encounters[0]["countries"] = ["fra", "xxx"], "País desconhecido"],
		["países ausentes", func(g: Dictionary) -> void: g["state"].encounters[0]["countries"] = "fra", "não lista os países"],
		["sem exércitos", func(g: Dictionary) -> void: g["state"].encounters[0]["armies"] = [], "não lista exércitos"],
		["exército inexistente", func(g: Dictionary) -> void: g["state"].encounters[0]["armies"].append(9999), "Exército 9999 do encontro não existe"],
		["exército repetido", func(g: Dictionary) -> void: g["state"].encounters[0]["armies"].append(g["state"].encounters[0]["armies"][0]), "mais de uma vez"],
		["id de exército inválido", func(g: Dictionary) -> void: g["state"].encounters[0]["armies"].append("a"), "Id de exército inválido"],
		["exército em outra província", func(g: Dictionary) -> void: g["state"].armies[g["state"].encounters[0]["armies"][0]]["province"] = "prov_paris", "não está na província do encontro"],
		["exército de terceiro país", func(g: Dictionary) -> void: g["state"].armies[g["state"].encounters[0]["armies"][0]]["owner"] = "bav", "não participa do encontro"],
		["exército sem unidades", func(g: Dictionary) -> void: g["state"].armies[g["state"].encounters[0]["armies"][0]]["units"] = [], "não tem unidades"],
		["jogador fora do encontro", func(g: Dictionary) -> void: g["state"].player_country_id = "bav", "não participa do encontro"],
	]
	for c in cases:
		var game := new_game()
		var encounter_id := _encounter(game)
		c[1].call(game)
		_assert_fails(_build(game, encounter_id), c[2], c[0])


func test_encounter_with_more_than_two_countries_is_rejected() -> void:
	var game := new_game()
	_army_in(game, "aus", ["unit_line_inf"])
	_army_in(game, "bav", ["unit_line_inf"])
	_fra_army_arriving(game, ["unit_line_inf"])
	var encounter: Dictionary = game["state"].encounters[0]
	assert_eq(encounter["countries"], ["aus", "bav", "fra"], "o encontro real tem 3 países")
	_assert_fails(_build(game, encounter["id"]), "exatamente 2 países", "3 países")


func test_army_listed_in_two_pending_encounters_is_rejected() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var other: Dictionary = game["state"].encounters[0].duplicate(true)
	other["id"] = encounter_id + 1  # outro encontro pendente que lista os mesmos exércitos
	game["state"].encounters.append(other)
	_assert_fails(_build(game, encounter_id), "também consta de outro encontro pendente", "exército em dois encontros")


func test_side_without_units_is_rejected() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	for army_id in game["state"].encounters[0]["armies"]:
		if game["state"].armies[army_id]["owner"] == "aus":
			game["state"].armies[army_id]["units"] = []
	_assert_fails(_build(game, encounter_id), "não tem unidades", "exército inimigo vazio")


# --- Unidades e ids de origem -------------------------------------------------------------------------------------------------

func _apply_unit_defect(kind: String, game: Dictionary, army: Dictionary) -> void:
	var state = game["state"]
	var first: int = army["units"][0]
	match kind:
		"inexistente":
			army["units"].append(99999)
		"zero":
			state.unit_by_id(first)["id"] = 0
			army["units"][0] = 0
		"negativo":
			state.unit_by_id(first)["id"] = -3
			army["units"][0] = -3
		"repetida":
			army["units"].append(first)
		"colisao":
			state.units.append(state.unit_by_id(first).duplicate())
		"dono":
			state.unit_by_id(first)["owner"] = "aus"
		"tipo":
			state.unit_by_id(first)["type"] = "unit_dragao"


func test_invalid_and_duplicate_source_ids_are_rejected() -> void:
	var cases := [
		["inexistente", "unidade 99999 inexistente"],
		["zero", "id de unidade inválido (0)"],
		["negativo", "id de unidade inválido (-3)"],
		["repetida", "já pertence ao exército"],
		["colisao", "colide"],
		["dono", "pertence a aus"],
		["tipo", "tipo desconhecido"],
	]
	for c in cases:
		var game := new_game()
		var encounter_id := _encounter(game)
		var army: Dictionary = game["state"].armies[game["state"].armies_in(PROVINCE, "fra")[0]]
		_apply_unit_defect(c[0], game, army)
		_assert_fails(_build(game, encounter_id), c[1], "defeito '%s'" % c[0])


func test_unit_in_two_armies_is_rejected() -> void:
	var game := new_game()
	var state = game["state"]
	_army_in(game, "aus", ["unit_line_inf"])
	var army_a := _fra_army_arriving(game, ["unit_line_inf"])
	var army_b := _fra_army_arriving(game, ["unit_line_inf"])
	var encounter_id: int = state.encounters[0]["id"]
	state.armies[army_a]["units"].append(state.armies[army_b]["units"][0])  # a mesma unidade em dois exércitos
	_assert_fails(_build(game, encounter_id), "já pertence ao exército", "unidade em dois exércitos")


# --- Categorias e terrenos sem mapeamento ----------------------------------------------------------------------------------------------

func test_unit_with_unmapped_category_is_rejected_for_every_unit() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	game["registry"].units["unit_line_inf"]["category"] = "navy"
	var result := _build(game, encounter_id)
	_assert_fails(result, "categoria 'navy' sem tipo tático", "categoria desconhecida")
	assert_eq(result["errors"].size(), 3, "um erro por unidade afetada (3 batalhões): nada é descartado em silêncio")


func test_tactical_type_without_campaign_category_or_ambiguous_is_rejected() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var br := battle_registry()
	br.unit_types["cavalry"].erase("campaign_category")
	_assert_fails(_build(game, encounter_id, {}, br), "'cavalry' sem tipo tático", "categoria sem tipo")
	br = battle_registry()
	br.unit_types["cavalry"]["campaign_category"] = "infantry"
	_assert_fails(_build(game, encounter_id, {}, br), "ambígua", "categoria ambígua")


func test_unknown_strategic_terrain_is_an_error_not_plains() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	game["registry"].provinces[PROVINCE]["terrain"] = "lava"
	_assert_fails(_build(game, encounter_id), "Terreno estratégico sem mapeamento: 'lava'", "terreno desconhecido")


func test_mapping_missing_a_strategic_terrain_is_rejected() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var mapping := _mapping()
	mapping["terrains"].erase("forest")
	_assert_fails(_build(game, encounter_id, mapping), "sem mapeamento: 'forest'", "mapeamento incompleto")


func test_invalid_mapping_is_rejected() -> void:
	var game := new_game()
	var br := battle_registry()
	assert_has_error(Builder.validate_mapping(5, game["registry"], br), "deve ser um objeto", "não é objeto")
	var cases := [
		["seed_salt negativo", func(m: Dictionary) -> void: m["seed_salt"] = -1, "seed_salt"],
		["mapa pequeno", func(m: Dictionary) -> void: m["map"]["width"] = 2, "map.width"],
		["sem colunas de implantação", func(m: Dictionary) -> void: m["deployment"]["columns"] = 0, "deployment.columns"],
		["borda não suportada", func(m: Dictionary) -> void: m["deployment"]["player_edge"] = "north", "player_edge"],
		["largura insuficiente", func(m: Dictionary) -> void: m["map"]["width"] = 5, "pequena demais"],
		["terreno de campanha desconhecido", func(m: Dictionary) -> void: m["terrains"]["lava"] = m["terrains"]["plains"].duplicate(true), "desconhecido na campanha"],
		["base intransponível", func(m: Dictionary) -> void: m["terrains"]["plains"]["base"] = "water", "transitável"],
		["feature desconhecida", func(m: Dictionary) -> void: m["terrains"]["plains"]["features"][0]["terrain"] = "lava", "cada feature"],
		["chances acima de 1", func(m: Dictionary) -> void: m["terrains"]["plains"]["features"][0]["chance"] = 0.99, "passa de 1"],
		["rio na zona de implantação", func(m: Dictionary) -> void: m["terrains"]["river_valley"]["river"]["column"] = 1, "invade uma zona"],
		["vau fora do mapa", func(m: Dictionary) -> void: m["terrains"]["river_valley"]["river"]["fords"] = [99], "vau fora do mapa"],
		["rio incompleto", func(m: Dictionary) -> void: m["terrains"]["river_valley"]["river"].erase("fords"), "river precisa"],
	]
	for c in cases:
		var mapping := _mapping()
		c[1].call(mapping)
		assert_has_error(Builder.validate_mapping(mapping, game["registry"], br), c[2], c[0])


func test_real_mapping_file_is_valid_and_missing_file_is_reported() -> void:
	var game := new_game()
	assert_eq(Builder.validate_mapping(_mapping(), game["registry"], battle_registry()), PackedStringArray(), "mapeamento real válido")
	var missing := Builder.load_mapping("res://data/battle/nao_existe.json")
	assert_true(not missing["ok"], "arquivo ausente")
	assert_has_error(missing["errors"], "ausente", "mensagem")
	var categories := Builder.category_types(game["registry"], battle_registry())
	assert_true(categories["ok"], str(categories["errors"]))
	assert_eq(categories["map"], {"infantry": "infantry", "cavalry": "cavalry", "artillery": "artillery"}, "categoria -> tipo tático")


func test_unloaded_tactical_registry_is_reported() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	_assert_fails(_build(game, encounter_id, {}, BattleRegistry.new()), "não carregado", "registro tático vazio")


# --- A campanha não é tocada ----------------------------------------------------------------------------------------------------------------

func test_building_a_scenario_never_modifies_the_campaign() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	var state_before: Dictionary = game["state"].to_dict()
	var registry_before: Dictionary = {
		"provinces": game["registry"].provinces.duplicate(true),
		"units": game["registry"].units.duplicate(true),
		"countries": game["registry"].countries.duplicate(true),
	}
	var ok := _build(game, encounter_id)
	assert_true(ok["ok"], ok["message"])
	assert_eq(game["state"].to_dict(), state_before, "estado da campanha idêntico depois de converter")
	assert_eq(game["state"].encounters.size(), 1, "o encontro continua pendente (não foi consumido)")
	for army_id in game["state"].encounters[0]["armies"]:
		assert_eq(game["state"].armies[army_id]["moved"], state_before["armies"][army_id]["moved"], "exércitos não foram travados nem liberados")
	assert_eq(game["registry"].provinces, registry_before["provinces"], "registro de províncias intacto")
	assert_eq(game["registry"].units, registry_before["units"], "registro de unidades intacto")
	assert_eq(game["registry"].countries, registry_before["countries"], "registro de países intacto")
	# O cenário gerado é independente da campanha: alterar a campanha depois não o muda.
	var entry: Dictionary = ok["scenario"]["units"][0]
	var strength_in_scenario: int = entry["strength"]
	game["state"].unit_by_id(entry["source_id"])["strength"] = 1
	assert_eq(entry["strength"], strength_in_scenario, "o cenário não compartilha dados com a campanha")


func test_failed_builds_do_not_modify_the_campaign_either() -> void:
	var game := new_game()
	var encounter_id := _encounter(game)
	game["state"].player_country_id = "bav"
	var before: Dictionary = game["state"].to_dict()
	assert_true(not _build(game, encounter_id)["ok"], "recusado")
	assert_eq(game["state"].to_dict(), before, "estado intacto mesmo na recusa")
