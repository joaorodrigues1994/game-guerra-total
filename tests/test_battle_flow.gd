extends "res://tests/integration_case.gd"
## Fluxo campanha -> batalha tática (Etapa 5): iniciar a partir do encontro, jogar até o fim, voltar, cancelar.
## O resultado tático é apenas REGISTRADO: nada é aplicado à campanha e a batalha continua "active".

const Flow := preload("res://src/integration/battle_flow.gd")
const Request := preload("res://src/integration/battle_request.gd")
const Lifecycle := preload("res://src/integration/battle_lifecycle.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")

const MAIN_SCENE := "res://scenes/main.tscn"


func _controller(game: Dictionary) -> CampaignController:
	var province_map := ProvinceMap.new()
	province_map.build(game["registry"])
	var controller := CampaignController.new()
	controller.setup(game["registry"], game["state"], province_map)
	return controller


## Jogo + encontro + controlador da campanha + lista das batalhas iniciadas ([[id, controlador tático], ...]).
func _setup() -> Dictionary:
	var game := new_game()
	var encounter_id := make_encounter(game)
	var controller := _controller(game)
	var started := []
	controller.battle_started.connect(func(battle_id: int, battle: RefCounted) -> void: started.append([battle_id, battle]))
	return {"game": game, "state": game["state"], "registry": game["registry"], "encounter_id": encounter_id,
		"controller": controller, "started": started}


## Dados estratégicos sem o registro de batalhas e sem o vínculo battle_id dos encontros.
func _strategic(state: RefCounted) -> Dictionary:
	var data: Dictionary = state.to_dict()
	data.erase("battles")
	data.erase("next_battle_id")
	var encounters := []
	for encounter in data.get("encounters", []):
		var copy: Dictionary = encounter.duplicate(true)
		copy.erase("battle_id")
		encounters.append(copy)
	data["encounters"] = encounters
	return data


func _wipe(battle: RefCounted, side: String) -> void:
	wipe_side(battle, side)


func _free_of_lock(state: RefCounted) -> bool:
	for army_id in state.armies:
		if state.battle_of_army(army_id) != 0:
			return false
	return true


# --- Início ------------------------------------------------------------------------------------

func test_context_loads_the_battle_data() -> void:
	var context := Flow.load_context()
	assert_true(context["ok"], str(context["errors"]))
	assert_true(context["battle_registry"] != null and not context["mapping"].is_empty(), "registro e mapeamento")


func test_start_registers_locks_and_opens_exactly_the_registered_scenario() -> void:
	var s := _setup()
	var state = s["state"]
	var captured := []
	var spy := func(battle_registry: RefCounted, scenario: Dictionary) -> RefCounted:
		captured.append(scenario.duplicate(true))
		var battle := BattleController.new()
		return battle if battle.setup_from_scenario(battle_registry, scenario) else null
	var result := Flow.start(s["registry"], state, Flow.load_context(), s["encounter_id"], spy)
	assert_true(result["ok"], result["message"])
	var battle_id: int = result["battle_id"]
	assert_eq(state.battles[battle_id]["status"], "active", "batalha ativa")
	assert_eq(captured.size(), 1, "inicializou uma vez")
	assert_eq(captured[0], state.battles[battle_id]["scenario"], "a cena recebeu EXATAMENTE o cenário registrado")
	var battle: BattleController = result["controller"]
	assert_eq(battle.scenario, state.battles[battle_id]["scenario"], "o controlador guarda o cenário registrado")
	assert_eq(battle.linked_battle_id, battle_id, "ligada à batalha da campanha")
	assert_eq(battle.state.units.size(), state.battles[battle_id]["scenario"]["units"].size(), "todas as unidades do cenário")
	for entry in state.battles[battle_id]["scenario"]["units"]:
		var found := false
		for id in battle.state.units:
			var unit: Dictionary = battle.state.units[id]
			if unit["source_id"] == entry["source_id"]:
				found = true
				assert_eq(unit["strength"], entry["strength"], "efetivo da unidade %d" % entry["source_id"])
				# A regra tática existente recupera moral no início do turno 1 (até morale_recovery), sem inimigo adjacente.
				var gain: int = unit["morale"] - entry["morale"]
				assert_true(gain >= 0 and gain <= int(battle.state.rules["morale_recovery"]), "moral da unidade %d (cenário %d, batalha %d)" % [entry["source_id"], entry["morale"], unit["morale"]])
				assert_eq(unit["type"], entry["type"], "tipo tático")
				assert_eq(unit["pos"], hx(int(entry["at"][0]), int(entry["at"][1])), "posição da unidade %d" % entry["source_id"])
				assert_eq(unit["side"], entry["side"], "lado")
		assert_true(found, "unidade %d presente na batalha" % entry["source_id"])
	assert_true(not state.battles[battle_id]["armies"].is_empty(), "participantes registrados")
	for army_id in state.battles[battle_id]["armies"]:
		assert_eq(state.battle_of_army(army_id), battle_id, "exército %d bloqueado" % army_id)
	assert_eq(TurnProcessor.new().validate_state(s["registry"], state), PackedStringArray(), "estado consistente")


