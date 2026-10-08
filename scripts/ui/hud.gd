extends Control
## HUD: resources, selection info, the command panel (build menu for
## Henchmen, production for buildings), messages and the game-over banner.

const MESSAGE_TIME := 2.5

@export var selection_manager: SelectionManager
@export var game_rules: GameRules

var _context := "none"
## [Button, coal cost, electricity cost] for refreshing disabled states.
var _cost_buttons: Array = []
var _message_timer := 0.0

@onready var selection_label: Label = $SelectionLabel
var resource_label: Label
var command_panel: PanelContainer
var command_title: Label
var command_grid: GridContainer
var command_status: Label
var message_label: Label
var game_over_label: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_layout()
	game_rules.game_over.connect(_on_game_over)


func _process(delta: float) -> void:
	var team := selection_manager.player_team
	resource_label.text = "Coal  %d      Electricity  %d" % [Economy.coal(team), Economy.electricity(team)]
	selection_label.text = _describe_selection()
	_refresh_command_panel()
	_message_timer -= delta
	message_label.visible = _message_timer > 0.0


func show_message(text: String) -> void:
	message_label.text = text
	_message_timer = MESSAGE_TIME


# --- Selection text -----------------------------------------------------------

func _describe_selection() -> String:
	var lines := PackedStringArray()
	if selection_manager.build_placer.is_active():
		lines.append("PLACING %s: left click to build (Shift: keep placing), right click / Esc to cancel"
				% selection_manager.build_placer.data.display_name.to_upper())
	elif selection_manager.attack_move_armed:
		lines.append("ATTACK-MOVE: left click a target  (right click / Esc to cancel)")

	var building := selection_manager.selected_building
	var alive := selection_manager.selected.filter(func(u: Creature) -> bool: return Creature.is_valid_target(u))
	if Creature.is_valid_target(building):
		lines.append(building.data.display_name)
		lines.append("  Health  %d / %d    Armor  %d" % [ceili(building.health), building.data.max_health, building.data.armor])
		if building.is_complete:
			lines.append("  Right click: set rally point")
	elif alive.is_empty():
		lines.append("No units selected")
	elif alive.size() == 1:
		var unit: Creature = alive[0]
		var s := unit.stats
		lines.append(s.display_name)
		lines.append("  Health  %d / %d" % [ceili(unit.health), s.max_health])
		lines.append("  Damage  %d every %.1fs (%s)" % [s.attack_damage, s.attack_cooldown,
				"ranged %dm" % s.attack_range if s.is_ranged() else "melee"])
		lines.append("  Armor   %d    Speed  %.1f" % [s.armor, s.move_speed])
		var traits := PackedStringArray()
		if s.design != null:
			traits.append("Level %d" % s.level)
		if s.can_fly:
			traits.append("Flying")
		if s.poison_dps > 0.0:
			traits.append("Poison")
		if unit.is_poisoned():
			traits.append("POISONED")
		if not traits.is_empty():
			lines.append("  " + "  ".join(traits))
		if unit is Henchman:
			lines.append("  Carrying  %d coal" % unit.carried_coal)
	else:
		var counts := {}
		for unit: Creature in alive:
			counts[unit.stats.display_name] = counts.get(unit.stats.display_name, 0) + 1
		lines.append("Selected: %d" % alive.size())
		for unit_name: String in counts:
			lines.append("  %dx %s" % [counts[unit_name], unit_name])
	return "\n".join(lines)


# --- Command panel ------------------------------------------------------------

func _refresh_command_panel() -> void:
	var building := selection_manager.selected_building
	var context := "none"
	if Creature.is_valid_target(building):
		context = "building:%d:%s" % [building.get_instance_id(), building.is_complete]
	elif not selection_manager.selected_henchmen().is_empty():
		context = "henchmen"
	if context != _context:
		_context = context
		_rebuild_command_panel(building)

	var team := selection_manager.player_team
	for entry in _cost_buttons:
		entry[0].disabled = not Economy.can_afford(team, entry[1], entry[2])
	if context.begins_with("building"):
		command_status.text = _building_status(building)


