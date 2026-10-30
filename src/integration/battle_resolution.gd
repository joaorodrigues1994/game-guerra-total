extends RefCounted
## Resolução estratégica de uma batalha (Etapa 6): aplica à campanha o resultado tático guardado em
## battle["tactical_result"] (BattleState.result_summary) e leva a batalha ao estado terminal "applied".
##
## Duas fases, para a aplicação ser atômica do ponto de vista do estado da campanha:
##  1. plan(): SOMENTE LEITURA. Valida a batalha, o resultado, as unidades, os exércitos e os destinos e calcula
##     tudo o que mudará. Qualquer problema vira erro e nada é alterado.
##  2. apply(): tira um instantâneo das partes mutáveis, aplica o plano (só atribuições), grava o relatório em
##     battle["result"], transita a batalha para "applied" e revalida o estado com TurnProcessor.validate_state;
##     se algo falhar, restaura o instantâneo (nada fica pela metade e a batalha segue "active", com o
##     resultado tático preservado para diagnóstico ou nova tentativa).
## A aplicação única vem do ciclo de vida: só uma batalha "active" com resultado passa (cancelada e já aplicada
## são recusadas), e a transição para "applied" é terminal.
##
## REGRAS (documentadas em docs/ARCHITECTURE.md):
##  - Mapeamento: unidade tática -> unidade de campanha por `source_id` (instantâneo battle["units"]); nunca por
##    ordem, nome ou posição. Todas as unidades do instantâneo precisam aparecer exatamente uma vez.
##  - Efetivo: o final da unidade tática (0 .. efetivo inicial). Moral: a final (mesma escala 0..max_morale; sem
##    reescala), com piso 1 para sobreviventes (o adaptador recusa moral < 1 numa batalha futura).
##  - Unidade "destroyed" (efetivo 0) é removida; "fled" (saiu do campo) sobrevive com o efetivo e a moral finais.
##    Exército sem unidades é removido (general liberado). Não há reposição nem recuperação extra.
##  - Vencedor permanece. Perdedor com sobreviventes recua; "draw": recua o INVASOR (lado cujo país não é o dono da
##    província); se o dono não for nenhum dos dois, ninguém recua.
##  - Retirada: caminho mais curto até uma província do PRÓPRIO país, passando só por províncias acessíveis pelas
##    regras de movimento (própria ou de país em guerra), sem exército hostil e sem batalha ativa; empate de
##    distância decidido pelo id da província. Sem destino, o exército derrotado é DESTRUÍDO (unidades removidas,
##    general liberado); nunca teletransporta.
##  - O encontro da batalha deixa de existir se restar um só país na província; senão continua pendente.
##
## Convenção de retorno: {ok, battle_id, errors, message, report}.

const BattleLifecycle := preload("res://src/integration/battle_lifecycle.gd")
const BattleRequest := preload("res://src/integration/battle_request.gd")
const GameState := preload("res://src/core/game_state.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")

const STATUSES: Array[String] = ["firm", "shaken", "routing", "fled", "destroyed"]
const MIN_SURVIVOR_MORALE := 1


# --- Aplicação -------------------------------------------------------------------------------------

## Valida e aplica o resultado tático à campanha. Em qualquer falha o estado fica exatamente como estava.
## `validator` (opcional) substitui a validação final do estado: Callable(registry, state) -> PackedStringArray
## (usado pelos testes para provar o desfazer; o padrão é TurnProcessor.validate_state).
static func apply(registry: RefCounted, state: RefCounted, battle_id: int, validator: Callable = Callable()) -> Dictionary:
	var planned := plan(registry, state, battle_id)
	if not planned["ok"]:
		return _fail(planned["errors"], battle_id)
	var report: Dictionary = planned["report"]
	var saved := _snapshot(state, battle_id)
	_commit(state, battle_id, report)
	var problems: PackedStringArray = validator.call(registry, state) if validator.is_valid() 		else TurnProcessor.new().validate_state(registry, state)
	if not problems.is_empty():
		_restore(state, battle_id, saved)
		var errors := PackedStringArray(["A aplicação deixaria a campanha inconsistente e foi desfeita:"])
		for problem in problems:
			errors.append(problem)
		return _fail(errors, battle_id)
	var lines := describe(registry, report)
	return {"ok": true, "battle_id": battle_id, "errors": PackedStringArray(), "report": report,
		"message": " ".join(lines)}


