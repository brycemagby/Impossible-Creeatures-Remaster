class_name SelectionManager
extends Node
## Handles RTS selection and orders for the local player.
##
## - Left click: select a unit or building (Shift to add/remove units)
## - Left drag: box select units (Shift to add)
## - Right click with units: move / attack enemy / gather coal / help build
## - Right click with a building: set its rally point
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


## Selects the unit or own building under [param screen_position], or clears
## the selection if there is none. With [param additive], toggles units.
func click_select(screen_position: Vector2, additive := false) -> void:
	var unit := unit_at_screen(screen_position)
	if unit == null or not _is_selectable(unit):
		var building := building_at_screen(screen_position)
		if building != null and building.team == player_team and not additive:
			select_building(building)
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
	select_units(inside, additive)


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
func issue_move(target: Vector3) -> void:
	_issue_formation_order(_valid_selected(), target, &"command_move", MOVE_COLOR)


## Orders the selected units to move to [param target] in formation, fighting
## any enemies they meet on the way.
func issue_attack_move(target: Vector3) -> void:
	_issue_formation_order(_valid_selected(), target, &"command_attack_move", ATTACK_COLOR)


## Orders every selected unit to attack [param target] (creature or building).
func issue_attack(target: Node3D) -> void:
	if not Creature.is_valid_target(target) or target.team == player_team:
		return
	var units := _valid_selected()
	if units.is_empty():
		return
	for unit in units:
		unit.command_attack(target)
	_spawn_marker(target.global_position, ATTACK_COLOR)


## Selected Henchmen gather from [param pile]; everyone else walks over.
func issue_gather(pile: CoalPile) -> void:
	var others := _valid_selected()
	for henchman in selected_henchmen():
		henchman.command_gather(pile)
		others.erase(henchman)
	_issue_formation_order(others, pile.global_position, &"command_move", MOVE_COLOR)
	_spawn_marker(pile.global_position, WORK_COLOR)


## Selected Henchmen help construct [param site]; everyone else walks over.
func issue_build(site: Building) -> void:
	var others := _valid_selected()
	for henchman in selected_henchmen():
		henchman.command_build(site)
		others.erase(henchman)
	_issue_formation_order(others, site.global_position, &"command_move", MOVE_COLOR)
	_spawn_marker(site.global_position, WORK_COLOR)


func issue_stop() -> void:
	for unit in _valid_selected():
		unit.command_stop()


func issue_hold() -> void:
	for unit in _valid_selected():
		unit.command_hold()


## Orders the selected units to patrol between where they are and [param target].
func issue_patrol(target: Vector3) -> void:
	_issue_formation_order(_valid_selected(), target, &"command_patrol", PATROL_COLOR)


## Handles a right click (or attack-move click) at [param screen_position].
func issue_order_at_screen(screen_position: Vector2, attack_move := false) -> void:
	if Creature.is_valid_target(selected_building):
		_set_rally_at_screen(screen_position)
		return
	if _valid_selected().is_empty():
		return
	var unit := unit_at_screen(screen_position)
	if unit != null and unit.team != player_team:
		issue_attack(unit)
		return
	var building := building_at_screen(screen_position)
	if building != null:
		if building.team != player_team:
			issue_attack(building)
			return
		if not building.is_complete and not selected_henchmen().is_empty():
			issue_build(building)
			return
	if not attack_move:
		var pile := coal_pile_at_screen(screen_position)
		if pile != null:
			issue_gather(pile)
			return
	var target: Variant = ground_at_screen(screen_position)
	if target == null:
		return
	if attack_move:
		issue_attack_move(target)
	else:
		issue_move(target)


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
static func formation_offsets(count: int, spacing: float, yaw := 0.0) -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	if count <= 0:
		return offsets
	var columns := ceili(sqrt(count))
	var rows := ceili(float(count) / columns)
	for i in count:
		var row := i / columns
		var column := i % columns
		var offset := Vector3(
			(column - (columns - 1) / 2.0) * spacing,
			0.0,
			((rows - 1) / 2.0 - row) * spacing
		)
		offsets.append(offset.rotated(Vector3.UP, yaw))
	return offsets


## Gives each unit a slot in a grid around [param target] facing the direction
## of travel, then calls [param command] (a Creature method name) with the slot
## and the group's speed (that of its slowest member).
static func assign_formation(units: Array, target: Vector3, spacing: float, command: StringName) -> void:
	if units.is_empty():
		return
	var center := Vector3.ZERO
	var group_speed := INF
	for unit: Creature in units:
		center += unit.global_position
		group_speed = minf(group_speed, unit.stats.move_speed)
	center /= units.size()
	var direction := target - center
	direction.y = 0.0
	var yaw := atan2(direction.x, direction.z) if direction.length() > 0.1 else 0.0

	# Greedily give each formation slot to the closest remaining unit.
	var remaining := units.duplicate()
	for offset in formation_offsets(units.size(), spacing, yaw):
		var slot := target + offset
		var best: Creature = null
		var best_distance := INF
		for unit: Creature in remaining:
			var distance := unit.global_position.distance_squared_to(slot)
			if distance < best_distance:
				best_distance = distance
				best = unit
		remaining.erase(best)
		best.call(command, slot, group_speed)


# --- Input handling -----------------------------------------------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed and build_placer.is_active():
				place_building_at_screen(event.position, event.shift_pressed)
				get_viewport().set_input_as_handled()
			elif event.pressed and targeting_order != &"":
				_place_targeted_order(event.position)
				set_targeting(targeting_order if event.shift_pressed else &"")
				get_viewport().set_input_as_handled()
			elif event.pressed:
				_pressing = true
				_dragging = false
				_press_position = event.position
			elif _pressing:
				_pressing = false
				if _dragging:
					select_in_rect(_drag_rect(event.position), event.shift_pressed)
				else:
					click_select(event.position, event.shift_pressed)
				_dragging = false
				selection_box.hide_box()
		MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				return
			if build_placer.is_active():
				cancel_placement()
			elif targeting_order != &"":
				set_targeting(&"")
			else:
				issue_order_at_screen(event.position, event.ctrl_pressed)


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
		elif not selected.is_empty() or selected_building != null:
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
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var group := event.keycode - KEY_0
		if event.ctrl_pressed:
			_control_groups[group] = _valid_selected()
		elif _control_groups.has(group):
			select_units(_control_groups[group])
	else:
		return
	get_viewport().set_input_as_handled()


# --- Helpers ------------------------------------------------------------------

func _issue_formation_order(units: Array, target: Vector3, command: StringName, color: Color) -> void:
	if units.is_empty():
		return
	assign_formation(units, target, formation_spacing, command)
	_spawn_marker(target, color)


func _place_targeted_order(screen_position: Vector2) -> void:
	if targeting_order == ATTACK_MOVE:
		issue_order_at_screen(screen_position, true)
	elif targeting_order == PATROL:
		var point: Variant = ground_at_screen(screen_position)
		if point != null:
			issue_patrol(point)


func _set_rally_at_screen(screen_position: Vector2) -> void:
	if building_at_screen(screen_position) == selected_building:
		selected_building.set_rally_point(null)
		return
	var point: Variant = ground_at_screen(screen_position)
	if point != null:
		selected_building.set_rally_point(point)
		_spawn_marker(point, MOVE_COLOR)


func _set_selection(units: Array, building: Building) -> void:
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
