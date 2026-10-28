extends "res://tests/test_case.gd"
## Estado inicial, seleção de províncias e dados exibidos.

const ProvinceMap := preload("res://src/provinces/province_map.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")

var _selection_events: Array[String] = []


func _controller() -> CampaignController:
	var reg := Registry.new()
	assert_true(reg.load_from_dir("res://data"), str(reg.errors))
	var state := GameState.new()
	assert_true(state.setup_from_registry(reg, "fra"), "estado inicial")
	var pmap := ProvinceMap.new()
	pmap.build(reg)
	var controller := CampaignController.new()
	controller.setup(reg, state, pmap)
	controller.selection_changed.connect(func(id: String) -> void: _selection_events.append(id))
	return controller


func test_game_state_copies_only_mutable_data() -> void:
	var c := _controller()
	assert_eq(c.state.owner_of("prov_paris"), "fra", "dono inicial")
	assert_eq(c.state.provinces["prov_paris"]["garrison"], 2000, "guarnição inicial")
	assert_eq(c.state.countries["fra"]["resources"]["gold"], 500.0, "ouro inicial")
	c.state.provinces["prov_paris"]["buildings"].append("farm")
	assert_eq(c.registry.provinces["prov_paris"]["buildings"], ["market", "barracks"], "registro não é alterado pelo estado")


func test_game_state_rejects_unknown_player_country() -> void:
	var c := _controller()
	assert_true(not GameState.new().setup_from_registry(c.registry, "xxx"), "país inexistente")


func test_hit_test_resolves_each_province_at_its_label() -> void:
	var c := _controller()
	for id in c.province_map.ids:
		assert_eq(c.province_map.province_at(c.province_map.label_points[id]), id, "ponto central de %s" % id)


func test_hit_test_is_precise_near_a_shared_border() -> void:
	var c := _controller()
	# A fronteira Paris/Francônia é a aresta (262,30)-(252,292): x ≈ 257 em y = 161.
	assert_eq(c.province_map.province_at(Vector2(250, 161)), "prov_paris", "lado esquerdo")
	assert_eq(c.province_map.province_at(Vector2(264, 161)), "prov_franconia", "lado direito")


func test_hit_test_outside_provinces_is_empty() -> void:
	var c := _controller()
	assert_eq(c.province_map.province_at(Vector2(-10, -10)), "", "fora do mapa")
	assert_eq(c.province_map.province_at(Vector2(5, 20)), "", "canto sem província")


func test_select_at_selects_and_emits_once() -> void:
	var c := _controller()
	_selection_events.clear()
	assert_eq(c.select_at(c.province_map.label_points["prov_vienna"]), "prov_vienna", "id retornado")
	assert_eq(c.selected_province_id, "prov_vienna", "seleção")
	c.select_at(c.province_map.label_points["prov_vienna"])
	assert_eq(_selection_events, ["prov_vienna"] as Array[String], "sem evento repetido")


func test_select_other_province_replaces_selection() -> void:
	var c := _controller()
	c.select_province("prov_paris")
	c.select_province("prov_bohemia")
	assert_eq(c.selected_province_id, "prov_bohemia", "nova seleção")


func test_select_at_empty_area_clears_selection() -> void:
	var c := _controller()
	c.select_province("prov_paris")
	c.select_at(Vector2(-50, -50))
	assert_eq(c.selected_province_id, "", "seleção limpa")


func test_clear_selection() -> void:
	var c := _controller()
	c.select_province("prov_paris")
	_selection_events.clear()
	c.clear_selection()
	assert_eq(c.selected_province_id, "", "limpa")
	assert_eq(_selection_events, [""] as Array[String], "evento de limpeza")
	c.clear_selection()
	assert_eq(_selection_events.size(), 1, "limpar de novo não emite")


func test_select_unknown_province_is_rejected() -> void:
	var c := _controller()
	assert_true(not c.select_province("prov_atlantida"), "id desconhecido")
	assert_eq(c.selected_province_id, "", "seleção inalterada")


func test_province_view_shows_registry_and_state_data() -> void:
	var c := _controller()
	var v := c.province_view("prov_paris")
	assert_eq(v["name"], "Île-de-France", "nome")
	assert_eq(v["owner_name"], "França", "país controlador")
	assert_eq(v["capital_of"], "França", "capital")
	assert_eq(v["terrain_name"], "Planície", "terreno")
	assert_eq(v["population"], 60000, "população")
	assert_eq(v["buildings"], ["Mercado", "Quartel"] as Array[String], "construções")
	assert_eq(v["neighbors"].size(), 2, "conexões")
	assert_eq(v["neighbors"][0]["link"], "Estrada", "tipo de conexão")


func test_province_view_follows_state_changes() -> void:
	var c := _controller()
	c.state.provinces["prov_paris"]["owner"] = "aus"
	c.state.provinces["prov_paris"]["garrison"] = 42
	var v := c.province_view("prov_paris")
	assert_eq(v["owner_name"], "Áustria", "dono vem do estado")
	assert_eq(v["garrison"], 42, "guarnição vem do estado")


func test_non_capital_province_has_no_capital_flag() -> void:
	assert_eq(_controller().province_view("prov_strasbourg")["capital_of"], "", "sem capital")


func test_unknown_province_view_is_empty() -> void:
	assert_true(_controller().province_view("nada").is_empty(), "visão vazia")


func test_focus_country_follows_selection() -> void:
	var c := _controller()
	assert_eq(c.focus_country_id(), "fra", "sem seleção: jogador")
	c.select_province("prov_vienna")
	assert_eq(c.focus_country_id(), "aus", "seleção: dono da província")
	c.clear_selection()
	assert_eq(c.focus_country_id(), "fra", "limpa: jogador")


