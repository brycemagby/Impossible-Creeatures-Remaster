extends Node
## Headless tests for the core RTS loop, combat, economy and base building.
##
## Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with a non-zero code if any check fails.

var _failures := 0
var _checks := 0


func _ready() -> void:
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
	await _test_economy()
	await _test_generator()
	await _test_gathering()
	await _test_pile_depletion()
	await _test_production()
	await _test_production_costs()
	await _test_placement_and_construction()
	await _test_gather_order_input()
	await _test_attack_building()
	await _test_buildings_call_defenders()
	await _test_victory()
	await _test_ai_economy()
	await _test_hud_command_panel()
	print("\n%d checks, %d failed" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


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
	_check(player_units.size() == 9, "9 player units spawned (4 Henchmen + 5 fighters)")
	_check(enemy_units.size() == 9, "9 enemy units spawned (3 Henchmen + 6 fighters)")

	var nav_map := main.get_world_3d().navigation_map
	_check(NavigationServer3D.map_get_regions(nav_map).size() > 0, "navigation region registered")

	# Click selection through the real mouse input path.
	var first := player_units[0]
	_click(camera.unproject_position(first.global_position), MOUSE_BUTTON_LEFT)
	_check(manager.selected == [first], "left click selects a single unit")
	_check(first.selection_ring.visible, "selected unit shows its ring")

	main.get_node("RTSCamera").focus_on(enemy_units[0].global_position)
	await get_tree().process_frame
	_click(camera.unproject_position(enemy_units[0].global_position), MOUSE_BUTTON_LEFT)
	_check(manager.selected.is_empty(), "clicking an enemy does not select it")
	main.get_node("RTSCamera").focus_on(Vector3(0, 0, 28))
	await get_tree().process_frame

	# Drag-select the whole screen: only player units get picked.
	var screen := get_tree().root.get_visible_rect().size
	var visible := player_units.filter(func(u: Creature) -> bool:
		return Rect2(Vector2.ZERO, screen).has_point(camera.unproject_position(u.global_position)))
	_drag(Vector2(2, 2), screen - Vector2(2, 2))
	_check(visible.size() >= 5 and manager.selected.size() == visible.size(), "box select grabs all visible player units (%d)" % visible.size())
	_check(manager.selected.all(func(u: Creature) -> bool: return u.team == 0), "box select ignores enemies")

	# Control groups.
	_key(KEY_1, true)
	_key(KEY_ESCAPE)
	_check(manager.selected.is_empty(), "escape clears the selection")
	_key(KEY_1)
	_check(manager.selected.size() == visible.size(), "control group 1 recalls the selection")

	# Move order around a rock and check everyone arrives near the target.
	var target := Vector3(14, 0, 6)
	var movers: Array = manager.selected.duplicate()
	manager.issue_move(target)
	await _wait_until(func() -> bool: return movers.all(func(u: Creature) -> bool: return not u.is_moving), 15.0)
	var max_distance := 0.0
	for unit: Creature in movers:
		max_distance = maxf(max_distance, _flat(unit.global_position - target))
	_check(max_distance < 6.0, "all units arrive near the move target (furthest %.2f m)" % max_distance)
	_check(movers.all(func(u: Creature) -> bool: return absf(u.global_position.y) < 0.2), "units stay on the ground")

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
		await get_tree().physics_frame
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
	var units := _fighters(0)
	var enemy := _first(1, "Brute")
	manager.select_units(units)

	rig.focus_on(enemy.global_position)
	await get_tree().process_frame
	_click(camera.unproject_position(enemy.global_position), MOUSE_BUTTON_RIGHT)
	_check(units.all(func(u: Creature) -> bool: return u.attack_target == enemy and u.order == Creature.Order.ATTACK),
			"right clicking an enemy orders an attack")

	_key(KEY_H)
	_check(units.all(func(u: Creature) -> bool: return u.order == Creature.Order.IDLE and u.attack_target == null),
			"H stops the selected units")

	rig.focus_on(Vector3(0, 0, -10))
	await get_tree().process_frame
	_key(KEY_F)
	_check(manager.attack_move_armed, "F arms attack-move")
	_click(get_tree().root.get_visible_rect().size / 2.0, MOUSE_BUTTON_LEFT)
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
	_check(sent == 6, "AI sends all 6 idle fighters in a wave")
	_check(_fighters(1).all(func(u: Creature) -> bool: return u.order == Creature.Order.ATTACK_MOVE), "wave units attack-move")
	_check(_team_units(1).all(func(u: Creature) -> bool: return u is not Henchman or u.order == Creature.Order.IDLE), "Henchmen stay home")
	await _unload(main)


func _test_full_battle() -> void:
	print("full battle")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	_isolate(_fighters(0) + _fighters(1))
	manager.select_units(_team_units(0))
	manager.issue_attack_move(Vector3(0, 0, -32))
	await _wait_until(func() -> bool: return _team_units(0).is_empty() or _team_units(1).is_empty(), 60.0)
	var player_left := _team_units(0).size()
	var enemy_left := _team_units(1).size()
	_check(player_left == 0 or enemy_left == 0, "attack-move battle resolves (%d player vs %d enemy left)" % [player_left, enemy_left])
	await _unload(main)


# --- Economy and base building ------------------------------------------------

func _test_economy() -> void:
	print("economy")
	var main := await _load_map()
	# Generators run from the first frame, so electricity is already a little above 100.
	_check(Economy.coal(0) == 300.0 and absf(Economy.electricity(0) - 100.0) < 2.0, "teams start with 300 coal and 100 electricity")
	var electricity: float = Economy.electricity(0)
	_check(Economy.spend(0, 100, 50), "spending within budget succeeds")
	_check(Economy.coal(0) == 200.0 and is_equal_approx(Economy.electricity(0), electricity - 50.0), "spending deducts both resources")
	_check(not Economy.spend(0, 500, 0) and Economy.coal(0) == 200.0, "overspending fails and changes nothing")
	_check(Economy.shortfall(0, 0, 999) == "Not enough electricity", "shortfall explains what's missing")
	await _unload(main)


func _test_generator() -> void:
	print("generator")
	var main := await _load_map()
	var before: float = Economy.electricity(0)
	await _physics_frames(120)
	var gained: float = Economy.electricity(0) - before
	_check(gained > 3.0 and gained < 5.0, "generator produces about 2 electricity per second (%.1f in 2s)" % gained)
	await _unload(main)


func _test_gathering() -> void:
	print("gathering")
	var main := await _load_map()
	var henchman: Henchman = _first(0, "Henchman")
	var pile := _nearest_pile(henchman.global_position)
	var pile_start := pile.amount
	var coal_start: float = Economy.coal(0)
	henchman.command_gather(pile)
	_check(henchman.order == Creature.Order.GATHER, "Henchman takes the gather order")
	await _wait_until(func() -> bool: return Economy.coal(0) >= coal_start + 20.0, 30.0)
	_check(Economy.coal(0) >= coal_start + 20.0, "Henchman delivers at least two loads of coal (+%d)" % (Economy.coal(0) - coal_start))
	_check(pile.amount < pile_start, "the pile shrinks as it is mined")
	_check(henchman.order == Creature.Order.GATHER, "Henchman keeps gathering after delivering")
	await _unload(main)


func _test_pile_depletion() -> void:
	print("pile depletion")
	var main := await _load_map()
	var henchman: Henchman = _first(0, "Henchman")
	var pile := _nearest_pile(henchman.global_position)
	pile.amount = 10
	henchman.command_gather(pile)
	var gone: WeakRef = weakref(pile)
	await _wait_until(func() -> bool: return gone.get_ref() == null, 15.0)
	_check(gone.get_ref() == null, "an empty pile disappears")
	await _physics_frames(5)
	_check(henchman.order == Creature.Order.GATHER and is_instance_valid(henchman.gather_target),
			"Henchman moves on to another pile nearby")
	await _unload(main)


func _test_production() -> void:
	print("production")
	var main := await _load_map()
	var lab := _building(0, "Lab")
	var recipe: UnitRecipe = lab.data.production[0]
	var henchmen_before := _team_units(0).filter(func(u: Creature) -> bool: return u is Henchman).size()
	var rally := lab.global_position + Vector3(8, 0, -10)
	lab.set_rally_point(rally)
	_check(lab.enqueue(recipe) == "", "Lab queues a Henchman")
	_check(Economy.coal(0) == 250.0, "queueing pays the cost up front")
	await _wait_until(func() -> bool: return lab.queue.is_empty(), recipe.build_time + 2.0)
	var henchmen := _team_units(0).filter(func(u: Creature) -> bool: return u is Henchman)
	_check(henchmen.size() == henchmen_before + 1, "a new Henchman is produced after its build time")
	var newest: Creature = henchmen.back()
	await _wait_until(func() -> bool: return not newest.is_moving, 6.0)
	_check(_flat(newest.global_position - rally) < 1.5, "new units walk to the rally point")
	await _unload(main)


func _test_production_costs() -> void:
	print("production costs")
	var main := await _load_map()
	var lab := _building(0, "Lab")
	var recipe: UnitRecipe = lab.data.production[0]
	for i in Building.MAX_QUEUE:
		lab.enqueue(recipe)
	_check(lab.queue.size() == Building.MAX_QUEUE, "queue holds up to %d units" % Building.MAX_QUEUE)
	Economy.add(0, 1000)
	_check(lab.enqueue(recipe) == "Queue is full", "queue rejects a sixth unit")
	var coal: float = Economy.coal(0)
	lab.cancel_last()
	_check(Economy.coal(0) == coal + recipe.cost_coal and lab.queue.size() == Building.MAX_QUEUE - 1, "cancelling refunds the cost")
	Economy.reset([0, 1], 0.0, 0.0)
	lab.queue.clear()
	_check(lab.enqueue(recipe) == "Not enough coal" and lab.queue.is_empty(), "can't queue without enough coal")
	await _unload(main)


func _test_placement_and_construction() -> void:
	print("placement and construction")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var placer: BuildPlacer = manager.build_placer
	var rig: RTSCamera = main.get_node("RTSCamera")
	var henchmen := _team_units(0).filter(func(u: Creature) -> bool: return u is Henchman)
	var generator: BuildingData = load("res://resources/buildings/generator.tres")
	manager.select_units(henchmen)
	manager.begin_placement(generator)
	_check(placer.is_active(), "selecting a building to construct starts placement")
	_check(not placer.can_place_at(_building(0, "Lab").global_position), "can't place on top of another building")
	_check(not placer.can_place_at(Vector3(-12, 0, -6)), "can't place on a rock")
	_check(not placer.can_place_at(Vector3(49, 0, 0)), "can't place outside the map")

	var spot := Vector3(-14, 0, 24)
	rig.focus_on(spot)
	await get_tree().process_frame
	_click(manager.camera.unproject_position(spot), MOUSE_BUTTON_LEFT)
	var site := _building(0, "Electrical Generator", true)
	_check(site != null and not site.is_complete, "clicking places a construction site")
	_check(not placer.is_active(), "placement ends after placing")
	_check(Economy.coal(0) == 150.0, "the building's cost is paid")
	_check(henchmen.all(func(u: Henchman) -> bool: return u.order == Creature.Order.BUILD), "selected Henchmen go and build it")
	_check(manager.selected.size() == henchmen.size(), "placing doesn't change the selection")
	await _wait_until(func() -> bool: return site.is_complete, 20.0)
	_check(site.is_complete and is_equal_approx(site.health, site.data.max_health), "Henchmen finish construction at full health")
	await _physics_frames(2)
	_check(henchmen.all(func(u: Henchman) -> bool: return u.order == Creature.Order.IDLE), "Henchmen go idle when the building is done")
	await _wait_until(func() -> bool: return not main.is_baking(), 5.0)
	await _physics_frames(5)
	var map := main.get_world_3d().navigation_map
	var nearest := NavigationServer3D.map_get_closest_point(map, site.global_position)
	_check(_flat(nearest - site.global_position) > 1.4, "the navmesh is rebaked around the new building")
	await _unload(main)


func _test_gather_order_input() -> void:
	print("gather order input")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var rig: RTSCamera = main.get_node("RTSCamera")
	var henchman: Henchman = _first(0, "Henchman")
	var runner := _first(0, "Runner")
	var pile := _nearest_pile(henchman.global_position)
	manager.select_units([henchman, runner])
	rig.focus_on(pile.global_position)
	await get_tree().process_frame
	_click(manager.camera.unproject_position(pile.global_position + Vector3.UP * 0.8), MOUSE_BUTTON_RIGHT)
	_check(henchman.order == Creature.Order.GATHER and henchman.gather_target == pile, "right clicking coal sends Henchmen to gather")
	_check(runner.order == Creature.Order.MOVE, "other units just walk over")

	var lab := _building(0, "Lab")
	manager.select_building(lab)
	_check(manager.selected_building == lab and manager.selected.is_empty(), "buildings can be selected")
	var rally_screen := manager.camera.unproject_position(pile.global_position + Vector3(-4, 0, 0))
	_click(rally_screen, MOUSE_BUTTON_RIGHT)
	_check(lab.rally_point != null and lab.rally_flag.visible, "right click with a building selected sets its rally point")
	await _unload(main)


func _test_attack_building() -> void:
	print("attack building")
	var main := await _load_map()
	var brute := _first(0, "Brute")
	_isolate([brute])
	var generator := _building(1, "Electrical Generator")
	_place(brute, generator.global_position + Vector3(0, 0, 5))
	brute.command_attack(generator)
	await _physics_frames(240)
	_check(generator.health < generator.data.max_health, "units can damage buildings")
	generator.take_damage(99999.0)
	_check(not generator.is_alive() and not generator.is_in_group("buildings"), "destroyed buildings leave play")
	await _physics_frames(5)
	_check(brute.order == Creature.Order.IDLE, "attacker goes idle after destroying the building")
	var wreck: WeakRef = weakref(generator)
	await _wait_until(func() -> bool: return wreck.get_ref() == null, 3.0)
	_check(wreck.get_ref() == null, "the wreck sinks and is removed")
	await _unload(main)


func _test_buildings_call_defenders() -> void:
	print("defending buildings")
	var main := await _load_map()
	var attacker := _first(0, "Skirmisher")
	var lab := _building(1, "Lab")
	var defender := _first(1, "Henchman")
	_check(defender.order == Creature.Order.IDLE, "defender starts idle")
	lab.take_damage(50.0, attacker)
	_check(defender.attack_target == attacker, "units near an attacked building come to defend it")
	await _unload(main)


func _test_victory() -> void:
	print("victory")
	var main := await _load_map()
	var rules: GameRules = main.get_node("GameRules")
	rules.check_now()
	_check(rules.winner == -1, "no winner at the start")
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		if target.team == 1:
			target.take_damage(999999.0)
	rules.check_now()
	_check(rules.winner == 0, "destroying every enemy unit and building wins")
	var banner: Label = main.get_node("UI/HUD").game_over_label
	_check(banner.visible and banner.text == "VICTORY", "the HUD shows VICTORY")
	await _unload(main)


func _test_ai_economy() -> void:
	print("enemy AI economy")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	ai.wave_interval = 0.0
	ai.enabled = true
	await _physics_frames(90)
	var henchmen := _team_units(1).filter(func(u: Creature) -> bool: return u is Henchman)
	_check(henchmen.all(func(u: Henchman) -> bool: return u.order == Creature.Order.GATHER), "AI puts its Henchmen to work")
	_check(not _building(1, "Lab").queue.is_empty(), "AI produces more Henchmen")
	_check(not _building(1, "Creature Chamber").queue.is_empty(), "AI produces creatures")
	await _unload(main)


func _test_hud_command_panel() -> void:
	print("HUD command panel")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	manager.select_units([_first(0, "Henchman")])
	await _process_frames(2)
	var buttons: Array = hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(hud.command_panel.visible and buttons.size() == 3, "Henchmen show a build menu with 3 buildings")
	buttons[1].pressed.emit()
	_check(manager.build_placer.is_active() and manager.build_placer.data.display_name == "Electrical Generator",
			"clicking a build button starts placement")
	_key(KEY_ESCAPE)
	_check(not manager.build_placer.is_active() and not manager.selected.is_empty(), "Esc cancels placement without deselecting")

	manager.select_building(_building(0, "Lab"))
	await _process_frames(2)
	buttons = hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(buttons.size() == 2, "the Lab shows Henchman + Cancel buttons")
	buttons[0].pressed.emit()
	_check(_building(0, "Lab").queue.size() == 1, "clicking a production button queues a unit")
	await _unload(main)


# --- Helpers ------------------------------------------------------------------

func _load_map() -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.get_node("EnemyAI").enabled = false
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _physics_frames(10)
	return main


func _unload(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _team_units(team: int) -> Array[Creature]:
	var result: Array[Creature] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team:
			result.append(unit)
	return result


## Combat units (everything except Henchmen) of [param team].
func _fighters(team: int) -> Array[Creature]:
	var result: Array[Creature] = []
	for unit in _team_units(team):
		if unit is not Henchman:
			result.append(unit)
	return result


func _building(team: int, display_name: String, newest := false) -> Building:
	var found: Building = null
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.data.display_name == display_name:
			found = building
			if not newest:
				break
	return found


func _nearest_pile(from: Vector3) -> CoalPile:
	var best: CoalPile = null
	for pile: CoalPile in get_tree().get_nodes_in_group("coal_piles"):
		if best == null or pile.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = pile
	return best


func _first(team: int, display_name: String) -> Creature:
	for unit in _team_units(team):
		if unit.stats.display_name == display_name:
			return unit
	return null


## Removes every unit except [param keep] so a scenario runs undisturbed.
func _isolate(keep: Array) -> void:
	for unit: Creature in get_tree().get_nodes_in_group("units"):
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
		await get_tree().physics_frame


func _process_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _click(position: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = position
		event.pressed = pressed
		get_tree().root.push_input(event)


func _drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from
	press.pressed = true
	get_tree().root.push_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	get_tree().root.push_input(motion)
	var release := press.duplicate()
	release.position = to
	release.pressed = false
	get_tree().root.push_input(release)


func _key(keycode: Key, ctrl := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.pressed = true
	get_tree().root.push_input(event)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
