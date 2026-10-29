extends "res://tests/battle_case.gd"
## Base dos testes de integração campanha <-> batalha (não começa com "test_": o executor não a roda).
## Os encontros nascem do código real da campanha (ArmyActions.move_army), nunca de dados montados à mão.

const ArmyActions := preload("res://src/units/army_actions.gd")
const Builder := preload("res://src/integration/battle_scenario_builder.gd")

const PROVINCE := "prov_strasbourg"  # França; terreno estratégico: river_valley
const OTHER_PROVINCE := "prov_paris"  # França; terreno estratégico: plains


func mapping() -> Dictionary:
	var loaded := Builder.load_mapping()
	assert_true(loaded["ok"], "mapeamento real deve carregar: %s" % str(loaded["errors"]))
	return loaded["mapping"].duplicate(true)


## Exército parado na província (como o inimigo já presente).
func army_in(game: Dictionary, owner_id: String, types: Array, province_id: String = PROVINCE) -> int:
	var state = game["state"]
	var army_id: int = state.create_army("Exército %d de %s" % [state.next_army_id, owner_id], owner_id, province_id)
	for type_id in types:
		state.armies[army_id]["units"].append(state.add_unit(game["registry"], type_id, owner_id, province_id))
	return army_id


## Exército da França que CHEGA à província vindo de outra: o encontro é registrado pelo código real.
func fra_army_arriving(game: Dictionary, types: Array, from_province: String, to_province: String) -> int:
	var army_id := army_in(game, "fra", types, from_province)
	var moved := ArmyActions.move_army(game["registry"], game["state"], "fra", army_id, to_province)
	assert_true(moved["ok"], moved["message"])
	return army_id


## Encontro em `province` (aus já presente; fra chega vinda da outra província francesa). Devolve o id do encontro.
func make_encounter(game: Dictionary, province: String = PROVINCE, types: Array = ["unit_line_inf", "unit_line_inf", "unit_light_cav"]) -> int:
	var from_province := OTHER_PROVINCE if province == PROVINCE else PROVINCE
	army_in(game, "aus", ["unit_line_inf", "unit_field_art"], province)
	fra_army_arriving(game, types, from_province, province)
	for encounter in game["state"].encounters:
		if encounter["province"] == province:
			return encounter["id"]
	assert_true(false, "o encontro deveria existir em %s" % province)
	return 0


func build_scenario(game: Dictionary, encounter_id: int) -> Dictionary:
	return Builder.build(game["registry"], game["state"], battle_registry(), mapping(), encounter_id)
