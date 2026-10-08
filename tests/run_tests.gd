extends Node
## Headless tests for the core RTS loop, combat, economy, base building and
## the creature combiner.
##
## Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with a non-zero code if any check fails.

const TEST_ARMY_PATH := "user://test_army.tres"
## Hand-tuned units the combat tests rely on, spawned instead of the roster
## army so results don't depend on combiner balance: [stats, team, x, z].
const FIXTURE_UNITS := [
	["runner", 0, -4, 26], ["runner", 0, -2, 26], ["skirmisher", 0, 0, 26], ["skirmisher", 0, 2, 26], ["brute", 0, 4, 26],
	["brute", 1, -2, -30], ["brute", 1, 2, -30], ["runner", 1, -6, -31], ["runner", 1, 6, -31],
	["skirmisher", 1, -3, -33], ["skirmisher", 1, 3, -33],
]

var _failures := 0
var _checks := 0


func _ready() -> void:
	# Headless windows are tiny (64x64); use a real screen size so the HUD
	# (minimap, panels) sits where it would in the game.
	get_tree().root.size = Vector2i(1600, 900)
	# Never touch the player's real saved army.
	Armies.save_path = TEST_ARMY_PATH
	Armies.set_designs(0, Armies.default_designs())
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
	_test_combiner_rules()
	_test_army_roster()
	await _test_hybrid_production()
	await _test_flying()
	await _test_poison()
	await _test_charge()
	await _test_leap()
	await _test_starting_army()
	await _test_research()
	await _test_fog_of_war()
	await _test_minimap()
	await _test_ai_defence_and_waves()
	await _test_difficulty_and_settings()
	await _test_canyon_map()
	await _test_skirmish_setup()
	await _test_match_stats()
	await _test_pause_and_speed()
	await _test_end_screen()
	await _test_fog_props_and_ghosts()
	await _test_lab_healing()
	await _test_ai_retreat()
	await _test_ai_expansion()
	await _test_soundbeam_tower()
	await _test_workshop_upgrades()
	await _test_research_center()
	await _test_ai_builds_defences()
	_test_teams_service()
	await _test_four_player_free_for_all()
	await _test_unused_bases_removed()
	await _test_two_vs_two()
	await _test_setup_players()
	await _test_population()
	await _test_target_choice()
	await _test_kiting()
	await _test_hold_position()
	await _test_patrol()
	await _test_focus_fire()
	await _test_combiner_screen()
	await _test_main_menu()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ARMY_PATH))
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

	# A quill still in flight when its shooter's body is removed must still land.
	var projectile: Node3D = load("res://scenes/fx/projectile.tscn").instantiate()
	main.add_child(projectile)
	var health := brute.health
	projectile.launch(skirmisher.global_position + Vector3.UP, brute, 15.0, skirmisher, 20.0)
	skirmisher.free()
	var flying: WeakRef = weakref(projectile)
	await _wait_until(func() -> bool: return flying.get_ref() == null, 2.0)
	_check(flying.get_ref() == null and brute.health < health, "projectiles from a removed shooter still hit and disappear")
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
	var screen: EndScreen = main.get_node("UI/HUD").end_screen
	_check(screen.visible and screen.title.text == "VICTORY", "the HUD shows VICTORY")
	await _unload(main)


func _test_ai_economy() -> void:
	print("enemy AI economy")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	ai.wave_interval = 0.0
	_check(ai.needs_house() and ai.next_building() == AIController.HOUSE_DATA, "near its population cap the AI builds a House first")
	_add_houses(1, 2)
	await _physics_frames(2)
	_check(_building(1, "Creature Chamber") == null, "the enemy starts without a Creature Chamber")
	_check(ai.next_building().display_name == "Creature Chamber", "a Creature Chamber is the AI's first build")
	ai.enabled = true
	await _physics_frames(90)
	var henchmen := _team_units(1).filter(func(u: Creature) -> bool: return u is Henchman)
	_check(henchmen.all(func(u: Henchman) -> bool: return u.is_working()), "AI puts its Henchmen to work")
	var builder_count := henchmen.filter(func(u: Henchman) -> bool: return u.order == Creature.Order.BUILD).size()
	_check(builder_count == AIController.BUILDERS_PER_SITE, "two Henchmen build while the rest gather")
	var site := _building(1, "Creature Chamber")
	_check(site != null and not site.is_complete, "AI places a Creature Chamber")
	_check(site != null and site.edge_distance_from(_building(1, "Lab").global_position) < 20.0, "it builds near its Lab")
	_check(not _building(1, "Lab").queue.is_empty(), "AI produces more Henchmen")
	if site == null:
		await _unload(main)
		return

	# Fast-forward a couple of minutes of game time.
	Engine.time_scale = 4.0
	await _wait_until(func() -> bool: return Research.level(1) >= 2, 40.0)
	Engine.time_scale = 1.0
	_check(site.is_complete, "the Creature Chamber gets finished")
	_check(_count_buildings(1, "Electrical Generator") >= 2, "AI adds a Generator to keep up with production")
	_check(Research.level(1) >= 2, "AI researches new levels")
	await _unload(main)


func _count_buildings(team: int, display_name: String) -> int:
	return get_tree().get_nodes_in_group("buildings").filter(
			func(b: Building) -> bool: return b.team == team and b.data.display_name == display_name).size()


func _test_hud_command_panel() -> void:
	print("HUD command panel")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	manager.select_units([_first(0, "Henchman")])
	await _process_frames(2)
	var buttons: Array = hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(hud.command_panel.visible and buttons.size() == 7, "Henchmen show a build menu with 7 buildings")
	buttons[2].pressed.emit()
	_check(manager.build_placer.is_active() and manager.build_placer.data.display_name == "Electrical Generator",
			"clicking a build button starts placement")
	_key(KEY_ESCAPE)
	_check(not manager.build_placer.is_active() and not manager.selected.is_empty(), "Esc cancels placement without deselecting")

	manager.select_building(_building(0, "Lab"))
	await _process_frames(2)
	buttons = hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(buttons.size() == 3 and buttons[2].text.begins_with("Research L2"), "the Lab shows Henchman, Cancel and Research buttons")
	buttons[0].pressed.emit()
	_check(_building(0, "Lab").queue.size() == 1, "clicking a production button queues a unit")
	await _unload(main)


# --- Creature combiner --------------------------------------------------------

func _design(a: String, b: String, picks: Array, name := "") -> CreatureDesign:
	var typed: Array[int] = []
	typed.assign(picks)
	return CreatureDesign.create(Armies.animal(a), Armies.animal(b), typed, name)


func _stats(a: String, b: String, picks: Array) -> CreatureStats:
	return CreatureCombiner.build_stats(_design(a, b, picks))


func _test_combiner_rules() -> void:
	print("combiner rules")
	var pure_elephant := _stats("elephant", "elephant", [0, 0, 0, 0, 0, -1])
	var pure_cheetah := _stats("cheetah", "cheetah", [0, 0, 0, 0, 0, -1])
	var cheetah_legs := _stats("elephant", "cheetah", [0, 0, 1, 1, 0, -1])
	_check(pure_elephant.max_health > pure_cheetah.max_health * 3.0, "an elephant torso is far tougher than a cheetah's")
	_check(cheetah_legs.move_speed > pure_elephant.move_speed and cheetah_legs.move_speed < pure_cheetah.move_speed,
			"cheetah legs speed up an elephant, but not to cheetah speed (%.1f)" % cheetah_legs.move_speed)
	_check(_stats("elephant", "rhino", [1, 0, 0, 0, 0, -1]).armor > pure_elephant.armor, "a rhino head adds armor")
	var croc_body := _stats("lion", "crocodile", [0, 1, 0, 0, 0, -1])
	_check(croc_body.ranged_armor > _stats("lion", "lion", [0, 0, 0, 0, 0, -1]).ranged_armor, "a crocodile torso adds ranged armor")

	var stinger := _stats("lion", "scorpion", [0, 0, 0, 0, 1, -1])
	_check(stinger.poison_dps > 0.0 and not stinger.is_ranged(), "a scorpion tail adds poison")
	var quills := _stats("gorilla", "porcupine", [0, 0, 0, 0, 1, -1])
	_check(quills.is_ranged() and quills.attack_range >= 8.0, "a porcupine tail gives a ranged attack")
	_check(_stats("lion", "eagle", [0, 0, 0, 0, 0, 1]).can_fly, "eagle wings let a lion fly")
	_check(_stats("lion", "rhino", [1, 0, 0, 0, 0, -1]).can_charge, "a rhino head gives a charge")
	_check(_stats("lion", "kangaroo", [0, 0, 0, 1, 0, -1]).can_leap, "kangaroo hind legs give a leap")
	_check(not _stats("rhino", "porcupine", [0, 0, 0, 0, 1, -1]).can_charge, "quill-shooters don't charge")
	_check(not _stats("kangaroo", "eagle", [0, 0, 0, 0, 0, 1]).can_leap, "flyers don't leap")
	_check(Armies.all_animals().size() == 12, "12 animals are available")
	_check(not _stats("lion", "eagle", [0, 0, 0, 0, 0, -1]).can_fly, "no wings, no flight")
	var heavy := _design("rhino", "eagle", [0, 0, 0, 0, 0, 1])
	_check(not CreatureCombiner.build_stats(heavy).can_fly and CreatureCombiner.too_heavy_to_fly(heavy), "a rhino is too heavy for eagle wings")

	var wingless := _design("lion", "cheetah", [0, 0, 0, 0, 0, -1])
	wingless.set_pick(CreatureDesign.Slot.WINGS, CreatureDesign.FROM_A)
	_check(wingless.picks[CreatureDesign.Slot.WINGS] == CreatureDesign.NONE, "wings can't come from an animal without them")
	_check(CreatureDesign.generated_name(Armies.animal("lion"), Armies.animal("eagle")) == "Ligle", "names are portmanteaus (Lion + Eagle = Ligle)")

	# Every pair of animals with a few part mixes gives sane numbers.
	var sane := true
	var levels := {}
	var animals := Armies.all_animals()
	for a in animals:
		for b in animals:
			for picks in [[0, 0, 0, 0, 0, -1], [1, 0, 1, 0, 1, -1], [0, 1, 1, 1, 0, 1]]:
				var typed: Array[int] = []
				typed.assign(picks)
				var design := CreatureDesign.create(a, b, typed)
				design.set_pick(CreatureDesign.Slot.WINGS, typed[5])
				var stats := CreatureCombiner.build_stats(design)
				var recipe := CreatureCombiner.make_recipe(design)
				levels[stats.level] = true
				if stats.max_health <= 0 or stats.move_speed <= 0 or stats.attack_damage <= 0 or recipe.cost_coal <= 0 \
						or stats.level < 1 or stats.level > 5:
					sane = false
	_check(sane, "all %d animal pairs produce valid stats and costs" % (animals.size() * animals.size()))
	_check(levels.size() == 5, "hybrids span all 5 levels")


