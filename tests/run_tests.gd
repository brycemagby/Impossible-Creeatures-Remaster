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
	# Nor their saved options: start every run from the defaults.
	Settings.persist = false
	Settings.reset_to_defaults()
	_run.call_deferred()


func _run() -> void:
	# TEST_ONLY=_test_name runs just that test, for quick iteration.
	var only := OS.get_environment("TEST_ONLY")
	if only != "":
		await call(only)
		print("\n%d checks, %d failed" % [_checks, _failures])
		get_tree().quit(1 if _failures > 0 else 0)
		return
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
	await _test_sonic()
	await _test_pack_frenzy_trample()
	await _test_stink()
	await _test_camouflage()
	await _test_herding()
	await _test_starting_army()
	await _test_research()
	await _test_fog_of_war()
	await _test_minimap()
	await _test_ai_defence_and_waves()
	await _test_difficulty_and_settings()
	await _test_canyon_map()
	await _test_lakeside_water()
	await _test_swimmers()
	await _test_water_chamber()
	await _test_ai_on_water()
	await _test_aviary()
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
	await _test_alerts()
	await _test_selection_shortcuts()
	await _test_m1_touch_ups()
	await _test_m1_extras()
	await _test_m3_touch_ups()
	await _test_idle_buildings()
	await _test_cancel_queued_unit()
	await _test_last_enemies_revealed()
	await _test_unit_portrait()
	await _test_control_tooltips()
	await _test_queued_orders()
	await _test_command_hotkeys()
	await _test_rally_on_coal()
	await _test_target_choice()
	await _test_kiting()
	await _test_hold_position()
	await _test_patrol()
	await _test_stances()
	await _test_sounds()
	await _test_creature_models()
	await _test_building_models()
	await _test_death_animation()
	await _test_terrain_visuals()
	await _test_focus_fire()
	await _test_combiner_screen()
	await _test_main_menu()
	await _test_options_and_accessibility()
	await _test_alert_pings_and_failed_orders()
	_test_online_encoding()
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
	# Henchmen stay out of a box that has fighters in it.
	var visible := player_units.filter(func(u: Creature) -> bool:
		return not u is Henchman and Rect2(Vector2.ZERO, screen).has_point(camera.unproject_position(u.global_position)))
	_drag(Vector2(2, 2), screen - Vector2(2, 2))
	_check(visible.size() >= 5 and manager.selected.size() == visible.size(), "box select grabs all visible player fighters (%d)" % visible.size())
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
	_check(gained > 2.0 and gained < 3.0, "generator produces about 1.25 electricity per second (%.1f in 2s)" % gained)
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
	_check(henchmen.all(func(u: Henchman) -> bool: return u.order == Creature.Order.GATHER or u.order == Creature.Order.IDLE),
			"when the building is done, Henchmen go and mine coal nearby (or wait if there's none)")
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
	ai.think_interval = 1.0
	_check(ai.needs_house() and ai.next_building() == AIController.HOUSE_DATA, "near its population cap the AI builds a House first")
	_add_houses(1, 2)
	await _physics_frames(2)
	_check(_building(1, "Creature Chamber") == null, "the enemy starts without a Creature Chamber")
	_check(ai.next_building().display_name == "Creature Chamber", "a Creature Chamber is the AI's first build")
	_check(ai.building_reserve() == AIController.CHAMBER_DATA.cost_coal, "the AI keeps coal for its next building")
	var lab_one := _building(1, "Lab")
	_add_building("res://resources/buildings/creature_chamber.tres", 1, lab_one.global_position + Vector3(14, 0, 0))
	await _physics_frames(2)
	var chamber_one := _building(1, "Creature Chamber")
	Economy.spend(1, Economy.coal(1) - AIController.GENERATOR_DATA.cost_coal - 50, 0)
	ai.manage_production()
	_check(chamber_one.queue.is_empty(), "so it doesn't spend that coal on creatures")
	chamber_one.free()
	await _physics_frames(2)
	Economy.add(1, 300, 0)
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
	_check(hud.command_panel.visible and buttons.size() == 8, "Henchmen show a build menu with 8 buildings (no Water Chamber without water)")
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
	_check(Armies.all_animals().size() == 17, "17 animals are available")
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

	# Balance: armor is worth health, so a small armored body isn't top tier.
	var scorpion := _stats("scorpion", "scorpion", [0, 0, 0, 0, 0, -1])
	_check(scorpion.level <= 3, "a pure Scorpion is mid-level, not level 5 (level %d)" % scorpion.level)
	_check(_stats("bat", "bat", [0, 0, 0, 0, 0, 0]).level == 1 and _stats("crocodile", "crocodile", [0, 0, 0, 0, 0, -1]).level == 5,
			"Bats are level 1 and Crocodiles level 5")
	var crawler := _stats("elephant", "bat", [0, 0, 1, 1, 0, -1])
	_check(crawler.move_speed >= CreatureCombiner.MIN_SPEED, "tiny legs under a huge body still walk at %.1f" % crawler.move_speed)
	_check(is_equal_approx(Creature.damage_after_armor(10.0, 3.0), 7.0) and is_equal_approx(Creature.damage_after_armor(9.0, 9.0), 9.0 * (1.0 - Creature.MAX_ARMOR_BLOCK)),
			"armor blocks its value, but never more than %d%% of a hit" % roundi(Creature.MAX_ARMOR_BLOCK * 100.0))
	var armored := scorpion.duplicate()
	armored.armor += 2.0
	var big_armored := _stats("elephant", "elephant", [0, 0, 0, 0, 0, -1])
	var big_base := CreatureCombiner.power_rating(big_armored)
	big_armored.armor += 2.0
	_check(CreatureCombiner.power_rating(big_armored) - big_base > CreatureCombiner.power_rating(armored) - CreatureCombiner.power_rating(scorpion),
			"armor adds more power on a big body than a small one")


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
	var walkers := Armies.recipes(1).filter(func(r: UnitRecipe) -> bool: return not r.stats.water_only and not r.stats.can_fly)
	_check(options.size() == walkers.size() and walkers.size() < Armies.designs(1).size(),
			"the Creature Chamber offers the team's army, except flyers and water-only designs")
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
	# Keep the flyer out of the fight: just flying over.
	flyer.command_move(goal + Vector3(0, 0, -6))
	await _physics_frames(30)
	melee.command_attack(flyer)
	_check(not flyer.is_swooping() and melee.attack_target != flyer and melee.find_best_enemy(50.0) != flyer,
			"ground melee creatures can't attack flyers flying over")
	_check(ranged.attack_target == flyer or ranged.attack_target == walker, "ranged creatures can")
	ranged.command_attack(flyer)
	_check(ranged.attack_target == flyer, "ranged creatures accept attack orders on flyers")
	ranged.queue_free()
	ranged.remove_from_group("units")
	walker.queue_free()
	walker.remove_from_group("units")
	flyer.command_attack(melee)
	await _wait_until(func() -> bool: return flyer.is_swooping(), 5.0)
	_check(flyer.is_swooping() and melee.can_attack(flyer), "a flyer swooping into melee can be hit back")
	melee.command_attack(flyer)
	_check(melee.attack_target == flyer, "and melee creatures accept the attack order")
	flyer.command_move(goal + Vector3(0, 0, -15))
	await _physics_frames(30)
	_check(melee.attack_target != flyer, "once it flies off again, melee creatures give up on it")
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


func _test_sonic() -> void:
	print("sonic screech")
	var stats := _stats("bat", "lion", [0, 1, 1, 1, 1, -1])
	_check(stats.has_sonic and stats.sight_range > _stats("lion", "lion", [0, 0, 0, 0, 0, -1]).sight_range, "a bat head gives a sonic screech and sees further")
	var main := await _load_map()
	_isolate([])
	var screecher := _spawn(main, stats, 0, Vector3(0, 0, 0))
	# No automatic screech while the scene is set up; the test screeches by hand.
	screecher.set("_sonic_cooldown", 999.0)
	var near_a := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(2.5, 0, 0))
	var near_b := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(-2.5, 0, 1))
	var far := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(0, 0, 12))
	var flyer := _spawn(main, _stats("lion", "eagle", [0, 0, 1, 0, 0, 1]), 1, Vector3(0, 0, -3))
	var ally := _spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(1, 0, 2))
	for unit: Creature in [near_a, near_b, far, flyer, ally]:
		unit.command_hold()
	await _physics_frames(3)
	var before := [near_a.health, near_b.health, far.health, flyer.health, ally.health]
	_check(screecher.call("_try_sonic") == 3, "the screech hits every enemy close by, flyers included")
	_check(is_equal_approx(before[0] - near_a.health, Creature.SONIC_DAMAGE) and is_equal_approx(before[1] - near_b.health, Creature.SONIC_DAMAGE),
			"for %d damage each, through armor" % Creature.SONIC_DAMAGE)
	_check(far.health == before[2] and ally.health == before[4], "not enemies further away, nor allies")
	_check(is_equal_approx(screecher.get("_sonic_cooldown"), Creature.SONIC_COOLDOWN), "then it has to recover")
	var second := _spawn(main, stats, 0, Vector3(0, 0, 1))
	second.set("_sonic_cooldown", 999.0)
	await _physics_frames(1)
	var after_first := near_a.health
	second.call("_try_sonic")
	_check(near_a.health == after_first, "screeches don't stack: a creature just hit is deafened for a moment")
	await _unload(main)