func test_invalid_stale_and_unavailable_requests_are_refused_without_changes() -> void:
	var s := _setup()
	var state = s["state"]
	var context := Flow.load_context()
	var before: Dictionary = state.to_dict()
	assert_true(not Flow.start(s["registry"], state, context, 999)["ok"], "encontro inexistente")
	assert_true(not Flow.start(s["registry"], state, {"ok": false, "errors": PackedStringArray(["sem dados"])}, s["encounter_id"])["ok"], "dados da batalha indisponíveis")
	assert_eq(state.to_dict(), before, "recusas não alteram nada")
	# Desatualizado: o inimigo sai da província e o encontro deixa de existir.
	for army_id in state.armies.keys():
		if state.armies[army_id]["owner"] == "aus":
			state.armies.erase(army_id)
	ArmyActions.refresh_encounters(state)
	var stale := Flow.start(s["registry"], state, context, s["encounter_id"])
	assert_true(not stale["ok"], "encontro que já não existe")
	assert_eq(state.battles.size(), 0, "nenhum registro")
	assert_eq(state.next_battle_id, 1, "id não consumido")


func test_repeated_start_never_registers_twice() -> void:
	var s := _setup()
	var state = s["state"]
	var first: Dictionary = s["controller"].start_battle(s["encounter_id"])
	assert_true(first["ok"], first["message"])
	var second: Dictionary = s["controller"].start_battle(s["encounter_id"])
	assert_true(not second["ok"], "segundo clique recusado")
	assert_true("batalha ativa" in second["message"], second["message"])
	assert_eq(state.battles.size(), 1, "um único registro")
	assert_eq(state.next_battle_id, 2, "um único id consumido")
	assert_eq(s["started"].size(), 1, "uma única cena aberta")


# --- Falha de inicialização --------------------------------------------------------------------

func test_scene_initialization_failure_cancels_the_battle_and_leaves_no_orphan_lock() -> void:
	var s := _setup()
	var state = s["state"]
	var strategic_before := _strategic(state)
	var failing := func(_battle_registry: RefCounted, _scenario: Dictionary) -> RefCounted: return null
	var result := Flow.start(s["registry"], state, Flow.load_context(), s["encounter_id"], failing)
	assert_true(not result["ok"], "falhou")
	assert_true("cancelada" in result["message"], result["message"])
	assert_eq(state.battles[1]["status"], "cancelled", "o registro ficou cancelado (histórico preservado)")
	assert_eq(state.active_battles(), [] as Array[int], "nenhuma batalha ativa inacessível")
	assert_true(_free_of_lock(state), "nenhum exército bloqueado")
	assert_true(not Request.find_encounter(state, s["encounter_id"]).has("battle_id"), "encontro sem vínculo")
	assert_eq(_strategic(state), strategic_before, "dados estratégicos intactos")
	assert_eq(TurnProcessor.new().validate_state(s["registry"], state), PackedStringArray(), "estado consistente")
	var retry := Flow.start(s["registry"], state, Flow.load_context(), s["encounter_id"])
	assert_true(retry["ok"] and retry["battle_id"] == 2, "o encontro pode tentar de novo (id 2): %s" % retry["message"])


