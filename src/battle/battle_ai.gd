extends RefCounted
## Rotina básica e DETERMINÍSTICA do inimigo (sem aleatoriedade própria). Para cada unidade, em ordem de id:
##   1. se já alcança algum alvo, ataca (alvo de menor efetivo; empate: menor id);
##   2. senão, procura um hexágono alcançável de onde possa atacar (e, se puder, vai e ataca: alvo de menor
##      efetivo; hexágono de maior bônus de terreno, depois menor custo, depois ordem de linha/coluna);
##   3. senão, aproxima-se do inimigo mais próximo (artilharia para a 'alcance máximo' de distância).
## Usa as mesmas funções validadas do jogador (BattleMovement.move_unit e BattleCombat.attack): a IA não burla regras.
## Unidades em retirada não são controladas (a retirada é automática no início do turno).

const Combat := preload("res://src/battle/battle_combat.gd")
const Hex := preload("res://src/battle/hex.gd")
const Movement := preload("res://src/battle/battle_movement.gd")
const Pathfinding := preload("res://src/battle/battle_pathfinding.gd")


## Joga o turno inteiro do lado. Devolve o número de ações executadas (movimentos + ataques).
static func play_turn(state: RefCounted, side: String) -> int:
	var actions := 0
	for unit_id in state.effective_units(side):
		if state.over:
			break
		actions += _play_unit(state, side, unit_id)
	return actions


static func _play_unit(state: RefCounted, side: String, unit_id: int) -> int:
	var unit: Dictionary = state.units[unit_id]
	var enemies := _enemy_ids(state, side)
	if enemies.is_empty():
		return 0
	var actions := 0

	# 1. Atacar sem se mover.
	var target_id := _best_target_in_range(state, unit, unit["pos"], enemies, true)
	if target_id != 0:
		return 1 if Combat.attack(state, side, unit_id, target_id)["ok"] else 0

	# 2. Mover-se para um hexágono de onde possa atacar (se a unidade puder atacar depois de mover).
	var reach := Movement.reachable_for(state, unit_id)
	var can_fire_after_move: bool = state.unit_types[unit["type"]]["can_attack_after_move"]
	if can_fire_after_move and not unit["moved"]:
		var option := _best_attack_option(state, unit, reach, enemies)
		if not option.is_empty():
			if option["hex"] != unit["pos"] and Movement.move_unit(state, side, unit_id, option["hex"])["ok"]:
				actions += 1
			if Combat.attack(state, side, unit_id, option["target"])["ok"]:
				actions += 1
			return actions

	# 3. Aproximar-se.
	if not unit["moved"]:
		var destination := _approach_hex(state, unit, reach, enemies)
		if destination != unit["pos"] and Movement.move_unit(state, side, unit_id, destination)["ok"]:
			actions += 1
	return actions


static func _enemy_ids(state: RefCounted, side: String) -> Array[int]:
	return state.live_units(state.opponent_of(side))


## Alvo de menor efetivo (empate: menor id) que a unidade alcança de `from_hex`.
static func _best_target_in_range(state: RefCounted, unit: Dictionary, from_hex: Vector2i, enemies: Array[int], check_state: bool) -> int:
	var best := 0
	for id in enemies:
		var target: Dictionary = state.units[id]
		if check_state:
			if not Combat.check_attack(state, unit["side"], unit["id"], id).is_empty():
				continue
		elif not Combat.in_range_from(unit, from_hex, target):
			continue
		if best == 0 or target["strength"] < state.units[best]["strength"]:
			best = id
	return best


## Melhor {hex, target} entre os hexágonos alcançáveis; {} se nenhum permite atacar.
static func _best_attack_option(state: RefCounted, unit: Dictionary, reach: Dictionary, enemies: Array[int]) -> Dictionary:
	if unit["attacked"]:
		return {}
	var best := {}
	for hex in reach["cost"]:
		var target_id := _best_target_in_range(state, unit, hex, enemies, false)
		if target_id == 0:
			continue
		var option := {"hex": hex, "target": target_id}
		if best.is_empty() or _option_precedes(state, option, best, reach):
			best = option
	return best


static func _option_precedes(state: RefCounted, a: Dictionary, b: Dictionary, reach: Dictionary) -> bool:
	var strength_a: int = state.units[a["target"]]["strength"]
	var strength_b: int = state.units[b["target"]]["strength"]
	if strength_a != strength_b:
		return strength_a < strength_b
	if a["target"] != b["target"]:
		return a["target"] < b["target"]
	var defense_a: float = state.map.defense_bonus(a["hex"])
	var defense_b: float = state.map.defense_bonus(b["hex"])
	if not is_equal_approx(defense_a, defense_b):
		return defense_a > defense_b
	if reach["cost"][a["hex"]] != reach["cost"][b["hex"]]:
		return reach["cost"][a["hex"]] < reach["cost"][b["hex"]]
	if a["hex"].y != b["hex"].y:
		return a["hex"].y < b["hex"].y
	return a["hex"].x < b["hex"].x


## Hexágono alcançável que mais aproxima a unidade do inimigo mais próximo (ou o próprio hexágono).
static func _approach_hex(state: RefCounted, unit: Dictionary, reach: Dictionary, enemies: Array[int]) -> Vector2i:
	var target_id := 0
	for id in enemies:
		var d: int = Hex.distance(unit["pos"], state.units[id]["pos"])
		if target_id == 0 or d < Hex.distance(unit["pos"], state.units[target_id]["pos"]):
			target_id = id
	var target_pos: Vector2i = state.units[target_id]["pos"]
	var field := Pathfinding.distance_field(state.map, target_pos)
	var ranged: bool = not unit["melee"]
	var best: Vector2i = unit["pos"]
	var best_key := _approach_key(unit, unit["pos"], target_pos, field, 0, ranged)
	for hex in reach["cost"]:
		if hex == unit["pos"] or not field.has(hex):
			continue
		var key := _approach_key(unit, hex, target_pos, field, reach["cost"][hex], ranged)
		if _key_less(key, best_key):
			best_key = key
			best = hex
	return best


## Chave de comparação (menor é melhor): [desvio do alcance ideal (só à distância), distância por terreno, custo, linha, coluna].
static func _approach_key(unit: Dictionary, hex: Vector2i, target_pos: Vector2i, field: Dictionary, cost: int, ranged: bool) -> Array:
	var spread := absi(Hex.distance(hex, target_pos) - unit["attack_range"]) if ranged else 0
	return [spread, field.get(hex, 100000), cost, hex.y, hex.x]


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