func _test_pack_frenzy_trample() -> void:
	print("pack, frenzy and trample")
	var wolf := _stats("wolf", "wolf", [0, 0, 0, 0, 0, -1])
	var gorilla := _stats("gorilla", "gorilla", [0, 0, 0, 0, 0, -1])
	var elephant := _stats("elephant", "elephant", [0, 0, 0, 0, 0, -1])
	_check(wolf.pack_hunter and gorilla.has_frenzy and elephant.has_trample, "wolf heads hunt in packs, gorilla torsos frenzy, elephant torsos trample")
	_check(not _stats("elephant", "porcupine", [0, 0, 0, 0, 1, -1]).has_trample, "quill-shooters don't trample")
	var main := await _load_map()
	_isolate([])
	var leader := _spawn(main, wolf, 0, Vector3(0, 0, 0))
	await _physics_frames(2)
	var alone := leader.attack_damage()
	_spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(2, 0, 0))
	await _physics_frames(2)
	_check(leader.packmates() == 0 and leader.attack_damage() == alone, "other creatures aren't packmates")
	for i in 4:
		_spawn(main, wolf, 0, Vector3(-2 - i, 0, 1))
	await _physics_frames(2)
	_check(leader.packmates() == Creature.PACK_MAX_MATES, "packmates nearby count, up to %d" % Creature.PACK_MAX_MATES)
	_check(is_equal_approx(leader.attack_damage(), alone * (1.0 + Creature.PACK_BONUS * Creature.PACK_MAX_MATES)), "each adds %d%% damage" % roundi(Creature.PACK_BONUS * 100.0))
	_isolate([])

	var ape := _spawn(main, gorilla, 0, Vector3(0, 0, 0))
	await _physics_frames(2)
	_check(not ape.is_frenzied() and is_equal_approx(ape.attack_cooldown(), gorilla.attack_cooldown), "a healthy gorilla attacks normally")
	ape.health = gorilla.max_health * 0.4
	_check(ape.is_frenzied() and is_equal_approx(ape.attack_cooldown(), gorilla.attack_cooldown * Creature.FRENZY_COOLDOWN_FACTOR), "badly wounded, it attacks faster")
	_isolate([])

	var trampler := _spawn(main, elephant, 0, Vector3(0, 0, 0))
	var target := _spawn(main, load("res://tests/fixtures/runner.tres"), 1, Vector3(0, 0, 3))
	var beside := _spawn(main, load("res://tests/fixtures/runner.tres"), 1, Vector3(1.2, 0, 3.4))
	var away := _spawn(main, load("res://tests/fixtures/runner.tres"), 1, Vector3(0, 0, 12))
	for unit: Creature in [target, beside, away]:
		unit.command_hold()
	await _physics_frames(2)
	var hp := [target.health, beside.health, away.health]
	trampler.deal_hit(target)
	_check(hp[0] - target.health > 0.0 and is_equal_approx(hp[1] - beside.health, (hp[0] - target.health) * Creature.TRAMPLE_SHARE),
			"trample: enemies next to the target take half (%.1f of %.1f)" % [hp[1] - beside.health, hp[0] - target.health])
	_check(away.health == hp[2], "enemies further off don't")
	await _unload(main)


func _test_stink() -> void:
	print("stink")
	var stinker_stats := _stats("lion", "skunk", [0, 0, 0, 0, 1, -1])
	_check(stinker_stats.has_stink and not stinker_stats.is_ranged(), "a skunk tail gives stink")
	var main := await _load_map()
	_isolate([])
	var brute := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(0, 0, 0))
	var friend := _spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(1.5, 0, 0))
	for unit: Creature in [brute, friend]:
		unit.command_hold()
	await _physics_frames(2)
	var normal := brute.attack_damage()
	var friend_damage := friend.attack_damage()
	var stinker := _spawn(main, stinker_stats, 0, Vector3(0, 0, 3))
	stinker.command_hold()
	await _physics_frames(2)
	_check(brute.is_stunk() and is_equal_approx(brute.attack_damage(), normal * (1.0 - Creature.STINK_PENALTY)),
			"enemies near a stinker deal %d%% less damage" % roundi(Creature.STINK_PENALTY * 100.0))
	_check(not friend.is_stunk() and friend.attack_damage() == friend_damage, "its own side doesn't mind")
	_spawn(main, stinker_stats, 0, Vector3(0, 0, -3)).command_hold()
	await _physics_frames(2)
	_check(is_equal_approx(brute.attack_damage(), normal * (1.0 - Creature.STINK_PENALTY)), "two stinkers don't stack")
	brute.global_position = Vector3(0, 0, 20)
	_check(not brute.is_stunk() and brute.attack_damage() == normal, "out of range, the stink wears off")
	await _unload(main)


func _test_camouflage() -> void:
	print("camouflage")
	var chameleon_stats := _stats("chameleon", "lion", [1, 0, 1, 1, 1, -1])
	_check(chameleon_stats.has_camouflage, "a chameleon torso gives camouflage")
	var main := await _load_map()
	_isolate([])
	var fog: FogOfWar = main.get_node("FogOfWar")
	# An enemy chameleon, as the player (team 0) sees it.
	var chameleon := _spawn(main, chameleon_stats, 1, Vector3(0, 0, 0))
	var watcher := _spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(0, 0, 15))
	watcher.command_hold()
	chameleon.command_hold()
	await _physics_frames(5)
	fog.update_now()
	_check(not chameleon.is_camouflaged() and chameleon.visible, "a creature that just arrived is visible")
	await _wait_until(func() -> bool: return chameleon.is_camouflaged(), Creature.CAMOUFLAGE_DELAY + 2.0)
	fog.update_now()
	_check(chameleon.is_camouflaged() and chameleon.is_hidden_from(0), "after standing still it camouflages")
	_check(not chameleon.visible, "the player can't see it, even with the fog off")
	_check(not watcher.can_attack(chameleon) and watcher.find_best_enemy(50.0) != chameleon, "enemies can't target it")
	_check(not chameleon.is_hidden_from(1), "its own side still sees it")

	var scout := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3(2, 0, 0))
	scout.command_hold()
	fog.update_now()
	_check(not chameleon.is_hidden_from(0) and chameleon.visible, "an enemy right next to it spots it")
	scout.queue_free()
	scout.remove_from_group("units")
	await _physics_frames(2)
	var bat_head := _spawn(main, _stats("bat", "lion", [0, 1, 1, 1, 1, -1]), 0, Vector3(0, 0, Creature.ECHOLOCATION_RADIUS - 1.0))
	bat_head.command_hold()
	_check(not chameleon.is_hidden_from(0), "echolocation (a bat head) finds it from further away")
	bat_head.queue_free()
	bat_head.remove_from_group("units")
	await _physics_frames(2)
	_check(chameleon.is_hidden_from(0), "hidden again once they've gone")
	chameleon.take_damage(1.0)
	await _physics_frames(1)
	_check(not chameleon.is_camouflaged(), "getting hit breaks camouflage")
	chameleon.command_move(Vector3(5, 0, 0))
	await _wait_until(func() -> bool: return not chameleon.is_moving, 5.0)
	await _wait_until(func() -> bool: return chameleon.is_camouflaged(), Creature.CAMOUFLAGE_DELAY + 2.0)
	_check(chameleon.is_camouflaged(), "standing still again brings it back")
	await _unload(main)


func _test_herding() -> void:
	print("herding")
	var bison := _stats("bison", "bison", [0, 0, 0, 0, 0, -1])
	_check(bison.herding and not _stats("lion", "bison", [0, 0, 0, 0, 0, -1]).herding, "a bison torso gives herding")
	var main := await _load_map()
	_isolate([])
	var leader := _spawn(main, bison, 0, Vector3(0, 0, 0))
	_spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(2, 0, 0))
	_spawn(main, bison, 1, Vector3(-3, 0, 0))
	await _physics_frames(2)
	_check(leader.herd_mates() == 0 and leader.armor() == bison.armor, "other creatures and enemies aren't herd mates")
	for i in 4:
		_spawn(main, bison, 0, Vector3(i * 1.5 - 2, 0, 2.5))
	await _physics_frames(2)
	var bonus := Creature.HERD_ARMOR * Creature.HERD_MAX_MATES
	_check(leader.herd_mates() == Creature.HERD_MAX_MATES, "herd mates nearby count, up to %d" % Creature.HERD_MAX_MATES)
	_check(leader.armor() == bison.armor + bonus and leader.ranged_armor() == bison.ranged_armor + bonus, "each adds melee and ranged armor")
	leader.global_position = Vector3(30, 0, 30)
	_check(leader.herd_mates() == 0 and leader.armor() == bison.armor, "a straggler loses the bonus")
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
	_check(hud.research_value.text == "L1", "the HUD shows the research level")
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
	_check(is_equal_approx(Economy.coal(1) - coal, 10.0 * AIController.DIFFICULTY_SETTINGS[2].income) and Economy.coal(1) - coal > 10.0,
			"Hard gives the AI a coal bonus")
	coal = Economy.coal(0)
	Economy.deposit_coal(0, 10)
	_check(is_equal_approx(Economy.coal(0) - coal, 10.0), "the player gets no bonus")
	_check(not main.get_node("FogOfWar").enabled, "the fog setting is applied to the match")
	await _unload(main)

	GameSettings.difficulty = GameSettings.Difficulty.EASY
	main = await _load_map()
	ai = main.get_node("EnemyAI")
	coal = Economy.coal(1)
	Economy.deposit_coal(1, 10)
	_check(Economy.coal(1) - coal < 10.0, "Easy gives the AI less income")
	_check(ai.first_wave_delay >= 300.0 and ai.max_wave_size <= 6, "Easy attacks late and small")
	_check(ai.max_research == 3 and ai.upgrade_tiers == 0 and not ai.retreats, "Easy stops at research level 3, buys no upgrades and doesn't retreat")
	Research.set_level(1, 3)
	_check(not ai.is_saving_for_research(), "at its research cap it stops saving for research")
	var easy_workshop := _add_building("res://resources/buildings/workshop.tres", 1, _building(1, "Lab").global_position + Vector3(-12, 0, -2))
	await _physics_frames(2)
	Economy.add(1, 2000, 2000)
	ai.manage_upgrades()
	_check(easy_workshop.upgrading == null, "Easy never buys upgrades")
	ai.min_wave_size = 1
	for i in 10:
		_spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(i - 5.0, 0, -20))
	await _physics_frames(2)
	_check(ai.launch_wave() <= ai.max_wave_size, "waves never send more than the cap")
	ai.max_fighters = 0
	var chamber := _add_building("res://resources/buildings/creature_chamber.tres", 1, _building(1, "Lab").global_position + Vector3(14, 0, 0))
	await _physics_frames(2)
	ai.manage_production()
	_check(chamber.queue.is_empty(), "with its army full it makes no more creatures")
	await _unload(main)

	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	main = await _load_map()
	ai = main.get_node("EnemyAI")
	_check(ai.upgrade_tiers == 1 and ai.max_research == 4, "Normal buys only first-tier upgrades and stops at level 4")
	await _unload(main)
	GameSettings.difficulty = GameSettings.Difficulty.NORMAL
	GameSettings.fog_enabled = true


