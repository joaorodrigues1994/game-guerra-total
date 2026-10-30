extends "res://tests/integration_case.gd"
## Resolução estratégica (Etapa 6): o resultado tático é APLICADO à campanha uma única vez, de forma atômica.
## Cenário padrão: batalha em Suábia (Baviera) entre a França (atacante, vinda de Estrasburgo) e um exército bávaro.
## Os desfechos táticos são fixados por source_id (set_outcome) e a cena termina pelo motor (end_turn), então o
## resumo (result_summary) é o que a batalha realmente produz.

const Flow := preload("res://src/integration/battle_flow.gd")
const Resolution := preload("res://src/integration/battle_resolution.gd")
const Lifecycle := preload("res://src/integration/battle_lifecycle.gd")
const TurnProcessor := preload("res://src/campaign/turn_processor.gd")
const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const ProvinceMap := preload("res://src/provinces/province_map.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STRASBOURG := "prov_strasbourg"  # França
const SWABIA := "prov_swabia"  # Baviera; vizinha de Estrasburgo, Francônia e Baviera
const FRANCONIA := "prov_franconia"  # Baviera; vizinha de Paris
const BAVARIA := "prov_bavaria"  # Baviera; vizinha de Suábia e de províncias austríacas
const PARIS := "prov_paris"  # França

const FRA_TYPES: Array = ["unit_line_inf", "unit_line_inf", "unit_light_cav"]
const BAV_TYPES: Array = ["unit_line_inf", "unit_line_inf"]


# --- Fixtures -------------------------------------------------------------------------------------------

## Batalha registrada e iniciada. `from_province` -> `province` (a França ataca). create_enemy = false reaproveita o
## exército que já está na província (ex.: o Exército Bávaro em Baviera).
func _fight_in(game: Dictionary, province: String = SWABIA, from_province: String = STRASBOURG, enemy: String = "bav",
		fra_types: Array = FRA_TYPES, enemy_types: Array = BAV_TYPES, create_enemy: bool = true) -> Dictionary:
	var state = game["state"]
	var registry = game["registry"]
	if not state.at_war("fra", enemy):
		declare_war_between(game, "fra", enemy)
	var enemy_army: int = army_in(game, enemy, enemy_types, province) if create_enemy else state.armies_in(province, enemy)[0]
	var fra_army: int = army_in(game, "fra", fra_types, from_province)
	var moved := ArmyActions.move_army(registry, state, "fra", fra_army, province)
	assert_true(moved["ok"], moved["message"])
	var encounter_id := 0
	for encounter in state.encounters:
		if encounter["province"] == province:
			encounter_id = encounter["id"]
	var started := Flow.start(registry, state, Flow.load_context(), encounter_id)
	assert_true(started["ok"], started["message"])
	return {"game": game, "registry": registry, "state": state, "fra_army": fra_army, "enemy_army": enemy_army,
		"battle_id": started["battle_id"], "battle": started["controller"], "encounter_id": encounter_id, "province": province}


func _fight(province: String = SWABIA, from_province: String = STRASBOURG, enemy: String = "bav",
		fra_types: Array = FRA_TYPES, enemy_types: Array = BAV_TYPES, create_enemy: bool = true) -> Dictionary:
	return _fight_in(new_game(), province, from_province, enemy, fra_types, enemy_types, create_enemy)


func _units(s: Dictionary, army_id: int) -> Array:
	return s["state"].armies[army_id]["units"].duplicate()


## Termina a cena pelo motor (end_turn do jogador) e aplica o resultado como o fluxo da campanha faz.
func _conclude(s: Dictionary) -> Dictionary:
	var battle: BattleController = s["battle"]
	battle.end_turn()
	assert_true(battle.state.over, "a cena tática terminou")
	return Flow.finish(s["registry"], s["state"], s["battle_id"], battle.state.result_summary())


## Vitória da França: a França mantém as três unidades (feridas) e o inimigo perde uma e vê a outra fugir.
func _french_victory(s: Dictionary) -> Array:
	var f: Array = _units(s, s["fra_army"])
	var b: Array = _units(s, s["enemy_army"])
	set_outcome(s["battle"], f[0], 410, 62)
	set_outcome(s["battle"], f[1], 300, 55)
	set_outcome(s["battle"], f[2], 150, 80)
	set_outcome(s["battle"], b[0], 0, 0, "destroyed")
	set_outcome(s["battle"], b[1], 90, 15, "fled")
	return [f, b]


## Derrota da França com sobreviventes: uma unidade destruída, uma que foge e a cavalaria destruída.
func _french_defeat(s: Dictionary) -> Array:
	var f: Array = _units(s, s["fra_army"])
	var b: Array = _units(s, s["enemy_army"])
	set_outcome(s["battle"], f[0], 0, 0, "destroyed")
	set_outcome(s["battle"], f[1], 120, 18, "fled")
	set_outcome(s["battle"], f[2], 0, 0, "destroyed")
	set_outcome(s["battle"], b[0], 300, 70)
	set_outcome(s["battle"], b[1], 250, 63)
	return [f, b]


func _valid(s: Dictionary) -> void:
	assert_eq(TurnProcessor.new().validate_state(s["registry"], s["state"]), PackedStringArray(), "validate_state aprova o estado")


# --- Vitória e derrota -----------------------------------------------------------------------------------

func test_victory_updates_strength_and_morale_of_both_sides_and_the_winner_stays() -> void:
	var s := _fight()
	var state = s["state"]
	var ids := _french_victory(s)
	var f: Array = ids[0]
	var b: Array = ids[1]
	var result := _conclude(s)
	assert_true(result["ok"] and result["applied"], result["message"])
	assert_eq([state.unit_by_id(f[0])["strength"], state.unit_by_id(f[0])["morale"]], [410, 62], "efetivo e moral da 1ª unidade francesa")
	assert_eq([state.unit_by_id(f[1])["strength"], state.unit_by_id(f[1])["morale"]], [300, 55], "da 2ª")
	assert_eq([state.unit_by_id(f[2])["strength"], state.unit_by_id(f[2])["morale"]], [150, 80], "da cavalaria")
	assert_true(state.unit_by_id(b[0]).is_empty(), "a unidade destruída saiu da campanha")
	assert_eq(state.armies[s["enemy_army"]]["units"], [b[1]], "o exército inimigo ficou só com a que fugiu")
	assert_eq([state.unit_by_id(b[1])["strength"], state.unit_by_id(b[1])["morale"]], [90, 15], "que fugiu: efetivo e moral finais")
	assert_eq(state.armies[s["fra_army"]]["province"], SWABIA, "o vencedor permanece na província do combate")
	assert_eq(state.armies[s["fra_army"]]["units"], f, "e mantém as três unidades")
	assert_eq(state.armies[s["enemy_army"]]["province"], BAVARIA, "o derrotado recuou (empate de distância: id menor, prov_bavaria < prov_franconia)")
	assert_true(state.armies[s["enemy_army"]]["moved"], "e gastou o movimento do turno")
	assert_eq(state.owner_of(SWABIA), "bav", "sem conquista da província")
	_valid(s)


func test_defeat_with_survivors_retreats_to_a_valid_allied_province() -> void:
	var s := _fight()
	var state = s["state"]
	var ids := _french_defeat(s)
	var f: Array = ids[0]
	var result := _conclude(s)
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[s["fra_army"]]["units"], [f[1]], "só a unidade que fugiu sobrevive")
	assert_eq([state.unit_by_id(f[1])["strength"], state.unit_by_id(f[1])["morale"]], [120, 18], "com o efetivo e a moral finais")
	assert_true(state.unit_by_id(f[0]).is_empty() and state.unit_by_id(f[2]).is_empty(), "as destruídas saíram da campanha")
	assert_eq(state.armies[s["fra_army"]]["province"], STRASBOURG, "recuou para a única província francesa vizinha")
	assert_eq(state.owner_of(state.armies[s["fra_army"]]["province"]), "fra", "província aliada (própria)")
	assert_eq(state.armies[s["enemy_army"]]["province"], SWABIA, "o vencedor permanece")
	assert_true(state.encounters.is_empty(), "encontro resolvido: só resta um país na província")
	var report: Dictionary = state.battles[s["battle_id"]]["result"]
	assert_eq(report["armies"][s["fra_army"]]["outcome"], "retreats", "relatório: recuou")
	assert_eq(report["armies"][s["fra_army"]]["path"], [STRASBOURG], "pelo caminho")
	_valid(s)


