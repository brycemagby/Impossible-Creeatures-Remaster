class_name SelectionManager
extends Node
## Handles RTS selection and orders for the local player.
##
## - Left click: select a unit or building (Shift to add/remove units)
## - Double click or Ctrl + click: select every unit of that type on screen
## - Left drag: box select units (Shift to add)
## - Right click with units: move / attack enemy / gather coal / help build
##   (hold Shift to queue the order after the current ones)
## - Right drag with units: line them up along the drag, facing away from where
##   they are now
## - Right click with a building: set its rally point (on coal: new Henchmen gather)
## - Period: next idle Henchman; Home: next Lab; Space: jump to the latest alert
## - Clicking an enemy unit or building shows its stats (no orders)
## - Ctrl+1..9 sets a control group, Shift+1..9 adds to it, 1..9 recalls it
##   (twice quickly: centre the camera on it)
## - F then left click, or Ctrl + right click: attack-move
## - P then left click: patrol between here and there
## - G: hold position
## - H: stop
## - Ctrl+1..9: assign control group, 1..9: recall it
## - Escape: cancel placement or order targeting, otherwise deselect

signal selection_changed()
## A short message for the player, e.g. "Not enough coal".
signal message(text: String)
## Esc was pressed with nothing to cancel or deselect.
signal menu_requested()

const DRAG_THRESHOLD := 6.0
const CLICK_PICK_RADIUS := 24.0
const RAY_LENGTH := 1000.0
const GROUND_MASK := 1
const UNIT_MASK := 2
const BUILDING_MASK := 4
const RESOURCE_MASK := 8
const MOVE_COLOR := Color(0.35, 1.0, 0.4)
const ATTACK_COLOR := Color(1.0, 0.3, 0.25)
const WORK_COLOR := Color(1.0, 0.85, 0.3)
const PATROL_COLOR := Color(0.4, 0.7, 1.0)
## Orders that wait for a left click to pick their destination.
const ATTACK_MOVE := &"attack_move"
const PATROL := &"patrol"
## Two presses of a group key within this many seconds centre the camera on it.
const DOUBLE_TAP_TIME := 0.4
## A right-button drag longer than this (pixels) lines the selection up.
const LINE_DRAG_THRESHOLD := 20.0
## Gap kept between neighbours in a formation, on top of their sizes.
const FORMATION_GAP := 0.4
const MoveMarkerScene := preload("res://scenes/fx/move_marker.tscn")

@export var camera: Camera3D
@export var selection_box: SelectionBox
@export var build_placer: BuildPlacer
@export var player_team := 0
@export var formation_spacing := 1.8
## Buildings Henchmen can construct, in build-menu order.
@export var buildable: Array[BuildingData] = []

var selected: Array[Creature] = []
var selected_building: Building = null
## An enemy (or neutral) unit or building whose stats are shown, or null.
var inspected: Node3D = null
## The order waiting for a left click (ATTACK_MOVE or PATROL), or &"".
var targeting_order := &""
## True while waiting for the click that places an attack-move order.
var attack_move_armed: bool:
	get:
		return targeting_order == ATTACK_MOVE
var _control_groups := {}
var _press_position := Vector2.ZERO
var _pressing := false
var _dragging := false
var _double_click := false
var _right_pressing := false
var _right_press_position := Vector2.ZERO
var _last_group_key := -1
var _last_group_time := -1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


# --- Selection ----------------------------------------------------------------

func select_units(units: Array, additive := false) -> void:
	var result: Array[Creature] = []
	if additive:
		result = _valid_selected()
	for unit: Creature in units:
		if _is_selectable(unit) and unit not in result:
			result.append(unit)
	_set_selection(result, null)


func select_building(building: Building) -> void:
	if Creature.is_valid_target(building) and building.team == player_team:
		_set_selection([], building)


func clear_selection() -> void:
	_set_selection([], null)


