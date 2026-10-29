extends RefCounted
## Mapa hexagonal da batalha: terreno de cada hexágono e consultas (passagem, custo, defesa, bordas).
## Usa coordenadas axiais (ver Hex). Construído a partir das linhas de texto do cenário.

const Hex := preload("res://src/battle/hex.gd")

var width: int = 0
var height: int = 0
var terrain: Dictionary = {}       # Vector2i (axial) -> id do terreno
var terrain_defs: Dictionary = {}  # id -> definição (de terrain.json)


## rows: linhas do cenário (cada caractere é o "legend" de um terreno); linha 0 é o topo.
func build(rows: Array, defs: Dictionary) -> void:
	terrain_defs = defs
	terrain = {}
	height = rows.size()
	width = str(rows[0]).length() if height > 0 else 0
	var by_legend := {}
	for id in defs:
		by_legend[defs[id]["legend"]] = id
	for row in height:
		for col in width:
			terrain[Hex.offset_to_axial(col, row)] = by_legend[str(rows[row])[col]]


func in_bounds(hex: Vector2i) -> bool:
	return terrain.has(hex)


func terrain_id_at(hex: Vector2i) -> String:
	return terrain.get(hex, "")


func terrain_def_at(hex: Vector2i) -> Dictionary:
	return terrain_defs.get(terrain_id_at(hex), {})


func is_passable(hex: Vector2i) -> bool:
	return in_bounds(hex) and terrain_def_at(hex)["passable"]


## Custo de ENTRAR no hexágono (0 se intransponível ou fora do mapa).
func move_cost(hex: Vector2i) -> int:
	return int(terrain_def_at(hex).get("move_cost", 0)) if is_passable(hex) else 0


func defense_bonus(hex: Vector2i) -> float:
	return float(terrain_def_at(hex).get("defense_bonus", 0.0))


## Vizinhos que estão dentro do mapa (na ordem fixa de Hex.DIRECTIONS).
func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for n in Hex.neighbors(hex):
		if in_bounds(n):
			result.append(n)
	return result


## Todos os hexágonos, por linha e depois por coluna (ordem determinística).
func all_hexes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row in height:
		for col in width:
			result.append(Hex.offset_to_axial(col, row))
	return result


## Hexágonos da borda "west" (coluna 0) ou "east" (última coluna) que podem ser pisados.
func edge_hexes(edge: String) -> Array[Vector2i]:
	var col := 0 if edge == "west" else width - 1
	var result: Array[Vector2i] = []
	for row in height:
		var hex := Hex.offset_to_axial(col, row)
		if is_passable(hex):
			result.append(hex)
	return result


func is_edge(hex: Vector2i, edge: String) -> bool:
	return in_bounds(hex) and Hex.axial_to_offset(hex).x == (0 if edge == "west" else width - 1)
