extends PanelContainer
## Registro de combate (últimas linhas) e a mensagem mais recente (erros em vermelho).

const BattleController := preload("res://src/battle/battle_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

const VISIBLE_LINES := 6
const INITIAL_MESSAGE := "Clique em uma unidade sua, depois em um hexágono azul para mover ou em um alvo vermelho para atacar."

var message_label: Label
var log_label: Label
## Histórico completo desta batalha (a tela mostra só as últimas linhas).
var lines: Array[String] = []


func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_TOP]))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	add_child(column)
	message_label = UiStyle.make_label(14, UiStyle.ACCENT, true)
	message_label.text = INITIAL_MESSAGE
	column.add_child(message_label)
	log_label = UiStyle.make_label(13, UiStyle.TEXT, true)
	column.add_child(log_label)


func bind(controller: BattleController) -> void:
	controller.log_added.connect(append_line)
	controller.message_posted.connect(show_message)
	controller.restarted.connect(clear)


func append_line(text: String) -> void:
	for part in text.split("\n"):
		lines.append(part)
	log_label.text = "\n".join(PackedStringArray(lines.slice(maxi(0, lines.size() - VISIBLE_LINES))))


func show_message(text: String, is_error: bool) -> void:
	message_label.text = text.split("\n")[0]
	message_label.add_theme_color_override("font_color", UiStyle.ERROR if is_error else UiStyle.ACCENT)


func clear() -> void:
	lines = []
	log_label.text = ""
	message_label.text = INITIAL_MESSAGE
	message_label.add_theme_color_override("font_color", UiStyle.ACCENT)