func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _test_lakeside_water() -> void:
	print("water")
	GameSettings.select_map(3)
	var main: Node3D = load(GameSettings.map_path()).instantiate()
	main.get_node("EnemyAI").enabled = false
	main.get_node("FogOfWar").reveal_all = true
	main.spawn_starting_army = false
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _physics_frames(10)
	_check(GameSettings.MAPS[3].name == "Lakeside", "Lakeside is in the map list")
	_check(WaterArea.is_deep_water(get_tree(), Vector3(-10, 0, 0)) and not WaterArea.is_deep_water(get_tree(), Vector3(0, 0, 0))
			and not WaterArea.is_deep_water(get_tree(), Vector3(-30, 0, 0)), "the lake is deep water, the ford and shore aren't")
	var map := main.get_world_3d().navigation_map
	var north := Vector3(-10, 0, 25)
	var south := Vector3(-10, 0, -25)
	var walk := NavigationServer3D.map_get_path(map, north, south, true, WaterArea.LAND_LAYER)
	var dry := true
	for i in range(1, walk.size()):
		for t in 10:
			if WaterArea.is_deep_water(get_tree(), walk[i - 1].lerp(walk[i], t / 10.0), 0.3):
				dry = false
	_check(dry and walk[walk.size() - 1].distance_to(south) < 1.0, "walkers go round the lake or through the ford")
	var swim := NavigationServer3D.map_get_path(map, Vector3(-10, 0, 8), Vector3(-10, 0, -8), true, WaterArea.WATER_LAYER)
	_check(_path_length(swim) < 16.5 and swim[swim.size() - 1].distance_to(Vector3(-10, 0.5, -8)) < 1.0, "swimmers have a way across the water")
	var both := NavigationServer3D.map_get_path(map, north, south, true, WaterArea.LAND_LAYER | WaterArea.WATER_LAYER)
	_check(_path_length(both) < _path_length(walk) - 2.0, "amphibians can cut across the lake (%.0f m vs %.0f m)" % [_path_length(both), _path_length(walk)])

	var placer: BuildPlacer = main.get_node("SelectionManager").build_placer
	placer.start(load("res://resources/buildings/house.tres"), 0)
	_check(not placer.can_place_at(Vector3(-10, 0, 0)) and not placer.can_place_at(Vector3(0, 0, 0)), "nothing can be built on water, deep or shallow")
	_check(placer.can_place_at(Vector3(-30, 0, 18)), "but the shore is fine")
	placer.cancel()

	var runner := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, north)
	await _physics_frames(2)
	runner.command_move(south)
	var stayed_dry := true
	var arrived := false
	var wet_at := Vector3.INF
	for i in 900:
		await get_tree().physics_frame
		if stayed_dry and WaterArea.is_deep_water(get_tree(), runner.global_position, 0.5):
			stayed_dry = false
			wet_at = runner.global_position
		if runner.global_position.distance_to(south) < 2.0:
			arrived = true
			break
	_check(arrived and stayed_dry, "a walking creature crosses the map without swimming (arrived %s, in the water at %s, now %s)" % [arrived, wet_at, runner.global_position])
	await _unload(main)
	GameSettings.select_map(0)


func _load_lakeside() -> Node3D:
	GameSettings.select_map(3)
	var main: Node3D = load(GameSettings.map_path()).instantiate()
	main.get_node("EnemyAI").enabled = false
	main.get_node("FogOfWar").reveal_all = true
	main.spawn_starting_army = false
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _physics_frames(10)
	return main


func _test_swimmers() -> void:
	print("swimmers")
	var croc := _stats("crocodile", "crocodile", [0, 0, 0, 0, 0, -1])
	var shark := _stats("shark", "shark", [0, 0, 0, 0, 0, -1])
	_check(croc.can_swim and not croc.water_only, "crocodile legs make an amphibian")
	_check(shark.water_only and shark.can_swim and shark.move_speed == shark.swim_speed, "fins front and back: water only")
	var half := _stats("lion", "shark", [0, 0, 1, 0, 0, -1])
	_check(half.can_swim and not half.water_only and half.move_speed >= CreatureCombiner.MIN_SPEED, "one pair of fins and one of legs: amphibious")
	var winged := _stats("electric_eel", "bat", [0, 0, 0, 0, 0, 1])
	_check(winged.can_fly and not winged.can_swim, "wings win: a light enough finned flyer flies over the water")
	_check(_stats("lion", "electric_eel", [0, 1, 0, 0, 0, -1]).has_electric, "an electric eel torso is electric")
	_check(not _stats("lion", "lion", [0, 0, 0, 0, 0, -1]).can_swim, "lions don't swim")

	var main := await _load_lakeside()
	var north := Vector3(-10, 0, 24)
	var south := Vector3(-10, 0, -24)
	var swimmer := _spawn(main, croc, 0, north)
	await _physics_frames(2)
	swimmer.command_move(south)
	var swam := false
	var swim_speed_ok := true
	for i in 900:
		await get_tree().physics_frame
		if swimmer.is_in_water():
			swam = true
			if not is_equal_approx(swimmer.move_speed(), croc.swim_speed * Upgrades.speed_multiplier(0)):
				swim_speed_ok = false
		if swimmer.global_position.distance_to(south) < 2.0:
			break
	_check(swam and swimmer.global_position.distance_to(south) < 2.0, "an amphibian swims straight across the lake")
	_check(swim_speed_ok, "at its swim speed")

	var fish := _spawn(main, shark, 0, Vector3(-10, 0, 0))
	await _physics_frames(2)
	fish.command_move(Vector3(-30, 0, 0))
	var stayed_in := true
	for i in 240:
		await get_tree().physics_frame
		if not WaterArea.is_deep_water(get_tree(), fish.global_position):
			stayed_in = false
	_check(stayed_in and fish.global_position.x < -14.0, "water-only creatures go to the shore but never onto land")

	fish.global_position = Vector3(-10, 0, 0)
	fish.command_stop()
	var lion := _spawn(main, _stats("lion", "lion", [0, 0, 0, 0, 0, -1]), 1, Vector3(-20, 0, 0))
	lion.command_hold()
	await _physics_frames(2)
	_check(not lion.can_attack(fish), "a land melee creature can't reach a swimmer far from the shore")
	_check(not fish.can_attack(lion) or WaterArea.distance_to_deep_water(get_tree(), lion.global_position) < 4.0, "and a shark can't reach far up the bank")
	lion.global_position = Vector3(-40, 0, 0)
	_check(not fish.can_attack(lion), "water-only creatures can't attack far inland")
	fish.global_position = Vector3(-16, 0, 0)
	lion.global_position = Vector3(-18, 0, 0)
	_check(lion.can_attack(fish) and fish.can_attack(lion), "but they fight at the water's edge")
	var spitter := _spawn(main, _stats("gorilla", "porcupine", [0, 0, 0, 0, 1, -1]), 1, Vector3(-24, 0, 0))
	fish.global_position = Vector3(-10, 0, 0)
	_check(spitter.can_attack(fish), "ranged creatures shoot swimmers anywhere")
	_isolate([])

	var eel := _spawn(main, _stats("lion", "electric_eel", [0, 1, 0, 0, 0, -1]), 0, Vector3(30, 0, 30))
	var victim := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(31, 0, 30))
	victim.command_hold()
	await _physics_frames(2)
	var before := victim.health
	eel.deal_hit(victim)
	_check(victim.is_stunned(), "an electric hit stuns")
	_check(before - victim.health >= Creature.ELECTRIC_DAMAGE, "and shocks for extra damage")
	var stunned_at := victim.global_position
	victim.command_move(Vector3(40, 0, 40))
	await _physics_frames(30)
	_check(victim.global_position.distance_to(stunned_at) < 0.1, "stunned creatures can't move (moved %.2f m)" % victim.global_position.distance_to(stunned_at))
	before = victim.health
	eel.deal_hit(victim)
	_check(before - victim.health < Creature.ELECTRIC_DAMAGE + eel.attack_damage(), "the shock needs time to recharge")
	_isolate([])
	await _unload(main)
	GameSettings.select_map(0)


func _test_water_chamber() -> void:
	print("Water Chamber")
	var saved := Armies.designs(0)
	Armies.set_designs(0, [_design("lion", "lion", [0, 0, 0, 0, 0, -1]), _design("crocodile", "crocodile", [0, 0, 0, 0, 0, -1]),
			_design("shark", "shark", [0, 0, 0, 0, 0, -1])])
	var dry := await _load_map()
	var manager: SelectionManager = dry.get_node("SelectionManager")
	var hud := dry.get_node("UI/HUD")
	manager.select_units([_first(0, "Henchman")])
	await _process_frames(2)
	_check(not _button_names(hud).has("Water Chamber"), "no Water Chamber on maps without water")
	var picks: Array = dry.call("spawn_army", 0, dry.get_node("ArmySpawn0"))
	_check(picks.all(func(u: Creature) -> bool: return not u.stats.water_only), "starting armies leave water-only creatures at home")
	await _unload(dry)

	var main := await _load_lakeside()
	manager = main.get_node("SelectionManager")
	hud = main.get_node("UI/HUD")
	manager.select_units([_first(0, "Henchman")])
	await _process_frames(2)
	_check(_button_names(hud).has("Water Chamber"), "on Lakeside, Henchmen can build a Water Chamber")
	var placer: BuildPlacer = manager.build_placer
	Economy.add(0, 2000, 2000)
	placer.start(load("res://resources/buildings/water_chamber.tres"), 0)
	_check(placer.place(Vector3(-36, 0, 20)) == null and placer.last_error == "Must be built on a shore", "it has to be on a shore")
	var chamber := placer.place(Vector3(-21, 0, 10))
	_check(chamber != null, "a spot by the lake works")
	placer.cancel()
	if chamber == null:
		await _unload(main)
		Armies.set_designs(0, saved)
		return
	chamber.add_build_work(chamber.data.build_time)
	var names := chamber.production_options().map(func(r: UnitRecipe) -> String: return r.stats.display_name)
	_check(names.size() == 2 and not names.has("Lion"), "the Water Chamber makes the swimming designs (%s)" % [names])
	var land := _add_building("res://resources/buildings/creature_chamber.tres", 0, Vector3(20, 0, 26))
	await _physics_frames(2)
	var land_names := land.production_options().map(func(r: UnitRecipe) -> String: return r.stats.display_name)
	_check(land_names.size() == 2 and not land_names.has("Shark"), "the Creature Chamber makes everything that walks (%s)" % [land_names])
	var shark_recipe: UnitRecipe = chamber.production_options().filter(func(r: UnitRecipe) -> bool: return r.stats.water_only)[0]
	chamber.call("_spawn", shark_recipe)
	var newest: Creature = _team_units(0).back()
	_check(newest.stats.water_only and WaterArea.is_deep_water(get_tree(), newest.global_position), "sharks come out into the water")

	# Swimmer upgrades.
	var swimmer := newest
	await _physics_frames(2)
	var swim := swimmer.move_speed()
	var target := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, Vector3(-30, 0, 0))
	target.command_hold()
	swimmer.global_position = Vector3(-15.5, 0, 0)
	await _physics_frames(1)
	Research.set_level(0, 3)
	var streamlining: UpgradeData = chamber.data.upgrades[0]
	var lungs: UpgradeData = chamber.data.upgrades[1]
	_check(chamber.start_upgrade(streamlining) == "", "the Water Chamber sells swimmer upgrades")
	chamber.upgrade_time = streamlining.duration
	await _physics_frames(3)
	_check(is_equal_approx(swimmer.move_speed(), swim * 1.15), "Streamlining: swimmers 15% faster")
	target.global_position = Vector3(-16.63 - (swimmer.stats.attack_range + target.radius() + Creature.SHORE_REACH + 1.0), 0, 0)
	_check(not swimmer.can_attack(target), "a land target just out of a shark's reach")
	Upgrades.grant(0, lungs)
	_check(swimmer.can_attack(target), "Deep Lungs: water-only creatures reach further up the shore")
	var walker := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3(30, 0, 30))
	await _physics_frames(1)
	_check(walker.move_speed() == walker.stats.move_speed * Upgrades.speed_multiplier(0), "walkers don't get swimmer upgrades")
	await _unload(main)
	GameSettings.select_map(0)
	Armies.set_designs(0, saved)