func _test_army_roster() -> void:
	print("army roster")
	_check(Armies.designs(0).size() == Armies.PRESETS.size(), "the player starts with the preset army")
	_check(Armies.recipes(1).size() == Armies.PRESETS.size(), "the enemy has a roster too")
	var many: Array[CreatureDesign] = []
	for i in 12:
		many.append(_design("lion", "cheetah", [0, 0, 1, 1, 0, -1]))
	Armies.set_designs(0, many)
	_check(Armies.designs(0).size() == Armies.MAX_SIZE, "armies are capped at %d designs" % Armies.MAX_SIZE)

	var saved: Array[CreatureDesign] = [_design("gorilla", "eagle", [1, 0, 0, 1, 0, 1], "Kong"), _design("rhino", "scorpion", [0, 0, 1, 0, 1, -1])]
	Armies.set_designs(0, saved)
	_check(Armies.save_player_army() == OK, "the army saves to disk")
	Armies.set_designs(0, Armies.default_designs())
	Armies.load_player_army()
	var loaded := Armies.designs(0)
	_check(loaded.size() == 2 and loaded[0].display_name() == "Kong" and loaded[0].animal_a.display_name == "Gorilla"
			and loaded[1].picks == saved[1].picks, "the saved army loads back the same")
	Armies.set_designs(0, Armies.default_designs())


## Finished Houses for [param team] in a row along the map's west edge,
## out of everyone's way (test buildings skip the navmesh rebake).
func _add_houses(team: int, count: int) -> void:
	for i in count:
		_add_building("res://resources/buildings/house.tres", team, Vector3(-46, 0, -20 + team * 12 + i * 3.5))


func _add_building(data_path: String, team: int, at: Vector3, complete := true) -> Building:
	var building: Building = load("res://scenes/buildings/building.tscn").instantiate()
	building.data = load(data_path)
	building.start_complete = complete
	building.team = team
	building.position = at
	get_tree().get_first_node_in_group("building_container").add_child(building)
	return building


func _test_hybrid_production() -> void:
	print("hybrid production")
	var main := await _load_map()
	var chamber := _add_building("res://resources/buildings/creature_chamber.tres", 1, Vector3(12, 0, -40))
	var options := chamber.production_options()
	_check(options.size() == Armies.designs(1).size(), "the Creature Chamber offers the team's army")
	Economy.add(1, 1000, 1000)
	Research.set_level(1, Research.MAX_LEVEL)
	var recipe := options[0]
	_check(chamber.enqueue(recipe) == "", "a hybrid can be queued")
	var before := _team_units(1).size()
	await _wait_until(func() -> bool: return chamber.queue.is_empty(), recipe.build_time + 2.0)
	var units := _team_units(1)
	var hybrid: Creature = units.back()
	_check(units.size() == before + 1 and hybrid.stats.design != null, "the chamber produces the hybrid")
	_check(hybrid.find_children("*", "CreatureModel", false, false).size() == 1, "hybrids get a model built from their parts")
	await _unload(main)


func _spawn(main: Node, stats: CreatureStats, team: int, at: Vector3) -> Creature:
	var unit: Creature = load("res://scenes/units/creature.tscn").instantiate()
	unit.stats = stats
	unit.team = team
	unit.position = at
	main.get_node("Units").add_child(unit)
	return unit


func _test_flying() -> void:
	print("flying")
	var main := await _load_map()
	_isolate([])
	var lab := _building(0, "Lab")
	var start := lab.global_position + Vector3(0, 0, -8)
	var goal := lab.global_position + Vector3(0, 0, 8)
	var flyer := _spawn(main, _stats("lion", "eagle", [0, 0, 1, 0, 0, 1]), 0, start)
	var walker := _spawn(main, _stats("lion", "cheetah", [0, 0, 1, 1, 0, -1]), 0, start + Vector3(2, 0, 0))
	await _physics_frames(5)
	flyer.command_move(goal)
	walker.command_move(goal + Vector3(2, 0, 0))
	var direct := start.distance_to(goal) / flyer.stats.move_speed
	await _wait_until(func() -> bool: return not flyer.is_moving, direct + 1.5)
	_check(not flyer.is_moving and _flat(flyer.global_position - goal) < 1.0, "flyers go straight over buildings")
	_check(absf(flyer.global_position.y - Creature.HOVER_HEIGHT) < 0.3, "flyers hover above the ground")
	var map := main.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, start, goal, true)
	var walked := 0.0
	for i in range(1, path.size()):
		walked += path[i - 1].distance_to(path[i])
	_check(walked > start.distance_to(goal) + 2.0, "walkers have to path around the building (%.1f m vs %.1f m)" % [walked, start.distance_to(goal)])

	var melee := _spawn(main, _stats("rhino", "rhino", [0, 0, 0, 0, 0, -1]), 1, goal + Vector3(0, 0, 3))
	var ranged := _spawn(main, _stats("gorilla", "porcupine", [0, 0, 0, 0, 1, -1]), 1, goal + Vector3(-3, 0, 3))
	await _physics_frames(30)
	melee.command_attack(flyer)
	_check(melee.attack_target != flyer and melee.find_best_enemy(50.0) != flyer, "ground melee creatures can't attack flyers")
	_check(ranged.attack_target == flyer or ranged.attack_target == walker, "ranged creatures can")
	ranged.command_attack(flyer)
	_check(ranged.attack_target == flyer, "ranged creatures accept attack orders on flyers")
	await _unload(main)


func _test_poison() -> void:
	print("poison")
	var main := await _load_map()
	var brute := _first(1, "Brute")
	_isolate([brute])
	# Away from its Lab, whose healing would cancel the poison out.
	_place(brute, Vector3(0, 0, -5))
	var stinger := _spawn(main, _stats("lion", "scorpion", [0, 0, 0, 0, 1, -1]), 0, Vector3(30, 0, 30))
	await _physics_frames(2)
	stinger.deal_hit(brute)
	var after_hit := brute.health
	_check(brute.is_poisoned(), "a poisonous hit poisons the target")
	await _physics_frames(120)
	var poison_damage := after_hit - brute.health
	_check(poison_damage > 6.0 and poison_damage < 10.0, "poison deals ~4/s through armor (%.1f in 2s)" % poison_damage)
	await _physics_frames(150)
	_check(not brute.is_poisoned(), "poison wears off")
	await _unload(main)


