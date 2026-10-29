extends "res://tests/test_case.gd"
## Geometria hexagonal: vizinhança, distância, conversão para pixels e coordenadas offset.

const Hex := preload("res://src/battle/hex.gd")


func test_neighbors_are_the_six_adjacent_hexes() -> void:
	var origin := Vector2i(0, 0)
	var expected := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
	assert_eq(Hex.neighbors(origin), expected as Array[Vector2i], "vizinhos de (0,0) na ordem fixa")
	var center := Vector2i(4, -3)
	var seen := {}
	for n in Hex.neighbors(center):
		assert_eq(Hex.distance(center, n), 1, "vizinho a distância 1")
		assert_true(center in Hex.neighbors(n), "vizinhança é simétrica")
		seen[n] = true
	assert_eq(seen.size(), 6, "seis vizinhos distintos")


func test_distance_values_and_properties() -> void:
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "mesmo hexágono")
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, 0)), 3, "linha reta em q")
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -2)), 2, "diagonal")
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, 1)), 3, "misto")
	assert_eq(Hex.distance(Vector2i(-2, 3), Vector2i(3, -1)), 5, "negativos")
	var a := Vector2i(1, 2)
	var b := Vector2i(-3, 4)
	var c := Vector2i(5, -2)
	assert_eq(Hex.distance(a, b), Hex.distance(b, a), "simétrica")
	assert_true(Hex.distance(a, c) <= Hex.distance(a, b) + Hex.distance(b, c), "desigualdade triangular")


func test_within_returns_a_filled_hexagon() -> void:
	var cells := Hex.within(Vector2i(2, 1), 2)
	assert_eq(cells.size(), 19, "1 + 6 + 12 hexágonos")
	for cell in cells:
		assert_true(Hex.distance(Vector2i(2, 1), cell) <= 2, "dentro do raio")
	assert_eq(Hex.within(Vector2i(0, 0), 0), [Vector2i(0, 0)] as Array[Vector2i], "raio 0")


func test_neighbor_centers_are_equally_spaced_on_screen() -> void:
	var size := 30.0
	var center := Hex.to_pixel(Vector2i(3, 2), size)
	for n in Hex.neighbors(Vector2i(3, 2)):
		assert_true(is_equal_approx(center.distance_to(Hex.to_pixel(n, size)), size * Hex.SQRT3), "distância entre centros = √3 × raio")


func test_pixel_roundtrip_for_every_hex_of_a_region() -> void:
	for size in [18.0, 30.0, 47.5]:
		for q in range(-6, 7):
			for r in range(-6, 7):
				var hex := Vector2i(q, r)
				assert_eq(Hex.from_pixel(Hex.to_pixel(hex, size), size), hex, "ida e volta de %s (tamanho %s)" % [hex, size])


func test_points_inside_a_hex_map_back_to_it() -> void:
	var size := 40.0
	var hex := Vector2i(2, 3)
	var center := Hex.to_pixel(hex, size)
	var inner_radius := size * Hex.SQRT3 / 2.0  # apótema
	for i in 12:
		var angle := TAU * i / 12.0
		var point := center + Vector2(cos(angle), sin(angle)) * inner_radius * 0.9
		assert_eq(Hex.from_pixel(point, size), hex, "ponto %d dentro do hexágono" % i)
	for n in Hex.neighbors(hex):
		var toward := center + (Hex.to_pixel(n, size) - center) * 0.8
		assert_eq(Hex.from_pixel(toward, size), n, "perto do vizinho %s" % n)


func test_corners_lie_on_the_circle_of_the_hex() -> void:
	var center := Vector2(100, 50)
	var corners := Hex.corners(center, 25.0)
	assert_eq(corners.size(), 6, "seis vértices")
	for corner in corners:
		assert_true(is_equal_approx(corner.distance_to(center), 25.0), "vértice no raio")
	assert_true(is_equal_approx(corners[0].distance_to(corners[1]), 25.0), "lado = raio")


func test_axial_round_picks_the_nearest_hex() -> void:
	assert_eq(Hex.axial_round(0.1, -0.1), Vector2i(0, 0), "perto da origem")
	assert_eq(Hex.axial_round(0.9, 0.1), Vector2i(1, 0), "perto de (1,0)")
	assert_eq(Hex.axial_round(-1.2, 2.1), Vector2i(-1, 2), "negativos")


func test_offset_odd_r_conversion_roundtrip_and_adjacency() -> void:
	for row in 9:
		for col in 12:
			assert_eq(Hex.axial_to_offset(Hex.offset_to_axial(col, row)), Vector2i(col, row), "ida e volta (%d,%d)" % [col, row])
	# Linhas ímpares são deslocadas meio hexágono para a direita.
	var odd := Hex.offset_to_axial(2, 1)
	assert_eq(Hex.distance(odd, Hex.offset_to_axial(2, 0)), 1, "(2,1) toca (2,0)")
	assert_eq(Hex.distance(odd, Hex.offset_to_axial(3, 0)), 1, "(2,1) toca (3,0)")
	assert_eq(Hex.distance(odd, Hex.offset_to_axial(1, 0)), 2, "(2,1) não toca (1,0)")
	var even := Hex.offset_to_axial(2, 2)
	assert_eq(Hex.distance(even, Hex.offset_to_axial(1, 1)), 1, "(2,2) toca (1,1)")
	assert_eq(Hex.distance(even, Hex.offset_to_axial(2, 1)), 1, "(2,2) toca (2,1)")
	assert_eq(Hex.distance(even, Hex.offset_to_axial(3, 1)), 2, "(2,2) não toca (3,1)")
	assert_eq(Hex.distance(Hex.offset_to_axial(2, 2), Hex.offset_to_axial(3, 2)), 1, "mesma linha: colunas vizinhas")
