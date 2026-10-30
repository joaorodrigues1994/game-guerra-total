extends RefCounted
## Base mínima para testes headless: métodos test_* são descobertos pelo executor.

const Registry := preload("res://src/core/registry.gd")
const GameState := preload("res://src/core/game_state.gd")

var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0


func assert_true(condition: bool, message: String = "") -> void:
	assertions += 1
	if not condition:
		failures.append(message if message != "" else "assert_true falhou")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (esperado: %s, obtido: %s)" % [message, str(expected), str(actual)])


func assert_has_error(errors: PackedStringArray, fragment: String, message: String = "") -> void:
	assertions += 1
	for e in errors:
		if fragment in e:
			return
	failures.append("%s (nenhum erro contém '%s'; erros: %s)" % [message, fragment, str(errors)])


## Partida nova com os dados reais: {registry, state}. Cada teste recebe a sua própria cópia.
func new_game(player_country_id: String = "fra") -> Dictionary:
	var registry := Registry.new()
	assert_true(registry.load_from_dir("res://data"), "dados devem carregar: %s" % str(registry.errors))
	var state := GameState.new()
	assert_true(state.setup_from_registry(registry, player_country_id), "estado inicial")
	return {"registry": registry, "state": state}


## Declara guerra pela ação real da campanha (WarActions); falha o teste se a declaração for recusada.
func declare_war_between(game: Dictionary, country_id: String, target_id: String) -> void:
	var result: Dictionary = preload("res://src/campaign/war_actions.gd").declare_war(game["registry"], game["state"], country_id, target_id)
	assert_true(result["ok"], "declarar guerra: %s" % result["message"])


## Unidades de um país (a partida inicial já tem exércitos de Áustria e Baviera).
func units_of(state: RefCounted, country_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in state.units:
		if unit["owner"] == country_id:
			result.append(unit)
	return result
