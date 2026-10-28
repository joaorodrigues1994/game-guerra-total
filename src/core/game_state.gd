extends RefCounted
## Fonte única de verdade do estado mutável da partida.
## Na Fase 0 contém apenas o necessário para o esqueleto de turnos.

var turn: int = 1
var player_country_id: String = ""


func to_dict() -> Dictionary:
	return {
		"turn": turn,
		"player_country_id": player_country_id,
	}
