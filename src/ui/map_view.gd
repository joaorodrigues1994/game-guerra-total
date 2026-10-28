extends Control
## Desenha o mapa de campanha (polígonos, fronteiras, nomes, capitais) e traduz cliques em seleção.
## Não guarda dados de jogo: tudo vem do controlador (Registry + GameState).

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

const SEA_COLOR := Color("22465f")
const FRAME_COLOR := Color("0f1f2b")
const BORDER_COLOR := Color(0.12, 0.09, 0.06, 0.85)
const COUNTRY_BORDER_COLOR := Color(0.04, 0.03, 0.02)
const LABEL_COLOR := Color("fff6dc")
const LABEL_OUTLINE := Color(0.08, 0.06, 0.04, 0.95)
const STAR_COLOR := Color("ffd84a")
const MARGIN := 28.0
const TERRAIN_BLEND := 0.12
const TERRAIN_TINT := {
	"plains": Color("c9d68a"),
	"hills": Color("b59a62"),
	"mountains": Color("8d8478"),
	"forest": Color("4f7a4a"),
	"river_valley": Color("8fc4b0"),
}

var controller: CampaignController


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.selection_changed.connect(func(_id: String) -> void: queue_redraw())
	queue_redraw()


# --- Transformação mapa <-> tela --------------------------------------------

func map_scale() -> float:
	var map_size: Vector2 = controller.province_map.size
	var available := size - Vector2(MARGIN, MARGIN) * 2.0
	return maxf(minf(available.x / map_size.x, available.y / map_size.y), 0.01)


func map_origin() -> Vector2:
	return (size - controller.province_map.size * map_scale()) * 0.5


func map_to_screen(point: Vector2) -> Vector2:
	return map_origin() + point * map_scale()


func screen_to_map(point: Vector2) -> Vector2:
	return (point - map_origin()) / map_scale()


# --- Entrada ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if controller == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		controller.select_at(screen_to_map(event.position))
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		controller.clear_selection()
		accept_event()


# --- Desenho ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA_COLOR)
	if controller == null:
		return
	var pmap: RefCounted = controller.province_map
	draw_rect(Rect2(map_origin(), pmap.size * map_scale()).grow(2.0), FRAME_COLOR, false, 3.0)

	for id in pmap.ids:
		draw_colored_polygon(_screen_polygon(pmap.polygons[id]), _fill_color(id))
	for id in pmap.ids:
		var outline := _screen_polygon(pmap.polygons[id])
		outline.append(outline[0])
		draw_polyline(outline, BORDER_COLOR, 1.5, true)
	for border in pmap.borders:
		if controller.state.owner_of(border["a"]) != controller.state.owner_of(border["b"]):
			for segment in border["segments"]:
				draw_line(map_to_screen(segment[0]), map_to_screen(segment[1]), COUNTRY_BORDER_COLOR, 3.5, true)

	var selected := controller.selected_province_id
	if not selected.is_empty():
		var outline := _screen_polygon(pmap.polygons[selected])
		draw_colored_polygon(outline, Color(UiStyle.ACCENT, 0.22))
		outline.append(outline[0])
		draw_polyline(outline, UiStyle.ACCENT, 4.0, true)

	for id in pmap.ids:
		_draw_label(id)


func _screen_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in poly:
		result.append(map_to_screen(p))
	return result


func _fill_color(province_id: String) -> Color:
	var owner_id: String = controller.state.owner_of(province_id)
	var base := Color(controller.registry.countries[owner_id]["color"])
	var terrain: String = controller.registry.provinces[province_id]["terrain"]
	return base.lerp(TERRAIN_TINT.get(terrain, base), TERRAIN_BLEND)


func _draw_label(province_id: String) -> void:
	var pmap: RefCounted = controller.province_map
	var anchor := map_to_screen(pmap.label_points[province_id])
	var bbox_width: float = pmap.bounds_of(province_id).size.x * map_scale()

	if _is_capital(province_id):
		_draw_star(anchor + Vector2(0, -20), 8.0)

	var font := ThemeDB.fallback_font
	var text: String = controller.registry.provinces[province_id]["name"]
	for font_size in [15, 12]:
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if text_width <= bbox_width * 0.9:
			var pos := anchor + Vector2(-text_width * 0.5, 5)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, LABEL_OUTLINE)
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)
			return


func _is_capital(province_id: String) -> bool:
	for country_id in controller.registry.countries:
		if controller.registry.countries[country_id]["capital"] == province_id:
			return true
	return false


func _draw_star(center: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, STAR_COLOR)
	points.append(points[0])
	draw_polyline(points, LABEL_OUTLINE, 1.5, true)
