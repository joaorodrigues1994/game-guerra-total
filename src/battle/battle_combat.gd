extends RefCounted
## Resolução de ataques (corpo a corpo e à distância) e suas consequências (baixas, moral, destruição).
##
## FÓRMULA (valores em data/battle/battle_rules.json e unit_types.json):
##   poder      = ataque × (efetivo_atual / efetivo_máx) × mult_moral_atacante × (1 + carga)
##   defesa_ef  = defesa_alvo × (1 + bônus_terreno_do_alvo) × mult_moral_alvo
##   fração     = clamp(taxa × (poder / defesa_ef) × fator × variação, 0, max_loss_fraction)
##   baixas     = clamp(ceil(efetivo_alvo × fração), 1, efetivo_alvo)        (dano mínimo 1)
##   taxa       = melee_rate (0,22) ou ranged_rate (0,14); fator = 1 (ataque) ou retaliation_factor (0,5)
##   variação   = 1 + aleatório(-v, +v) com RNG de semente configurável (v = "variation"; v = 0 não sorteia)
## Carga: cavalaria (charge_bonus) que andou >= charge_min_steps hexágonos no turno e ataca corpo a corpo.
## Retaliação: após um ataque corpo a corpo, o alvo sobrevivente, firme/abalado e capaz de retaliar
##   contra-ataca uma vez com fator retaliation_factor. Ataques à distância não geram retaliação.
## Artilharia: só ataca à distância, entre min_range e attack_range, e não ataca no turno em que se moveu.

const Hex := preload("res://src/battle/hex.gd")
const Morale := preload("res://src/battle/battle_morale.gd")
const Turns := preload("res://src/battle/battle_turns.gd")


## Motivo da recusa do ataque ("" = permitido). Não altera o estado.
static func check_attack(state: RefCounted, side: String, attacker_id: int, target_id: int) -> String:
	if state.over:
		return "A batalha terminou."
	if not state.units.has(attacker_id) or not state.is_on_field(state.units[attacker_id]):
		return "Unidade atacante inexistente ou fora de combate."
	var attacker: Dictionary = state.units[attacker_id]
	if attacker["side"] != side:
		return "Esta unidade pertence ao outro lado."
	if state.active_side != side:
		return "Não é o turno deste lado."
	if not state.units.has(target_id) or not state.is_on_field(state.units[target_id]):
		return "Alvo inexistente ou fora de combate."
	var target: Dictionary = state.units[target_id]
	if target["side"] == attacker["side"]:
		return "Não é possível atacar uma unidade aliada."
	if attacker["routing"]:
		return "Unidades em retirada não podem atacar."
	if attacker["attacked"]:
		return "Esta unidade já atacou neste turno."
	if attacker["moved"] and not state.unit_types[attacker["type"]]["can_attack_after_move"]:
		return "%s não pode atacar no turno em que se moveu." % state.unit_types[attacker["type"]]["name"]
	return range_problem(attacker, Hex.distance(attacker["pos"], target["pos"]))


## "" se a distância está dentro do alcance da unidade; senão o motivo.
static func range_problem(attacker: Dictionary, distance: int) -> String:
	if distance < attacker["min_range"]:
		return "Alvo perto demais (distância %d; mínimo %d)." % [distance, attacker["min_range"]]
	if distance > attacker["attack_range"]:
		return "Alvo fora do alcance (distância %d; alcance máximo %d)." % [distance, attacker["attack_range"]]
	return ""


## Se a unidade, estando em `from_hex`, alcançaria o alvo (só distância; usado pela IA).
static func in_range_from(unit: Dictionary, from_hex: Vector2i, target: Dictionary) -> bool:
	return range_problem(unit, Hex.distance(from_hex, target["pos"])).is_empty()


