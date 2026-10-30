extends RefCounted
## Controlador da batalha tática: seleção, ordens do jogador, turno inimigo automático, reinício e dados
## prontos para a interface. A interface só fala com este objeto (sinais + views); as regras vivem em
## BattleMovement, BattleCombat, BattleMorale, BattleTurns e BattleAI.
##
## O jogador controla o lado "player"; o lado "enemy" joga sozinho (BattleAI) ao fim do turno do jogador.

const BattleState := preload("res://src/battle/battle_state.gd")
const Combat := preload("res://src/battle/battle_combat.gd")
const Hex := preload("res://src/battle/hex.gd")
const Movement := preload("res://src/battle/battle_movement.gd")
const Turns := preload("res://src/battle/battle_turns.gd")
const AI := preload("res://src/battle/battle_ai.gd")

const PLAYER := "player"
const NO_HEX := Vector2i(-9999, -9999)

signal state_changed
signal selection_changed
signal message_posted(text: String, is_error: bool)
signal log_added(text: String)
signal battle_finished(summary: Dictionary)
## A batalha foi reiniciada (a interface deve limpar o que guardou, ex.: o painel de resultado).
signal restarted

var registry: RefCounted
var scenario_id: String = ""
## Cenário em memória usado por setup_from_scenario (vazio = cenário cadastrado em `registry`).
var scenario: Dictionary = {}
## Id opaco da batalha da campanha a que esta batalha pertence (0 = batalha independente/de teste). A batalha
## não interpreta o valor: só o usa para recusar o reinício e para a interface se identificar.
var linked_battle_id: int = 0
var state: BattleState
var selected_unit_id: int = 0
var selected_hex: Vector2i = NO_HEX
## Motivos da última falha de setup()/setup_from_scenario().
var setup_errors: PackedStringArray = PackedStringArray()

var _logged: int = 0
var _announced: bool = false


func setup(p_registry: RefCounted, p_scenario_id: String) -> bool:
	registry = p_registry
	scenario_id = p_scenario_id
	scenario = {}
	state = BattleState.new()
	if not state.setup(registry, scenario_id):
		setup_errors = state.setup_errors
		return false
	setup_errors = PackedStringArray()
	Turns.begin_turn(state, state.active_side)
	_logged = 0
	_announced = false
	_flush_log()
	return true


## Inicia a batalha a partir de um cenário em memória (ex.: o registrado pela campanha). O cenário é validado
## antes de qualquer alteração: se for inválido, devolve false, preenche `setup_errors` e este controlador
## permanece como estava.
func setup_from_scenario(p_registry: RefCounted, p_scenario: Dictionary) -> bool:
	var fresh := BattleState.new()
	if not fresh.setup_from_scenario(p_registry, p_scenario):
		setup_errors = fresh.setup_errors
		return false
	setup_errors = PackedStringArray()
	registry = p_registry
	scenario = p_scenario.duplicate(true)
	scenario_id = scenario["id"]
	state = fresh
	Turns.begin_turn(state, state.active_side)
	_logged = 0
	_announced = false
	_flush_log()
	return true


## Reinicia a batalha do zero (terreno, unidades, posições, moral, turnos, semente do RNG e registro).
## Os mesmos objetos e conexões de sinal continuam valendo: nada é duplicado. Uma batalha ligada à campanha
## não reinicia (o resultado tático registrado seria de outra partida).
func restart() -> void:
	if linked_battle_id != 0:
		message_posted.emit("Esta batalha da campanha não pode ser reiniciada.", true)
		return
	state = BattleState.new()
	if scenario.is_empty():
		state.setup(registry, scenario_id)
	else:
		state.setup_from_scenario(registry, scenario)
	Turns.begin_turn(state, state.active_side)
	selected_unit_id = 0
	selected_hex = NO_HEX
	_logged = 0
	_announced = false
	restarted.emit()
	_flush_log()
	selection_changed.emit()
	state_changed.emit()
	message_posted.emit("Batalha reiniciada.", false)


# --- Seleção e cliques --------------------------------------------------------

func select_unit(unit_id: int) -> bool:
	if not state.units.has(unit_id) or not state.is_on_field(state.units[unit_id]):
		return false
	selected_unit_id = unit_id
	selected_hex = state.units[unit_id]["pos"]
	selection_changed.emit()
	return true


func clear_selection() -> void:
	if selected_unit_id == 0 and selected_hex == NO_HEX:
		return
	selected_unit_id = 0
	selected_hex = NO_HEX
	selection_changed.emit()


## Clique em um hexágono. Unidade do lado ativo -> seleciona; inimigo -> ataca (se uma unidade própria
## estiver selecionada) ou inspeciona; hexágono livre -> move (se uma unidade própria estiver selecionada).
func click_hex(hex: Vector2i) -> void:
	if not state.map.in_bounds(hex):
		return
	var clicked_id: int = state.unit_at(hex)
	var own_selected := _own_selected_id()
	if clicked_id != 0:
		var clicked: Dictionary = state.units[clicked_id]
		if clicked["side"] == PLAYER:
			select_unit(clicked_id)
		elif own_selected != 0:
			selected_hex = hex
			attack(own_selected, clicked_id)
			selection_changed.emit()
		else:
			select_unit(clicked_id)
	else:
		selected_hex = hex
		if own_selected != 0:
			move(own_selected, hex)
		selection_changed.emit()


