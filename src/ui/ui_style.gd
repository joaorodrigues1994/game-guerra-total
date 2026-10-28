extends RefCounted
## Cores e estilos compartilhados pela interface de campanha.

const PANEL_BG := Color("2a2018")
const PANEL_BORDER := Color("6b5230")
const TEXT := Color("efe4c8")
const TEXT_DIM := Color("a89a7c")
const ACCENT := Color("ffd84a")


static func panel_style(border_sides: Array[int] = []) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_content_margin_all(12)
	for side in border_sides:
		style.set_border_width(side, 2)
	return style


static func make_label(font_size: int, color: Color = TEXT, wrap: bool = false) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