func test_controller_rejects_an_invalid_scenario_and_stays_as_it_was() -> void:
	var battle := new_controller()
	var units_before: Dictionary = battle.state.units.duplicate(true)
	assert_true(not battle.setup_from_scenario(battle.registry, {"id": "x"}), "cenário inválido")
	assert_true(not battle.setup_errors.is_empty(), "motivos informados")
	assert_eq(battle.state.units, units_before, "controlador intacto")
	assert_eq(battle.scenario_id, "test_battle", "mesmo cenário")


func test_a_campaign_battle_cannot_be_restarted() -> void:
	var s := _setup()
	var result := Flow.start(s["registry"], s["state"], Flow.load_context(), s["encounter_id"])
	var battle: BattleController = result["controller"]
	battle.end_turn()
	var turn: int = battle.state.turn
	battle.restart()
	assert_eq(battle.state.turn, turn, "não reiniciou")
	var standalone := new_controller()
	standalone.end_turn()
	standalone.restart()
	assert_eq(standalone.state.turn, 1, "a batalha de teste continua reiniciando")


# --- Resultado: vitória e derrota, sem aplicação -----------------------------------------------

## Camada de REGISTRO: a cena tática é iniciada por BattleFlow.start (sem o ouvinte do CampaignController), então o
## resultado é apenas registrado em battle["tactical_result"], sem aplicação (a aplicação é testada em
## test_battle_resolution.gd, que usa o fluxo completo).
func _play_to_the_end(loser_side: String) -> Dictionary:
	var s := _setup()
	var state = s["state"]
	var strategic_before := _strategic(state)
	var result := Flow.start(s["registry"], state, Flow.load_context(), s["encounter_id"])
	assert_true(result["ok"], result["message"])
	var battle: BattleController = result["controller"]
	var battle_id: int = result["battle_id"]
	# Dano tático que NÃO pode vazar para a campanha na camada de registro.
	for id in battle.state.live_units("player"):
		battle.state.units[id]["strength"] = 1
		battle.state.units[id]["morale"] = 1
		break
	_wipe(battle, loser_side)
	battle.end_turn()
	assert_true(Flow.record_result(state, battle_id, battle.state.result_summary())["ok"], "resultado registrado")
	s["battle"] = battle
	s["battle_id"] = battle_id
	s["strategic_before"] = strategic_before
	return s


func test_victory_is_recorded_but_not_applied() -> void:
	var s := _play_to_the_end("enemy")
	var state = s["state"]
	assert_true(s["battle"].state.over, "cena tática terminou")
	var record: Dictionary = state.battles[s["battle_id"]]
	assert_eq(record["tactical_result"]["winner"], "player", "vitória registrada")
	assert_eq(record["tactical_result"]["scenario_id"], record["scenario_id"], "do cenário registrado")
	assert_eq(record["status"], "active", "NÃO virou applied nem cancelled")
	assert_eq(record["result"], {}, "result (aplicação) segue vazio")
	assert_eq(_strategic(state), s["strategic_before"], "efetivo, moral, exércitos, unidades, províncias e recursos intactos")
	assert_eq(state.battle_of_army(record["armies"][0]), s["battle_id"], "participantes seguem bloqueados")


func test_defeat_is_recorded_but_not_applied() -> void:
	var s := _play_to_the_end("player")
	var state = s["state"]
	var record: Dictionary = state.battles[s["battle_id"]]
	assert_eq(record["tactical_result"]["winner"], "enemy", "derrota registrada")
	assert_eq(record["status"], "active", "NÃO virou applied")
	assert_eq(record["result"], {}, "result segue vazio")
	assert_eq(_strategic(state), s["strategic_before"], "campanha intacta")


