extends Control
## Title screen: start a skirmish or open the creature combiner.

const SETUP_SCENE := "res://scenes/ui/skirmish_setup.tscn"
const COMBINER_SCENE := "res://scenes/ui/combiner.tscn"


func _ready() -> void:
	add_child(DecoBackdrop.new())

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := Label.new()
	title.text = "IMPOSSIBLE CREATURES"
	UiTheme.style_title(title, 72)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "fan remake  ·  prototype"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_heading(subtitle, 18)
	column.add_child(subtitle)
	column.add_child(Control.new())

	_add_button(column, "Play Skirmish", func() -> void: get_tree().change_scene_to_file(SETUP_SCENE))
	_add_button(column, "Creature Combiner", func() -> void: get_tree().change_scene_to_file(COMBINER_SCENE))
	_add_button(column, "Quit", func() -> void: get_tree().quit())


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(action)
	parent.add_child(button)
