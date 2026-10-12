class_name OptionsMenu
extends Control
## The Options screen, opened from the main menu or the pause menu: sound,
## display, controls (camera and key bindings) and accessibility. Every
## change applies at once and is saved (see the Settings autoload).
## Works with mouse, keyboard or gamepad; Esc or Done closes it.

signal closed()

## Rebindable actions in display order: action -> label.
const ACTION_NAMES := {
	"camera_forward": "Camera forward",
	"camera_back": "Camera back",
	"camera_left": "Camera left",
	"camera_right": "Camera right",
	"camera_rotate_left": "Rotate camera left",
	"camera_rotate_right": "Rotate camera right",
	"camera_reset": "Reset camera",
	"attack_move": "Attack-move",
	"stop": "Stop",
	"hold": "Hold position",
	"patrol": "Patrol",
	"idle_henchman": "Next idle Henchman",
	"idle_building": "Next idle building",
	"jump_to_alert": "Look at last alert",
	"select_lab": "Select Lab",
	"demolish": "Demolish building",
	"deselect": "Deselect / back",
	"pause_menu": "Pause menu",
	"speed_up": "Game faster",
	"speed_down": "Game slower",
}
const UI_SCALE_NAMES := ["Smaller", "Small", "Normal", "Large", "Larger", "Largest"]
const BAR_MODES := [Settings.BARS_DAMAGED, Settings.BARS_ALWAYS]
const BAR_NAMES := ["When damaged or selected", "Always"]

var tabs: TabContainer
var master_slider: HSlider
var effects_slider: HSlider
var voice_slider: HSlider
var fullscreen_check: CheckButton
var scale_option: OptionButton
var edge_check: CheckButton
var pan_slider: HSlider
var colorblind_check: CheckButton
var bars_option: OptionButton
var done_button: Button
## Action -> its key button.
var key_buttons := {}
## The action waiting for a key press, or "".
var rebinding := ""
var _key_status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(640, 0)
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 36)
	column.add_child(title)

	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(640, 430)
	column.add_child(tabs)
	_build_sound(_page("Sound"))
	_build_display(_page("Display"))
	_build_controls(_page("Controls"))
	_build_accessibility(_page("Accessibility"))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(200, 40)
	reset.pressed.connect(func() -> void:
		ConfirmBox.ask(self, "Put every option and key back to its default?", "Reset", _reset))
	row.add_child(reset)
	done_button = Button.new()
	done_button.text = "Done"
	done_button.custom_minimum_size = Vector2(160, 40)
	done_button.pressed.connect(close)
	row.add_child(done_button)
	refresh()


func open() -> void:
	refresh()
	visible = true
	tabs.get_tab_bar().grab_focus.call_deferred()


func close() -> void:
	_stop_rebinding()
	visible = false
	closed.emit()


## Shows the current settings on every control.
func refresh() -> void:
	master_slider.set_value_no_signal(Settings.master_volume)
	effects_slider.set_value_no_signal(Settings.effects_volume)
	voice_slider.set_value_no_signal(Settings.voice_volume)
	fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	scale_option.select(maxi(Settings.UI_SCALES.find(Settings.ui_scale), 0))
	edge_check.set_pressed_no_signal(Settings.edge_scroll)
	pan_slider.set_value_no_signal(Settings.pan_speed)
	colorblind_check.set_pressed_no_signal(Settings.colorblind)
	bars_option.select(maxi(BAR_MODES.find(Settings.health_bars), 0))
	for action: String in key_buttons:
		(key_buttons[action] as Button).text = Settings.key_names(action)


func _input(event: InputEvent) -> void:
	if not visible or rebinding == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key.physical_keycode == KEY_ESCAPE:
		_stop_rebinding()
		return
	rebind(rebinding, key.physical_keycode)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		close()
	get_viewport().set_input_as_handled()


## Binds [param action] to [param keycode]; an action that used that key
## takes this action's old keys, so nothing is left without a key.
func rebind(action: String, keycode: Key) -> void:
	var other := Settings.action_for_key(keycode)
	var old: Array = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			old.append((event as InputEventKey).physical_keycode)
	Settings.bind(action, [keycode])
	if other != "" and other != action:
		Settings.bind(other, old)
		_set_status("%s now uses %s" % [ACTION_NAMES.get(other, other), Settings.key_names(other)])
	else:
		_set_status("")
	_stop_rebinding()
	refresh()


func _start_rebinding(action: String) -> void:
	_stop_rebinding()
	rebinding = action
	(key_buttons[action] as Button).text = "Press a key… (Esc: cancel)"