func test_tactical_result_is_recorded_once_and_only_for_the_matching_active_battle() -> void:
	var s := _play_to_the_end("enemy")
	var state = s["state"]
	var summary: Dictionary = s["battle"].state.result_summary()
	var recorded: Dictionary = state.battles[s["battle_id"]]["tactical_result"].duplicate(true)
	assert_true(not Lifecycle.record_tactical_result(state, s["battle_id"], summary)["ok"], "segundo registro recusado")
	assert_true(not Lifecycle.record_tactical_result(state, 99, summary)["ok"], "batalha inexistente")
	var other := summary.duplicate(true)
	other["scenario_id"] = "outro"
	assert_true(not Lifecycle.check_can_record_result(state, s["battle_id"], other).is_empty(), "cenário diferente")
	assert_eq(state.battles[s["battle_id"]]["tactical_result"], recorded, "nada mudou")
	Lifecycle.cancel(state, s["battle_id"])
	assert_true(not Lifecycle.record_tactical_result(state, s["battle_id"], summary)["ok"], "batalha cancelada não recebe resultado")
	# Resultado incompleto (batalha não concluída) em uma batalha ativa nova.
	var again: Dictionary = s["controller"].start_battle(s["encounter_id"])
	assert_true(again["ok"], again["message"])
	var unfinished: Dictionary = s["started"][0][1].state.result_summary()
	assert_true(not Lifecycle.record_tactical_result(state, again["battle_id"], unfinished)["ok"], "sem vencedor: recusado")
	assert_eq(state.battles[again["battle_id"]]["tactical_result"], {}, "nada registrado")


func test_malformed_tactical_result_is_reported_by_state_validation() -> void:
	var s := _setup()
	s["controller"].start_battle(s["encounter_id"])
	s["state"].battles[1]["tactical_result"] = "x"
	assert_true(not TurnProcessor.new().validate_state(s["registry"], s["state"]).is_empty(), "detectado")


# --- Cancelamento e turno ---------------------------------------------------------------------

func test_cancel_releases_armies_and_the_encounter_can_start_another_battle() -> void:
	var s := _setup()
	var state = s["state"]
	s["controller"].start_battle(s["encounter_id"])
	var cancelled: Dictionary = s["controller"].cancel_battle(1)
	assert_true(cancelled["ok"], cancelled["message"])
	assert_true(_free_of_lock(state), "exércitos liberados")
	assert_true(not Request.find_encounter(state, s["encounter_id"]).has("battle_id"), "vínculo removido")
	assert_true(not s["controller"].cancel_battle(1)["ok"], "cancelar de novo é recusado")
	assert_true(s["controller"].start_battle(s["encounter_id"])["ok"], "nova batalha (id 2)")
	assert_eq(state.battles.size(), 2, "histórico das duas")
	assert_eq(TurnProcessor.new().validate_state(s["registry"], state), PackedStringArray(), "estado consistente")


func test_turn_stays_blocked_during_and_after_the_tactical_battle_until_it_is_cancelled() -> void:
	var s := _play_to_the_end("enemy")
	var state = s["state"]
	var controller: CampaignController = s["controller"]
	assert_true(not controller.end_turn()["ok"], "bloqueado com a batalha concluída mas não aplicada")
	assert_eq(state.turn, 1, "turno não avançou")
	assert_true(controller.cancel_battle(s["battle_id"])["ok"], "cancela")
	assert_true(controller.end_turn()["ok"], "depois do cancelamento o turno avança")
	assert_eq(state.turn, 2, "turno 2")