func _test_ai_on_water() -> void:
	print("AI on water")
	var dry := await _load_map()
	_check(not (dry.get_node("EnemyAI") as AIController).wants_water_chamber(), "no Water Chamber wanted on a dry map")
	await _unload(dry)

	var main := await _load_lakeside()
	var ai: AIController = main.get_node("EnemyAI")
	var lab := _building(1, "Lab")
	_add_houses(1, 3)
	_add_building("res://resources/buildings/creature_chamber.tres", 1, lab.global_position + Vector3(14, 0, 0))
	_add_building("res://resources/buildings/generator.tres", 1, lab.global_position + Vector3(-14, 0, 6))
	await _physics_frames(2)
	_check(ai.next_building() != AIController.WATER_CHAMBER_DATA, "no Water Chamber before its swimmers are researched")
	Research.set_level(1, 3)
	_check(ai.next_building() == AIController.WATER_CHAMBER_DATA, "with swimmers it can make, the AI wants a Water Chamber")
	Economy.add(1, 1000, 1000)
	ai.manage_construction()
	var chamber := _building(1, "Water Chamber")
	_check(chamber != null and WaterArea.distance_to_deep_water(get_tree(), chamber.global_position) < 8.0, "it builds one on the shore")
	if chamber:
		chamber.add_build_work(chamber.data.build_time)
		_check(chamber.production_options().any(func(r: UnitRecipe) -> bool: return r.stats.water_only), "which can make its water-only design")
		Economy.add(1, 1000, 1000)
		ai.manage_upgrades()
		_check(chamber.upgrading != null, "and it buys swimmer upgrades there")

	var fighter := _spawn(main, load("res://tests/fixtures/brute.tres"), 1, lab.global_position + Vector3(0, 0, 10))
	var shark := _spawn(main, _stats("shark", "electric_eel", [0, 1, 0, 0, 0, -1]), 1, Vector3(-10, 0, 0))
	await _physics_frames(2)
	ai.min_wave_size = 1
	ai.waves_sent = 0
	var sent := ai.launch_wave()
	_check(fighter.order == Creature.Order.ATTACK_MOVE and shark.order != Creature.Order.ATTACK_MOVE, "water-only creatures stay out of land attacks")
	_check(ai.manage_navy() == 1 and shark.order == Creature.Order.ATTACK_MOVE, "they're sent to the water nearest the enemy instead")
	await _unload(main)
	GameSettings.select_map(0)


func _test_aviary() -> void:
	print("Aviary")
	var saved := Armies.designs(0)
	Armies.set_designs(0, [_design("lion", "lion", [0, 0, 0, 0, 0, -1]), _design("lion", "eagle", [0, 0, 1, 0, 0, 1])])
	var main := await _load_map()
	var aviary := _add_building("res://resources/buildings/aviary.tres", 0, Vector3(-22, 0, 22))
	var chamber := _add_building("res://resources/buildings/creature_chamber.tres", 0, Vector3(14, 0, 22))
	await _physics_frames(2)
	var flyers := aviary.production_options().map(func(r: UnitRecipe) -> String: return r.stats.display_name)
	var walkers := chamber.production_options().map(func(r: UnitRecipe) -> String: return r.stats.display_name)
	_check(flyers == ["Ligle"], "the Aviary makes the flying designs (%s)" % [flyers])
	_check(walkers == ["Lion"], "and the Creature Chamber no longer does (%s)" % [walkers])

	var flyer := _spawn(main, _stats("lion", "eagle", [0, 0, 1, 0, 0, 1]), 0, Vector3(0, 0, 0))
	var walker := _first(0, "Brute")
	await _physics_frames(2)
	var speed := flyer.move_speed()
	var sight := flyer.sight_range()
	var vision := flyer.vision_range()
	var walker_speed := walker.move_speed()
	Economy.add(0, 2000, 2000)
	Research.set_level(0, 2)
	var wings: UpgradeData = aviary.data.upgrades[0]
	var eyes: UpgradeData = aviary.data.upgrades[1]
	_check(aviary.start_upgrade(wings) == "", "the Aviary sells flyer upgrades")
	aviary.upgrade_time = wings.duration
	await _physics_frames(3)
	Upgrades.grant(0, eyes)
	_check(is_equal_approx(flyer.move_speed(), speed * 1.15), "Strong Wings: flyers 15% faster")
	_check(flyer.sight_range() == sight + 4.0 and flyer.vision_range() == vision + 4.0, "Keen Eyes: flyers see 4 m further")
	_check(walker.move_speed() == walker_speed, "walkers don't get flyer upgrades")

	var ai: AIController = main.get_node("EnemyAI")
	Armies.set_designs(1, [_design("lion", "lion", [0, 0, 0, 0, 0, -1]), _design("lion", "eagle", [0, 0, 1, 0, 0, 1])])
	Research.set_level(1, 1)
	_check(not ai.wants_aviary(), "the AI waits for the research its flyers need")
	Research.set_level(1, 5)
	_check(ai.wants_aviary(), "then wants an Aviary")
	Armies.set_designs(1, Armies.default_designs())
	await _unload(main)
	Armies.set_designs(0, saved)


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
	_check(walked > west.distance_to(east) * 2.0, "the river forces a detour through a ford (%.0f m vs %.0f m)" % [walked, west.distance_to(east)])
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
	_check(hud.speed_label.visible and hud.speed_label.text.contains("Speed  2"), "the HUD shows a non-normal speed")
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
	_check(_building(1, "Lab").model.team_color() == Teams.GREEN,
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


func _test_alerts() -> void:
	print("under-attack alerts")
	var main := await _load_map()
	var hud := main.get_node("UI/HUD")
	var rig: Node3D = main.get_node("RTSCamera")
	var raised := []
	var on_raised := func(team: int, text: String, _where: Vector3) -> void: raised.append([team, text])
	Alerts.raised.connect(on_raised)
	_check(not Alerts.has_alert(0), "no alerts at the start")
	var runner := _first(0, "Runner")
	var attacker := _first(1, "Brute")
	runner.take_damage(1.0, attacker)
	_check(raised.size() == 1 and raised[0][0] == 0 and "under attack" in raised[0][1], "a hit by an enemy raises an alert (%s)" % [raised])
	_check(hud.message_label.text.contains("under attack"), "the HUD shows it")
	runner.take_damage(1.0, attacker)
	_first(0, "Skirmisher").take_damage(1.0, attacker)
	_check(raised.size() == 1, "more hits in the same fight stay quiet")
	_first(0, "Brute").take_damage(1.0, _first(0, "Runner"))
	_check(raised.size() == 1, "friendly fire doesn't alert")
	var lab := _building(0, "Lab")
	var far_unit := _first(0, "Skirmisher")
	far_unit.global_position = lab.global_position + Vector3(0, 0, -60)
	far_unit.take_damage(1.0, attacker)
	_check(raised.size() == 2, "a fight somewhere else alerts again")
	rig.focus_on(Vector3(30, 0, -30))
	_key(KEY_SPACE)
	_check(Vector2(rig.position.x, rig.position.z).distance_to(Vector2(far_unit.global_position.x, far_unit.global_position.z)) < 1.0,
			"Space jumps the camera to the latest alert")
	Alerts.raised.disconnect(on_raised)
	await _unload(main)


func _test_selection_shortcuts() -> void:
	print("selection shortcuts")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var rig: Node3D = main.get_node("RTSCamera")
	var henchmen := _team_units(0).filter(func(u: Creature) -> bool: return u is Henchman)
	henchmen[0].command_gather(_nearest_pile(henchmen[0].global_position))
	_key(KEY_PERIOD)
	var first: Creature = manager.selected[0] if manager.selected.size() == 1 else null
	_check(first is Henchman and first != henchmen[0], "Period selects an idle Henchman, not a busy one")
	_check(Vector2(rig.position.x, rig.position.z).distance_to(Vector2(first.global_position.x, first.global_position.z)) < 1.0, "and centres on it")
	_key(KEY_PERIOD)
	var second: Creature = manager.selected[0] if manager.selected.size() == 1 else null
	_check(second is Henchman and second != first and second != henchmen[0], "pressing again cycles to the next one")

	manager.clear_selection()
	_key(KEY_HOME)
	_check(manager.selected_building == _building(0, "Lab"), "Home selects the Lab")

	manager.clear_selection()
	var runners := _team_units(0).filter(func(u: Creature) -> bool: return u.stats.display_name == "Runner")
	rig.focus_on(runners[0].global_position)
	await _process_frames(2)
	var camera: Camera3D = manager.camera
	var at := camera.unproject_position(runners[0].global_position)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = at
	press.pressed = true
	press.double_click = true
	get_tree().root.push_input(press)
	var release := press.duplicate()
	release.pressed = false
	release.double_click = false
	get_tree().root.push_input(release)
	_check(manager.selected.size() == runners.size() and manager.selected.all(func(u: Creature) -> bool: return u.stats.display_name == "Runner"),
			"double click selects every Runner on screen (%d)" % manager.selected.size())
	manager.select_same_type(_first(0, "Brute"), true)
	_check(manager.selected.size() == runners.size() + 1, "Shift adds another type")
	_check(manager.selected.all(func(u: Creature) -> bool: return u.team == 0), "never the enemy's")
	await _unload(main)


func _test_m1_touch_ups() -> void:
	print("M1 touch-ups")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	var rig: RTSCamera = main.get_node("RTSCamera")
	var camera: Camera3D = manager.camera

	# Box select leaves Henchmen out when fighters are in the box.
	manager.select_in_rect(Rect2(Vector2.ZERO, Vector2(1600, 900)))
	_check(not manager.selected.is_empty() and manager.selected.all(func(u: Creature) -> bool: return not u is Henchman),
			"a box over the army and workers selects only the army")
	var henchman := _first(0, "Henchman")
	var at := camera.unproject_position(henchman.global_position)
	manager.select_in_rect(Rect2(at - Vector2(6, 6), Vector2(12, 12)))
	_check(manager.selected.size() >= 1 and manager.selected.all(func(u: Creature) -> bool: return u is Henchman), "a box over only workers still selects them")

	# Inspecting an enemy.
	var enemy := _first(1, "Brute")
	rig.focus_on(enemy.global_position)
	await _process_frames(2)
	manager.click_select(camera.unproject_position(enemy.global_position))
	await _process_frames(2)
	_check(manager.inspected == enemy and manager.selected.is_empty(), "clicking an enemy inspects it without selecting it")
	_check(hud.selection_label.text.begins_with("Enemy Brute") and hud.selection_label.text.contains("Armor"), "the panel shows the enemy's stats")
	_check(not hud.command_panel.visible, "with no orders to give")
	_key(KEY_ESCAPE)
	_check(manager.inspected == null, "Esc stops inspecting")
	var enemy_lab := _building(1, "Lab")
	rig.focus_on(enemy_lab.global_position)
	await _process_frames(2)
	manager.click_select(camera.unproject_position(enemy_lab.global_position + Vector3.UP * 1.0))
	await _process_frames(2)
	_check(manager.inspected == enemy_lab and hud.selection_label.text.begins_with("Enemy Lab"), "enemy buildings can be inspected too")
	manager.clear_selection()

	# Control groups: Shift adds, a double tap centres the camera.
	var runners := _team_units(0).filter(func(u: Creature) -> bool: return u.stats.display_name == "Runner")
	manager.select_units([runners[0]])
	_key(KEY_1, true)
	manager.select_units([runners[1]])
	_key(KEY_1, false, true)
	_check(manager.control_groups()[1].size() == 2, "Shift + number adds the selection to a group")
	await _process_frames(1)
	_check(hud.groups_label.text.contains("1: 2"), "the HUD lists control groups")
	rig.focus_on(Vector3(30, 0, -30))
	manager.clear_selection()
	_key(KEY_1)
	_check(manager.selected.size() == 2 and Vector2(rig.position.x, rig.position.z).distance_to(Vector2(30, -30)) < 1.0, "one press selects the group")
	_key(KEY_1)
	var centre: Vector3 = (runners[0].global_position + runners[1].global_position) / 2.0
	_check(Vector2(rig.position.x, rig.position.z).distance_to(Vector2(centre.x, centre.z)) < 1.0, "a quick second press centres the camera on it")

	# Camera.
	rig.rotation.y = 1.2
	_key(KEY_BACKSPACE)
	_check(rig.rotation.y == 0.0, "Backspace turns the camera back to north")
	rig.focus_on(Vector3(0, 0, 0))
	rig.target_zoom = 30.0
	var cursor := camera.unproject_position(Vector3(10, 0, 0))
	rig.zoom_towards(cursor)
	_check(rig.position.x > 0.5 and absf(rig.position.z) < 1.0 and rig.target_zoom < 30.0, "zooming in moves towards the cursor")

	# Formations make room for big creatures.
	_isolate([])
	var big := _stats("elephant", "elephant", [0, 0, 0, 0, 0, -1])
	var herd: Array[Creature] = []
	for i in 4:
		herd.append(_spawn(main, big, 0, Vector3(i * 4.0 - 6.0, 0, 10)))
	await _physics_frames(2)
	manager.select_units(herd)
	manager.issue_move(Vector3(0, 0, -10))
	var closest := INF
	for a_unit in herd:
		for b_unit in herd:
			if a_unit != b_unit:
				closest = minf(closest, (a_unit.get("_order_point") as Vector3).distance_to(b_unit.get("_order_point")))
	_check(closest >= herd[0].radius() * 2.0, "formation slots are spaced for big creatures (%.1f m apart, %.1f m wide)" % [closest, herd[0].radius() * 2.0])
	_isolate([])

	# A crowd sent to one spot all arrive instead of jostling forever.
	var crowd: Array[Creature] = []
	for i in 12:
		var unit := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3((i % 4) * 2.0 - 3.0, 0, 15.0 + (i / 4) * 2.0))
		crowd.append(unit)
	await _physics_frames(2)
	for unit in crowd:
		unit.command_move(Vector3(0, 0, -5))
	await _wait_until(func() -> bool: return crowd.all(func(u: Creature) -> bool: return not u.is_moving), 15.0)
	_check(crowd.all(func(u: Creature) -> bool: return not u.is_moving and u.order == Creature.Order.IDLE),
			"a crowd sent to one spot all settle (%d still moving)" % crowd.filter(func(u: Creature) -> bool: return u.is_moving).size())
	_check(crowd.all(func(u: Creature) -> bool: return u.global_position.distance_to(Vector3(0, 0, -5)) < 6.0), "and they all got close")
	await _unload(main)


