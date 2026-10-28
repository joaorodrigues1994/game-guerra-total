extends "res://tests/test_case.gd"
## Movimentação estratégica de exércitos, encontros e reinício do movimento a cada turno.

const ArmyActions := preload("res://src/units/army_actions.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")

const INFANTRY := "unit_line_inf"


func _fra_army(game: Dictionary, province_id: String = "prov_paris") -> int:
	var state = game["state"]
	var army_id: int = state.create_army("Exército de teste", "fra", province_id)
	state.armies[army_id]["units"].append(state.add_unit(game["registry"], INFANTRY, "fra", province_id))
	return army_id


func _move(game: Dictionary, army_id: int, destination: String, country: String = "fra") -> Dictionary:
	return ArmyActions.move_army(game["registry"], game["state"], country, army_id, destination)


func _foreign_army_in(game: Dictionary, owner_id: String, province_id: String) -> int:
	var state = game["state"]
	var army_id: int = state.create_army("Forças de %s" % owner_id, owner_id, province_id)
	state.armies[army_id]["units"].append(state.add_unit(game["registry"], INFANTRY, owner_id, province_id))
	return army_id


func test_move_between_connected_own_provinces() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game)
	var unit_id: int = state.armies[army_id]["units"][0]
	var result := _move(game, army_id, "prov_strasbourg")
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[army_id]["province"], "prov_strasbourg", "nova localização")
	assert_true(state.armies[army_id]["moved"], "movimento consumido")
	assert_eq(state.location_of_unit(unit_id), "prov_strasbourg", "as unidades acompanham o exército")
	assert_eq(state.armies_in("prov_paris", "fra").size(), 0, "saiu de Paris")
	assert_eq(state.armies_in("prov_strasbourg", "fra"), [army_id] as Array[int], "chegou a Alsácia")
	assert_true(result["encounter"].is_empty() and state.encounters.is_empty(), "movimento pacífico: sem encontro")
	assert_true("moveu-se de Île-de-France para Alsácia" in result["message"], result["message"])


func test_destinations_come_from_the_province_graph() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	var dests := ArmyActions.destinations(game["registry"], game["state"], "fra", army_id)
	var ids := []
	for d in dests:
		ids.append(d["id"])
		if d["id"] == "prov_strasbourg":
			assert_eq(d["reason"], "", "Alsácia: própria e conectada")
		else:
			assert_true("Sem acesso" in d["reason"], "%s: %s" % [d["id"], d["reason"]])
	assert_eq(ids, ["prov_strasbourg", "prov_franconia"], "exatamente os vizinhos de Paris")