## Shows [param target]'s stats (an enemy or ally) without selecting it.
func inspect(target: Node3D) -> void:
	_set_selection([], null)
	if not Creature.is_valid_target(target):
		return
	inspected = target
	target.selection_ring.visible = true
	selection_changed.emit()


## Narrows the selection to creatures named [param display_name], or with
## [param remove] drops them from it.
func select_type(display_name: String, remove := false) -> void:
	var kept := _valid_selected().filter(func(u: Creature) -> bool: return (u.stats.display_name == display_name) != remove)
	_set_selection(kept, null)


## The player's control groups: group number -> living units.
func control_groups() -> Dictionary:
	var result := {}
	for group: int in _control_groups:
		var alive: Array = _control_groups[group].filter(func(u: Variant) -> bool: return Creature.is_valid_target(u) and u.team == player_team)
		if not alive.is_empty():
			result[group] = alive
	return result


## Selects the unit or own building under [param screen_position], or clears
## the selection if there is none. With [param additive], toggles units.
func click_select(screen_position: Vector2, additive := false) -> void:
	var unit := unit_at_screen(screen_position)
	if unit == null or not _is_selectable(unit):
		var building := building_at_screen(screen_position)
		if building != null and building.team == player_team and not additive:
			select_building(building)
		elif not additive and unit != null:
			inspect(unit)
		elif not additive and building != null:
			inspect(building)
		elif not additive:
			clear_selection()
		return
	if not additive:
		_set_selection([unit], null)
	elif unit in selected:
		var remaining := _valid_selected()
		remaining.erase(unit)
		_set_selection(remaining, null)
	else:
		select_units([unit], true)


## Selects every player unit whose position projects inside [param rect].
func select_in_rect(rect: Rect2, additive := false) -> void:
	var inside: Array[Creature] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not _is_selectable(unit) or camera.is_position_behind(unit.global_position):
			continue
		if rect.has_point(camera.unproject_position(unit.global_position)):
			inside.append(unit)
	# A box over an army leaves the workers at work.
	if inside.any(func(u: Creature) -> bool: return not u is Henchman):
		inside = inside.filter(func(u: Creature) -> bool: return not u is Henchman)
	select_units(inside, additive)


## Selects every player unit of the same kind as [param unit] that is on screen.
func select_same_type(unit: Creature, additive := false) -> void:
	if not _is_selectable(unit):
		return
	var view := get_viewport().get_visible_rect()
	var matches: Array[Creature] = []
	for other: Creature in get_tree().get_nodes_in_group("units"):
		if not _is_selectable(other) or other.stats.display_name != unit.stats.display_name:
			continue
		if camera.is_position_behind(other.global_position) or not view.has_point(camera.unproject_position(other.global_position)):
			continue
		matches.append(other)
	if unit not in matches:
		matches.append(unit)
	select_units(matches, additive)


## Selects and centres on the next idle Henchman. Returns it, or null.
func select_idle_henchman() -> Henchman:
	var idle: Array = get_tree().get_nodes_in_group("units").filter(
			func(u: Creature) -> bool: return u is Henchman and _is_selectable(u) and u.is_idle() and u.queued_orders() == 0)
	if idle.is_empty():
		message.emit("No idle Henchmen")
		return null
	var henchman: Henchman = _next_after(idle, selected[0] if selected.size() == 1 else null)
	_set_selection([henchman], null)
	_focus(henchman.global_position)
	return henchman


## Selects and centres on the next of the player's Labs. Returns it, or null.
func select_next_lab() -> Building:
	var labs: Array = get_tree().get_nodes_in_group("buildings").filter(
			func(b: Building) -> bool: return b.team == player_team and b.data.can_research and b.is_alive())
	if labs.is_empty():
		return null
	var lab: Building = _next_after(labs, selected_building)
	select_building(lab)
	_focus(lab.global_position)
	return lab


