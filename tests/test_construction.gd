extends "res://tests/test_case.gd"
## Construções: validação, custo, fila, progresso e efeitos.

const CampaignActions := preload("res://src/campaign/campaign_actions.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")


func _build(game: Dictionary, province_id: String, building_id: String, country_id: String = "fra") -> Dictionary:
	return CampaignActions.start_construction(game["registry"], game["state"], country_id, province_id, building_id)


func _end_turn(game: Dictionary, processor: TurnProcessor) -> Dictionary:
	var report: Dictionary = processor.end_turn(game["registry"], game["state"])
	assert_true(report["ok"], "turno válido: %s" % str(report["errors"]))
	return report


func test_valid_construction_deducts_cost_and_queues() -> void:
	var game := new_game()
	var result := _build(game, "prov_strasbourg", "farm")
	assert_true(result["ok"], result["message"])
	assert_eq(game["state"].resources_of("fra")["gold"], 400, "500 - 100")
	assert_eq(game["state"].provinces["prov_strasbourg"]["constructions"], [{"building": "farm", "remaining": 2}], "fila")
	assert_true(not ("farm" in game["state"].provinces["prov_strasbourg"]["buildings"]), "ainda não concluída")


func test_cost_with_several_resources_is_deducted() -> void:
	var game := new_game()
	assert_true(_build(game, "prov_paris", "fortification")["ok"], "Fortificação")
	assert_eq(game["state"].resources_of("fra")["gold"], 250, "500 - 250")
	assert_eq(game["state"].resources_of("fra")["materials"], 160, "200 - 40")


func test_construction_above_budget_is_rejected_without_changes() -> void:
	var game := new_game()
	game["state"].countries["fra"]["resources"]["gold"] = 99
	var before: Dictionary = game["state"].to_dict()
	var result := _build(game, "prov_strasbourg", "farm")
	assert_true(not result["ok"], "rejeitada")
	assert_true("Recursos insuficientes" in result["message"] and "1 de Ouro" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_exact_budget_is_accepted_and_balance_is_zero() -> void:
	var game := new_game()
	game["state"].countries["fra"]["resources"]["gold"] = 100
	assert_true(_build(game, "prov_strasbourg", "farm")["ok"], "custo exato")
	assert_eq(game["state"].resources_of("fra")["gold"], 0, "saldo zero, nunca negativo")


func test_foreign_province_is_rejected() -> void:
	var game := new_game()
	var before: Dictionary = game["state"].to_dict()
	var result := _build(game, "prov_vienna", "farm")
	assert_true(not result["ok"] and "não controla" in result["message"], result["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")


func test_already_built_and_already_queued_are_rejected() -> void:
	var game := new_game()
	assert_true("já possui" in _build(game, "prov_paris", "market")["message"], "já concluída")
	assert_true(_build(game, "prov_strasbourg", "farm")["ok"], "primeira")
	var again := _build(game, "prov_strasbourg", "farm")
	assert_true(not again["ok"] and "já está em construção" in again["message"], again["message"])


func test_construction_queue_limit() -> void:
	var game := new_game()
	assert_true(_build(game, "prov_strasbourg", "farm")["ok"], "primeira")
	var second := _build(game, "prov_strasbourg", "workshop")
	assert_true(not second["ok"] and "Fila de construção cheia" in second["message"], second["message"])
	assert_eq(game["state"].resources_of("fra")["gold"], 400, "segunda não cobrou nada")


func test_requirements_are_enforced() -> void:
	var game := new_game()
	game["registry"].buildings["arsenal"]["buildable"] = true  # cópia de teste: Arsenal exige Oficina
	var result := _build(game, "prov_strasbourg", "arsenal")
	assert_true(not result["ok"] and "Requer: Oficina" in result["message"], result["message"])
	game["state"].provinces["prov_strasbourg"]["buildings"].append("workshop")
	assert_true(_build(game, "prov_strasbourg", "arsenal")["ok"], "com Oficina concluída")


func test_unavailable_building_is_rejected() -> void:
	var game := new_game()
	var result := _build(game, "prov_strasbourg", "arsenal")
	assert_true(not result["ok"] and "não está disponível" in result["message"], result["message"])


func test_construction_progresses_and_completes_on_expected_turn() -> void:
	var game := new_game()
	var state = game["state"]
	var processor := TurnProcessor.new()
	assert_true(_build(game, "prov_strasbourg", "farm")["ok"], "Fazenda: 2 turnos")
	_end_turn(game, processor)
	assert_eq(state.provinces["prov_strasbourg"]["constructions"][0]["remaining"], 1, "1 turno restante")
	assert_true(not ("farm" in state.provinces["prov_strasbourg"]["buildings"]), "ainda em obras")
	var report := _end_turn(game, processor)
	assert_true("farm" in state.provinces["prov_strasbourg"]["buildings"], "concluída no 2º encerramento")
	assert_true(state.provinces["prov_strasbourg"]["constructions"].is_empty(), "fila vazia")
	assert_eq(report["completed_buildings"], [{"province": "prov_strasbourg", "building": "farm"}], "relatório")
	assert_eq(state.turn, 3, "turno 3")


func test_completed_building_yields_from_next_turn_only() -> void:
	var game := new_game()
	var state = game["state"]
	var processor := TurnProcessor.new()
	assert_true(_build(game, "prov_strasbourg", "farm")["ok"], "Fazenda")
	var food: int = state.resources_of("fra")["food"]
	_end_turn(game, processor)
	food += 14
	assert_eq(state.resources_of("fra")["food"], food, "turno 1: receita base")
	_end_turn(game, processor)  # a Fazenda conclui aqui, depois da receita
	food += 14
	assert_eq(state.resources_of("fra")["food"], food, "turno da conclusão: sem receita retroativa")
	_end_turn(game, processor)
	food += 18
	assert_eq(state.resources_of("fra")["food"], food, "turno seguinte: +4 da Fazenda")


func test_new_queue_slot_is_free_after_completion() -> void:
	var game := new_game()
	var processor := TurnProcessor.new()
	assert_true(_build(game, "prov_strasbourg", "farm")["ok"], "Fazenda")
	_end_turn(game, processor)
	_end_turn(game, processor)
	assert_true(_build(game, "prov_strasbourg", "workshop")["ok"], "fila liberada")
