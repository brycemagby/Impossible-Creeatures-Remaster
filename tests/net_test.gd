extends Node
## End-to-end online test: two headless copies of the game, one hosting and
## one joining over localhost, play the start of a real match.
##
## Run with tests/run_net_test.sh (it starts both). By hand:
##   godot --headless --path . res://tests/net_test.tscn -- host 7790
##   godot --headless --path . res://tests/net_test.tscn -- client 7790
## Each exits with the number of failed checks. Both sides sit on the Play
## Online screen until the match starts, so it gets exercised too. With
## NET_TEST_SHOTS=<dir> (and a real display) each side saves screenshots.
##
## The two copies coordinate through RPCs on a driver node that lives at the
## same path (/root/NetTestDriver) on both, outside the map scene.

const TIMEOUT := 120.0
const MOVE_POINT := Vector3(6, 0, 0)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var driver := Driver.new()
	driver.name = "NetTestDriver"
	driver.role = args[0] if args.size() > 0 else "host"
	driver.port = int(args[1]) if args.size() > 1 else 7790
	get_tree().root.add_child.call_deferred(driver)


class Driver:
	extends Node

	var role := "host"
	var port := 7790
	var failures := 0
	var checks := 0
	var client_failures := -1
	var _facts := {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Armies.save_path = "user://net_test_army_%s.tres" % role
		Armies.set_designs(0, Armies.default_designs())
		get_tree().create_timer(TIMEOUT, true, false, true).timeout.connect(func() -> void:
			print("[%s] TIMEOUT" % role)
			get_tree().quit(99))
		get_tree().change_scene_to_file("res://scenes/ui/multiplayer_lobby.tscn")
		if role == "host":
			_run_host.call_deferred()
		else:
			_run_client.call_deferred()

	func check(passed: bool, what: String) -> void:
		checks += 1
		if not passed:
			failures += 1
		print("[%s] %s  %s" % [role, "PASS" if passed else "FAIL", what])

	func wait_until(condition: Callable, seconds: float) -> bool:
		var end := Time.get_ticks_msec() + int(seconds * 1000.0)
		while Time.get_ticks_msec() < end:
			if condition.call():
				return true
			await get_tree().process_frame
		return condition.call()

	func shot(label: String) -> void:
		var dir := OS.get_environment("NET_TEST_SHOTS")
		if dir == "" or DisplayServer.get_name() == "headless":
			return
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s-%s.png" % [dir, role, label])

	func wait(seconds: float) -> void:
		await get_tree().create_timer(seconds, true, false, true).timeout

	func units(team: int) -> Array:
		return get_tree().get_nodes_in_group("units").filter(func(u: Creature) -> bool: return u.team == team and u.is_alive())

	func lab(team: int) -> Building:
		for building: Building in get_tree().get_nodes_in_group("buildings"):
			if building.team == team and building.data.is_drop_off:
				return building
		return null

	# --- Host ------------------------------------------------------------------

	func _run_host() -> void:
		Net.player_name = "Host"
		check(Net.host(port) == OK, "hosts on port %d" % port)
		check(await wait_until(func() -> bool: return Net.players.size() == 2, 30.0), "the other player joins the lobby")
		check(Net.players.get(Net.players.keys().filter(func(p: int) -> bool: return p != 1)[0], {}).get("team") == 1,
				"the joining player gets team 1")
		await wait(0.5)
		check(get_tree().current_scene is MultiplayerLobby and get_tree().current_scene.start_button.visible
				and not get_tree().current_scene.start_button.disabled, "the Play Online screen lets the host start")
		await shot("lobby")
		await wait(1.0)
		Net.start_match()
		check(await wait_until(func() -> bool: return Net.sync != null and Net.sync.is_streaming(), 30.0),
				"the match starts once both maps are loaded")
		check(not get_tree().paused, "the host's game runs once the other player is in")
		check(get_tree().get_first_node_in_group("fog") == null or not Net.sync._match_root.has_node("EnemyAI"),
				"no computer opponent plays the human's team")
		await wait(1.0)
		var counts := {0: units(0).size(), 1: units(1).size()}
		check(counts[1] > 0, "team 1 has its starting creatures on the host")
		# Move one of ours so the other side can see it travel.
		var mover: Creature = units(0).filter(func(u: Creature) -> bool: return not u is Henchman)[0]
		mover.command_move(MOVE_POINT)
		_facts_to_client.rpc({"counts": counts, "mover": Net.sync.id_of(mover), "starting_coal": Economy.coal(1)})
		await wait(6.0)
		await shot("match")
		check(await wait_until(func() -> bool: return client_failures >= 0, 60.0), "the other player finishes their checks")
		# They leave: with nobody to fight, the host wins.
		var rules := Net.sync._match_root.get_node("GameRules") as GameRules
		check(await wait_until(func() -> bool: return rules.winner == Teams.alliance(0), 10.0),
				"the host wins when the other player leaves")
		_finish(failures + maxi(client_failures, 0))

	@rpc("any_peer", "call_remote", "reliable")
	func _client_moved(id: int, point: Vector3) -> void:
		_host_check_move(id, point)

	func _host_check_move(id: int, point: Vector3) -> void:
		var unit := Net.sync.node_of(id) as Creature
		check(unit != null and unit.team == 1, "the moved Henchman is team 1's")
		var arrived := await wait_until(func() -> bool:
			return is_instance_valid(unit) and Vector2(unit.global_position.x - point.x, unit.global_position.z - point.z).length() < 3.0, 20.0)
		check(arrived, "a move order from the other player walks their Henchman there on the host")

	@rpc("any_peer", "call_remote", "reliable")
	func _client_enqueued(lab_id: int, before: int) -> void:
		var building := Net.sync.node_of(lab_id) as Building
		var grew := await wait_until(func() -> bool:
			return is_instance_valid(building) and (not building.queue.is_empty() or units(1).size() > before), 5.0)
		check(grew, "the other player's production order queues a unit at their Lab on the host")

	@rpc("any_peer", "call_remote", "reliable")
	func _client_placed(spot: Vector3) -> void:
		var placed := await wait_until(func() -> bool:
			for building: Building in get_tree().get_nodes_in_group("buildings"):
				if building.team == 1 and building.global_position.distance_to(spot) < 0.5:
					return true
			return false, 5.0)
		check(placed, "the other player's building site appears on the host")

	@rpc("any_peer", "call_remote", "reliable")
	func _client_tried_cheating(id: int, start: Vector3) -> void:
		await wait(2.0)
		var unit := Net.sync.node_of(id) as Creature
		check(unit != null and unit.team == 0 and unit.global_position.distance_to(start) < 0.5,
				"the host ignores orders to units that aren't theirs")

	@rpc("any_peer", "call_remote", "reliable")
	func _client_done(count: int) -> void:
		client_failures = count

	# --- Client ----------------------------------------------------------------

	func _run_client() -> void:
		Net.player_name = "Guest"
		await wait(0.5)
		check(Net.join("127.0.0.1", port) == OK, "connects to the host")
		check(await wait_until(func() -> bool: return Net.players.size() == 2, 30.0), "joins the lobby")
		check(Net.local_team == 1, "plays team 1")
		await wait(0.5)
		check(get_tree().current_scene is MultiplayerLobby and get_tree().current_scene.lobby_box.visible
				and not get_tree().current_scene.start_button.visible, "the Play Online screen shows the lobby, without Start")
		await shot("lobby")
		check(await wait_until(func() -> bool: return not _facts.is_empty(), 60.0), "the match starts")
		var root := Net.sync._match_root
		var selection: SelectionManager = root.get_node("SelectionManager")
		check(Teams.color(1) == Teams.BLUE and Teams.color(0) != Teams.BLUE, "your own units are blue, the host's aren't")
		check(selection.player_team == 1, "you command team 1")
		check(not root.has_node("EnemyAI"), "no AI runs on the joining player's machine")
		var counts: Dictionary = _facts.counts
		check(await wait_until(func() -> bool: return units(0).size() == counts[0] and units(1).size() == counts[1], 5.0),
				"both armies show up: %d and %d creatures (host has %d and %d)" % [units(0).size(), units(1).size(), counts[0], counts[1]])
		var own_lab := lab(1)
		var camera := root.get_node("RTSCamera") as Node3D
		check(own_lab != null and Vector2(camera.global_position.x - own_lab.global_position.x,
				camera.global_position.z - own_lab.global_position.z).length() < 20.0, "the camera starts over your own base")

		# The host's creature walks to MOVE_POINT: its puppet should follow.
		var mover := Net.sync.node_of(_facts.mover) as Creature
		check(mover != null, "the host's moving creature exists here")
		var followed := await wait_until(func() -> bool:
			return is_instance_valid(mover) and Vector2(mover.global_position.x - MOVE_POINT.x, mover.global_position.z - MOVE_POINT.z).length() < 3.0, 20.0)
		check(followed, "the host's creature is seen walking to where it was sent")

		# Move a Henchman through the normal selection path.
		var henchman: Henchman = units(1).filter(func(u: Creature) -> bool: return u is Henchman)[0]
		var target := henchman.global_position + Vector3(4, 0, 0)
		selection.select_units([henchman])
		selection.issue_move(target)
		_client_moved.rpc_id(1, Net.sync.id_of(henchman), target)
		var walked := await wait_until(func() -> bool:
			return Vector2(henchman.global_position.x - target.x, henchman.global_position.z - target.z).length() < 3.0, 20.0)
		check(walked, "your Henchman is seen walking where you sent it")
		await shot("match")

		# Queue a Henchman at the Lab.
		var before := units(1).size()
		var recipe: UnitRecipe = own_lab.production_options()[0]
		check(own_lab.enqueue(recipe) == "", "the Lab accepts a production order")
		_client_enqueued.rpc_id(1, Net.sync.id_of(own_lab), before)
		check(await wait_until(func() -> bool: return not own_lab.queue.is_empty() or units(1).size() > before, 5.0),
				"the queued unit shows in your Lab's queue")
		check(await wait_until(func() -> bool: return Economy.coal(1) < _facts.starting_coal, 5.0), "its cost comes off your coal")
		check(await wait_until(func() -> bool: return units(1).size() > before, 30.0), "the new Henchman comes out of your Lab")

		# Place a House next to the Lab.
		var house: BuildingData = selection.buildable.filter(func(d: BuildingData) -> bool: return d.population > 0 and not d.is_drop_off)[0]
		selection.select_units([henchman])
		selection.begin_placement(house)
		var spot := Vector3.ZERO
		for offset in [Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8), Vector3(8, 0, 8), Vector3(-8, 0, -8)]:
			spot = selection.build_placer.snap(own_lab.global_position + offset)
			if selection.build_placer.check(spot) == "":
				break
		selection._request_placement(spot, false)
		_client_placed.rpc_id(1, spot)
		var site_seen := await wait_until(func() -> bool:
			for building: Building in get_tree().get_nodes_in_group("buildings"):
				if building.team == 1 and building.global_position.distance_to(spot) < 0.5:
					return true
			return false, 5.0)
		check(site_seen, "your building site appears")
		check(await wait_until(func() -> bool: return henchman.order == Creature.Order.BUILD, 5.0), "your Henchman goes to build it")

		# Orders to the host's units must be ignored.
		var enemy: Creature = units(0).filter(func(u: Creature) -> bool: return u != mover)[0]
		var enemy_start := enemy.global_position
		enemy.command_move(enemy_start + Vector3(10, 0, 0))
		_client_tried_cheating.rpc_id(1, Net.sync.id_of(enemy), enemy_start)
		await wait(2.5)
		check(enemy.global_position.distance_to(enemy_start) < 0.5, "you can't order the host's units around")

		_client_done.rpc_id(1, failures)
		await wait(0.5)
		Net.leave()
		_finish(failures)

	@rpc("authority", "call_remote", "reliable")
	func _facts_to_client(facts: Dictionary) -> void:
		_facts = facts

	func _finish(count: int) -> void:
		print("[%s] %d checks, %d failed" % [role, checks, count])
		await wait(0.5)
		get_tree().quit(count)
