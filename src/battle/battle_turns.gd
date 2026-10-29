extends RefCounted
## Fluxo de turnos da batalha (jogador -> inimigo -> jogador...), retirada forçada e condições de vitória.
##
## Um "turno" numerado é uma rodada: o jogador joga, depois o inimigo; ao fim do inimigo o número sobe.
## INÍCIO DO TURNO DE UM LADO (begin_turn), nesta ordem:
##   1. suas unidades recuperam as ações (moved/attacked/moved_steps);
##   2. recuperação de moral (só sem inimigo adjacente) e reagrupamento de quem estava em retirada;
##   3. unidades que continuam em retirada recuam sozinhas em direção à borda de origem do lado
##      (caminho de menor custo, até o alcance de movimento; se chegam à borda, deixam o campo;
##      sem caminho, ficam paradas — nunca há teletransporte);
##   4. verificação de vitória.
## VITÓRIA (evaluate_victory, após cada ataque e no início de cada turno): um lado é "quebrado" quando
##   não tem unidades efetivas (em campo e fora de retirada). Estar sem ação (já moveu/atacou) NÃO conta.
##   - só um lado quebrado: o outro vence ("elimination" se o quebrado não tem mais ninguém em campo;
##     "rout" se restam unidades dele, todas em retirada);
##   - os dois quebrados: empate ("mutual_break");
##   - ao terminar o turno max_turns do inimigo: vence quem tem mais efetivo efetivo ("turn_limit"); empate se igual.
## Depois do fim, nenhuma ação é aceita (as validações recusam com "A batalha terminou.").

const Morale := preload("res://src/battle/battle_morale.gd")
const Movement := preload("res://src/battle/battle_movement.gd")
const Pathfinding := preload("res://src/battle/battle_pathfinding.gd")


## Encerra o turno do lado ativo e inicia o do oponente. Resultado: {ok, message}.
static func end_turn(state: RefCounted, side: String) -> Dictionary:
	if state.over:
		return {"ok": false, "message": "A batalha terminou."}
	if side != state.active_side:
		return {"ok": false, "message": "Não é o turno deste lado."}
	var next: String = state.opponent_of(side)
	if next == "player":
		if state.turn >= state.max_turns:
			_finish_by_turn_limit(state)
			return {"ok": true, "message": state.result["text"]}
		state.turn += 1
	state.active_side = next
	state.add_log("— Turno %d: %s —" % [state.turn, state.sides[next]["name"]])
	begin_turn(state, next)
	return {"ok": true, "message": "Turno de %s." % state.sides[next]["name"]}


static func begin_turn(state: RefCounted, side: String) -> void:
	for id in state.live_units(side):
		var unit: Dictionary = state.units[id]
		unit["moved"] = false
		unit["attacked"] = false
		unit["moved_steps"] = 0
	Morale.recover_side(state, side)
	for id in state.live_units(side):
		if state.units[id]["routing"]:
			_retreat(state, id)
	evaluate_victory(state)


## Verifica as condições de vitória; encerra a batalha se alguma valer. Devolve true se acabou.
static func evaluate_victory(state: RefCounted) -> bool:
	if state.over:
		return true
	var player_broken: bool = state.effective_units("player").is_empty()
	var enemy_broken: bool = state.effective_units("enemy").is_empty()
	if player_broken and enemy_broken:
		finish(state, "draw", "mutual_break", "Empate: os dois lados estão quebrados.")
	elif player_broken or enemy_broken:
		var loser := "player" if player_broken else "enemy"
		var winner: String = state.opponent_of(loser)
		var winner_name: String = state.sides[winner]["name"]
		var loser_name: String = state.sides[loser]["name"]
		if state.live_units(loser).is_empty():
			finish(state, winner, "elimination", "Vitória de %s por eliminação: todas as unidades de %s foram destruídas ou deixaram o campo." % [winner_name, loser_name])
		else:
			finish(state, winner, "rout", "Vitória de %s: todas as unidades restantes de %s estão em retirada." % [winner_name, loser_name])
	return state.over


static func finish(state: RefCounted, winner: String, reason: String, text: String) -> void:
	state.over = true
	state.result = {"winner": winner, "reason": reason, "turn": state.turn, "text": text}
	state.add_log(text)


static func _finish_by_turn_limit(state: RefCounted) -> void:
	var totals := {"player": 0, "enemy": 0}
	for side in totals:
		for id in state.effective_units(side):
			totals[side] += state.units[id]["strength"]
	if totals["player"] == totals["enemy"]:
		finish(state, "draw", "turn_limit", "Limite de %d turnos: empate em efetivos." % state.max_turns)
	else:
		var winner := "player" if totals["player"] > totals["enemy"] else "enemy"
		finish(state, winner, "turn_limit", "Limite de %d turnos: vitória de %s (%d x %d homens efetivos)." % [
			state.max_turns, state.sides[winner]["name"], totals[winner], totals[state.opponent_of(winner)]])


## Retirada forçada de uma unidade em fuga, em direção à borda de origem do lado.
static func _retreat(state: RefCounted, unit_id: int) -> void:
	var unit: Dictionary = state.units[unit_id]
	var edge: String = state.sides[unit["side"]]["home_edge"]
	unit["moved"] = true
	unit["attacked"] = true
	if state.map.is_edge(unit["pos"], edge):
		_flee(state, unit)
		return
	var reach := Pathfinding.reachable(state.map, unit["pos"], 100000, Movement.blocked_hexes(state, unit_id))
	var goal := Vector2i(-1, -1)
	var best_cost := -1
	for hex in state.map.edge_hexes(edge):
		if reach["cost"].has(hex) and (best_cost < 0 or reach["cost"][hex] < best_cost):
			best_cost = reach["cost"][hex]
			goal = hex
	if best_cost < 0:
		state.add_log("%s está cercada e não consegue recuar." % unit["name"])
		return
	var path := Pathfinding.path_to(reach["prev"], unit["pos"], goal)
	var spent := 0
	var destination: Vector2i = unit["pos"]
	for i in range(1, path.size()):
		var step_cost: int = state.map.move_cost(path[i])
		if spent + step_cost > unit["move_range"]:
			break
		spent += step_cost
		destination = path[i]
	if destination != unit["pos"]:
		unit["pos"] = destination
		state.add_log("%s recua em desordem." % unit["name"])
	if state.map.is_edge(unit["pos"], edge):
		_flee(state, unit)


static func _flee(state: RefCounted, unit: Dictionary) -> void:
	unit["fled"] = true
	state.add_log("%s abandona o campo de batalha." % unit["name"])