func _right_drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
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


func _test_m1_extras() -> void:
	print("M1 extras")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	var camera: Camera3D = manager.camera

	# Narrowing a mixed selection by type.
	var fighters := _fighters(0)
	manager.select_units(fighters)
	await _process_frames(2)
	var type_buttons: Array = hud.type_bar.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(hud.type_bar.visible and type_buttons.size() == 3, "a mixed selection shows a button per type (%d)" % type_buttons.size())
	var runner_button: Button = type_buttons.filter(func(b: Button) -> bool: return b.text.ends_with("Runner"))[0]
	runner_button.pressed.emit()
	_check(manager.selected.size() == 2 and manager.selected.all(func(u: Creature) -> bool: return u.stats.display_name == "Runner"),
			"clicking a type keeps only that type")
	await _process_frames(2)
	_check(not hud.type_bar.visible, "one type left: no buttons")
	manager.select_units(fighters)
	manager.select_type("Brute", true)
	_check(manager.selected.size() == fighters.size() - 1 and manager.selected.all(func(u: Creature) -> bool: return u.stats.display_name != "Brute"),
			"Shift+click drops a type instead")

	# Right-drag: a line formation.
	_isolate([])
	var line: Array[Creature] = []
	for i in 4:
		line.append(_spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3(i * 1.5 - 2.0, 0, 20)))
	await _physics_frames(2)
	manager.select_units(line)
	var start := Vector3(-8, 0, 5)
	var end := Vector3(8, 0, 5)
	_right_drag(camera.unproject_position(start), camera.unproject_position(end))
	var points := line.map(func(u: Creature) -> Vector3: return u.get("_order_point"))
	var xs := points.map(func(p: Vector3) -> float: return p.x)
	_check(points.all(func(p: Vector3) -> bool: return absf(p.z - 5.0) < 0.6), "a right-drag lines the group up along the drag")
	_check(xs.max() - xs.min() > 12.0, "as wide as the drag (%.1f m)" % (xs.max() - xs.min()))
	_check(line.all(func(u: Creature) -> bool: return u.order == Creature.Order.MOVE), "and moves them there")
	_click(camera.unproject_position(Vector3(0, 0, 0)), MOUSE_BUTTON_RIGHT)
	var tight := line.map(func(u: Creature) -> Vector3: return u.get("_order_point")).map(func(p: Vector3) -> float: return p.x)
	_check(tight.max() - tight.min() < 6.0, "a plain right click still makes a compact formation")

	# Idle allies make way (Godot's avoidance does it: they yield to movers).
	_isolate([])
	var block: Array[Creature] = []
	for i in 9:
		block.append(_spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3((i % 3) - 1.0, 0, (i / 3) - 1.0)))
	var crosser := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3(0, 0, 10))
	await _physics_frames(2)
	for unit in block:
		unit.command_stop()
	crosser.command_move(Vector3(0, 0, -10))
	await _wait_until(func() -> bool: return crosser.global_position.distance_to(Vector3(0, 0, -10)) < 1.5, 10.0)
	_check(crosser.global_position.distance_to(Vector3(0, 0, -10)) < 1.5, "a walker gets through a tight block of idle allies")

	_isolate([])
	var bystander := _spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(0, 0, 0))
	var holder := _spawn(main, load("res://tests/fixtures/brute.tres"), 0, Vector3(20, 0, 0))
	var walker := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3(0, 0, 8))
	var walker2 := _spawn(main, load("res://tests/fixtures/runner.tres"), 0, Vector3(20, 0, 8))
	bystander.command_stop()
	holder.command_hold()
	await _physics_frames(2)
	var stood := bystander.global_position
	var held := holder.global_position
	walker.command_move(Vector3(0, 0, -8))
	walker2.command_move(Vector3(20, 0, -8))
	await _wait_until(func() -> bool: return not walker.is_moving, 8.0)
	_check(bystander.global_position.distance_to(stood) > 0.8, "an idle ally is nudged out of the way (%.1f m)" % bystander.global_position.distance_to(stood))
	_check(walker.global_position.distance_to(Vector3(0, 0, -8)) < 1.5, "and the walker gets through")
	await _wait_until(func() -> bool: return not walker2.is_moving, 8.0)
	_check(holder.order == Creature.Order.HOLD and holder.get("_guard_position").distance_to(held) < 0.1, "creatures holding position keep their post")
	await _unload(main)


func _test_idle_buildings() -> void:
	print("idle buildings")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud = main.get_node("UI/HUD")
	var lab := _building(0, "Lab")
	var generator := _building(0, "Electrical Generator")
	_check(lab.is_idle() and lab in manager.idle_buildings(), "a Lab making nothing counts as idle")
	_check(not generator.is_idle(), "a Generator (makes no units) never counts as idle")
	await _process_frames(2)
	_check(hud.idle_button.visible and hud.idle_button.text.begins_with("1 idle building"), "the HUD shows how many buildings are idle")
	manager.select_units([_first(0, "Henchman")])
	_key(KEY_COMMA)
	await _process_frames(1)
	_check(manager.selected_building == lab, "Comma selects the next idle building")
	Economy.add(0, 500)
	lab.enqueue(lab.data.production[0])
	await _process_frames(2)
	_check(not lab.is_idle() and manager.idle_buildings().is_empty() and not hud.idle_button.visible, "a building making something isn't idle")
	await _unload(main)


