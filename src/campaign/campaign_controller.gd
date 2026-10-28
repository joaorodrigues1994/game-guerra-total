extends RefCounted
## Controlador da campanha: seleção de província e dados prontos para exibição.
## Lê Registry (definições) e GameState (estado mutável); não guarda cópia dos dados do jogo.

const MONTH_NAMES := [
	"Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
	"Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
]

signal selection_changed(province_id: String)

var registry: RefCounted
var state: RefCounted
var province_map: RefCounted
var selected_province_id: String = ""


func setup(p_registry: RefCounted, p_state: RefCounted, p_province_map: RefCounted) -> void:
	registry = p_registry
	state = p_state
	province_map = p_province_map
	selected_province_id = ""


# --- Seleção ---------------------------------------------------------------

func select_province(province_id: String) -> bool:
	if not registry.provinces.has(province_id):
		return false
	_set_selection(province_id)
	return true


## Seleciona a província sob o ponto (coordenadas de mapa); fora de qualquer província, limpa a seleção.
func select_at(map_point: Vector2) -> String:
	var id: String = province_map.province_at(map_point)
	if id.is_empty():
		clear_selection()
	else:
		_set_selection(id)
	return id


func clear_selection() -> void:
	_set_selection("")


func _set_selection(province_id: String) -> void:
	if province_id == selected_province_id:
		return
	selected_province_id = province_id
	selection_changed.emit(province_id)


# --- Dados para exibição ---------------------------------------------------

## País cujas informações aparecem na barra superior: dono da província selecionada ou o do jogador.
func focus_country_id() -> String:
	if not selected_province_id.is_empty():
		return state.owner_of(selected_province_id)
	return state.player_country_id


func province_view(province_id: String) -> Dictionary:
	if not registry.provinces.has(province_id):
		return {}
	var def: Dictionary = registry.provinces[province_id]
	var pstate: Dictionary = state.provinces[province_id]
	var owner_id: String = pstate["owner"]
	var resource_names: Dictionary = registry.rules["resource_names"]

	var production: Array[Dictionary] = []
	for res in registry.rules["resources"]:
		if def["production"].has(res):
			production.append({"name": resource_names[res], "amount": def["production"][res]})
	var building_names: Array[String] = []
	for building_id in pstate["buildings"]:
		building_names.append(registry.buildings[building_id]["name"])
	var neighbors: Array[Dictionary] = []
	for link in def["neighbors"]:
		neighbors.append({
			"id": link["id"],
			"name": registry.provinces[link["id"]]["name"],
			"link": registry.rules["link_type_names"][link["type"]],
		})
	var capital_of := ""
	for country_id in registry.countries:
		if registry.countries[country_id]["capital"] == province_id:
			capital_of = registry.countries[country_id]["name"]

	return {
		"id": province_id,
		"name": def["name"],
		"city": def["city"]["name"] if def["city"] != null else "",
		"owner_id": owner_id,
		"owner_name": registry.countries[owner_id]["name"],
		"owner_color": Color(registry.countries[owner_id]["color"]),
		"capital_of": capital_of,
		"terrain_name": registry.rules["terrain_names"][def["terrain"]],
		"population": pstate["population"],
		"economic_value": int(def["economic_value"]),
		"strategic_value": int(def["strategic_value"]),
		"garrison": pstate["garrison"],
		"production": production,
		"buildings": building_names,
		"neighbors": neighbors,
	}


func country_view(country_id: String) -> Dictionary:
	if not registry.countries.has(country_id):
		return {}
	var def: Dictionary = registry.countries[country_id]
	var resources: Array[Dictionary] = []
	for res in registry.rules["resources"]:
		resources.append({
			"name": registry.rules["resource_names"][res],
			"amount": int(state.countries[country_id]["resources"][res]),
		})
	return {
		"id": country_id,
		"name": def["name"],
		"color": Color(def["color"]),
		"capital_name": registry.provinces[def["capital"]]["name"],
		"resources": resources,
		"is_player": country_id == state.player_country_id,
	}


func date_text() -> String:
	var months_elapsed: int = (state.turn - 1) * int(registry.rules["months_per_turn"])
	var total_months: int = int(registry.rules["start_month"]) - 1 + months_elapsed
	var month_index: int = total_months % 12
	var year: int = int(registry.rules["start_year"]) + floori(total_months / 12.0)
	return "%s de %d · Turno %d" % [MONTH_NAMES[month_index], year, state.turn]
