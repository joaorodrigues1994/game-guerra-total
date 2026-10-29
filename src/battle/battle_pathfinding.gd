extends RefCounted
## Caminhos de custo mínimo (Dijkstra) sobre o mapa hexagonal. O custo é o do terreno de cada hexágono
## ENTRADO, não a distância em linha reta. Determinístico: empates resolvidos por ordem de linha/coluna
## e pela ordem fixa dos vizinhos.


## Hexágonos alcançáveis a partir de `start` com custo total <= budget.
## blocked: {hex: true} de hexágonos que não podem ser atravessados (unidades). Devolve:
##   cost: {hex: custo acumulado}  (inclui o próprio start com 0)
##   prev: {hex: hex anterior no melhor caminho}
static func reachable(map: RefCounted, start: Vector2i, budget: int, blocked: Dictionary) -> Dictionary:
	var cost := {start: 0}
	var prev := {}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var best_index := 0
		for i in range(1, frontier.size()):
			if _precedes(frontier[i], frontier[best_index], cost):
				best_index = i
		var current: Vector2i = frontier[best_index]
		frontier.remove_at(best_index)
		for n in map.neighbors(current):
			if blocked.has(n) or not map.is_passable(n):
				continue
			var new_cost: int = cost[current] + map.move_cost(n)
			if new_cost > budget:
				continue
			if not cost.has(n) or new_cost < cost[n]:
				cost[n] = new_cost
				prev[n] = current
				if not (n in frontier):
					frontier.append(n)
	return {"cost": cost, "prev": prev}


static func _precedes(a: Vector2i, b: Vector2i, cost: Dictionary) -> bool:
	if cost[a] != cost[b]:
		return cost[a] < cost[b]
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


## Caminho de `start` a `destination` (ambos incluídos) usando o resultado de reachable(); [] se inalcançável.
static func path_to(prev: Dictionary, start: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if destination != start and not prev.has(destination):
		return path
	var current := destination
	path.append(current)
	while current != start:
		current = prev[current]
		path.append(current)
	path.reverse()
	return path


## Custo para chegar a cada hexágono vindo de `target`, ignorando unidades (só terreno). Serve de
## "mapa de distância" para a IA se aproximar de um alvo contornando água.
static func distance_field(map: RefCounted, target: Vector2i) -> Dictionary:
	return reachable(map, target, 100000, {})["cost"]
