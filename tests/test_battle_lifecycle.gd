extends "res://tests/integration_case.gd"
## Registro e ciclo de vida das batalhas na campanha: registrar, bloquear exércitos, cancelar e travar o turno.

const Lifecycle := preload("res://src/integration/battle_lifecycle.gd")
const Request := preload("res://src/integration/battle_request.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")
const CampaignActions := preload("res://src/campaign/campaign_actions.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")


## Encontro + cenário + registro (batalha #1 ativa). Devolve {game, encounter_id, built, registered}.
func _registered() -> Dictionary:
	var game := new_game()
	var encounter_id := make_encounter(game)
	var built := build_scenario(game, encounter_id)
	assert_true(built["ok"], built["message"])
	var registered := Lifecycle.register(game["registry"], game["state"], built)
	assert_true(registered["ok"], registered["message"])
	return {"game": game, "encounter_id": encounter_id, "built": built, "registered": registered}


func _participants(game: Dictionary, encounter_id: int, country_id: String = "fra") -> Array:
	var ids := []
	for army_id in Request.find_encounter(game["state"], encounter_id)["armies"]:
		if game["state"].armies[army_id]["owner"] == country_id:
			ids.append(army_id)
	return ids


# --- Registro -----------------------------------------------------------------------------------

func test_register_creates_an_active_battle_from_a_valid_encounter() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	assert_eq(r["registered"]["battle_id"], 1, "primeiro id sequencial")
	assert_eq(state.next_battle_id, 2, "o próximo id avançou")
	var battle: Dictionary = state.battles[1]
	assert_eq(battle["status"], "active", "ativa")
	assert_eq(battle["id"], 1, "id no registro")
	assert_eq(battle["encounter_id"], r["encounter_id"], "encontro de origem")
	assert_eq(battle["province"], PROVINCE, "província")
	assert_eq(battle["turn"], 1, "turno da campanha no registro")
	assert_eq(battle["countries"], ["fra", "aus"], "países: jogador e adversário")
	assert_eq(battle["armies"], Request.find_encounter(state, r["encounter_id"])["armies"], "exércitos participantes (ordenados)")
	assert_eq(battle["sides"]["player"]["country"], "fra", "lado do jogador")
	assert_eq(battle["sides"]["enemy"]["country"], "aus", "lado do adversário")
	assert_eq(battle["scenario_id"], "campaign_encounter_%d" % r["encounter_id"], "cenário tático associado")
	assert_eq(battle["result"], {}, "sem resultado aplicado")
	assert_eq(battle["history"], [{"status": "active", "turn": 1}], "histórico de estados")
	assert_eq(state.battle_of_encounter(r["encounter_id"]), 1, "consulta por encontro")
	assert_eq(state.active_battles(), [1] as Array[int], "batalhas ativas")
	assert_true("registrada" in r["registered"]["message"], r["registered"]["message"])


func test_the_pending_encounter_is_kept_and_linked_not_consumed() -> void:
	var r := _registered()
	var state = r["game"]["state"]
	assert_eq(state.encounters.size(), 1, "o encontro continua pendente")
	assert_eq(state.encounters[0]["battle_id"], 1, "vinculado à batalha")
	for army_id in state.encounters[0]["armies"]:
		assert_true(ArmyActions.is_engaged(state, army_id), "os exércitos continuam em encontro")


func test_snapshot_preserves_units_and_armies_and_is_independent() -> void:
	var game := new_game()
	var state = game["state"]
	var encounter_id := make_encounter(game)
	var wounded: int = state.armies[_participants(game, encounter_id)[0]]["units"][0]
	state.unit_by_id(wounded)["strength"] = 320
	state.unit_by_id(wounded)["morale"] = 55
	var built := build_scenario(game, encounter_id)
	assert_true(Lifecycle.register(game["registry"], state, built)["ok"], "registrado")
	var battle: Dictionary = state.battles[1]
	assert_eq(battle["units"].size(), 5, "as 5 unidades participantes")
	var snap: Dictionary = battle["units"][wounded]
	assert_eq([snap["strength"], snap["morale"]], [320, 55], "efetivo e moral atuais no instantâneo")
	assert_eq(snap["type"], "unit_line_inf", "tipo de campanha")
	assert_eq(snap["category"], "infantry", "categoria")
	assert_eq(snap["owner"], "fra", "dono")
	assert_eq(snap["army"], state.army_of_unit(wounded), "exército de origem")
	for unit_id in battle["units"]:
		assert_eq(battle["units"][unit_id]["army"], state.army_of_unit(unit_id), "cada unidade aponta para o seu exército")
		assert_true(battle["units"][unit_id]["army"] in battle["armies"], "e o exército é participante")
	# O instantâneo e o cenário guardados são cópias independentes.
	state.unit_by_id(wounded)["strength"] = 1
	assert_eq(battle["units"][wounded]["strength"], 320, "mudar a campanha depois não altera o instantâneo")
	built["scenario"]["units"][0]["strength"] = 1
	assert_true(battle["scenario"]["units"][0]["strength"] != 1, "nem o cenário guardado")
	assert_eq(battle["scenario"]["id"], battle["scenario_id"], "cenário guardado")


