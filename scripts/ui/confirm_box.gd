class_name ConfirmBox
extends Control
## "Are you sure?" over everything else, for actions that throw work away
## (restarting or quitting a match). Esc or No backs out; keyboard and
## gamepad can answer it. Works while the game is paused.

signal answered(confirmed: bool)

var yes_button: Button
var no_button: Button


## Shows [param question] over [param parent]; calls [param on_yes] if confirmed.
static func ask(parent: Node, question: String, yes_text: String, on_yes: Callable) -> ConfirmBox:
	var box := ConfirmBox.new()
	box._build(question, yes_text)
	box.answered.connect(func(confirmed: bool) -> void:
		if confirmed:
			on_yes.call())
	parent.add_child(box)
	box.no_button.grab_focus.call_deferred()
	return box


func _build(question: String, yes_text: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(380, 0)
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var label := Label.new()
	label.text = question
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	yes_button = Button.new()
	yes_button.text = yes_text
	yes_button.custom_minimum_size = Vector2(150, 42)
	yes_button.pressed.connect(_answer.bind(true))
	row.add_child(yes_button)
	no_button = Button.new()
	no_button.text = "Cancel"
	no_button.custom_minimum_size = Vector2(150, 42)
	no_button.pressed.connect(_answer.bind(false))
	row.add_child(no_button)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_answer(false)
	# Nothing behind the box reacts while it's open.
	get_viewport().set_input_as_handled()


func _answer(confirmed: bool) -> void:
	answered.emit(confirmed)
	queue_free()
