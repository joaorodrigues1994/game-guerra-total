extends RefCounted
## Estado de UMA batalha tática: mapa, unidades-instância, lado ativo, turno, resultado, RNG e registro.
## Só dados e consultas; as regras ficam em BattleMovement, BattleCombat, BattleTurns e BattleAI.
##
## Unidade tática (dicionário): id (inteiro único), name, type (id em unit_types.json), side ("player"/"enemy"),
## pos (hex axial), strength/max_strength, attack, defense, move_range, attack_range, min_range, melee,
## morale/max_morale, moved, attacked, moved_steps (passos andados no turno; usado pela carga),
## routing, fled, destroyed, source_id (reservado: id da unidade de campanha de origem; 0 = nenhuma).
## Os atributos são copiados do tipo na criação, permitindo que a campanha injete modificadores no futuro.

const BattleMap := preload("res://src/battle/battle_map.gd")
const Hex := preload("res://src/battle/hex.gd")

var scenario_id: String = ""
var scenario_name: String = ""
var seed_value: int = 0
var map: BattleMap = BattleMap.new()
var rules: Dictionary = {}
var unit_types: Dictionary = {}
## lado -> {name, color, home_edge}
var sides: Dictionary = {}
var units: Dictionary = {}  # id -> unidade
var next_unit_id: int = 1
var active_side: String = "player"
var turn: int = 1
var max_turns: int = 40
var over: bool = false
## {winner: "player"/"enemy"/"draw", reason: "elimination"/"rout"/"turn_limit"/"mutual_break", turn, text}
var result: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var log: Array[String] = []


## Motivos da última recusa de setup()/setup_from_scenario() (vazio se a última chamada deu certo).
var setup_errors: PackedStringArray = PackedStringArray()


## Monta a batalha a partir de um cenário CADASTRADO no BattleRegistry. Retorna false se o cenário não existir.
## Chamar de novo restaura tudo (é assim que a batalha é reiniciada).
func setup(registry: RefCounted, p_scenario_id: String) -> bool:
	if not registry.scenarios.has(p_scenario_id):
		setup_errors = PackedStringArray(["Cenário não cadastrado: %s" % p_scenario_id])
		return false
	return setup_from_scenario(registry, registry.scenarios[p_scenario_id])


## Monta a batalha a partir de um cenário fornecido como dicionário (mesmo formato de data/battle/scenarios/),
## sem precisar cadastrá-lo. O cenário é VALIDADO antes de qualquer alteração: se for inválido, devolve false,
## preenche `setup_errors` e este estado permanece exatamente como estava (nunca fica parcialmente montado).
func setup_from_scenario(registry: RefCounted, scenario: Dictionary) -> bool:
	setup_errors = registry.validate_scenario(scenario)
	if not setup_errors.is_empty():
		return false
	var p_scenario_id: String = scenario["id"]
	scenario = scenario.duplicate(true)  # não compartilha dicionários com o chamador
	scenario_id = p_scenario_id
	scenario_name = scenario["name"]
	seed_value = int(scenario["seed"])
	rules = registry.rules
	unit_types = registry.unit_types
	sides = scenario["sides"]
	map = BattleMap.new()
	map.build(scenario["map"]["rows"], registry.terrains)
	units = {}
	next_unit_id = 1
	active_side = "player"
	turn = 1
	max_turns = int(scenario.get("max_turns", rules["default_max_turns"]))
	over = false
	result = {}
	log = []
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	for entry in scenario["units"]:
		var pos := Hex.offset_to_axial(int(entry["at"][0]), int(entry["at"][1]))
		var overrides := {}
		for field in ["strength", "morale", "source_id"]:
			if entry.has(field):
				overrides[field] = int(entry[field])
		add_unit(entry["type"], entry["name"], entry["side"], pos, overrides)
	return true