# --- Recusas e transações ------------------------------------------------------------------------

func test_invalid_built_results_are_rejected() -> void:
	var game := new_game()
	var encounter_id := make_encounter(game)
	var built := build_scenario(game, encounter_id)
	for bad in [{}, {"ok": false}, {"ok": true}, {"ok": true, "request": {}, "scenario": {}}, {"ok": true, "request": built["request"]}]:
		var result := Lifecycle.register(game["registry"], game["state"], bad)
		assert_true(not result["ok"], "recusado: %s" % str(bad.keys()))
	var unknown: Dictionary = built.duplicate(true)
	unknown["request"]["encounter_id"] = 999
	var missing := Lifecycle.register(game["registry"], game["state"], unknown)
	assert_true(not missing["ok"] and "inexistente" in missing["message"], missing["message"])
	assert_true(game["state"].battles.is_empty(), "nada foi registrado")


func test_an_already_used_encounter_is_rejected_and_nothing_changes() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var before: Dictionary = game["state"].to_dict()
	var again := Lifecycle.register(game["registry"], game["state"], r["built"])
	assert_true(not again["ok"] and "já tem a batalha ativa #1" in again["message"], again["message"])
	assert_eq(game["state"].to_dict(), before, "estado intacto")
	assert_eq(game["state"].battles.size(), 1, "só uma batalha")
	var rebuilt := build_scenario(game, r["encounter_id"])
	assert_true(not rebuilt["ok"] and "já tem a batalha ativa" in rebuilt["message"], "o adaptador também recusa: " + rebuilt["message"])


func test_stale_request_and_mismatching_scenario_are_rejected() -> void:
	var game := new_game()
	var encounter_id := make_encounter(game)
	var built := build_scenario(game, encounter_id)
	var tampered: Dictionary = built.duplicate(true)
	tampered["scenario"]["units"][0]["strength"] = 1
	var mismatch := Lifecycle.register(game["registry"], game["state"], tampered)
	assert_true(not mismatch["ok"] and "diferem do instantâneo" in mismatch["message"], mismatch["message"])
	var swapped: Dictionary = built.duplicate(true)
	swapped["scenario"]["units"].remove_at(0)
	var missing := Lifecycle.register(game["registry"], game["state"], swapped)
	assert_true(not missing["ok"] and "não aparece no cenário" in missing["message"], missing["message"])
	# A campanha muda depois de gerar o cenário: o pedido fica desatualizado.
	var some_unit: int = game["state"].armies[_participants(game, encounter_id)[0]]["units"][0]
	game["state"].unit_by_id(some_unit)["strength"] = 400
	var stale := Lifecycle.register(game["registry"], game["state"], built)
	assert_true(not stale["ok"] and "desatualizado" in stale["message"], stale["message"])
	assert_true(game["state"].battles.is_empty() and game["state"].next_battle_id == 1, "nada registrado, id não consumido")


func test_failed_registrations_leave_no_partial_state() -> void:
	var game := new_game()
	var state = game["state"]
	var encounter_id := make_encounter(game)
	var built := build_scenario(game, encounter_id)
	var before: Dictionary = state.to_dict()
	var bad_cases := [
		{},
		{"ok": false, "request": {}, "scenario": {}},
		built.duplicate(true),
	]
	bad_cases[2]["scenario"]["units"][1]["morale"] = 3
	for bad in bad_cases:
		assert_true(not Lifecycle.register(game["registry"], state, bad)["ok"], "recusado")
		assert_eq(state.to_dict(), before, "nenhum registro parcial, id não consumido, encontro sem vínculo")
	assert_eq(state.next_battle_id, 1, "o id só é consumido junto com o registro")
	assert_true(not state.encounters[0].has("battle_id"), "o encontro não foi vinculado")
	for army_id in state.encounters[0]["armies"]:
		assert_eq(state.battle_of_army(army_id), 0, "nenhum exército ficou bloqueado")
	# Depois de falhas, um registro válido ainda recebe o id 1.
	assert_eq(Lifecycle.register(game["registry"], state, built)["battle_id"], 1, "registro válido normal")