func test_country_view_and_date() -> void:
	var c := _controller()
	var v := c.country_view("fra")
	assert_eq(v["name"], "França", "nome")
	assert_true(v["is_player"], "jogador")
	assert_eq(v["resources"][0]["name"], "Ouro", "nome do recurso")
	assert_eq(v["resources"][0]["amount"], 500, "ouro")
	assert_eq(v["resources"][0]["income"], 22, "receita de ouro por turno")
	assert_eq(v["resources"][0]["upkeep"], 0, "sem despesas")
	assert_eq(v["resources"][0]["net"], 22, "saldo")
	assert_eq(c.date_text(), "Janeiro de 1805 · Turno 1", "data")
	c.state.turn = 14
	assert_eq(c.date_text(), "Fevereiro de 1806 · Turno 14", "virada de ano")


# --- Ações, turnos e eventos ------------------------------------------------

var _messages: Array[Dictionary] = []
var _state_changes: int = 0
var _turn_reports: Array[Dictionary] = []


func _watched_controller() -> CampaignController:
	var c := _controller()
	_messages.clear()
	_state_changes = 0
	_turn_reports.clear()
	c.message_posted.connect(func(text: String, is_error: bool) -> void: _messages.append({"text": text, "error": is_error}))
	c.state_changed.connect(func() -> void: _state_changes += 1)
	c.turn_ended.connect(func(report: Dictionary) -> void: _turn_reports.append(report))
	return c


func test_build_through_controller_emits_events_and_updates_view() -> void:
	var c := _watched_controller()
	var result := c.build("prov_strasbourg", "farm")
	assert_true(result["ok"], result["message"])
	assert_eq(_state_changes, 1, "state_changed emitido")
	assert_true(not _messages[0]["error"] and "Construção iniciada" in _messages[0]["text"], "mensagem de sucesso")
	var v := c.province_view("prov_strasbourg")
	assert_eq(v["constructions"], [{"name": "Fazenda", "remaining": 2}] as Array[Dictionary], "em andamento na visão")


func test_rejected_action_posts_error_and_does_not_signal_state_change() -> void:
	var c := _watched_controller()
	var result := c.build("prov_vienna", "farm")  # província da Áustria
	assert_true(not result["ok"], "rejeitada")
	assert_eq(_state_changes, 0, "sem state_changed")
	assert_true(_messages[0]["error"] and "não controla" in _messages[0]["text"], "mensagem de erro")


func test_recruit_through_controller() -> void:
	var c := _watched_controller()
	assert_true(c.recruit("prov_paris", "unit_line_inf")["ok"], "recrutar")
	assert_eq(c.province_view("prov_paris")["recruitments"], [{"name": "Infantaria de linha", "remaining": 2}] as Array[Dictionary], "visão")
	assert_eq(c.state.resources_of("fra")["manpower"], 500, "custo descontado no estado")


func test_end_turn_through_controller_updates_state_and_reports() -> void:
	var c := _watched_controller()
	c.build("prov_strasbourg", "farm")
	_messages.clear()
	_state_changes = 0
	var report := c.end_turn()
	assert_true(report["ok"], "turno processado")
	assert_eq(c.state.turn, 2, "turno avançou")
	assert_eq(_state_changes, 1, "state_changed uma vez")
	assert_eq(_turn_reports.size(), 1, "turn_ended uma vez")
	assert_true("Turno 1 encerrado" in _messages[0]["text"] and "Ouro +22" in _messages[0]["text"], _messages[0]["text"])
	assert_eq(c.date_text(), "Fevereiro de 1805 · Turno 2", "data")


func test_end_turn_report_mentions_completions() -> void:
	var c := _watched_controller()
	c.build("prov_strasbourg", "farm")
	c.recruit("prov_paris", "unit_line_inf")
	c.end_turn()
	c.end_turn()
	assert_true("Construção concluída: Fazenda em Alsácia" in _messages[-1]["text"], _messages[-1]["text"])
	assert_true("Unidade pronta: Infantaria de linha em Île-de-France" in _messages[-1]["text"], _messages[-1]["text"])
	assert_eq(c.province_view("prov_paris")["units"], ["Infantaria de linha × 1 (500 homens)"] as Array[String], "unidades na visão")


func test_options_show_reasons_for_unavailable_actions() -> void:
	var c := _controller()
	var options := c.build_options("prov_strasbourg")
	var ids := []
	for option in options:
		ids.append(option["id"])
	assert_true(not ("arsenal" in ids), "Arsenal (não construível) não é oferecido")
	assert_true(not ("market" in c.build_options("prov_paris").map(func(o): return o["id"])), "construída não é oferecida")
	for option in options:
		assert_true(option["available"], "%s disponível" % option["id"])
	c.state.countries["fra"]["resources"]["gold"] = 120
	for option in c.build_options("prov_strasbourg"):
		if option["id"] == "farm":
			assert_true(option["available"], "Fazenda cabe no orçamento")
		else:
			assert_true(not option["available"] and "Recursos insuficientes" in option["reason"], "%s sem fundos" % option["id"])
	var recruit := c.recruit_options("prov_strasbourg")
	assert_eq(recruit.size(), 1, "só infantaria de linha é recrutável")
	assert_true("Requer: Quartel" in recruit[0]["reason"], recruit[0]["reason"])


func test_foreign_province_has_no_action_options() -> void:
	var v := _controller().province_view("prov_vienna")
	assert_true(not v["owned_by_player"], "não é do jogador")
	assert_true(v["build_options"].is_empty() and v["recruit_options"].is_empty(), "sem opções")