## Calcula, sem alterar nada, o que a aplicação faria. Devolve {ok, errors, report}.
static func plan(registry: RefCounted, state: RefCounted, battle_id: int) -> Dictionary:
	var errors := PackedStringArray()
	var reason := BattleLifecycle.check_can_apply(state, battle_id)
	if not reason.is_empty():
		return _planned(errors, {}, [reason])
	var battle: Dictionary = state.battles[battle_id]
	var tactical: Variant = battle.get("tactical_result", {})
	if typeof(tactical) != TYPE_DICTIONARY or tactical.is_empty():
		return _planned(errors, {}, ["A batalha #%d ainda não tem resultado tático: nada a aplicar." % battle_id])
	var before := TurnProcessor.new().validate_state(registry, state)
	if not before.is_empty():
		var list: Array = ["A campanha está inconsistente antes da aplicação (batalha #%d):" % battle_id]
		for problem in before:
			list.append(problem)
		return _planned(errors, {}, list)

	var entries := _entries(battle, tactical, errors)
	var unit_plans := _unit_plans(state, battle, entries, errors)
	if not errors.is_empty():
		return _planned(errors, {}, [])

	var winner: String = tactical["winner"]
	var retreating := _retreating_side(state, battle, winner)
	var army_plans := {}
	var removed := {}
	for army_id in battle["armies"]:
		var army: Dictionary = state.armies[army_id]
		var survivors := 0
		var strength_before := 0
		var strength_after := 0
		for unit_id in battle["units"]:
			if battle["units"][unit_id]["army"] != army_id:
				continue
			var unit_plan: Dictionary = unit_plans[unit_id]
			strength_before += unit_plan["strength_before"]
			if not unit_plan["removed"]:
				survivors += 1
				strength_after += unit_plan["strength_after"]
		var side := _side_of_army(battle, army_id)
		var entry := {
			"army_id": army_id, "name": army["name"], "owner": army["owner"], "side": side, "from": army["province"],
			"to": army["province"], "path": [], "units_before": army["units"].size(), "units_after": survivors,
			"strength_before": strength_before, "strength_after": strength_after, "outcome": "stays",
		}
		if survivors == 0:
			entry["outcome"] = "removed"
			removed[army_id] = true
		elif side == retreating:
			var route := retreat_route(registry, state, army["owner"], army["province"])
			if route.is_empty():
				# Sem para onde ir, o exército derrotado é destruído: as unidades que sobraram se dispersam.
				entry["outcome"] = "removed"
				entry["no_route"] = true
				entry["units_after"] = 0
				entry["strength_after"] = 0
				removed[army_id] = true
				for unit_id in battle["units"]:
					if battle["units"][unit_id]["army"] == army_id:
						unit_plans[unit_id]["removed"] = true
						unit_plans[unit_id]["dispersed"] = true
						unit_plans[unit_id]["strength_after"] = 0
			else:
				entry["outcome"] = "retreats"
				entry["to"] = route[route.size() - 1]
				entry["path"] = route
		army_plans[army_id] = entry
	var report := {
		"battle_id": battle_id, "applied_turn": state.turn, "province": battle["province"],
		"winner": winner, "reason": tactical.get("reason", ""), "text": tactical.get("text", ""),
		"retreating_side": retreating, "countries": {"player": battle["sides"]["player"]["country"],
		"enemy": battle["sides"]["enemy"]["country"]}, "units": unit_plans, "armies": army_plans,
	}
	return _planned(errors, report, [])


# --- Validação do resultado e das unidades -------------------------------------------------------------

