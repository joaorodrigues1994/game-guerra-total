extends "res://tests/test_case.gd"
## Modelo de exércitos, unidades-instância, incorporação, organização e generais.

const ArmyActions := preload("res://src/units/army_actions.gd")
const CampaignActions := preload("res://src/campaign/campaign_actions.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")

const INFANTRY := "unit_line_inf"


## Exército do jogador (França) com `count` unidades, criado direto no estado.
func _fra_army(game: Dictionary, province_id: String = "prov_paris", count: int = 1) -> int:
	var state = game["state"]
	var army_id: int = state.create_army("Exército de teste", "fra", province_id)
	for i in count:
		state.armies[army_id]["units"].append(state.add_unit(game["registry"], INFANTRY, "fra", province_id))
	return army_id


func _raw() -> Dictionary:
	var reg := Registry.new()
	assert_true(reg.load_from_dir("res://data"), str(reg.errors))
	return reg.raw_data.duplicate(true)


func _errors_for(raw: Dictionary) -> PackedStringArray:
	var reg := Registry.new()
	assert_true(not reg.load_from_data(raw), "dados inválidos devem falhar")
	return reg.errors


# --- Estado inicial -------------------------------------------------------------

func test_starting_armies_are_created_from_data() -> void:
	var game := new_game()
	var state = game["state"]
	assert_eq(state.armies.size(), 3, "3 exércitos iniciais")
	assert_eq(state.armies_in("prov_bohemia").size(), 1, "exército na Boêmia")
	var army: Dictionary = state.armies[state.armies_in("prov_bohemia")[0]]
	assert_eq(army["name"], "Exército da Boêmia", "nome")
	assert_eq(army["owner"], "aus", "dono")
	assert_eq(army["units"].size(), 2, "2 unidades")
	assert_eq(army["general"], "gen_charles", "general")
	assert_eq(state.army_strength(army["id"]), 1000, "efetivo = soma das unidades")
	assert_true(state.armies_in("prov_paris").is_empty(), "França começa sem exércitos")
	assert_true(state.encounters.is_empty(), "sem encontros")


func test_unit_instances_have_own_ids_and_reference_definitions() -> void:
	var game := new_game()
	var state = game["state"]
	var ids := {}
	for unit in state.units:
		assert_true(not ids.has(unit["id"]), "id único da instância %d" % unit["id"])
		ids[unit["id"]] = true
		assert_true(game["registry"].units.has(unit["type"]), "referencia a definição")
		assert_true(unit["id"] is int and unit["type"] is String, "id de instância é inteiro; tipo é o id da definição")
		assert_eq(unit["strength"], 500, "efetivo inicial vem da definição")
		assert_true(unit.has("morale") and unit.has("experience"), "dados mutáveis da instância")
		assert_true(not unit.has("name") and not unit.has("attack"), "dados estáticos não são copiados")
	assert_eq(state.units.size(), 5, "5 unidades iniciais (3 aus + 2 bav)")


func test_starting_units_belong_to_exactly_one_army() -> void:
	var state = new_game()["state"]
	for unit in state.units:
		assert_true(state.army_of_unit(unit["id"]) != 0, "unidade %d está em um exército" % unit["id"])
	assert_eq(state.army_of_unit(9999), 0, "unidade inexistente: nenhum exército")


# --- Criação e consulta ---------------------------------------------------------

func test_create_army_has_valid_location_and_defaults() -> void:
	var game := new_game()
	var state = game["state"]
	var a: int = state.create_army("Primeiro", "fra", "prov_paris")
	var b: int = state.create_army("Segundo", "fra", "prov_paris")
	assert_true(a != b, "ids de exército únicos")
	var army: Dictionary = state.armies[a]
	assert_eq(army["province"], "prov_paris", "localização")
	assert_true(game["registry"].provinces.has(army["province"]), "localização é uma província existente")
	assert_eq(army["owner"], "fra", "dono")
	assert_eq(army["units"], [], "sem unidades")
	assert_eq(army["general"], "", "sem general")
	assert_true(not army["moved"], "movimento disponível")