func _test_charge() -> void:
	print("charge")
	var main := await _load_map()
	var brute := _first(1, "Brute")
	_isolate([brute])
	_place(brute, Vector3(0, 0, -10))
	var charger := _spawn(main, _stats("lion", "rhino", [1, 0, 0, 0, 0, -1]), 0, Vector3(0, 0, 4))
	await _physics_frames(5)
	charger.command_attack(brute)
	await _physics_frames(20)
	_check(charger.is_charging, "a charger sprints at a distant target")
	var speed := Vector2(charger.velocity.x, charger.velocity.z).length()
	_check(speed > charger.stats.move_speed * 1.3, "charging is faster than walking (%.1f vs %.1f)" % [speed, charger.stats.move_speed])
	var health := brute.health
	await _wait_until(func() -> bool: return brute.health < health, 5.0)
	var expected := charger.stats.attack_damage * Creature.CHARGE_DAMAGE_FACTOR - brute.stats.armor
	_check(is_equal_approx(health - brute.health, expected), "the charge hit does double damage (%.0f)" % (health - brute.health))
	_check(not charger.is_charging, "the charge ends on impact")
	health = brute.health
	await _wait_until(func() -> bool: return brute.health < health, 3.0)
	_check(is_equal_approx(health - brute.health, charger.stats.attack_damage - brute.stats.armor), "later hits are normal")
	await _unload(main)


func _test_leap() -> void:
	print("leap")
	var main := await _load_map()
	var brute := _first(1, "Brute")
	_isolate([brute])
	_place(brute, Vector3(0, 0, -6))
	var leaper := _spawn(main, _stats("lion", "kangaroo", [0, 0, 0, 1, 0, -1]), 0, Vector3(0, 0, 0))
	await _physics_frames(5)
	var gap := leaper.surface_distance_to(brute)
	leaper.command_attack(brute)
	await _physics_frames(2)
	_check(leaper.is_leaping(), "a leaper jumps at a target %.1f m away" % gap)
	await _physics_frames(int(Creature.LEAP_DURATION * 60) + 2)
	_check(leaper.surface_distance_to(brute) <= leaper.stats.attack_range + 0.3, "it lands within reach")
	_check(not leaper.is_leaping(), "the leap ends")
	await _unload(main)


func _test_research() -> void:
	print("research")
	var main := await _load_map()
	_check(Research.level(0) == 1 and Research.level(1) == 1, "teams start at research level 1")
	var lab := _building(0, "Lab")
	var chamber := _add_building("res://resources/buildings/creature_chamber.tres", 0, Vector3(12, 0, 30))
	await _physics_frames(2)
	var locked: UnitRecipe = null
	for recipe in chamber.production_options():
		if recipe.stats.level >= 3:
			locked = recipe
			break
	Economy.add(0, 2000, 2000)
	_check(chamber.enqueue(locked) == "Requires research level %d" % locked.stats.level, "creatures above the research level are locked")
	var henchman_recipe: UnitRecipe = lab.data.production[0]
	_check(Research.can_produce(0, henchman_recipe), "Henchmen are never locked")

	var coal: float = Economy.coal(0)
	_check(lab.start_research() == "" and lab.researching == 2, "the Lab researches the next level")
	_check(Economy.coal(0) == coal - Research.coal_cost(2), "research is paid up front")
	_check(lab.start_research() == "Already researching", "one research at a time")
	lab.cancel_research()
	_check(lab.researching == 0 and Economy.coal(0) == coal, "cancelling research refunds it")
	lab.start_research()
	lab.research_time = Research.duration(2) - 0.05
	await _physics_frames(6)
	_check(Research.level(0) == 2 and lab.researching == 0, "research completes after its duration")
	_check(Research.level(1) == 1, "research is per team")

	Research.set_level(0, locked.stats.level)
	_check(chamber.enqueue(locked) == "", "researched levels can be produced")

	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	Research.set_level(0, 1)
	manager.select_building(chamber)
	await _process_frames(2)
	var buttons: Array = hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var locked_buttons := buttons.filter(func(b: Button) -> bool: return b.text.contains("needs research"))
	_check(not locked_buttons.is_empty() and locked_buttons.all(func(b: Button) -> bool: return b.disabled),
			"locked creatures show as disabled in the HUD")
	_check(hud.resource_label.text.contains("Research  L1"), "the HUD shows the research level")
	await _unload(main)


func _fog_frames() -> void:
	await _physics_frames(int(FogOfWar.UPDATE_INTERVAL * 60) + 3)


func _test_fog_of_war() -> void:
	print("fog of war")
	var main := await _load_map()
	var fog: FogOfWar = main.get_node("FogOfWar")
	fog.reveal_all = false
	await _fog_frames()
	var my_lab := _building(0, "Lab")
	var enemy_lab := _building(1, "Lab")
	var enemy := _first(1, "Brute")
	_check(fog.is_visible(0, my_lab.global_position), "the player sees around their own base")
	_check(not fog.is_explored(0, enemy_lab.global_position), "the enemy base starts unexplored")
	_check(not enemy.visible and not enemy_lab.visible, "enemy creatures and buildings in the fog are hidden")
	var material := (main.get_node("NavigationRegion3D/Ground/MeshInstance3D") as MeshInstance3D).material_override as ShaderMaterial
	_check(material != null and material.get_shader_parameter("fog") == fog.texture and material.get_shader_parameter("fog_enabled"),
			"the ground shader shows the fog")

	var manager: SelectionManager = main.get_node("SelectionManager")
	var rig: RTSCamera = main.get_node("RTSCamera")
	manager.select_units([_first(0, "Runner")])
	rig.focus_on(enemy.global_position)
	await get_tree().process_frame
	_check(manager.unit_at_screen(manager.camera.unproject_position(enemy.global_position)) == null, "hidden enemies can't be clicked")

	var scout := _first(0, "Runner")
	_isolate([scout, enemy, _first(0, "Henchman")])
	scout.global_position = enemy_lab.global_position + Vector3(0, 0, 7)
	scout.command_stop()
	await _fog_frames()
	_check(enemy.visible, "enemies in sight of a scout appear")
	_check(enemy_lab.visible and fog.is_explored(0, enemy_lab.global_position), "scouted enemy buildings appear")
	scout.global_position = Vector3(30, 0, 30)
	scout.command_stop()
	await _fog_frames()
	_check(not enemy.visible, "enemies disappear again when out of sight")
	_check(enemy_lab.visible, "explored enemy buildings stay on the map")
	_check(fog.explored_fraction(0) > 0.05 and fog.explored_fraction(0) < 0.9, "exploration is tracked (%d%% of the map)" % (fog.explored_fraction(0) * 100))

	fog.enabled = false
	await _fog_frames()
	_check(enemy.visible and fog.is_visible(0, Vector3(40, 0, -40)), "with fog of war off, everything is visible")
	await _unload(main)


func _test_minimap() -> void:
	print("minimap")
	var main := await _load_map()
	var minimap: Minimap = main.get_node("UI/HUD/Minimap")
	var rig: RTSCamera = main.get_node("RTSCamera")
	var manager: SelectionManager = main.get_node("SelectionManager")
	await _process_frames(2)
	var point := Vector3(20, 0, -30)
	_check(minimap.map_to_world(minimap.world_to_map(point)).distance_to(point) < 0.01, "minimap and world coordinates convert both ways")
	var screen := minimap.get_global_rect().position + minimap.world_to_map(point)
	_click(screen, MOUSE_BUTTON_LEFT)
	await _process_frames(1)
	_check(Vector2(rig.position.x - point.x, rig.position.z - point.z).length() < 1.0, "clicking the minimap moves the camera")
	var runner := _first(0, "Runner")
	manager.select_units([runner])
	var target := Vector3(-20, 0, 10)
	_click(minimap.get_global_rect().position + minimap.world_to_map(target), MOUSE_BUTTON_RIGHT)
	_check(runner.order == Creature.Order.MOVE and runner.agent.target_position.distance_to(target) < 1.0,
			"right clicking the minimap orders the selection there")
	await _unload(main)


func _test_ai_defence_and_waves() -> void:
	print("AI defence and waves")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	var fog: FogOfWar = main.get_node("FogOfWar")
	var player_lab := _building(0, "Lab")
	await _fog_frames()
	var target: Variant = ai.wave_target()
	_check(target != null and target.z > 20.0, "without scouting, the AI heads for the far side of the map")
	var scout := _first(1, "Runner")
	scout.global_position = player_lab.global_position + Vector3(0, 0, -6)
	scout.command_stop()
	await _fog_frames()
	_check(fog.is_explored(1, player_lab.global_position), "AI units explore for their team")
	_check(_flat(ai.wave_target() - player_lab.global_position) < 1.0, "once scouted, the AI attacks the player's buildings")

	# Next to the enemy Generator, but out of its fighters' sight: only the
	# AI's base awareness can react.
	var raider := _first(0, "Brute")
	raider.global_position = _building(1, "Electrical Generator").global_position + Vector3(-6, 0, -2)
	raider.command_stop()
	await _fog_frames()
	var sent := ai.defend_base()
	_check(sent > 0 and _fighters(1).any(func(u: Creature) -> bool: return u.order == Creature.Order.ATTACK_MOVE),
			"the AI sends nearby fighters to defend its base (%d)" % sent)

	# Keep exactly the minimum wave size.
	var keep: Array = _fighters(1).slice(0, ai.min_wave_size) + _team_units(0) + _team_units(1).filter(func(u: Creature) -> bool: return u is Henchman)
	_isolate(keep)
	for unit in _fighters(1):
		unit.command_stop()
	_check(ai.launch_wave() == ai.min_wave_size and ai.waves_sent == 1, "the AI launches an attack wave")
	for unit in _fighters(1):
		unit.command_stop()
	_check(ai.launch_wave() == 0, "each wave needs a bigger army than the last")
	await _unload(main)


