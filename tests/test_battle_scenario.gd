extends "res://tests/battle_case.gd"
## API de cenários em memória: BattleState.setup_from_scenario e BattleRegistry.validate_scenario.

const Combat := preload("res://src/battle/battle_combat.gd")
const Movement := preload("res://src/battle/battle_movement.gd")


## Cenário pequeno e válido, em memória (não cadastrado em lugar nenhum).
func _scenario() -> Dictionary:
	return {
		"id": "mem_test",
		"name": "Em memória",
		"seed": 7,
		"max_turns": 10,
		"map": {"rows": ["....f", "..~..", "h...."]},
		"sides": {
			"player": {"name": "Lado A", "color": "#2f55c4", "home_edge": "west"},
			"enemy": {"name": "Lado B", "color": "#b8433a", "home_edge": "east"},
		},
		"units": [
			{"side": "player", "type": "infantry", "name": "P1", "at": [0, 0], "source_id": 11, "strength": 300, "morale": 80},
			{"side": "enemy", "type": "cavalry", "name": "E1", "at": [4, 2]},
		],
	}


## Recusa esperada: o validador aponta `fragment`, o setup devolve false e o estado não é alterado.
func _assert_rejected(registry: BattleRegistry, scenario: Variant, fragment: String, label: String) -> void:
	assert_has_error(registry.validate_scenario(scenario), fragment, label)
	if typeof(scenario) == TYPE_DICTIONARY:
		var state := BattleState.new()
		assert_true(not state.setup_from_scenario(registry, scenario), "%s: setup recusado" % label)
		assert_has_error(state.setup_errors, fragment, "%s: setup_errors" % label)


# --- Inicialização válida ---------------------------------------------------------------

func test_setup_from_a_valid_in_memory_scenario() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	assert_eq(registry.validate_scenario(scenario), PackedStringArray(), "cenário válido: sem problemas")
	var state := BattleState.new()
	assert_true(state.setup_from_scenario(registry, scenario), "inicializa: %s" % str(state.setup_errors))
	assert_eq(state.setup_errors.size(), 0, "sem erros")
	assert_eq(state.scenario_id, "mem_test", "id")
	assert_eq(state.scenario_name, "Em memória", "nome")
	assert_eq(state.seed_value, 7, "semente")
	assert_eq(state.max_turns, 10, "limite de turnos")
	assert_eq(state.map.width, 5, "largura do mapa")
	assert_eq(state.map.height, 3, "altura do mapa")
	assert_eq(state.map.terrain_id_at(hx(2, 1)), "water", "terreno do cenário")
	assert_eq(state.map.terrain_id_at(hx(4, 0)), "forest", "floresta")
	assert_eq(state.units.size(), 2, "duas unidades")
	var p1: Dictionary = state.units[state.unit_at(hx(0, 0))]
	assert_eq(p1["name"], "P1", "unidade do jogador na posição indicada")
	assert_eq(p1["side"], "player", "lado")
	assert_eq(p1["strength"], 300, "efetivo do cenário")
	assert_eq(p1["morale"], 80, "moral do cenário")
	assert_eq(p1["source_id"], 11, "source_id repassado à unidade")
	assert_eq(p1["max_strength"], 500, "máximo vem do tipo")
	var e1: Dictionary = state.units[state.unit_at(hx(4, 2))]
	assert_eq(e1["type"], "cavalry", "tipo")
	assert_eq(e1["strength"], 200, "sem override: efetivo máximo do tipo")
	assert_eq(e1["source_id"], 0, "sem source_id: 0")
	assert_eq(state.active_side, "player", "começa o jogador")
	assert_eq(state.turn, 1, "turno 1")
	assert_true(not state.over, "sem resultado")


func test_in_memory_scenario_is_not_registered_and_does_not_touch_the_registry() -> void:
	var registry := battle_registry()
	var scenarios_before := registry.scenarios.duplicate(true)
	var errors_before := registry.errors
	var state := BattleState.new()
	state.setup_from_scenario(registry, _scenario())
	assert_eq(registry.scenarios, scenarios_before, "registro de cenários intacto")
	assert_true(not registry.scenarios.has("mem_test"), "não foi cadastrado")
	assert_eq(registry.errors, errors_before, "o validador não polui registry.errors")
	_assert_rejected(registry, {"id": "x"}, "campo 'name'", "cenário inválido")
	assert_eq(registry.errors, errors_before, "nem com cenário inválido")


func test_state_does_not_share_dictionaries_with_the_caller() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	var state := BattleState.new()
	state.setup_from_scenario(registry, scenario)
	scenario["sides"]["player"]["name"] = "Alterado depois"
	scenario["units"][0]["name"] = "Alterado"
	assert_eq(state.sides["player"]["name"], "Lado A", "mudar o dicionário depois não afeta a batalha")
	assert_eq(state.units[1]["name"], "P1", "nem as unidades")


