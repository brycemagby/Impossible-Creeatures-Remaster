class_name SelectionManager
extends Node
## Handles RTS selection and orders for the local player.
##
## - Left click: select a unit (Shift to add/remove)
## - Left drag: box select (Shift to add)
## - Right click ground: move in formation. Right click enemy: attack it
## - F then left click, or Ctrl + right click: attack-move
## - H: stop
## - Ctrl+1..9: assign control group, 1..9: recall it
## - Escape: cancel attack-move targeting, otherwise deselect

signal selection_changed(units: Array)

const DRAG_THRESHOLD := 6.0
const CLICK_PICK_RADIUS := 24.0
const RAY_LENGTH := 1000.0
const GROUND_MASK := 1
const UNIT_MASK := 2
const MOVE_COLOR := Color(0.35, 1.0, 0.4)
const ATTACK_COLOR := Color(1.0, 0.3, 0.25)
const MoveMarkerScene := preload("res://scenes/fx/move_marker.tscn")

@export var camera: Camera3D
@export var selection_box: SelectionBox
@export var player_team := 0
@export var formation_spacing := 1.8

var selected: Array[Creature] = []
## True while waiting for the click that places an attack-move order.
var attack_move_armed := false
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
	_set_selection(result)


func clear_selection() -> void:
	_set_selection([])


## Selects the unit under [param screen_position], or clears the selection if
## there is none. With [param additive], toggles the unit instead.
func click_select(screen_position: Vector2, additive := false) -> void:
	var unit := unit_at_screen(screen_position)
	if unit == null or not _is_selectable(unit):
		if not additive:
			clear_selection()
		return
	if not additive:
		_set_selection([unit])
	elif unit in selected:
		var remaining := _valid_selected()
		remaining.erase(unit)
		_set_selection(remaining)
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


## Returns the unit under the cursor, falling back to the nearest unit within
## a small screen radius so small units are easy to click.
func unit_at_screen(screen_position: Vector2) -> Creature:
	var hit := _raycast(screen_position, UNIT_MASK)
	if hit and hit.collider is Creature and hit.collider.is_alive():
		return hit.collider
	var best: Creature = null
	var best_distance := CLICK_PICK_RADIUS
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if camera.is_position_behind(unit.global_position):
			continue
		var distance := camera.unproject_position(unit.global_position).distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best


## Returns the ground point under the cursor, or null if there is none.
func ground_at_screen(screen_position: Vector2) -> Variant:
	var hit := _raycast(screen_position, GROUND_MASK)
	return hit.position if hit else null


# --- Orders -------------------------------------------------------------------

## Orders the selected units to move to [param target] in formation.
func issue_move(target: Vector3) -> void:
	_issue_formation_order(target, false)


## Orders the selected units to move to [param target] in formation, fighting
## any enemies they meet on the way.
func issue_attack_move(target: Vector3) -> void:
	_issue_formation_order(target, true)


## Orders every selected unit to attack [param target].
func issue_attack(target: Creature) -> void:
	if not Creature.is_valid_target(target) or target.team == player_team:
		return
	var units := _valid_selected()
	if units.is_empty():
		return
	for unit in units:
		unit.command_attack(target)
	_spawn_marker(target.global_position, ATTACK_COLOR)


func issue_stop() -> void:
	for unit in _valid_selected():
		unit.command_stop()


## Handles a right click (or attack-move click) at [param screen_position]:
## attacks an enemy under the cursor, otherwise moves or attack-moves there.
func issue_order_at_screen(screen_position: Vector2, attack_move := false) -> void:
	var unit := unit_at_screen(screen_position)
	if unit != null and unit.team != player_team:
		issue_attack(unit)
		return
	var target: Variant = ground_at_screen(screen_position)
	if target == null:
		return
	if attack_move:
		issue_attack_move(target)
	else:
		issue_move(target)


func set_attack_move_armed(armed: bool) -> void:
	attack_move_armed = armed and not _valid_selected().is_empty()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if attack_move_armed else Input.CURSOR_ARROW)


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
			if event.pressed and attack_move_armed:
				issue_order_at_screen(event.position, true)
				set_attack_move_armed(event.shift_pressed)
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
			if attack_move_armed:
				set_attack_move_armed(false)
			else:
				issue_order_at_screen(event.position, event.ctrl_pressed)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _pressing:
		return
	if not _dragging and event.position.distance_to(_press_position) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		selection_box.show_box(_drag_rect(event.position))


func _handle_key(event: InputEventKey) -> void:
	if event.is_action_pressed("deselect"):
		if attack_move_armed:
			set_attack_move_armed(false)
		else:
			clear_selection()
	elif event.is_action_pressed("attack_move"):
		set_attack_move_armed(true)
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

func _issue_formation_order(target: Vector3, attack_move: bool) -> void:
	var units := _valid_selected()
	if units.is_empty():
		return
	var command := &"command_attack_move" if attack_move else &"command_move"
	assign_formation(units, target, formation_spacing, command)
	_spawn_marker(target, ATTACK_COLOR if attack_move else MOVE_COLOR)


func _set_selection(units: Array) -> void:
	for unit in selected:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected.clear()
	for unit: Creature in units:
		if _is_selectable(unit):
			unit.set_selected(true)
			selected.append(unit)
			if not unit.died.is_connected(_on_unit_died):
				unit.died.connect(_on_unit_died)
	if selected.is_empty() and attack_move_armed:
		set_attack_move_armed(false)
	selection_changed.emit(selected.duplicate())


func _on_unit_died(unit: Creature) -> void:
	if unit in selected:
		var remaining := _valid_selected()
		remaining.erase(unit)
		_set_selection(remaining)


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


func _spawn_marker(target: Vector3, color: Color) -> void:
	var marker := MoveMarkerScene.instantiate()
	marker.color = color
	get_tree().current_scene.add_child(marker)
	marker.global_position = target + Vector3.UP * 0.05
