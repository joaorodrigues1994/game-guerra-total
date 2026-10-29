extends RefCounted
## Moral das unidades: efeitos no combate, perdas por baixas, recuperação, retirada e reagrupamento.
## Valores em data/battle/battle_rules.json. Moral sempre dentro de [0, max_morale].
##
## Estados (BattleState.status_of): firm (> shaken_threshold), shaken (<= shaken_threshold),
## routing (entra em retirada ao cair a <= rout_threshold; só se reagrupa ao chegar a >= rally_threshold,
## recuperando moral longe de inimigos), fled (saiu do campo pela borda) e destroyed.

const Hex := preload("res://src/battle/hex.gd")


## Multiplicador do ataque pelo estado de moral (em retirada = 0: não ataca).
static func attack_multiplier(state: RefCounted, unit: Dictionary) -> float:
	match state.status_of(unit):
		"shaken":
			return float(state.rules["shaken_attack_multiplier"])
		"routing":
			return 0.0
	return 1.0


## Multiplicador da defesa pelo estado de moral (em retirada a unidade fica vulnerável).
static func defense_multiplier(state: RefCounted, unit: Dictionary) -> float:
	match state.status_of(unit):
		"shaken":
			return float(state.rules["shaken_defense_multiplier"])
		"routing":
			return float(state.rules["routing_defense_multiplier"])
	return 1.0


static func change(state: RefCounted, unit: Dictionary, delta: int) -> void:
	unit["morale"] = clampi(unit["morale"] + delta, 0, unit["max_morale"])
	update_rout(state, unit)


static func update_rout(state: RefCounted, unit: Dictionary) -> void:
	if not unit["routing"] and not unit["destroyed"] and unit["morale"] <= state.rules["rout_threshold"]:
		unit["routing"] = true
		state.add_log("%s perde a coragem e entra em retirada!" % unit["name"])


## Perda de moral por receber um ataque que causou `losses` baixas. Devolve a queda aplicada.
static func apply_hit(state: RefCounted, unit: Dictionary, losses: int, melee: bool) -> int:
	var fraction := float(losses) / float(unit["max_strength"])
	var drop := ceili(fraction * 100.0 * float(state.rules["morale_loss_per_casualty_percent"]) - 0.000001)
	drop += int(state.rules["morale_hit_penalty"])
	if melee:
		drop += int(state.rules["morale_melee_extra_penalty"])
	var before: int = unit["morale"]
	change(state, unit, -drop)
	return before - unit["morale"]


## Aliados em campo a até ally_death_radius hexágonos de uma unidade destruída perdem moral.
static func on_unit_destroyed(state: RefCounted, dead: Dictionary) -> void:
	for id in state.live_units(dead["side"]):
		var ally: Dictionary = state.units[id]
		if Hex.distance(ally["pos"], dead["pos"]) <= int(state.rules["ally_death_radius"]):
			change(state, ally, -int(state.rules["ally_death_morale_penalty"]))


static func has_adjacent_enemy(state: RefCounted, unit: Dictionary) -> bool:
	for n in Hex.neighbors(unit["pos"]):
		var other_id: int = state.unit_at(n)
		if other_id != 0 and state.units[other_id]["side"] != unit["side"]:
			return true
	return false


## Início do turno do lado: unidades sem inimigo adjacente recuperam moral; as que estavam em
## retirada e alcançaram rally_threshold se reagrupam (voltam a obedecer, abaladas).
static func recover_side(state: RefCounted, side: String) -> void:
	for id in state.live_units(side):
		var unit: Dictionary = state.units[id]
		if has_adjacent_enemy(state, unit):
			continue
		var gain := int(state.rules["morale_recovery_routing"]) if unit["routing"] else int(state.rules["morale_recovery"])
		unit["morale"] = mini(unit["morale"] + gain, unit["max_morale"])
		if unit["routing"] and unit["morale"] >= state.rules["rally_threshold"]:
			unit["routing"] = false
			state.add_log("%s se reagrupa." % unit["name"])