## Entradas do resultado tático por source_id: {source_id -> {entry, side}}. Preenche `errors`.
static func _entries(battle: Dictionary, tactical: Dictionary, errors: PackedStringArray) -> Dictionary:
	var result := {}
	if tactical.get("scenario_id") != battle["scenario_id"]:
		errors.append("O resultado é do cenário '%s', não do da batalha ('%s')." % [str(tactical.get("scenario_id")), battle["scenario_id"]])
	if not (tactical.get("winner") in ["player", "enemy", "draw"]):
		errors.append("Resultado tático sem vencedor válido ('%s')." % str(tactical.get("winner")))
	var by_side: Variant = tactical.get("units")
	if typeof(by_side) != TYPE_DICTIONARY:
		errors.append("Resultado tático sem a lista de unidades.")
		return result
	for side in ["player", "enemy"]:
		if typeof(by_side.get(side)) != TYPE_ARRAY:
			errors.append("Resultado tático sem as unidades do lado '%s'." % side)
			continue
		for raw in by_side[side]:
			if typeof(raw) != TYPE_DICTIONARY:
				errors.append("Entrada de unidade inválida no lado '%s'." % side)
				continue
			var source_id := _as_int(raw.get("source_id"))
			if source_id <= 0 or not battle["units"].has(source_id):
				errors.append("O resultado traz a unidade tática %s (source_id %s), que não pertence à batalha." % [str(raw.get("unit_id")), str(raw.get("source_id"))])
			elif result.has(source_id):
				errors.append("A unidade %d aparece mais de uma vez no resultado." % source_id)
			elif not (source_id in battle["sides"][side]["units"]):
				errors.append("A unidade %d veio no lado '%s', mas pertence ao outro lado." % [source_id, side])
			else:
				result[source_id] = {"entry": raw, "side": side}
	for source_id in battle["units"]:
		if not result.has(source_id):
			errors.append("A unidade %d da batalha não aparece no resultado tático." % source_id)
	return result


static func _unit_plans(state: RefCounted, battle: Dictionary, entries: Dictionary, errors: PackedStringArray) -> Dictionary:
	var plans := {}
	for source_id in battle["units"]:
		if not entries.has(source_id):
			continue
		var snapshot: Dictionary = battle["units"][source_id]
		var entry: Dictionary = entries[source_id]["entry"]
		var current: Dictionary = state.unit_by_id(source_id)
		if current.is_empty():
			errors.append("A unidade %d não existe mais na campanha." % source_id)
			continue
		if current["owner"] != snapshot["owner"] or current["strength"] != snapshot["strength"] or current["morale"] != snapshot["morale"]:
			errors.append("A unidade %d mudou desde o início da batalha (dono, efetivo ou moral)." % source_id)
			continue
		var strength := _as_int(entry.get("strength"))
		var morale := _as_int(entry.get("morale"))
		var max_morale := _as_int(entry.get("max_morale"))
		var status := str(entry.get("status", ""))
		if strength < 0 or strength > snapshot["strength"]:
			errors.append("Unidade %d: efetivo final %s fora de 0..%d." % [source_id, str(entry.get("strength")), snapshot["strength"]])
			continue
		if max_morale < 1 or morale < 0 or morale > max_morale:
			errors.append("Unidade %d: moral final %s fora de 0..%s." % [source_id, str(entry.get("morale")), str(entry.get("max_morale"))])
			continue
		if not (status in STATUSES):
			errors.append("Unidade %d: situação tática desconhecida ('%s')." % [source_id, status])
			continue
		if (status == "destroyed") != (strength == 0):
			errors.append("Unidade %d: situação '%s' incoerente com o efetivo final %d." % [source_id, status, strength])
			continue
		var removed := status == "destroyed"
		plans[source_id] = {
			"unit_id": source_id, "army_id": snapshot["army"], "side": entries[source_id]["side"], "status": status,
			"removed": removed, "strength_before": snapshot["strength"], "strength_after": 0 if removed else strength,
			"morale_before": snapshot["morale"], "morale_after": morale if removed else clampi(morale, MIN_SURVIVOR_MORALE, max_morale),
		}
	# Os exércitos participantes precisam estar como no instantâneo (a validação geral já cobre unidades e província).
	for army_id in battle["armies"]:
		if not state.armies.has(army_id):
			errors.append("O exército %d da batalha não existe mais." % army_id)
			continue
		var expected: Array = []
		for source_id in battle["units"]:
			if battle["units"][source_id]["army"] == army_id:
				expected.append(source_id)
		var actual: Array = state.armies[army_id]["units"].duplicate()
		expected.sort()
		actual.sort()
		if expected != actual:
			errors.append("A composição do exército %d mudou desde o início da batalha." % army_id)
	return plans


