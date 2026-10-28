extends RefCounted
## Base mínima para testes headless: métodos test_* são descobertos pelo executor.

var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0


func assert_true(condition: bool, message: String = "") -> void:
	assertions += 1
	if not condition:
		failures.append(message if message != "" else "assert_true falhou")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (esperado: %s, obtido: %s)" % [message, str(expected), str(actual)])


func assert_has_error(errors: PackedStringArray, fragment: String, message: String = "") -> void:
	assertions += 1
	for e in errors:
		if fragment in e:
			return
	failures.append("%s (nenhum erro contém '%s'; erros: %s)" % [message, fragment, str(errors)])
