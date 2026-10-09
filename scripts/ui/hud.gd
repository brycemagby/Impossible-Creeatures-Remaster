extends Control
## HUD: resources, selection info, the command panel (build menu for
## Henchmen, production for buildings), messages and the game-over banner.

const MESSAGE_TIME := 2.5
## Command panel hotkeys, in button order (keys the camera and orders don't use).
const HOTKEYS: Array[Key] = [KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M,
		KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_J, KEY_K, KEY_L]
## How many units Shift + click queues at once.
const BATCH_SIZE := 5

@export var selection_manager: SelectionManager
@export var game_rules: GameRules

var _context := "none"
## [Button, coal cost, electricity cost, research level needed] for refreshing
## disabled states.
var _cost_buttons: Array = []
var _message_timer := 0.0
## True while a Shift + hotkey press is being handled.
var _hotkey_shift := false

@onready var selection_label: Label = $SelectionLabel
var resource_label: Label
var command_panel: PanelContainer
var command_title: Label
var command_grid: GridContainer
var command_status: Label
var message_label: Label
var pause_menu: PauseMenu
var end_screen: EndScreen


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_layout()
	game_rules.game_over.connect(_on_game_over)
	selection_manager.menu_requested.connect(pause_menu.open)
	selection_manager.message.connect(show_message)
	Alerts.raised.connect(_on_alert)


func _process(delta: float) -> void:
	var team := selection_manager.player_team
	resource_label.text = "Coal  %d      Electricity  %d      Pop  %d / %d      Research  L%d" % [
			Economy.coal(team), Economy.electricity(team), Population.used(team), Population.cap(team), Research.level(team)]
	_warn_if_population_blocked(team)
	if not is_equal_approx(Engine.time_scale, 1.0):
		resource_label.text += "      Speed  %sx" % Engine.time_scale
	selection_label.text = _describe_selection()
	_refresh_command_panel()
	_message_timer -= delta
	message_label.visible = _message_timer > 0.0


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.ctrl_pressed or not command_panel.visible:
		return
	var index := HOTKEYS.find(key.physical_keycode)
	if index < 0:
		return
	var buttons := command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	if index < buttons.size() and not buttons[index].disabled:
		_hotkey_shift = key.shift_pressed
		buttons[index].pressed.emit()
		_hotkey_shift = false
		get_viewport().set_input_as_handled()


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
	elif selection_manager.targeting_order == SelectionManager.PATROL:
		lines.append("PATROL: left click the other end of the route  (right click / Esc to cancel)")

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
		lines.append("  Damage  %d every %.1fs (%s)" % [unit.attack_damage(), s.attack_cooldown,
				"ranged %dm" % s.attack_range if s.is_ranged() else "melee"])
		lines.append("  Armor   %d melee / %d ranged    Speed  %.1f" % [unit.armor(), unit.ranged_armor(), unit.move_speed()])
		if unit.order == Creature.Order.HOLD:
			lines.append("  Holding position")
		elif unit.order == Creature.Order.PATROL:
			lines.append("  Patrolling")
		var traits := PackedStringArray()
		if s.design != null:
			traits.append("Level %d" % s.level)
		if s.can_fly:
			traits.append("Flying")
		if s.poison_dps > 0.0:
			traits.append("Poison")
		if s.can_charge:
			traits.append("Charge")
		if s.can_leap:
			traits.append("Leap")
		if s.has_sonic:
			traits.append("Sonic")
		if s.pack_hunter:
			traits.append("Pack x%d" % unit.packmates() if unit.packmates() > 0 else "Pack")
		if s.has_frenzy:
			traits.append("FRENZIED" if unit.is_frenzied() else "Frenzy")
		if s.has_trample:
			traits.append("Trample")
		if s.water_only:
			traits.append("Water only")
		elif s.can_swim:
			traits.append("SWIMMING" if unit.is_in_water() else "Amphibious")
		if s.has_electric:
			traits.append("Electric")
		if unit.is_stunned():
			traits.append("STUNNED")
		if s.has_stink:
			traits.append("Stink")
		if s.herding:
			traits.append("Herd x%d" % unit.herd_mates() if unit.herd_mates() > 0 else "Herding")
		if s.has_camouflage:
			traits.append("CAMOUFLAGED" if unit.is_camouflaged() else "Camouflage")
		if unit.is_stunk():
			traits.append("STUNK")
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
		context = "building:%d:%s:%d:%d:%s:%d" % [building.get_instance_id(), building.is_complete,
				Research.level(building.team), building.researching, building.upgrading != null,
				_owned_upgrades(building.team)]
	elif not selection_manager.selected_henchmen().is_empty():
		context = "henchmen:%d" % Research.level(selection_manager.player_team)
	if context != _context:
		_context = context
		_rebuild_command_panel(building)

	var team := selection_manager.player_team
	for entry in _cost_buttons:
		entry[0].disabled = not Economy.can_afford(team, entry[1], entry[2]) or Research.level(team) < entry[3]
	if context.begins_with("building"):
		command_status.text = _building_status(building)


