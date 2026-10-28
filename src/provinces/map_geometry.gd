extends RefCounted
## Funções puras de geometria 2D usadas na validação e na seleção de províncias.
## Convenção: províncias vizinhas compartilham os mesmos vértices em sua fronteira.


static func to_polygon(points: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in points:
		poly.append(Vector2(p[0], p[1]))
	return poly


static func signed_area(poly: PackedVector2Array) -> float:
	var total := 0.0
	var n := poly.size()
	for i in n:
		var p: Vector2 = poly[i]
		var q: Vector2 = poly[(i + 1) % n]
		total += p.x * q.y - q.x * p.y
	return total * 0.5


static func has_duplicate_vertices(poly: PackedVector2Array) -> bool:
	for i in poly.size():
		for j in range(i + 1, poly.size()):
			if poly[i].is_equal_approx(poly[j]):
				return true
	return false


## Verdadeiro se nenhuma aresta cruza outra aresta não adjacente.
static func is_simple(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	for i in n:
		for j in range(i + 1, n):
			if j == i + 1 or (i == 0 and j == n - 1):
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(
				poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n])
			if hit != null:
				return false
	return true


static func bounds(poly: PackedVector2Array) -> Rect2:
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return rect


## Segmentos (pares de vértices) que as duas fronteiras têm em comum.
static func shared_edges(a: PackedVector2Array, b: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for i in a.size():
		var p: Vector2 = a[i]
		var q: Vector2 = a[(i + 1) % a.size()]
		for j in b.size():
			var r: Vector2 = b[j]
			var s: Vector2 = b[(j + 1) % b.size()]
			if (p.is_equal_approx(r) and q.is_equal_approx(s)) \
					or (p.is_equal_approx(s) and q.is_equal_approx(r)):
				result.append(PackedVector2Array([p, q]))
	return result
