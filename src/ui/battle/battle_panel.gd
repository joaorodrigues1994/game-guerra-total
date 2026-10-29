extends PanelContainer
## Painel lateral da batalha: unidade selecionada (efetivo, ataque, defesa, movimento, moral) e hexágono.

const BattleController := preload("res://src/battle/battle_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

var controller: BattleController

var empty_label: Label
var unit_title_label: Label
var unit_side_label: Label
var strength_label: Label
var strength_bar: ProgressBar
var stats_label: Label
var movement_label: Label
var range_label: Label
var morale_label: Label
var morale_bar: ProgressBar
var actions_label: Label
var hex_label: Label

var _unit_box: VBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(330, 0)
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_LEFT]))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var heading := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	heading.text = "UNIDADE"
	root.add_child(heading)

	empty_label = UiStyle.make_label(15, UiStyle.TEXT_DIM, true)
	empty_label.text = "Nenhuma unidade selecionada.\nClique em uma unidade do mapa."
	root.add_child(empty_label)

	_unit_box = VBoxContainer.new()
	_unit_box.add_theme_constant_override("separation", 5)
	root.add_child(_unit_box)
	unit_title_label = UiStyle.make_label(22, UiStyle.ACCENT, true)
	_unit_box.add_child(unit_title_label)
	unit_side_label = UiStyle.make_label(14, UiStyle.TEXT, true)
	_unit_box.add_child(unit_side_label)
	strength_label = UiStyle.make_label(15)
	_unit_box.add_child(strength_label)
	strength_bar = _make_bar(Color("5cc24a"))
	_unit_box.add_child(strength_bar)
	stats_label = UiStyle.make_label(15)
	_unit_box.add_child(stats_label)
	movement_label = UiStyle.make_label(15, UiStyle.TEXT, true)
	_unit_box.add_child(movement_label)
	range_label = UiStyle.make_label(15, UiStyle.TEXT, true)
	_unit_box.add_child(range_label)
	morale_label = UiStyle.make_label(15)
	_unit_box.add_child(morale_label)
	morale_bar = _make_bar(Color("4aa3e0"))
	_unit_box.add_child(morale_bar)
	actions_label = UiStyle.make_label(14, UiStyle.TEXT_DIM, true)
	_unit_box.add_child(actions_label)

	root.add_child(HSeparator.new())
	var hex_heading := UiStyle.make_label(13, UiStyle.TEXT_DIM)
	hex_heading.text = "HEXÁGONO"
	root.add_child(hex_heading)
	hex_label = UiStyle.make_label(15, UiStyle.TEXT, true)
	root.add_child(hex_label)

	show_unit({})
	show_hex({})


func bind(p_controller: BattleController) -> void:
	controller = p_controller
	controller.state_changed.connect(_refresh)
	controller.selection_changed.connect(_refresh)
	controller.restarted.connect(_refresh)
	_refresh()


func _refresh() -> void:
	show_unit(controller.unit_view(controller.selected_unit_id))
	show_hex(controller.hex_view(controller.selected_hex))


func _make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## Preenche o painel com uma visão de unidade (BattleController.unit_view); vazio = sem seleção.
func show_unit(view: Dictionary) -> void:
	_unit_box.visible = not view.is_empty()
	empty_label.visible = view.is_empty()
	if view.is_empty():
		return
	unit_title_label.text = view["name"]
	unit_side_label.text = "%s · %s%s" % [view["type_name"], view["side_name"],
		"" if view["is_player"] else " (inimigo: somente consulta)"]
	strength_label.text = "Efetivo: %d / %d" % [view["strength"], view["max_strength"]]
	strength_bar.max_value = view["max_strength"]
	strength_bar.value = view["strength"]
	stats_label.text = "Ataque: %d   ·   Defesa: %d" % [view["attack"], view["defense"]]
	movement_label.text = "Movimento: %d disponível de %d%s" % [view["move_available"], view["move_range"],
		" (já se moveu)" if view["moved"] else ""]
	var range_text := "%d (corpo a corpo)" % view["attack_range"] if view["melee"] \
		else "%d a %d (à distância)" % [view["min_range"], view["attack_range"]]
	range_label.text = "Alcance de ataque: %s" % range_text
	morale_label.text = "Moral: %d / %d — %s" % [view["morale"], view["max_morale"], view["status_text"]]
	morale_bar.max_value = view["max_morale"]
	morale_bar.value = view["morale"]
	actions_label.text = "Neste turno: %s · %s" % [
		"moveu" if view["moved"] else "não moveu", "atacou" if view["attacked"] else "não atacou"]


## Preenche o bloco do hexágono (BattleController.hex_view); vazio = nenhum hexágono selecionado.
func show_hex(view: Dictionary) -> void:
	if view.is_empty():
		hex_label.text = "Nenhum hexágono selecionado."
		return
	var lines := PackedStringArray()
	lines.append("Posição: coluna %d, linha %d  (axial %d, %d)" % [view["col"], view["row"], view["axial"].x, view["axial"].y])
	lines.append("Terreno: %s" % view["terrain_name"])
	if view["passable"]:
		lines.append("Custo de movimento: %d" % view["move_cost"])
		lines.append("Bônus defensivo: +%d%%" % roundi(view["defense_bonus"] * 100.0))
	else:
		lines.append("Intransponível")
	if view["unit_id"] != 0:
		lines.append("Ocupante: %s" % controller.unit_view(view["unit_id"])["name"])
	hex_label.text = "\n".join(lines)
