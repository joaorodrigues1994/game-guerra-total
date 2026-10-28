extends RefCounted
## Controlador da campanha: seleção, ações do jogador, encerramento de turno e dados de exibição.
## Lê Registry (definições) e GameState (estado mutável); não guarda cópia dos dados do jogo.
## Toda regra vive em CampaignActions, EconomyCalculator e TurnProcessor; aqui só se orquestra.

const CampaignActions := preload("res://src/campaign/campaign_actions.gd")
const EconomyCalculator := preload("res://src/economy/economy_calculator.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")

const MONTH_NAMES := [
	"Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
	"Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
]

signal selection_changed(province_id: String)
## O estado do jogo mudou (ação aceita ou turno encerrado): a interface deve se atualizar.
signal state_changed
signal turn_ended(report: Dictionary)
## Mensagem para o jogador (resultado de ação, motivo de rejeição, resumo do turno).
signal message_posted(text: String, is_error: bool)

var registry: RefCounted
var state: RefCounted
var province_map: RefCounted
var processor: TurnProcessor = TurnProcessor.new()
## Opcional: EventBus (autoload) que recebe os eventos de turno.
var bus: Object = null
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


# --- Ações do jogador ------------------------------------------------------

func build(province_id: String, building_id: String) -> Dictionary:
	return _finish_action(CampaignActions.start_construction(
		registry, state, state.player_country_id, province_id, building_id))


func recruit(province_id: String, unit_id: String) -> Dictionary:
	return _finish_action(CampaignActions.start_recruitment(
		registry, state, state.player_country_id, province_id, unit_id))


func end_turn() -> Dictionary:
	var report := processor.end_turn(registry, state, bus)
	if report["ok"]:
		state_changed.emit()
		turn_ended.emit(report)
		message_posted.emit(report_text(report), false)
	else:
		message_posted.emit("Não foi possível encerrar o turno: %s" % " ".join(PackedStringArray(report["errors"])), true)
	return report


func _finish_action(result: Dictionary) -> Dictionary:
	message_posted.emit(result["message"], not result["ok"])
	if result["ok"]:
		state_changed.emit()
	return result


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
	var owned_by_player: bool = owner_id == state.player_country_id

	var income := EconomyCalculator.province_income(registry, state, province_id)
	var income_lines: Array[Dictionary] = []
	for res in registry.rules["resources"]:
		if income[res] != 0:
			income_lines.append({"name": registry.rules["resource_names"][res], "amount": income[res]})
	var building_names: Array[String] = []
	for building_id in pstate["buildings"]:
		building_names.append(registry.buildings[building_id]["name"])
	var constructions: Array[Dictionary] = []
	for entry in pstate["constructions"]:
		constructions.append({"name": registry.buildings[entry["building"]]["name"], "remaining": entry["remaining"]})
	var recruitments: Array[Dictionary] = []
	for entry in pstate["recruitments"]:
		recruitments.append({"name": registry.units[entry["unit"]]["name"], "remaining": entry["remaining"]})
	var units := _unit_summary(province_id)
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
		"defense_bonus": EconomyCalculator.defense_bonus(registry, state, province_id),
		"income": income_lines,
		"buildings": building_names,
		"constructions": constructions,
		"recruitments": recruitments,
		"units": units,
		"neighbors": neighbors,
		"owned_by_player": owned_by_player,
		"build_options": build_options(province_id) if owned_by_player else [],
		"recruit_options": recruit_options(province_id) if owned_by_player else [],
	}


