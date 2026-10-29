extends RefCounted
## Geometria da grade hexagonal. Único lugar com as contas de hexágonos (vizinhança, distância,
## conversão para pixels e de volta). Ninguém mais deve repetir essas fórmulas.
##
## Escolha: coordenadas AXIAIS (q, r) em um Vector2i (x = q, y = r), hexágonos "pointy-top"
## (ponta para cima). A terceira coordenada cúbica é s = -q - r e não é armazenada.
## Vizinhos de (q, r): (+1,0) (+1,-1) (0,-1) (-1,0) (-1,+1) (0,+1)  (sentido anti-horário a partir de leste).
## Distância = (|dq| + |dq + dr| + |dr|) / 2.
## Pixels (tamanho = raio do hexágono): x = size * (√3 * q + √3/2 * r), y = size * 3/2 * r.
##
## Os cenários descrevem posições em "offset odd-r" (coluna, linha), mais natural para desenhar
## mapas retangulares: linhas ímpares deslocadas meio hexágono para a direita.
## offset_to_axial / axial_to_offset convertem entre as duas formas.

const SQRT3 := 1.7320508075688772

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbors(hex: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		result.append(hex + direction)
	return result


@warning_ignore("integer_division")
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dq + dr) + absi(dr)) / 2


## Todos os hexágonos a distância <= radius (inclui o próprio centro).
static func within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		for dr in range(maxi(-radius, -dq - radius), mini(radius, -dq + radius) + 1):
			result.append(center + Vector2i(dq, dr))
	return result


## Centro do hexágono em pixels (relativo à origem do mapa).
static func to_pixel(hex: Vector2i, size: float) -> Vector2:
	return Vector2(size * (SQRT3 * hex.x + SQRT3 / 2.0 * hex.y), size * 1.5 * hex.y)


## Hexágono que contém o ponto (inverso de to_pixel).
static func from_pixel(point: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * point.x - point.y / 3.0) / size
	var r := (2.0 / 3.0 * point.y) / size
	return axial_round(q, r)


## Arredonda coordenadas axiais fracionárias para o hexágono mais próximo (via cúbicas).
static func axial_round(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


## Os 6 vértices do hexágono, em pixels.
static func corners(center: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * size)
	return points


## (coluna, linha) "odd-r" -> axial.
static func offset_to_axial(col: int, row: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(col - (row - (row & 1)) / 2, row)


## Axial -> (coluna, linha) "odd-r".
static func axial_to_offset(hex: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(hex.x + (hex.y - (hex.y & 1)) / 2, hex.y)