func test_province_view_exposes_the_battle_actions_by_phase() -> void:
	var s := _setup()
	var controller: CampaignController = s["controller"]
	var actions: Array = controller.province_view(PROVINCE)["encounter_actions"]
	assert_eq(actions.size(), 1, "um encontro")
	assert_eq(actions[0]["phase"], "free", "livre")
	assert_eq(actions[0]["start_reason"], "", "pode iniciar")
	controller.start_battle(s["encounter_id"])
	actions = controller.province_view(PROVINCE)["encounter_actions"]
	assert_eq(actions[0]["phase"], "in_progress", "em andamento")
	assert_eq(actions[0]["battle_id"], 1, "batalha 1")
	assert_eq(Flow.start_reason(s["registry"], s["state"], s["encounter_id"]).is_empty(), false, "não pode iniciar outra")
	# Resultado incoerente (unidade "destruída" com efetivo): a aplicação é recusada e a batalha segue ativa.
	var tactical: BattleController = s["started"][0][1]
	_wipe(tactical, "enemy")
	tactical.state.units[tactical.state.units.keys()[tactical.state.units.size() - 1]]["strength"] = 5
	tactical.end_turn()
	actions = controller.province_view(PROVINCE)["encounter_actions"]
	assert_eq(actions[0]["phase"], "finished", "concluída, mas a aplicação falhou")
	assert_true(not actions[0]["result_text"].is_empty(), "texto do resultado")
	controller.cancel_battle(1)
	assert_eq(controller.province_view(PROVINCE)["encounter_actions"][0]["phase"], "free", "livre de novo")
	assert_eq(controller.province_view(OTHER_PROVINCE)["encounter_actions"], [] as Array[Dictionary], "outra província sem encontro")


# --- Cena principal (interface montada, sem janela) -----------------------------------------

func _campaign() -> Control:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func _main_with_encounter() -> Dictionary:
	var main := _campaign()
	var game := {"registry": main.registry, "state": main.state}
	var encounter_id := make_encounter(game)
	main.controller.select_province(PROVINCE)
	main.controller.state_changed.emit()
	return {"main": main, "encounter_id": encounter_id}


func test_main_scene_starts_the_battle_from_the_province_panel_and_cancels_when_leaving_early() -> void:
	var m := _main_with_encounter()
	var main: Control = m["main"]
	var state = main.state
	var state_object: RefCounted = state
	var turn: int = state.turn
	var strategic_before := _strategic(state)
	var button: Button = main.screen.province_panel.start_battle_buttons[m["encounter_id"]]
	assert_true(not button.disabled, "botão habilitado")
	button.pressed.emit()
	assert_true(main.battle_screen != null, "cena tática aberta")
	assert_eq(main.current_battle_id, 1, "batalha 1")
	assert_true(not main.screen.visible, "campanha oculta por baixo")
	assert_true(not main.battle_screen.restart_button.visible, "sem reinício")
	assert_eq(main.battle_screen.back_button.text, "Cancelar batalha e voltar", "sair antes do fim cancela")
	assert_true("#1" in main.battle_screen.title_label.text, main.battle_screen.title_label.text)
	assert_eq(state.battles[1]["status"], "active", "ativa")
	main.battle_screen.back_button.pressed.emit()
	assert_true(main.battle_screen == null and main.screen.visible, "voltou à campanha")
	assert_eq(main.current_battle_id, 0, "sem batalha atual")
	assert_eq(state.battles[1]["status"], "cancelled", "cancelada")
	assert_true(_free_of_lock(state), "exércitos liberados")
	assert_true(main.state == state_object, "o mesmo estado da campanha")
	assert_eq(state.turn, turn, "turno intacto")
	assert_eq(_strategic(state), strategic_before, "dados estratégicos intactos")
	main.free()