# --- Retirada --------------------------------------------------------------------------------------------

## Lado que recua: o perdedor; no empate, o invasor (país diferente do dono da província). "" = ninguém.
static func _retreating_side(state: RefCounted, battle: Dictionary, winner: String) -> String:
	if winner == "player":
		return "enemy"
	if winner == "enemy":
		return "player"
	var owner_id: String = state.owner_of(battle["province"])
	for side in ["player", "enemy"]:
		if battle["sides"][side]["country"] == owner_id:
			return "enemy" if side == "player" else "player"
	return ""


static func _side_of_army(battle: Dictionary, army_id: int) -> String:
	return "player" if army_id in battle["sides"]["player"]["armies"] else "enemy"


## Rota de retirada (lista de províncias, a última é o destino) ou [] se não houver. Ver as regras no cabeçalho.
static func retreat_route(registry: RefCounted, state: RefCounted, country_id: String, from_province: String) -> Array:
	var distance := {from_province: 0}
	var previous := {}
	var frontier: Array = [from_province]
	var found: Array = []
	while not frontier.is_empty() and found.is_empty():
		var next_frontier: Array = []
		for node in frontier:
			var neighbor_ids: Array = []
			for link in registry.provinces[node]["neighbors"]:
				neighbor_ids.append(link["id"])
			neighbor_ids.sort()
			for neighbor in neighbor_ids:
				if distance.has(neighbor) or not _passable(state, country_id, neighbor):
					continue
				distance[neighbor] = distance[node] + 1
				previous[neighbor] = node
				next_frontier.append(neighbor)
				if state.owner_of(neighbor) == country_id:
					found.append(neighbor)
		next_frontier.sort()
		frontier = next_frontier
	if found.is_empty():
		return []
	found.sort()
	var route: Array = []
	var cursor: String = found[0]
	while cursor != from_province:
		route.push_front(cursor)
		cursor = previous[cursor]
	return route


## Uma província pode ser atravessada/ocupada na retirada: acessível pelas regras de movimento (própria ou de país
## em guerra), sem exército hostil (país em guerra com o que recua) e sem batalha ativa.
static func _passable(state: RefCounted, country_id: String, province_id: String) -> bool:
	var owner_id: String = state.owner_of(province_id)
	if owner_id != country_id and not state.at_war(country_id, owner_id):
		return false
	if not state.active_battles_in(province_id).is_empty():
		return false
	for army_id in state.armies_in(province_id):
		if state.at_war(country_id, state.armies[army_id]["owner"]):
			return false
	return true


# --- Aplicação (somente atribuições) e desfazer -------------------------------------------------------

