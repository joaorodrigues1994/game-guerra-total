extends RefCounted
## Regras de exércitos, generais e movimentação estratégica.
## Toda ação valida ANTES de alterar o estado: se algo falhar, o estado permanece intacto e o motivo
## é devolvido em português. Resultado: {ok: bool, message: String}.
##
## Regras de movimentação (a única relação diplomática é a guerra declarada, GameState.wars):
##  - um exército só se move por conexões do grafo de províncias (rules/provinces.json), 1 província por turno;
##  - só pode entrar em províncias do PRÓPRIO país ou de um país EM GUERRA com o seu (não há acordos de passagem);
##  - se o destino já contém exército de um país em GUERRA com o do exército, o movimento é feito mas fica registrado
##    um encontro pendente (state.encounters), e os exércitos envolvidos ficam parados até ele ser resolvido.
##    Exércitos de países em paz coexistem sem encontro (países sem guerra declarada NÃO são inimigos).
##
## BLOQUEIO POR BATALHA: um exército de uma batalha ATIVA (GameState.battles) não pode se mover, receber ou
## perder unidades nem ter o general alterado, e nenhum exército pode entrar na província de uma batalha
## ativa (o encontro dela está congelado). Todas as verificações passam por battle_lock_reason / check_*:
## a interface não é a única barreira.
##
## Regra de incorporação de recrutas: a unidade concluída entra no primeiro exército do mesmo país, na mesma
## província, com vaga e fora de encontro; se não houver, forma-se um novo exército com ela.


# --- Consultas -----------------------------------------------------------------

## Motivo do bloqueio do exército por uma batalha ativa; "" se ele está livre.
static func battle_lock_reason(state: RefCounted, army_id: int) -> String:
	var battle_id: int = state.battle_of_army(army_id)
	if battle_id == 0:
		return ""
	return "O exército %s está na batalha ativa #%d e fica bloqueado (não se move nem tem unidades ou general alterados) até ela ser concluída ou cancelada." % [
		state.armies[army_id]["name"], battle_id]


static func max_units(registry: RefCounted) -> int:
	return int(registry.rules["max_army_units"])


## Exército está parado por um encontro pendente?
static func is_engaged(state: RefCounted, army_id: int) -> bool:
	return not state.encounter_of_army(army_id).is_empty()