# --- Método antigo ------------------------------------------------------------------------

func test_legacy_setup_by_id_is_equivalent_to_setup_from_scenario() -> void:
	var registry := battle_registry()
	var by_id := BattleState.new()
	assert_true(by_id.setup(registry, BattleRegistry.DEFAULT_SCENARIO), "setup por id")
	var by_dict := BattleState.new()
	assert_true(by_dict.setup_from_scenario(registry, registry.scenarios[BattleRegistry.DEFAULT_SCENARIO]), "setup por dicionário")
	assert_eq(by_id.to_dict(), by_dict.to_dict(), "estados idênticos (unidades, turno, semente do RNG...)")
	assert_eq(by_id.map.terrain, by_dict.map.terrain, "mesmo terreno")
	assert_eq(by_id.units.size(), 10, "as 10 unidades do cenário de teste")
	assert_eq(by_id.scenario_id, "test_battle", "id do cenário registrado")


func test_legacy_setup_with_unknown_id_fails_cleanly() -> void:
	var registry := battle_registry()
	var state := BattleState.new()
	assert_true(not state.setup(registry, "nao_existe"), "id desconhecido")
	assert_has_error(state.setup_errors, "não cadastrado", "motivo")
	assert_true(state.units.is_empty() and state.scenario_id == "", "estado vazio")


func test_setup_resets_a_battle_in_progress_for_both_entry_points() -> void:
	var registry := battle_registry()
	var state := BattleState.new()
	state.setup(registry, BattleRegistry.DEFAULT_SCENARIO)
	state.units[1]["strength"] = 1
	state.turn = 5
	state.log.append("sujeira")
	assert_true(state.setup_from_scenario(registry, _scenario()), "reinicia com outro cenário")
	assert_eq(state.turn, 1, "turno reiniciado")
	assert_eq(state.units.size(), 2, "só as unidades do novo cenário")
	assert_true(state.log.is_empty(), "registro limpo")
	assert_true(state.setup(registry, BattleRegistry.DEFAULT_SCENARIO), "e volta ao cenário cadastrado")
	assert_eq(state.units.size(), 10, "10 unidades")
	assert_eq(state.units[1]["strength"], 500, "efetivo restaurado")


# --- Campos obrigatórios ---------------------------------------------------------------------

func test_missing_required_fields_are_rejected() -> void:
	var registry := battle_registry()
	var expected := {
		"id": "campo 'id'", "name": "campo 'name'", "seed": "campo 'seed'", "max_turns": "campo 'max_turns'",
		"map": "map.rows", "sides": "sides deve ser um objeto", "units": "units deve ser uma lista",
	}
	for field in expected:
		var scenario := _scenario()
		scenario.erase(field)
		_assert_rejected(registry, scenario, expected[field], "sem '%s'" % field)


func test_missing_unit_and_side_fields_are_rejected() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["units"][0].erase("name")
	_assert_rejected(registry, scenario, "campo 'name'", "unidade sem nome")
	scenario = _scenario()
	scenario["units"][0].erase("at")
	_assert_rejected(registry, scenario, "posição 'at'", "unidade sem posição")
	scenario = _scenario()
	scenario["units"][0].erase("type")
	_assert_rejected(registry, scenario, "tipo desconhecido", "unidade sem tipo")
	scenario = _scenario()
	scenario["sides"].erase("enemy")
	_assert_rejected(registry, scenario, "lado 'enemy' ausente", "sem o lado inimigo")
	scenario = _scenario()
	scenario["sides"]["player"].erase("home_edge")
	_assert_rejected(registry, scenario, "home_edge", "lado sem borda de origem")


# --- Tipos inválidos --------------------------------------------------------------------------

func test_scenario_that_is_not_a_dictionary_is_rejected() -> void:
	var registry := battle_registry()
	for bad in [5, "texto", [1, 2], null]:
		assert_has_error(registry.validate_scenario(bad), "deve ser um dicionário", "valor %s" % str(bad))


func test_invalid_value_types_are_rejected() -> void:
	var registry := battle_registry()
	var cases := [
		["name", 5, "campo 'name'"],
		["seed", "abc", "'seed' deve ser numérico"],
		["max_turns", 0, "menor que"],
		["max_turns", "dez", "'max_turns' deve ser numérico"],
		["units", "nenhuma", "units deve ser uma lista"],
		["sides", [], "sides deve ser um objeto"],
		["map", "texto", "map.rows"],
	]
	for c in cases:
		var scenario := _scenario()
		scenario[c[0]] = c[1]
		_assert_rejected(registry, scenario, c[2], "%s = %s" % [c[0], str(c[1])])


