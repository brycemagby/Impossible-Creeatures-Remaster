extends SceneTree
## Headless smoke tests for the core RTS loop and combat.
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
	await _test_selection_and_movement()
	await _test_armor()
	await _test_melee_attack_order()
	await _test_ranged_attack()
	await _test_auto_acquire()
	await _test_ally_alert()
	await _test_leash()
	await _test_death_clears_selection()
	await _test_order_input()
	await _test_ai_wave()
	await _test_full_battle()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- Core loop ----------------------------------------------------------------

func _test_formation_offsets() -> void:
	print("formation")
	var offsets := SelectionManager.formation_offsets(7, 2.0)
	_check(offsets.size() == 7, "formation has one slot per unit")
	var unique := {}
	for offset in offsets:
		unique[offset.snapped(Vector3.ONE * 0.01)] = true
	_check(unique.size() == 7, "formation slots don't overlap")
	_check(SelectionManager.formation_offsets(0, 2.0).is_empty(), "empty formation for zero units")


func _test_selection_and_movement() -> void:
	print("selection and movement")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var camera: Camera3D = manager.camera
	var player_units := _team_units(0)
	var enemy_units := _team_units(1)
	_check(player_units.size() == 7, "7 player units spawned")
	_check(enemy_units.size() == 6, "6 enemy units spawned")

	var nav_map := main.get_world_3d().navigation_map
	_check(NavigationServer3D.map_get_regions(nav_map).size() > 0, "navigation region registered")

	# Click selection through the real mouse input path.
	var first := player_units[0]
	_click(camera.unproject_position(first.global_position), MOUSE_BUTTON_LEFT)
	_check(manager.selected == [first], "left click selects a single unit")
	_check(first.selection_ring.visible, "selected unit shows its ring")

	main.get_node("RTSCamera").focus_on(enemy_units[0].global_position)
	await process_frame
	_click(camera.unproject_position(enemy_units[0].global_position), MOUSE_BUTTON_LEFT)
	_check(manager.selected.is_empty(), "clicking an enemy does not select it")
	main.get_node("RTSCamera").focus_on(Vector3(0, 0, 2))
	await process_frame

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
	await _wait_until(func() -> bool: return player_units.all(func(u: Creature) -> bool: return not u.is_moving), 10.0)
	var max_distance := 0.0
	for unit in player_units:
		max_distance = maxf(max_distance, _flat(unit.global_position - target))
	_check(max_distance < 6.0, "all units arrive near the move target (furthest %.2f m)" % max_distance)
	_check(player_units.all(func(u: Creature) -> bool: return absf(u.global_position.y) < 0.2), "units stay on the ground")

	# Camera bounds clamp panning.
	var rig: RTSCamera = main.get_node("RTSCamera")
	rig.pan_by(Vector2(1000, 1000))
	_check(rig.position.x <= rig.bounds.end.x and rig.position.z <= rig.bounds.end.y, "camera is clamped to map bounds")
	await _unload(main)


# --- Combat -------------------------------------------------------------------

func _test_armor() -> void:
	print("armor")
	var main := await _load_map()
	var brute := _first(1, "Brute")
	_isolate([brute])
	brute.take_damage(10.0)
	_check(is_equal_approx(brute.health, brute.stats.max_health - 6.0), "armor 4 reduces a 10 damage hit to 6")
	brute.take_damage(2.0)
	_check(is_equal_approx(brute.health, brute.stats.max_health - 7.0), "hits always deal at least 1 damage")
	await _unload(main)