## Centres the camera on the player's latest "under attack" alert.
func jump_to_alert() -> bool:
	if not Alerts.has_alert(player_team):
		return false
	_focus(Alerts.latest(player_team))
	return true


func selected_henchmen() -> Array[Henchman]:
	var result: Array[Henchman] = []
	for unit in _valid_selected():
		if unit is Henchman:
			result.append(unit)
	return result


# --- Picking ------------------------------------------------------------------

## Returns the unit under the cursor, falling back to the nearest unit within
## a small screen radius so small units are easy to click.
func unit_at_screen(screen_position: Vector2) -> Creature:
	var hit := _raycast(screen_position, UNIT_MASK)
	if hit and hit.collider is Creature and hit.collider.is_alive() and hit.collider.is_visible_in_tree():
		return hit.collider
	var best: Creature = null
	var best_distance := CLICK_PICK_RADIUS
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		# Creatures hidden by fog of war can't be clicked.
		if camera.is_position_behind(unit.global_position) or not unit.is_visible_in_tree():
			continue
		var distance := camera.unproject_position(unit.global_position).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best


func building_at_screen(screen_position: Vector2) -> Building:
	var hit := _raycast(screen_position, BUILDING_MASK)
	if hit and hit.collider is Building and hit.collider.is_alive() and hit.collider.is_visible_in_tree():
		return hit.collider
	return null


func coal_pile_at_screen(screen_position: Vector2) -> CoalPile:
	var hit := _raycast(screen_position, RESOURCE_MASK)
	return hit.collider if hit and hit.collider is CoalPile and hit.collider.is_visible_in_tree() else null


## Returns the ground point under the cursor, or null if there is none.
func ground_at_screen(screen_position: Vector2) -> Variant:
	var hit := _raycast(screen_position, GROUND_MASK)
	return hit.position if hit else null


# --- Orders -------------------------------------------------------------------

## Orders the selected units to move to [param target] in formation.
func issue_move(target: Vector3, queue := false) -> void:
	_issue_formation_order(_valid_selected(), target, &"command_move", MOVE_COLOR, queue)


## Orders the selected units to move to [param target] in formation, fighting
## any enemies they meet on the way.
func issue_attack_move(target: Vector3, queue := false) -> void:
	_issue_formation_order(_valid_selected(), target, &"command_attack_move", ATTACK_COLOR, queue)


## Orders every selected unit to attack [param target] (creature or building).
func issue_attack(target: Node3D, queue := false) -> void:
	if not Creature.is_valid_target(target) or not Teams.are_enemies(player_team, target.team):
		return
	var units := _valid_selected()
	if units.is_empty():
		return
	# A weak reference, since the target may be gone by the time a queued order runs.
	var target_ref: WeakRef = weakref(target)
	for unit in units:
		var attack := func() -> void:
			var current: Variant = target_ref.get_ref()
			if Creature.is_valid_target(current):
				unit.command_attack(current)
		_dispatch(unit, attack, queue)
	_spawn_marker(target.global_position, ATTACK_COLOR)


## Selected Henchmen gather from [param pile]; everyone else walks over.
func issue_gather(pile: CoalPile, queue := false) -> void:
	var others := _valid_selected()
	var pile_ref: WeakRef = weakref(pile)
	for henchman in selected_henchmen():
		var gather := func() -> void:
			var current: Variant = pile_ref.get_ref()
			if current != null:
				henchman.command_gather(current)
		_dispatch(henchman, gather, queue)
		others.erase(henchman)
	_issue_formation_order(others, pile.global_position, &"command_move", MOVE_COLOR, queue)
	_spawn_marker(pile.global_position, WORK_COLOR)


## Selected Henchmen help construct [param site]; everyone else walks over.
func issue_build(site: Building, queue := false) -> void:
	var others := _valid_selected()
	var site_ref: WeakRef = weakref(site)
	for henchman in selected_henchmen():
		var build := func() -> void:
			var current: Variant = site_ref.get_ref()
			if Creature.is_valid_target(current) and not current.is_complete:
				henchman.command_build(current)
		_dispatch(henchman, build, queue)
		others.erase(henchman)
	_issue_formation_order(others, site.global_position, &"command_move", MOVE_COLOR, queue)
	_spawn_marker(site.global_position, WORK_COLOR)