func test_armies_can_be_queried_by_province_and_owner() -> void:
	var game := new_game()
	var state = game["state"]
	var first := _fra_army(game)
	var second := _fra_army(game)
	_fra_army(game, "prov_strasbourg")
	assert_eq(state.armies_in("prov_paris"), [first, second] as Array[int], "na província, ordenados")
	assert_eq(state.armies_in("prov_paris", "aus"), [] as Array[int], "filtro por país")
	assert_eq(state.armies_in("prov_vienna", "aus").size(), 1, "exército austríaco em Viena")


func test_army_strength_is_computed_from_units() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 2)
	assert_eq(state.army_strength(army_id), 1000, "2 x 500")
	state.unit_by_id(state.armies[army_id]["units"][0])["strength"] = 320  # baixas
	assert_eq(state.army_strength(army_id), 820, "usa o efetivo ATUAL da instância")


# --- Incorporação de recrutas ---------------------------------------------------

func _recruit_and_finish(game: Dictionary, province_id: String = "prov_paris") -> void:
	assert_true(CampaignActions.start_recruitment(game["registry"], game["state"], "fra", province_id, INFANTRY)["ok"], "recrutar")
	var processor := TurnProcessor.new()
	processor.end_turn(game["registry"], game["state"])
	processor.end_turn(game["registry"], game["state"])


func test_completed_recruit_forms_a_new_army_when_none_exists() -> void:
	var game := new_game()
	var state = game["state"]
	_recruit_and_finish(game)
	var ids: Array[int] = state.armies_in("prov_paris", "fra")
	assert_eq(ids.size(), 1, "um exército novo")
	var army: Dictionary = state.armies[ids[0]]
	assert_eq(army["name"], "Exército de Île-de-France", "nome")
	assert_eq(army["units"].size(), 1, "com a unidade recrutada")
	var unit: Dictionary = state.unit_by_id(army["units"][0])
	assert_eq(unit["strength"], 500, "efetivo preservado na incorporação")
	assert_eq(unit["owner"], "fra", "dono da unidade")
	assert_eq(state.army_strength(army["id"]), 500, "efetivo do exército")


func test_completed_recruit_joins_existing_army_with_room() -> void:
	var game := new_game()
	var state = game["state"]
	game["state"].countries["fra"]["resources"]["manpower"] = 5000
	_recruit_and_finish(game)
	_recruit_and_finish(game)
	var ids: Array[int] = state.armies_in("prov_paris", "fra")
	assert_eq(ids.size(), 1, "a 2ª unidade entrou no mesmo exército")
	assert_eq(state.armies[ids[0]]["units"].size(), 2, "2 unidades")
	assert_eq(state.army_strength(ids[0]), 1000, "efetivo somado")


func test_two_recruits_completing_together_join_the_same_army() -> void:
	var game := new_game()
	var state = game["state"]
	state.countries["fra"]["resources"]["manpower"] = 5000
	CampaignActions.start_recruitment(game["registry"], state, "fra", "prov_paris", INFANTRY)
	CampaignActions.start_recruitment(game["registry"], state, "fra", "prov_paris", INFANTRY)
	var processor := TurnProcessor.new()
	processor.end_turn(game["registry"], state)
	var report: Dictionary = processor.end_turn(game["registry"], state)
	assert_eq(report["completed_units"].size(), 2, "duas unidades concluídas")
	assert_eq(report["completed_units"][0]["army"], report["completed_units"][1]["army"], "mesmo exército")
	assert_eq(units_of(state, "fra").size(), 2, "nenhuma unidade perdida")


func test_recruit_goes_to_new_army_when_existing_one_is_full() -> void:
	var game := new_game()
	var state = game["state"]
	var full := _fra_army(game, "prov_paris", ArmyActions.max_units(game["registry"]))
	_recruit_and_finish(game)
	var ids: Array[int] = state.armies_in("prov_paris", "fra")
	assert_eq(ids.size(), 2, "exército cheio: forma-se outro")
	assert_eq(state.armies[full]["units"].size(), 4, "o cheio continua com 4")
	assert_eq(state.armies[ids[1]]["name"], "Exército de Île-de-France", "novo exército nomeado")
	assert_eq(units_of(state, "fra").size(), 5, "nenhuma unidade perdida")


