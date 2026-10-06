class_name SelectionManager
extends Node
## Handles RTS selection and orders for the local player.
##
## - Left click: select a unit (Shift to add/remove)
## - Left drag: box select (Shift to add)
## - Right click: move selected units in formation
## - Ctrl+1..9: assign control group, 1..9: recall it
## - Escape: deselect

signal selection_changed(units: Array)

const DRAG_THRESHOLD := 6.0
const CLICK_PICK_RADIUS := 24.0
const RAY_LENGTH := 1000.0
const GROUND_MASK := 1
const UNIT_MASK := 2
const MoveMarkerScene := preload("res://scenes/fx/move_marker.tscn")

@export var camera: Camera3D
@export var selection_box: SelectionBox
@export var player_team := 0
@export var formation_spacing := 1.8

var selected: Array[Creature] = []
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


# --- Public API ---------------------------------------------------------------

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
	if hit and hit.collider is Creature:
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


## Orders the selected units to move to [param target] in a grid formation
## facing the direction of travel.
func issue_move(target: Vector3) -> void:
	var units := _valid_selected()
	if units.is_empty():
		return
	var center := Vector3.ZERO
	for unit in units:
		center += unit.global_position
	center /= units.size()
	var direction := target - center
	direction.y = 0.0
	var yaw := atan2(direction.x, direction.z) if direction.length() > 0.1 else 0.0

	# Greedily give each formation slot to the closest remaining unit.
	var remaining := units.duplicate()
	for offset in formation_offsets(units.size(), formation_spacing, yaw):
		var slot := target + offset
		var best: Creature = null
		var best_distance := INF
		for unit: Creature in remaining:
			var distance := unit.global_position.distance_squared_to(slot)
			if distance < best_distance:
				best_distance = distance
				best = unit
		remaining.erase(best)
		best.move_to(slot)
	_spawn_move_marker(target)


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


# --- Input handling -----------------------------------------------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
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
			if event.pressed:
				var target: Variant = ground_at_screen(event.position)
				if target != null:
					issue_move(target)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _pressing:
		return
	if not _dragging and event.position.distance_to(_press_position) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		selection_box.show_box(_drag_rect(event.position))


func _handle_key(event: InputEventKey) -> void:
	if event.is_action_pressed("deselect"):
		clear_selection()
		get_viewport().set_input_as_handled()
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9:
		return
	var group := event.keycode - KEY_0
	if event.ctrl_pressed:
		_control_groups[group] = _valid_selected()
	elif _control_groups.has(group):
		select_units(_control_groups[group])
	get_viewport().set_input_as_handled()


# --- Helpers ------------------------------------------------------------------

func _set_selection(units: Array) -> void:
	for unit in selected:
		if is_instance_valid(unit):
			unit.set_selected(false)
	selected.clear()
	for unit: Creature in units:
		if is_instance_valid(unit):
			unit.set_selected(true)
			selected.append(unit)
	selection_changed.emit(selected.duplicate())


func _valid_selected() -> Array[Creature]:
	var result: Array[Creature] = []
	for unit in selected:
		if is_instance_valid(unit):
			result.append(unit)
	return result


func _is_selectable(unit: Creature) -> bool:
	return is_instance_valid(unit) and unit.team == player_team


func _drag_rect(current: Vector2) -> Rect2:
	return Rect2(_press_position, current - _press_position).abs()


func _raycast(screen_position: Vector2, mask: int) -> Dictionary:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return camera.get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_move_marker(target: Vector3) -> void:
	var marker := MoveMarkerScene.instantiate()
	get_tree().current_scene.add_child(marker)
	marker.global_position = target + Vector3.UP * 0.05
