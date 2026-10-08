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
	await _test_target_choice()
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
	_check(hud.command_panel.visible and buttons.size() == 3, "Henchmen show a build menu with 3 buildings")
	buttons[1].pressed.emit()
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


func _add_building(data_path: String, team: int, at: Vector3) -> Building:
	var building: Building = load("res://scenes/buildings/building.tscn").instantiate()
	building.data = load(data_path)
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
