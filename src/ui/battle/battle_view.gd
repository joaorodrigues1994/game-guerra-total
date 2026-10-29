extends Control
## Mapa hexagonal da batalha: desenha terreno, destaques, unidades e traduz o mouse em hexágonos.
## Não guarda dados de jogo: lê o BattleController. Toda a geometria vem de Hex.

const BattleController := preload("res://src/battle/battle_controller.gd")
const Hex := preload("res://src/battle/hex.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

const MARGIN := 18.0
const SEA_COLOR := Color("1b2a38")
const GRID_COLOR := Color(0.05, 0.07, 0.05, 0.85)
const REACH_COLOR := Color(0.3, 0.65, 1.0, 0.38)
const TARGET_COLOR := Color(1.0, 0.25, 0.2, 0.5)
const SELECT_COLOR := Color("ffd84a")
const HOVER_COLOR := Color(1, 1, 1, 0.8)
const TEXT_COLOR := Color("fff6dc")
const TEXT_OUTLINE := Color(0.05, 0.04, 0.03, 0.95)
const SHAKEN_COLOR := Color("ff9f1a")
const ROUTING_COLOR := Color("d94bd9")

var controller: BattleController
var _hover_hex: Vector2i = BattleController.NO_HEX


func bind(p_controller: BattleController) -> void:
	controller = p_controller
	controller.state_changed.connect(queue_redraw)
	controller.selection_changed.connect(queue_redraw)
	controller.restarted.connect(queue_redraw)
	queue_redraw()


# --- Layout (hexágono <-> tela) -----------------------------------------------

## Raio do hexágono em pixels, ajustado para o mapa inteiro caber na área.
func hex_size() -> float:
	var bounds := _unit_bounds()
	var available := size - Vector2(MARGIN, MARGIN) * 2.0
	return maxf(minf(available.x / bounds.size.x, available.y / bounds.size.y), 8.0)


func origin() -> Vector2:
	var bounds := _unit_bounds()
	return size / 2.0 - bounds.get_center() * hex_size()


func hex_to_screen(hex: Vector2i) -> Vector2:
	return origin() + Hex.to_pixel(hex, hex_size())


## Hexágono do mapa sob o ponto de tela; NO_HEX se o ponto cai fora do mapa.
func screen_to_hex(point: Vector2) -> Vector2i:
	var hex := Hex.from_pixel(point - origin(), hex_size())
	return hex if controller.state.map.in_bounds(hex) else BattleController.NO_HEX


## Retângulo (em pixels, raio 1) que contém todos os hexágonos do mapa.
func _unit_bounds() -> Rect2:
	var rect := Rect2()
	var first := true
	for hex in controller.state.map.all_hexes():
		var center := Hex.to_pixel(hex, 1.0)
		var cell := Rect2(center - Vector2(Hex.SQRT3 / 2.0, 1.0), Vector2(Hex.SQRT3, 2.0))
		rect = cell if first else rect.merge(cell)
		first = false
	return rect


# --- Entrada ---------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if controller == null:
		return
	if event is InputEventMouseMotion:
		var hovered := screen_to_hex(event.position)
		if hovered != _hover_hex:
			_hover_hex = hovered
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var hex := screen_to_hex(event.position)
			if hex != BattleController.NO_HEX:
				controller.click_hex(hex)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			controller.clear_selection()
			accept_event()


# --- Desenho -----------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA_COLOR)
	if controller == null:
		return
	var state: RefCounted = controller.state
	var radius := hex_size()
	var reachable: Dictionary = controller.reachable_hexes()
	var targets: Array[int] = controller.attack_target_ids()

	for hex in state.map.all_hexes():
		var corners := Hex.corners(hex_to_screen(hex), radius)
		var terrain: Dictionary = state.map.terrain_def_at(hex)
		draw_colored_polygon(corners, Color(terrain["color"]))
		_draw_terrain_glyph(terrain["id"], hex_to_screen(hex), radius)
		if reachable.has(hex):
			draw_colored_polygon(corners, REACH_COLOR)
		_outline(corners, GRID_COLOR, 1.5)

	for id in targets:
		var corners := Hex.corners(hex_to_screen(state.units[id]["pos"]), radius)
		draw_colored_polygon(corners, TARGET_COLOR)
		_outline(corners, TARGET_COLOR.lightened(0.3), 3.0)

	if _hover_hex != BattleController.NO_HEX:
		_outline(Hex.corners(hex_to_screen(_hover_hex), radius), HOVER_COLOR, 2.0)

	for id in state.live_units():
		_draw_unit(state.units[id], id == controller.selected_unit_id)

	if controller.selected_hex != BattleController.NO_HEX and state.map.in_bounds(controller.selected_hex):
		_outline(Hex.corners(hex_to_screen(controller.selected_hex), radius), SELECT_COLOR, 3.5)


func _outline(corners: PackedVector2Array, color: Color, width: float) -> void:
	var points := corners.duplicate()
	points.append(corners[0])
	draw_polyline(points, color, width, true)


## Marcas simples (sem imagens): árvores, colinas e ondas, para o terreno não depender só da cor.
func _draw_terrain_glyph(terrain_id: String, center: Vector2, radius: float) -> void:
	match terrain_id:
		"forest":
			for offset in [Vector2(-0.35, 0.2), Vector2(0.3, 0.25), Vector2(0.0, -0.3)]:
				draw_circle(center + offset * radius, radius * 0.2, Color("234a22"))
		"hills":
			for offset in [Vector2(-0.3, 0.25), Vector2(0.3, 0.25)]:
				var base: Vector2 = center + offset * radius
				draw_colored_polygon(PackedVector2Array([
					base + Vector2(-0.3, 0.0) * radius, base + Vector2(0.0, -0.45) * radius, base + Vector2(0.3, 0.0) * radius]),
					Color("8a7240"))
		"water":
			for dy in [-0.2, 0.2]:
				var wave := PackedVector2Array()
				for i in 5:
					wave.append(center + Vector2((-0.5 + i * 0.25) * radius, (dy + (0.07 if i % 2 == 0 else -0.07)) * radius))
				draw_polyline(wave, Color("a9d2ee"), 1.5, true)


func _draw_unit(unit: Dictionary, selected: bool) -> void:
	var state: RefCounted = controller.state
	var center := hex_to_screen(unit["pos"])
	var radius := hex_size() * 0.58
	var side_color := Color(state.sides[unit["side"]]["color"])
	var status: String = state.status_of(unit)
	var border := Color(0.05, 0.05, 0.05)
	if status == "shaken":
		border = SHAKEN_COLOR
	elif status == "routing":
		border = ROUTING_COLOR
	if selected:
		border = SELECT_COLOR

	match unit["type"]:
		"cavalry":
			var diamond := PackedVector2Array([center + Vector2(0, -radius * 1.1), center + Vector2(radius * 1.1, 0),
				center + Vector2(0, radius * 1.1), center + Vector2(-radius * 1.1, 0)])
			draw_colored_polygon(diamond, side_color)
			_outline(diamond, border, 3.0 if selected or status != "firm" else 2.0)
		"artillery":
			draw_circle(center, radius, side_color)
			draw_arc(center, radius, 0.0, TAU, 24, border, 3.0 if selected or status != "firm" else 2.0, true)
			draw_line(center + Vector2(0, -radius * 0.2), center + Vector2(radius * 1.2, -radius * 0.9), Color(0.08, 0.08, 0.08), 4.0)
		_:
			var rect := Rect2(center - Vector2(radius * 1.15, radius * 0.8), Vector2(radius * 2.3, radius * 1.6))
			draw_rect(rect, side_color)
			draw_rect(rect, border, false, 3.0 if selected or status != "firm" else 2.0)

	var font := ThemeDB.fallback_font
	var label := str(unit["strength"])
	var font_size := clampi(int(hex_size() * 0.38), 9, 16)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos := center + Vector2(-text_size.x / 2.0, text_size.y / 4.0)
	draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, TEXT_OUTLINE)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)

	# Barras de efetivo (verde) e moral (azul) sob a unidade.
	var bar_width := radius * 2.3
	var bar_origin := center + Vector2(-bar_width / 2.0, radius * 0.95)
	_draw_bar(bar_origin, bar_width, float(unit["strength"]) / float(unit["max_strength"]), Color("5cc24a"))
	_draw_bar(bar_origin + Vector2(0, 5), bar_width, float(unit["morale"]) / float(unit["max_morale"]), Color("4aa3e0"))

	if status == "routing":
		draw_string_outline(font, center + Vector2(-radius * 1.1, -radius * 0.9), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, TEXT_OUTLINE)
		draw_string(font, center + Vector2(-radius * 1.1, -radius * 0.9), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ROUTING_COLOR)
	# Marcas de ações já gastas neste turno: azul = moveu, vermelho = atacou.
	if unit["moved"]:
		draw_circle(center + Vector2(-radius * 0.9, -radius * 1.1), 3.5, Color("4aa3e0"))
	if unit["attacked"]:
		draw_circle(center + Vector2(radius * 0.9, -radius * 1.1), 3.5, Color("e0483c"))


func _draw_bar(origin_point: Vector2, width: float, fraction: float, color: Color) -> void:
	draw_rect(Rect2(origin_point, Vector2(width, 4)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(origin_point, Vector2(width * clampf(fraction, 0.0, 1.0), 4)), color)