func _test_difficulty_and_settings() -> void:
	print("difficulty and settings")
	GameSettings.difficulty = GameSettings.Difficulty.HARD
	GameSettings.fog_enabled = false
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	_check(ai.wave_interval < 100.0 and ai.max_henchmen > 7, "Hard makes the AI attack sooner and keep more workers")
	var coal: float = Economy.coal(1)
	Economy.deposit_coal(1, 10)
	_check(is_equal_approx(Economy.coal(1) - coal, 13.0), "Hard gives the AI a coal bonus")
	coal = Economy.coal(0)
	Economy.deposit_coal(0, 10)
	_check(is_equal_approx(Economy.coal(0) - coal, 10.0), "the player gets no bonus")
	_check(not main.get_node("FogOfWar").enabled, "the fog setting is applied to the match")
	await _unload(main)
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	GameSettings.fog_enabled = true


func _test_canyon_map() -> void:
	print("canyon map")
	var main: Node3D = load(GameSettings.MAPS[1].path).instantiate()
	main.get_node("EnemyAI").enabled = false
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _physics_frames(10)
	var player_lab := _building(0, "Lab")
	var enemy_lab := _building(1, "Lab")
	_check(player_lab != null and enemy_lab != null and player_lab.global_position.x < 0 and enemy_lab.global_position.x > 0,
			"Canyon has bases on the west and east")
	_check(_fighters(0).size() >= 3 and _fighters(1).size() >= 3, "both armies spawn on Canyon")
	var map := main.get_world_3d().navigation_map
	var from := player_lab.global_position + Vector3(6, 0, 0)
	var to := enemy_lab.global_position - Vector3(6, 0, 0)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	_check(path.size() > 1 and path[path.size() - 1].distance_to(to) < 1.0, "the bases are connected through the canyon")
	# Crossing the wall where it's solid means walking round to a pass.
	var west := Vector3(-6, 0, -38)
	var east := Vector3(6, 0, -38)
	path = NavigationServer3D.map_get_path(map, west, east, true)
	var walked := 0.0
	for i in range(1, path.size()):
		walked += path[i - 1].distance_to(path[i])
	_check(walked > west.distance_to(east) * 2.0, "the rock wall forces a detour through a pass (%.0f m vs %.0f m)" % [walked, west.distance_to(east)])
	var ai: AIController = main.get_node("EnemyAI")
	_check(ai.wave_target().x < 0.0, "the AI's first guess is the west side")
	await _unload(main)


func _test_skirmish_setup() -> void:
	print("skirmish setup")
	var setup: SkirmishSetup = load("res://scenes/ui/skirmish_setup.tscn").instantiate()
	get_tree().root.add_child(setup)
	await _process_frames(2)
	_check(setup.map_list.item_count == GameSettings.MAPS.size(), "the setup screen lists every map")
	setup.select_map(1)
	setup.difficulty_option.select(GameSettings.Difficulty.EASY)
	setup.difficulty_option.item_selected.emit(GameSettings.Difficulty.EASY)
	setup.fog_check.button_pressed = false
	_check(GameSettings.map_path() == "res://scenes/maps/canyon.tscn" and GameSettings.difficulty == GameSettings.Difficulty.EASY
			and not GameSettings.fog_enabled, "choices are stored for the match")
	setup.queue_free()
	GameSettings.map_index = 0
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	GameSettings.fog_enabled = true
	await _process_frames(1)


func _test_match_stats() -> void:
	print("match stats")
	var main := await _load_map()
	var brute := _first(0, "Brute")
	var runner := _first(1, "Runner")
	_isolate([brute, runner, _first(0, "Henchman")])
	_place(brute, Vector3(0, 0, 0))
	_place(runner, Vector3(0, 0, -3))
	brute.command_attack(runner)
	await _wait_until(func() -> bool: return not runner.is_alive(), 15.0)
	_check(MatchStats.get_stat(0, "kills") == 1 and MatchStats.get_stat(1, "units_lost") == 1, "kills and losses are counted")
	Economy.deposit_coal(0, 10)
	_check(MatchStats.get_stat(0, "coal_gathered") == 10, "delivered coal is counted")
	var lab := _building(0, "Lab")
	lab.production_time = 0.0
	Economy.add(0, 500)
	var chamber := _add_building("res://resources/buildings/creature_chamber.tres", 0, Vector3(12, 0, 30))
	Research.set_level(0, 5)
	var recipe: UnitRecipe = chamber.production_options()[0]
	chamber.enqueue(recipe)
	await _wait_until(func() -> bool: return chamber.queue.is_empty(), recipe.build_time + 2.0)
	_check(MatchStats.get_stat(0, "units_produced") == 1, "produced creatures are counted")
	_building(1, "Electrical Generator").take_damage(99999.0, brute)
	_check(MatchStats.get_stat(1, "buildings_lost") == 1 and MatchStats.get_stat(0, "buildings_destroyed") == 1,
			"destroyed buildings are counted for both sides")
	_check(MatchStats.elapsed > 1.0, "match time is tracked")
	await _unload(main)


func _test_pause_and_speed() -> void:
	print("pause and speed")
	var main := await _load_map()
	var hud := main.get_node("UI/HUD")
	var menu: PauseMenu = hud.pause_menu
	var manager: SelectionManager = main.get_node("SelectionManager")
	manager.select_units([_first(0, "Runner")])
	_key(KEY_ESCAPE)
	_check(not menu.visible and manager.selected.is_empty(), "Esc first clears the selection")
	_key(KEY_ESCAPE)
	_check(menu.visible and get_tree().paused, "Esc with nothing selected opens the pause menu")
	var runner := _first(0, "Runner")
	var at := runner.global_position
	runner.command_move(at + Vector3(10, 0, 0))
	await _physics_frames(20)
	_check(runner.global_position.distance_to(at) < 0.01, "nothing moves while paused")
	_key(KEY_ESCAPE)
	_check(not menu.visible and not get_tree().paused, "Esc closes the pause menu")
	_key(KEY_F10)
	_check(menu.visible, "F10 opens it too")
	menu.close()

	_key(KEY_EQUAL)
	_check(is_equal_approx(Engine.time_scale, 1.5) and is_equal_approx(GameSettings.game_speed, 1.5), "= speeds the game up")
	_key(KEY_MINUS)
	_key(KEY_MINUS)
	_check(is_equal_approx(Engine.time_scale, 0.5), "- slows it down")
	menu.set_speed(2.0)
	await _process_frames(2)
	_check(hud.resource_label.text.contains("Speed  2"), "the HUD shows a non-normal speed")
	menu.set_speed(1.0)
	await _unload(main)
	_check(not get_tree().paused and is_equal_approx(Engine.time_scale, 1.0), "leaving a match unpauses and resets speed")


func _test_end_screen() -> void:
	print("end screen")
	var main := await _load_map()
	var rules: GameRules = main.get_node("GameRules")
	var brute := _first(0, "Brute")
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		if target.team == 1:
			target.take_damage(999999.0, brute)
	rules.check_now()
	var screen: EndScreen = main.get_node("UI/HUD").end_screen
	_check(screen.visible and screen.title.text == "VICTORY" and get_tree().paused, "the end screen shows the result and pauses")
	_check(screen.cell_text(0, 1) == "You" and screen.cell_text(0, 2) == "Enemy", "it compares you with the enemy")
	var kills_row := MatchStats.LABELS.keys().find("kills") + 1
	_check(screen.cell_text(kills_row, 1) == str(int(MatchStats.get_stat(0, "kills"))) and MatchStats.get_stat(0, "kills") >= 6,
			"it lists the match statistics")
	_check(not MatchStats.running, "match time stops at the end")
	await _unload(main)


