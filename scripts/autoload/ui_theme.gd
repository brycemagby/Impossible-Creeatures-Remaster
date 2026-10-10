extends Node
## The game's look: 1930s pulp-adventure brass and art deco, with a
## retro-futuristic spin (dark glass panels, cyan "valve-glow" highlights,
## chamfered corners).
##
## Builds one Theme at startup and merges it into the default theme, so every
## Control in every scene picks it up. Other scripts use the palette and the
## helpers below for titles and one-off styles. Placeholder art until
## human-made assets replace it.

# --- Palette ------------------------------------------------------------------
## Polished brass: frames, titles.
const BRASS := Color(0.86, 0.66, 0.34)
## Shadowed brass: inner edges, disabled frames.
const BRASS_DARK := Color(0.45, 0.32, 0.15)
## Valve glow: hover, focus, selected, live readouts.
const GLOW := Color(0.36, 0.92, 0.88)
## Smoked glass behind panels.
const GLASS := Color(0.04, 0.09, 0.11, 0.9)
const GLASS_LIGHT := Color(0.08, 0.17, 0.2, 0.95)
## Ivory text and dimmer secondary text.
const TEXT := Color(0.95, 0.9, 0.79)
const TEXT_DIM := Color(0.66, 0.68, 0.62)
const WARNING := Color(1.0, 0.72, 0.32)
const DANGER := Color(0.98, 0.38, 0.3)
## Full-screen backdrop for menus.
const BACKDROP := Color(0.03, 0.06, 0.07)

const TITLE_FONT := preload("res://assets/fonts/Federo-Regular.ttf")
const BODY_FONT := preload("res://assets/fonts/Rajdhani-SemiBold.ttf")
const BOLD_FONT := preload("res://assets/fonts/Rajdhani-Bold.ttf")

## Chamfer size (corners cut at 45 degrees).
const CUT := 7

var theme: Theme


func _enter_tree() -> void:
	theme = build_theme()
	# Merged into the engine's default theme rather than set on the root
	# window: a window's theme doesn't reach Controls under a CanvasLayer
	# (the in-game HUD), but the default theme is everyone's fallback.
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = BODY_FONT
	ThemeDB.get_default_theme().default_font_size = 18


func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 18

	# Panels: smoked glass in a brass frame.
	var panel := framed(GLASS, BRASS, 2)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# Buttons: dark glass plates; hover lights the valve glow.
	var normal := framed(GLASS_LIGHT, BRASS_DARK, 2)
	var hover := framed(Color(0.1, 0.24, 0.27, 0.97), GLOW, 2)
	var pressed := framed(Color(0.14, 0.36, 0.38, 0.98), GLOW, 2)
	var disabled := framed(Color(0.06, 0.08, 0.09, 0.85), Color(0.25, 0.22, 0.17), 1)
	var focus := StyleBoxEmpty.new()
	for style in [normal, hover, pressed, disabled]:
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, GLOW)
		t.set_color("font_hover_pressed_color", type, GLOW)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(0.5, 0.48, 0.42))
		t.set_color("font_outline_color", type, Color.BLACK)
		t.set_constant("outline_size", type, 0)
	# Check boxes and toggles sit on the background, not on a plate.
	for type in ["CheckBox", "CheckButton"]:
		var plain := StyleBoxEmpty.new()
		plain.content_margin_left = 4
		plain.content_margin_right = 4
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(state, type, plain)

	# Labels: ivory with a dark outline, readable over the 3D world.
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 4)

	# Text input, drop-down lists, tooltips and scroll bars.
	var field := framed(Color(0.02, 0.05, 0.06, 0.95), BRASS_DARK, 1)
	field.content_margin_left = 8
	field.content_margin_right = 8
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", framed(Color(0.02, 0.05, 0.06, 0.95), GLOW, 1))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GLOW)
	t.set_color("selection_color", "LineEdit", Color(GLOW, 0.35))
	var popup := framed(GLASS, BRASS, 2)
	popup.content_margin_left = 6
	popup.content_margin_right = 6
	popup.content_margin_top = 6
	popup.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", framed(Color(0.1, 0.24, 0.27), GLOW, 1))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var tooltip := framed(Color(0.03, 0.07, 0.08, 0.96), GLOW, 1)
	tooltip.content_margin_left = 8
	tooltip.content_margin_right = 8
	tooltip.content_margin_top = 4
	tooltip.content_margin_bottom = 4
	t.set_stylebox("panel", "TooltipPanel", tooltip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.4)
		var grabber := StyleBoxFlat.new()
		grabber.bg_color = BRASS_DARK
		var grabber_hot := StyleBoxFlat.new()
		grabber_hot.bg_color = BRASS
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, grabber)
		t.set_stylebox("grabber_highlight", bar, grabber_hot)
		t.set_stylebox("grabber_pressed", bar, grabber_hot)
	var slider_track := StyleBoxFlat.new()
	slider_track.bg_color = Color(0.02, 0.05, 0.06)
	slider_track.border_color = BRASS_DARK
	slider_track.set_border_width_all(1)
	slider_track.content_margin_top = 3
	slider_track.content_margin_bottom = 3
	var slider_fill := StyleBoxFlat.new()
	slider_fill.bg_color = Color(GLOW, 0.6)
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider_track)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	# Item lists (map picker, combiner): rows light up like valves.
	var list := framed(Color(0.02, 0.05, 0.06, 0.92), BRASS_DARK, 1)
	list.content_margin_left = 6
	list.content_margin_right = 6
	list.content_margin_top = 6
	list.content_margin_bottom = 6
	t.set_stylebox("panel", "ItemList", list)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var row_selected := framed(Color(0.12, 0.32, 0.34, 0.95), GLOW, 1, 4)
	t.set_stylebox("selected", "ItemList", row_selected)
	t.set_stylebox("selected_focus", "ItemList", row_selected)
	t.set_stylebox("hovered", "ItemList", framed(Color(0.08, 0.17, 0.2), BRASS_DARK, 1, 4))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_constant("v_separation", "ItemList", 6)
	var bar_bg := framed(Color(0.02, 0.05, 0.06, 0.9), BRASS_DARK, 1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = GLOW
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	return t


## A chamfered box: [param fill] inside a [param border]-coloured frame.
static func framed(fill: Color, border: Color, width := 2, cut := CUT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(cut)
	# One segment per corner turns the rounded corner into a straight cut.
	style.corner_detail = 1
	style.anti_aliasing = true
	return style


## Styles [param label] as a title: deco capitals in brass with a soft glow.
static func style_title(label: Label, size := 48) -> void:
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", BRASS)
	label.add_theme_color_override("font_shadow_color", Color(GLOW, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", maxi(6, size / 6))
	label.add_theme_constant_override("outline_size", 0)
	label.text = label.text.to_upper()


## A section heading: small, bold and glowing.
static func style_heading(label: Label, size := 16) -> void:
	label.add_theme_font_override("font", BOLD_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GLOW)
