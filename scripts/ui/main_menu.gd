extends Control
## Title screen: start a skirmish or open the creature combiner.

const GAME_SCENE := "res://scenes/main.tscn"
const COMBINER_SCENE := "res://scenes/ui/combiner.tscn"


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.12, 0.1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	var title := Label.new()
	title.text = "IMPOSSIBLE CREATURES"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "fan remake  ·  prototype"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	column.add_child(subtitle)
	column.add_child(Control.new())

	_add_button(column, "Play Skirmish", func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	_add_button(column, "Creature Combiner", func() -> void: get_tree().change_scene_to_file(COMBINER_SCENE))
	_add_button(column, "Quit", func() -> void: get_tree().quit())


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	parent.add_child(button)