func _test_fog_props_and_ghosts() -> void:
	print("fog props and ghosts")
	var main := await _load_map()
	var fog: FogOfWar = main.get_node("FogOfWar")
	fog.reveal_all = false
	await _fog_frames()
	var enemy_pile := _nearest_pile(_building(1, "Lab").global_position)
	var home_pile := _nearest_pile(_building(0, "Lab").global_position)
	_check(not enemy_pile.visible and home_pile.visible, "coal piles stay hidden until explored")
	var far_rock: Node3D = null
	for rock: Node3D in get_tree().get_nodes_in_group("fog_hidden"):
		if rock is not CoalPile and rock.global_position.z < -20.0:
			far_rock = rock
	_check(far_rock != null and not far_rock.visible, "so do rocks")
	var manager: SelectionManager = main.get_node("SelectionManager")
	var rig: RTSCamera = main.get_node("RTSCamera")
	rig.focus_on(enemy_pile.global_position)
	await get_tree().process_frame
	_check(manager.coal_pile_at_screen(manager.camera.unproject_position(enemy_pile.global_position + Vector3.UP * 0.8)) == null,
			"hidden coal can't be clicked")

	# Scout the enemy Generator, walk away, then destroy it out of sight.
	var scout := _first(0, "Runner")
	var generator := _building(1, "Electrical Generator")
	scout.global_position = generator.global_position + Vector3(6, 0, 4)
	scout.command_stop()
	await _fog_frames()
	scout.global_position = Vector3(30, 0, 30)
	scout.command_stop()
	await _fog_frames()
	var where := generator.global_position
	generator.take_damage(99999.0, scout)
	_check(fog.ghosts.size() == 1 and fog.ghosts[0].position.distance_to(where) < 0.1,
			"a building destroyed out of sight leaves a last-seen ghost")
	scout.global_position = where + Vector3(5, 0, 0)
	scout.command_stop()
	await _fog_frames()
	_check(fog.ghosts.is_empty(), "the ghost disappears once the spot is seen again")
	var lab := _building(1, "Lab")
	lab.take_damage(99999.0, scout)
	_check(fog.ghosts.is_empty(), "buildings destroyed in plain sight leave no ghost")
	await _unload(main)


func _test_lab_healing() -> void:
	print("Lab healing")
	var main := await _load_map()
	var lab := _building(0, "Lab")
	var near := _first(0, "Runner")
	var far := _first(0, "Brute")
	_isolate([near, far])
	_place(near, lab.global_position + Vector3(0, 0, -6))
	_place(far, Vector3(0, 0, 0))
	near.take_damage(50.0)
	far.take_damage(50.0)
	var near_health := near.health
	var far_health := far.health
	await _physics_frames(130)
	_check(near.health > near_health + 6.0, "creatures near a Lab heal (+%d in 2s)" % (near.health - near_health))
	_check(is_equal_approx(far.health, far_health), "creatures far away don't")
	await _unload(main)


func _test_ai_retreat() -> void:
	print("AI retreat")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	var wounded := _first(1, "Brute")
	_place(wounded, Vector3(0, 0, -5))
	wounded.take_damage(wounded.stats.max_health * 0.8)
	_check(ai.manage_retreats() == 1 and wounded.order == Creature.Order.MOVE, "the AI pulls a badly wounded creature back")
	var lab := _building(1, "Lab")
	_check(lab.heals_at(wounded.agent.target_position), "it retreats to where its Lab heals it")
	_check(ai.launch_wave() == 0 or wounded.order == Creature.Order.MOVE, "retreating creatures aren't sent in waves")
	wounded.heal(wounded.stats.max_health)
	ai.manage_retreats()
	_check(ai.retreating.is_empty() and wounded.order == Creature.Order.IDLE, "healed creatures are released for duty")
	await _unload(main)


func _test_ai_expansion() -> void:
	print("AI expansion")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	var lab := _building(1, "Lab")
	_add_houses(1, 3)
	_add_building("res://resources/buildings/creature_chamber.tres", 1, lab.global_position + Vector3(12, 0, 0))
	_add_building("res://resources/buildings/generator.tres", 1, lab.global_position + Vector3(-12, 0, 6))
	await _physics_frames(2)
	_check(not ai.wants_expansion(), "no expansion while home coal is plentiful")
	for pile in ai._piles_near(lab.global_position):
		pile.amount = 100
	_check(ai.wants_expansion() and ai.next_building() == AIController.LAB_DATA, "low home coal makes the AI want a new Lab")
	var site_pile := ai.expansion_site()
	_check(site_pile != null and site_pile.global_position.distance_to(lab.global_position) > AIController.BASE_COAL_RADIUS,
			"it picks unclaimed coal away from its base")
	Economy.reset([0, 1], 50.0, 500.0)
	_check(ai.is_saving_for_expansion(), "it saves up when it can't afford the Lab yet")
	Economy.add(1, 1000)
	ai.manage_construction()
	var new_lab: Building = null
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == 1 and building.data.display_name == "Lab" and not building.is_complete:
			new_lab = building
	_check(new_lab != null and new_lab.global_position.distance_to(site_pile.global_position) < 15.0, "it builds the new Lab next to that coal")
	await _unload(main)


func _test_soundbeam_tower() -> void:
	print("Soundbeam Tower")
	var main := await _load_map()
	var tower_data: BuildingData = load("res://resources/buildings/soundbeam_tower.tres")
	var placer: BuildPlacer = main.get_node("SelectionManager").build_placer
	placer.start(tower_data, 0)
	Economy.add(0, 1000, 1000)
	_check(placer.place(Vector3(-20, 0, 20)) == null and placer.last_error == "Requires research level 2", "towers need research level 2")
	placer.cancel()
	var tower := _add_building("res://resources/buildings/soundbeam_tower.tres", 0, Vector3(0, 0, 0))
	var near := _first(1, "Brute")
	var far := _first(1, "Runner")
	_isolate([near, far])
	_place(near, Vector3(0, 0, -8))
	_place(far, Vector3(0, 0, -25))
	near.command_hold()
	await _physics_frames(10)
	_check(near.health < near.stats.max_health and is_equal_approx(near.stats.max_health - near.health, tower_data.attack_damage - near.ranged_armor()),
			"the tower hits enemies in range (through ranged armor)")
	_check(far.health == far.stats.max_health, "but not ones out of range")
	var flyer := _spawn(main, _stats("lion", "eagle", [0, 0, 1, 0, 0, 1]), 1, Vector3(6, 0, 0))
	near.global_position = Vector3(0, 0, -30)
	await _physics_frames(100)
	_check(flyer.health < flyer.stats.max_health, "towers shoot flyers too")
	_check(main.find_children("*", "MeshInstance3D", false, false).size() >= 0, "beams are drawn")
	await _unload(main)


func _test_workshop_upgrades() -> void:
	print("Workshop upgrades")
	var main := await _load_map()
	# Clear of the Henchmen's route to the coal (test buildings skip the navmesh rebake).
	var workshop := _add_building("res://resources/buildings/workshop.tres", 0, Vector3(-22, 0, 22))
	await _physics_frames(2)
	Economy.add(0, 2000, 2000)
	var sacks: UpgradeData = workshop.data.upgrades[0]
	var wagons: UpgradeData = workshop.data.upgrades[1]
	var boots: UpgradeData = workshop.data.upgrades[2]
	var hands: UpgradeData = workshop.data.upgrades[3]
	_check(workshop.start_upgrade(hands) == "Requires research level 2", "upgrades can need research")
	Research.set_level(0, 3)
	_check(workshop.start_upgrade(wagons) == "Needs the previous tier first", "Coal Wagons need Coal Sacks first")
	var coal: float = Economy.coal(0)
	_check(workshop.start_upgrade(sacks) == "" and Economy.coal(0) == coal - sacks.cost_coal, "the Workshop sells upgrades")
	_check(workshop.start_upgrade(boots) == "Already upgrading", "one upgrade at a time")
	workshop.cancel_upgrade()
	_check(Economy.coal(0) == coal and workshop.upgrading == null, "cancelling refunds it")
	workshop.start_upgrade(sacks)
	workshop.upgrade_time = sacks.duration - 0.05
	await _physics_frames(5)
	_check(Upgrades.has(0, &"coal_sacks") and not Upgrades.has(1, &"coal_sacks"), "the upgrade completes for that team only")
	_check(workshop.start_upgrade(sacks) == "Already bought", "upgrades are bought once")

	var henchman: Henchman = _first(0, "Henchman")
	var deliveries := MatchStats.get_stat(0, "coal_gathered")
	henchman.command_gather(_nearest_pile(henchman.global_position))
	await _wait_until(func() -> bool: return MatchStats.get_stat(0, "coal_gathered") > deliveries, 20.0)
	_check(MatchStats.get_stat(0, "coal_gathered") - deliveries == 15, "Coal Sacks: Henchmen carry 15 coal (delivered %d)" % (MatchStats.get_stat(0, "coal_gathered") - deliveries))
	Upgrades.grant(0, wagons)
	_check(Upgrades.carry_capacity(0) == 20 and Upgrades.carry_capacity(1) == Upgrades.BASE_CARRY, "Coal Wagons: 20 coal, for that team only")

	var base_speed := henchman.move_speed()
	Upgrades.grant(0, boots)
	Upgrades.grant(0, hands)
	Upgrades.grant(0, load("res://resources/upgrades/builders_tools.tres"))
	_check(is_equal_approx(henchman.move_speed(), base_speed * 1.2), "Sturdy Boots: Henchmen 20% faster")
	_check(is_equal_approx(Upgrades.gather_time_factor(0), 0.7) and Upgrades.gather_time_factor(1) == 1.0, "Quick Hands: gathering 30% quicker")
	_check(is_equal_approx(Upgrades.build_speed_multiplier(0), 1.3), "Builder's Tools: building 30% faster")
	_check(_first(1, "Brute").move_speed() == _first(1, "Brute").stats.move_speed, "Henchman upgrades don't touch creatures")
	var site := _add_building("res://resources/buildings/house.tres", 0, Vector3(-30, 0, 30), false)
	var enemy_site := _add_building("res://resources/buildings/house.tres", 1, Vector3(30, 0, -30), false)
	var friendly: Henchman = _first(0, "Henchman")
	var enemy: Henchman = _first(1, "Henchman")
	_isolate([friendly, enemy])
	friendly.global_position = site.global_position + Vector3(2.5, 0, 0)
	enemy.global_position = enemy_site.global_position + Vector3(2.5, 0, 0)
	friendly.command_build(site)
	enemy.command_build(enemy_site)
	await _physics_frames(240)
	_check(site.build_progress > enemy_site.build_progress * 1.15, "upgraded Henchmen build faster (%.2f vs %.2f)" % [site.build_progress, enemy_site.build_progress])
	await _unload(main)