func test_registration_is_not_repeatable_with_the_same_result() -> void:
	var r := _registered()
	var state = r["game"]["state"]
	for i in 3:
		assert_true(not Lifecycle.register(r["game"]["registry"], state, r["built"])["ok"], "tentativa %d recusada" % i)
	assert_eq(state.battles.size(), 1, "idempotente: continua uma única batalha")
	assert_eq(state.next_battle_id, 2, "e um único id consumido")


func test_an_army_cannot_be_in_two_battles_at_once() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	# Um segundo encontro (registro forjado) que lista exércitos já em batalha.
	var second: Dictionary = state.encounters[0].duplicate(true)
	second.erase("battle_id")
	second["id"] = r["encounter_id"] + 1
	state.encounters.append(second)
	var request := Request.build(game["registry"], state, second["id"])
	assert_true(not request["ok"], "o pedido recusa")
	assert_has_error(request["errors"], "já está na batalha ativa #1", "exército bloqueado")
	var built := build_scenario(game, second["id"])
	assert_true(not built["ok"], "o adaptador recusa")
	assert_true(not Lifecycle.register(game["registry"], state, built)["ok"], "e o registro também")
	assert_eq(state.active_battles(), [1] as Array[int], "continua só a batalha 1")


# --- Bloqueio dos exércitos ----------------------------------------------------------------------------

func test_locked_armies_cannot_move_and_reasons_are_clear() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	var army_id: int = _participants(game, r["encounter_id"])[0]
	var before: Dictionary = state.to_dict()
	var result := ArmyActions.move_army(game["registry"], state, "fra", army_id, "prov_paris")
	assert_true(not result["ok"] and "batalha ativa #1" in result["message"] and "bloqueado" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "estado intacto")
	for d in ArmyActions.destinations(game["registry"], state, "fra", army_id):
		assert_true("batalha ativa #1" in d["reason"], "todos os destinos mostram o bloqueio: %s" % d["reason"])
	assert_true("batalha ativa #1" in ArmyActions.battle_lock_reason(state, army_id), "consulta direta")


func test_no_army_can_enter_a_province_with_an_active_battle() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	var bystander := army_in(game, "fra", ["unit_line_inf"], OTHER_PROVINCE)  # outro exército francês, fora da batalha
	var before: Dictionary = state.to_dict()
	var result := ArmyActions.move_army(game["registry"], state, "fra", bystander, PROVINCE)
	assert_true(not result["ok"] and "nenhum exército pode entrar" in result["message"] and "Alsácia" in result["message"], result["message"])
	assert_eq(state.to_dict(), before, "o encontro congelado não foi estendido")
	assert_eq(state.encounters[0]["armies"].size(), 2, "o encontro continua só com os 2 exércitos originais (aus e fra)")


func test_only_participating_armies_are_blocked_not_the_whole_country() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	var bystander := army_in(game, "fra", ["unit_line_inf"], OTHER_PROVINCE)
	var garrison_unit: int = state.add_unit(game["registry"], "unit_line_inf", "fra", OTHER_PROVINCE)
	assert_eq(state.battle_of_army(bystander), 0, "o exército de fora não está bloqueado")
	assert_true(ArmyActions.add_unit_to_army(game["registry"], state, "fra", bystander, garrison_unit)["ok"], "organização livre fora da batalha")
	assert_true(ArmyActions.assign_general(game["registry"], state, "fra", bystander, "gen_davout")["ok"], "general livre")
	var second_unit: int = state.add_unit(game["registry"], "unit_line_inf", "fra", OTHER_PROVINCE)
	assert_true(ArmyActions.form_army(game["registry"], state, "fra", OTHER_PROVINCE, second_unit)["ok"], "formar exército também")
	assert_true(CampaignActions.start_recruitment(game["registry"], state, "fra", OTHER_PROVINCE, "unit_line_inf")["ok"], "recrutar continua possível")