func test_defeat_with_no_survivors_removes_the_army_and_its_units() -> void:
	var s := _fight()
	var state = s["state"]
	var f: Array = _units(s, s["fra_army"])
	for unit_id in f:
		set_outcome(s["battle"], unit_id, 0, 0, "destroyed")
	for unit_id in _units(s, s["enemy_army"]):
		set_outcome(s["battle"], unit_id, 200, 66)
	var units_before: int = state.units.size()
	var result := _conclude(s)
	assert_true(result["ok"], result["message"])
	assert_true(not state.armies.has(s["fra_army"]), "o exército sem sobreviventes foi removido da campanha")
	for unit_id in f:
		assert_true(state.unit_by_id(unit_id).is_empty(), "unidade %d removida" % unit_id)
	assert_eq(state.units.size(), units_before - f.size(), "só as unidades dele saíram")
	assert_true(state.armies.has(s["enemy_army"]) and state.armies[s["enemy_army"]]["province"] == SWABIA, "o vencedor segue lá")
	assert_true(state.encounters.is_empty(), "sem referências a um exército que não existe")
	_valid(s)


func test_one_unit_reduced_to_zero_and_a_fully_destroyed_second_army() -> void:
	var game := new_game()
	declare_war_between(game, "fra", "bav")
	var state = game["state"]
	army_in(game, "bav", BAV_TYPES, SWABIA)
	var main_army := army_in(game, "fra", ["unit_line_inf", "unit_line_inf"], STRASBOURG)
	var second := army_in(game, "fra", ["unit_light_cav"], STRASBOURG)
	ArmyActions.move_army(game["registry"], state, "fra", main_army, SWABIA)
	ArmyActions.move_army(game["registry"], state, "fra", second, SWABIA)
	var started := Flow.start(game["registry"], state, Flow.load_context(), state.encounters[0]["id"])
	assert_true(started["ok"], started["message"])
	var s := {"game": game, "registry": game["registry"], "state": state, "battle": started["controller"], "battle_id": started["battle_id"]}
	var main_units: Array = _units({"state": state}, main_army)
	var cav: int = state.armies[second]["units"][0]
	set_outcome(s["battle"], main_units[0], 0, 0, "destroyed")  # uma unidade zerada, o exército continua
	set_outcome(s["battle"], main_units[1], 333, 44)
	set_outcome(s["battle"], cav, 0, 0, "destroyed")  # o segundo exército perde tudo, mesmo do lado vencedor
	for unit_id in state.battles[s["battle_id"]]["units"]:
		if state.battles[s["battle_id"]]["units"][unit_id]["owner"] == "bav":
			set_outcome(s["battle"], unit_id, 0, 0, "destroyed")
	var result := _conclude(s)
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[main_army]["units"], [main_units[1]], "o exército com outras unidades continua, sem a zerada")
	assert_eq(state.unit_by_id(main_units[1])["strength"], 333, "com o efetivo final")
	assert_true(not state.armies.has(second), "o exército cujas unidades foram todas eliminadas foi removido")
	assert_true(state.unit_by_id(cav).is_empty(), "e sua unidade também")
	assert_eq(state.armies[main_army]["province"], SWABIA, "o vencedor permanece")
	_valid(s)