func _test_cancel_queued_unit() -> void:
	print("cancel any queued unit")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud = main.get_node("UI/HUD")
	var lab := _building(0, "Lab")
	var recipe: UnitRecipe = lab.data.production[0]
	Economy.add(0, 1000)
	for i in 3:
		lab.enqueue(recipe)
	await _physics_frames(30)
	var progress: float = lab.production_time
	var coal: float = Economy.coal(0)
	lab.cancel_at(1)
	_check(lab.queue.size() == 2 and Economy.coal(0) == coal + recipe.cost_coal, "cancelling a unit in the middle of the queue refunds it")
	_check(progress > 0.0 and is_equal_approx(lab.production_time, progress), "the unit in progress keeps its progress")
	manager.select_building(lab)
	await _process_frames(2)
	var buttons: Array = hud.queue_bar.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(hud.queue_bar.visible and buttons.size() == 2, "the selected building's queue shows one button per unit")
	buttons[0].pressed.emit()
	_check(lab.queue.size() == 1 and lab.production_time == 0.0, "clicking the unit in progress cancels it and the next starts fresh")
	await _process_frames(2)
	buttons = hud.queue_bar.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(buttons.size() == 1, "the queue buttons update")
	await _unload(main)


func _test_last_enemies_revealed() -> void:
	print("last enemies revealed")
	var main := await _load_map()
	var fog: FogOfWar = main.get_node("FogOfWar")
	fog.reveal_all = false
	var exposed := []
	fog.team_exposed.connect(func(team: int) -> void: exposed.append(team))
	var hider := _first(1, "Henchman")
	_isolate([hider, _first(0, "Henchman")])
	hider.global_position = Vector3(40, 0, -40)
	hider.command_stop()
	await _fog_frames()
	_check(not fog.is_exposed(1) and not hider.visible, "a team with buildings left stays hidden in the fog")
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == 1:
			building.remove_from_group("buildings")
			building.remove_from_group("targets")
			building.queue_free()
	await _fog_frames()
	_check(fog.is_exposed(1) and exposed == [1], "with no buildings and few creatures left, a team is exposed")
	_check(fog.is_visible(0, hider.global_position) and hider.visible, "its last creatures can be seen anywhere")
	_check(not fog.is_exposed(0), "the player, who still has buildings, isn't exposed")
	await _unload(main)


func _test_control_tooltips() -> void:
	print("control tooltips")
	var main := await _load_map()
	var hud := main.get_node("UI/HUD")
	_check(hud.get_node_or_null("ControlsLabel") == null, "there is no on-screen controls list")
	_check("Right click" in hud.selection_label.tooltip_text, "the selection readout explains orders on hover")
	var minimap: Minimap = main.get_node("UI/HUD/Minimap")
	_check("Wheel: zoom" in minimap.tooltip_text, "the minimap explains the camera on hover")
	var manager: SelectionManager = main.get_node("SelectionManager")
	manager.select_building(_building(0, "Lab"))
	await _process_frames(2)
	_check("rally point" in hud.command_panel.tooltip_text, "a building's command panel explains rally points")
	var make := hud.command_grid.get_child(0) as Button
	_check("make 5" in make.tooltip_text, "production buttons explain Shift to make 5")
	await _unload(main)


func _test_unit_portrait() -> void:
	print("unit portrait")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var portrait: UnitPortrait = main.get_node("UI/HUD").portrait
	await _process_frames(2)
	_check(portrait.subject == null, "the portrait is empty with nothing selected")
	var brute := _first(0, "Brute")
	manager.select_units([brute])
	await _process_frames(2)
	_check(portrait.subject == brute, "selecting a creature shows it in the portrait")
	var lab := _building(0, "Lab")
	manager.select_building(lab)
	await _process_frames(2)
	_check(portrait.subject == lab, "selecting a building shows the building")
	manager.select_units([])
	await _process_frames(2)
	_check(portrait.subject == null, "deselecting empties it again")
	await _unload(main)


func _test_m3_touch_ups() -> void:
	print("M3 touch-ups")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")

	# Builders go back to the coal they were mining.
	var worker: Henchman = _first(0, "Henchman")
	var pile := _nearest_pile(worker.global_position)
	worker.command_gather(pile)
	var house := _add_building("res://resources/buildings/house.tres", 0, Vector3(8, 0, 28), false)
	await _physics_frames(2)
	worker.command_build(house)
	await _wait_until(func() -> bool: return house.is_complete, 30.0)
	await _physics_frames(2)
	_check(house.is_complete and worker.order == Creature.Order.GATHER and worker.gather_target == pile, "after building, a Henchman goes back to the pile it was mining")

	# Repairs.
	var lab := _building(0, "Lab")
	lab.take_damage(600.0)
	var damaged := lab.health
	_check(lab.needs_repair(), "a damaged building needs repair")
	manager.select_units([worker])
	manager.issue_build(lab)
	_check(worker.order == Creature.Order.BUILD and worker.build_target == lab, "Henchmen can be sent to repair it")
	var coal: float = Economy.coal(0)
	await _wait_until(func() -> bool: return lab.health > damaged + 100.0, 15.0)
	_check(lab.health > damaged + 100.0, "repairs restore health")
	_check(Economy.coal(0) < coal, "and cost coal")
	Economy.spend(0, Economy.coal(0), 0)
	var stuck_at := lab.health
	await _physics_frames(60)
	_check(lab.health - stuck_at < 5.0 and worker.order != Creature.Order.BUILD, "with no coal, repairs stop and the Henchman goes back to work")
	Economy.add(0, 5000, 0)
	manager.select_building(lab)
	await _process_frames(2)
	_check(hud.selection_label.text.contains("repair"), "the panel points out a damaged building can be repaired")
	lab.health = lab.data.max_health
	_check(not lab.needs_repair() and not lab.needs_work(), "full health: nothing to repair")

	# Demolishing.
	var site := _add_building("res://resources/buildings/generator.tres", 0, Vector3(-22, 0, 22), false)
	await _physics_frames(2)
	coal = Economy.coal(0)
	manager.select_building(site)
	_key(KEY_DELETE)
	_check(not Creature.is_valid_target(site) and Economy.coal(0) == coal + int(site.data.cost_coal * Building.SITE_REFUND),
			"Delete cancels a construction site and refunds most of it")
	var lost := MatchStats.get_stat(0, "buildings_lost")
	var done := _add_building("res://resources/buildings/house.tres", 0, Vector3(-22, 0, 30))
	await _physics_frames(2)
	manager.select_building(done)
	_key(KEY_DELETE)
	_check(Creature.is_valid_target(done), "a finished building asks for a second press")
	_key(KEY_DELETE)
	_check(not Creature.is_valid_target(done) and MatchStats.get_stat(0, "buildings_lost") == lost, "then it's demolished (and not counted as lost)")
	var enemy_lab := _building(1, "Lab")
	manager.inspect(enemy_lab)
	_key(KEY_DELETE)
	_key(KEY_DELETE)
	_check(Creature.is_valid_target(enemy_lab), "you can't demolish someone else's building")
	manager.clear_selection()
	enemy_lab.take_damage(enemy_lab.data.max_health * 0.6)
	(main.get_node("EnemyAI") as AIController).manage_workers()
	_check(_team_units(1).any(func(u: Creature) -> bool: return u is Henchman and u.build_target == enemy_lab), "the AI sends a Henchman to repair a badly damaged building")

	# More coal on the maps.
	var total := 0
	for coal_pile: CoalPile in get_tree().get_nodes_in_group("coal_piles"):
		total += coal_pile.amount
	_check(total >= 20000, "Island Clearing holds plenty of coal (%d)" % total)
	await _unload(main)


func _test_queued_orders() -> void:
	print("queued orders")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var runner := _first(0, "Runner")
	_isolate([runner, _first(1, "Brute")])
	_place(_first(1, "Brute"), Vector3(40, 0, 40))
	_place(runner, Vector3(-10, 0, 10))
	manager.select_units([runner])
	manager.issue_move(Vector3(-10, 0, 0))
	manager.issue_move(Vector3(0, 0, 0), true)
	manager.issue_move(Vector3(0, 0, 10), true)
	_check(runner.queued_orders() == 2, "Shift queues orders behind the current one")
	await _wait_until(func() -> bool: return runner.queued_orders() == 1, 10.0)
	_check(runner.global_position.distance_to(Vector3(-10, 0, 0)) < 2.0, "the first waypoint is reached before the next starts")
	await _wait_until(func() -> bool: return runner.queued_orders() == 0 and runner.is_idle(), 15.0)
	_check(runner.global_position.distance_to(Vector3(0, 0, 10)) < 2.0, "then it works through the queue")

	manager.issue_move(Vector3(10, 0, 10))
	manager.issue_move(Vector3(20, 0, 10), true)
	manager.issue_move(Vector3(-10, 0, 10))
	_check(runner.queued_orders() == 0, "a plain order replaces the queue")
	manager.issue_move(Vector3(-10, 0, 20), true)
	manager.issue_stop()
	_check(runner.queued_orders() == 0 and runner.is_idle(), "Stop clears the queue")

	var enemy := _first(1, "Brute")
	manager.issue_move(Vector3(-10, 0, 0))
	manager.issue_attack(enemy, true)
	manager.issue_move(Vector3(-20, 0, 0), true)
	enemy.queue_free()
	enemy.remove_from_group("units")
	await _wait_until(func() -> bool: return runner.queued_orders() == 0 and runner.is_idle(), 15.0)
	_check(runner.global_position.distance_to(Vector3(-20, 0, 0)) < 2.0, "a queued attack on a dead target is skipped")
	await _unload(main)


func _test_command_hotkeys() -> void:
	print("command hotkeys")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	var lab := _building(0, "Lab")
	_add_houses(0, 4)
	Economy.add(0, 2000, 2000)
	manager.select_building(lab)
	await _process_frames(2)
	var buttons: Array = hud.command_grid.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(buttons[0].text.ends_with("[Z]") and buttons[1].text.ends_with("[X]"), "buttons show their hotkeys")
	_key(KEY_Z)
	_check(lab.queue.size() == 1, "Z presses the first button")
	_key(KEY_Z, false, true)
	_check(lab.queue.size() == Building.MAX_QUEUE, "Shift + Z queues up to 5 more (%d)" % lab.queue.size())
	_key(KEY_X)
	_check(lab.queue.size() == Building.MAX_QUEUE - 1, "X is the second button (Cancel)")

	manager.select_units([_first(0, "Henchman")])
	await _process_frames(2)
	_key(KEY_X)
	_check(manager.build_placer.is_active() and manager.build_placer.data.display_name == "House", "Henchmen: X places a House")
	manager.cancel_placement()
	await _unload(main)


func _test_rally_on_coal() -> void:
	print("rally on coal")
	var main := await _load_map()
	var lab := _building(0, "Lab")
	var pile := _nearest_pile(lab.global_position)
	lab.set_rally_point(pile.global_position, pile)
	lab.call("_spawn", lab.data.production[0])
	var newest: Creature = _team_units(0).back()
	_check(newest is Henchman and newest.order == Creature.Order.GATHER and newest.gather_target == pile, "new Henchmen gather at a coal rally point")
	lab.set_rally_point(Vector3(0, 0, 10))
	_check(lab.rally_pile == null, "a ground rally point drops the pile")
	await _unload(main)


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
	_check(hud.population_value.text == "10 / 10", "the top bar shows population")
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


