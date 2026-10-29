extends "res://tests/test_case.gd"
## Garante que o executor de testes NÃO reporta como sucesso um teste que quebra em tempo de execução.
## Roda o próprio executor em um processo separado, apontado para tests/fixtures/runtime_error_fixture.gd
## (um teste saudável e um que faz uma asserção e depois acessa um índice inexistente).


func test_runtime_error_in_a_test_is_reported_as_failure_with_nonzero_exit() -> void:
	var output: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/run_tests.gd",
		"--", "--only=fixtures/runtime_error_fixture.gd"]
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(PackedStringArray(output))
	assert_eq(code, 1, "código de saída 1 (falha), não 0. Saída:\n%s" % text)
	# (sem acentos na busca: a codificação do console do processo filho pode variar no Windows)
	assert_true("FALHA  fixtures/runtime_error_fixture.gd::test_crashes_after_a_passing_assertion: erro de execu" in text,
		"o teste que quebrou é reportado como FALHA por erro de execução. Saída:
%s" % text)
	assert_true("ok     fixtures/runtime_error_fixture.gd::test_passes_normally" in text, "o teste saudável continua 'ok'")
	assert_true("2 testes" in text and "1 falhas" in text, "contagem: 2 testes, 1 falha")
	assert_true(not ("ok     fixtures/runtime_error_fixture.gd::test_crashes" in text), "o teste quebrado nunca aparece como ok")