# --- Mapeamento, conversão e preservação ----------------------------------------------------------------------

func test_units_are_mapped_by_source_id_even_with_shuffled_arrays_and_tactical_ids() -> void:
	var s := _fight()
	var state = s["state"]
	var ids := _french_victory(s)
	var f: Array = ids[0]
	var battle: BattleController = s["battle"]
	battle.end_turn()
	var summary: Dictionary = battle.state.result_summary()
	for side in summary["units"]:
		summary["units"][side].reverse()  # ordem diferente da implantação
		for entry in summary["units"][side]:
			entry["unit_id"] = int(entry["unit_id"]) + 1000  # ids táticos que nada têm a ver com os da campanha
			entry["name"] = "nome trocado"
	var result := Flow.finish(s["registry"], state, s["battle_id"], summary)
	assert_true(result["ok"], result["message"])
	assert_eq([state.unit_by_id(f[0])["strength"], state.unit_by_id(f[1])["strength"], state.unit_by_id(f[2])["strength"]], [410, 300, 150], "cada efetivo na unidade certa")
	assert_eq([state.unit_by_id(f[0])["morale"], state.unit_by_id(f[1])["morale"], state.unit_by_id(f[2])["morale"]], [62, 55, 80], "e cada moral")


func test_conversion_rules_for_strength_and_morale() -> void:
	var s := _fight()
	var state = s["state"]
	var f: Array = _units(s, s["fra_army"])
	var b: Array = _units(s, s["enemy_army"])
	var initial: int = state.unit_by_id(f[0])["strength"]
	set_outcome(s["battle"], f[0], initial, 100)  # intacta, moral no máximo tático
	set_outcome(s["battle"], f[1], 1, 0, "fled")  # 1 homem, moral 0 -> piso 1 para sobreviventes
	set_outcome(s["battle"], f[2], 77, 37)
	set_outcome(s["battle"], b[0], 0, 0, "destroyed")
	set_outcome(s["battle"], b[1], 0, 0, "destroyed")
	assert_true(_conclude(s)["ok"], "aplicada")
	assert_eq([state.unit_by_id(f[0])["strength"], state.unit_by_id(f[0])["morale"]], [initial, 100], "sem perda: efetivo igual e moral 100 (sem reescala)")
	assert_eq([state.unit_by_id(f[1])["strength"], state.unit_by_id(f[1])["morale"]], [1, 1], "moral 0 vira 1: o adaptador recusaria 0 numa batalha futura")
	assert_eq([state.unit_by_id(f[2])["strength"], state.unit_by_id(f[2])["morale"]], [77, 37], "valores intermediários copiados")
	var report: Dictionary = state.battles[s["battle_id"]]["result"]
	assert_eq(report["units"][f[1]]["morale_before"], 70, "o relatório guarda o antes")
	assert_eq(report["units"][f[1]]["morale_after"], 1, "e o depois")
	for unit_id in [f[0], f[1], f[2]]:
		assert_true(state.unit_by_id(unit_id)["strength"] <= report["units"][unit_id]["strength_before"], "efetivo nunca aumenta")


