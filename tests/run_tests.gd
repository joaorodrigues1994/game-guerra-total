extends SceneTree
## Executor de testes headless.
## Uso: godot --headless --path . --script res://tests/run_tests.gd
##      (opcional, após "--": --only=<arquivo em tests/> para rodar um único arquivo)
## Código de saída 0 = todos passaram; 1 = falhas (ou nenhum teste executado); 2 = tempo esgotado.
## Um erro de EXECUÇÃO dentro de um teste (índice fora do limite, chamada em null, assert...) não é
## capturável em GDScript; por isso um Logger registra os erros da engine e o executor conta o teste
## como FALHA. Sem isso, um teste que fizesse uma asserção e depois quebrasse constaria como "ok".

## Tempo máximo da execução inteira (a suíte leva ~2 min). Evita processo pendurado sem resposta.
const WATCHDOG_SECONDS := 900.0


## Registra erros da engine (SCRIPT ERROR, push_error, falhas de assert) ocorridos durante um teste.
class ErrorCatcher extends Logger:
	var messages: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		messages.append("%s (%s:%d)" % [rationale if not rationale.is_empty() else code, file, line])


func _init() -> void:
	# O laço principal e a árvore de cena só existem depois de _init; os testes de UI precisam deles.
	process_frame.connect(_run, CONNECT_ONE_SHOT)
	create_timer(WATCHDOG_SECONDS).timeout.connect(func() -> void:
		print("FALHA  tempo esgotado: a execução passou de %d s (teste pendurado?)" % int(WATCHDOG_SECONDS))
		quit(2))


func _run() -> void:
	var total := 0
	var failed := 0
	var assertions := 0
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)

	for file in _test_files():
		catcher.messages.clear()
		var script: Script = load("res://tests/%s" % file)
		# Um arquivo com erro de sintaxe carrega como Script não instanciável: sem esta checagem o
		# executor falhava no meio e o processo ficava pendurado em vez de terminar.
		if script == null or not script.can_instantiate():
			print("FALHA  %s: não foi possível carregar o script (erro de sintaxe?)" % file)
			failed += 1
			continue
		var probe: RefCounted = script.new()
		if not catcher.messages.is_empty():
			failed += 1
			print("FALHA  %s: erro de execução ao carregar o arquivo: %s" % [file, catcher.messages[0]])
			continue
		for method in probe.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var case: RefCounted = script.new()  # instância nova por teste
			catcher.messages.clear()
			await case.call(name)  # testes podem aguardar frames (ex.: layout de UI)
			total += 1
			assertions += case.assertions
			if not catcher.messages.is_empty():
				failed += 1
				for message in catcher.messages:
					print("FALHA  %s::%s: erro de execução: %s" % [file, name, message])
			elif case.assertions == 0:
				failed += 1
				print("FALHA  %s::%s: nenhuma asserção executada (teste abortado?)" % [file, name])
			elif case.failures.is_empty():
				print("ok     %s::%s" % [file, name])
			else:
				failed += 1
				for message in case.failures:
					print("FALHA  %s::%s: %s" % [file, name, message])

	OS.remove_logger(catcher)
	print("")
	print("%d testes, %d asserções, %d falhas" % [total, assertions, failed])
	if total == 0:
		print("Nenhum teste executado: tratado como falha.")
		failed += 1
	quit(1 if failed > 0 else 0)


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			files.append(arg.trim_prefix("--only="))
			return files
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	return files
