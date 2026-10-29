extends "res://tests/test_case.gd"
## Fixture do executor de testes (NÃO roda na suíte normal: está fora de tests/ direto e não é descoberta).
## É executada só por tests/test_runner_detects_errors.gd, em um processo separado, via --only=.


func test_passes_normally() -> void:
	assert_true(true, "teste saudável")


func test_crashes_after_a_passing_assertion() -> void:
	assert_true(true, "uma asserção que passa antes do erro")
	var items: Array = []
	var boom: Variant = items[5]  # erro de execução: índice fora do limite
	assert_true(boom == null, "nunca chega aqui")