func test_locked_armies_reject_unit_and_general_changes() -> void:
	var game := new_game()
	var state = game["state"]
	var encounter_id := make_encounter(game)
	var army_id: int = _participants(game, encounter_id)[0]
	assert_true(ArmyActions.assign_general(game["registry"], state, "fra", army_id, "gen_davout")["ok"], "general atribuído antes da batalha")
	assert_true(Lifecycle.register(game["registry"], state, build_scenario(game, encounter_id))["ok"], "batalha registrada")
	var garrison_unit: int = state.add_unit(game["registry"], "unit_line_inf", "fra", PROVINCE)
	var member: int = state.armies[army_id]["units"][0]
	var before: Dictionary = state.to_dict()
	var results := {
		"incorporar": ArmyActions.add_unit_to_army(game["registry"], state, "fra", army_id, garrison_unit),
		"separar": ArmyActions.detach_unit(game["registry"], state, "fra", army_id, member),
		"atribuir general": ArmyActions.assign_general(game["registry"], state, "fra", army_id, "gen_ney"),
		"remover general": ArmyActions.unassign_general(game["registry"], state, "fra", army_id),
	}
	for label in results:
		assert_true(not results[label]["ok"] and "batalha ativa #1" in results[label]["message"], "%s: %s" % [label, results[label]["message"]])
	assert_eq(state.to_dict(), before, "nenhuma alteração passou pelo bloqueio")
	for check in [
			ArmyActions.check_add_unit(game["registry"], state, "fra", army_id, garrison_unit),
			ArmyActions.check_detach(game["registry"], state, "fra", army_id, member),
			ArmyActions.check_assign_general(game["registry"], state, "fra", army_id, "gen_ney"),
			ArmyActions.check_unassign_general(state, "fra", army_id)]:
		assert_true("batalha ativa" in check, "as funções de validação também recusam: " + check)


func test_recruits_never_join_a_locked_army() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	var locked: int = _participants(game, r["encounter_id"])[0]
	assert_true(state.armies[locked]["units"].size() < ArmyActions.max_units(game["registry"]), "o exército bloqueado tem vaga")
	var recruit: int = state.add_unit(game["registry"], "unit_line_inf", "fra", PROVINCE)
	var joined := ArmyActions.incorporate_new_unit(game["registry"], state, recruit)
	assert_true(joined != locked, "o recruta forma outro exército em vez de entrar no bloqueado")
	assert_eq(state.armies[locked]["units"].size(), 3, "composição do exército bloqueado inalterada")
	assert_eq(state.battle_of_army(joined), 0, "o novo exército não está em batalha")
	# Defesa em profundidade: mesmo que o exército deixasse de contar como "em encontro", o bloqueio da batalha
	# sozinho impede o recruta de entrar nele.
	state.encounters[0]["armies"] = []
	var second_recruit: int = state.add_unit(game["registry"], "unit_line_inf", "fra", PROVINCE)
	assert_true(not ArmyActions.is_engaged(state, locked), "(situação anômala simulada)")
	var joined_again := ArmyActions.incorporate_new_unit(game["registry"], state, second_recruit)
	assert_true(joined_again != locked, "o bloqueio da batalha, sozinho, impede a entrada")
	assert_eq(state.armies[locked]["units"].size(), 3, "composição ainda inalterada")


func test_encounter_with_active_battle_survives_the_turn_refresh() -> void:
	var r := _registered()
	var state = r["game"]["state"]
	for army_id in state.encounters[0]["armies"]:
		if state.armies[army_id]["owner"] == "aus":
			state.armies.erase(army_id)  # situação anômala: não deve apagar o encontro congelado
	ArmyActions.refresh_encounters(state)
	assert_eq(state.encounters.size(), 1, "encontro com batalha ativa não é descartado")
	assert_true(not TurnProcessor.new().validate_state(r["game"]["registry"], state).is_empty(), "mas a inconsistência é detectada pela validação")


# --- Cancelamento --------------------------------------------------------------------------------------------

