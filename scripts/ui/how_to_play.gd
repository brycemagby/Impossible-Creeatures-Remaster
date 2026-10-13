class_name HowToPlay
extends Control
## A short guide from the main menu: the goal, the camera, giving orders,
## the economy and the combiner. Keys come from the current bindings, so the
## page stays right after the player rebinds them. Esc or Close shuts it.

signal closed()

var text: RichTextLabel
var close_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.85)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 36)
	column.add_child(title)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(720, 460)
	text.focus_mode = Control.FOCUS_ALL
	text.add_theme_color_override("default_color", UiTheme.TEXT)
	column.add_child(text)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(160, 40)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(close)
	column.add_child(close_button)


func open() -> void:
	text.text = guide()
	text.scroll_to_line(0)
	visible = true
	close_button.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	get_viewport().set_input_as_handled()


## The guide's text (BBCode), with the current key bindings filled in.
func guide() -> String:
	var heading := "[color=#%s][b]%s[/b][/color]\n"
	var glow := UiTheme.GLOW.to_html(false)
	var parts := PackedStringArray()
	parts.append(heading % [glow, "The goal"])
	parts.append("Destroy every enemy building. Your Henchmen gather coal and build; your Creature Chamber turns coal and electricity into hybrid creatures you design in the Creature Combiner.\n")
	parts.append(heading % [glow, "Camera"])
	parts.append("Move: %s, or push the mouse to a screen edge, or drag with the middle mouse button.\nRotate: %s / %s.  Zoom: mouse wheel.  Reset: %s.\n" % [
			_keys("camera_forward"), _keys("camera_rotate_left"), _keys("camera_rotate_right"), _keys("camera_reset")])
	parts.append(heading % [glow, "Selecting and orders"])
	parts.append("Left click or drag to select; Shift adds. Double click selects every creature of that type on screen.\nRight click to move, attack or gather coal; Shift + right click queues orders.\nAttack-move: %s.  Patrol: %s.  Hold: %s.  Stop: %s.\nCtrl + 1-9 makes a control group; 1-9 selects it again (twice to look at it).\n" % [
			_keys("attack_move"), _keys("patrol"), _keys("hold"), _keys("stop")])
	parts.append(heading % [glow, "Economy and building"])
	parts.append("Select Henchmen and pick a building from the command panel (each button shows its key). Houses raise your population limit, Generators make electricity, research at the Lab unlocks stronger creatures.\nNext idle Henchman: %s.  Next idle building: %s.  Select Lab: %s.\n" % [
			_keys("idle_henchman"), _keys("idle_building"), _keys("select_lab")])
	parts.append(heading % [glow, "Alerts"])
	parts.append("When something of yours is attacked a klaxon sounds, a message appears and the spot flashes on the minimap. Press %s to look there.\n" % _keys("jump_to_alert"))
	parts.append(heading % [glow, "Help while playing"])
	parts.append("Hover over any button, the selection readout or the minimap for its controls. Pause with %s; game speed with %s / %s.\nKeys, sound, interface size and colour-blind colours are under Options." % [
			_keys("pause_menu"), _keys("speed_down"), _keys("speed_up")])
	return "\n".join(parts)


func _keys(action: String) -> String:
	return "[b]%s[/b]" % Settings.key_names(action)
