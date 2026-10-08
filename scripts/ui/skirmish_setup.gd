class_name SkirmishSetup
extends Control
## Pick the map, how many players (and free-for-all or 2 vs 2), the computer
## opponents' difficulty and whether fog of war is on, then start the match.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var map_list: ItemList
var description: Label
var difficulty_option: OptionButton
var players_option: OptionButton
var mode_option: OptionButton
var fog_check: CheckBox


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.12, 0.1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var title := Label.new()
	title.text = "SKIRMISH"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	column.add_child(title)

	column.add_child(_heading("Map"))
	map_list = ItemList.new()
	map_list.auto_height = true
	for map in GameSettings.MAPS:
		map_list.add_item(map.name)
	map_list.item_selected.connect(select_map)
	column.add_child(map_list)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	column.add_child(description)

	column.add_child(_heading("Players"))
	var player_row := HBoxContainer.new()
	column.add_child(player_row)
	players_option = OptionButton.new()
	players_option.custom_minimum_size.x = 160
	players_option.item_selected.connect(func(index: int) -> void: set_player_count(players_option.get_item_id(index)))
	player_row.add_child(players_option)
	mode_option = OptionButton.new()
	for mode_name in GameSettings.MODE_NAMES:
		mode_option.add_item(mode_name)
	mode_option.item_selected.connect(func(index: int) -> void: GameSettings.mode = index)
	player_row.add_child(mode_option)

	column.add_child(_heading("Computer difficulty"))
	difficulty_option = OptionButton.new()
	for difficulty_name in GameSettings.DIFFICULTY_NAMES:
		difficulty_option.add_item(difficulty_name)
	difficulty_option.item_selected.connect(func(index: int) -> void: GameSettings.difficulty = index)
	column.add_child(difficulty_option)

	fog_check = CheckBox.new()
	fog_check.text = "Fog of war"
	fog_check.toggled.connect(func(on: bool) -> void: GameSettings.fog_enabled = on)
	column.add_child(fog_check)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 44)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	buttons.add_child(back)
	var start := Button.new()
	start.text = "Start"
	start.custom_minimum_size = Vector2(140, 44)
	start.pressed.connect(start_match)
	buttons.add_child(start)

	select_map(GameSettings.map_index)
	difficulty_option.select(GameSettings.difficulty)
	fog_check.button_pressed = GameSettings.fog_enabled


func select_map(index: int) -> void:
	GameSettings.select_map(index)
	map_list.select(index)
	description.text = GameSettings.MAPS[index].description
	players_option.clear()
	for count in range(2, GameSettings.max_players() + 1):
		players_option.add_item("%d players" % count, count)
	players_option.select(GameSettings.player_count - 2)
	_refresh_mode()


func set_player_count(count: int) -> void:
	GameSettings.player_count = count
	if not GameSettings.teams_available():
		GameSettings.mode = GameSettings.Mode.FREE_FOR_ALL
	_refresh_mode()


func _refresh_mode() -> void:
	mode_option.disabled = not GameSettings.teams_available()
	mode_option.select(GameSettings.mode)


func start_match() -> void:
	get_tree().change_scene_to_file(GameSettings.map_path())


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	return label
