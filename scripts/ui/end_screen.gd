class_name EndScreen
extends Control
## Shown when the match ends: the result, match time, and each side's
## statistics, with buttons to play again or return to the main menu.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var title: Label
var time_label: Label
var table: GridContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BACKDROP, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(520, 0)
	column.add_theme_constant_override("separation", 12)
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(padding)
	padding.add_child(column)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 60)
	column.add_child(title)
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(time_label)
	table = GridContainer.new()
	table.add_theme_constant_override("h_separation", 28)
	column.add_child(table)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	_button(buttons, "Play again", func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene())
	_button(buttons, "Main menu", func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(MENU_SCENE))


## Shows the results and pauses the game.
func show_results(winner: int, player_team: int) -> void:
	MatchStats.stop()
	var won := winner == Teams.alliance(player_team)
	title.text = "VICTORY" if won else "DEFEAT"
	title.add_theme_color_override("font_color", UiTheme.BRASS if won else UiTheme.DANGER)
	title.add_theme_color_override("font_shadow_color", Color(UiTheme.GLOW if won else UiTheme.DANGER, 0.35))
	var seconds := int(MatchStats.elapsed)
	time_label.text = "Match time  %d:%02d" % [seconds / 60, seconds % 60]

	for child in table.get_children():
		child.queue_free()
	var teams: Array = MatchStats.teams()
	teams.sort()
	teams.erase(player_team)
	teams.push_front(player_team)
	table.columns = teams.size() + 1
	_cell("")
	for team: int in teams:
		_cell(_team_label(team, player_team, teams.size()), true)
	for key: String in MatchStats.LABELS:
		_cell(MatchStats.LABELS[key])
		for team: int in teams:
			_cell(str(int(MatchStats.get_stat(team, key))))
	_cell("Research level")
	for team: int in teams:
		_cell(str(Research.level(team)))
	visible = true
	get_tree().paused = true


## The value shown for [param key] and [param team] (for tests).
func cell_text(row: int, column: int) -> String:
	var cells := table.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	return cells[row * table.columns + column].text


static func _team_label(team: int, player_team: int, team_count: int) -> String:
	if team == player_team:
		return "You"
	if Teams.are_allies(team, player_team):
		return "Ally"
	return "Enemy" if team_count == 2 else "Enemy %d" % (team + 1)


func _cell(text: String, heading := false) -> void:
	var label := Label.new()
	label.text = text
	if heading:
		UiTheme.style_heading(label, 16)
	table.add_child(label)


func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(160, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