func _test_melee_attack_order() -> void:
	print("melee attack order")
	var main := await _load_map()
	var brute := _first(0, "Brute")
	var runner := _first(1, "Runner")
	_isolate([brute, runner])
	_place(brute, Vector3(0, 0, 0))
	_place(runner, Vector3(0, 0, -6))
	brute.command_attack(runner)
	_check(brute.order == Creature.Order.ATTACK and brute.attack_target == runner, "attack order targets the enemy")
	await _wait_until(func() -> bool: return not runner.is_alive(), 20.0)
	_check(not runner.is_alive(), "brute kills the runner")
	_check(brute.is_alive() and brute.health < brute.stats.max_health, "runner fought back before dying")
	_check(not runner.is_in_group("units"), "dead creatures leave the units group")
	await _physics_frames(5)
	_check(brute.order == Creature.Order.IDLE and brute.attack_target == null, "attacker goes idle after the kill")
	var corpse: WeakRef = weakref(runner)
	await _wait_until(func() -> bool: return corpse.get_ref() == null, 4.0)
	_check(corpse.get_ref() == null, "corpse is removed after the death animation")
	await _unload(main)


func _test_ranged_attack() -> void:
	print("ranged attack")
	var main := await _load_map()
	var skirmisher := _first(0, "Skirmisher")
	var brute := _first(1, "Brute")
	_isolate([skirmisher, brute])
	_place(skirmisher, Vector3(0, 0, 0))
	_place(brute, Vector3(0, 0, -8.5))
	skirmisher.command_attack(brute)
	var saw_projectile := false
	for i in 120:
		await physics_frame
		if main.find_children("*", "Node3D", false, false).any(func(n: Node) -> bool: return n.name.begins_with("Projectile")):
			saw_projectile = true
	_check(saw_projectile, "skirmisher fires projectiles")
	_check(brute.health < brute.stats.max_health, "projectiles damage the target")
	_check(skirmisher.surface_distance_to(brute) > 1.0 or brute.attack_target == skirmisher, "skirmisher attacks from range")
	await _unload(main)


func _test_auto_acquire() -> void:
	print("auto acquire")
	var main := await _load_map()
	var mine := _first(0, "Runner")
	var theirs := _first(1, "Runner")
	_isolate([mine, theirs])
	_place(mine, Vector3(0, 0, 0))
	_place(theirs, Vector3(0, 0, -8))
	await _physics_frames(30)
	_check(mine.attack_target == theirs, "idle player unit engages an enemy in sight")
	_check(theirs.attack_target == mine, "idle enemy unit engages a player unit in sight")
	await _unload(main)


func _test_ally_alert() -> void:
	print("ally alert")
	var main := await _load_map()
	var attacker := _first(0, "Skirmisher")
	var victim := _first(1, "Brute")
	var ally := _first(1, "Runner")
	_isolate([attacker, victim, ally])
	_place(attacker, Vector3(0, 0, 20))
	_place(victim, Vector3(0, 0, -10))
	_place(ally, Vector3(4, 0, -10))
	await _physics_frames(5)
	victim.take_damage(5.0, attacker)
	_check(victim.attack_target == attacker, "damaged creature retaliates against an out-of-sight attacker")
	_check(ally.attack_target == attacker, "nearby idle allies join in")
	await _unload(main)


func _test_leash() -> void:
	print("leash")
	var main := await _load_map()
	var runner := _first(0, "Runner")
	var brute := _first(1, "Brute")
	_isolate([runner, brute])
	var guard := Vector3(0, 0, -10)
	_place(brute, guard)
	_place(runner, Vector3(0, 0, 20))
	await _physics_frames(5)
	brute.take_damage(5.0, runner)
	runner.command_move(Vector3(0, 0, 45))
	_check(brute.attack_target == runner, "brute chases its attacker")
	await _physics_frames(60)
	_check(_flat(brute.global_position - guard) > 2.0, "brute leaves its post to chase")
	await _wait_until(func() -> bool: return brute.order == Creature.Order.IDLE and not brute.is_moving, 15.0)
	_check(brute.attack_target == null, "brute gives up the chase")
	_check(_flat(brute.global_position - guard) < 2.0, "brute walks back to its post (%.2f m away)" % _flat(brute.global_position - guard))
	await _unload(main)