func test_non_participants_provinces_and_countries_are_untouched() -> void:
	var game := new_game()
	var state = game["state"]
	var reserve := army_in(game, "fra", ["unit_line_inf"], PARIS)
	var reserve_unit: int = state.armies[reserve]["units"][0]
	state.unit_by_id(reserve_unit)["strength"] = 200
	var s := _fight_in(game)
	var untouched := {}
	for army_id in state.armies:
		if not (army_id in [s["fra_army"], s["enemy_army"]]):
			untouched[army_id] = state.armies[army_id].duplicate(true)
	assert_true(untouched.size() >= 4, "há exércitos de outros países e a reserva (Boêmia, Viena, Baviera, Paris)")
	var other_units := {}
	for unit in state.units:
		if state.army_of_unit(unit["id"]) in untouched:
			other_units[unit["id"]] = unit.duplicate(true)
	var around: Dictionary = {"provinces": state.provinces.duplicate(true), "countries": state.countries.duplicate(true),
		"generals": state.generals.duplicate(true), "wars": state.wars.duplicate(true), "turn": state.turn}
	_french_victory(s)
	assert_true(_conclude(s)["ok"], "aplicada")
	for army_id in untouched:
		assert_eq(state.armies[army_id], untouched[army_id], "exército %d (não participante) intacto" % army_id)
	for unit_id in other_units:
		assert_eq(state.unit_by_id(unit_id), other_units[unit_id], "unidade %d (não participante) intacta" % unit_id)
	assert_eq({"provinces": state.provinces, "countries": state.countries, "generals": state.generals, "wars": state.wars, "turn": state.turn},
		around, "províncias, países, generais, guerras e turno intactos")


# --- Rejeições e atomicidade -----------------------------------------------------------------------------------

func test_missing_result_is_rejected_without_changes() -> void:
	var s := _fight()
	var before: Dictionary = s["state"].to_dict()
	var result := Resolution.apply(s["registry"], s["state"], s["battle_id"])
	assert_true(not result["ok"], "sem resultado tático")
	assert_has_error(result["errors"], "ainda não tem resultado tático", "motivo claro")
	assert_eq(s["state"].to_dict(), before, "nada mudou")
	assert_true(not Resolution.apply(s["registry"], s["state"], 99)["ok"], "batalha inexistente")


func test_invalid_results_are_rejected_without_any_partial_change() -> void:
	var cases := {
		"source_id desconhecido": func(summary: Dictionary) -> void: summary["units"]["player"][0]["source_id"] = 9999,
		"unidade ausente": func(summary: Dictionary) -> void: summary["units"]["player"].remove_at(0),
		"unidade duplicada": func(summary: Dictionary) -> void: summary["units"]["player"].append(summary["units"]["player"][0].duplicate()),
		"lado trocado": func(summary: Dictionary) -> void: summary["units"]["enemy"].append(summary["units"]["player"].pop_front()),
		"efetivo acima do inicial": func(summary: Dictionary) -> void: summary["units"]["player"][0]["strength"] = 99999,
		"efetivo negativo": func(summary: Dictionary) -> void: summary["units"]["player"][0]["strength"] = -3,
		"destruída com efetivo": func(summary: Dictionary) -> void: summary["units"]["enemy"][0]["strength"] = 5,
		"viva sem efetivo": func(summary: Dictionary) -> void: summary["units"]["player"][0]["strength"] = 0,
		"situação desconhecida": func(summary: Dictionary) -> void: summary["units"]["player"][0]["status"] = "voando",
		"moral acima do máximo": func(summary: Dictionary) -> void: summary["units"]["player"][0]["morale"] = 150,
		"sem max_morale": func(summary: Dictionary) -> void: summary["units"]["player"][0].erase("max_morale"),
		"efetivo fracionário": func(summary: Dictionary) -> void: summary["units"]["player"][0]["strength"] = 3.5,
		"efetivo em texto": func(summary: Dictionary) -> void: summary["units"]["player"][0]["strength"] = "muito",
		"lado inexistente": func(summary: Dictionary) -> void: summary["units"].erase("enemy"),
	}
	for label in cases:
		var s := _fight()
		_french_victory(s)
		s["battle"].end_turn()
		var summary: Dictionary = s["battle"].state.result_summary()
		cases[label].call(summary)
		assert_true(Flow.record_result(s["state"], s["battle_id"], summary)["ok"], "o registro aceita (%s): a validação forte é da aplicação" % label)
		var before: Dictionary = s["state"].to_dict()
		var result := Resolution.apply(s["registry"], s["state"], s["battle_id"])
		assert_true(not result["ok"], "recusado: %s" % label)
		assert_eq(s["state"].to_dict(), before, "nenhuma alteração parcial: %s" % label)
		assert_eq(s["state"].battles[s["battle_id"]]["status"], "active", "segue ativa: %s" % label)
	var s2 := _fight()
	_french_victory(s2)
	s2["battle"].end_turn()
	var no_winner: Dictionary = s2["battle"].state.result_summary()
	no_winner["winner"] = "ninguem"
	assert_true(not Flow.record_result(s2["state"], s2["battle_id"], no_winner)["ok"], "vencedor inválido nem é registrado")


