extends RefCounted
## Movimentação tática: valida e executa o movimento de uma unidade pelo mapa hexagonal.
## Regras: custo do terreno de cada hexágono entrado (não a distância reta); orçamento = move_range da unidade;
## terreno intransponível e hexágonos ocupados (por qualquer unidade) não podem ser atravessados nem ocupados;
## um movimento por unidade por turno; só unidades do lado ativo, que não estejam em retirada.
## Toda função "check_*" devolve o motivo da recusa ("" = permitido) e não altera o estado.

const Pathfinding := preload("res://src/battle/battle_pathfinding.gd")


## Hexágonos ocupados por unidades em campo, exceto a indicada.
static func blocked_hexes(state: RefCounted, except_unit_id: int = 0) -> Dictionary:
	var blocked := {}
	for id in state.live_units():
		if id != except_unit_id:
			blocked[state.units[id]["pos"]] = true
	return blocked


## Movimento disponível agora: move_range se a unidade ainda pode se mover, senão 0.
static func available_move(state: RefCounted, unit: Dictionary) -> int:
	if unit["moved"] or unit["routing"] or not state.is_on_field(unit):
		return 0
	return unit["move_range"]


## {cost, prev} dos hexágonos alcançáveis pela unidade neste momento (inclui o hexágono atual com custo 0).
static func reachable_for(state: RefCounted, unit_id: int) -> Dictionary:
	var unit: Dictionary = state.units[unit_id]
	return Pathfinding.reachable(state.map, unit["pos"], available_move(state, unit), blocked_hexes(state, unit_id))


static func check_move(state: RefCounted, side: String, unit_id: int, destination: Vector2i) -> String:
	if state.over:
		return "A batalha terminou."
	if not state.units.has(unit_id) or not state.is_on_field(state.units[unit_id]):
		return "Unidade inexistente ou fora de combate."
	var unit: Dictionary = state.units[unit_id]
	if unit["side"] != side:
		return "Esta unidade pertence ao outro lado."
	if state.active_side != side:
		return "Não é o turno deste lado."
	if unit["routing"]:
		return "Unidades em retirada não recebem ordens."
	if unit["moved"]:
		return "Esta unidade já se moveu neste turno."
	if not state.map.in_bounds(destination):
		return "Destino fora do mapa."
	if destination == unit["pos"]:
		return "A unidade já está neste hexágono."
	if not state.map.is_passable(destination):
		return "Terreno intransponível: %s." % state.map.terrain_def_at(destination)["name"].to_lower()
	if state.unit_at(destination) != 0:
		return "Hexágono ocupado por outra unidade."
	var budget: int = unit["move_range"]
	var reach := reachable_for(state, unit_id)
	if reach["cost"].has(destination):
		return ""
	var unlimited := Pathfinding.reachable(state.map, unit["pos"], 100000, blocked_hexes(state, unit_id))
	if unlimited["cost"].has(destination):
		return "Fora do alcance de movimento: o caminho custa %d e a unidade dispõe de %d." % [unlimited["cost"][destination], budget]
	return "Sem caminho até o destino (bloqueado por terreno ou por outras unidades)."


## Move a unidade pelo caminho de menor custo. Resultado: {ok, message, path, cost}.
static func move_unit(state: RefCounted, side: String, unit_id: int, destination: Vector2i) -> Dictionary:
	var reason := check_move(state, side, unit_id, destination)
	if not reason.is_empty():
		return {"ok": false, "message": reason, "path": [], "cost": 0}
	var unit: Dictionary = state.units[unit_id]
	var reach := reachable_for(state, unit_id)
	var path := Pathfinding.path_to(reach["prev"], unit["pos"], destination)
	var cost: int = reach["cost"][destination]
	unit["pos"] = destination
	unit["moved"] = true
	unit["moved_steps"] = path.size() - 1
	var message := "%s move-se para %s (custo %d de %d)." % [
		unit["name"], state.map.terrain_def_at(destination)["name"].to_lower(), cost, unit["move_range"]]
	state.add_log(message)
	return {"ok": true, "message": message, "path": path, "cost": cost}
