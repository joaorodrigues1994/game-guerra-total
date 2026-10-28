extends RefCounted
## Geometria do mapa de campanha, construída a partir do Registry.
## Responde "qual província está neste ponto?" e expõe polígonos, rótulos e fronteiras compartilhadas.
## Coordenadas em "unidades de mapa" (rules.map_size); a escala para a tela é feita pela interface.

const MapGeometry := preload("res://src/provinces/map_geometry.gd")

var size: Vector2 = Vector2.ZERO
var ids: Array[String] = []
var polygons: Dictionary = {}  # id -> PackedVector2Array
var label_points: Dictionary = {}  # id -> Vector2
## Fronteiras entre pares de províncias: [{a, b, segments}]
var borders: Array[Dictionary] = []


func build(registry: RefCounted) -> void:
	size = Vector2(registry.rules["map_size"][0], registry.rules["map_size"][1])
	ids = []
	polygons = {}
	label_points = {}
	borders = []
	for id in registry.provinces:
		ids.append(id)
	ids.sort()
	for id in ids:
		var map: Dictionary = registry.provinces[id]["map"]
		polygons[id] = MapGeometry.to_polygon(map["polygon"])
		label_points[id] = Vector2(map["label"][0], map["label"][1])
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var segments := MapGeometry.shared_edges(polygons[ids[i]], polygons[ids[j]])
			if not segments.is_empty():
				borders.append({"a": ids[i], "b": ids[j], "segments": segments})


func bounds_of(province_id: String) -> Rect2:
	return MapGeometry.bounds(polygons[province_id])


## Id da província que contém o ponto (em coordenadas de mapa) ou "" se não houver.
func province_at(point: Vector2) -> String:
	for id in ids:
		if Geometry2D.is_point_in_polygon(point, polygons[id]):
			return id
	return ""