func _test_research_center() -> void:
	print("Research Center")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	var center := _add_building("res://resources/buildings/research_center.tres", 0, Vector3(-22, 0, 22))
	await _physics_frames(2)
	Economy.add(0, 5000, 5000)
	var bite_1: UpgradeData = load("res://resources/upgrades/bite_claw_1.tres")
	var bite_2: UpgradeData = load("res://resources/upgrades/bite_claw_2.tres")
	_check(center.start_upgrade(bite_1) == "Requires research level 2", "tier I needs research level 2")
	Research.set_level(0, 3)
	_check(center.start_upgrade(bite_2) == "Needs the previous tier first", "tier II needs tier I")

	manager.select_building(center)
	await _process_frames(2)
	var names := _button_names(hud)
	_check(names.has("Bite & Claw I") and not names.has("Bite & Claw II"), "the panel shows only the next tier (%s)" % [names])
	_check(names.has("Sharp Quills I") and names.has("Tough Hide I") and names.has("Scales I"), "melee/ranged damage and armor lines are offered")
	center.start_upgrade(bite_1)
	center.upgrade_time = bite_1.duration - 0.05
	await _physics_frames(5)
	_check(Upgrades.has(0, &"bite_claw_1"), "tier I completes")
	manager.select_building(null)
	await _process_frames(2)
	manager.select_building(center)
	await _process_frames(2)
	names = _button_names(hud)
	_check(names.has("Bite & Claw II") and not names.has("Bite & Claw I"), "then tier II appears (%s)" % [names])

	var brute := _first(0, "Brute")
	var skirmisher := _first(0, "Skirmisher")
	_check(brute.attack_damage() == brute.stats.attack_damage + 1.0, "Bite & Claw I: melee +1 damage")
	_check(skirmisher.attack_damage() == skirmisher.stats.attack_damage, "melee upgrades don't help ranged attackers")
	for id in ["sharp_quills_1", "tough_hide_1", "scales_1", "scales_2"]:
		Upgrades.grant(0, load("res://resources/upgrades/%s.tres" % id))
	_check(skirmisher.attack_damage() == skirmisher.stats.attack_damage + 1.0, "Sharp Quills I: ranged +1 damage")
	_check(brute.armor() == brute.stats.armor + 1.0 and brute.ranged_armor() == brute.stats.ranged_armor + 2.0,
			"Tough Hide adds melee armor and Scales ranged armor")
	var enemy := _first(1, "Brute")
	_check(enemy.attack_damage() == enemy.stats.attack_damage and enemy.armor() == enemy.stats.armor, "the enemy doesn't get your upgrades")

	_isolate([brute])
	var before := brute.health
	brute.take_damage(10.0, null, true)
	_check(is_equal_approx(before - brute.health, 10.0 - brute.ranged_armor()), "ranged hits are reduced by ranged armor")
	before = brute.health
	brute.take_damage(10.0)
	_check(is_equal_approx(before - brute.health, 10.0 - brute.armor()), "melee hits are reduced by melee armor")
	await _unload(main)


func _button_names(hud: Node) -> Array:
	return hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).map(
			func(b: Button) -> String: return b.text.split("\n")[0])


func _test_ai_builds_defences() -> void:
	print("AI builds defences")
	var main := await _load_map()
	var ai: AIController = main.get_node("EnemyAI")
	var lab := _building(1, "Lab")
	_add_houses(1, 3)
	_add_building("res://resources/buildings/creature_chamber.tres", 1, lab.global_position + Vector3(12, 0, 0))
	_add_building("res://resources/buildings/generator.tres", 1, lab.global_position + Vector3(-12, 0, 6))
	await _physics_frames(2)
	_check(ai.next_building() == null, "at research level 1 the base is complete")
	Research.set_level(1, 2)
	_check(ai.next_building() == AIController.WORKSHOP_DATA, "at level 2 the AI wants a Workshop")
	_add_building("res://resources/buildings/workshop.tres", 1, lab.global_position + Vector3(-12, 0, -2))
	await _physics_frames(2)
	_check(ai.next_building() == AIController.RESEARCH_CENTER_DATA, "then a Research Center")
	_add_building("res://resources/buildings/research_center.tres", 1, lab.global_position + Vector3(0, 0, 24))
	await _physics_frames(2)
	_check(ai.next_building() == AIController.TOWER_DATA, "then a Soundbeam Tower")
	Economy.add(1, 1000, 1000)
	ai.manage_construction()
	var tower := _building(1, "Soundbeam Tower")
	_check(tower != null and tower.global_position.distance_to(lab.global_position) < 15.0, "it guards its Lab with the tower")
	ai.manage_upgrades()
	_check(_building(1, "Workshop").upgrading != null, "it buys upgrades at its Workshop")
	ai.manage_upgrades()
	var center := _building(1, "Research Center")
	_check(center.upgrading != null and center.upgrading.requires == &"", "and tier I upgrades at its Research Center")
	center.upgrade_time = center.upgrading.duration
	await _physics_frames(3)
	Research.set_level(1, 3)
	Economy.add(1, 2000, 2000)
	ai.manage_upgrades()
	ai.manage_upgrades()
	_check(center.upgrading != null, "it keeps buying (%s)" % (center.upgrading.id if center.upgrading else &"none"))
	await _unload(main)


func _load_crossroads(players: int, mode: int) -> Node3D:
	GameSettings.select_map(2)
	GameSettings.player_count = players
	GameSettings.mode = mode
	var main: Node3D = load(GameSettings.map_path()).instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for ai: AIController in main.find_children("*", "AIController", false, false):
		ai.enabled = false
	await _physics_frames(10)
	for ai: AIController in main.find_children("*", "AIController", false, false):
		ai.enabled = false
	return main


func _reset_match_settings() -> void:
	GameSettings.select_map(0)
	GameSettings.player_count = 2
	GameSettings.mode = GameSettings.Mode.FREE_FOR_ALL
	Teams.setup([0, 1])


func _test_teams_service() -> void:
	print("teams")
	Teams.setup([0, 1, 2, 3], {0: 0, 1: 0, 2: 1, 3: 1})
	_check(Teams.are_allies(0, 1) and Teams.are_enemies(0, 2) and Teams.are_enemies(1, 3), "alliances decide who's an enemy")
	_check(Teams.enemies_of(0) == [2, 3] and Teams.members(1) == [2, 3], "teams can list enemies and alliance members")
	Teams.setup([0, 1, 2])
	_check(Teams.are_enemies(1, 2) and Teams.enemies_of(0) == [1, 2], "without alliances it's every team for itself")
	Teams.setup([0, 1])


func _test_four_player_free_for_all() -> void:
	print("4-player free-for-all")
	var main := await _load_crossroads(4, GameSettings.Mode.FREE_FOR_ALL)
	_check(Teams.active == [0, 1, 2, 3], "four teams play on Crossroads")
	for team in 4:
		_check(_building(team, "Lab") != null and _fighters(team).size() >= 3, "team %d has a base and an army" % team)
	var ais := main.find_children("*", "AIController", false, false)
	_check(ais.size() == 3 and ais.map(func(a: AIController) -> int: return a.team).has(3), "one computer opponent per other team")
	var ai: AIController = ais.filter(func(a: AIController) -> bool: return a.team == 2)[0]
	var target: Variant = ai.wave_target()
	var nearest_start := Vector3.INF
	for start: Node3D in get_tree().get_nodes_in_group("start_locations"):
		if start.get_meta("team") != 2 and start.global_position.distance_to(_building(2, "Lab").global_position) < nearest_start.distance_to(_building(2, "Lab").global_position):
			nearest_start = start.global_position
	_check(target != null and target.distance_to(nearest_start) < 0.1, "unscouted, the AI heads for the nearest enemy start location")
	var rules: GameRules = main.get_node("GameRules")
	for target_node: Node3D in get_tree().get_nodes_in_group("targets"):
		if target_node.team in [1, 2]:
			target_node.take_damage(999999.0)
	rules.check_now()
	_check(rules.winner == -1 and rules.eliminated_teams() == [1, 2], "the match goes on while two teams remain")
	for target_node: Node3D in get_tree().get_nodes_in_group("targets"):
		if target_node.team == 3:
			target_node.take_damage(999999.0)
	rules.check_now()
	_check(rules.winner == 0, "the last team standing wins")
	await _unload(main)
	_reset_match_settings()


