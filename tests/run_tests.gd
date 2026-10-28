extends SceneTree
## Executor de testes headless.
## Uso: godot --headless --path . --script res://tests/run_tests.gd
## Código de saída 0 = todos passaram; 1 = falhas (ou nenhum teste executado).


func _init() -> void:
	# O laço principal e a árvore de cena só existem depois de _init; os testes de UI precisam deles.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var total := 0
	var failed := 0
	var assertions := 0

	for file in _test_files():
		var script: Script = load("res://tests/%s" % file)
		if script == null:
			print("FALHA  %s: não foi possível carregar o script" % file)
			failed += 1
			continue
		var probe: RefCounted = script.new()
		for method in probe.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var case: RefCounted = script.new()  # instância nova por teste
			await case.call(name)  # testes podem aguardar frames (ex.: layout de UI)
			total += 1
			assertions += case.assertions
			if case.assertions == 0:
				failed += 1
				print("FALHA  %s::%s: nenhuma asserção executada (teste abortado?)" % [file, name])
			elif case.failures.is_empty():
				print("ok     %s::%s" % [file, name])
			else:
				failed += 1
				for message in case.failures:
					print("FALHA  %s::%s: %s" % [file, name, message])

	print("")
	print("%d testes, %d asserções, %d falhas" % [total, assertions, failed])
	if total == 0:
		print("Nenhum teste executado: tratado como falha.")
		failed += 1
	quit(1 if failed > 0 else 0)


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	return files