func test_connectivity_is_logical_not_visual() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	# Remove a ligação lógica Paris <-> Alsácia mantendo as geometrias vizinhas no mapa.
	game["registry"].provinces["prov_paris"]["neighbors"] = [{"id": "prov_franconia", "type": "land"}]
	var before: Dictionary = game["state"].to_dict()
	var result := _move(game, army_id, "prov_strasbourg")
	assert_true(not result["ok"] and "Destino inválido" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_unconnected_destination_is_rejected() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	var before: Dictionary = game["state"].to_dict()
	var result := _move(game, army_id, "prov_hungary")
	assert_true(not result["ok"] and "Destino inválido" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_nonexistent_destination_is_rejected() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	var before: Dictionary = game["state"].to_dict()
	for bad in ["prov_atlantida", ""]:
		var result := _move(game, army_id, bad)
		assert_true(not result["ok"] and "inexistente" in result["message"], "'%s': %s" % [bad, result["message"]])
	assert_true(not _move(game, 99999, "prov_strasbourg")["ok"], "exército inexistente")
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_foreign_army_cannot_be_ordered() -> void:
	var game := new_game()
	var state = game["state"]
	var foreign: int = state.armies_in("prov_bohemia")[0]
	var before: Dictionary = state.to_dict()
	var result := _move(game, foreign, "prov_moravia")
	assert_true(not result["ok"] and "pertence a outro país" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_no_access_to_foreign_territory() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	var before: Dictionary = game["state"].to_dict()
	var result := _move(game, army_id, "prov_franconia")  # Baviera
	assert_true(not result["ok"] and "Sem acesso ao território de Baviera" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_staying_in_place_is_rejected() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	var result := _move(game, army_id, "prov_paris")
	assert_true(not result["ok"] and "já está nesta província" in result["message"], result["message"])


func test_second_move_in_the_same_turn_is_rejected() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game)
	assert_true(_move(game, army_id, "prov_strasbourg")["ok"], "primeiro movimento")
	var before: Dictionary = state.to_dict()
	var result := _move(game, army_id, "prov_paris")
	assert_true(not result["ok"] and "já se moveu neste turno" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")
	assert_eq(state.armies[army_id]["province"], "prov_strasbourg", "continua em Alsácia")


func test_movement_is_reset_at_the_new_turn() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game)
	_move(game, army_id, "prov_strasbourg")
	var report: Dictionary = TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(report["ok"], str(report["errors"]))
	assert_true(not state.armies[army_id]["moved"], "movimento reiniciado")
	assert_eq(state.armies[army_id]["province"], "prov_strasbourg", "o turno não move exércitos sozinho")
	assert_true(_move(game, army_id, "prov_paris")["ok"], "pode se mover de novo")
	for other in state.armies:
		if other != army_id:
			assert_true(not state.armies[other]["moved"], "exército %s não se moveu" % str(other))


func test_move_order_is_not_executed_twice_across_turns() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game)
	_move(game, army_id, "prov_strasbourg")
	var processor := TurnProcessor.new()
	processor.end_turn(game["registry"], state)
	processor.end_turn(game["registry"], state)
	assert_eq(state.armies[army_id]["province"], "prov_strasbourg", "a ordem não se repete")


# --- Encontros ------------------------------------------------------------------------

func test_moving_into_a_province_with_foreign_army_registers_an_encounter() -> void:
	var game := new_game()
	var state = game["state"]
	var mine := _fra_army(game)
	var intruder := _foreign_army_in(game, "aus", "prov_strasbourg")
	var result := _move(game, mine, "prov_strasbourg")
	assert_true(result["ok"], "o destino é próprio: o movimento é feito")
	assert_true("Encontro pendente" in result["message"], "a mensagem não trata como pacífico: " + result["message"])
	assert_eq(state.encounters.size(), 1, "um encontro registrado")
	var encounter: Dictionary = state.encounters[0]
	assert_eq(encounter["province"], "prov_strasbourg", "província do encontro")
	assert_eq(encounter["armies"], [mine, intruder] as Array, "exércitos envolvidos")
	assert_eq(encounter["countries"], ["aus", "fra"] as Array, "países envolvidos")
	assert_eq(encounter["initiator"], mine, "quem entrou")
	assert_eq(encounter["turn"], 1, "turno do encontro")
	assert_eq(result["encounter"]["id"], encounter["id"], "devolvido ao chamador")
	assert_true(ArmyActions.is_engaged(state, mine) and ArmyActions.is_engaged(state, intruder), "ambos parados")


func test_engaged_armies_cannot_move_or_be_reorganized() -> void:
	var game := new_game()
	var state = game["state"]
	var mine := _fra_army(game)
	_foreign_army_in(game, "aus", "prov_strasbourg")
	_move(game, mine, "prov_strasbourg")
	TurnProcessor.new().end_turn(game["registry"], state)  # novo turno: movimento liberado
	assert_eq(state.encounters.size(), 1, "o encontro continua pendente")
	var move := _move(game, mine, "prov_paris")
	assert_true(not move["ok"] and "encontro pendente" in move["message"], move["message"])
	var unit_id: int = state.armies[mine]["units"][0]
	var detach := ArmyActions.detach_unit(game["registry"], state, "fra", mine, unit_id)
	assert_true(not detach["ok"] and "encontro pendente" in detach["message"], detach["message"])


func test_encounter_is_dropped_when_no_longer_applicable() -> void:
	var game := new_game()
	var state = game["state"]
	var mine := _fra_army(game)
	var intruder := _foreign_army_in(game, "aus", "prov_strasbourg")
	_move(game, mine, "prov_strasbourg")
	state.armies.erase(intruder)  # simula a saída/resolução futura do exército estrangeiro
	TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(state.encounters.is_empty(), "encontro encerrado")
	assert_true(_move(game, mine, "prov_paris")["ok"], "o exército volta a se mover")


func test_no_encounter_with_own_or_no_armies() -> void:
	var game := new_game()
	var state = game["state"]
	var mine := _fra_army(game)
	_fra_army(game, "prov_strasbourg")  # outro exército próprio no destino
	var result := _move(game, mine, "prov_strasbourg")
	assert_true(result["ok"] and result["encounter"].is_empty(), "exércitos do mesmo país não geram encontro")
	assert_true(state.encounters.is_empty(), "nenhum encontro")


func test_existing_encounter_is_extended_instead_of_duplicated() -> void:
	var game := new_game()
	var state = game["state"]
	var first := _fra_army(game)
	var second := _fra_army(game)
	_foreign_army_in(game, "aus", "prov_strasbourg")
	_move(game, first, "prov_strasbourg")
	_move(game, second, "prov_strasbourg")
	assert_eq(state.encounters.size(), 1, "um único encontro na província")
	assert_true(first in state.encounters[0]["armies"] and second in state.encounters[0]["armies"], "ambos incluídos")
	assert_eq(state.encounters[0]["armies"].size(), 3, "3 exércitos")


func test_state_validation_still_passes_after_movement_and_encounters() -> void:
	var game := new_game()
	var mine := _fra_army(game)
	_foreign_army_in(game, "aus", "prov_strasbourg")
	_move(game, mine, "prov_strasbourg")
	assert_true(TurnProcessor.new().validate_state(game["registry"], game["state"]).is_empty(), "estado consistente")