func test_invalid_map_rows_are_rejected() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["map"]["rows"] = "...."
	_assert_rejected(registry, scenario, "map.rows deve ser uma lista", "rows não é lista")
	scenario = _scenario()
	scenario["map"]["rows"] = []
	_assert_rejected(registry, scenario, "map.rows deve ser uma lista", "rows vazia")
	scenario = _scenario()
	scenario["map"]["rows"][1] = 5
	_assert_rejected(registry, scenario, "mesma largura", "linha que não é texto")
	scenario = _scenario()
	scenario["map"]["rows"][1] = "..."
	_assert_rejected(registry, scenario, "mesma largura", "linhas de larguras diferentes")
	scenario = _scenario()
	scenario["map"]["rows"][0] = "..X.f"
	_assert_rejected(registry, scenario, "caractere de terreno desconhecido 'X'", "terreno desconhecido")


func test_invalid_unit_entries_are_rejected() -> void:
	var registry := battle_registry()
	var cases := [
		["units entry", func(s: Dictionary) -> void: s["units"][0] = "P1", "unidade inválida"],
		["lado inválido", func(s: Dictionary) -> void: s["units"][0]["side"] = "alien", "lado inválido"],
		["tipo desconhecido", func(s: Dictionary) -> void: s["units"][0]["type"] = "dragao", "tipo desconhecido"],
		["at texto", func(s: Dictionary) -> void: s["units"][0]["at"] = "0,0", "posição 'at' inválida"],
		["at tamanho", func(s: Dictionary) -> void: s["units"][0]["at"] = [0], "posição 'at' inválida"],
		["at booleano", func(s: Dictionary) -> void: s["units"][0]["at"] = [true, 0], "posição 'at' inválida"],
		["at fracionário", func(s: Dictionary) -> void: s["units"][0]["at"] = [0.5, 0], "coordenadas inteiras"],
		["at negativo", func(s: Dictionary) -> void: s["units"][0]["at"] = [-1, 0], "fora do mapa"],
		["at fora do mapa", func(s: Dictionary) -> void: s["units"][0]["at"] = [9, 9], "fora do mapa"],
		["em água", func(s: Dictionary) -> void: s["units"][0]["at"] = [2, 1], "intransponível"],
		["posição repetida", func(s: Dictionary) -> void: s["units"][1]["at"] = [0, 0], "já ocupada"],
		["efetivo acima do máximo", func(s: Dictionary) -> void: s["units"][0]["strength"] = 9999, "strength fora dos limites"],
		["efetivo zero", func(s: Dictionary) -> void: s["units"][0]["strength"] = 0, "strength fora dos limites"],
		["moral acima do máximo", func(s: Dictionary) -> void: s["units"][0]["morale"] = 101, "morale fora dos limites"],
		["efetivo texto", func(s: Dictionary) -> void: s["units"][0]["strength"] = "muito", "strength fora dos limites"],
		["source_id negativo", func(s: Dictionary) -> void: s["units"][0]["source_id"] = -1, "source_id"],
		["source_id fracionário", func(s: Dictionary) -> void: s["units"][0]["source_id"] = 1.5, "source_id"],
		["source_id texto", func(s: Dictionary) -> void: s["units"][0]["source_id"] = "a", "source_id"],
	]
	for c in cases:
		var scenario := _scenario()
		c[1].call(scenario)
		_assert_rejected(registry, scenario, c[2], c[0])


func test_duplicate_source_ids_are_rejected_but_zero_may_repeat() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["units"][1]["source_id"] = 11  # mesma unidade de origem que "P1"
	_assert_rejected(registry, scenario, "source_id 11 repetido", "source_id repetido")
	scenario = _scenario()
	scenario["units"][0]["source_id"] = 0
	scenario["units"][1]["source_id"] = 0
	assert_eq(registry.validate_scenario(scenario), PackedStringArray(), "0 = sem origem: pode repetir")
	scenario = _scenario()
	scenario["units"].append({"side": "player", "type": "infantry", "name": "P2", "at": [0, 2], "source_id": 12})
	assert_eq(registry.validate_scenario(scenario), PackedStringArray(), "ids de origem diferentes: válido")