func _rebuild_command_panel(building: Building) -> void:
	for child in command_grid.get_children():
		child.queue_free()
	_cost_buttons.clear()
	command_status.text = ""
	command_panel.visible = _context != "none"

	if _context == "henchmen":
		command_title.text = "Build"
		for data in selection_manager.buildable:
			var button := _add_button("%s\n%s" % [data.display_name, _cost_text(data.cost_coal, data.cost_electricity)])
			button.pressed.connect(selection_manager.begin_placement.bind(data))
			_cost_buttons.append([button, data.cost_coal, data.cost_electricity])
	elif _context.begins_with("building"):
		command_title.text = building.data.display_name
		if building.is_complete:
			var options := building.production_options()
			for recipe in options:
				var button := _add_button("%s\n%s" % [recipe.display_name(), _cost_text(recipe.cost_coal, recipe.cost_electricity)])
				button.pressed.connect(_on_produce_pressed.bind(building, recipe))
				button.tooltip_text = _recipe_tooltip(recipe)
				_cost_buttons.append([button, recipe.cost_coal, recipe.cost_electricity])
			if not options.is_empty():
				var cancel := _add_button("Cancel\nlast")
				cancel.pressed.connect(building.cancel_last)
		command_status.text = _building_status(building)


func _building_status(building: Building) -> String:
	if not building.is_complete:
		return "Under construction  %d%%" % roundi(building.build_progress * 100.0)
	var lines := PackedStringArray()
	if building.data.electricity_per_second > 0.0:
		lines.append("Producing %.1f electricity / s" % building.data.electricity_per_second)
	if not building.queue.is_empty():
		lines.append("Making %s  %d%%" % [building.queue[0].display_name(), roundi(building.production_fraction() * 100.0)])
		if building.queue.size() > 1:
			var waiting := PackedStringArray()
			for recipe in building.queue.slice(1):
				waiting.append(recipe.display_name())
			lines.append("Queued: " + ", ".join(waiting))
	elif not building.production_options().is_empty():
		lines.append("Idle")
	return "\n".join(lines)


func _recipe_tooltip(recipe: UnitRecipe) -> String:
	var s := recipe.stats
	return "%s (level %d)\nHealth %d  Armor %d  Speed %.1f\nDamage %.0f%s%s%s" % [
		s.display_name, s.level, s.max_health, s.armor, s.move_speed, s.attack_damage,
		"  ranged" if s.is_ranged() else "", "  poison" if s.poison_dps > 0.0 else "",
		"  flying" if s.can_fly else ""]


func _on_produce_pressed(building: Building, recipe: UnitRecipe) -> void:
	var error := building.enqueue(recipe)
	if error != "":
		show_message(error)


func _on_game_over(winner: int) -> void:
	game_over_label.text = "VICTORY" if winner == selection_manager.player_team else "DEFEAT"
	game_over_label.visible = true


func _cost_text(coal: int, electricity: int) -> String:
	return "%dc" % coal + ("  %de" % electricity if electricity > 0 else "")


func _add_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(120, 52)
	command_grid.add_child(button)
	return button


# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	resource_label = _make_label(20)
	resource_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	resource_label.offset_top = 10
	resource_label.offset_right = -16
	resource_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	message_label = _make_label(20)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_top = 120
	message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	message_label.visible = false

	game_over_label = _make_label(72)
	game_over_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	game_over_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	game_over_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.visible = false

	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_button.offset_top = 44
	menu_button.offset_right = -16
	menu_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	add_child(menu_button)

	command_panel = PanelContainer.new()
	command_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	command_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	command_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	command_panel.offset_right = -16
	command_panel.offset_bottom = -16
	command_panel.visible = false
	add_child(command_panel)
	var column := VBoxContainer.new()
	command_panel.add_child(column)
	command_title = Label.new()
	column.add_child(command_title)
	command_grid = GridContainer.new()
	command_grid.columns = 4
	column.add_child(command_grid)
	command_status = Label.new()
	column.add_child(command_status)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 5))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
