extends "res://tests/test_case.gd"
## Recrutamento: validação, custo, progresso, unidades no estado e manutenção.

const CampaignActions := preload("res://src/campaign/campaign_actions.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")

const INFANTRY := "unit_line_inf"


func _recruit(game: Dictionary, province_id: String, unit_id: String, country_id: String = "fra") -> Dictionary:
	return CampaignActions.start_recruitment(game["registry"], game["state"], country_id, province_id, unit_id)


func _end_turn(game: Dictionary, processor: TurnProcessor) -> Dictionary:
	var report: Dictionary = processor.end_turn(game["registry"], game["state"])
	assert_true(report["ok"], "turno válido: %s" % str(report["errors"]))
	return report


func test_valid_recruitment_deducts_all_costs_and_queues() -> void:
	var game := new_game()
	var result := _recruit(game, "prov_paris", INFANTRY)
	assert_true(result["ok"], result["message"])
	var res: Dictionary = game["state"].resources_of("fra")
	assert_eq(res["gold"], 440, "500 - 60")
	assert_eq(res["materials"], 180, "200 - 20")
	assert_eq(res["manpower"], 500, "1000 - 500")
	assert_eq(game["state"].provinces["prov_paris"]["recruitments"], [{"unit": INFANTRY, "remaining": 2}], "fila")
	assert_true(game["state"].units.is_empty(), "ainda não existe unidade")


func test_recruitment_progresses_and_unit_appears_on_expected_turn() -> void:
	var game := new_game()
	var state = game["state"]
	var processor := TurnProcessor.new()
	assert_true(_recruit(game, "prov_paris", INFANTRY)["ok"], "2 turnos")
	_end_turn(game, processor)
	assert_eq(state.provinces["prov_paris"]["recruitments"][0]["remaining"], 1, "1 turno restante")
	assert_true(state.units.is_empty(), "ainda sem unidade")
	var report := _end_turn(game, processor)
	assert_eq(state.units.size(), 1, "unidade disponível no 2º encerramento")
	var unit: Dictionary = state.units[0]
	assert_eq(unit["type"], INFANTRY, "tipo")
	assert_eq(unit["owner"], "fra", "dono")
	assert_eq(unit["province"], "prov_paris", "província de origem")
	assert_eq(unit["strength"], 500, "efetivo")
	assert_true(state.provinces["prov_paris"]["recruitments"].is_empty(), "fila vazia")
	assert_eq(report["completed_units"].size(), 1, "relatório")
	assert_eq(state.units_in("prov_paris").size(), 1, "consulta por província")


func test_unit_ids_are_unique() -> void:
	var game := new_game()
	var processor := TurnProcessor.new()
	game["state"].countries["fra"]["resources"]["manpower"] = 5000
	assert_true(_recruit(game, "prov_paris", INFANTRY)["ok"], "primeira")
	assert_true(_recruit(game, "prov_paris", INFANTRY)["ok"], "segunda (capacidade 2)")
	_end_turn(game, processor)
	_end_turn(game, processor)
	assert_eq(game["state"].units.size(), 2, "duas unidades")
	assert_true(game["state"].units[0]["id"] != game["state"].units[1]["id"], "ids distintos")


func test_province_without_barracks_is_rejected_without_changes() -> void:
	var game := new_game()
	var before: Dictionary = game["state"].to_dict()
	var result := _recruit(game, "prov_strasbourg", INFANTRY)
	assert_true(not result["ok"] and "Requer: Quartel" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_insufficient_resources_rejected_without_changes() -> void:
	var game := new_game()
	game["state"].countries["fra"]["resources"]["manpower"] = 100
	var before: Dictionary = game["state"].to_dict()
	var result := _recruit(game, "prov_paris", INFANTRY)
	assert_true(not result["ok"] and "400 de População recrutável" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_unit_not_yet_recruitable_is_rejected() -> void:
	var game := new_game()
	var before: Dictionary = game["state"].to_dict()
	var result := _recruit(game, "prov_paris", "unit_light_cav")
	assert_true(not result["ok"] and "ainda não pode ser recrutada" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_foreign_province_is_rejected() -> void:
	var game := new_game()
	var before: Dictionary = game["state"].to_dict()
	var result := _recruit(game, "prov_vienna", INFANTRY)
	assert_true(not result["ok"] and "não controla" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_recruitment_capacity_limit() -> void:
	var game := new_game()
	game["state"].countries["fra"]["resources"]["manpower"] = 5000
	assert_true(_recruit(game, "prov_paris", INFANTRY)["ok"], "1 de 2")
	assert_true(_recruit(game, "prov_paris", INFANTRY)["ok"], "2 de 2")
	var before: Dictionary = game["state"].to_dict()
	var third := _recruit(game, "prov_paris", INFANTRY)
	assert_true(not third["ok"] and "Capacidade de recrutamento esgotada" in third["message"], third["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_unit_upkeep_starts_the_turn_after_completion() -> void:
	var game := new_game()
	var state = game["state"]
	var processor := TurnProcessor.new()
	assert_true(_recruit(game, "prov_paris", INFANTRY)["ok"], "recrutar")
	var gold: int = state.resources_of("fra")["gold"]
	var food: int = state.resources_of("fra")["food"]
	_end_turn(game, processor)
	gold += 22
	food += 14
	assert_eq(state.resources_of("fra")["gold"], gold, "turno 1: sem manutenção")
	_end_turn(game, processor)  # a unidade fica pronta aqui, depois do cálculo econômico
	gold += 22
	food += 14
	assert_eq(state.resources_of("fra")["gold"], gold, "turno da conclusão: sem manutenção ainda")
	_end_turn(game, processor)
	gold += 22 - 4
	food += 14 - 5
	assert_eq(state.resources_of("fra")["gold"], gold, "turno seguinte: manutenção de ouro")
	assert_eq(state.resources_of("fra")["food"], food, "turno seguinte: manutenção de alimentos")
