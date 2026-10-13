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

# --- Fonts --------------------------------------------------------------------
# Free (SIL OFL) stand-ins for the intended commercial faces:
#   titles and logos  Cinzel Bold        for Copperplate Gothic Bold
#   headings          Michroma           for Microgramma
#   body and buttons  Saira SemiBold     for Eurostile
# Licensed fonts dropped into assets/fonts/licensed/ as title, heading or body
# (.ttf or .otf) replace these automatically; that folder isn't committed.
const LICENSED_DIR := "res://assets/fonts/licensed/"
const CINZEL := preload("res://assets/fonts/Cinzel.ttf")
const MICHROMA := preload("res://assets/fonts/Michroma-Regular.ttf")
const SAIRA := preload("res://assets/fonts/Saira.ttf")

var title_font: Font
var heading_font: Font
var body_font: Font
## Numbers on the resource gauges.
var bold_font: Font

## Chamfer size (corners cut at 45 degrees).
const CUT := 7

var theme: Theme


func _enter_tree() -> void:
	title_font = _licensed("title", _weighted(CINZEL, 800))
	heading_font = _licensed("heading", MICHROMA)
	body_font = _licensed("body", _weighted(SAIRA, 600))
	bold_font = _licensed("body", _weighted(SAIRA, 700))
	theme = build_theme()
	# Merged into the engine's default theme rather than set on the root
	# window: a window's theme doesn't reach Controls under a CanvasLayer
	# (the in-game HUD), but the default theme is everyone's fallback.
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = body_font
	ThemeDB.get_default_theme().default_font_size = 18


func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font
	t.default_font_size = 18

	# Panels: smoked glass in a brass frame.
	# Panels: a heavy riveted brass bezel around dark glass (frame_panel.png).
	var panel := textured("frame_panel", 26)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	# Buttons: dark glass plates; hover lights the valve glow.
	# Bevelled brass-rimmed plates; pressed ones sink and glow.
	var normal := textured("button_normal", 12)
	var hover := textured("button_hover", 12)
	var pressed := textured("button_pressed", 12)
	var disabled := textured("button_disabled", 12)
	# A valve-glow outline shows which control the keyboard or gamepad is on.
	var focus := focus_ring()
	for style in [normal, hover, pressed, disabled]:
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 6
		style.content_margin_bottom = 6
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
	var list := textured("frame_panel", 26)
	list.content_margin_left = 14
	list.content_margin_right = 14
	list.content_margin_top = 12
	list.content_margin_bottom = 12
	t.set_stylebox("panel", "ItemList", list)
	t.set_stylebox("focus", "ItemList", focus_ring())
	for type in ["HSlider", "TabBar", "TabContainer", "SpinBox"]:
		t.set_stylebox("focus", type, focus_ring())
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


## A nine-sliced texture from assets/ui (painted by tools/generate_ui_textures.py);
## [param margin] is the unstretched border in pixels.
static func textured(texture_name: String, margin: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/%s.png" % texture_name)
	style.texture_margin_left = margin
	style.texture_margin_right = margin
	style.texture_margin_top = margin
	style.texture_margin_bottom = margin
	return style


## The bottom console strip: a riveted brass band over machined gunmetal,
## repeated sideways.
static func console_style() -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/ui/console.png")
	style.texture_margin_top = 20
	style.texture_margin_bottom = 2
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return style


## A chamfered box: [param fill] inside a [param border]-coloured frame.
## The keyboard / gamepad focus outline drawn over a focused control.
static func focus_ring() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = GLOW
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.expand_margin_left = 3
	style.expand_margin_right = 3
	style.expand_margin_top = 3
	style.expand_margin_bottom = 3
	return style


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
func style_title(label: Label, size := 48) -> void:
	label.add_theme_font_override("font", title_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", BRASS)
	label.add_theme_color_override("font_shadow_color", Color(GLOW, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 0)
	label.add_theme_constant_override("shadow_outline_size", maxi(6, size / 6))
	label.add_theme_constant_override("outline_size", 0)
	label.text = label.text.to_upper()


## A section heading: small, wide, glowing capitals.
func style_heading(label: Label, size := 16) -> void:
	label.add_theme_font_override("font", heading_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GLOW)
	# Microgramma-style headings read best in capitals (display only; text is unchanged).
	label.uppercase = true


## A variable font at a given weight (100 thin to 900 black).
static func _weighted(font: FontFile, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return variation


## The licensed font for [param role] if one was dropped in, else [param fallback].
func _licensed(role: String, fallback: Font) -> Font:
	for extension in [".ttf", ".otf"]:
		if ResourceLoader.exists(LICENSED_DIR + role + extension):
			return load(LICENSED_DIR + role + extension)
	return fallback
