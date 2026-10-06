extends SceneTree
## Headless smoke tests for the core RTS loop.
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with a non-zero code if any check fails.

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_formation_offsets()
	await _test_skirmish_map()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_formation_offsets() -> void:
	var offsets := SelectionManager.formation_offsets(7, 2.0)
	_check(offsets.size() == 7, "formation has one slot per unit")
	var unique := {}
	for offset in offsets:
		unique[offset.snapped(Vector3.ONE * 0.01)] = true
	_check(unique.size() == 7, "formation slots don't overlap")
	_check(SelectionManager.formation_offsets(0, 2.0).is_empty(), "empty formation for zero units")


func _test_skirmish_map() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _physics_frames(10)

	var manager: SelectionManager = main.get_node("SelectionManager")
	var camera: Camera3D = manager.camera
	var player_units: Array[Creature] = []
	var enemy_units: Array[Creature] = []
	for unit: Creature in get_nodes_in_group("units"):
		(player_units if unit.team == 0 else enemy_units).append(unit)
	_check(player_units.size() == 7, "7 player units spawned")
	_check(enemy_units.size() == 3, "3 enemy units spawned")

	var nav_map := main.get_world_3d().navigation_map
	_check(NavigationServer3D.map_get_regions(nav_map).size() > 0, "navigation region registered")

	# Click selection through the real mouse input path.
	var first := player_units[0]
	_click(camera.unproject_position(first.global_position), MOUSE_BUTTON_LEFT)
	_check(manager.selected == [first], "left click selects a single unit")
	_check(first.selection_ring.visible, "selected unit shows its ring")

	_click(camera.unproject_position(enemy_units[0].global_position), MOUSE_BUTTON_LEFT)
	_check(manager.selected.is_empty(), "clicking an enemy does not select it")

	# Drag-select the whole screen: only player units get picked.
	var screen := root.get_visible_rect().size
	_drag(Vector2(2, 2), screen - Vector2(2, 2))
	_check(manager.selected.size() == player_units.size(), "box select grabs all visible player units")
	_check(manager.selected.all(func(u: Creature) -> bool: return u.team == 0), "box select ignores enemies")

	# Control groups.
	_key(KEY_1, true)
	_key(KEY_ESCAPE)
	_check(manager.selected.is_empty(), "escape clears the selection")
	_key(KEY_1)
	_check(manager.selected.size() == player_units.size(), "control group 1 recalls the selection")

	# Move order around a rock and check everyone arrives near the target.
	var target := Vector3(-10, 0, -12)
	manager.issue_move(target)
	for i in 600:
		await physics_frame
		if player_units.all(func(u: Creature) -> bool: return not u.is_moving):
			break
	var max_distance := 0.0
	for unit in player_units:
		max_distance = maxf(max_distance, Vector2(unit.global_position.x - target.x, unit.global_position.z - target.z).length())
	_check(max_distance < 6.0, "all units arrive near the move target (furthest %.2f m)" % max_distance)
	_check(player_units.all(func(u: Creature) -> bool: return absf(u.global_position.y) < 0.2), "units stay on the ground")

	# Camera bounds clamp panning.
	var rig: RTSCamera = main.get_node("RTSCamera")
	rig.pan_by(Vector2(1000, 1000))
	_check(rig.position.x <= rig.bounds.end.x and rig.position.z <= rig.bounds.end.y, "camera is clamped to map bounds")

	main.queue_free()
	await process_frame


func _click(position: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = position
		event.pressed = pressed
		root.push_input(event)


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from
	press.pressed = true
	root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	root.push_input(motion)
	var release := press.duplicate()
	release.position = to
	release.pressed = false
	root.push_input(release)


func _key(keycode: Key, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.pressed = true
	root.push_input(event)


func _physics_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
