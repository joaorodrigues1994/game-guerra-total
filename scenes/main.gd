extends Control
## Cena inicial da Fase 0: confirma que o projeto executa e que os dados carregam.

const Registry := preload("res://src/core/registry.gd")


func _ready() -> void:
	var registry := Registry.new()
	var loaded := registry.load_from_dir("res://data")

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = _build_text(registry, loaded)
	add_child(label)

	if not loaded:
		for message in registry.errors:
			push_error(message)


func _build_text(registry: RefCounted, loaded: bool) -> String:
	var title := str(ProjectSettings.get_setting("application/config/name"))
	var lines := PackedStringArray([title, "Fase 0 — Fundação", ""])
	lines.append("Godot %s" % Engine.get_version_info()["string"])
	if loaded:
		lines.append("Dados: %d países, %d províncias, %d unidades, %d construções" % [
			registry.countries.size(), registry.provinces.size(),
			registry.units.size(), registry.buildings.size()])
	else:
		lines.append("ERRO ao carregar dados (veja o console)")
	return "\n".join(lines)
