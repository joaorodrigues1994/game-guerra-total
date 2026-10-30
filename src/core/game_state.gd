extends RefCounted
## Fonte única de verdade do estado mutável da partida.
## Definições estáticas (nomes, terreno, produção, geometria, custos, atributos base) ficam no
## Registry; aqui vive apenas o que muda durante o jogo.

var turn: int = 1
var player_country_id: String = ""
## id da província -> {owner, population, buildings, garrison, constructions, recruitments}
##   buildings:     ids de construções concluídas
##   constructions: fila [{building, remaining}] (turnos restantes)
##   recruitments:  fila [{unit, remaining}]
var provinces: Dictionary = {}
## id do país -> {resources: {id_do_recurso: int}}
var countries: Dictionary = {}

## Instâncias de unidades recrutadas: [{id, type, owner, province, strength, morale, experience}].
##   id:       identificador da INSTÂNCIA (inteiro, único e estável na campanha)
##   type:     id da definição estática em units.json (nome, ataque etc. não são copiados)
##   province: onde a unidade está de guarnição (última província conhecida); só vale
##             enquanto ela não pertence a um exército. Ao sair de um exército passa a ser
##             a província do exército.
##   strength/morale/experience: dados mutáveis da instância.
var units: Array[Dictionary] = []
var next_unit_id: int = 1

## id do exército (inteiro) -> {id, name, owner, province, units, general, moved}
##   units:   ids de instâncias de unidades (única fonte de "quem está em qual exército")
##   general: id do general ("" = sem general) (única fonte de "quem comanda qual exército")
##   moved:   true se já usou a movimentação deste turno
var armies: Dictionary = {}
var next_army_id: int = 1

## id do general -> {owner, experience}. Nome e comando vêm do Registry.
var generals: Dictionary = {}

## Encontros pendentes entre exércitos de países diferentes na mesma província:
## [{id, province, turn, initiator, armies, countries}]. Contrato para uma futura batalha.
## Enquanto uma batalha ATIVA estiver registrada para o encontro, ele ganha o campo "battle_id" (e continua
## pendente: assim os exércitos seguem em encontro se a batalha for cancelada). O campo some ao cancelar.
var encounters: Array[Dictionary] = []
var next_encounter_id: int = 1

## Registro de batalhas (histórico preservado: nunca se apaga uma batalha). id (inteiro sequencial) -> {
##   id, encounter_id, province, turn (da campanha, no registro), status, countries [jogador, adversário],
##   sides {player|enemy: {country, armies, units}}, armies (todos os participantes, ordenados),
##   units {id da unidade: {army, type, category, owner, strength, morale}}   (INSTANTÂNEO antes da batalha),
##   scenario_id, scenario (cópia do cenário tático gerado), result (vazio até o resultado ser aplicado),
##   tactical_result (BattleState.result_summary guardado quando a cena tática termina; vazio antes; NÃO é aplicação),
##   history [{status, turn}] }
## Ciclo de vida (transições em BattleLifecycle): active -> applied | cancelled; applied e cancelled são finais.
## Exércitos de uma batalha ATIVA ficam bloqueados (ver battle_of_army e ArmyActions).
const BATTLE_ACTIVE := "active"
const BATTLE_APPLIED := "applied"
const BATTLE_CANCELLED := "cancelled"
var battles: Dictionary = {}
var next_battle_id: int = 1

## Guerras declaradas (a única relação diplomática que existe): chave do par de países em ordem alfabética
## ("aus|fra", ver war_key) -> {countries [a, b] ordenados, declared_by, turn}. Sem entrada = paz: países sem guerra
## declarada NÃO são inimigos (não se movem no território um do outro e seus exércitos não geram encontros).
## Não há paz negociada nem fim de guerra por enquanto.
var wars: Dictionary = {}


## Cria o estado inicial a partir dos dados validados. Retorna false se o país do jogador não existir.
func setup_from_registry(registry: RefCounted, p_player_country_id: String) -> bool:
	if not registry.countries.has(p_player_country_id):
		return false
	turn = 1
	player_country_id = p_player_country_id
	provinces = {}
	countries = {}
	units = []
	next_unit_id = 1
	armies = {}
	next_army_id = 1
	generals = {}
	encounters = []
	next_encounter_id = 1
	battles = {}
	next_battle_id = 1
	wars = {}
	for id in registry.countries:
		var resources := {}
		for res in registry.countries[id]["starting_resources"]:
			resources[res] = int(registry.countries[id]["starting_resources"][res])
		countries[id] = {"resources": resources}
	for id in registry.provinces:
		var def: Dictionary = registry.provinces[id]
		provinces[id] = {
			"owner": def["owner"],
			"population": int(def["population"]),
			"buildings": def["buildings"].duplicate(),
			"garrison": int(def["garrison"]),
			"constructions": [],
			"recruitments": [],
		}
	for id in registry.generals:
		generals[id] = {
			"owner": registry.generals[id]["nationality"],
			"experience": int(registry.generals[id]["experience"]),
		}
	for entry in registry.armies:
		var army_id := create_army(entry["name"], entry["owner"], entry["province"])
		for unit_type in entry["units"]:
			var unit_id := add_unit(registry, unit_type, entry["owner"], entry["province"])
			armies[army_id]["units"].append(unit_id)
		if entry["general"] != null:
			armies[army_id]["general"] = entry["general"]
	return true


## Chave canônica do par de países (a ordem dos argumentos não importa).
static func war_key(country_a: String, country_b: String) -> String:
	return "%s|%s" % ([country_a, country_b] if country_a <= country_b else [country_b, country_a])