## Lines the selection up along [param start]-[param end] (as wide as the drag
## allows), facing away from where the group is now. Attack-moves with
## [param attack_move].
func issue_line_formation(start: Vector3, end: Vector3, attack_move := false, queue := false) -> void:
	var units := _valid_selected()
	if units.is_empty():
		return
	var spacing := formation_spacing
	var group_center := Vector3.ZERO
	for unit in units:
		spacing = maxf(spacing, unit.radius() * 2.0 + FORMATION_GAP)
		group_center += unit.global_position
	group_center /= units.size()
	var line := end - start
	line.y = 0.0
	var width := line.length()
	var columns := clampi(floori(width / spacing) + 1, 1, units.size())
	var column_spacing := width / (columns - 1) if columns > 1 else spacing
	var middle := (start + end) / 2.0
	var facing := Vector3(line.z, 0.0, -line.x).normalized()
	if facing.dot(middle - group_center) < 0.0:
		facing = -facing
	var command := &"command_attack_move" if attack_move else &"command_move"
	assign_formation(units, middle, spacing, command, queue, facing, columns, column_spacing)
	for unit in units:
		_spawn_marker(unit.get("_order_point") if not queue else middle, ATTACK_COLOR if attack_move else MOVE_COLOR)


func issue_stop() -> void:
	for unit in _valid_selected():
		unit.clear_order_queue()
		unit.command_stop()


func issue_hold() -> void:
	for unit in _valid_selected():
		unit.clear_order_queue()
		unit.command_hold()


## Orders the selected units to patrol between where they are and [param target].
func issue_patrol(target: Vector3, queue := false) -> void:
	_issue_formation_order(_valid_selected(), target, &"command_patrol", PATROL_COLOR, queue)


## Handles a right click (or attack-move click) at [param screen_position].
## With [param queue], units do it after finishing their current orders.
func issue_order_at_screen(screen_position: Vector2, attack_move := false, queue := false) -> void:
	if Creature.is_valid_target(selected_building):
		_set_rally_at_screen(screen_position)
		return
	if _valid_selected().is_empty():
		return
	var unit := unit_at_screen(screen_position)
	if unit != null and Teams.are_enemies(player_team, unit.team):
		issue_attack(unit, queue)
		return
	var building := building_at_screen(screen_position)
	if building != null:
		if Teams.are_enemies(player_team, building.team):
			issue_attack(building, queue)
			return
		if not building.is_complete and not selected_henchmen().is_empty():
			issue_build(building, queue)
			return
	if not attack_move:
		var pile := coal_pile_at_screen(screen_position)
		if pile != null:
			issue_gather(pile, queue)
			return
	var target: Variant = ground_at_screen(screen_position)
	if target == null:
		return
	if attack_move:
		issue_attack_move(target, queue)
	else:
		issue_move(target, queue)


## Orders the selection to [param point] (from the minimap): a building sets
## its rally point, units move or attack-move.
func issue_order_at_world(point: Vector3, attack_move := false) -> void:
	if Creature.is_valid_target(selected_building):
		selected_building.set_rally_point(point)
		_spawn_marker(point, MOVE_COLOR)
	elif attack_move:
		issue_attack_move(point)
	else:
		issue_move(point)


func set_attack_move_armed(armed: bool) -> void:
	set_targeting(ATTACK_MOVE if armed else &"")


## Waits for a left click to place [param order_name] (ATTACK_MOVE, PATROL),
## or stops waiting with &"".
func set_targeting(order_name: StringName) -> void:
	targeting_order = order_name if not _valid_selected().is_empty() else &""
	_update_cursor()


# --- Building placement -------------------------------------------------------

