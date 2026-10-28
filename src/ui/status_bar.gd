extends PanelContainer
## Barra de mensagens: resultado de ações, motivos de rejeição e resumo do turno.

const CampaignController := preload("res://src/campaign/campaign_controller.gd")
const UiStyle := preload("res://src/ui/ui_style.gd")

const INITIAL_MESSAGE := "Selecione uma província sua para construir ou recrutar. Encerre o turno para processar a economia."

var message_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(0, 78)
	add_theme_stylebox_override("panel", UiStyle.panel_style([SIDE_TOP]))
	message_label = UiStyle.make_label(14, UiStyle.TEXT, true)
	message_label.text = INITIAL_MESSAGE
	add_child(message_label)


func bind(controller: CampaignController) -> void:
	controller.message_posted.connect(show_message)


func show_message(text: String, is_error: bool) -> void:
	message_label.text = text
	message_label.add_theme_color_override("font_color", UiStyle.ERROR if is_error else UiStyle.TEXT)