func _test_stances() -> void:
	print("stances")
	var main := await _load_map()
	var guard := _first(0, "Runner")
	var shooter := _first(1, "Skirmisher")
	_isolate([guard, shooter])
	var manager: SelectionManager = main.get_node("SelectionManager")
	var hud := main.get_node("UI/HUD")
	manager.select_units([guard])
	await _process_frames(2)
	_check(hud.command_title.text == "Stance" and hud.command_grid.get_child_count() == 3, "an army selection shows the stance buttons")
	_check(guard.stance == Creature.Stance.DEFENSIVE, "creatures start defensive")
	var post := Vector3(0, 0, 0)
	# Stand ground: shot at from out of reach, it stays put.
	_place(guard, post)
	_place(shooter, Vector3(0, 0, -6))
	_key(KEY_C)
	_check(guard.stance == Creature.Stance.STAND_GROUND, "the third stance button (C) sets stand ground")
	shooter.command_hold()
	shooter.command_attack(guard)
	await _physics_frames(120)
	_check(guard.health < guard.stats.max_health and _flat(guard.global_position - post) < 0.3,
			"a creature standing its ground doesn't chase an attacker out of reach")
	# Defensive: chases, but walks back to its post past the leash.
	guard.health = guard.stats.max_health
	manager.set_stance(Creature.Stance.DEFENSIVE)
	_place(guard, post)
	guard.command_stop()
	shooter.command_move(Vector3(0, 0, -6))
	await _physics_frames(10)
	shooter.command_attack(guard)
	await _wait_until(func() -> bool: return guard.attack_target == shooter, 3.0)
	_check(guard.attack_target == shooter, "a defensive creature fights back")
	shooter.command_move(Vector3(0, 0, -40))
	await _wait_until(func() -> bool: return guard.attack_target == null, 8.0)
	await _wait_until(func() -> bool: return _flat(guard.global_position - post) < 1.5, 8.0)
	_check(_flat(guard.global_position - post) < 1.5, "it gives up past its leash and walks back")
	# Aggressive: keeps chasing past the leash.
	manager.set_stance(Creature.Stance.AGGRESSIVE)
	_place(guard, post)
	guard.command_stop()
	_place(shooter, Vector3(0, 0, -6))
	shooter.command_attack(guard)
	await _wait_until(func() -> bool: return guard.attack_target == shooter, 3.0)
	shooter.command_move(Vector3(0, 0, -30))
	await _physics_frames(150)
	_check(guard.attack_target == shooter and _flat(guard.global_position - post) > guard.stats.leash_range,
			"an aggressive creature chases past its leash")
	await _unload(main)


func _test_sounds() -> void:
	print("sounds")
	for sound: String in Sfx.SOUNDS:
		for file: String in Sfx.SOUNDS[sound]:
			_check(ResourceLoader.exists(Sfx.DIR + file + ".wav"), "sound file %s exists" % file)
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var brute := _first(0, "Brute")
	Sfx.last_played = ""
	manager.select_units([brute])
	_check(Sfx.last_played == "select", "selecting a creature makes it talk")
	await _physics_frames(20)
	manager.issue_move(brute.global_position + Vector3(4, 0, 0))
	_check(Sfx.last_played == "move", "a move order gets a reply")
	_check(Sfx.voice_pitch(_first(0, "Henchman")) > Sfx.voice_pitch(brute) or brute.stats.size <= 1.0,
			"bigger creatures have deeper voices")
	var hud := main.get_node("UI/HUD")
	hud.show_error("nope")
	_check(Sfx.last_played == "error", "errors go bwomp")
	hud.pause_menu.volume_slider.value = 0.5
	_check(is_equal_approx(Sfx.volume, 0.5), "the pause menu's slider sets the volume")
	Sfx.volume = 1.0
	await _unload(main)


func _test_creature_models() -> void:
	print("creature models")
	var main := await _load_map()
	var stats := CreatureCombiner.build_stats(Armies.default_designs()[0])
	var walker := _spawn(main, stats, 0, Vector3(0, 0, 0))
	await _physics_frames(2)
	var model := walker.find_children("*", "CreatureModel", false, false)[0] as CreatureModel
	var body := model.get_node_or_null("Rig/Body")
	_check(body != null and body.has_node("Neck") and body.has_node("HipFL") and body.has_node("HipBR") and body.has_node("TailBase"),
			"hybrid models have a rig: neck, four hips and a tail")
	var leg := body.get_node("HipFL").get_child(0) as Node3D
	var henchman := _first(0, "Henchman")
	_isolate([walker, henchman])
	walker.command_move(walker.global_position + Vector3(8, 0, 0))
	var swung := false
	for i in 40:
		await _physics_frames(1)
		swung = swung or absf(leg.rotation.x) > 0.1
	_check(swung, "legs swing while walking")
	var worker := henchman.find_children("*", "CreatureModel", false, false)
	_check(worker.size() == 1 and worker[0].has_node("Rig/Body/Neck") and not henchman.body.visible,
			"Henchmen get a worker model instead of the capsule")
	var copy := walker.portrait_visual()
	add_child(copy)
	await _process_frames(2)
	_check(copy.get_node_or_null("Rig/Body") != null, "the portrait copy keeps the rig")
	copy.queue_free()
	await _unload(main)


func _test_building_models() -> void:
	print("building models")
	var signatures := {}
	var all_inside := true
	for file in DirAccess.get_files_at("res://resources/buildings"):
		if not file.ends_with(".tres"):
			continue
		var data: BuildingData = load("res://resources/buildings/" + file)
		var model := BuildingModel.new()
		add_child(model)
		model.build(data, Teams.RED)
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		signatures[model.id] = meshes.size()
		for mesh: MeshInstance3D in meshes:
			var at := model.to_local(mesh.global_position)
			if absf(at.x) > data.size.x / 2.0 + 0.3 or absf(at.z) > data.size.z / 2.0 + 0.3 or at.y < -0.1 or at.y > data.size.y + 1.0:
				all_inside = false
				print("  outside: ", model.id, " ", mesh.name, " ", at)
		model.queue_free()
	_check(signatures.size() == 9 and not signatures.has("") and signatures.values().all(func(n: int) -> bool: return n > 10),
			"every building has its own detailed model")
	_check(all_inside, "models stay inside the building's footprint")

	var main := await _load_map()
	var lab := _building(0, "Lab")
	var team_parts := lab.model.find_children("Team*", "MeshInstance3D", true, false)
	_check(not team_parts.is_empty() and team_parts.all(func(m: MeshInstance3D) -> bool:
			return (m.material_override as StandardMaterial3D).albedo_color == Teams.color(0)), "buildings carry their team colour")
	var site: Building = preload("res://scenes/buildings/building.tscn").instantiate()
	site.data = lab.data
	site.team = 0
	site.start_complete = false
	site.position = lab.global_position + Vector3(20, 0, 0)
	main.add_child(site)
	var scaffold := site.model.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return m.has_meta("scaffold"))
	var lamps := site.model.find_children("*", "MeshInstance3D", true, false).filter(func(m: Node) -> bool: return m.has_meta("lit"))
	_check(site.model.scale.y < 0.5 and scaffold.all(func(m: Node3D) -> bool: return m.visible)
			and lamps.all(func(m: Node3D) -> bool: return not m.visible), "construction sites are low, in scaffolding, with lamps off")
	site.add_build_work(site.data.build_time)
	_check(site.is_complete and is_equal_approx(site.model.scale.y, 1.0) and scaffold.all(func(m: Node3D) -> bool: return not m.visible)
			and lamps.all(func(m: Node3D) -> bool: return m.visible), "finished buildings lose the scaffolding and light up")
	var copy := lab.portrait_visual()
	add_child(copy)
	await _process_frames(2)
	_check(copy.find_children("*", "MeshInstance3D", true, false).size() > 10, "the portrait shows the building's model")
	copy.queue_free()
	await _unload(main)


func _test_death_animation() -> void:
	print("death animation")
	var main := await _load_map()
	var stats := CreatureCombiner.build_stats(Armies.default_designs()[0])
	var victim := _spawn(main, stats, 1, Vector3(0, 0, 10))
	await _physics_frames(2)
	var rig := (victim.find_children("*", "CreatureModel", false, false)[0] as Node).get_node("Rig") as Node3D
	victim.take_damage(100000.0)
	_check(not victim.is_alive() and is_instance_valid(victim), "a dead creature stays to play its death")
	var fallen := func() -> bool:
		return absf(rig.rotation.z) > 1.4 and not victim.find_children("Dust*", "MeshInstance3D", false, false).is_empty()
	await _wait_until(fallen, 1.5)
	_check(absf(rig.rotation.z) > 1.4, "it keels over onto its side")
	_check(not victim.find_children("Dust*", "MeshInstance3D", false, false).is_empty(), "with a puff of dust")
	await _wait_until(func() -> bool: return not is_instance_valid(victim),
			Creature.DEATH_LIE_TIME + Creature.DEATH_FADE_TIME + 1.5)
	_check(not is_instance_valid(victim), "then fades away and is removed")
	await _unload(main)


func _test_terrain_visuals() -> void:
	print("terrain visuals")
	var main := await _load_lakeside()
	var decor := main.get_node_or_null("TerrainDecor")
	_check(decor != null and decor.get_node("Grass").multimesh.instance_count > 1000, "maps are scattered with grass")
	var clear := true
	for point: Vector3 in decor.placed["grass"]:
		for water: WaterArea in get_tree().get_nodes_in_group("water_areas"):
			if water.contains(point):
				clear = false
		for prop: Node3D in get_tree().get_nodes_in_group("fog_hidden"):
			if _flat(prop.global_position - point) < 2.0:
				clear = false
	_check(clear, "but none in the water, on rocks or on coal")
	_check(decor.get_node("Grass").is_in_group("fog_surfaces")
			and (decor.get_node("Grass").material_override as ShaderMaterial).get_shader_parameter("fog") != null,
			"and it darkens with the fog like the ground")
	var rock: Node3D = main.get_node("NavigationRegion3D/Rocks").get_child(0)
	_check(rock.find_children("*", "MeshInstance3D", true, false).size() >= 3, "rocks are outcrops of several boulders")
	var pile: CoalPile = get_tree().get_nodes_in_group("coal_piles")[0]
	_check(pile.mesh.get_child_count() == CoalPile.LUMPS, "coal piles are heaps of lumps")
	pile.take(pile.amount / 2)
	_check(pile.mesh.scale.x < 1.0, "which shrink as they are mined")
	var water: WaterArea = get_tree().get_nodes_in_group("water_areas")[0]
	_check((water._surface.material_override as ShaderMaterial).shader.resource_path.ends_with("water.gdshader"), "water has its own rippling surface")
	await _unload(main)
	_reset_match_settings()


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
	if screen.army.size() >= Armies.MAX_SIZE:
		screen.select_army_item(screen.army.size() - 1)
		screen.remove_selected()
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
	_check("Play Online" in labels, "the main menu offers online play")
	menu.queue_free()
	await _process_frames(1)