## Starts placing [param data] if Henchmen are selected and it's affordable.
func begin_placement(data: BuildingData) -> void:
	if selected_henchmen().is_empty():
		return
	var reason := Economy.shortfall(player_team, data.cost_coal, data.cost_electricity)
	if Research.level(player_team) < data.required_research:
		reason = "Requires research level %d" % data.required_research
	if reason != "":
		message.emit(reason)
		return
	targeting_order = &""
	build_placer.start(data, player_team)
	_update_cursor()


func cancel_placement() -> void:
	build_placer.cancel()
	_update_cursor()


## Places the building being positioned at [param screen_position] and sends
## the selected Henchmen to build it. Returns the site, or null.
func place_building_at_screen(screen_position: Vector2, keep_placing := false) -> Building:
	var point: Variant = ground_at_screen(screen_position)
	if point == null:
		return null
	var site := build_placer.place(point)
	if site == null:
		message.emit(build_placer.last_error)
		return null
	for henchman in selected_henchmen():
		henchman.command_build(site)
	if not keep_placing or not Economy.can_afford(player_team, build_placer.data.cost_coal, build_placer.data.cost_electricity):
		cancel_placement()
	return site


## Grid offsets for [param count] units centred on the origin, rotated so the
## grid's forward (+Z) axis points along [param yaw].
## [param columns] fixes how wide the grid is (0: roughly square), and
## [param column_spacing] the gap along a row (0: [param spacing]).
static func formation_offsets(count: int, spacing: float, yaw := 0.0, columns := 0, column_spacing := 0.0) -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	if count <= 0:
		return offsets
	if columns <= 0:
		columns = ceili(sqrt(count))
	columns = mini(columns, count)
	if column_spacing <= 0.0:
		column_spacing = spacing
	var rows := ceili(float(count) / columns)
	for i in count:
		var row := i / columns
		var column := i % columns
		var offset := Vector3(
			(column - (columns - 1) / 2.0) * column_spacing,
			0.0,
			((rows - 1) / 2.0 - row) * spacing
		)
		offsets.append(offset.rotated(Vector3.UP, yaw))
	return offsets


## Gives each unit a slot in a grid around [param target] facing the direction
## of travel, then calls [param command] (a Creature method name) with the slot
## and the group's speed (that of its slowest member).
## With [param queue], each unit queues the order instead of starting it now.
## [param facing] (if not zero) and [param columns] / [param column_spacing]
## override the direction and shape (a line from a right-drag).
static func assign_formation(units: Array, target: Vector3, spacing: float, command: StringName, queue := false,
		facing := Vector3.ZERO, columns := 0, column_spacing := 0.0) -> void:
	if units.is_empty():
		return
	var center := Vector3.ZERO
	var group_speed := INF
	for unit: Creature in units:
		center += unit.global_position
		group_speed = minf(group_speed, unit.move_speed())
		# Big creatures need a wider grid so they don't fight over slots.
		spacing = maxf(spacing, unit.radius() * 2.0 + FORMATION_GAP)
	center /= units.size()
	var direction := target - center if facing == Vector3.ZERO else facing
	direction.y = 0.0
	var yaw := atan2(direction.x, direction.z) if direction.length() > 0.1 else 0.0

	# Greedily give each formation slot to the closest remaining unit.
	var remaining := units.duplicate()
	for offset in formation_offsets(units.size(), spacing, yaw, columns, maxf(column_spacing, spacing) if column_spacing > 0.0 else 0.0):
		var slot := target + offset
		var best: Creature = null
		var best_distance := INF
		for unit: Creature in remaining:
			var distance := unit.global_position.distance_squared_to(slot)
			if distance < best_distance:
				best_distance = distance
				best = unit
		remaining.erase(best)
		_dispatch(best, Callable(best, command).bind(slot, group_speed), queue)


