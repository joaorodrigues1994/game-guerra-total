extends "res://tests/test_case.gd"
## Base para os testes da batalha tática (não começa com "test_": o executor não a roda como teste).

const BattleRegistry := preload("res://src/battle/battle_registry.gd")
const BattleState := preload("res://src/battle/battle_state.gd")
const BattleController := preload("res://src/battle/battle_controller.gd")
const Hex := preload("res://src/battle/hex.gd")


func battle_registry() -> BattleRegistry:
	var registry := BattleRegistry.new()
	assert_true(registry.load_from_dir("res://data/battle"), "dados da batalha devem carregar: %s" % str(registry.errors))
	return registry


## Posição axial a partir de (coluna, linha) do cenário.
func hx(col: int, row: int) -> Vector2i:
	return Hex.offset_to_axial(col, row)


## Batalha do cenário de teste. empty = true remove todas as unidades (campo vazio com o mesmo terreno).
## A variação aleatória é zerada para que os números sejam exatos (cópia das regras: não afeta outros testes).
func new_battle(empty: bool = true, variation: float = 0.0) -> BattleState:
	var state := BattleState.new()
	assert_true(state.setup(battle_registry(), BattleRegistry.DEFAULT_SCENARIO), "cenário de teste")
	state.rules = state.rules.duplicate()
	state.rules["variation"] = variation
	if empty:
		state.units = {}
		state.next_unit_id = 1
	return state


func put(state: BattleState, type_id: String, unit_name: String, side: String, col: int, row: int, overrides: Dictionary = {}) -> int:
	return state.add_unit(type_id, unit_name, side, hx(col, row), overrides)


func new_controller() -> BattleController:
	var controller := BattleController.new()
	assert_true(controller.setup(battle_registry(), BattleRegistry.DEFAULT_SCENARIO), "controlador")
	return controller
