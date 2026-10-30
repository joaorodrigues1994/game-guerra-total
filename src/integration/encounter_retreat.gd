extends RefCounted
## Recuo do DEFENSOR de um encontro pendente, sem batalha. Defensor = país do encontro que NÃO é o do exército que
## iniciou o encontro (o que entrou na província). Só é possível se TODOS os exércitos do defensor no encontro tiverem
## uma rota até uma província do próprio país (mesma regra da retirada pós-batalha: BattleResolution.retreat_route);
## sem rota, o defensor não pode recuar e deve lutar. Nada de batalha é criada nem registrada; o atacante permanece.
## Depois do recuo o encontro termina (sobra um só país na província).
## Convenção de retorno: {ok, message}. Toda ação valida antes de alterar o estado.

const ArmyActions := preload("res://src/units/army_actions.gd")
const BattleRequest := preload("res://src/integration/battle_request.gd")
const BattleResolution := preload("res://src/integration/battle_resolution.gd")


## Exércitos do país `country_id` no encontro.
static func armies_of(state: RefCounted, encounter: Dictionary, country_id: String) -> Array[int]:
	var result: Array[int] = []
	for army_id in encounter["armies"]:
		if state.armies.has(army_id) and state.armies[army_id]["owner"] == country_id:
			result.append(army_id)
	return result


## Verdadeiro se `country_id` é o defensor do encontro (participa dele sem ter sido quem entrou na província).
static func is_defender(state: RefCounted, encounter: Dictionary, country_id: String) -> bool:
	if not (country_id in encounter["countries"]):
		return false
	var initiator: int = encounter.get("initiator", 0)
	return state.armies.has(initiator) and state.armies[initiator]["owner"] != country_id


## "" se o recuo é possível; senão o motivo.
static func check(registry: RefCounted, state: RefCounted, country_id: String, encounter_id: int) -> String:
	var encounter := BattleRequest.find_encounter(state, encounter_id)
	if encounter.is_empty():
		return "Encontro inexistente."
	if not is_defender(state, encounter, country_id):
		return "Só o defensor do encontro pode recuar."
	if state.battle_of_encounter(encounter_id) != 0:
		return "Já existe uma batalha ativa neste encontro."
	for army_id in armies_of(state, encounter, country_id):
		var route := BattleResolution.retreat_route(registry, state, country_id, state.armies[army_id]["province"])
		if route.is_empty():
			return "Não há província aliada alcançável para recuar: o exército %s deve lutar." % state.armies[army_id]["name"]
	return ""


static func retreat(registry: RefCounted, state: RefCounted, country_id: String, encounter_id: int) -> Dictionary:
	var reason := check(registry, state, country_id, encounter_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var encounter := BattleRequest.find_encounter(state, encounter_id)
	var origin: String = encounter["province"]
	var parts := PackedStringArray()
	for army_id in armies_of(state, encounter, country_id):
		var route := BattleResolution.retreat_route(registry, state, country_id, origin)
		var destination: String = route[route.size() - 1]
		state.armies[army_id]["province"] = destination
		state.armies[army_id]["moved"] = true
		parts.append("%s recuou para %s" % [state.armies[army_id]["name"], registry.provinces[destination]["name"]])
	ArmyActions.refresh_encounters(state)
	return {"ok": true, "message": "Sem combate: %s." % "; ".join(parts)}