func test_recruit_does_not_join_foreign_or_other_province_armies() -> void:
	var game := new_game()
	var state = game["state"]
	_fra_army(game, "prov_strasbourg")  # outra província
	state.create_army("Visitante", "aus", "prov_paris")  # de outro país
	_recruit_and_finish(game)
	assert_eq(state.armies_in("prov_paris", "fra").size(), 1, "novo exército próprio em Paris")
	assert_eq(state.armies[state.armies_in("prov_strasbourg")[0]]["units"].size(), 1, "exército de Alsácia intacto")


func test_army_unit_limit_is_enforced_when_adding() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 4)
	var extra: int = state.add_unit(game["registry"], INFANTRY, "fra", "prov_paris")
	var before: Dictionary = state.to_dict()
	var result := ArmyActions.add_unit_to_army(game["registry"], state, "fra", army_id, extra)
	assert_true(not result["ok"] and "Limite de unidades" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")
	# Liberada uma vaga, a mesma unidade entra e mantém o efetivo.
	var first_unit: int = state.armies[army_id]["units"][0]
	assert_true(ArmyActions.detach_unit(game["registry"], state, "fra", army_id, first_unit)["ok"], "liberar vaga")
	assert_true(ArmyActions.add_unit_to_army(game["registry"], state, "fra", army_id, extra)["ok"], "com vaga")
	assert_eq(state.unit_by_id(extra)["strength"], 500, "efetivo preservado")
	assert_eq(state.armies[army_id]["units"].size(), 4, "de volta a 4 unidades")


# --- Organização: propriedade e localização ----------------------------------------

func test_add_unit_validates_ownership_and_location() -> void:
	var game := new_game()
	var state = game["state"]
	var registry = game["registry"]
	var army_id := _fra_army(game, "prov_paris", 1)
	var elsewhere: int = state.add_unit(registry, INFANTRY, "fra", "prov_strasbourg")
	var foreign_unit: int = state.add_unit(registry, INFANTRY, "aus", "prov_paris")
	var foreign_army: int = state.armies_in("prov_vienna")[0]
	var in_other_army: int = state.armies[_fra_army(game, "prov_paris", 1)]["units"][0]
	var before: Dictionary = state.to_dict()

	var cases := [
		[army_id, elsewhere, "outra província"],
		[army_id, foreign_unit, "outro país"],
		[foreign_army, elsewhere, "outro país"],
		[army_id, in_other_army, "já pertence"],
		[army_id, 99999, "inexistente"],
		[99999, elsewhere, "inexistente"],
	]
	for c in cases:
		var result := ArmyActions.add_unit_to_army(registry, state, "fra", c[0], c[1])
		assert_true(not result["ok"] and c[2] in result["message"], "%s -> %s" % [str(c), result["message"]])
	assert_eq(state.to_dict(), before, "nenhuma rejeição alterou o estado")


func test_add_garrison_unit_in_same_province_works() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 1)
	var garrison_unit: int = state.add_unit(game["registry"], INFANTRY, "fra", "prov_paris")
	var result := ArmyActions.add_unit_to_army(game["registry"], state, "fra", army_id, garrison_unit)
	assert_true(result["ok"], result["message"])
	assert_eq(state.army_of_unit(garrison_unit), army_id, "agora está no exército")
	assert_eq(state.armies[army_id]["units"].size(), 2, "2 unidades")


func test_detach_returns_unit_to_garrison_without_losing_it() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 2)
	var unit_id: int = state.armies[army_id]["units"][0]
	var total_before: int = state.units.size()
	var result := ArmyActions.detach_unit(game["registry"], state, "fra", army_id, unit_id)
	assert_true(result["ok"] and not result["disbanded"], result["message"])
	assert_eq(state.units.size(), total_before, "a unidade não desapareceu")
	assert_eq(state.army_of_unit(unit_id), 0, "fora do exército")
	assert_eq(state.garrison_units("prov_paris", "fra").size(), 1, "na guarnição de Paris")
	assert_eq(state.units_in("prov_paris").size(), 2, "ainda presente na província")