# --- Input handling -----------------------------------------------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed and build_placer.is_active():
				place_building_at_screen(event.position, event.shift_pressed)
				get_viewport().set_input_as_handled()
			elif event.pressed and targeting_order != &"":
				_place_targeted_order(event.position, event.shift_pressed)
				set_targeting(targeting_order if event.shift_pressed else &"")
				get_viewport().set_input_as_handled()
			elif event.pressed:
				_pressing = true
				_dragging = false
				_double_click = event.double_click
				_press_position = event.position
			elif _pressing:
				_pressing = false
				if _dragging:
					select_in_rect(_drag_rect(event.position), event.shift_pressed)
				elif _double_click or event.ctrl_pressed:
					var unit := unit_at_screen(event.position)
					if unit != null and _is_selectable(unit):
						select_same_type(unit, event.shift_pressed)
					else:
						click_select(event.position, event.shift_pressed)
				else:
					click_select(event.position, event.shift_pressed)
				_dragging = false
				selection_box.hide_box()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if build_placer.is_active():
					cancel_placement()
				elif targeting_order != &"":
					set_targeting(&"")
				else:
					_right_pressing = true
					_right_press_position = event.position
			elif _right_pressing:
				# The order goes out on release: a drag lines the group up.
				_right_pressing = false
				if event.position.distance_to(_right_press_position) > LINE_DRAG_THRESHOLD and not _valid_selected().is_empty() \
						and not Creature.is_valid_target(selected_building):
					var start: Variant = ground_at_screen(_right_press_position)
					var end: Variant = ground_at_screen(event.position)
					if start != null and end != null:
						issue_line_formation(start, end, event.ctrl_pressed, event.shift_pressed)
						return
				issue_order_at_screen(_right_press_position, event.ctrl_pressed, event.shift_pressed)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if build_placer.is_active():
		build_placer.update_ghost(ground_at_screen(event.position))
	if not _pressing:
		return
	if not _dragging and event.position.distance_to(_press_position) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		selection_box.show_box(_drag_rect(event.position))


func _handle_key(event: InputEventKey) -> void:
	if event.is_action_pressed("deselect"):
		if build_placer.is_active():
			cancel_placement()
		elif targeting_order != &"":
			set_targeting(&"")
		elif not selected.is_empty() or selected_building != null or inspected != null:
			clear_selection()
		else:
			menu_requested.emit()
	elif event.is_action_pressed("attack_move"):
		set_targeting(ATTACK_MOVE)
	elif event.is_action_pressed("patrol"):
		set_targeting(PATROL)
	elif event.is_action_pressed("hold"):
		issue_hold()
	elif event.is_action_pressed("stop"):
		issue_stop()
	elif event.is_action_pressed("idle_henchman"):
		select_idle_henchman()
	elif event.is_action_pressed("select_lab"):
		select_next_lab()
	elif event.is_action_pressed("jump_to_alert"):
		jump_to_alert()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var group := event.keycode - KEY_0
		if event.ctrl_pressed:
			_control_groups[group] = _valid_selected()
		elif event.shift_pressed:
			var members: Array = control_groups().get(group, [])
			for unit in _valid_selected():
				if unit not in members:
					members.append(unit)
			_control_groups[group] = members
		elif control_groups().has(group):
			var now := Time.get_ticks_msec() / 1000.0
			var members: Array = control_groups()[group]
			select_units(members)
			if group == _last_group_key and now - _last_group_time <= DOUBLE_TAP_TIME:
				_focus(_center_of(members))
			_last_group_key = group
			_last_group_time = now
	else:
		return
	get_viewport().set_input_as_handled()


# --- Helpers ------------------------------------------------------------------

func _issue_formation_order(units: Array, target: Vector3, command: StringName, color: Color, queue := false) -> void:
	if units.is_empty():
		return
	assign_formation(units, target, formation_spacing, command, queue)
	_spawn_marker(target, color)