func _stop_rebinding() -> void:
	if rebinding != "" and key_buttons.has(rebinding):
		(key_buttons[rebinding] as Button).text = Settings.key_names(rebinding)
	rebinding = ""


func _reset() -> void:
	Settings.reset_to_defaults()
	_set_status("")
	refresh()


## Shows a note under the key list (hidden while empty).
func _set_status(note: String) -> void:
	_key_status.text = note
	_key_status.visible = note != ""


# --- Pages --------------------------------------------------------------------

func _page(page_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	return page


func _build_sound(page: VBoxContainer) -> void:
	master_slider = _slider(page, "Master volume", 0.0, 1.0, func(v: float) -> void: Settings.set_value("master_volume", v))
	effects_slider = _slider(page, "Effects", 0.0, 1.0, func(v: float) -> void: Settings.set_value("effects_volume", v))
	voice_slider = _slider(page, "Creature voices", 0.0, 1.0, func(v: float) -> void:
		Settings.set_value("voice_volume", v)
		Sfx.play("select"))


func _build_display(page: VBoxContainer) -> void:
	fullscreen_check = _check(page, "Fullscreen", func(on: bool) -> void: Settings.set_value("fullscreen", on))
	scale_option = _choice(page, "Interface size", UI_SCALE_NAMES, func(index: int) -> void:
		Settings.set_value("ui_scale", Settings.UI_SCALES[index]))
	_note(page, "The interface also grows and shrinks with the window.")


func _build_controls(page: VBoxContainer) -> void:
	edge_check = _check(page, "Scroll at screen edges", func(on: bool) -> void: Settings.set_value("edge_scroll", on))
	pan_slider = _slider(page, "Camera speed", 0.4, 2.0, func(v: float) -> void: Settings.set_value("pan_speed", v))
	var heading := Label.new()
	heading.text = "Keys"
	UiTheme.style_heading(heading)
	page.add_child(heading)
	_note(page, "Click a key, then press the new one. Control groups (1-9) and the command panel keys stay fixed.")
	_key_status = Label.new()
	_key_status.add_theme_color_override("font_color", UiTheme.WARNING)
	_key_status.visible = false
	page.add_child(_key_status)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	page.add_child(grid)
	for action: String in ACTION_NAMES:
		if not InputMap.has_action(action):
			continue
		var label := Label.new()
		label.text = ACTION_NAMES[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(240, 34)
		button.pressed.connect(_start_rebinding.bind(action))
		grid.add_child(button)
		key_buttons[action] = button


func _build_accessibility(page: VBoxContainer) -> void:
	colorblind_check = _check(page, "Colour-blind friendly team colours", func(on: bool) -> void: Settings.set_value("colorblind", on))
	_note(page, "You stay blue, allies turn light blue or teal, and enemies orange, yellow, violet or white.")
	bars_option = _choice(page, "Health bars", BAR_NAMES, func(index: int) -> void:
		Settings.set_value("health_bars", BAR_MODES[index]))
	_note(page, "Enemy health bars carry a small pointer, so they can be told apart without colour.")


# --- Controls -----------------------------------------------------------------

func _slider(page: VBoxContainer, text: String, low: float, high: float, on_change: Callable) -> HSlider:
	var row := _row(page, text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(260, 28)
	var readout := Label.new()
	readout.custom_minimum_size.x = 56
	readout.add_theme_color_override("font_color", UiTheme.GLOW)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%d%%" % roundi(v * 100.0)
		on_change.call(v))
	slider.changed.connect(func() -> void: readout.text = "%d%%" % roundi(slider.value * 100.0))
	row.add_child(slider)
	row.add_child(readout)
	# set_value_no_signal() doesn't update the readout, so keep it in step.
	slider.draw.connect(func() -> void: readout.text = "%d%%" % roundi(slider.value * 100.0))
	return slider


func _check(page: VBoxContainer, text: String, on_toggle: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.toggled.connect(on_toggle)
	page.add_child(check)
	return check


func _choice(page: VBoxContainer, text: String, names: Array, on_select: Callable) -> OptionButton:
	var row := _row(page, text)
	var option := OptionButton.new()
	for choice_name: String in names:
		option.add_item(choice_name)
	option.custom_minimum_size = Vector2(260, 34)
	option.item_selected.connect(on_select)
	row.add_child(option)
	return option


func _row(page: VBoxContainer, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	page.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 220
	row.add_child(label)
	return row


func _note(page: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 15)
	page.add_child(label)
