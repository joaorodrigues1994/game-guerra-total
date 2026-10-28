extends Control
## Desenha o mapa de campanha (polígonos, fronteiras, nomes, capitais, marcadores de exércitos) e traduz
## cliques em seleção de província ou de exército.
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
const MARGIN := 36.0
const TERRAIN_BLEND := 0.12
const TERRAIN_TINT := {
	"plains": Color("c9d68a"),
	"hills": Color("b59a62"),
	"mountains": Color("8d8478"),
	"forest": Color("4f7a4a"),
	"river_valley": Color("8fc4b0"),
}

# Marcadores de exército
const MARKER_SIZE := Vector2(34, 20)
const MARKER_GAP := 4.0
const MAX_MARKERS := 6  # acima disso, o último espaço vira "+N" (a lista completa fica no painel)
const OWN_BORDER := Color("ffd84a")
const FOREIGN_BORDER := Color("e0483c")
const SELECTED_ARMY_BORDER := Color("ffffff")
const DESTINATION_COLOR := Color("7dff7d")

var controller: CampaignController


func bind(p_controller: CampaignController) -> void:
	controller = p_controller
	controller.selection_changed.connect(func(_id: String) -> void: queue_redraw())
	controller.army_selection_changed.connect(func(_id: int) -> void: queue_redraw())
	controller.state_changed.connect(queue_redraw)
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


# --- Marcadores de exércitos ------------------------------------------------

## Retângulos (em coordenadas de tela) dos marcadores da província: [{army_id, rect, overflow}].
## army_id = 0 indica o marcador "+N" de excedente. Usado tanto para desenhar quanto para o clique.
func marker_rects(province_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var army_ids: Array[int] = controller.state.armies_in(province_id)
	if army_ids.is_empty():
		return result
	var anchor := map_to_screen(controller.province_map.label_points[province_id]) + Vector2(0, 24)
	var width: float = controller.province_map.bounds_of(province_id).size.x * map_scale()
	var per_row := maxi(1, int((width * 0.85 + MARKER_GAP) / (MARKER_SIZE.x + MARKER_GAP)))
	var slots := mini(army_ids.size(), MAX_MARKERS)
	var overflow := army_ids.size() > MAX_MARKERS
	for i in slots:
		var row := i / per_row
		var col := i % per_row
		var in_row := mini(per_row, slots - row * per_row)
		var center := anchor + Vector2((col - (in_row - 1) / 2.0) * (MARKER_SIZE.x + MARKER_GAP),
			row * (MARKER_SIZE.y + MARKER_GAP))
		var is_overflow := overflow and i == slots - 1
		result.append({
			"army_id": 0 if is_overflow else army_ids[i],
			"rect": Rect2(center - MARKER_SIZE / 2.0, MARKER_SIZE),
			"overflow": is_overflow,
			"hidden_count": army_ids.size() - (slots - 1) if is_overflow else 0,
		})
	return result


## Marcador sob o ponto de tela: {province_id, army_id, overflow} ou {} se não houver.
func marker_at(screen_point: Vector2) -> Dictionary:
	for province_id in controller.province_map.ids:
		for marker in marker_rects(province_id):
			if marker["rect"].has_point(screen_point):
				return {"province_id": province_id, "army_id": marker["army_id"], "overflow": marker["overflow"]}
	return {}


# --- Entrada ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if controller == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		var marker := marker_at(event.position)
		if marker.is_empty():
			controller.select_at(screen_to_map(event.position))
		elif marker["overflow"]:
			controller.select_province(marker["province_id"])  # a lista de exércitos fica no painel
		else:
			controller.select_army(marker["army_id"])
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

	for id in controller.army_destination_ids():
		var outline := _screen_polygon(pmap.polygons[id])
		draw_colored_polygon(outline, Color(DESTINATION_COLOR, 0.2))
		outline.append(outline[0])
		draw_polyline(outline, DESTINATION_COLOR, 3.0, true)

	var selected := controller.selected_province_id
	if not selected.is_empty():
		var outline := _screen_polygon(pmap.polygons[selected])
		draw_colored_polygon(outline, Color(UiStyle.ACCENT, 0.22))
		outline.append(outline[0])
		draw_polyline(outline, UiStyle.ACCENT, 4.0, true)

	for id in pmap.ids:
		_draw_label(id)
	for id in pmap.ids:
		for marker in marker_rects(id):
			_draw_marker(marker)
	_draw_legend()


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


## Exército próprio: borda dourada. Estrangeiro: borda vermelha. Selecionado: borda branca grossa.
## "!" no canto indica encontro pendente. O número é a quantidade de unidades.
func _draw_marker(marker: Dictionary) -> void:
	var rect: Rect2 = marker["rect"]
	var font := ThemeDB.fallback_font
	if marker["overflow"]:
		draw_rect(rect, Color(0.12, 0.1, 0.08, 0.92))
		draw_rect(rect, LABEL_COLOR, false, 2.0)
		_draw_centered_text("+%d" % marker["hidden_count"], rect, 13, LABEL_COLOR)
		return
	var army: Dictionary = controller.state.armies[marker["army_id"]]
	var is_player: bool = army["owner"] == controller.state.player_country_id
	var fill := Color(controller.registry.countries[army["owner"]]["color"])
	var selected: bool = marker["army_id"] == controller.selected_army_id
	draw_rect(rect, fill.darkened(0.15))
	draw_rect(rect, SELECTED_ARMY_BORDER if selected else (OWN_BORDER if is_player else FOREIGN_BORDER),
		false, 4.0 if selected else 2.5)
	_draw_centered_text(str(army["units"].size()), rect, 13, Color.WHITE)
	if not controller.state.encounter_of_army(marker["army_id"]).is_empty():
		draw_string_outline(font, rect.position + Vector2(rect.size.x - 7, 3), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, LABEL_OUTLINE)
		draw_string(font, rect.position + Vector2(rect.size.x - 7, 3), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FOREIGN_BORDER)


func _draw_centered_text(text: String, rect: Rect2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := rect.position + Vector2((rect.size.x - text_size.x) / 2.0, (rect.size.y + text_size.y) / 2.0 - 4.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, LABEL_OUTLINE)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var y := size.y - 18.0
	var x := 10.0
	for entry in [["Seus exércitos", OWN_BORDER], ["Exércitos estrangeiros", FOREIGN_BORDER]]:
		var swatch := Rect2(Vector2(x, y), Vector2(18, 11))
		draw_rect(swatch, Color("5b6b7a"))
		draw_rect(swatch, entry[1], false, 2.0)
		draw_string(font, Vector2(x + 24, y + 10), entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LABEL_COLOR)
		x += 24 + font.get_string_size(entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18