func test_campaign_changes_since_the_battle_started_are_rejected() -> void:
	var cases := {
		"unidade mudou de efetivo": func(s: Dictionary) -> void: s["state"].unit_by_id(s["state"].armies[s["fra_army"]]["units"][0])["strength"] -= 1,
		"unidade mudou de moral": func(s: Dictionary) -> void: s["state"].unit_by_id(s["state"].armies[s["enemy_army"]]["units"][0])["morale"] -= 1,
		"exército participante sumiu": func(s: Dictionary) -> void: s["state"].armies.erase(s["enemy_army"]),
		"exército saiu da província": func(s: Dictionary) -> void: s["state"].armies[s["fra_army"]]["province"] = STRASBOURG,
		"unidade saiu do exército": func(s: Dictionary) -> void: s["state"].armies[s["fra_army"]]["units"].pop_back(),
		"unidade extra no exército": func(s: Dictionary) -> void: s["state"].armies[s["fra_army"]]["units"].append(s["state"].add_unit(s["registry"], "unit_line_inf", "fra", SWABIA)),
	}
	for label in cases:
		var s := _fight()
		_french_victory(s)
		s["battle"].end_turn()
		assert_true(Flow.record_result(s["state"], s["battle_id"], s["battle"].state.result_summary())["ok"], "registrado")
		cases[label].call(s)
		var before: Dictionary = s["state"].to_dict()
		var result := Resolution.apply(s["registry"], s["state"], s["battle_id"])
		assert_true(not result["ok"], "recusado: %s" % label)
		assert_eq(s["state"].to_dict(), before, "nada alterado: %s" % label)


func test_cancelled_and_already_applied_battles_cannot_be_applied() -> void:
	var s := _fight()
	_french_victory(s)
	s["battle"].end_turn()
	var summary: Dictionary = s["battle"].state.result_summary()
	assert_true(Flow.record_result(s["state"], s["battle_id"], summary)["ok"], "registrado")
	assert_true(Lifecycle.cancel(s["state"], s["battle_id"])["ok"], "cancelada")
	var before: Dictionary = s["state"].to_dict()
	var cancelled := Resolution.apply(s["registry"], s["state"], s["battle_id"])
	assert_true(not cancelled["ok"] and "cancelled" in cancelled["message"], "cancelada: " + cancelled["message"])
	assert_eq(s["state"].to_dict(), before, "nada mudou")


func test_the_result_is_applied_only_once() -> void:
	var s := _fight()
	var state = s["state"]
	_french_victory(s)
	var first := _conclude(s)
	assert_true(first["ok"], first["message"])
	var after_first: Dictionary = state.to_dict()
	var second := Resolution.apply(s["registry"], state, s["battle_id"])
	assert_true(not second["ok"] and "applied" in second["message"], "aplicada de novo: " + second["message"])
	assert_true(not Flow.apply_result(s["registry"], state, s["battle_id"])["ok"], "nem pelo fluxo")
	assert_true(not Flow.finish(s["registry"], state, s["battle_id"], s["battle"].state.result_summary())["ok"], "nem registrando de novo")
	assert_true(not Lifecycle.cancel(state, s["battle_id"])["ok"], "nem cancelando depois de aplicada")
	assert_eq(state.to_dict(), after_first, "as consequências não se repetem")
	assert_eq(state.battles[s["battle_id"]]["history"].size(), 2, "histórico: active -> applied, uma única vez")
	assert_true(not state.battles[s["battle_id"]]["tactical_result"].is_empty(), "o resultado tático segue preservado")
	assert_eq(state.battles[s["battle_id"]]["result"]["winner"], "player", "e o relatório estratégico é outro campo")


func test_a_failed_final_validation_undoes_everything_and_can_be_retried() -> void:
	var s := _fight()
	var state = s["state"]
	_french_victory(s)
	s["battle"].end_turn()
	assert_true(Flow.record_result(state, s["battle_id"], s["battle"].state.result_summary())["ok"], "registrado")
	var before: Dictionary = state.to_dict()
	var failing := func(_registry: RefCounted, _state: RefCounted) -> PackedStringArray: return PackedStringArray(["falha simulada"])
	var result := Resolution.apply(s["registry"], state, s["battle_id"], failing)
	assert_true(not result["ok"], "a aplicação foi desfeita")
	assert_has_error(result["errors"], "falha simulada", "o motivo aparece")
	assert_eq(state.to_dict(), before, "estado idêntico ao anterior: nem unidades, nem exércitos, nem encontro, nem a batalha")
	assert_eq(state.battles[s["battle_id"]]["status"], "active", "a batalha segue ativa")
	assert_true(not state.battles[s["battle_id"]]["tactical_result"].is_empty(), "com o resultado tático disponível")
	var retry := Flow.apply_result(s["registry"], state, s["battle_id"])
	assert_true(retry["ok"], "nova tentativa segura: %s" % retry["message"])
	assert_eq(state.battles[s["battle_id"]]["status"], "applied", "aplicada uma vez")


# --- Retirada: regra determinística, rota e ausência de destino -------------------------------------------------