func test_detach_unit_uses_the_armys_current_province() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 2)
	ArmyActions.move_army(game["registry"], state, "fra", army_id, "prov_strasbourg")
	var unit_id: int = state.armies[army_id]["units"][0]
	assert_true(ArmyActions.detach_unit(game["registry"], state, "fra", army_id, unit_id)["ok"], "separar")
	assert_eq(state.unit_by_id(unit_id)["province"], "prov_strasbourg", "guarnição onde o exército estava")
	assert_eq(state.garrison_units("prov_strasbourg", "fra").size(), 1, "guarnição de Alsácia")


func test_detaching_last_unit_disbands_army_and_frees_general() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 1)
	assert_true(ArmyActions.assign_general(game["registry"], state, "fra", army_id, "gen_davout")["ok"], "general")
	var unit_id: int = state.armies[army_id]["units"][0]
	var result := ArmyActions.detach_unit(game["registry"], state, "fra", army_id, unit_id)
	assert_true(result["ok"] and result["disbanded"], result["message"])
	assert_true(not state.armies.has(army_id), "exército desfeito")
	assert_eq(state.army_of_general("gen_davout"), 0, "general livre")
	assert_eq(state.unit_by_id(unit_id)["strength"], 500, "unidade preservada")
	assert_eq(state.garrison_units("prov_paris", "fra").size(), 1, "unidade na guarnição")


func test_detach_validates_ownership_and_membership() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game, "prov_paris", 1)
	var other_unit: int = state.add_unit(game["registry"], INFANTRY, "fra", "prov_paris")
	var foreign_army: int = state.armies_in("prov_vienna")[0]
	var foreign_unit: int = state.armies[foreign_army]["units"][0]
	var before: Dictionary = state.to_dict()
	var not_member := ArmyActions.detach_unit(game["registry"], state, "fra", army_id, other_unit)
	assert_true(not not_member["ok"] and "não pertence" in not_member["message"], not_member["message"])
	var foreign := ArmyActions.detach_unit(game["registry"], state, "fra", foreign_army, foreign_unit)
	assert_true(not foreign["ok"] and "outro país" in foreign["message"], foreign["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_form_army_from_garrison_unit() -> void:
	var game := new_game()
	var state = game["state"]
	var unit_id: int = state.add_unit(game["registry"], INFANTRY, "fra", "prov_paris")
	var result := ArmyActions.form_army(game["registry"], state, "fra", "prov_paris", unit_id)
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[result["army_id"]]["units"], [unit_id], "exército com a unidade")
	assert_eq(state.armies[result["army_id"]]["province"], "prov_paris", "província")
	var again := ArmyActions.form_army(game["registry"], state, "fra", "prov_paris", unit_id)
	assert_true(not again["ok"] and "já pertence" in again["message"], again["message"])
	var wrong_province := ArmyActions.form_army(game["registry"], state, "fra", "prov_strasbourg", state.add_unit(game["registry"], INFANTRY, "fra", "prov_paris"))
	assert_true(not wrong_province["ok"] and "outra província" in wrong_province["message"], wrong_province["message"])


# --- Generais ------------------------------------------------------------------------

func test_assign_and_unassign_general() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game)
	var result := ArmyActions.assign_general(game["registry"], state, "fra", army_id, "gen_davout")
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[army_id]["general"], "gen_davout", "general atribuído")
	assert_eq(state.army_of_general("gen_davout"), army_id, "consulta inversa")
	assert_true(ArmyActions.unassign_general(game["registry"], state, "fra", army_id)["ok"], "remover")
	assert_eq(state.armies[army_id]["general"], "", "sem general")
	assert_true(not ArmyActions.unassign_general(game["registry"], state, "fra", army_id)["ok"], "remover de novo falha")