static func _commit(state: RefCounted, battle_id: int, report: Dictionary) -> void:
	var unit_ids: Array = report["units"].keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit_plan: Dictionary = report["units"][unit_id]
		var army: Dictionary = state.armies[unit_plan["army_id"]]
		if unit_plan["removed"]:
			army["units"].erase(unit_id)
			for index in state.units.size():
				if state.units[index]["id"] == unit_id:
					state.units.remove_at(index)
					break
		else:
			var unit: Dictionary = state.unit_by_id(unit_id)
			unit["strength"] = unit_plan["strength_after"]
			unit["morale"] = unit_plan["morale_after"]
	var army_ids: Array = report["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army_plan: Dictionary = report["armies"][army_id]
		if army_plan["outcome"] == "removed":
			state.armies.erase(army_id)
		elif army_plan["outcome"] == "retreats":
			state.armies[army_id]["province"] = army_plan["to"]
			state.armies[army_id]["moved"] = true
	state.battles[battle_id]["result"] = report.duplicate(true)
	BattleLifecycle.transition(state, battle_id, GameState.BATTLE_APPLIED)
	_update_encounter(state, state.battles[battle_id]["encounter_id"])


## O encontro da batalha: continua só se ainda houver exércitos de 2+ países na província; senão é resolvido.
static func _update_encounter(state: RefCounted, encounter_id: int) -> void:
	var encounter := BattleRequest.find_encounter(state, encounter_id)
	if encounter.is_empty():
		return
	var present: Array[int] = []
	var countries := {}
	for army_id in encounter["armies"]:
		if state.armies.has(army_id) and state.armies[army_id]["province"] == encounter["province"]:
			present.append(army_id)
			countries[state.armies[army_id]["owner"]] = true
	if countries.size() < 2:
		state.encounters.erase(encounter)
		return
	encounter["armies"] = present
	if not (encounter["initiator"] in present):
		encounter["initiator"] = present[0]


static func _snapshot(state: RefCounted, battle_id: int) -> Dictionary:
	return {
		"armies": state.armies.duplicate(true), "units": state.units.duplicate(true),
		"encounters": state.encounters.duplicate(true), "battle": state.battles[battle_id].duplicate(true),
	}


static func _restore(state: RefCounted, battle_id: int, saved: Dictionary) -> void:
	state.armies = saved["armies"]
	state.units = saved["units"]
	state.encounters = saved["encounters"]
	state.battles[battle_id] = saved["battle"]


# --- Texto ----------------------------------------------------------------------------------------------------

## Linhas legíveis do relatório de aplicação (para mensagens e para o painel de resultado).
static func describe(registry: RefCounted, report: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var headline := "Batalha #%d: resultado aplicado à campanha. " % report["battle_id"]
	if report["winner"] == "draw":
		headline += "Empate."
	else:
		headline += "Vitória de %s." % registry.countries[report["countries"][report["winner"]]]["name"]
	lines.append(headline)
	var army_ids: Array = report["armies"].keys()
	army_ids.sort()
	for army_id in army_ids:
		var army_plan: Dictionary = report["armies"][army_id]
		var detail := "%s (%s): " % [army_plan["name"], registry.countries[army_plan["owner"]]["name"]]
		match army_plan["outcome"]:
			"removed":
				if army_plan.get("no_route", false):
					detail += "derrotado e sem rota de retirada (nenhuma província aliada alcançável): destruído, removido da campanha."
				else:
					detail += "destruído (sem sobreviventes), removido da campanha."
			"retreats":
				detail += "recuou para %s; %d de %d unidades, %d de %d homens." % [
					registry.provinces[army_plan["to"]]["name"], army_plan["units_after"], army_plan["units_before"],
					army_plan["strength_after"], army_plan["strength_before"]]
			_:
				detail += "permanece em %s; %d de %d unidades, %d de %d homens." % [
					registry.provinces[army_plan["from"]]["name"], army_plan["units_after"], army_plan["units_before"],
					army_plan["strength_after"], army_plan["strength_before"]]
		lines.append(detail)
	return lines


# --- Auxiliares -------------------------------------------------------------------------------------------------

static func _as_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value
	if typeof(value) == TYPE_FLOAT and value == floorf(value):
		return int(value)
	return -1


static func _planned(errors: PackedStringArray, report: Dictionary, extra: Array) -> Dictionary:
	for text in extra:
		errors.append(text)
	return {"ok": errors.is_empty(), "errors": errors, "report": report}


static func _fail(errors: PackedStringArray, battle_id: int) -> Dictionary:
	return {"ok": false, "battle_id": battle_id, "errors": errors, "report": {}, "message": " ".join(errors)}