func _rebuild_command_panel(building: Building) -> void:
	for child in command_grid.get_children():
		child.queue_free()
	_cost_buttons.clear()
	command_status.text = ""
	command_panel.visible = _context != "none"

	if _context.begins_with("henchmen"):
		command_title.text = "Build"
		var has_water := not get_tree().get_nodes_in_group("deep_water").is_empty()
		for data in selection_manager.buildable:
			# Shore buildings only on maps with water.
			if data.needs_shore and not has_water:
				continue
			var locked := Research.level(selection_manager.player_team) < data.required_research
			var button := _add_button("%s\n%s" % [data.display_name, "needs research L%d" % data.required_research if locked
					else _cost_text(data.cost_coal, data.cost_electricity)])
			button.pressed.connect(selection_manager.begin_placement.bind(data))
			_cost_buttons.append([button, data.cost_coal, data.cost_electricity, data.required_research])
	elif _context.begins_with("building"):
		command_title.text = building.data.display_name
		if building.is_complete:
			var options := building.production_options()
			for recipe in options:
				var locked := not Research.can_produce(building.team, recipe)
				var label := "%s  L%d" % [recipe.display_name(), recipe.stats.level] if recipe.stats.design else recipe.display_name()
				var button := _add_button("%s\n%s" % [label, "needs research L%d" % recipe.stats.level if locked
						else _cost_text(recipe.cost_coal, recipe.cost_electricity)])
				button.pressed.connect(_on_produce_pressed.bind(building, recipe))
				button.tooltip_text = _recipe_tooltip(recipe)
				var needed: int = recipe.stats.level if recipe.stats.design else 0
				_cost_buttons.append([button, recipe.cost_coal, recipe.cost_electricity, needed])
			if not options.is_empty():
				var cancel := _add_button("Cancel\nlast")
				cancel.pressed.connect(building.cancel_last)
			for upgrade in building.data.upgrades:
				if Upgrades.has(building.team, upgrade.id):
					continue
				if upgrade.requires != &"" and not Upgrades.has(building.team, upgrade.requires):
					continue
				var upgrade_locked := Research.level(building.team) < upgrade.required_research
				var upgrade_button := _add_button("%s\n%s" % [upgrade.display_name, "needs research L%d" % upgrade.required_research
						if upgrade_locked else _cost_text(upgrade.cost_coal, upgrade.cost_electricity)])
				upgrade_button.tooltip_text = upgrade.description
				upgrade_button.pressed.connect(_on_upgrade_pressed.bind(building, upgrade))
				if building.upgrading != null:
					upgrade_button.disabled = true
				else:
					_cost_buttons.append([upgrade_button, upgrade.cost_coal, upgrade.cost_electricity, upgrade.required_research])
			if building.upgrading != null:
				var stop_upgrade := _add_button("Cancel\nupgrade")
				stop_upgrade.pressed.connect(building.cancel_upgrade)
			if building.data.can_research:
				var next := Research.next_level(building.team)
				if building.researching > 0:
					var stop := _add_button("Cancel\nresearch")
					stop.pressed.connect(building.cancel_research)
				elif next > 0:
					var research := _add_button("Research L%d\n%s" % [next,
							_cost_text(Research.coal_cost(next), Research.electricity_cost(next))])
					research.tooltip_text = "Unlocks level %d creatures. Takes %ds." % [next, Research.duration(next)]
					research.pressed.connect(_on_research_pressed.bind(building))
					_cost_buttons.append([research, Research.coal_cost(next), Research.electricity_cost(next), 0])
		command_status.text = _building_status(building)