func test_invalid_sides_are_rejected() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["units"].remove_at(1)
	_assert_rejected(registry, scenario, "não tem unidades", "lado sem unidades")
	scenario = _scenario()
	scenario["sides"]["enemy"]["home_edge"] = "west"
	_assert_rejected(registry, scenario, "bordas de origem diferentes", "mesma borda")
	scenario = _scenario()
	scenario["sides"]["player"]["home_edge"] = "norte"
	_assert_rejected(registry, scenario, "home_edge inválida", "borda desconhecida")
	scenario = _scenario()
	scenario["sides"]["player"]["color"] = "azul-escuro-xyz"
	_assert_rejected(registry, scenario, "cor inválida", "cor inválida")
	scenario = _scenario()
	scenario["sides"]["player"]["name"] = ""
	_assert_rejected(registry, scenario, "campo 'name'", "nome de lado vazio")


func test_unloaded_registry_is_reported_instead_of_crashing() -> void:
	var empty := BattleRegistry.new()
	assert_has_error(empty.validate_scenario(_scenario()), "não carregado", "registro vazio")
	var state := BattleState.new()
	assert_true(not state.setup_from_scenario(empty, _scenario()), "recusa")
	assert_true(state.units.is_empty(), "nada criado")


func test_validation_reports_every_problem_at_once() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["name"] = ""
	scenario["units"][0]["type"] = "dragao"
	scenario["units"][1]["at"] = [9, 9]
	var errors := registry.validate_scenario(scenario)
	assert_has_error(errors, "campo 'name'", "nome")
	assert_has_error(errors, "tipo desconhecido", "tipo")
	assert_has_error(errors, "fora do mapa", "posição")
	assert_true(errors.size() >= 3, "vários problemas listados juntos (%d)" % errors.size())


# --- Nada parcial ---------------------------------------------------------------------------------

func test_failed_setup_leaves_a_fresh_state_empty() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["units"][1]["type"] = "dragao"  # o erro está na ÚLTIMA unidade: nada pode ter sido criado antes
	var state := BattleState.new()
	assert_true(not state.setup_from_scenario(registry, scenario), "recusado")
	assert_true(state.units.is_empty(), "nenhuma unidade criada")
	assert_eq(state.scenario_id, "", "sem id")
	assert_eq(state.map.width, 0, "sem mapa")
	assert_eq(state.map.terrain.size(), 0, "sem terreno")
	assert_true(state.log.is_empty() and not state.over and state.turn == 1, "sem registro, sem resultado")
	assert_true(state.sides.is_empty(), "sem lados")


func test_failed_setup_does_not_disturb_a_battle_in_progress() -> void:
	var registry := battle_registry()
	var state := BattleState.new()
	state.setup(registry, BattleRegistry.DEFAULT_SCENARIO)
	Movement.move_unit(state, "player", state.unit_at(hx(3, 3)), hx(4, 3))
	var map_before: RefCounted = state.map
	var before := state.to_dict()
	var scenario := _scenario()
	scenario["map"]["rows"][2] = "h..."
	assert_true(not state.setup_from_scenario(registry, scenario), "recusado")
	assert_eq(state.to_dict(), before, "a batalha em andamento ficou exatamente como estava")
	assert_true(state.map == map_before, "o mesmo mapa continua em uso")
	assert_has_error(state.setup_errors, "mesma largura", "motivo disponível")
	assert_true(state.setup_from_scenario(registry, _scenario()), "e uma chamada válida depois limpa os erros")
	assert_eq(state.setup_errors.size(), 0, "setup_errors limpo")


# --- Compatibilidade com as regras existentes ---------------------------------------------------------

func test_battle_from_a_memory_scenario_plays_with_the_existing_rules() -> void:
	var registry := battle_registry()
	var scenario := _scenario()
	scenario["units"] = [
		{"side": "player", "type": "infantry", "name": "A", "at": [0, 0]},
		{"side": "enemy", "type": "infantry", "name": "B", "at": [3, 0], "strength": 1},
	]
	var state := BattleState.new()
	assert_true(state.setup_from_scenario(registry, scenario), str(state.setup_errors))
	var a: int = state.unit_at(hx(0, 0))
	var b: int = state.unit_at(hx(3, 0))
	assert_true("fora do alcance" in Combat.check_attack(state, "player", a, b), "alcance respeitado")
	assert_true(Movement.move_unit(state, "player", a, hx(2, 0))["ok"], "movimento (custo do terreno)")
	assert_true(not Movement.move_unit(state, "player", a, hx(1, 0))["ok"], "um movimento por turno")
	var result := Combat.attack(state, "player", a, b)
	assert_true(result["ok"] and result["destroyed"], "ataque destrói a unidade de efetivo 1")
	assert_true(state.over, "vitória")
	assert_eq(state.result["winner"], "player", "vencedor")
	assert_eq(state.result["reason"], "elimination", "por eliminação")
	assert_eq(state.result_summary()["scenario_id"], "mem_test", "o resumo identifica o cenário em memória")
