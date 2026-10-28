extends RefCounted
## Processamento de turno. A ordem das etapas é fixa e está documentada em docs/ARCHITECTURE.md.
## Cada etapa roda exatamente uma vez por chamada de end_turn.

const EconomyCalculator := preload("res://src/economy/economy_calculator.gd")

const PHASES: Array[StringName] = [
	&"validate_state",         # valida o estado; se inválido, aborta sem alterar nada
	&"income_expenses",       # credita receitas e debita manutenção (sobre o estado do início do turno)
	&"construction_progress", # avança e conclui construções
	&"recruitment",           # avança recrutamentos e cria as unidades concluídas
	&"ai_actions",            # (futuro) ações dos países controlados pela IA
	&"military_movement",     # (futuro) movimentações militares
	&"advance_turn",          # incrementa o número do turno
	&"events",                # notifica a interface (turn_ended)
]

var _processing: bool = false


## Encerra o turno. Devolve o relatório:
##   ok, errors, phases (etapas executadas, na ordem), turn_before, turn_after,
##   income / upkeep / shortfall (por país), completed_buildings, completed_units.
## `bus` (opcional) recebe turn_phase_processed a cada etapa e turn_ended no fim.
func end_turn(registry: RefCounted, state: RefCounted, bus: Object = null) -> Dictionary:
	var phases: Array[StringName] = []
	var report := {
		"ok": false,
		"errors": [],
		"phases": phases,
		"turn_before": state.turn,
		"turn_after": state.turn,
		"income": {},
		"upkeep": {},
		"shortfall": {},
		"completed_buildings": [],
		"completed_units": [],
	}
	if _processing:
		report["errors"].append("O encerramento do turno já está em andamento.")
		return report

	_processing = true
	for phase in PHASES:
		_run_phase(phase, registry, state, report, bus)
		phases.append(phase)
		if bus != null:
			bus.turn_phase_processed.emit(phase)
		if not report["errors"].is_empty():
			break
	_processing = false
	report["ok"] = report["errors"].is_empty()
	return report


func _run_phase(phase: StringName, registry: RefCounted, state: RefCounted, report: Dictionary, bus: Object) -> void:
	match phase:
		&"validate_state":
			for problem in validate_state(registry, state):
				report["errors"].append(problem)
		&"income_expenses":
			_income_expenses(registry, state, report)
		&"construction_progress":
			_construction_progress(state, report)
		&"recruitment":
			_recruitment_progress(registry, state, report)
		&"advance_turn":
			state.turn += 1
			report["turn_after"] = state.turn
		&"events":
			if bus != null and bus.has_signal("turn_ended"):
				bus.turn_ended.emit(state.turn)
		_:
			pass  # ai_actions e military_movement: implementados nas fases seguintes.


## Lista de problemas que impedem o processamento; vazia se o estado está consistente.
func validate_state(registry: RefCounted, state: RefCounted) -> PackedStringArray:
	var problems := PackedStringArray()
	for country_id in state.countries:
		if not registry.countries.has(country_id):
			problems.append("País desconhecido no estado: %s" % country_id)
			continue
		var resources: Dictionary = state.countries[country_id]["resources"]
		for res in registry.rules["resources"]:
			if not resources.has(res) or typeof(resources[res]) != TYPE_INT or resources[res] < 0:
				problems.append("Recurso inválido (%s) em %s" % [res, country_id])
	for province_id in state.provinces:
		var province: Dictionary = state.provinces[province_id]
		if not registry.provinces.has(province_id) or not state.countries.has(province["owner"]):
			problems.append("Província ou dono inválido: %s" % province_id)
			continue
		for entry in province["constructions"]:
			if not registry.buildings.has(entry["building"]) or entry["remaining"] < 1:
				problems.append("Construção pendente inválida em %s" % province_id)
		for entry in province["recruitments"]:
			if not registry.units.has(entry["unit"]) or entry["remaining"] < 1:
				problems.append("Recrutamento pendente inválido em %s" % province_id)
	for unit in state.units:
		if not registry.units.has(unit["type"]) or not state.provinces.has(unit["province"]):
			problems.append("Unidade inválida: %s" % str(unit["id"]))
	return problems


## Receitas e manutenção são calculadas sobre o estado do INÍCIO do turno: o que for concluído
## neste turno só passa a render (ou custar) a partir do próximo.
## Se a manutenção superar o saldo, paga-se o que há (recursos nunca ficam negativos) e o
## déficit é registrado em report["shortfall"].
func _income_expenses(registry: RefCounted, state: RefCounted, report: Dictionary) -> void:
	var country_ids: Array = state.countries.keys()
	country_ids.sort()
	for country_id in country_ids:
		var income := EconomyCalculator.country_income(registry, state, country_id)
		var upkeep := EconomyCalculator.country_upkeep(registry, state, country_id)
		var resources: Dictionary = state.countries[country_id]["resources"]
		var shortfall := {}
		for res in registry.rules["resources"]:
			resources[res] += income[res]
			var paid := mini(upkeep[res], resources[res])
			resources[res] -= paid
			if upkeep[res] > paid:
				shortfall[res] = upkeep[res] - paid
		report["income"][country_id] = income
		report["upkeep"][country_id] = upkeep
		if not shortfall.is_empty():
			report["shortfall"][country_id] = shortfall


func _construction_progress(state: RefCounted, report: Dictionary) -> void:
	var province_ids: Array = state.provinces.keys()
	province_ids.sort()
	for province_id in province_ids:
		var province: Dictionary = state.provinces[province_id]
		var pending: Array = []
		for entry in province["constructions"]:
			entry["remaining"] -= 1
			if entry["remaining"] <= 0:
				province["buildings"].append(entry["building"])
				report["completed_buildings"].append({"province": province_id, "building": entry["building"]})
			else:
				pending.append(entry)
		province["constructions"] = pending


func _recruitment_progress(registry: RefCounted, state: RefCounted, report: Dictionary) -> void:
	var province_ids: Array = state.provinces.keys()
	province_ids.sort()
	for province_id in province_ids:
		var province: Dictionary = state.provinces[province_id]
		var pending: Array = []
		for entry in province["recruitments"]:
			entry["remaining"] -= 1
			if entry["remaining"] <= 0:
				var unit := {
					"id": state.next_unit_id,
					"type": entry["unit"],
					"owner": province["owner"],
					"province": province_id,
					"strength": int(registry.units[entry["unit"]]["strength"]),
				}
				state.next_unit_id += 1
				state.units.append(unit)
				report["completed_units"].append({"province": province_id, "unit": entry["unit"], "id": unit["id"]})
			else:
				pending.append(entry)
		province["recruitments"] = pending