func _own_selected_id() -> int:
	if selected_unit_id != 0 and state.units.has(selected_unit_id) and state.is_on_field(state.units[selected_unit_id]) \
			and state.units[selected_unit_id]["side"] == PLAYER:
		return selected_unit_id
	return 0


# --- Ordens do jogador -----------------------------------------------------------

func move(unit_id: int, destination: Vector2i) -> Dictionary:
	var result := Movement.move_unit(state, PLAYER, unit_id, destination)
	if result["ok"]:
		selected_hex = destination
	return _finish(result)


func attack(attacker_id: int, target_id: int) -> Dictionary:
	return _finish(Combat.attack(state, PLAYER, attacker_id, target_id))


## Encerra o turno do jogador; o inimigo joga automaticamente e o turno volta ao jogador (se a batalha continuar).
func end_turn() -> Dictionary:
	var result := Turns.end_turn(state, PLAYER)
	if not result["ok"]:
		return _finish(result)
	while not state.over and state.active_side != PLAYER:
		AI.play_turn(state, state.active_side)
		if not state.over:
			Turns.end_turn(state, state.active_side)
	selected_unit_id = 0
	selected_hex = NO_HEX
	selection_changed.emit()
	return _finish({"ok": true, "message": "Turno %d: sua vez." % state.turn if not state.over else state.result["text"]})


func _finish(result: Dictionary) -> Dictionary:
	message_posted.emit(result["message"], not result["ok"])
	_flush_log()
	if result["ok"]:
		state_changed.emit()
	if state.over and not _announced:
		_announced = true
		battle_finished.emit(state.result_summary())
	return result


func _flush_log() -> void:
	while _logged < state.log.size():
		log_added.emit(state.log[_logged])
		_logged += 1


# --- Consultas para a interface ---------------------------------------------------

## {hex: custo} dos hexágonos para onde a unidade própria selecionada pode ir agora (sem o hexágono atual).
func reachable_hexes() -> Dictionary:
	var unit_id := _own_selected_id()
	if unit_id == 0 or state.over or state.active_side != PLAYER:
		return {}
	var costs: Dictionary = Movement.reachable_for(state, unit_id)["cost"].duplicate()
	costs.erase(state.units[unit_id]["pos"])
	return costs


## Ids dos inimigos que a unidade própria selecionada pode atacar agora, do hexágono em que está.
func attack_target_ids() -> Array[int]:
	var result: Array[int] = []
	var unit_id := _own_selected_id()
	if unit_id == 0:
		return result
	for id in state.live_units(state.opponent_of(PLAYER)):
		if Combat.check_attack(state, PLAYER, unit_id, id).is_empty():
			result.append(id)
	return result


func unit_view(unit_id: int) -> Dictionary:
	if not state.units.has(unit_id):
		return {}
	var unit: Dictionary = state.units[unit_id]
	var status: String = state.status_of(unit)
	return {
		"id": unit_id,
		"name": unit["name"],
		"type": unit["type"],
		"type_name": state.unit_types[unit["type"]]["name"],
		"side": unit["side"],
		"side_name": state.sides[unit["side"]]["name"],
		"is_player": unit["side"] == PLAYER,
		"pos": unit["pos"],
		"strength": unit["strength"],
		"max_strength": unit["max_strength"],
		"attack": unit["attack"],
		"defense": unit["defense"],
		"move_range": unit["move_range"],
		"move_available": Movement.available_move(state, unit),
		"attack_range": unit["attack_range"],
		"min_range": unit["min_range"],
		"melee": unit["melee"],
		"morale": unit["morale"],
		"max_morale": unit["max_morale"],
		"status": status,
		"status_text": STATUS_TEXT[status],
		"moved": unit["moved"],
		"attacked": unit["attacked"],
		"terrain_name": state.map.terrain_def_at(unit["pos"]).get("name", ""),
	}


const STATUS_TEXT := {
	"firm": "Firme", "shaken": "Abalada", "routing": "Em retirada", "fled": "Fugiu", "destroyed": "Destruída",
}


func hex_view(hex: Vector2i) -> Dictionary:
	if not state.map.in_bounds(hex):
		return {}
	var def: Dictionary = state.map.terrain_def_at(hex)
	var offset := Hex.axial_to_offset(hex)
	return {
		"axial": hex,
		"col": offset.x,
		"row": offset.y,
		"terrain": def["id"],
		"terrain_name": def["name"],
		"passable": def["passable"],
		"move_cost": state.map.move_cost(hex),
		"defense_bonus": state.map.defense_bonus(hex),
		"unit_id": state.unit_at(hex),
	}


## Texto "Turno N — Lado ativo: ...".
func turn_text() -> String:
	return "Turno %d — Lado ativo: %s" % [state.turn, state.sides[state.active_side]["name"]]


## Dados do painel de resultado (vazio enquanto a batalha não terminou).
func result_view() -> Dictionary:
	if not state.over:
		return {}
	var summary := state.result_summary()
	var lines := {}
	for side in summary["units"]:
		var entries: Array[String] = []
		for u in summary["units"][side]:
			entries.append("%s — %s (%d/%d homens, moral %d)" % [
				u["name"], STATUS_TEXT[u["status"]], u["strength"], u["max_strength"], u["morale"]])
		lines[side] = entries
	var title := "Empate"
	if summary["winner"] != "draw":
		title = "Vitória de %s" % state.sides[summary["winner"]]["name"]
	return {"title": title, "text": summary["text"], "lines": lines, "summary": summary}
