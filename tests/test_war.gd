extends "res://tests/integration_case.gd"
## Declaração de guerra (Etapa 5.1): relação em GameState.wars, acesso ao território estrangeiro, encontros hostis
## e o fluxo completo declarar guerra -> mover -> encontro real -> iniciar batalha, com os dados reais da campanha.
## (Mapa: Estrasburgo [fra] -> Suábia [bav] -> Baviera [bav, com o "Exército Bávaro"].)

const WarActions := preload("res://src/campaign/war_actions.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")
const Flow := preload("res://src/integration/battle_flow.gd")
const Lifecycle := preload("res://src/integration/battle_lifecycle.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const BORDER := "prov_strasbourg"  # França, vizinha da Suábia (Baviera)
const FIRST_BAV := "prov_swabia"  # Baviera, sem exército
const BAV_ARMY_PROVINCE := "prov_bavaria"  # Baviera, com o "Exército Bávaro"


func _fra_army(game: Dictionary, province_id: String = BORDER) -> int:
	return army_in(game, "fra", ["unit_line_inf", "unit_line_inf"], province_id)


func _move(game: Dictionary, army_id: int, destination: String) -> Dictionary:
	return ArmyActions.move_army(game["registry"], game["state"], "fra", army_id, destination)


func _controller(game: Dictionary) -> CampaignController:
	var province_map := ProvinceMap.new()
	province_map.build(game["registry"])
	var controller := CampaignController.new()
	controller.setup(game["registry"], game["state"], province_map)
	return controller


func _next_turn(game: Dictionary) -> void:
	var report := TurnProcessor.new().end_turn(game["registry"], game["state"])
	assert_true(report["ok"], "turno avança: %s" % str(report["errors"]))


# --- Declaração ----------------------------------------------------------------------------------

func test_valid_declaration_changes_the_strategic_state() -> void:
	var game := new_game()
	var state = game["state"]
	assert_true(not state.at_war("fra", "bav") and not state.at_war("bav", "fra"), "começa em paz")
	assert_eq(state.wars, {}, "nenhuma guerra no início")
	var result := WarActions.declare_war(game["registry"], state, "fra", "bav")
	assert_true(result["ok"], result["message"])
	assert_true("Baviera" in result["message"], result["message"])
	assert_true(state.at_war("fra", "bav") and state.at_war("bav", "fra"), "relação simétrica")
	assert_true(not state.at_war("fra", "aus"), "países sem guerra declarada não são inimigos")
	assert_eq(state.wars.keys(), ["bav|fra"], "chave canônica do par")
	assert_eq(state.wars["bav|fra"], {"countries": ["bav", "fra"], "declared_by": "fra", "turn": 1}, "registro da guerra")
	assert_eq(state.enemies_of("fra"), ["bav"] as Array[String], "inimigos da França")
	assert_eq(state.enemies_of("aus"), [] as Array[String], "a Áustria segue sem inimigos")
	assert_eq(TurnProcessor.new().validate_state(game["registry"], state), PackedStringArray(), "estado consistente")


func test_invalid_declarations_are_refused_without_changing_anything() -> void:
	var game := new_game()
	var state = game["state"]
	var before: Dictionary = state.to_dict()
	assert_true(not WarActions.declare_war(game["registry"], state, "fra", "fra")["ok"], "contra o próprio país")
	assert_true("si mesmo" in WarActions.check_declare_war(game["registry"], state, "fra", "fra"), "motivo claro")
	assert_true(not WarActions.declare_war(game["registry"], state, "fra", "xxx")["ok"], "país inexistente")
	assert_true(not WarActions.declare_war(game["registry"], state, "xxx", "fra")["ok"], "declarante inexistente")
	assert_true(not state.at_war("fra", "fra"), "nunca em guerra consigo mesmo")
	assert_eq(state.to_dict(), before, "recusas não alteram o estado")


func test_duplicate_declarations_never_create_an_inconsistent_state() -> void:
	var game := new_game()
	var state = game["state"]
	assert_true(WarActions.declare_war(game["registry"], state, "fra", "bav")["ok"], "primeira")
	var snapshot: Dictionary = state.wars.duplicate(true)
	_next_turn(game)
	assert_true(not WarActions.declare_war(game["registry"], state, "fra", "bav")["ok"], "repetida")
	assert_true(not WarActions.declare_war(game["registry"], state, "bav", "fra")["ok"], "no sentido contrário")
	assert_true("Já há guerra" in WarActions.check_declare_war(game["registry"], state, "bav", "fra"), "motivo claro")
	assert_eq(state.wars, snapshot, "a guerra original (turno 1, declarada pela França) fica intacta")
	assert_eq(state.wars.size(), 1, "um único registro")


func test_war_persists_in_the_campaign_state_across_turns_and_resets_with_a_new_game() -> void:
	var game := new_game()
	var state = game["state"]
	WarActions.declare_war(game["registry"], state, "fra", "bav")
	_next_turn(game)
	_next_turn(game)
	assert_true(state.at_war("fra", "bav"), "a guerra continua depois de turnos")
	assert_true(state.to_dict().has("wars") and state.to_dict()["wars"].has("bav|fra"), "faz parte do estado")
	assert_true(state.setup_from_registry(game["registry"], "fra"), "reiniciar a partida")
	assert_eq(state.wars, {}, "uma partida nova começa em paz")


func test_state_validation_reports_corrupted_wars() -> void:
	var processor := TurnProcessor.new()
	var cases := {
		"consigo mesmo": func(s: RefCounted) -> void: s.wars["fra|fra"] = {"countries": ["fra", "fra"], "declared_by": "fra", "turn": 1},
		"país inexistente": func(s: RefCounted) -> void: s.wars["fra|xxx"] = {"countries": ["fra", "xxx"], "declared_by": "fra", "turn": 1},
		"chave não canônica": func(s: RefCounted) -> void: s.wars["fra|bav"] = {"countries": ["bav", "fra"], "declared_by": "fra", "turn": 1},
		"declarante de fora": func(s: RefCounted) -> void: s.wars["bav|fra"] = {"countries": ["bav", "fra"], "declared_by": "aus", "turn": 1},
		"registro inválido": func(s: RefCounted) -> void: s.wars["bav|fra"] = "guerra",
	}
	for label in cases:
		var game := new_game()
		assert_eq(processor.validate_state(game["registry"], game["state"]), PackedStringArray(), "sadio: %s" % label)
		cases[label].call(game["state"])
		assert_true(not processor.validate_state(game["registry"], game["state"]).is_empty(), "detectado: %s" % label)


# --- Movimentação -----------------------------------------------------------------------------------

func test_entering_foreign_territory_is_refused_in_peace_and_allowed_after_war() -> void:
	var game := new_game()
	var state = game["state"]
	var army := _fra_army(game)
	var refused := _move(game, army, FIRST_BAV)
	assert_true(not refused["ok"], "recusado em paz")
	assert_true("Sem acesso ao território de Baviera" in refused["message"], refused["message"])
	assert_eq(state.armies[army]["province"], BORDER, "o exército não saiu do lugar")
	assert_true(not state.armies[army]["moved"], "e não gastou o movimento")
	var in_peace := ArmyActions.destinations(game["registry"], state, "fra", army)
	assert_true(not in_peace.filter(func(d: Dictionary) -> bool: return d["id"] == FIRST_BAV)[0]["reason"].is_empty(), "a interface mostra o motivo")
	declare_war_between(game, "fra", "bav")
	assert_eq(ArmyActions.check_move(game["registry"], state, "fra", army, FIRST_BAV), "", "validação efetiva liberada")
	assert_true(ArmyActions.destinations(game["registry"], state, "fra", army).filter(
			func(d: Dictionary) -> bool: return d["id"] == FIRST_BAV)[0]["reason"].is_empty(), "e a lista da interface também")
	var moved := _move(game, army, FIRST_BAV)
	assert_true(moved["ok"], moved["message"])
	assert_eq(state.armies[army]["province"], FIRST_BAV, "entrou na Suábia")
	assert_true(moved["encounter"].is_empty() and state.encounters.is_empty(), "sem exército inimigo ali: sem encontro")
	assert_eq(state.owner_of(FIRST_BAV), "bav", "nenhuma conquista: a província continua da Baviera")


func test_war_with_one_country_does_not_open_the_territory_of_another() -> void:
	var game := new_game()
	var army := _fra_army(game, "prov_paris")
	declare_war_between(game, "fra", "aus")
	var refused := _move(game, army, "prov_franconia")  # Baviera, sem guerra
	assert_true(not refused["ok"] and "Baviera" in refused["message"], refused["message"])


func test_war_does_not_remove_the_other_movement_rules() -> void:
	var game := new_game()
	var state = game["state"]
	declare_war_between(game, "fra", "bav")
	var army := _fra_army(game)
	assert_true("não é conectada" in ArmyActions.check_move(game["registry"], state, "fra", army, "prov_bavaria"), "sem teletransporte: só vizinhas")
	assert_true(_move(game, army, FIRST_BAV)["ok"], "move uma vez")
	assert_true("já se moveu" in ArmyActions.check_move(game["registry"], state, "fra", army, BAV_ARMY_PROVINCE), "uma província por turno")
	assert_true("outro país" in ArmyActions.check_move(game["registry"], state, "bav", army, BAV_ARMY_PROVINCE), "só o dono dá ordens")
	assert_true(not ArmyActions.check_move(game["registry"], state, "fra", 9999, FIRST_BAV).is_empty(), "exército inexistente")


func test_own_territory_movement_is_unchanged() -> void:
	var game := new_game()
	var state = game["state"]
	var army := _fra_army(game, "prov_paris")
	var moved := _move(game, army, BORDER)
	assert_true(moved["ok"] and moved["encounter"].is_empty(), "movimento em território próprio, sem guerra: %s" % moved["message"])
	assert_eq(state.armies[army]["province"], BORDER, "chegou")
	assert_eq(state.wars, {}, "e nada foi declarado")


# --- Encontros ---------------------------------------------------------------------------------------

func test_armies_of_countries_not_at_war_never_generate_encounters() -> void:
	var game := new_game()
	var state = game["state"]
	army_in(game, "aus", ["unit_line_inf"], BORDER)  # presença austríaca em território francês, sem guerra
	var mine := _fra_army(game, "prov_paris")
	var moved := _move(game, mine, BORDER)
	assert_true(moved["ok"], moved["message"])
	assert_true(moved["encounter"].is_empty() and state.encounters.is_empty(), "paz: coexistem sem encontro")
	assert_true(not ArmyActions.is_engaged(state, mine), "nenhum exército fica parado")
	declare_war_between(game, "fra", "bav")  # guerra com OUTRO país não torna a Áustria hostil
	var second := _fra_army(game, "prov_paris")
	var joined := _move(game, second, BORDER)
	assert_true(joined["ok"] and joined["encounter"].is_empty(), "guerra com a Baviera não cria encontro com a Áustria")
	assert_true(state.encounters.is_empty(), "nenhum encontro")


func test_real_movement_into_an_enemy_army_registers_the_encounter_and_the_battle_can_start() -> void:
	var game := new_game()
	var state = game["state"]
	var registry = game["registry"]
	var bavarian: Array[int] = state.armies_in(BAV_ARMY_PROVINCE, "bav")
	assert_eq(bavarian.size(), 1, "o mapa inicial tem o Exército Bávaro em %s" % BAV_ARMY_PROVINCE)
	var mine := _fra_army(game)
	assert_true(WarActions.declare_war(registry, state, "fra", "bav")["ok"], "guerra à Baviera")
	assert_true(_move(game, mine, FIRST_BAV)["ok"], "1º turno: Estrasburgo -> Suábia")
	_next_turn(game)
	var arrival := _move(game, mine, BAV_ARMY_PROVINCE)
	assert_true(arrival["ok"], arrival["message"])
	assert_true("Encontro pendente" in arrival["message"], arrival["message"])
	assert_eq(state.encounters.size(), 1, "um encontro real")
	var participants: Array = [mine, bavarian[0]]
	participants.sort()  # o registro guarda os exércitos ordenados por id
	var encounter: Dictionary = state.encounters[0]
	assert_eq(encounter["province"], BAV_ARMY_PROVINCE, "na província do inimigo")
	assert_eq(encounter["countries"], ["bav", "fra"] as Array, "países")
	assert_eq(encounter["armies"], participants, "participantes")
	assert_eq(encounter["initiator"], mine, "quem entrou")
	assert_eq(TurnProcessor.new().validate_state(registry, state), PackedStringArray(), "estado consistente")

	var started := Flow.start(registry, state, Flow.load_context(), encounter["id"])
	assert_true(started["ok"], started["message"])
	var battle_id: int = started["battle_id"]
	assert_eq(state.battles[battle_id]["province"], BAV_ARMY_PROVINCE, "batalha na província do encontro")
	assert_eq(state.battles[battle_id]["countries"], ["fra", "bav"] as Array, "jogador e adversário")
	assert_eq(state.battles[battle_id]["armies"], participants, "participantes bloqueados")
	assert_eq(state.battle_of_army(mine), battle_id, "o exército do jogador está na batalha")


func test_active_battle_locks_still_apply_in_enemy_territory() -> void:
	var game := new_game()
	var state = game["state"]
	var registry = game["registry"]
	declare_war_between(game, "fra", "bav")
	var vanguard := _fra_army(game, FIRST_BAV)
	assert_true(_move(game, vanguard, BAV_ARMY_PROVINCE)["ok"], "chega ao inimigo")
	var reinforcement := _fra_army(game, FIRST_BAV)
	var started := Flow.start(registry, state, Flow.load_context(), state.encounters[0]["id"])
	assert_true(started["ok"], started["message"])
	ArmyActions.reset_movement(state)  # o turno não avança com batalha ativa: só libera o movimento para testar o bloqueio
	var lock := ArmyActions.check_move(registry, state, "fra", vanguard, FIRST_BAV)
	assert_true("batalha ativa" in lock, "exército bloqueado não se move: %s" % lock)
	var entry := ArmyActions.check_move(registry, state, "fra", reinforcement, BAV_ARMY_PROVINCE)
	assert_true("batalha ativa" in entry, "ninguém entra na província da batalha: %s" % entry)
	assert_true(not _move(game, reinforcement, BAV_ARMY_PROVINCE)["ok"], "e a ação efetiva também recusa")
	assert_eq(state.armies[reinforcement]["province"], FIRST_BAV, "o reforço não saiu do lugar")
	assert_true(Lifecycle.cancel(state, started["battle_id"])["ok"], "cancelar")
	assert_eq(ArmyActions.check_move(registry, state, "fra", reinforcement, BAV_ARMY_PROVINCE), "", "depois do cancelamento o reforço pode entrar")


# --- Fluxo completo pela campanha (controlador) -------------------------------------------------------

func test_full_flow_through_the_campaign_controller() -> void:
	var game := new_game()
	var state = game["state"]
	var controller := _controller(game)
	var opened := []
	controller.battle_started.connect(func(battle_id: int, battle: RefCounted) -> void: opened.append([battle_id, battle]))
	var army := _fra_army(game)
	var denied := controller.move_army(army, FIRST_BAV)
	assert_true(not denied["ok"], "em paz: recusado pela ação do controlador")
	assert_true(controller.province_view(FIRST_BAV)["diplomacy"]["can_declare"], "a província da Baviera oferece declarar guerra")
	assert_eq(controller.province_view(FIRST_BAV)["diplomacy"]["status"], "peace", "relação: paz")
	assert_eq(controller.province_view(BORDER)["diplomacy"]["status"], "own", "província própria: sem diplomacia")
	assert_true(controller.declare_war("bav")["ok"], "declarar guerra")
	assert_eq(controller.province_view(FIRST_BAV)["diplomacy"]["status"], "war", "relação: guerra")
	assert_true(not controller.province_view(FIRST_BAV)["diplomacy"]["can_declare"], "não declara de novo")
	assert_true(not controller.declare_war("bav")["ok"], "duplicada recusada")
	assert_true(not controller.declare_war("fra")["ok"], "contra si mesmo recusada")
	assert_true(controller.move_army(army, FIRST_BAV)["ok"], "move para a Suábia")
	assert_true(controller.end_turn()["ok"], "encerra o turno")
	assert_true(controller.move_army(army, BAV_ARMY_PROVINCE)["ok"], "entra na Baviera")
	var actions: Array = controller.province_view(BAV_ARMY_PROVINCE)["encounter_actions"]
	assert_eq(actions.size(), 1, "a interface apresenta o encontro")
	assert_eq(actions[0]["start_reason"], "", "e permite iniciar a batalha")
	var started := controller.start_battle(actions[0]["encounter_id"])
	assert_true(started["ok"], started["message"])
	assert_eq(opened.size(), 1, "a cena tática foi aberta")
	assert_true(not controller.end_turn()["ok"], "turno bloqueado com a batalha ativa")
	assert_true(controller.cancel_battle(started["battle_id"])["ok"], "cancelar")
	assert_true(state.at_war("fra", "bav"), "a guerra continua depois da batalha cancelada")
	assert_eq(state.owner_of(BAV_ARMY_PROVINCE), "bav", "nenhuma conquista")


# --- Interface (cena principal montada) -----------------------------------------------------------------

func _campaign() -> Control:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func test_province_panel_shows_owner_relation_and_declares_war() -> void:
	var main := _campaign()
	var panel = main.screen.province_panel
	main.controller.select_province(BORDER)
	assert_true(panel.war_button == null and panel.relation_label == null, "província própria: sem diplomacia")
	main.controller.select_province(FIRST_BAV)
	assert_true("Controlada por Baviera" in panel.relation_label.text and "Em paz com Baviera" in panel.relation_label.text, panel.relation_label.text)
	assert_true(panel.war_button != null and not panel.war_button.disabled, "botão de declarar guerra")
	assert_true("Baviera" in panel.war_button.text, panel.war_button.text)
	panel.war_button.pressed.emit()
	assert_true(main.state.at_war("fra", "bav"), "o estado da campanha mudou")
	assert_true("Em guerra com Baviera" in panel.relation_label.text, "a interface atualizou sem reiniciar: " + panel.relation_label.text)
	assert_true(panel.war_button == null, "sem botão quando já há guerra")
	assert_true("declarou guerra" in main.screen.status_bar.message_label.text, main.screen.status_bar.message_label.text)
	# Abrir e fechar uma batalha de teste (troca de cena) não desfaz a guerra.
	main.open_test_battle()
	main.close_battle()
	assert_true(main.state.at_war("fra", "bav"), "a guerra sobrevive à troca de cena")
	main.free()


func test_full_manual_script_through_the_interface() -> void:
	var main := _campaign()
	var game := {"registry": main.registry, "state": main.state}
	var state = main.state
	var army := _fra_army(game)  # equivale ao recrutamento concluído em Estrasburgo
	main.controller.state_changed.emit()
	main.controller.select_province(BORDER)
	main.controller.select_army(army)
	var army_panel = main.screen.army_panel
	assert_true(army_panel.move_buttons[FIRST_BAV].disabled, "sem guerra: o destino estrangeiro está desabilitado")
	assert_true("Sem acesso" in army_panel.move_buttons[FIRST_BAV].tooltip_text, army_panel.move_buttons[FIRST_BAV].tooltip_text)
	main.controller.select_province(FIRST_BAV)
	main.screen.province_panel.war_button.pressed.emit()
	main.controller.select_province(BORDER)
	main.controller.select_army(army)
	assert_true(not army_panel.move_buttons[FIRST_BAV].disabled, "depois da guerra o destino fica habilitado")
	army_panel.move_buttons[FIRST_BAV].pressed.emit()
	assert_eq(state.armies[army]["province"], FIRST_BAV, "o exército entrou na Suábia")
	main.screen.top_bar.end_turn_button.pressed.emit()
	assert_eq(state.turn, 2, "turno 2")
	main.controller.select_army(army)
	army_panel.move_buttons[BAV_ARMY_PROVINCE].pressed.emit()
	assert_eq(state.encounters.size(), 1, "encontro real criado pela movimentação")
	main.controller.select_province(BAV_ARMY_PROVINCE)
	var start_button: Button = main.screen.province_panel.start_battle_buttons[state.encounters[0]["id"]]
	assert_true(not start_button.disabled, "Iniciar batalha disponível")
	start_button.pressed.emit()
	assert_true(main.battle_screen != null and main.current_battle_id == 1, "a cena tática abriu")
	var battle: BattleController = main.battle_screen.controller
	wipe_side(battle, "enemy")
	battle.end_turn()
	assert_eq(state.battles[1]["tactical_result"]["winner"], "player", "vitória registrada")
	main.battle_screen.result_panel.back_button.pressed.emit()
	assert_true(main.screen.visible and main.battle_screen == null, "de volta à campanha")
	assert_eq(state.battles[1]["status"], "applied", "resultado aplicado ao terminar a cena")
	assert_eq(state.armies_in(BAV_ARMY_PROVINCE, "bav"), [] as Array[int], "o Exército Bávaro foi destruído e removido")
	assert_eq(state.armies[army]["province"], BAV_ARMY_PROVINCE, "o vencedor permanece na província")
	assert_true(state.encounters.is_empty(), "encontro resolvido")
	assert_eq(state.owner_of(BAV_ARMY_PROVINCE), "bav", "sem conquista")
	assert_true(state.at_war("fra", "bav"), "guerra preservada")
	assert_eq(TurnProcessor.new().validate_state(main.registry, state), PackedStringArray(), "campanha consistente")
	main.free()
