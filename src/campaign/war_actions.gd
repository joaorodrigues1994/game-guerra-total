extends RefCounted
## Declaração de guerra (Etapa 5.1): a ÚNICA mecânica diplomática existente. Sem paz negociada, alianças, tratados,
## reputação nem casus belli. A relação mora em GameState.wars; a movimentação (ArmyActions.check_move) e a criação
## de encontros (ArmyActions.move_army) a consultam por GameState.at_war.
## Toda ação valida ANTES de alterar o estado: se algo falhar, o estado permanece intacto e o motivo é devolvido em
## português. Resultado: {ok: bool, message: String}.


## Motivo pelo qual `country_id` não pode declarar guerra a `target_id`; "" se pode. Não altera nada.
static func check_declare_war(registry: RefCounted, state: RefCounted, country_id: String, target_id: String) -> String:
	if not registry.countries.has(country_id) or not state.countries.has(country_id):
		return "País inexistente."
	if not registry.countries.has(target_id) or not state.countries.has(target_id):
		return "País inexistente."
	if country_id == target_id:
		return "Um país não pode declarar guerra a si mesmo."
	if state.at_war(country_id, target_id):
		return "Já há guerra declarada entre %s e %s." % [registry.countries[country_id]["name"], registry.countries[target_id]["name"]]
	return ""


static func declare_war(registry: RefCounted, state: RefCounted, country_id: String, target_id: String) -> Dictionary:
	var reason := check_declare_war(registry, state, country_id, target_id)
	if not reason.is_empty():
		return {"ok": false, "message": reason}
	var pair: Array = [country_id, target_id]
	pair.sort()
	state.wars[state.war_key(country_id, target_id)] = {"countries": pair, "declared_by": country_id, "turn": state.turn}
	return {"ok": true, "message": "%s declarou guerra a %s. Seus exércitos podem entrar no território inimigo e exércitos inimigos geram encontros." % [
		registry.countries[country_id]["name"], registry.countries[target_id]["name"]]}