func test_cancel_releases_the_armies_and_keeps_history_and_encounter() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	var cancelled := Lifecycle.cancel(state, 1)
	assert_true(cancelled["ok"], cancelled["message"])
	assert_eq(state.battles[1]["status"], "cancelled", "estado cancelado")
	assert_eq(state.battles[1]["history"], [{"status": "active", "turn": 1}, {"status": "cancelled", "turn": 1}], "histórico preservado")
	assert_eq(state.battles.size(), 1, "o registro não é apagado")
	assert_eq(state.active_battles(), [] as Array[int], "sem batalhas ativas")
	for army_id in state.battles[1]["armies"]:
		assert_eq(state.battle_of_army(army_id), 0, "exército %d liberado" % army_id)
		assert_eq(ArmyActions.battle_lock_reason(state, army_id), "", "sem bloqueio")
	assert_eq(state.encounters.size(), 1, "o encontro continua pendente")
	assert_true(not state.encounters[0].has("battle_id"), "sem vínculo")
	var reregistered := Lifecycle.register(game["registry"], state, r["built"])
	assert_true(reregistered["ok"] and reregistered["battle_id"] == 2, "o encontro pode iniciar uma nova batalha (id 2): %s" % reregistered["message"])
	assert_eq(state.battles[1]["status"], "cancelled", "a antiga continua cancelada")


func test_cancel_does_not_change_strategic_data() -> void:
	var game := new_game()
	var state = game["state"]
	var encounter_id := make_encounter(game)
	var strategic_before: Dictionary = state.to_dict()
	var built := build_scenario(game, encounter_id)
	Lifecycle.register(game["registry"], state, built)
	Lifecycle.cancel(state, 1)
	var after: Dictionary = state.to_dict()
	for key in ["battles", "next_battle_id"]:
		strategic_before.erase(key)
		after.erase(key)
	assert_eq(after, strategic_before, "efetivo, moral, exércitos, unidades, províncias, recursos e encontros idênticos ao que eram antes do registro")


func test_duplicate_and_incompatible_transitions_are_rejected() -> void:
	var r := _registered()
	var state = r["game"]["state"]
	assert_eq(Lifecycle.check_can_apply(state, 1), "", "batalha ativa: o resultado ainda poderá ser aplicado")
	assert_true(Lifecycle.cancel(state, 1)["ok"], "primeiro cancelamento")
	var snapshot: Dictionary = state.to_dict()
	var again := Lifecycle.cancel(state, 1)
	assert_true(not again["ok"] and "'cancelled' e não pode passar a 'cancelled'" in again["message"], again["message"])
	assert_eq(state.to_dict(), snapshot, "cancelar de novo não altera nada (histórico inclusive)")
	var apply_cancelled := Lifecycle.transition(state, 1, "applied")
	assert_true(not apply_cancelled["ok"], "aplicar resultado a batalha cancelada é recusado")
	assert_true(Lifecycle.check_can_apply(state, 1) != "", "check_can_apply recusa batalha cancelada")
	assert_true(not Lifecycle.cancel(state, 999)["ok"], "batalha inexistente")
	assert_true("inexistente" in Lifecycle.cancel(state, 999)["message"], "mensagem clara")
	assert_true("desconhecido" in Lifecycle.check_transition(state, 1, "voando"), "estado desconhecido")

	# Batalha aplicada (futuro): final, não pode ser cancelada nem aplicada de novo.
	var second := new_game()
	var encounter_id := make_encounter(second)
	assert_true(Lifecycle.register(second["registry"], second["state"], build_scenario(second, encounter_id))["ok"], "outra batalha")
	assert_true(Lifecycle.transition(second["state"], 1, "applied")["ok"], "active -> applied")
	assert_true(not Lifecycle.cancel(second["state"], 1)["ok"], "cancelar batalha aplicada é recusado")
	assert_true(not Lifecycle.transition(second["state"], 1, "applied")["ok"], "aplicar duas vezes é recusado")
	assert_true(Lifecycle.check_can_apply(second["state"], 1) != "", "check_can_apply recusa batalha aplicada")
	assert_eq(second["state"].battles[1]["history"].size(), 2, "histórico: active, applied (sem entradas extras)")
	assert_eq(second["state"].battle_of_army(second["state"].battles[1]["armies"][0]), 0, "aplicada também libera os exércitos")


# --- Turno ---------------------------------------------------------------------------------------------------------