func _test_death_clears_selection() -> void:
	print("death and selection")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var units := _team_units(0)
	manager.select_units([units[0], units[1]])
	units[0].take_damage(9999.0)
	_check(manager.selected == [units[1]], "dead units are removed from the selection")
	manager.select_units([units[0]])
	_check(manager.selected.is_empty(), "dead units can't be selected")
	await _unload(main)


func _test_order_input() -> void:
	print("order input")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var camera: Camera3D = manager.camera
	var rig: RTSCamera = main.get_node("RTSCamera")
	var units := _team_units(0)
	var enemy := _first(1, "Brute")
	manager.select_units(units)

	rig.focus_on(enemy.global_position)
	await process_frame
	_click(camera.unproject_position(enemy.global_position), MOUSE_BUTTON_RIGHT)
	_check(units.all(func(u: Creature) -> bool: return u.attack_target == enemy and u.order == Creature.Order.ATTACK),
			"right clicking an enemy orders an attack")

	_key(KEY_H)
	_check(units.all(func(u: Creature) -> bool: return u.order == Creature.Order.IDLE and u.attack_target == null),
			"H stops the selected units")

	rig.focus_on(Vector3(0, 0, -10))
	await process_frame
	_key(KEY_F)
	_check(manager.attack_move_armed, "F arms attack-move")
	_click(root.get_visible_rect().size / 2.0, MOUSE_BUTTON_LEFT)
	_check(not manager.attack_move_armed, "clicking places the order and disarms attack-move")
	_check(manager.selected.size() == units.size(), "attack-move click doesn't change the selection")
	_check(units.all(func(u: Creature) -> bool: return u.order == Creature.Order.ATTACK_MOVE), "units are attack-moving")

	_key(KEY_F)
	_key(KEY_ESCAPE)
	_check(not manager.attack_move_armed and manager.selected.size() == units.size(), "Esc cancels attack-move without deselecting")
	await _unload(main)


func _test_ai_wave() -> void:
	print("enemy AI")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	var sent := ai.launch_wave()
	_check(sent == 6, "AI sends all 6 idle units in a wave")
	_check(_team_units(1).all(func(u: Creature) -> bool: return u.order == Creature.Order.ATTACK_MOVE), "wave units attack-move")
	await _unload(main)


func _test_full_battle() -> void:
	print("full battle")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	manager.select_units(_team_units(0))
	manager.issue_attack_move(Vector3(0, 0, -32))
	await _wait_until(func() -> bool: return _team_units(0).is_empty() or _team_units(1).is_empty(), 60.0)
	var player_left := _team_units(0).size()
	var enemy_left := _team_units(1).size()
	_check(player_left == 0 or enemy_left == 0, "attack-move battle resolves (%d player vs %d enemy left)" % [player_left, enemy_left])
	await _unload(main)


# --- Helpers ------------------------------------------------------------------

func _load_map() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.get_node("EnemyAI").wave_interval = 0.0
	root.add_child(main)
	current_scene = main
	await _physics_frames(10)
	return main


func _unload(main: Node) -> void:
	main.queue_free()
	await process_frame
	await process_frame


func _team_units(team: int) -> Array[Creature]:
	var result: Array[Creature] = []
	for unit: Creature in get_nodes_in_group("units"):
		if unit.team == team:
			result.append(unit)
	return result


func _first(team: int, display_name: String) -> Creature:
	for unit in _team_units(team):
		if unit.stats.display_name == display_name:
			return unit
	return null


## Removes every unit except [param keep] so a scenario runs undisturbed.
func _isolate(keep: Array) -> void:
	for unit: Creature in get_nodes_in_group("units"):
		if unit not in keep:
			unit.remove_from_group("units")
			unit.queue_free()


func _place(unit: Creature, position: Vector3) -> void:
	unit.global_position = position
	unit.command_stop()


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _wait_until(condition: Callable, timeout: float) -> void:
	var frames := int(timeout * Engine.physics_ticks_per_second)
	for i in frames:
		if condition.call():
			return
		await physics_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await physics_frame


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


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