## The pieces of online play that don't need a second copy of the game
## (tests/run_net_test.sh plays a real match between two).
func _test_online_encoding() -> void:
	print("online encoding")
	_check(not Net.is_online() and Net.sync == null, "the game starts offline")
	var unit := Creature.new()
	_check(not Net.forward(unit, &"command_stop"), "offline, commands run locally instead of being sent")
	unit.free()

	if OS.get_environment("IC_RELAY_URL") == "":
		_check(Net.relay_url() == ProjectSettings.get_setting(Net.RELAY_URL_SETTING), "the relay address comes from the project settings")
	var relay := RelayPeer.new()
	var joined: Array[int] = []
	relay.peer_connected.connect(func(peer: int) -> void: joined.append(peer))
	relay._control('{"type":"welcome","id":4242,"code":"ABCD","peers":[1]}')
	_check(relay.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and relay.get_unique_id() == 4242
			and joined == [1] and relay.room_code == "ABCD", "joining through the relay connects to the host with our own id")
	var host_relay := RelayPeer.new()
	host_relay._hosting = true
	var codes: Array[String] = []
	host_relay.room_opened.connect(func(code: String) -> void: codes.append(code))
	host_relay._control('{"type":"welcome","id":1,"code":"WXYZ","peers":[]}')
	host_relay._control('{"type":"peer_joined","id":77}')
	_check(host_relay._is_server() and host_relay.get_unique_id() == 1 and codes == ["WXYZ"],
			"hosting through the relay hands out a room code")
	var left: Array[int] = []
	host_relay.peer_disconnected.connect(func(peer: int) -> void: left.append(peer))
	host_relay._control('{"type":"peer_left","id":77}')
	_check(left == [77], "the host hears when a player leaves the room")

	var designs := Armies.default_designs()
	var decoded := Armies.decode_designs(Armies.encode_designs(designs))
	var same := decoded.size() == designs.size()
	for i in mini(decoded.size(), designs.size()):
		same = same and decoded[i].animal_a == designs[i].animal_a and decoded[i].animal_b == designs[i].animal_b \
				and decoded[i].picks == designs[i].picks and decoded[i].display_name() == designs[i].display_name()
	_check(same, "army rosters survive the trip to the other player")
	_check(Armies.decode_designs([["../../secret", "wolf", [0, 0, 0, 0, 0, -1], ""], ["wolf", "wolf", [0, 0, 7, 0, 0, -1], ""],
			"junk", ["wolf", "wolf", [0, 0, 0, 0, 0, 0], ""]]).is_empty(),
			"rosters with unknown animals, bad picks or wingless wings are refused")

	var sync := NetSync.new()
	var a := Node3D.new()
	var b := Node3D.new()
	add_child(a)
	add_child(b)
	a.set_meta(&"net_id", 7)
	b.set_meta(&"net_id", 70000)
	a.position = Vector3(12.345, 2.5, -40.01)
	b.position = Vector3(-47.9, 0.0, 47.9)
	a.rotation.y = 1.0
	b.rotation.y = -2.5
	var creatures := [a, b]
	var snapshot := NetSync.decode_snapshot(sync.encode_snapshot(3.25, creatures))
	_check(snapshot.units.size() == 2 and is_equal_approx(snapshot.time, 3.25), "a snapshot keeps its time and every creature")
	var first: Array = snapshot.units[0]
	var second: Array = snapshot.units[1]
	_check(first[0] == 7 and second[0] == 70000, "a snapshot keeps creature ids")
	_check(first[1].distance_to(a.position) < 0.01 and second[1].distance_to(b.position) < 0.01, "positions arrive to the centimetre")
	_check(absf(angle_difference(first[2], 1.0)) < 0.03 and absf(angle_difference(second[2], -2.5)) < 0.03, "facing arrives to a degree or two")
	_check(sync.encode_snapshot(0.0, creatures).size() == 6 + 2 * 11, "a snapshot costs 11 bytes per creature")
	_check(NetSync.decode_snapshot(PackedByteArray([1, 2, 3])).is_empty(), "a truncated snapshot is ignored")
	a.free()
	b.free()
	sync.free()

	var buffer := [[1.0, Vector3(0, 0, 0), 0.0], [2.0, Vector3(10, 0, 0), 1.0]]
	_check(NetSync.sample_buffer(buffer, 1.5)[0].is_equal_approx(Vector3(5, 0, 0)), "the joining player sees units halfway between snapshots")
	_check(NetSync.sample_buffer(buffer, 5.0)[0].is_equal_approx(Vector3(10, 0, 0)), "past the last snapshot a unit holds still rather than guessing")
	_check(NetSync.sample_buffer(buffer, 0.0)[0].is_equal_approx(Vector3.ZERO), "before the first snapshot a unit waits at the first")


func _test_options_and_accessibility() -> void:
	print("options and accessibility")
	_check(not Settings.persist, "tests never save the player's options")
	Settings.set_value("master_volume", 0.5)
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5) and is_equal_approx(Sfx.volume, 0.5),
			"master volume sets the master bus")
	Settings.set_value("voice_volume", 0.0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Voices")), "voices can be turned off on their own")
	Settings.set_value("ui_scale", 1.3)
	_check(is_equal_approx(get_tree().root.content_scale_factor, 1.3), "interface size scales the UI")
	Settings.reset_to_defaults()
	_check(is_equal_approx(get_tree().root.content_scale_factor, 1.0) and is_equal_approx(Settings.master_volume, 1.0),
			"reset puts everything back")

	var options := OptionsMenu.new()
	get_tree().root.add_child(options)
	options.open()
	await _process_frames(2)
	_check(options.visible and options.tabs.get_tab_count() == 4, "options has sound, display, controls and accessibility tabs")
	var stop_key: Key = (InputMap.action_get_events("stop")[0] as InputEventKey).physical_keycode
	var hold_keys := Settings.key_names("hold")
	options.rebind("hold", stop_key)
	_check(Settings.action_for_key(stop_key) == "hold", "a key can be rebound")
	_check(Settings.key_names("stop") == hold_keys, "the action that had the key takes the old one, so nothing is left unbound")
	_check(options.key_buttons["hold"].text == Settings.key_names("hold"), "the key list shows the new binding")
	var guide := HowToPlay.new()
	get_tree().root.add_child(guide)
	_check(guide.guide().contains("Hold: [b]%s[/b]" % Settings.key_names("hold")), "How to Play shows the current keys")
	guide.queue_free()
	Settings.reset_to_defaults()
	_check(Settings.action_for_key(stop_key) == "stop", "reset restores the default keys")
	_key(KEY_ESCAPE)
	_check(not options.visible, "Esc closes the options")
	options.queue_free()

	var confirmed := []
	var box := ConfirmBox.ask(get_tree().root, "Sure?", "Yes", func() -> void: confirmed.append(true))
	_key(KEY_ESCAPE)
	await _process_frames(1)
	_check(confirmed.is_empty() and not is_instance_valid(box), "Esc backs out of a confirmation")
	box = ConfirmBox.ask(get_tree().root, "Sure?", "Yes", func() -> void: confirmed.append(true))
	box.yes_button.pressed.emit()
	_check(confirmed.size() == 1, "confirming runs the action")
	await _process_frames(1)

	var main := await _load_map()
	var hud := main.get_node("UI/HUD")
	var menu: PauseMenu = hud.pause_menu
	menu.open()
	var restart: Button = menu.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Restart match")[0]
	restart.pressed.emit()
	await _process_frames(1)
	var asks := menu.find_children("*", "ConfirmBox", true, false)
	_check(asks.size() == 1 and main.is_inside_tree(), "restart asks first instead of throwing the match away")
	(asks[0] as ConfirmBox).no_button.pressed.emit()
	menu.close()

	var enemy := _first(1, "Brute")
	var red := Teams.color(1)
	Settings.set_value("colorblind", true)
	_check(Teams.color(1) != red and Teams.color(1) == Teams.CB_ENEMY_COLORS[0], "colour-blind mode swaps red enemies for orange")
	_check(Teams.color(0) == Teams.BLUE, "the player stays blue")
	Settings.set_value("colorblind", false)
	_check(Teams.color(1) == red, "and it can be turned off again")
	var bars: HealthBars = main.get_node("UI/HealthBars")
	_check(not bars.shows(enemy), "an unhurt, unselected creature has no health bar by default")
	Settings.set_value("health_bars", Settings.BARS_ALWAYS)
	_check(bars.shows(enemy), "health bars can be set to always show")
	Settings.reset_to_defaults()
	await _unload(main)


func _test_alert_pings_and_failed_orders() -> void:
	print("alert pings and failed orders")
	var main := await _load_map()
	var manager: SelectionManager = main.get_node("SelectionManager")
	var minimap := main.get_node("UI/HUD/Minimap")
	_first(0, "Runner").take_damage(1.0, _first(1, "Brute"))
	_check(minimap.pings.size() == 1, "an alert flashes on the minimap")
	_check(main.get_node("UI/HUD").message_label.text.contains("(%s to look)" % Settings.key_names("jump_to_alert", true)),
			"the alert names the look key")
	Alerts.report(1, Vector3(20, 0, 20), "Enemy hit")
	_check(minimap.pings.size() == 1, "the enemy's alerts don't ping")
	var henchmen := _team_units(0).filter(func(u: Creature) -> bool: return u is Henchman)
	manager.select_units(henchmen)
	manager.begin_placement(load("res://resources/buildings/generator.tres"))
	var lab := _building(0, "Lab")
	main.get_node("RTSCamera").focus_on(lab.global_position)
	await get_tree().process_frame
	var markers_before := main.get_children().filter(func(n: Node) -> bool: return "failed" in n and n.failed).size()
	manager.place_building_at_screen(manager.camera.unproject_position(lab.global_position))
	var markers := main.get_children().filter(func(n: Node) -> bool: return "failed" in n and n.failed)
	_check(markers.size() == markers_before + 1, "a building that doesn't fit leaves a red cross where it was tried")
	manager.cancel_placement()
	await _unload(main)


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


func _key(keycode: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	get_tree().root.push_input(event)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
