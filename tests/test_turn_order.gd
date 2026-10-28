extends "res://tests/test_case.gd"
## Ordem e unicidade das etapas do turno, avanço do número do turno e proteções do processador.

const TurnProcessor := preload("res://src/campaign/turn_processor.gd")
const EVENT_BUS := preload("res://src/core/event_bus.gd")

const EXPECTED_ORDER: Array[StringName] = [
	&"validate_state",
	&"income_expenses",
	&"construction_progress",
	&"recruitment",
	&"ai_actions",
	&"military_movement",
	&"advance_turn",
	&"army_reset",
	&"events",
]


func test_phase_order_is_fixed() -> void:
	assert_eq(TurnProcessor.PHASES, EXPECTED_ORDER, "ordem das etapas do turno")


func test_end_turn_runs_each_phase_once_in_order() -> void:
	var game := new_game()
	var report: Dictionary = TurnProcessor.new().end_turn(game["registry"], game["state"])
	assert_true(report["ok"], "turno válido: %s" % str(report["errors"]))
	assert_eq(report["phases"], EXPECTED_ORDER, "registro de execução (cada etapa uma vez)")


func test_turn_number_advances_by_one_per_call() -> void:
	var game := new_game()
	var processor := TurnProcessor.new()
	assert_eq(game["state"].turn, 1, "turno inicial")
	var report: Dictionary = processor.end_turn(game["registry"], game["state"])
	assert_eq(game["state"].turn, 2, "após o primeiro encerramento")
	assert_eq(report["turn_before"], 1, "turn_before")
	assert_eq(report["turn_after"], 2, "turn_after")
	processor.end_turn(game["registry"], game["state"])
	processor.end_turn(game["registry"], game["state"])
	assert_eq(game["state"].turn, 4, "três encerramentos = três turnos")


func test_income_is_credited_exactly_once_per_call() -> void:
	var game := new_game()
	var state = game["state"]
	var before: int = state.resources_of("fra")["gold"]
	TurnProcessor.new().end_turn(game["registry"], state)
	assert_eq(state.resources_of("fra")["gold"], before + 22, "ouro: +22 de receita, uma única vez")


func test_events_and_signals_follow_phase_order() -> void:
	var game := new_game()
	var bus: Node = EVENT_BUS.new()
	var seen: Array[StringName] = []
	var ended: Array[int] = []
	bus.turn_phase_processed.connect(func(phase: StringName) -> void: seen.append(phase))
	bus.turn_ended.connect(func(new_turn: int) -> void: ended.append(new_turn))
	TurnProcessor.new().end_turn(game["registry"], game["state"], bus)
	bus.free()
	assert_eq(seen, EXPECTED_ORDER, "sinais emitidos na ordem")
	assert_eq(ended, [2] as Array[int], "turn_ended emitido uma vez com o novo turno")


func test_reentrant_end_turn_is_rejected() -> void:
	var game := new_game()
	var processor := TurnProcessor.new()
	var bus: Node = EVENT_BUS.new()
	var inner: Array[Dictionary] = []
	bus.turn_phase_processed.connect(func(phase: StringName) -> void:
		if phase == &"income_expenses":
			inner.append(processor.end_turn(game["registry"], game["state"])))
	var gold_before: int = game["state"].resources_of("fra")["gold"]
	var report: Dictionary = processor.end_turn(game["registry"], game["state"], bus)
	bus.free()
	assert_true(report["ok"], "chamada externa concluída")
	assert_eq(inner.size(), 1, "tentativa reentrante ocorreu")
	assert_true(not inner[0]["ok"], "chamada reentrante rejeitada")
	assert_eq(game["state"].turn, 2, "turno avançou uma única vez")
	assert_eq(game["state"].resources_of("fra")["gold"], gold_before + 22, "receita creditada uma única vez")


func test_invalid_state_aborts_without_changes() -> void:
	var game := new_game()
	var state = game["state"]
	state.countries["fra"]["resources"]["gold"] = -5
	var before: Dictionary = state.to_dict()
	var report: Dictionary = TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not report["ok"], "turno inválido")
	assert_eq(report["phases"], [&"validate_state"] as Array[StringName], "só a validação executou")
	assert_true(not report["errors"].is_empty(), "erros descritos")
	assert_eq(state.to_dict(), before, "estado intacto")


func test_unpaid_upkeep_never_makes_resources_negative() -> void:
	var game := new_game()
	var state = game["state"]
	for i in 200:  # manutenção: 800 de ouro e 1000 de alimentos, acima do saldo + receita
		state.units.append({"id": i + 1, "type": "unit_line_inf", "owner": "fra", "province": "prov_paris", "strength": 500})
	var report: Dictionary = TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(report["ok"], "turno processado")
	assert_eq(state.resources_of("fra")["gold"], 0, "ouro limitado a zero")
	assert_eq(state.resources_of("fra")["food"], 0, "alimentos limitados a zero")
	assert_eq(report["shortfall"]["fra"]["gold"], 800 - 522, "déficit de ouro registrado")
	for res in state.resources_of("fra"):
		assert_true(state.resources_of("fra")[res] >= 0, "%s não negativo" % res)