func test_retreat_picks_the_nearest_allied_province_by_a_deterministic_rule() -> void:
	# Francônia (Baviera) é vizinha de Paris e Suábia; as duas passam a ser francesas: empate de distância -> id menor.
	var game := new_game()
	game["state"].provinces[SWABIA]["owner"] = "fra"
	var s := _fight_in(game, FRANCONIA, PARIS)
	_french_defeat(s)
	assert_true(_conclude(s)["ok"], "aplicada")
	assert_eq(game["state"].armies[s["fra_army"]]["province"], PARIS, "prov_paris < prov_swabia")
	# Com um exército hostil em Paris, a província deixa de ser candidata: vai para a outra.
	var game2 := new_game()
	game2["state"].provinces[SWABIA]["owner"] = "fra"
	declare_war_between(game2, "fra", "bav")
	army_in(game2, "bav", ["unit_line_inf"], PARIS)  # bávaros em Paris (hostis à França)
	var s2 := _fight_in(game2, FRANCONIA, PARIS)
	_french_defeat(s2)
	assert_true(_conclude(s2)["ok"], "aplicada")
	assert_eq(game2["state"].armies[s2["fra_army"]]["province"], SWABIA, "Paris ocupada por inimigos: recua para Suábia")


func test_retreat_may_cross_empty_enemy_territory_but_never_teleports() -> void:
	var game := new_game()
	var state = game["state"]
	declare_war_between(game, "fra", "bav")
	var vanguard := army_in(game, "fra", FRA_TYPES, SWABIA)  # exército já em território bávaro (vazio)
	ArmyActions.move_army(game["registry"], state, "fra", vanguard, BAVARIA)  # onde está o Exército Bávaro
	var started := Flow.start(game["registry"], state, Flow.load_context(), state.encounters[0]["id"])
	assert_true(started["ok"], started["message"])
	var s := {"game": game, "registry": game["registry"], "state": state, "fra_army": vanguard, "battle": started["controller"],
		"battle_id": started["battle_id"], "enemy_army": state.armies_in(BAVARIA, "bav")[0]}
	_french_defeat(s)
	assert_true(_conclude(s)["ok"], "aplicada")
	assert_eq(state.armies[vanguard]["province"], STRASBOURG, "a província francesa mais próxima fica a duas fronteiras")
	assert_eq(state.battles[s["battle_id"]]["result"]["armies"][vanguard]["path"], [SWABIA, STRASBOURG], "pelo caminho acessível")
	assert_eq(state.battles[s["battle_id"]]["result"]["armies"][vanguard]["from"], BAVARIA, "de onde saiu")


func test_defeated_army_without_a_reachable_allied_province_is_destroyed() -> void:
	var game := new_game()
	var state = game["state"]
	declare_war_between(game, "fra", "bav")
	army_in(game, "bav", ["unit_line_inf"], SWABIA)  # bloqueia a única rota de volta
	var vanguard := army_in(game, "fra", FRA_TYPES, SWABIA)
	ArmyActions.move_army(game["registry"], state, "fra", vanguard, BAVARIA)
	var started := Flow.start(game["registry"], state, Flow.load_context(), state.encounters[0]["id"])
	assert_true(started["ok"], started["message"])
	var s := {"game": game, "registry": game["registry"], "state": state, "fra_army": vanguard, "battle": started["controller"],
		"battle_id": started["battle_id"], "enemy_army": state.armies_in(BAVARIA, "bav")[0]}
	_french_defeat(s)
	var result := _conclude(s)
	assert_true(result["ok"], "a aplicação é bem-sucedida mesmo sem rota: " + result["message"])
	assert_true("sem rota de retirada" in result["message"], result["message"])
	assert_true(not state.armies.has(vanguard), "sem rota, o exército derrotado é destruído (não fica na província nem teletransporta)")
	var plan: Dictionary = state.battles[s["battle_id"]]["result"]["armies"][vanguard]
	assert_eq(plan["outcome"], "removed", "relatório: removido")
	assert_true(plan["no_route"], "relatório: por falta de rota")
	assert_eq(state.battles[s["battle_id"]]["status"], "applied", "batalha aplicada")
	assert_eq(state.encounters.size(), 0, "sem exércitos de dois países, o encontro termina")
	assert_eq(state.armies_in(BAVARIA, "bav").size(), 1, "o vencedor permanece")
	_valid(s)


# --- Empate -------------------------------------------------------------------------------------------------------

func _draw(s: Dictionary) -> Dictionary:
	var battle: BattleController = s["battle"]
	battle.state.over = true
	battle.state.result = {"winner": "draw", "reason": "turn_limit", "turn": 3, "text": "Empate em efetivos."}
	return Flow.finish(s["registry"], s["state"], s["battle_id"], battle.state.result_summary())


func test_draw_applies_losses_and_the_invader_withdraws_while_the_defender_stays() -> void:
	var s := _fight()
	var state = s["state"]
	var f: Array = _units(s, s["fra_army"])
	var b: Array = _units(s, s["enemy_army"])
	set_outcome(s["battle"], f[0], 200, 40)
	set_outcome(s["battle"], f[1], 0, 0, "destroyed")
	set_outcome(s["battle"], f[2], 100, 50)
	set_outcome(s["battle"], b[0], 210, 60)
	set_outcome(s["battle"], b[1], 0, 0, "destroyed")
	var result := _draw(s)
	assert_true(result["ok"], result["message"])
	assert_eq(state.unit_by_id(f[0])["strength"], 200, "perdas aplicadas aos dois lados")
	assert_eq(state.unit_by_id(b[0])["strength"], 210, "inclusive ao defensor")
	assert_true(state.unit_by_id(f[1]).is_empty() and state.unit_by_id(b[1]).is_empty(), "destruídas removidas")
	assert_eq(state.armies[s["fra_army"]]["province"], STRASBOURG, "o invasor (a França, que atacou a Baviera) recua")
	assert_eq(state.armies[s["enemy_army"]]["province"], SWABIA, "o dono da província, defensor, permanece")
	assert_eq(state.battles[s["battle_id"]]["result"]["winner"], "draw", "relatório: empate")
	assert_true(state.encounters.is_empty(), "encontro resolvido")
	_valid(s)