## Províncias para onde o exército poderia ir (vizinhas conectadas), com o motivo se não puder.
## Devolve [{id, link, reason}]; reason vazio = movimento permitido.
static func destinations(registry: RefCounted, state: RefCounted, country_id: String, army_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not state.armies.has(army_id):
		return result
	for link in registry.provinces[state.armies[army_id]["province"]]["neighbors"]:
		result.append({
			"id": link["id"],
			"link": link["type"],
			"reason": check_move(registry, state, country_id, army_id, link["id"]),
		})
	return result


# --- Movimentação -----------------------------------------------------------------

static func check_move(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, destination_id: String) -> String:
	if not state.armies.has(army_id):
		return "Exército inexistente."
	var army: Dictionary = state.armies[army_id]
	if army["owner"] != country_id:
		return "Este exército pertence a outro país: você não pode dar ordens a ele."
	var lock := battle_lock_reason(state, army_id)
	if not lock.is_empty():
		return lock
	if is_engaged(state, army_id):
		return "Este exército está em um encontro pendente com forças estrangeiras e não pode se mover."
	if army["moved"]:
		return "Este exército já se moveu neste turno."
	if not registry.provinces.has(destination_id):
		return "Província de destino inexistente."
	var battles_there: Array[int] = state.active_battles_in(destination_id)
	if not battles_there.is_empty():
		return "Há uma batalha ativa (#%d) em %s: nenhum exército pode entrar até ela ser concluída ou cancelada." % [
			battles_there[0], registry.provinces[destination_id]["name"]]
	if destination_id == army["province"]:
		return "O exército já está nesta província."
	var connected := false
	for link in registry.provinces[army["province"]]["neighbors"]:
		connected = connected or link["id"] == destination_id
	if not connected:
		return "Destino inválido: %s não é conectada a %s." % [
			registry.provinces[destination_id]["name"], registry.provinces[army["province"]]["name"]]
	var destination_owner: String = state.owner_of(destination_id)
	if destination_owner != country_id and not state.at_war(country_id, destination_owner):
		return "Sem acesso ao território de %s: não há guerra declarada nem acordo de passagem." % \
			registry.countries[destination_owner]["name"]
	return ""


## Move o exército. Em caso de encontro, "encounter" traz o registro criado/atualizado.
static func move_army(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, destination_id: String) -> Dictionary:
	var reason := check_move(registry, state, country_id, army_id, destination_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason, "encounter": {}}
	var army: Dictionary = state.armies[army_id]
	var origin_name: String = registry.provinces[army["province"]]["name"]
	army["province"] = destination_id
	army["moved"] = true
	var message := "%s moveu-se de %s para %s." % [army["name"], origin_name, registry.provinces[destination_id]["name"]]
	var encounter := _register_encounter(state, army_id)
	if not encounter.is_empty():
		message += " Encontro pendente com forças estrangeiras em %s: o confronto exigirá uma decisão futura." % \
			registry.provinces[destination_id]["name"]
	return {"ok": true, "message": message, "encounter": encounter}


## Se há exército de um país EM GUERRA com o do exército na província dele, registra (ou amplia) o encontro.
static func _register_encounter(state: RefCounted, army_id: int) -> Dictionary:
	var army: Dictionary = state.armies[army_id]
	var involved: Array[int] = [army_id]
	for other_id in state.armies_in(army["province"]):
		if state.at_war(army["owner"], state.armies[other_id]["owner"]):
			involved.append(other_id)
	if involved.size() == 1:
		return {}
	var existing: Dictionary = {}
	for encounter in state.encounters:
		if encounter["province"] == army["province"]:
			existing = encounter
	if existing.is_empty():
		existing = {"id": state.next_encounter_id, "province": army["province"], "turn": state.turn,
			"initiator": army_id, "armies": [], "countries": []}
		state.next_encounter_id += 1
		state.encounters.append(existing)
	for id in involved:
		if not (id in existing["armies"]):
			existing["armies"].append(id)
		var owner_id: String = state.armies[id]["owner"]
		if not (owner_id in existing["countries"]):
			existing["countries"].append(owner_id)
	existing["armies"].sort()
	existing["countries"].sort()
	return existing


## Remove encontros que já não se aplicam (menos de dois países na província). Chamado a cada turno.
static func refresh_encounters(state: RefCounted) -> void:
	var kept: Array[Dictionary] = []
	for encounter in state.encounters:
		if state.battle_of_encounter(encounter["id"]) != 0:
			kept.append(encounter)  # congelado enquanto a batalha estiver ativa
			continue
		var present: Array[int] = []
		var countries := {}
		for army_id in encounter["armies"]:
			if state.armies.has(army_id) and state.armies[army_id]["province"] == encounter["province"]:
				present.append(army_id)
				countries[state.armies[army_id]["owner"]] = true
		if countries.size() >= 2:
			encounter["armies"] = present
			kept.append(encounter)
	state.encounters = kept


## Libera a movimentação de todos os exércitos (início de um novo turno).
static func reset_movement(state: RefCounted) -> void:
	for army_id in state.armies:
		state.armies[army_id]["moved"] = false


# --- Organização ------------------------------------------------------------------

static func check_add_unit(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, unit_id: int) -> String:
	if not state.armies.has(army_id):
		return "Exército inexistente."
	var army: Dictionary = state.armies[army_id]
	if army["owner"] != country_id:
		return "Este exército pertence a outro país."
	var add_lock := battle_lock_reason(state, army_id)
	if not add_lock.is_empty():
		return add_lock
	var unit: Dictionary = state.unit_by_id(unit_id)
	if unit.is_empty():
		return "Unidade inexistente."
	if unit["owner"] != country_id:
		return "Esta unidade pertence a outro país."
	var current_army: int = state.army_of_unit(unit_id)
	if current_army != 0:
		return "A unidade já pertence ao exército %s." % state.armies[current_army]["name"]
	if unit["province"] != army["province"]:
		return "A unidade está em outra província."
	if army["units"].size() >= max_units(registry):
		return "Limite de unidades do exército excedido (%d de %d)." % [army["units"].size(), max_units(registry)]
	return ""


static func add_unit_to_army(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, unit_id: int) -> Dictionary:
	var reason := check_add_unit(registry, state, country_id, army_id, unit_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	state.armies[army_id]["units"].append(unit_id)
	return {"ok": true, "message": "%s incorporada ao %s." % [
		_unit_label(registry, state, unit_id), state.armies[army_id]["name"]]}


static func check_detach(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, unit_id: int) -> String:
	if not state.armies.has(army_id):
		return "Exército inexistente."
	var army: Dictionary = state.armies[army_id]
	if army["owner"] != country_id:
		return "Este exército pertence a outro país."
	var detach_lock := battle_lock_reason(state, army_id)
	if not detach_lock.is_empty():
		return detach_lock
	if not (unit_id in army["units"]):
		return "A unidade não pertence a este exército."
	if state.owner_of(army["province"]) != country_id:
		return "Só é possível deixar unidades de guarnição em território próprio."
	if is_engaged(state, army_id):
		return "Este exército está em um encontro pendente e não pode ser reorganizado."
	return ""


## Separa a unidade para a guarnição da província atual. Se o exército ficar vazio, é desfeito
## (e o general, liberado): nenhuma unidade desaparece, ela passa a ser guarnição.
static func detach_unit(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, unit_id: int) -> Dictionary:
	var reason := check_detach(registry, state, country_id, army_id, unit_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var army: Dictionary = state.armies[army_id]
	army["units"].erase(unit_id)
	state.unit_by_id(unit_id)["province"] = army["province"]
	var message := "%s separada do %s e posta na guarnição de %s." % [
		_unit_label(registry, state, unit_id), army["name"], registry.provinces[army["province"]]["name"]]
	var disbanded := false
	if army["units"].is_empty():
		state.armies.erase(army_id)
		disbanded = true
		message += " O exército ficou sem unidades e foi desfeito."
	return {"ok": true, "message": message, "disbanded": disbanded}


static func check_form_army(registry: RefCounted, state: RefCounted, country_id: String,
		province_id: String, unit_id: int) -> String:
	if not state.provinces.has(province_id):
		return "Província inexistente."
	if state.owner_of(province_id) != country_id:
		return "Você não controla esta província."
	var unit: Dictionary = state.unit_by_id(unit_id)
	if unit.is_empty():
		return "Unidade inexistente."
	if unit["owner"] != country_id:
		return "Esta unidade pertence a outro país."
	if state.army_of_unit(unit_id) != 0:
		return "A unidade já pertence a um exército."
	if unit["province"] != province_id:
		return "A unidade está em outra província."
	return ""


## Forma um novo exército com uma unidade da guarnição.
static func form_army(registry: RefCounted, state: RefCounted, country_id: String,
		province_id: String, unit_id: int) -> Dictionary:
	var reason := check_form_army(registry, state, country_id, province_id, unit_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var army_id: int = state.create_army(_new_army_name(registry, state, province_id), country_id, province_id)
	state.armies[army_id]["units"].append(unit_id)
	return {"ok": true, "army_id": army_id, "message": "Novo exército formado: %s." % state.armies[army_id]["name"]}


## Regra de incorporação de recrutas concluídos (ver cabeçalho). Devolve o id do exército.
static func incorporate_new_unit(registry: RefCounted, state: RefCounted, unit_id: int) -> int:
	var unit: Dictionary = state.unit_by_id(unit_id)
	for army_id in state.armies_in(unit["province"], unit["owner"]):
		if not is_engaged(state, army_id) and battle_lock_reason(state, army_id).is_empty() \
				and state.armies[army_id]["units"].size() < max_units(registry):
			state.armies[army_id]["units"].append(unit_id)
			return army_id
	var new_id: int = state.create_army(_new_army_name(registry, state, unit["province"]), unit["owner"], unit["province"])
	state.armies[new_id]["units"].append(unit_id)
	return new_id


## Mesclar `source_id` em `target_id` (mesmo país, mesma província, livres de batalha e de encontro, cabendo no limite
## de unidades). O alvo mantém nome e general; sem general, herda o do exército absorvido.
static func check_merge(registry: RefCounted, state: RefCounted, country_id: String,
		target_id: int, source_id: int) -> String:
	if target_id == source_id:
		return "Escolha dois exércitos diferentes."
	for army_id in [target_id, source_id]:
		if not state.armies.has(army_id):
			return "Exército inexistente."
		if state.armies[army_id]["owner"] != country_id:
			return "Este exército pertence a outro país."
	var target: Dictionary = state.armies[target_id]
	var source: Dictionary = state.armies[source_id]
	if target["province"] != source["province"]:
		return "Os exércitos estão em províncias diferentes."
	for army_id in [target_id, source_id]:
		var merge_lock := battle_lock_reason(state, army_id)
		if not merge_lock.is_empty():
			return merge_lock
		if is_engaged(state, army_id):
			return "O exército %s está em um encontro pendente e não pode ser reorganizado." % state.armies[army_id]["name"]
	var total: int = target["units"].size() + source["units"].size()
	if total > max_units(registry):
		return "Os dois exércitos somam %d unidades; o limite é %d." % [total, max_units(registry)]
	return ""


static func merge_armies(registry: RefCounted, state: RefCounted, country_id: String,
		target_id: int, source_id: int) -> Dictionary:
	var reason := check_merge(registry, state, country_id, target_id, source_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var target: Dictionary = state.armies[target_id]
	var source: Dictionary = state.armies[source_id]
	var message := "%s incorporado ao %s (%d unidades)." % [source["name"], target["name"], target["units"].size() + source["units"].size()]
	target["units"].append_array(source["units"])
	target["moved"] = target["moved"] or source["moved"]
	if not str(source["general"]).is_empty():
		if str(target["general"]).is_empty():
			target["general"] = source["general"]
		else:
			message += " %s deixou o comando." % registry.generals[source["general"]]["name"]
	state.armies.erase(source_id)
	return {"ok": true, "army_id": target_id, "message": message}


static func _new_army_name(registry: RefCounted, state: RefCounted, province_id: String) -> String:
	var base := "Exército de %s" % registry.provinces[province_id]["name"]
	var same := 0
	for army_id in state.armies:
		if str(state.armies[army_id]["name"]).begins_with(base):
			same += 1
	return base if same == 0 else "%s (%d)" % [base, same + 1]


# --- Generais -----------------------------------------------------------------------

static func check_assign_general(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, general_id: String) -> String:
	if not state.armies.has(army_id):
		return "Exército inexistente."
	var army: Dictionary = state.armies[army_id]
	if army["owner"] != country_id:
		return "Este exército pertence a outro país."
	var assign_lock := battle_lock_reason(state, army_id)
	if not assign_lock.is_empty():
		return assign_lock
	if not state.generals.has(general_id):
		return "General inexistente."
	var general_name: String = registry.generals[general_id]["name"]
	if state.generals[general_id]["owner"] != country_id:
		return "%s serve a outro país." % general_name
	var commanded: int = state.army_of_general(general_id)
	if commanded != 0:
		return "%s já comanda o %s." % [general_name, state.armies[commanded]["name"]]
	if not str(army["general"]).is_empty():
		return "O exército já tem um general (%s); remova-o antes." % registry.generals[army["general"]]["name"]
	return ""


static func assign_general(registry: RefCounted, state: RefCounted, country_id: String,
		army_id: int, general_id: String) -> Dictionary:
	var reason := check_assign_general(registry, state, country_id, army_id, general_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	state.armies[army_id]["general"] = general_id
	return {"ok": true, "message": "%s assumiu o comando do %s." % [
		registry.generals[general_id]["name"], state.armies[army_id]["name"]]}


static func check_unassign_general(state: RefCounted, country_id: String, army_id: int) -> String:
	if not state.armies.has(army_id):
		return "Exército inexistente."
	if state.armies[army_id]["owner"] != country_id:
		return "Este exército pertence a outro país."
	var unassign_lock := battle_lock_reason(state, army_id)
	if not unassign_lock.is_empty():
		return unassign_lock
	if str(state.armies[army_id]["general"]).is_empty():
		return "O exército não tem general."
	return ""


static func unassign_general(registry: RefCounted, state: RefCounted, country_id: String, army_id: int) -> Dictionary:
	var reason := check_unassign_general(state, country_id, army_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var general_id: String = state.armies[army_id]["general"]
	state.armies[army_id]["general"] = ""
	return {"ok": true, "message": "%s deixou o comando do %s." % [
		registry.generals[general_id]["name"], state.armies[army_id]["name"]]}


static func _unit_label(registry: RefCounted, state: RefCounted, unit_id: int) -> String:
	return "%s #%d" % [registry.units[state.unit_by_id(unit_id)["type"]]["name"], unit_id]