## Há guerra declarada entre os dois países? Um país nunca está em guerra consigo mesmo.
func at_war(country_a: String, country_b: String) -> bool:
	return country_a != country_b and wars.has(war_key(country_a, country_b))


## Ids (ordenados) dos países em guerra com `country_id`.
func enemies_of(country_id: String) -> Array[String]:
	var result: Array[String] = []
	for key in wars:
		var pair: Array = wars[key]["countries"]
		if country_id in pair:
			result.append(pair[1] if pair[0] == country_id else pair[0])
	result.sort()
	return result


func owner_of(province_id: String) -> String:
	return provinces[province_id]["owner"] if provinces.has(province_id) else ""


func resources_of(country_id: String) -> Dictionary:
	return countries[country_id]["resources"]


# --- Unidades -----------------------------------------------------------------

## Cria uma instância de unidade (fora de qualquer exército) e devolve seu id.
func add_unit(registry: RefCounted, unit_type: String, owner_id: String, province_id: String) -> int:
	var def: Dictionary = registry.units[unit_type]
	var unit := {
		"id": next_unit_id,
		"type": unit_type,
		"owner": owner_id,
		"province": province_id,
		"strength": int(def["strength"]),
		"morale": int(def["morale"]),
		"experience": int(def["experience"]),
	}
	next_unit_id += 1
	units.append(unit)
	return unit["id"]


## Instância da unidade ou {} se não existir.
func unit_by_id(unit_id: int) -> Dictionary:
	for unit in units:
		if unit["id"] == unit_id:
			return unit
	return {}


## Id do exército que contém a unidade; 0 se ela está na guarnição.
func army_of_unit(unit_id: int) -> int:
	for army_id in armies:
		if unit_id in armies[army_id]["units"]:
			return army_id
	return 0


## Província onde a unidade se encontra (a do exército, ou a de guarnição).
func location_of_unit(unit_id: int) -> String:
	var army_id := army_of_unit(unit_id)
	if army_id != 0:
		return armies[army_id]["province"]
	var unit := unit_by_id(unit_id)
	return unit["province"] if not unit.is_empty() else ""


## Unidades presentes na província (guarnição e exércitos).
func units_in(province_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in units:
		if location_of_unit(unit["id"]) == province_id:
			result.append(unit)
	return result


## Unidades de guarnição (sem exército) na província, opcionalmente de um país.
func garrison_units(province_id: String, owner_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in units:
		if unit["province"] == province_id and army_of_unit(unit["id"]) == 0 \
				and (owner_id.is_empty() or unit["owner"] == owner_id):
			result.append(unit)
	return result


# --- Exércitos ----------------------------------------------------------------

## Cria um exército vazio e devolve seu id.
func create_army(army_name: String, owner_id: String, province_id: String) -> int:
	var army_id := next_army_id
	next_army_id += 1
	armies[army_id] = {
		"id": army_id,
		"name": army_name,
		"owner": owner_id,
		"province": province_id,
		"units": [],
		"general": "",
		"moved": false,
	}
	return army_id


## Ids dos exércitos na província (ordenados), opcionalmente só de um país.
func armies_in(province_id: String, owner_id: String = "") -> Array[int]:
	var result: Array[int] = []
	for army_id in armies:
		var army: Dictionary = armies[army_id]
		if army["province"] == province_id and (owner_id.is_empty() or army["owner"] == owner_id):
			result.append(army_id)
	result.sort()
	return result


## Efetivo total do exército: soma do efetivo atual das unidades.
func army_strength(army_id: int) -> int:
	var total := 0
	for unit_id in armies[army_id]["units"]:
		total += unit_by_id(unit_id).get("strength", 0)
	return total


## Id do exército comandado pelo general; 0 se ele está livre.
func army_of_general(general_id: String) -> int:
	for army_id in armies:
		if armies[army_id]["general"] == general_id:
			return army_id
	return 0


## Encontro pendente que envolve o exército, ou {} se não houver.
func encounter_of_army(army_id: int) -> Dictionary:
	for encounter in encounters:
		if army_id in encounter["armies"]:
			return encounter
	return {}


# --- Batalhas -----------------------------------------------------------------

## Ids das batalhas ativas, ordenados.
func active_battles() -> Array[int]:
	var result: Array[int] = []
	for battle_id in battles:
		if battles[battle_id]["status"] == BATTLE_ACTIVE:
			result.append(battle_id)
	result.sort()
	return result


## Id da batalha ATIVA da qual o exército participa (e que o bloqueia); 0 se estiver livre.
func battle_of_army(army_id: int) -> int:
	for battle_id in active_battles():
		if army_id in battles[battle_id]["armies"]:
			return battle_id
	return 0


## Id da batalha ATIVA registrada para o encontro; 0 se não houver.
func battle_of_encounter(encounter_id: int) -> int:
	for battle_id in active_battles():
		if battles[battle_id]["encounter_id"] == encounter_id:
			return battle_id
	return 0


## Ids das batalhas ativas na província.
func active_battles_in(province_id: String) -> Array[int]:
	var result: Array[int] = []
	for battle_id in active_battles():
		if battles[battle_id]["province"] == province_id:
			result.append(battle_id)
	return result


func to_dict() -> Dictionary:
	return {
		"turn": turn,
		"player_country_id": player_country_id,
		"provinces": provinces.duplicate(true),
		"countries": countries.duplicate(true),
		"units": units.duplicate(true),
		"next_unit_id": next_unit_id,
		"armies": armies.duplicate(true),
		"next_army_id": next_army_id,
		"generals": generals.duplicate(true),
		"encounters": encounters.duplicate(true),
		"next_encounter_id": next_encounter_id,
		"battles": battles.duplicate(true),
		"next_battle_id": next_battle_id,
		"wars": wars.duplicate(true),
	}
