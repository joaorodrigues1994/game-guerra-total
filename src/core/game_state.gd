extends RefCounted
## Fonte única de verdade do estado mutável da partida.
## Definições estáticas (nomes, terreno, produção, geometria) ficam no Registry;
## aqui vive apenas o que muda durante o jogo.

var turn: int = 1
var player_country_id: String = ""
## id da província -> {owner, population, buildings, garrison}
var provinces: Dictionary = {}
## id do país -> {resources}
var countries: Dictionary = {}


## Cria o estado inicial a partir dos dados validados. Retorna false se o país do jogador não existir.
func setup_from_registry(registry: RefCounted, p_player_country_id: String) -> bool:
	if not registry.countries.has(p_player_country_id):
		return false
	turn = 1
	player_country_id = p_player_country_id
	provinces = {}
	countries = {}
	for id in registry.countries:
		countries[id] = {"resources": registry.countries[id]["starting_resources"].duplicate()}
	for id in registry.provinces:
		var def: Dictionary = registry.provinces[id]
		provinces[id] = {
			"owner": def["owner"],
			"population": int(def["population"]),
			"buildings": def["buildings"].duplicate(),
			"garrison": int(def["garrison"]),
		}
	return true


func owner_of(province_id: String) -> String:
	return provinces[province_id]["owner"] if provinces.has(province_id) else ""


func to_dict() -> Dictionary:
	return {
		"turn": turn,
		"player_country_id": player_country_id,
		"provinces": provinces.duplicate(true),
		"countries": countries.duplicate(true),
	}