func test_draw_in_a_province_owned_by_a_third_country_moves_nobody() -> void:
	var s := _fight()
	var state = s["state"]
	state.provinces[SWABIA]["owner"] = "aus"
	set_outcome(s["battle"], _units(s, s["fra_army"])[0], 200, 40)
	var result := _draw(s)
	assert_true(result["ok"], result["message"])
	assert_eq(state.armies[s["fra_army"]]["province"], SWABIA, "ninguém recua")
	assert_eq(state.armies[s["enemy_army"]]["province"], SWABIA, "nem o outro lado")
	assert_eq(state.encounters.size(), 1, "o encontro segue pendente")
	assert_eq(state.battle_of_army(s["fra_army"]), 0, "mas sem bloqueio de batalha")


# --- Ciclo de vida, bloqueios e turno ---------------------------------------------------------------------------------

func test_applying_releases_the_locks_and_the_turn_can_advance() -> void:
	var s := _fight()
	var state = s["state"]
	_french_victory(s)
	var processor := TurnProcessor.new()
	assert_true(not processor.end_turn(s["registry"], state)["ok"], "com a batalha ativa o turno não avança")
	assert_true(_conclude(s)["ok"], "aplicada")
	var record: Dictionary = state.battles[s["battle_id"]]
	assert_eq(record["status"], "applied", "estado terminal")
	assert_eq(record["history"].map(func(entry: Dictionary) -> String: return entry["status"]), ["active", "applied"], "histórico")
	assert_eq(state.active_battles(), [] as Array[int], "nenhuma batalha ativa")
	for army_id in state.armies:
		assert_eq(state.battle_of_army(army_id), 0, "exército %d livre" % army_id)
	assert_eq(ArmyActions.battle_lock_reason(state, s["fra_army"]), "", "sem bloqueio")
	var report := processor.end_turn(s["registry"], state)
	assert_true(report["ok"], "o turno avança sem cancelar nada: %s" % str(report["errors"]))
	assert_eq(state.turn, 2, "turno 2")
	assert_true(not state.armies[s["fra_army"]]["moved"], "o movimento foi liberado no novo turno")


func test_another_active_battle_still_blocks_the_turn() -> void:
	var game := new_game()
	var state = game["state"]
	var first := _fight_in(game)
	var second := _fight_in(game, PARIS, STRASBOURG, "aus", ["unit_line_inf"], ["unit_line_inf"])
	_french_victory(first)
	assert_true(_conclude(first)["ok"], "a primeira é aplicada")
	assert_eq(state.active_battles(), [second["battle_id"]] as Array[int], "a segunda segue ativa")
	var blocked := TurnProcessor.new().end_turn(game["registry"], state)
	assert_true(not blocked["ok"], "o turno segue bloqueado")
	assert_has_error(PackedStringArray(blocked["errors"]), "#%d" % second["battle_id"], "cita a batalha que falta")
	assert_eq(state.battle_of_army(second["fra_army"]), second["battle_id"], "os participantes da segunda seguem bloqueados")
	assert_true(Lifecycle.cancel(state, second["battle_id"])["ok"], "cancela a segunda")
	assert_true(TurnProcessor.new().end_turn(game["registry"], state)["ok"], "agora o turno avança")


# --- Texto, jogo real e campanha pela interface --------------------------------------------------------------------------

func test_report_text_describes_what_changed() -> void:
	var s := _fight()
	_french_defeat(s)
	var result := _conclude(s)
	assert_true(result["ok"], result["message"])
	var name: String = s["registry"].provinces[STRASBOURG]["name"]
	assert_true("Vitória de Baviera" in result["message"], result["message"])
	assert_true(("recuou para %s" % name) in result["message"], result["message"])
	assert_true("1 de 3 unidades" in result["message"], result["message"])


func test_a_real_tactical_battle_played_to_the_end_is_applied_consistently() -> void:
	var s := _fight()
	var state = s["state"]
	var before := {}
	for unit_id in state.battles[s["battle_id"]]["units"]:
		before[unit_id] = state.unit_by_id(unit_id).duplicate(true)
	var battle: BattleController = s["battle"]
	var guard := 0
	while not battle.state.over and guard < 60:
		battle.end_turn()  # o jogador passa; o inimigo (IA) ataca
		guard += 1
	assert_true(battle.state.over, "a batalha real terminou (turnos: %d)" % guard)
	var result := Flow.finish(s["registry"], state, s["battle_id"], battle.state.result_summary())
	assert_true(result["ok"], result["message"])
	for unit_id in before:
		var unit: Dictionary = state.unit_by_id(unit_id)
		if not unit.is_empty():
			assert_true(unit["strength"] > 0 and unit["strength"] <= before[unit_id]["strength"], "efetivo %d coerente" % unit_id)
			assert_true(unit["morale"] >= 1 and unit["morale"] <= 100, "moral %d coerente" % unit_id)
	_valid(s)
	assert_eq(state.battles[s["battle_id"]]["status"], "applied", "aplicada")


