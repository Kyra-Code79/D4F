class_name D4FUITheme
extends RefCounted
## Provides a clean, playful, competitive UI styling helper for all 11 screens.

const COLOR_BG_DARK := Color("#121624")
const COLOR_PANEL := Color("#1c2236")
const COLOR_PANEL_BORDER := Color("#334166")
const COLOR_ACCENT_BLUE := Color("#1e90ff")
const COLOR_ACCENT_ORANGE := Color("#ff6b2b")
const COLOR_ACCENT_GREEN := Color("#2ed573")
const COLOR_ACCENT_GOLD := Color("#ffd32a")
const COLOR_DANGER := Color("#ff4757")
const COLOR_TEXT_MAIN := Color("#f1f2f6")
const COLOR_TEXT_MUTED := Color("#a4b0be")

static func style_panel(panel: PanelContainer, bg_color: Color = COLOR_PANEL, border_color: Color = COLOR_PANEL_BORDER, corner_radius: int = 10) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.set_border_width_all(2)
	box.set_corner_radius_all(corner_radius)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", box)

static func style_button(btn: Button, bg_color: Color = COLOR_ACCENT_BLUE, min_size: Vector2 = Vector2(160, 42)) -> void:
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_ALL

	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = bg_color.lightened(0.28)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 8.0
	normal.content_margin_bottom = 8.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg_color.lightened(0.14)
	hover.border_color = Color.WHITE

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = bg_color.darkened(0.18)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)

static func create_header_label(text: String, font_size: int = 28, color: Color = COLOR_TEXT_MAIN) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl

static func create_body_label(text: String, font_size: int = 15, color: Color = COLOR_TEXT_MUTED) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