## Cria uma unidade e devolve seu id. overrides: strength, morale, source_id.
func add_unit(type_id: String, unit_name: String, side: String, pos: Vector2i, overrides: Dictionary = {}) -> int:
	var def: Dictionary = unit_types[type_id]
	var unit := {
		"id": next_unit_id,
		"name": unit_name,
		"type": type_id,
		"side": side,
		"pos": pos,
		"strength": clampi(int(overrides.get("strength", def["max_strength"])), 1, int(def["max_strength"])),
		"max_strength": int(def["max_strength"]),
		"attack": float(def["attack"]),
		"defense": float(def["defense"]),
		"move_range": int(def["move_range"]),
		"attack_range": int(def["attack_range"]),
		"min_range": int(def["min_range"]),
		"melee": bool(def["melee"]),
		"morale": clampi(int(overrides.get("morale", def["max_morale"])), 0, int(def["max_morale"])),
		"max_morale": int(def["max_morale"]),
		"moved": false,
		"attacked": false,
		"moved_steps": 0,
		"routing": false,
		"fled": false,
		"destroyed": false,
		"source_id": int(overrides.get("source_id", 0)),
	}
	next_unit_id += 1
	units[unit["id"]] = unit
	return unit["id"]


# --- Consultas ----------------------------------------------------------------

func is_on_field(unit: Dictionary) -> bool:
	return not unit["destroyed"] and not unit["fled"]


## Id da unidade em campo no hexágono; 0 se livre.
func unit_at(hex: Vector2i) -> int:
	for id in units:
		if is_on_field(units[id]) and units[id]["pos"] == hex:
			return id
	return 0


## Unidades em campo (vivas e não fugidas), ordenadas por id; opcionalmente só de um lado.
func live_units(side: String = "") -> Array[int]:
	var result_ids: Array[int] = []
	for id in units:
		if is_on_field(units[id]) and (side.is_empty() or units[id]["side"] == side):
			result_ids.append(id)
	result_ids.sort()
	return result_ids


## Unidades em campo que ainda combatem (não estão em retirada).
func effective_units(side: String) -> Array[int]:
	var result_ids: Array[int] = []
	for id in live_units(side):
		if not units[id]["routing"]:
			result_ids.append(id)
	return result_ids


func opponent_of(side: String) -> String:
	return "enemy" if side == "player" else "player"


## "destroyed", "fled", "routing", "shaken" ou "firm" (limites em battle_rules.json).
func status_of(unit: Dictionary) -> String:
	if unit["destroyed"]:
		return "destroyed"
	if unit["fled"]:
		return "fled"
	if unit["routing"]:
		return "routing"
	if unit["morale"] <= rules["shaken_threshold"]:
		return "shaken"
	return "firm"


func add_log(text: String) -> void:
	log.append(text)


## Contrato do futuro BattleResult (a campanha lerá isto): vencedor, motivo, turnos e situação de cada unidade.
func result_summary() -> Dictionary:
	var by_side := {}
	for side in sides:
		by_side[side] = []
	for id in units:
		var unit: Dictionary = units[id]
		by_side[unit["side"]].append({
			"unit_id": id,
			"source_id": unit["source_id"],
			"name": unit["name"],
			"type": unit["type"],
			"strength": unit["strength"],
			"max_strength": unit["max_strength"],
			"morale": unit["morale"],
			"max_morale": unit["max_morale"],
			"status": status_of(unit),
		})
	return {
		"scenario_id": scenario_id,
		"winner": result.get("winner", ""),
		"reason": result.get("reason", ""),
		"text": result.get("text", ""),
		"turns": turn,
		"units": by_side,
	}


func to_dict() -> Dictionary:
	return {
		"scenario_id": scenario_id,
		"units": units.duplicate(true),
		"next_unit_id": next_unit_id,
		"active_side": active_side,
		"turn": turn,
		"over": over,
		"result": result.duplicate(true),
		"log": log.duplicate(),
		"rng_state": rng.state,
	}
