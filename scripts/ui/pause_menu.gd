class_name PauseMenu
extends Control
## Pause menu (F10, Esc with nothing selected, or the HUD's Menu button):
## resume, restart, change game speed, or quit to the main menu.
## The - and = keys change game speed during play.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SPEEDS := [0.5, 1.0, 1.5, 2.0]

var _speed_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 10)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(padding)
	padding.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 36)
	column.add_child(title)
	_button(column, "Resume", close)
	_button(column, "Restart match", restart)

	var speed_label := Label.new()
	speed_label.text = "Game speed"
	UiTheme.style_heading(speed_label)
	column.add_child(speed_label)
	var speeds := HBoxContainer.new()
	column.add_child(speeds)
	var group := ButtonGroup.new()
	for speed: float in SPEEDS:
		var button := Button.new()
		button.text = "%sx" % speed
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(72, 36)
		button.pressed.connect(set_speed.bind(speed))
		speeds.add_child(button)
		_speed_buttons.append(button)
	_button(column, "Quit to main menu", quit_to_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") or (visible and event.is_action_pressed("deselect")):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_up"):
		step_speed(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_down"):
		step_speed(-1)
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh_speed_buttons()


func close() -> void:
	visible = false
	get_tree().paused = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func set_speed(speed: float) -> void:
	GameSettings.game_speed = speed
	Engine.time_scale = speed
	_refresh_speed_buttons()


## Moves the game speed one step up (1) or down (-1).
func step_speed(direction: int) -> void:
	var index := SPEEDS.find(GameSettings.game_speed)
	if index < 0:
		index = SPEEDS.find(1.0)
	set_speed(SPEEDS[clampi(index + direction, 0, SPEEDS.size() - 1)])


func restart() -> void:
	close()
	get_tree().reload_current_scene()


func quit_to_menu() -> void:
	close()
	get_tree().change_scene_to_file(MENU_SCENE)


func _refresh_speed_buttons() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(is_equal_approx(SPEEDS[i], GameSettings.game_speed))


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
