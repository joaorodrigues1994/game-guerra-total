extends RefCounted
## Processamento de turno. A ordem das etapas é fixa e está documentada em docs/ARCHITECTURE.md.
## Cada etapa roda exatamente uma vez por chamada de end_turn.

const EconomyCalculator := preload("res://src/economy/economy_calculator.gd")
const ArmyActions := preload("res://src/units/army_actions.gd")

const PHASES: Array[StringName] = [
	&"validate_state",         # valida o estado; se inválido, aborta sem alterar nada
	&"income_expenses",       # credita receitas e debita manutenção (sobre o estado do início do turno)
	&"construction_progress", # avança e conclui construções
	&"recruitment",           # avança recrutamentos; unidades concluídas entram em exércitos
	&"ai_actions",            # (futuro) ações dos países controlados pela IA
	&"military_movement",     # (futuro) ordens de movimento enfileiradas; hoje as ordens são imediatas
	&"advance_turn",          # incrementa o número do turno
	&"army_reset",            # novo turno: libera a movimentação e descarta encontros que não se aplicam mais
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
			for blocker in turn_blockers(registry, state):
				report["errors"].append(blocker)
		&"income_expenses":
			_income_expenses(registry, state, report)
		&"construction_progress":
			_construction_progress(state, report)
		&"recruitment":
			_recruitment_progress(registry, state, report)
		&"advance_turn":
			state.turn += 1
			report["turn_after"] = state.turn
		&"army_reset":
			ArmyActions.reset_movement(state)
			ArmyActions.refresh_encounters(state)
		&"events":
			if bus != null and bus.has_signal("turn_ended"):
				bus.turn_ended.emit(state.turn)
		_:
			pass  # ai_actions e military_movement: implementados nas fases seguintes.


## Condições (não são inconsistências) que impedem encerrar o turno: hoje, batalha ativa. É checada na etapa
## validate_state, então a tentativa falha de forma controlada, sem alterar nada nem processar parcialmente.
func turn_blockers(registry: RefCounted, state: RefCounted) -> PackedStringArray:
	var blockers := PackedStringArray()
	for battle_id in state.active_battles():
		blockers.append("Há uma batalha ativa (#%d em %s): conclua ou cancele a batalha antes de encerrar o turno." % [
			battle_id, registry.provinces[state.battles[battle_id]["province"]]["name"]])
	return blockers


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
	problems.append_array(_validate_armies(state))
	problems.append_array(_validate_battles(registry, state))
	return problems


## Registro de batalhas: ids coerentes e, nas ATIVAS, participantes existentes, na província da batalha, com a
## mesma composição do instantâneo, sem exército em duas batalhas e com o encontro ainda vinculado.
func _validate_battles(registry: RefCounted, state: RefCounted) -> PackedStringArray:
	var problems := PackedStringArray()
	var locked_by := {}
	for battle_id in state.battles:
		var battle: Dictionary = state.battles[battle_id]
		if battle_id >= state.next_battle_id or battle.get("id") != battle_id:
			problems.append("Registro de batalha inconsistente: id %s" % str(battle_id))
		var malformed := false
		for key in ["encounter_id", "province", "armies", "units"]:
			malformed = malformed or not battle.has(key)
		if malformed or typeof(battle.get("armies")) != TYPE_ARRAY or typeof(battle.get("units")) != TYPE_DICTIONARY:
			problems.append("Batalha %s com registro incompleto (faltam encounter_id, province, armies ou units)." % str(battle_id))
			continue
		if not (battle.get("status") in [state.BATTLE_ACTIVE, state.BATTLE_APPLIED, state.BATTLE_CANCELLED]):
			problems.append("Batalha %s com estado inválido: %s" % [str(battle_id), str(battle.get("status"))])
			continue
		if battle["status"] != state.BATTLE_ACTIVE:
			continue
		if not registry.provinces.has(battle["province"]):
			problems.append("Batalha %d em província inexistente: %s" % [battle_id, str(battle["province"])])
		var linked := false
		for encounter in state.encounters:
			linked = linked or (encounter.get("battle_id") == battle_id and encounter["id"] == battle["encounter_id"])
		if not linked:
			problems.append("Batalha ativa %d sem encontro vinculado (encontro #%s)." % [battle_id, str(battle["encounter_id"])])
		for army_id in battle["armies"]:
			if locked_by.has(army_id):
				problems.append("O exército %d está em mais de uma batalha ativa (%d e %d)." % [army_id, locked_by[army_id], battle_id])
			locked_by[army_id] = battle_id
			if not state.armies.has(army_id):
				problems.append("Batalha %d: o exército %d não existe mais." % [battle_id, army_id])
			elif state.armies[army_id]["province"] != battle["province"]:
				problems.append("Batalha %d: o exército %d saiu da província da batalha." % [battle_id, army_id])
		for unit_id in battle["units"]:
			if state.army_of_unit(unit_id) != battle["units"][unit_id]["army"]:
				problems.append("Batalha %d: a unidade %d não está mais no exército do instantâneo." % [battle_id, unit_id])
	# Sentido inverso: todo vínculo "battle_id" de um encontro precisa apontar para uma batalha ATIVA dele.
	for encounter in state.encounters:
		if not encounter.has("battle_id"):
			continue
		var linked_id: Variant = encounter["battle_id"]
		var target: Dictionary = state.battles.get(linked_id, {})
		if target.is_empty() or target.get("status") != state.BATTLE_ACTIVE or target.get("encounter_id") != encounter["id"]:
			problems.append("O encontro #%s aponta para a batalha %s, que não existe, não está ativa ou é de outro encontro." % [
				str(encounter["id"]), str(linked_id)])
	return problems


## Exércitos: dono e província válidos, unidades existentes e do dono (cada uma em um único exército)
## e generais válidos, do mesmo país e comandando no máximo um exército.
func _validate_armies(state: RefCounted) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen_units := {}
	var seen_generals := {}
	for army_id in state.armies:
		var army: Dictionary = state.armies[army_id]
		if not state.countries.has(army["owner"]) or not state.provinces.has(army["province"]):
			problems.append("Exército com dono ou província inválidos: %s" % str(army_id))
			continue
		for unit_id in army["units"]:
			var unit: Dictionary = state.unit_by_id(unit_id)
			if unit.is_empty() or unit["owner"] != army["owner"]:
				problems.append("Exército %s referencia unidade inválida: %s" % [str(army_id), str(unit_id)])
			elif seen_units.has(unit_id):
				problems.append("Unidade %s está em mais de um exército" % str(unit_id))
			seen_units[unit_id] = true
		var general_id: String = army["general"]
		if not general_id.is_empty():
			if not state.generals.has(general_id) or state.generals[general_id]["owner"] != army["owner"]:
				problems.append("Exército %s tem general inválido: %s" % [str(army_id), general_id])
			elif seen_generals.has(general_id):
				problems.append("General %s comanda mais de um exército" % general_id)
			seen_generals[general_id] = true
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
				var unit_id: int = state.add_unit(registry, entry["unit"], province["owner"], province_id)
				var army_id := ArmyActions.incorporate_new_unit(registry, state, unit_id)
				report["completed_units"].append(
					{"province": province_id, "unit": entry["unit"], "id": unit_id, "army": army_id})
			else:
				pending.append(entry)
		province["recruitments"] = pending