## Construções oferecidas para a província (as já concluídas não entram). reason vazio = disponível.
func build_options(province_id: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for building_id in registry.buildings:
		var def: Dictionary = registry.buildings[building_id]
		if not def["buildable"] or building_id in state.provinces[province_id]["buildings"]:
			continue
		var reason := CampaignActions.check_build(registry, state, state.player_country_id, province_id, building_id)
		options.append({
			"id": building_id,
			"name": def["name"],
			"cost": CampaignActions.format_amounts(registry, def["cost"]),
			"turns": int(def["build_turns"]),
			"effects": CampaignActions.describe_effects(registry, def["effects"]),
			"reason": reason,
			"available": reason.is_empty(),
		})
	return options


func recruit_options(province_id: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for unit_id in registry.units:
		var def: Dictionary = registry.units[unit_id]
		if not def["recruitable"]:
			continue
		var reason := CampaignActions.check_recruit(registry, state, state.player_country_id, province_id, unit_id)
		options.append({
			"id": unit_id,
			"name": def["name"],
			"cost": CampaignActions.format_amounts(registry, def["recruit_cost"]),
			"upkeep": CampaignActions.format_amounts(registry, def["upkeep"]),
			"turns": int(def["recruit_turns"]),
			"strength": int(def["strength"]),
			"reason": reason,
			"available": reason.is_empty(),
		})
	return options


func _unit_summary(province_id: String) -> Array[String]:
	var counts := {}
	var strength := {}
	for unit in state.units_in(province_id):
		counts[unit["type"]] = counts.get(unit["type"], 0) + 1
		strength[unit["type"]] = strength.get(unit["type"], 0) + unit["strength"]
	var lines: Array[String] = []
	for unit_type in counts:
		lines.append("%s × %d (%d homens)" % [registry.units[unit_type]["name"], counts[unit_type], strength[unit_type]])
	return lines


## Recursos do país com receita, despesa e saldo por turno (projeção sobre o estado atual).
func country_view(country_id: String) -> Dictionary:
	if not registry.countries.has(country_id):
		return {}
	var def: Dictionary = registry.countries[country_id]
	var income := EconomyCalculator.country_income(registry, state, country_id)
	var upkeep := EconomyCalculator.country_upkeep(registry, state, country_id)
	var resources: Array[Dictionary] = []
	for res in registry.rules["resources"]:
		resources.append({
			"id": res,
			"name": registry.rules["resource_names"][res],
			"amount": int(state.countries[country_id]["resources"][res]),
			"income": income[res],
			"upkeep": upkeep[res],
			"net": income[res] - upkeep[res],
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


## Resumo em português do que mudou no turno encerrado (para o jogador).
func report_text(report: Dictionary) -> String:
	var country_id: String = state.player_country_id
	var names: Dictionary = registry.rules["resource_names"]
	var lines := PackedStringArray()
	lines.append("Turno %d encerrado. Agora é o turno %d." % [report["turn_before"], report["turn_after"]])
	var income: Dictionary = report["income"][country_id]
	var upkeep: Dictionary = report["upkeep"][country_id]
	var gains := PackedStringArray()
	var costs := PackedStringArray()
	for res in registry.rules["resources"]:
		if income[res] != 0:
			gains.append("%s +%d" % [names[res], income[res]])
		if upkeep[res] != 0:
			costs.append("%s -%d" % [names[res], upkeep[res]])
	lines.append("Receitas: %s. Despesas: %s." % [
		", ".join(gains) if not gains.is_empty() else "nenhuma",
		", ".join(costs) if not costs.is_empty() else "nenhuma"])
	if report["shortfall"].has(country_id):
		var missing := PackedStringArray()
		for res in report["shortfall"][country_id]:
			missing.append("%s %d" % [names[res], report["shortfall"][country_id][res]])
		lines.append("Atenção: manutenção não paga (%s)." % ", ".join(missing))
	for done in report["completed_buildings"]:
		if state.owner_of(done["province"]) == country_id:
			lines.append("Construção concluída: %s em %s." % [
				registry.buildings[done["building"]]["name"], registry.provinces[done["province"]]["name"]])
	for done in report["completed_units"]:
		if state.owner_of(done["province"]) == country_id:
			lines.append("Unidade pronta: %s em %s." % [
				registry.units[done["unit"]]["name"], registry.provinces[done["province"]]["name"]])
	return "\n".join(lines)