## Resolve o ataque. Resultado: {ok, message, losses, counter_losses, destroyed, counter_destroyed, battle_over}.
static func attack(state: RefCounted, side: String, attacker_id: int, target_id: int) -> Dictionary:
	var reason := check_attack(state, side, attacker_id, target_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var attacker: Dictionary = state.units[attacker_id]
	var target: Dictionary = state.units[target_id]
	var melee: bool = attacker["melee"]
	var charge_bonus := float(state.unit_types[attacker["type"]]["charge_bonus"])
	var charging: bool = melee and charge_bonus > 0.0 and attacker["moved_steps"] >= int(state.rules["charge_min_steps"])

	attacker["attacked"] = true
	var kind := "à distância"
	if melee:
		kind = "carga" if charging else "corpo a corpo"
	var first := _strike(state, attacker, target, melee, 1.0, charge_bonus if charging else 0.0)
	var message := "%s ataca %s (%s): %s (%d/%d), moral %d → %d.%s" % [
		attacker["name"], target["name"], kind, _casualties(first["losses"]), target["strength"], target["max_strength"],
		first["morale_before"], target["morale"], " Unidade destruída!" if target["destroyed"] else ""]
	state.add_log(message)

	var counter := {"losses": 0}
	if melee and not target["destroyed"] and not target["routing"] \
			and state.unit_types[target["type"]]["can_retaliate"]:
		counter = _strike(state, target, attacker, true, float(state.rules["retaliation_factor"]), 0.0)
		var counter_message := "%s contra-ataca %s: %s (%d/%d), moral %d → %d.%s" % [
			target["name"], attacker["name"], _casualties(counter["losses"]), attacker["strength"], attacker["max_strength"],
			counter["morale_before"], attacker["morale"], " Unidade destruída!" if attacker["destroyed"] else ""]
		state.add_log(counter_message)
		message += "\n" + counter_message
	Turns.evaluate_victory(state)
	return {
		"ok": true,
		"message": message,
		"losses": first["losses"],
		"counter_losses": counter["losses"],
		"destroyed": target["destroyed"],
		"counter_destroyed": attacker["destroyed"],
		"charge": charging,
		"battle_over": state.over,
	}


static func _casualties(count: int) -> String:
	return "1 baixa" if count == 1 else "%d baixas" % count


## Um golpe de `from` contra `to`. Aplica baixas, moral e destruição. Devolve {losses, morale_before}.
static func _strike(state: RefCounted, from: Dictionary, to: Dictionary, melee: bool, factor: float, charge: float) -> Dictionary:
	var fraction := loss_fraction(state, from, to, melee, factor, charge)
	# O epsilon evita que erros de ponto flutuante (110.00000000000001) somem uma baixa a mais.
	var losses := clampi(ceili(to["strength"] * fraction - 0.000001), 1, to["strength"])
	var morale_before: int = to["morale"]
	to["strength"] -= losses
	if to["strength"] <= 0:
		to["strength"] = 0
		to["destroyed"] = true
		Morale.on_unit_destroyed(state, to)
	else:
		Morale.apply_hit(state, to, losses, melee)
	return {"losses": losses, "morale_before": morale_before}


## Fração do efetivo do alvo perdida em um golpe (consome o RNG apenas se a variação for > 0).
static func loss_fraction(state: RefCounted, from: Dictionary, to: Dictionary, melee: bool, factor: float, charge: float) -> float:
	var power: float = from["attack"] * (float(from["strength"]) / float(from["max_strength"])) \
		* Morale.attack_multiplier(state, from) * (1.0 + charge)
	var defense: float = to["defense"] * (1.0 + state.map.defense_bonus(to["pos"])) * Morale.defense_multiplier(state, to)
	var rate := float(state.rules["melee_rate"] if melee else state.rules["ranged_rate"])
	var variation := 1.0
	var spread := float(state.rules["variation"])
	if spread > 0.0:
		variation = 1.0 + state.rng.randf_range(-spread, spread)
	return clampf(rate * (power / defense) * factor * variation, 0.0, float(state.rules["max_loss_fraction"]))