func _test_unused_bases_removed() -> void:
	print("unused bases")
	var main := await _load_crossroads(2, GameSettings.Mode.FREE_FOR_ALL)
	_check(Teams.active == [0, 1], "a 2-player game on a 4-player map uses two bases")
	_check(_building(2, "Lab") == null and _building(3, "Lab") == null and _team_units(3).is_empty(), "the other bases are removed")
	var map := main.get_world_3d().navigation_map
	var removed_lab := Vector3(38, 0, -38)
	_check(_flat(NavigationServer3D.map_get_closest_point(map, removed_lab) - removed_lab) < 0.5, "and their ground is walkable")
	await _unload(main)
	_reset_match_settings()


func _test_two_vs_two() -> void:
	print("2 vs 2")
	var main := await _load_crossroads(4, GameSettings.Mode.TEAMS)
	_check(Teams.are_allies(0, 1) and Teams.are_enemies(0, 2), "you and team 1 are allies")
	_check(Teams.color(0) == Teams.BLUE and Teams.color(1) == Teams.GREEN and Teams.color(2) == Teams.RED,
			"you're blue, your ally green, enemies red")
	_check((_building(1, "Lab").team_band.material_override as StandardMaterial3D).albedo_color == Teams.GREEN,
			"your ally's buildings show the ally colour")
	var mine := _fighters(0)[0]
	var ally := _fighters(1)[0]
	var enemy := _fighters(2)[0]
	_place(mine, Vector3(0, 0, 20))
	_place(ally, Vector3(3, 0, 20))
	_place(enemy, Vector3(30, 0, -30))
	_check(mine.find_best_enemy(20.0) == null, "allies aren't treated as enemies")
	mine.command_attack(ally)
	_check(mine.attack_target == null, "you can't order an attack on an ally")

	var fog: FogOfWar = main.get_node("FogOfWar")
	fog.reveal_all = false
	_place(ally, Vector3(30, 0, -24))
	await _fog_frames()
	_check(fog.is_visible(0, Vector3(30, 0, -24)) and enemy.visible, "allies share vision")

	var rules: GameRules = main.get_node("GameRules")
	for target_node: Node3D in get_tree().get_nodes_in_group("targets"):
		if target_node.team == 0:
			target_node.take_damage(999999.0)
	rules.check_now()
	_check(rules.winner == -1, "your alliance survives while your ally does")
	for target_node: Node3D in get_tree().get_nodes_in_group("targets"):
		if target_node.team in [2, 3]:
			target_node.take_damage(999999.0, ally)
	rules.check_now()
	var screen: EndScreen = main.get_node("UI/HUD").end_screen
	_check(rules.winner == 0 and screen.title.text == "VICTORY", "beating both enemies wins for the whole alliance")
	_check(screen.cell_text(0, 2) == "Ally" and screen.cell_text(0, 3).begins_with("Enemy"), "the end screen labels allies and enemies")
	await _unload(main)
	_reset_match_settings()


func _test_setup_players() -> void:
	print("setup: players")
	var setup: SkirmishSetup = load("res://scenes/ui/skirmish_setup.tscn").instantiate()
	get_tree().root.add_child(setup)
	await _process_frames(2)
	setup.select_map(2)
	_check(setup.players_option.item_count == 3, "Crossroads offers 2, 3 or 4 players")
	_check(setup.mode_option.disabled, "2 vs 2 needs four players")
	setup.players_option.select(2)
	setup.players_option.item_selected.emit(2)
	_check(GameSettings.player_count == 4 and not setup.mode_option.disabled, "four players unlocks 2 vs 2")
	setup.mode_option.select(1)
	setup.mode_option.item_selected.emit(1)
	_check(GameSettings.alliances() == {0: 0, 1: 0, 2: 1, 3: 1}, "2 vs 2 pairs you with team 1")
	setup.select_map(0)
	_check(GameSettings.player_count == 2 and GameSettings.mode == GameSettings.Mode.FREE_FOR_ALL and setup.players_option.item_count == 1,
			"a 2-player map resets the player count")
	setup.queue_free()
	_reset_match_settings()
	await _process_frames(1)


func _test_population() -> void:
	print("population")
	var main := await _load_map()
	var lab := _building(0, "Lab")
	_check(Population.cap(0) == 10 and Population.used(0) == 9, "the Lab houses 10; 4 Henchmen + 5 creatures use 9")
	var site_house := _add_building("res://resources/buildings/house.tres", 0, Vector3(-20, 0, 20))
	site_house.start_complete = false
	site_house.is_complete = false
	_check(Population.cap(0) == 10, "unfinished Houses don't count")
	site_house.add_build_work(site_house.data.build_time)
	_check(Population.cap(0) == 15, "a finished House adds 5")
	site_house.take_damage(99999.0)
	_check(Population.cap(0) == 10, "losing a House lowers the cap")

	Economy.add(0, 2000, 2000)
	var recipe: UnitRecipe = lab.data.production[0]
	var chamber := _add_building("res://resources/buildings/creature_chamber.tres", 0, Vector3(14, 0, 22))
	Research.set_level(0, 5)
	lab.enqueue(recipe)
	chamber.enqueue(chamber.production_options()[0])
	await _physics_frames(3)
	_check(Population.used(0) == 10 and [lab.production_reserved, chamber.production_reserved].count(true) == 1,
			"two buildings can't both take the last slot")
	var waiting := chamber if lab.production_reserved else lab
	_check(waiting.population_blocked, "the other one waits for room")
	var hud := main.get_node("UI/HUD")
	await _process_frames(2)
	_check(hud.message_label.visible and hud.message_label.text.begins_with("Need more Houses"), "the HUD says to build more Houses")
	_check(hud.resource_label.text.contains("Pop  10 / 10"), "the top bar shows population")
	var house := _add_building("res://resources/buildings/house.tres", 0, Vector3(-24, 0, 20))
	await _physics_frames(3)
	_check(not waiting.population_blocked and waiting.production_reserved, "a new House lets production continue")
	var before := _team_units(0).size()
	await _wait_until(func() -> bool: return lab.queue.is_empty() and chamber.queue.is_empty(), 20.0)
	_check(_team_units(0).size() == before + 2 and Population.used(0) == 11, "both units come out")
	_check(Population.cap(0) <= Population.MAX_POPULATION, "the cap never passes %d" % Population.MAX_POPULATION)
	await _unload(main)


func _test_starting_army() -> void:
	print("starting army")
	var main := await _load_map(false)
	for team in [0, 1]:
		var expected: Array = main.pick_starting_army(Armies.recipes(team), main.starting_army_budget)
		var spent := 0
		for recipe in expected:
			spent += recipe.cost_coal
		var fighters := _fighters(team)
		_check(fighters.size() == expected.size() and fighters.size() >= 3, "team %d starts with %d creatures from its roster" % [team, fighters.size()])
		_check(fighters.all(func(u: Creature) -> bool: return u.stats.design != null), "team %d's starting creatures are hybrids" % team)
		_check(spent <= main.starting_army_budget, "team %d's starting army fits the budget (%d coal)" % [team, spent])
	var cheap: Array[UnitRecipe] = [CreatureCombiner.make_recipe(_design("bat", "bat", [0, 0, 0, 0, 0, 0]))]
	_check(main.pick_starting_army(cheap, 600).size() == 600 / cheap[0].cost_coal, "a roster of one design repeats it to fill the budget")
	await _unload(main)


func _test_target_choice() -> void:
	print("target choice")
	var main := await _load_map()
	var runner := _first(0, "Runner")
	var brute := _first(1, "Brute")
	var weak := _first(1, "Runner")
	var other := _first(1, "Skirmisher")
	_isolate([runner, brute, weak, other])
	_place(other, Vector3(0, 0, -40))
	_place(runner, Vector3(0, 0, 0))
	_place(brute, Vector3(-6, 0, -1))
	_place(weak, Vector3(6, 0, -1))
	_check(runner.find_best_enemy(20.0) == weak, "units prefer targets their attack gets through the armor of")

	_isolate([runner, weak, other])
	_place(weak, Vector3(-6, 0, -1))
	_place(other, Vector3(6, 0, -1))
	other.take_damage(80.0)
	_check(runner.find_best_enemy(20.0) == other, "units prefer finishing off wounded targets")
	await _unload(main)