func test_main_scene_failed_application_keeps_the_result_and_offers_retry_or_cancel() -> void:
	var m := _main_with_encounter()
	var main: Control = m["main"]
	var state = main.state
	var strategic_before := _strategic(state)
	main.screen.province_panel.start_battle_buttons[m["encounter_id"]].pressed.emit()
	var battle: BattleController = main.battle_screen.controller
	_wipe(battle, "enemy")
	var victim: int = battle.state.units.keys()[battle.state.units.size() - 1]
	battle.state.units[victim]["strength"] = 5  # resultado incoerente: "destruída" com efetivo -> a aplicação é recusada
	battle.end_turn()
	assert_true(main.battle_screen.result_panel.visible, "painel de resultado")
	assert_true(not main.battle_screen.result_panel.restart_button.visible, "sem 'Jogar novamente'")
	assert_eq(main.battle_screen.back_button.text, "Voltar à campanha (resultado pendente)", "depois do fim apenas volta, e avisa que a batalha segue pendente")
	assert_true("Nada foi alterado" in main.screen.status_bar.message_label.text, main.screen.status_bar.message_label.text)
	# A cena tática aberta (a campanha e seu status bar estão ocultos) mostra o erro completo e as ações disponíveis.
	var note = main.battle_screen.result_panel.campaign_note_label
	assert_true(note.visible and not main.screen.visible, "a nota do painel de resultado está visível e a campanha oculta")
	assert_true("NÃO foi aplicado" in note.text, note.text)
	assert_true("continua pendente" in note.text, note.text)
	assert_true("Aplicar resultado" in note.text and "Cancelar batalha" in note.text, "indica as ações: " + note.text)
	assert_true("aplicado aos exércitos ao terminar" not in note.text, "não afirma mais que o resultado é aplicado")
	assert_true(main.battle_screen.application_failed and "pendente" in main.battle_screen.back_button.text, main.battle_screen.back_button.text)
	main.battle_screen.result_panel.back_button.pressed.emit()
	assert_true(main.battle_screen == null and main.screen.visible, "voltou")
	assert_eq(state.battles[1]["status"], "active", "falha de aplicação: continua ativa")
	assert_eq(state.battles[1]["tactical_result"]["winner"], "player", "resultado preservado para nova tentativa")
	assert_eq(state.battles[1]["result"], {}, "nada aplicado")
	assert_eq(_strategic(state), strategic_before, "campanha intacta")
	assert_true(not state.battles[1]["armies"].is_empty() and not _free_of_lock(state), "participantes seguem bloqueados")
	var panel = main.screen.province_panel
	assert_true(panel.apply_battle_buttons.has(1) and panel.cancel_battle_buttons.has(1) and panel.start_battle_buttons.is_empty(), "painel oferece aplicar de novo e cancelar")
	assert_true(not main.controller.end_turn()["ok"], "turno bloqueado, com explicação")
	panel.apply_battle_buttons[1].pressed.emit()
	assert_eq(state.battles[1]["status"], "active", "a nova tentativa com o mesmo resultado falha da mesma forma, sem alterar nada")
	assert_eq(_strategic(state), strategic_before, "e continua intacta")
	# Corrige o registro (diagnóstico) e tenta de novo: aplica uma única vez.
	for side in state.battles[1]["tactical_result"]["units"]:
		for entry in state.battles[1]["tactical_result"]["units"][side]:
			if entry["status"] == "destroyed":
				entry["strength"] = 0
	panel.apply_battle_buttons[1].pressed.emit()
	assert_eq(state.battles[1]["status"], "applied", "aplicada na nova tentativa")
	assert_true(_free_of_lock(state), "liberados")
	assert_true(not main.screen.province_panel.start_battle_buttons.has(m["encounter_id"]), "o encontro foi resolvido")
	assert_true(main.controller.end_turn()["ok"], "o turno avança")
	main.free()


func test_main_scene_double_click_and_a_busy_screen_never_leave_a_second_or_orphan_battle() -> void:
	var m := _main_with_encounter()
	var main: Control = m["main"]
	var state = main.state
	var button: Button = main.screen.province_panel.start_battle_buttons[m["encounter_id"]]
	button.pressed.emit()
	button.pressed.emit()  # segundo clique no mesmo botão (a tela é reconstruída só no fim do quadro)
	assert_eq(state.battles.size(), 1, "um único registro")
	assert_true(main.battle_screen != null, "continua uma única cena")
	main.close_battle()
	assert_eq(state.battles[1]["status"], "cancelled", "fechada antes do fim: cancelada")
	# Tela ocupada (batalha de teste aberta): a batalha registrada é cancelada na hora.
	assert_true(main.open_test_battle(), "batalha de teste aberta")
	var result: Dictionary = main.controller.start_battle(m["encounter_id"])
	assert_true(result["ok"], "registrou")
	assert_eq(state.battles[2]["status"], "cancelled", "sem tela para ela: cancelada")
	assert_true(_free_of_lock(state), "sem bloqueio órfão")
	assert_eq(main.current_battle_id, 0, "a tela de teste não virou batalha da campanha")
	main.free()