func test_turn_cannot_advance_during_an_active_battle() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var state = game["state"]
	var before: Dictionary = state.to_dict()
	var report := TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not report["ok"], "o encerramento falha de forma controlada")
	assert_has_error(PackedStringArray(report["errors"]), "batalha ativa (#1 em Alsácia)", "mensagem clara")
	assert_eq(report["phases"], [&"validate_state"] as Array[StringName], "só a validação executou: nada parcial")
	assert_eq(state.turn, 1, "turno inalterado")
	assert_eq(state.to_dict(), before, "recursos, filas, exércitos e registro intactos")
	var again := TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not again["ok"] and state.to_dict() == before, "repetir a tentativa continua sem efeito")


func test_controller_reports_the_turn_block_and_the_locked_army_status() -> void:
	var r := _registered()
	var game: Dictionary = r["game"]
	var pmap := ProvinceMap.new()
	pmap.build(game["registry"])
	var controller := CampaignController.new()
	controller.setup(game["registry"], game["state"], pmap)
	var messages: Array[Dictionary] = []
	var changes: Array[int] = []
	controller.message_posted.connect(func(text: String, is_error: bool) -> void: messages.append({"text": text, "error": is_error}))
	controller.state_changed.connect(func() -> void: changes.append(1))
	var report := controller.end_turn()
	assert_true(not report["ok"], "controlador: recusado")
	assert_true(messages[-1]["error"] and "batalha ativa" in messages[-1]["text"], messages[-1]["text"])
	assert_eq(changes.size(), 0, "nenhuma notificação de mudança")
	assert_eq(game["state"].turn, 1, "turno inalterado")
	var army_id: int = _participants(game, r["encounter_id"])[0]
	assert_true("Em batalha ativa #1" in controller.army_view(army_id)["status"], "o painel do exército informa o bloqueio")


func test_turn_advances_after_cancel_only_if_no_other_battle_is_active() -> void:
	var game := new_game()
	var state = game["state"]
	var first_encounter := make_encounter(game, PROVINCE)
	var second_encounter := make_encounter(game, OTHER_PROVINCE)
	assert_true(Lifecycle.register(game["registry"], state, build_scenario(game, first_encounter))["ok"], "batalha 1")
	assert_true(Lifecycle.register(game["registry"], state, build_scenario(game, second_encounter))["ok"], "batalha 2 (outra província)")
	assert_eq(state.active_battles(), [1, 2] as Array[int], "duas batalhas ativas")
	var report := TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not report["ok"], "bloqueado por duas batalhas")
	assert_eq(PackedStringArray(report["errors"]).size(), 2, "cada batalha ativa é citada")
	assert_true(Lifecycle.cancel(state, 1)["ok"], "cancela a primeira")
	var still_blocked := TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not still_blocked["ok"], "ainda bloqueado pela segunda")
	assert_has_error(PackedStringArray(still_blocked["errors"]), "#2 em Île-de-France", "cita a batalha restante")
	assert_eq(state.turn, 1, "turno ainda 1")
	assert_true(Lifecycle.cancel(state, 2)["ok"], "cancela a segunda")
	var released := TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(released["ok"], "sem batalhas ativas: o turno avança: %s" % str(released["errors"]))
	assert_eq(state.turn, 2, "turno 2")
	assert_eq(state.battles.size(), 2, "o histórico das duas batalhas permanece")


func test_battle_registry_integrity_is_validated_by_the_turn_processor() -> void:
	var processor := TurnProcessor.new()
	var cases := {
		"exército sumiu": func(game: Dictionary) -> void: game["state"].armies.erase(game["state"].battles[1]["armies"][0]),
		"composição alterada por fora": func(game: Dictionary) -> void:
			var army: Dictionary = game["state"].armies[_participants(game, game["state"].battles[1]["encounter_id"])[0]]
			army["units"].pop_back(),
		"exército fora da província": func(game: Dictionary) -> void: game["state"].armies[game["state"].battles[1]["armies"][0]]["province"] = OTHER_PROVINCE,
		"encontro desvinculado": func(game: Dictionary) -> void: game["state"].encounters[0].erase("battle_id"),
		"estado inválido": func(game: Dictionary) -> void: game["state"].battles[1]["status"] = "voando",
		"id inconsistente": func(game: Dictionary) -> void: game["state"].next_battle_id = 1,
	}
	for label in cases:
		var r := _registered()
		assert_eq(processor.validate_state(r["game"]["registry"], r["game"]["state"]), PackedStringArray(), "estado sadio: %s" % label)
		cases[label].call(r["game"])
		assert_true(not processor.validate_state(r["game"]["registry"], r["game"]["state"]).is_empty(), "detectado: %s" % label)
	var r2 := _registered()
	var forged: Dictionary = r2["game"]["state"].battles[1].duplicate(true)
	forged["id"] = 2
	r2["game"]["state"].battles[2] = forged
	r2["game"]["state"].next_battle_id = 3
	assert_has_error(processor.validate_state(r2["game"]["registry"], r2["game"]["state"]), "mais de uma batalha ativa", "exército em duas batalhas ativas")