func _building_status(building: Building) -> String:
	if not building.is_complete:
		return "Under construction  %d%%" % roundi(building.build_progress * 100.0)
	var lines := PackedStringArray()
	if building.data.electricity_per_second > 0.0:
		lines.append("Producing %.1f electricity / s" % building.data.electricity_per_second)
	if building.researching > 0:
		lines.append("Researching level %d  %d%%" % [building.researching, roundi(building.research_fraction() * 100.0)])
	if building.upgrading != null:
		lines.append("Upgrading %s  %d%%" % [building.upgrading.display_name, roundi(building.upgrade_fraction() * 100.0)])
	elif not building.data.upgrades.is_empty():
		var owned := building.data.upgrades.filter(func(u: UpgradeData) -> bool: return Upgrades.has(building.team, u.id))
		lines.append("Upgrades bought: %d / %d" % [owned.size(), building.data.upgrades.size()])
	if building.data.attack_damage > 0.0:
		lines.append("Defends: %d damage every %.1fs, %dm range" % [building.data.attack_damage, building.data.attack_cooldown, building.data.attack_range])
	elif building.data.can_research and Research.next_level(building.team) == 0:
		lines.append("Fully researched")
	if building.data.population > 0:
		lines.append("Houses %d population" % building.data.population)
	if building.population_blocked:
		lines.append("Waiting for population room: build more Houses")
	elif not building.queue.is_empty():
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
	return "%s (level %d)\nHealth %d  Armor %d / %d ranged  Speed %.1f\nDamage %.0f%s%s%s" % [
		s.display_name, s.level, s.max_health, s.armor, s.ranged_armor, s.move_speed, s.attack_damage,
		"  ranged" if s.is_ranged() else "", "  poison" if s.poison_dps > 0.0 else "",
		"  flying" if s.can_fly else ""] + ("  charge" if s.can_charge else "") + ("  leap" if s.can_leap else "") \
		+ ("  sonic" if s.has_sonic else "") + ("  pack" if s.pack_hunter else "") + ("  frenzy" if s.has_frenzy else "") \
		+ ("  trample" if s.has_trample else "") + ("  stink" if s.has_stink else "") + ("  camouflage" if s.has_camouflage else "") + ("  herding" if s.herding else "") \
		+ ("  water only" if s.water_only else ("  amphibious" if s.can_swim else "")) + ("  electric" if s.has_electric else "")


func _on_upgrade_pressed(building: Building, upgrade: UpgradeData) -> void:
	var error := building.start_upgrade(upgrade)
	if error != "":
		show_message(error)


func _owned_upgrades(team: int) -> int:
	return Upgrades.owned(team).size()


var _was_blocked := false


## Flashes "Need more Houses" when production first gets stuck on population.
func _warn_if_population_blocked(team: int) -> void:
	var blocked := false
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.population_blocked:
			blocked = true
			break
	if blocked and not _was_blocked:
		show_message("Need more Houses (population %d / %d)" % [Population.used(team), Population.cap(team)])
	_was_blocked = blocked


func _on_research_pressed(building: Building) -> void:
	var error := building.start_research()
	if error != "":
		show_message(error)


func _on_produce_pressed(building: Building, recipe: UnitRecipe) -> void:
	var count := BATCH_SIZE if _hotkey_shift or Input.is_key_pressed(KEY_SHIFT) else 1
	var queued := 0
	for i in count:
		var error := building.enqueue(recipe)
		if error != "":
			if queued == 0:
				show_message(error)
			break
		queued += 1


func _on_alert(team: int, text: String, _where: Vector3) -> void:
	if team == selection_manager.player_team:
		show_message(text + "  (Space to look)")


func _on_game_over(winner: int) -> void:
	end_screen.show_results(winner, selection_manager.player_team)


func _cost_text(coal: int, electricity: int) -> String:
	return "%dc" % coal + ("  %de" % electricity if electricity > 0 else "")


func _add_button(text: String) -> Button:
	var button := Button.new()
	var index := command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).size()
	if index < HOTKEYS.size():
		text += "  [%s]" % OS.get_keycode_string(HOTKEYS[index])
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


	var menu_button := Button.new()
	menu_button.text = "Menu"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_button.offset_top = 44
	menu_button.offset_right = -16
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

	end_screen = EndScreen.new()
	add_child(end_screen)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	menu_button.pressed.connect(pause_menu.open)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(4, font_size / 5))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