func test_application_failure_is_signalled_once_per_attempt_and_never_retried_automatically() -> void:
	var s := _setup()
	var state = s["state"]
	var controller: CampaignController = s["controller"]
	var failures := []
	var resolutions := []
	controller.battle_application_failed.connect(func(battle_id: int, message: String) -> void: failures.append([battle_id, message]))
	controller.battle_resolved.connect(func(battle_id: int, _lines: PackedStringArray) -> void: resolutions.append(battle_id))
	assert_true(controller.start_battle(s["encounter_id"])["ok"], "batalha iniciada")
	var tactical: BattleController = s["started"][0][1]
	_wipe(tactical, "enemy")
	var last: int = tactical.state.units.keys()[tactical.state.units.size() - 1]
	tactical.state.units[last]["strength"] = 5  # resultado incoerente: a aplicação é recusada
	var before: Dictionary = state.to_dict()
	tactical.end_turn()
	assert_eq(failures.size(), 1, "o fim da cena tenta aplicar UMA vez e avisa UMA vez")
	assert_eq(resolutions.size(), 0, "sem sinal de aplicação")
	assert_eq(failures[0][0], 1, "da batalha 1")
	assert_true("NÃO foi aplicado" in failures[0][1] and "continua pendente" in failures[0][1], failures[0][1])
	assert_true("Aplicar resultado" in failures[0][1] and "Cancelar batalha" in failures[0][1], "e diz o que fazer")
	var after_failure: Dictionary = state.to_dict()
	for key in ["battles"]:
		before.erase(key)
		after_failure.erase(key)
	before["encounters"] = _strategic(state)["encounters"]
	after_failure["encounters"] = _strategic(state)["encounters"]
	assert_eq(after_failure, before, "nenhuma alteração parcial na campanha")
	# Nada acontece sozinho: passar o tempo (turnos, mensagens, mais chamadas) não repete a aplicação.
	assert_true(not controller.end_turn()["ok"], "o turno segue bloqueado, com explicação")
	assert_eq(failures.size(), 1, "sem nova tentativa automática")
	# Cada nova tentativa do jogador gera exatamente um aviso, enquanto falhar.
	assert_true(not controller.apply_battle_result(1)["ok"], "a tentativa manual falha do mesmo jeito")
	assert_eq(failures.size(), 2, "um aviso por tentativa")
	# Corrige o registro e tenta de novo: aplica uma vez, sem novo erro.
	for side in state.battles[1]["tactical_result"]["units"]:
		for entry in state.battles[1]["tactical_result"]["units"][side]:
			if entry["status"] == "destroyed":
				entry["strength"] = 0
	assert_true(controller.apply_battle_result(1)["ok"], "agora aplica")
	assert_eq(resolutions, [1], "um único sinal de aplicação")
	assert_eq(failures.size(), 2, "e nenhum erro novo")
	assert_true(not controller.apply_battle_result(1)["ok"], "aplicar de novo é recusado")
	assert_eq(state.battles[1]["history"].size(), 2, "histórico: active -> applied, uma vez")


func test_registration_failure_is_also_reported_with_the_available_action() -> void:
	var s := _setup()
	var controller: CampaignController = s["controller"]
	var failures := []
	controller.battle_application_failed.connect(func(battle_id: int, message: String) -> void: failures.append([battle_id, message]))
	assert_true(controller.start_battle(s["encounter_id"])["ok"], "batalha iniciada")
	controller._on_battle_finished({"scenario_id": "outro", "winner": "player", "units": {}}, 1)  # resumo de outro cenário
	assert_eq(failures.size(), 1, "avisou")
	assert_true("NÃO foi registrado" in failures[0][1] and "continua pendente" in failures[0][1], failures[0][1])
	assert_true("Cancelar batalha" in failures[0][1] and "Aplicar resultado" not in failures[0][1], "sem resultado registrado só o cancelamento faz sentido: " + failures[0][1])
	assert_eq(s["state"].battles[1]["tactical_result"], {}, "nada foi registrado")
	assert_eq(s["state"].battles[1]["status"], "active", "batalha segue ativa")