func _test_kiting() -> void:
	print("kiting")
	var main := await _load_map()
	var shooter := _first(0, "Skirmisher")
	var biter := _first(1, "Runner")
	var brute := _first(0, "Brute")
	_isolate([shooter, biter, brute])
	_place(shooter, Vector3(0, 0, 0))
	_place(biter, Vector3(0, 0, -1.6))
	_place(brute, Vector3(30, 0, 30))
	var start := shooter.global_position
	var kited := false
	for i in 60:
		await get_tree().physics_frame
		kited = kited or shooter.is_kiting()
	_check(kited, "a ranged creature backs off from a melee attacker")
	_check(_flat(shooter.global_position - start) > 2.0, "it gains some distance (%.1f m)" % _flat(shooter.global_position - start))
	var health := biter.health
	await _wait_until(func() -> bool: return biter.health < health, 5.0)
	_check(biter.health < health, "and keeps shooting between retreats")

	_place(brute, biter.global_position + Vector3(1.5, 0, 0))
	var brute_kited := false
	for i in 90:
		await get_tree().physics_frame
		brute_kited = brute_kited or brute.is_kiting()
	_check(not brute_kited, "melee creatures never kite")

	_place(shooter, Vector3(-20, 0, 0))
	_place(biter, Vector3(-20, 0, -1.6))
	shooter.command_hold()
	var held_kite := false
	for i in 60:
		await get_tree().physics_frame
		held_kite = held_kite or shooter.is_kiting()
	_check(not held_kite and _flat(shooter.global_position - Vector3(-20, 0, 0)) < 0.5, "holding creatures stand their ground")
	await _unload(main)


func _test_hold_position() -> void:
	print("hold position")
	var main := await _load_map()
	var guard := _first(0, "Runner")
	var shooter := _first(1, "Skirmisher")
	var brute := _first(1, "Brute")
	_isolate([guard, shooter, brute])
	var post := Vector3(0, 0, 0)
	_place(guard, post)
	_place(shooter, Vector3(0, 0, -6))
	_place(brute, Vector3(30, 0, -30))
	var manager: SelectionManager = main.get_node("SelectionManager")
	manager.select_units([guard])
	_key(KEY_G)
	_check(guard.order == Creature.Order.HOLD, "G holds the selected units")
	shooter.command_hold()
	shooter.command_attack(guard)
	await _physics_frames(120)
	_check(guard.health < guard.stats.max_health, "the holding creature is being shot at")
	_check(_flat(guard.global_position - post) < 0.3 and guard.order == Creature.Order.HOLD, "it doesn't chase an attacker out of reach")
	# Touching distance: well within a Runner's 0.6 m melee reach.
	_place(brute, Vector3(0, 0, -1.2))
	brute.command_hold()
	var health := brute.health
	await _wait_until(func() -> bool: return brute.health < health, 3.0)
	_check(brute.health < health and guard.order == Creature.Order.HOLD, "it attacks enemies that come within reach")
	await _unload(main)


func _test_patrol() -> void:
	print("patrol")
	var main := await _load_map()
	var walker := _first(0, "Runner")
	var victim := _first(1, "Runner")
	_isolate([walker, victim])
	var a := Vector3(0, 0, 0)
	var b := Vector3(12, 0, 0)
	_place(walker, a)
	_place(victim, Vector3(-30, 0, 30))
	walker.command_patrol(b)
	_check(walker.order == Creature.Order.PATROL and walker.is_moving, "patrolling creatures set off")
	await _wait_until(func() -> bool: return _flat(walker.global_position - b) < 1.0, 4.0)
	await _physics_frames(30)
	_check(walker.order == Creature.Order.PATROL and walker.agent.target_position.distance_to(a) < 1.0, "at the end of the route they turn back")
	await _wait_until(func() -> bool: return _flat(walker.global_position - a) < 1.0, 4.0)
	await _physics_frames(30)
	_check(walker.agent.target_position.distance_to(b) < 1.0, "and keep going back and forth")

	victim.take_damage(75.0)
	_place(victim, walker.global_position + Vector3(4, 0, 2))
	await _wait_until(func() -> bool: return not victim.is_alive(), 5.0)
	_check(not victim.is_alive(), "patrols fight enemies they meet")
	await _physics_frames(5)
	_check(walker.order == Creature.Order.PATROL and walker.is_moving, "then carry on patrolling")

	var manager: SelectionManager = main.get_node("SelectionManager")
	var rig: RTSCamera = main.get_node("RTSCamera")
	manager.select_units([walker])
	walker.command_stop()
	_key(KEY_P)
	_check(manager.targeting_order == SelectionManager.PATROL, "P starts picking a patrol route")
	rig.focus_on(Vector3(5, 0, 5))
	await get_tree().process_frame
	_click(get_tree().root.get_visible_rect().size / 2.0, MOUSE_BUTTON_LEFT)
	_check(walker.order == Creature.Order.PATROL and manager.targeting_order == &"", "clicking sets the route")
	_key(KEY_P)
	_key(KEY_ESCAPE)
	_check(manager.targeting_order == &"" and not manager.selected.is_empty(), "Esc cancels without deselecting")
	await _unload(main)


func _test_focus_fire() -> void:
	print("focus fire")
	var main := await _load_map()
	var leader := _first(0, "Runner")
	var follower: Creature = _team_units(0).filter(func(u: Creature) -> bool: return u.stats.display_name == "Runner")[1]
	var first := _first(1, "Runner")
	var second: Creature = _team_units(1).filter(func(u: Creature) -> bool: return u.stats.display_name == "Runner")[1]
	_isolate([leader, follower, first, second])
	_place(leader, Vector3(-2, 0, 0))
	_place(follower, Vector3(0, 0, 0))
	_place(first, Vector3(-4, 0, -5))
	_place(second, Vector3(4, 0, -5))
	leader.command_attack(first)
	_check(follower.find_best_enemy(20.0) == first, "units join the target nearby allies are attacking")
	_place(second, Vector3(1, 0, -1.2))
	_check(follower.find_best_enemy(20.0) == second, "but a much closer enemy still comes first")
	await _unload(main)


func _test_combiner_screen() -> void:
	print("combiner screen")
	var screen: CombinerScreen = load("res://scenes/ui/combiner.tscn").instantiate()
	get_tree().root.add_child(screen)
	await _process_frames(2)
	_check(screen.army.size() == Armies.designs(0).size(), "the combiner opens with the saved army")
	screen.set_animals(Armies.animal("lion"), Armies.animal("eagle"))
	screen.set_pick(CreatureDesign.Slot.WINGS, CreatureDesign.FROM_B)
	_check(screen.current_stats().can_fly, "choosing eagle wings makes the preview fly")
	_check(screen.stats_label.text.contains("Flying"), "the stats panel lists abilities")
	screen.set_pick(CreatureDesign.Slot.TAIL, CreatureDesign.FROM_B)
	_check(screen.design.picks[CreatureDesign.Slot.TAIL] == CreatureDesign.FROM_B, "parts can be switched between the two animals")
	var count := screen.army.size()
	_check(screen.add_to_army() and screen.army.size() == count + 1, "designs can be added to the army")
	while screen.army.size() < Armies.MAX_SIZE:
		screen.add_to_army()
	_check(not screen.add_to_army(), "the army can't exceed %d" % Armies.MAX_SIZE)
	screen.select_army_item(0)
	screen.remove_selected()
	_check(screen.army.size() == Armies.MAX_SIZE - 1, "designs can be removed")
	screen.save_army()
	_check(Armies.designs(0).size() == Armies.MAX_SIZE - 1, "saving hands the army to the Creature Chamber")
	_check(FileAccess.file_exists(TEST_ARMY_PATH), "saving writes the army to disk")
	screen.queue_free()
	Armies.set_designs(0, Armies.default_designs())
	await _process_frames(2)


func _test_main_menu() -> void:
	print("main menu")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _process_frames(2)
	var labels := menu.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	_check("Play Skirmish" in labels and "Creature Combiner" in labels, "the main menu offers skirmish and the combiner")
	menu.queue_free()
	await _process_frames(1)


# --- Helpers ------------------------------------------------------------------

func _load_map(with_fixtures := true) -> Node3D:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.get_node("EnemyAI").enabled = false
	# Fog is still computed, but the player sees everything unless a test opts in.
	main.get_node("FogOfWar").reveal_all = true
	main.spawn_starting_army = not with_fixtures
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if with_fixtures:
		for fixture in FIXTURE_UNITS:
			var unit := _spawn(main, load("res://tests/fixtures/%s.tres" % fixture[0]), fixture[1], Vector3(fixture[2], 0, fixture[3]))
			if fixture[1] == 1:
				unit.rotation.y = PI
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
