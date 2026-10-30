extends "res://tests/integration_case.gd"
## Mesclar exércitos na mesma província e recuo do defensor de um encontro (sem batalha).
## Os encontros nascem do código real de movimento (ArmyActions.move_army).

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const EncounterRetreat := preload("res://src/integration/encounter_retreat.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const INFANTRY := "unit_line_inf"
const SWABIA := "prov_swabia"


func _controller(game: Dictionary) -> CampaignController:
	var province_map := ProvinceMap.new()
	province_map.build(game["registry"])
	var controller := CampaignController.new()
	controller.setup(game["registry"], game["state"], province_map)
	return controller


func _first_general(game: Dictionary, index: int = 0) -> String:
	var ids: Array = []
	for general_id in game["state"].generals:
		if game["state"].generals[general_id]["owner"] == "fra":
			ids.append(general_id)
	ids.sort()
	return ids[index]


# --- Mesclar ----------------------------------------------------------------------------------------------------

func test_merging_moves_every_unit_into_the_target_and_removes_the_other_army() -> void:
	var game := new_game()
	var state = game["state"]
	var first := army_in(game, "fra", [INFANTRY, INFANTRY], OTHER_PROVINCE)
	var second := army_in(game, "fra", [INFANTRY, INFANTRY], OTHER_PROVINCE)
	var units: Array = state.armies[first]["units"] + state.armies[second]["units"]
	var result := ArmyActions.merge_armies(game["registry"], state, "fra", first, second)
	assert_true(result["ok"], result["message"])
	assert_true(not state.armies.has(second), "o exército absorvido deixa de existir")
	assert_eq(state.armies[first]["units"].size(), 4, "quatro unidades")
	for unit_id in units:
		assert_eq(state.army_of_unit(unit_id), first, "unidade %d no exército resultante" % unit_id)
		assert_true(not state.unit_by_id(unit_id).is_empty(), "a unidade continua existindo")


func test_merge_is_refused_above_the_unit_limit_without_changes() -> void:
	var game := new_game()
	var state = game["state"]
	var first := army_in(game, "fra", [INFANTRY, INFANTRY, INFANTRY], OTHER_PROVINCE)
	var second := army_in(game, "fra", [INFANTRY, INFANTRY], OTHER_PROVINCE)
	var result := ArmyActions.merge_armies(game["registry"], state, "fra", first, second)
	assert_true(not result["ok"] and "limite" in result["message"], result["message"])
	assert_eq(state.armies[first]["units"].size(), 3, "alvo intacto")
	assert_eq(state.armies[second]["units"].size(), 2, "origem intacta")


func test_merge_refusals() -> void:
	var game := new_game()
	var state = game["state"]
	var registry = game["registry"]
	var first := army_in(game, "fra", [INFANTRY], OTHER_PROVINCE)
	var same_place := army_in(game, "fra", [INFANTRY], OTHER_PROVINCE)
	var elsewhere := army_in(game, "fra", [INFANTRY], PROVINCE)
	var foreign := army_in(game, "aus", [INFANTRY], OTHER_PROVINCE)
	assert_true(not ArmyActions.merge_armies(registry, state, "fra", first, first)["ok"], "consigo mesmo")
	assert_true(not ArmyActions.merge_armies(registry, state, "fra", first, elsewhere)["ok"], "outra província")
	assert_true(not ArmyActions.merge_armies(registry, state, "fra", first, foreign)["ok"], "exército de outro país")
	assert_true(not ArmyActions.merge_armies(registry, state, "fra", first, 9999)["ok"], "inexistente")
	state.encounters.append({"id": 77, "province": OTHER_PROVINCE, "turn": 1, "initiator": same_place, "armies": [same_place, first], "countries": ["fra", "aus"]})
	assert_true("encontro" in ArmyActions.check_merge(registry, state, "fra", first, same_place), "encontro pendente")
	state.encounters.clear()
	state.battles[1] = {"id": 1, "status": "active", "armies": [first], "province": OTHER_PROVINCE, "encounter_id": 0}
	assert_true("batalha" in ArmyActions.check_merge(registry, state, "fra", first, same_place), "batalha ativa")
	state.battles.clear()
	assert_eq(ArmyActions.check_merge(registry, state, "fra", first, same_place), "", "livres: pode")


func test_merge_general_rules() -> void:
	var game := new_game()
	var state = game["state"]
	var registry = game["registry"]
	var general_a := _first_general(game, 0)
	var general_b := _first_general(game, 1)
	var first := army_in(game, "fra", [INFANTRY], OTHER_PROVINCE)
	var second := army_in(game, "fra", [INFANTRY], OTHER_PROVINCE)
	state.armies[second]["general"] = general_a
	assert_true(ArmyActions.merge_armies(registry, state, "fra", first, second)["ok"], "mescla")
	assert_eq(state.armies[first]["general"], general_a, "sem general, o alvo herda o do absorvido")
	var third := army_in(game, "fra", [INFANTRY], OTHER_PROVINCE)
	state.armies[third]["general"] = general_b
	var result := ArmyActions.merge_armies(registry, state, "fra", first, third)
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[first]["general"], general_a, "o alvo mantém o seu general")
	assert_eq(state.army_of_general(general_b), 0, "o outro general fica livre")