## Starts [param command] on [param unit] now (dropping its queued orders), or
## with [param queue] after the orders it already has.
static func _dispatch(unit: Creature, command: Callable, queue: bool) -> void:
	if queue:
		unit.queue_order(command)
	else:
		unit.clear_order_queue()
		command.call()


func _place_targeted_order(screen_position: Vector2, queue := false) -> void:
	if targeting_order == ATTACK_MOVE:
		issue_order_at_screen(screen_position, true, queue)
	elif targeting_order == PATROL:
		var point: Variant = ground_at_screen(screen_position)
		if point != null:
			issue_patrol(point, queue)


func _set_rally_at_screen(screen_position: Vector2) -> void:
	if building_at_screen(screen_position) == selected_building:
		selected_building.set_rally_point(null)
		return
	var pile := coal_pile_at_screen(screen_position)
	if pile != null:
		selected_building.set_rally_point(pile.global_position, pile)
		_spawn_marker(pile.global_position, WORK_COLOR)
		return
	var point: Variant = ground_at_screen(screen_position)
	if point != null:
		selected_building.set_rally_point(point)
		_spawn_marker(point, MOVE_COLOR)


func _set_selection(units: Array, building: Building) -> void:
	if is_instance_valid(inspected):
		inspected.selection_ring.visible = false
	inspected = null
	for unit in selected:
		if is_instance_valid(unit):
			unit.set_selected(false)
	if is_instance_valid(selected_building):
		selected_building.set_selected(false)
	selected.clear()
	selected_building = null
	for unit: Creature in units:
		if _is_selectable(unit):
			unit.set_selected(true)
			selected.append(unit)
			if not unit.died.is_connected(_on_unit_died):
				unit.died.connect(_on_unit_died)
	if building != null:
		selected_building = building
		building.set_selected(true)
		if not building.died.is_connected(_on_building_died):
			building.died.connect(_on_building_died)
	if selected.is_empty():
		targeting_order = &""
	if selected_henchmen().is_empty() and build_placer.is_active():
		build_placer.cancel()
	_update_cursor()
	selection_changed.emit()


func _on_unit_died(unit: Creature) -> void:
	if unit in selected:
		var remaining := _valid_selected()
		remaining.erase(unit)
		_set_selection(remaining, null)


func _on_building_died(building: Building) -> void:
	if building == selected_building:
		clear_selection()


func _valid_selected() -> Array[Creature]:
	var result: Array[Creature] = []
	for unit in selected:
		if Creature.is_valid_target(unit):
			result.append(unit)
	return result


func _is_selectable(unit: Creature) -> bool:
	return Creature.is_valid_target(unit) and unit.team == player_team


## The entry after [param current] in [param items] (by instance id), wrapping round.
func _next_after(items: Array, current: Variant) -> Variant:
	items.sort_custom(func(a: Node, b: Node) -> bool: return a.get_instance_id() < b.get_instance_id())
	var index := items.find(current) if is_instance_valid(current) else -1
	return items[(index + 1) % items.size()]


func _center_of(units: Array) -> Vector3:
	var center := Vector3.ZERO
	for unit: Node3D in units:
		center += unit.global_position
	return center / maxi(units.size(), 1)


func _focus(point: Vector3) -> void:
	var rig := camera.get_parent()
	if rig != null and rig.has_method("focus_on"):
		rig.focus_on(point)


func _drag_rect(current: Vector2) -> Rect2:
	return Rect2(_press_position, current - _press_position).abs()


func _raycast(screen_position: Vector2, mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return camera.get_world_3d().direct_space_state.intersect_ray(query)


func _update_cursor() -> void:
	var targeting := targeting_order != &"" or build_placer.is_active()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if targeting else Input.CURSOR_ARROW)


func _spawn_marker(target: Vector3, color: Color) -> void:
	var marker := MoveMarkerScene.instantiate()
	marker.color = color
	get_tree().current_scene.add_child(marker)
	marker.global_position = target + Vector3.UP * 0.05
