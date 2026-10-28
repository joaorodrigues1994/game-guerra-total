extends RefCounted
## Fonte única de verdade do estado mutável da partida.
## Definições estáticas (nomes, terreno, produção, geometria, custos) ficam no Registry;
## aqui vive apenas o que muda durante o jogo.

var turn: int = 1
var player_country_id: String = ""
## id da província -> {owner, population, buildings, garrison, constructions, recruitments}
##   buildings:     ids de construções concluídas
##   constructions: fila [{building, remaining}] (turnos restantes)
##   recruitments:  fila [{unit, remaining}]
var provinces: Dictionary = {}
## id do país -> {resources: {id_do_recurso: int}}
var countries: Dictionary = {}
## Unidades recrutadas: [{id, type, owner, province, strength}].
## "province" é a província de origem. Representação mínima: no futuro estas unidades
## serão agrupadas em exércitos (com general e posição) sem mudar o restante do estado.
var units: Array[Dictionary] = []
var next_unit_id: int = 1


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
	return true


func owner_of(province_id: String) -> String:
	return provinces[province_id]["owner"] if provinces.has(province_id) else ""


func resources_of(country_id: String) -> Dictionary:
	return countries[country_id]["resources"]


## Unidades recrutadas cuja província de origem é a indicada.
func units_in(province_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in units:
		if unit["province"] == province_id:
			result.append(unit)
	return result


func to_dict() -> Dictionary:
	return {
		"turn": turn,
		"player_country_id": player_country_id,
		"provinces": provinces.duplicate(true),
		"countries": countries.duplicate(true),
		"units": units.duplicate(true),
		"next_unit_id": next_unit_id,
	}
