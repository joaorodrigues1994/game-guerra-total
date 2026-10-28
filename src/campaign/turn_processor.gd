extends RefCounted
## Esqueleto do processamento de turno (Fase 0).
## Apenas fixa e registra a ORDEM das etapas. Nenhuma regra é executada.
## A ordem é documentada em docs/ARCHITECTURE.md.

const PHASES: Array[StringName] = [
	&"income_expenses",       # receitas e despesas
	&"construction_progress", # progresso das construções
	&"recruitment",           # recrutamento
	&"supply_upkeep",         # abastecimento e manutenção militar
	&"ai_actions",            # ações dos países controlados pela IA
	&"military_movement",     # movimentações militares
	&"events",                # eventos e consequências pendentes
]


## Percorre as etapas na ordem e devolve o registro do que "rodou".
## `bus` (opcional) recebe turn_phase_processed para cada etapa.
func end_turn(_state: RefCounted, bus: Object = null) -> Array[StringName]:
	var log: Array[StringName] = []
	for phase in PHASES:
		_run_phase(phase)
		log.append(phase)
		if bus != null:
			bus.turn_phase_processed.emit(phase)
	return log


func _run_phase(_phase: StringName) -> void:
	pass  # Implementado nas fases seguintes.