func _campaign() -> Control:
	var main: Control = load(MAIN_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	return main


func test_main_scene_applies_the_result_and_returns_to_an_updated_campaign() -> void:
	var main := _campaign()
	var game := {"registry": main.registry, "state": main.state}
	var state = main.state
	declare_war_between(game, "fra", "bav")
	var enemy_army := army_in(game, "bav", BAV_TYPES, SWABIA)
	var fra_army := army_in(game, "fra", FRA_TYPES, STRASBOURG)
	ArmyActions.move_army(main.registry, state, "fra", fra_army, SWABIA)
	main.controller.select_province(SWABIA)
	main.controller.select_army(fra_army)
	main.controller.state_changed.emit()
	var encounter_id: int = state.encounters[0]["id"]
	main.screen.province_panel.start_battle_buttons[encounter_id].pressed.emit()
	var battle: BattleController = main.battle_screen.controller
	var f: Array = state.armies[fra_army]["units"].duplicate()
	var b: Array = state.armies[enemy_army]["units"].duplicate()
	set_outcome(battle, f[0], 410, 62)
	set_outcome(battle, f[1], 300, 55)
	set_outcome(battle, f[2], 150, 80)
	set_outcome(battle, b[0], 0, 0, "destroyed")
	set_outcome(battle, b[1], 90, 15, "fled")
	battle.end_turn()
	assert_eq(state.battles[1]["status"], "applied", "aplicada ao terminar a cena")
	assert_true("resultado aplicado" in main.battle_screen.result_panel.campaign_note_label.text, main.battle_screen.result_panel.campaign_note_label.text)
	assert_true("recuou para" in main.battle_screen.result_panel.campaign_note_label.text, "o painel mostra o que mudou")
	assert_true("Vitória de França" in main.battle_screen.result_panel.campaign_note_label.text, "e quem venceu")
	assert_eq(main.battle_screen.back_button.text, "Voltar à campanha", "sair não cancela nada")
	main.battle_screen.result_panel.back_button.pressed.emit()
	assert_true(main.screen.visible and main.battle_screen == null, "de volta à campanha")
	assert_eq(state.battles[1]["status"], "applied", "continua aplicada (voltar não cancela)")
	var armies: Array = main.controller.province_view(SWABIA)["armies"]
	assert_eq(armies.size(), 1, "a província mostra só o exército que permaneceu")
	assert_eq(armies[0]["id"], fra_army, "o da França")
	assert_eq(armies[0]["strength"], 860, "com o efetivo atualizado (410 + 300 + 150)")
	assert_true(not armies[0]["engaged"], "sem encontro pendente")
	assert_eq(state.armies[enemy_army]["province"], BAVARIA, "o derrotado recuou")
	assert_true(main.screen.province_panel.start_battle_buttons.is_empty(), "o painel não oferece mais batalha neste encontro")
	assert_eq(TurnProcessor.new().validate_state(main.registry, state), PackedStringArray(), "campanha consistente")
	main.screen.top_bar.end_turn_button.pressed.emit()
	assert_eq(state.turn, 2, "o turno avançou sem cancelar nada")
	main.free()


func test_main_scene_clears_the_selection_of_a_destroyed_army() -> void:
	var main := _campaign()
	var game := {"registry": main.registry, "state": main.state}
	var state = main.state
	declare_war_between(game, "fra", "bav")
	army_in(game, "bav", BAV_TYPES, SWABIA)
	var fra_army := army_in(game, "fra", ["unit_line_inf"], STRASBOURG)
	ArmyActions.move_army(main.registry, state, "fra", fra_army, SWABIA)
	main.controller.select_province(SWABIA)
	main.controller.select_army(fra_army)
	main.controller.state_changed.emit()
	main.screen.province_panel.start_battle_buttons[state.encounters[0]["id"]].pressed.emit()
	var battle: BattleController = main.battle_screen.controller
	set_outcome(battle, state.armies[fra_army]["units"][0], 0, 0, "destroyed")
	for unit_id in state.battles[1]["units"]:
		if state.battles[1]["units"][unit_id]["owner"] == "bav":
			set_outcome(battle, unit_id, 400, 70)
	battle.end_turn()
	assert_eq(state.battles[1]["status"], "applied", "aplicada")
	assert_true(not state.armies.has(fra_army), "exército destruído removido")
	assert_eq(main.controller.selected_army_id, 0, "a seleção do exército destruído foi limpa")
	assert_true(not main.screen.army_panel.visible, "e o painel do exército fechou")
	main.battle_screen.result_panel.back_button.pressed.emit()
	assert_eq(TurnProcessor.new().validate_state(main.registry, state), PackedStringArray(), "campanha consistente")
	main.free()
