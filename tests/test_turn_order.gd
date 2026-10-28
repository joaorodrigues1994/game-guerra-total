extends "res://tests/test_case.gd"

const TurnProcessor := preload("res://src/campaign/turn_processor.gd")
const GameState := preload("res://src/core/game_state.gd")
const EVENT_BUS := preload("res://src/core/event_bus.gd")

const EXPECTED_ORDER: Array[StringName] = [
	&"income_expenses",
	&"construction_progress",
	&"recruitment",
	&"supply_upkeep",
	&"ai_actions",
	&"military_movement",
	&"events",
]


func test_phase_order_is_fixed() -> void:
	assert_eq(TurnProcessor.PHASES, EXPECTED_ORDER, "ordem das etapas do turno")


func test_end_turn_runs_phases_in_order() -> void:
	var processor := TurnProcessor.new()
	var log := processor.end_turn(GameState.new())
	assert_eq(log, EXPECTED_ORDER, "registro de execução")


func test_end_turn_does_not_change_state() -> void:
	var state := GameState.new()
	var before := state.to_dict()
	TurnProcessor.new().end_turn(state)
	assert_eq(state.to_dict(), before, "esqueleto não altera o estado")


func test_end_turn_emits_events_in_order() -> void:
	var bus: Node = EVENT_BUS.new()
	var seen: Array[StringName] = []
	bus.turn_phase_processed.connect(func(phase: StringName) -> void: seen.append(phase))
	TurnProcessor.new().end_turn(GameState.new(), bus)
	bus.free()
	assert_eq(seen, EXPECTED_ORDER, "sinais emitidos")