func test_validation_detects_orphan_links_and_malformed_records_without_crashing() -> void:
	var processor := TurnProcessor.new()
	var cases := {
		"vínculo para batalha cancelada": func(game: Dictionary) -> void:
			Lifecycle.cancel(game["state"], 1)
			game["state"].encounters[0]["battle_id"] = 1,
		"vínculo para batalha inexistente": func(game: Dictionary) -> void:
			Lifecycle.cancel(game["state"], 1)
			game["state"].encounters[0]["battle_id"] = 99,
		"batalha ativa de outro encontro": func(game: Dictionary) -> void: game["state"].battles[1]["encounter_id"] = 77,
		"registro sem exércitos": func(game: Dictionary) -> void: game["state"].battles[1].erase("armies"),
		"registro sem instantâneo": func(game: Dictionary) -> void: game["state"].battles[1].erase("units"),
	}
	for label in cases:
		var r := _registered()
		cases[label].call(r["game"])
		assert_true(not processor.validate_state(r["game"]["registry"], r["game"]["state"]).is_empty(), "detectado: %s" % label)


## O estado fica válido antes de qualquer batalha, após registrar, cancelar (uma de duas), tentativas inválidas e com várias batalhas.
func test_state_stays_valid_across_the_battle_lifecycle() -> void:
	var game := new_game()
	var registry = game["registry"]
	var state = game["state"]
	var processor := TurnProcessor.new()
	assert_eq(processor.validate_state(registry, state), PackedStringArray(), "antes de qualquer batalha")
	var first := make_encounter(game, PROVINCE)
	var second := make_encounter(game, OTHER_PROVINCE)
	assert_true(Lifecycle.register(registry, state, build_scenario(game, second))["ok"], "registra a do encontro 2 primeiro (id 1)")
	assert_eq(processor.validate_state(registry, state), PackedStringArray(), "após registrar")
	assert_true(Lifecycle.register(registry, state, build_scenario(game, first))["ok"], "registra a outra (id 2, outra província)")
	assert_eq(processor.validate_state(registry, state), PackedStringArray(), "com várias batalhas ativas")
	var before: Dictionary = state.to_dict()
	assert_true(not Lifecycle.register(registry, state, {"ok": false})["ok"], "registro inválido")
	assert_true(not Lifecycle.cancel(state, 99)["ok"], "cancelar inexistente")
	assert_eq(state.to_dict(), before, "tentativas inválidas não alteram nada")
	assert_eq(processor.validate_state(registry, state), PackedStringArray(), "após tentativas inválidas")
	assert_true(Lifecycle.cancel(state, 1)["ok"], "cancela a 1 (a 2 segue ativa)")
	assert_true(not Lifecycle.cancel(state, 1)["ok"], "cancelar de novo")
	assert_eq(state.active_battles(), [2] as Array[int], "só a 2 ativa")
	assert_eq(processor.validate_state(registry, state), PackedStringArray(), "após cancelar uma e manter a outra")
	assert_true(Lifecycle.cancel(state, 2)["ok"], "cancela a 2")
	assert_eq(processor.validate_state(registry, state), PackedStringArray(), "após cancelar todas")


func test_new_game_state_starts_without_battles() -> void:
	var game := new_game()
	assert_eq(game["state"].battles, {}, "sem batalhas")
	assert_eq(game["state"].next_battle_id, 1, "primeiro id")
	assert_eq(game["state"].active_battles(), [] as Array[int], "nenhuma ativa")
	assert_eq(game["state"].battle_of_army(1), 0, "nenhum exército bloqueado")
	var r := _registered()
	assert_true(r["game"]["state"].setup_from_registry(r["game"]["registry"], "fra"), "reiniciar o estado")
	assert_eq(r["game"]["state"].battles, {}, "reiniciar limpa o registro")
	assert_eq(r["game"]["state"].next_battle_id, 1, "e o contador")