func test_merge_through_the_interface() -> void:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var state = main.state
	var first := army_in({"state": state, "registry": main.registry}, "fra", [INFANTRY], OTHER_PROVINCE)
	var second := army_in({"state": state, "registry": main.registry}, "fra", [INFANTRY], OTHER_PROVINCE)
	main.controller.select_army(first)
	var panel = main.screen.army_panel
	assert_true(panel.merge_buttons.has(second), "botão de mesclar com o outro exército")
	assert_true(not panel.merge_buttons[second].disabled, "habilitado")
	panel.merge_buttons[second].pressed.emit()
	assert_true(not state.armies.has(second), "mesclado")
	assert_eq(state.armies[first]["units"].size(), 2, "duas unidades")
	assert_eq(main.controller.selected_army_id, first, "o exército resultante segue selecionado")
	assert_true(panel.merge_buttons.is_empty(), "sem outro exército, sem botões")
	main.queue_free()


# --- Recuo do defensor --------------------------------------------------------------------------------------------

## Exército da Áustria vem da Suábia e invade Alsácia, onde o exército da França (defensor) já está.
func _france_defended_encounter(game: Dictionary) -> Dictionary:
	declare_war_between(game, "fra", "aus")
	var defender := army_in(game, "fra", [INFANTRY, INFANTRY], PROVINCE)
	var invader := army_in(game, "aus", [INFANTRY, INFANTRY], SWABIA)
	var moved := ArmyActions.move_army(game["registry"], game["state"], "aus", invader, PROVINCE)
	assert_true(moved["ok"], moved["message"])
	assert_eq(game["state"].encounters.size(), 1, "encontro registrado")
	return {"defender": defender, "invader": invader, "encounter_id": game["state"].encounters[0]["id"]}


func test_defender_withdraws_to_an_allied_province_without_a_battle() -> void:
	var game := new_game()
	var state = game["state"]
	var s := _france_defended_encounter(game)
	assert_eq(EncounterRetreat.check(game["registry"], state, "fra", s["encounter_id"]), "", "o defensor pode recuar")
	assert_true("Só o defensor" in EncounterRetreat.check(game["registry"], state, "aus", s["encounter_id"]), "o atacante não recua")
	var result := EncounterRetreat.retreat(game["registry"], state, "fra", s["encounter_id"])
	assert_true(result["ok"], result["message"])
	assert_eq(state.owner_of(state.armies[s["defender"]]["province"]), "fra", "foi para província própria")
	assert_true(state.armies[s["defender"]]["province"] != PROVINCE, "saiu da província")
	assert_eq(state.armies[s["invader"]]["province"], PROVINCE, "o atacante permanece")
	assert_true(state.encounters.is_empty(), "o encontro termina")
	assert_true(state.battles.is_empty(), "nenhuma batalha foi criada")
	assert_eq(state.armies[s["defender"]]["units"].size(), 2, "o exército sai inteiro")


func test_defender_cannot_withdraw_without_an_allied_province_and_must_fight() -> void:
	var game := new_game()
	var state = game["state"]
	var s := _france_defended_encounter(game)
	for province_id in state.provinces:
		if state.owner_of(province_id) == "fra" and province_id != PROVINCE:
			army_in(game, "aus", [INFANTRY], province_id)  # bloqueia todas as rotas
	var reason := EncounterRetreat.check(game["registry"], state, "fra", s["encounter_id"])
	assert_true("deve lutar" in reason, reason)
	var result := EncounterRetreat.retreat(game["registry"], state, "fra", s["encounter_id"])
	assert_true(not result["ok"], "recusado")
	assert_eq(state.armies[s["defender"]]["province"], PROVINCE, "nada mudou")
	assert_eq(state.encounters.size(), 1, "o encontro continua")


func test_attacker_and_active_battle_cannot_use_the_withdrawal() -> void:
	var game := new_game()
	var state = game["state"]
	var s := _france_defended_encounter(game)
	assert_true(not EncounterRetreat.retreat(game["registry"], state, "aus", s["encounter_id"])["ok"], "atacante")
	assert_true(not EncounterRetreat.retreat(game["registry"], state, "fra", 999)["ok"], "encontro inexistente")
	state.battles[1] = {"id": 1, "status": "active", "armies": [s["defender"], s["invader"]], "province": PROVINCE, "encounter_id": s["encounter_id"]}
	assert_true("batalha ativa" in EncounterRetreat.check(game["registry"], state, "fra", s["encounter_id"]), "com batalha ativa")


func test_withdrawal_through_the_controller_and_province_panel() -> void:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var game := {"state": main.state, "registry": main.registry}
	var s := _france_defended_encounter(game)
	main.controller.select_province(PROVINCE)
	var panel = main.screen.province_panel
	assert_true(panel.retreat_buttons.has(s["encounter_id"]), "botão de recuar para o defensor")
	assert_true(not panel.retreat_buttons[s["encounter_id"]].disabled, "habilitado")
	panel.retreat_buttons[s["encounter_id"]].pressed.emit()
	assert_true(main.state.encounters.is_empty(), "recuou")
	assert_true(main.state.armies[s["defender"]]["province"] != PROVINCE, "saiu da província")
	main.queue_free()


func test_the_invader_is_not_offered_the_withdrawal() -> void:
	var game := new_game()
	var encounter_id := make_encounter(game)  # a França (jogador) é quem entra
	var controller := _controller(game)
	for entry in controller._encounter_actions(PROVINCE):
		assert_eq(entry["retreat_offered"], false, "o atacante não vê a opção")
	assert_true(encounter_id != 0, "encontro existe")