func test_general_cannot_command_two_armies() -> void:
	var game := new_game()
	var state = game["state"]
	var first := _fra_army(game)
	var second := _fra_army(game)
	ArmyActions.assign_general(game["registry"], state, "fra", first, "gen_davout")
	var before: Dictionary = state.to_dict()
	var result := ArmyActions.assign_general(game["registry"], state, "fra", second, "gen_davout")
	assert_true(not result["ok"] and "já comanda" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_army_cannot_have_two_generals() -> void:
	var game := new_game()
	var army_id := _fra_army(game)
	ArmyActions.assign_general(game["registry"], game["state"], "fra", army_id, "gen_davout")
	var result := ArmyActions.assign_general(game["registry"], game["state"], "fra", army_id, "gen_ney")
	assert_true(not result["ok"] and "já tem um general" in result["message"], result["message"])


func test_general_of_another_country_is_rejected() -> void:
	var game := new_game()
	var state = game["state"]
	var army_id := _fra_army(game)
	var before: Dictionary = state.to_dict()
	var result := ArmyActions.assign_general(game["registry"], state, "fra", army_id, "gen_mack")
	assert_true(not result["ok"] and "outro país" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")


func test_cannot_assign_general_to_foreign_army() -> void:
	var game := new_game()
	var state = game["state"]
	var foreign_army: int = state.armies_in("prov_vienna")[0]  # sem general
	var result := ArmyActions.assign_general(game["registry"], state, "fra", foreign_army, "gen_davout")
	assert_true(not result["ok"] and "outro país" in result["message"], result["message"])
	assert_eq(state.armies[foreign_army]["general"], "", "inalterado")


func test_unknown_general_is_rejected() -> void:
	var game := new_game()
	var result := ArmyActions.assign_general(game["registry"], game["state"], "fra", _fra_army(game), "gen_fantasma")
	assert_true(not result["ok"] and "inexistente" in result["message"], result["message"])


# --- Validação dos dados iniciais ----------------------------------------------------

func test_registry_rejects_invalid_starting_armies() -> void:
	var raw := _raw()
	raw["armies"][0]["owner"] = "xxx"
	assert_has_error(_errors_for(raw), "dono inexistente")

	raw = _raw()
	raw["armies"][0]["province"] = "prov_paris"  # província da França para um exército austríaco
	assert_has_error(_errors_for(raw), "província do próprio país")

	raw = _raw()
	raw["armies"][0]["units"] = [INFANTRY, INFANTRY, INFANTRY, INFANTRY, INFANTRY]
	assert_has_error(_errors_for(raw), "excede o limite")

	raw = _raw()
	raw["armies"][0]["units"] = ["unit_inexistente"]
	assert_has_error(_errors_for(raw), "unidade desconhecida")

	raw = _raw()
	raw["armies"][0]["general"] = "gen_davout"  # francês num exército austríaco
	assert_has_error(_errors_for(raw), "outra nacionalidade")

	raw = _raw()
	raw["armies"][1]["general"] = "gen_charles"  # já comanda o exército 0
	assert_has_error(_errors_for(raw), "já comanda outro exército")

	raw = _raw()
	raw["generals"][0]["nationality"] = "xxx"
	assert_has_error(_errors_for(raw), "nacionalidade inexistente")

	raw = _raw()
	raw["rules"]["max_army_units"] = 0.0
	assert_has_error(_errors_for(raw), "max_army_units")


# --- Integração com o processador de turnos -------------------------------------------

func test_turn_validation_rejects_inconsistent_armies() -> void:
	var game := new_game()
	var state = game["state"]
	var first := _fra_army(game)
	var second := _fra_army(game)
	state.armies[second]["units"].append(state.armies[first]["units"][0])  # unidade em dois exércitos
	var before: Dictionary = state.to_dict()
	var report: Dictionary = TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not report["ok"], "turno recusado")
	assert_true("mais de um exército" in " ".join(PackedStringArray(report["errors"])), str(report["errors"]))
	assert_eq(state.to_dict(), before, "estado intacto")

	var game2 := new_game()
	var a := _fra_army(game2)
	var b := _fra_army(game2)
	game2["state"].armies[a]["general"] = "gen_davout"
	game2["state"].armies[b]["general"] = "gen_davout"
	var report2: Dictionary = TurnProcessor.new().end_turn(game2["registry"], game2["state"])
	assert_true(not report2["ok"] and "comanda mais de um exército" in " ".join(PackedStringArray(report2["errors"])), str(report2["errors"]))
