extends Node
## Sinais globais para desacoplar lógica de jogo e interface.
## Registrado como autoload "EventBus" em project.godot.

signal registry_loaded(ok: bool)
signal turn_phase_processed(phase: StringName)
## Emitido na última etapa do encerramento de turno, já com o novo número de turno.
signal turn_ended(new_turn: int)
