class_name NetSync
extends Node
## One online match's networking, living at /root/Net/Sync on every machine.
##
## Host: runs the real game. Every creature, building and coal pile gets a
## network id (map-placed ones are numbered the same way on both machines;
## new ones are announced with a spawn message). Twenty times a second it
## sends where every creature is (a compact, unreliable snapshot), ten times a
## second whatever else changed (health, orders, production, resources), and
## one-off events as they happen (attacks, deaths, sounds, alerts).
##
## Joining player: never simulates. Units and buildings are puppets showing
## the host's state, positions blended between snapshots a little in the past
## so movement stays smooth. Player commands on puppets are forwarded to the
## host (see Net.forward), which checks they're theirs and carries them out.

## Shown on the host's HUD while waiting for the other player to load the map.
signal waiting_changed(waiting: bool)

const SNAPSHOT_INTERVAL := 0.05
const STATE_INTERVAL := 0.1
## The joining player's view runs this far behind the host, so there are
## (almost) always two snapshots to blend between.
const INTERP_DELAY := 0.12
const BUFFER_SIZE := 12
## Positions travel as whole centimetres in 16 bits (+-327 m).
const POSITION_SCALE := 100.0
const SNAPSHOT_HEADER := 6
const SNAPSHOT_ENTRY := 11
## Methods the joining player may call on their own units and buildings.
const CREATURE_COMMANDS := [&"command_move", &"command_attack", &"command_attack_move", &"command_stop",
	&"command_hold", &"command_patrol", &"clear_order_queue", &"set_stance", &"command_gather", &"command_build"]
const BUILDING_COMMANDS := [&"enqueue", &"cancel_at", &"start_research", &"cancel_research",
	&"start_upgrade", &"cancel_upgrade", &"set_rally_point", &"demolish"]
const UNIT_SCENE_DIR := "res://scenes/units/"
const CREATURE_DIR := "res://resources/creatures/"
const BUILDING_DIR := "res://resources/buildings/"
const UPGRADE_DIR := "res://resources/upgrades/"
const BuildingScene := preload("res://scenes/buildings/building.tscn")

## id -> Creature, Building or CoalPile
var _entities := {}
var _next_id := 1
## Ids up to this were placed in the map (both machines have them already).
var _scene_ids := 0
var _match_root: Node = null
## Host: game seconds since the match started. Joining player: local clock.
var _time := 0.0
var _snapshot_timer := 0.0
var _state_timer := 0.0
## Host: peers whose map has loaded (only they get match traffic).
var _ready_peers := {}
## Host: id -> the state last sent, to only send changes.
var _last_sent := {}
var _last_global := {}
## Host: places buildings for the other player.
var _placer: BuildPlacer = null
var _game_over := false
## Joining player: host clock minus local clock, smoothed.
var _offset := 0.0
var _have_offset := false
## Joining player: id -> Array of [host time, position, yaw].
var _buffers := {}


func _ready() -> void:
	# The host's game clock stops while paused (waiting for the other player).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Alerts.raised.connect(_on_alert_raised)


func is_streaming() -> bool:
	return Net.is_host() and not _ready_peers.is_empty() and _match_root != null


# --- Match start --------------------------------------------------------------

## Called by the map once its own setup is done (before any armies spawn).
func begin_match(root: Node) -> void:
	_match_root = root
	var found: Array[Node] = []
	for node in root.find_children("*", "", true, false):
		if node is Creature or node is Building or node is CoalPile:
			found.append(node)
	found.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path()))
	for node in found:
		_register(node, _next_id)
		_next_id += 1
	_scene_ids = _next_id - 1
	if Net.is_host():
		_placer = BuildPlacer.new()
		_placer.name = "NetBuildPlacer"
		root.add_child(_placer)
		var rules := root.get_node_or_null("GameRules") as GameRules
		if rules != null:
			rules.game_over.connect(_on_game_over)
		if _ready_peers.size() < Net.players.size() - 1:
			get_tree().paused = true
			waiting_changed.emit.call_deferred(true)
		else:
			_start_streaming.call_deferred()
	elif Net.is_connected_to_game():
		_client_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _client_loaded() -> void:
	if not Net.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if Net.team_of_peer(peer) < 0:
		return
	_ready_peers[peer] = true
	if _match_root != null:
		_send_everything(peer)
		_start_streaming()


func _start_streaming() -> void:
	if _ready_peers.size() < Net.players.size() - 1:
		return
	for peer: int in _ready_peers:
		_send_everything(peer)
	if get_tree().paused:
		get_tree().paused = false
	waiting_changed.emit(false)


## Brings a freshly loaded player up to date: every unit and building added
## since the map loaded, anything of the map's that's gone, and all state.
func _send_everything(peer: int) -> void:
	for id in range(1, _scene_ids + 1):
		if node_of(id) == null:
			_gone.rpc_id(peer, id)
	for id: int in _entities:
		if id > _scene_ids and node_of(id) != null:
			_spawn.rpc_id(peer, _spawn_info(_entities[id]))
	_last_sent.clear()
	_last_global.clear()
	_send_state()


# --- Registry -----------------------------------------------------------------

func id_of(node: Object) -> int:
	return node.get_meta(&"net_id", 0) if is_instance_valid(node) else 0


func node_of(id: int) -> Node:
	var node: Variant = _entities.get(id)
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return null
	return node


func _register(node: Node, id: int) -> void:
	node.set_meta(&"net_id", id)
	_entities[id] = node
	if Net.is_host():
		node.tree_exiting.connect(_on_entity_exiting.bind(id), CONNECT_ONE_SHOT)


## Units and buildings call this from _ready. On the host, anything new after
## the map loaded gets an id and is announced.
func entity_ready(node: Node) -> void:
	if not Net.is_host() or _match_root == null or id_of(node) != 0:
		return
	_register(node, _next_id)
	_next_id += 1
	if is_streaming():
		_broadcast(&"_spawn", [_spawn_info(node)])


func _on_entity_exiting(id: int) -> void:
	_entities.erase(id)
	_last_sent.erase(id)
	if is_streaming():
		_broadcast(&"_gone", [id])


func _spawn_info(node: Node) -> Dictionary:
	if node is Creature:
		return {"kind": "creature", "id": id_of(node), "scene": node.scene_file_path, "team": node.team,
			"stats": _encode_stats(node.stats), "position": node.global_position, "yaw": node.rotation.y}
	return {"kind": "building", "id": id_of(node), "data": node.data.resource_path, "team": node.team,
		"position": node.global_position, "yaw": node.rotation.y, "complete": node.is_complete}


static func _encode_stats(stats: CreatureStats) -> Dictionary:
	if stats.design != null:
		return {"design": Armies.encode_designs([stats.design])[0]}
	return {"path": stats.resource_path}


static func _decode_stats(data: Dictionary) -> CreatureStats:
	if data.has("design"):
		var design := Armies.decode_design(data.design)
		if design != null:
			return CreatureCombiner.build_stats(design)
	var path := str(data.get("path", ""))
	if path.begins_with(CREATURE_DIR) and ResourceLoader.exists(path):
		return load(path)
	return null


@rpc("authority", "call_remote", "reliable")
func _spawn(info: Dictionary) -> void:
	if _match_root == null or node_of(info.id) != null:
		return
	if info.kind == "creature":
		var scene_path := str(info.scene)
		var stats := _decode_stats(info.stats)
		if not scene_path.begins_with(UNIT_SCENE_DIR) or not ResourceLoader.exists(scene_path) or stats == null:
			return
		var unit: Creature = load(scene_path).instantiate()
		unit.stats = stats
		unit.team = info.team
		unit.position = info.position
		unit.rotation.y = info.yaw
		_register(unit, info.id)
		_container("unit_container").add_child(unit)
	elif info.kind == "building":
		var data_path := str(info.data)
		if not data_path.begins_with(BUILDING_DIR) or not ResourceLoader.exists(data_path):
			return
		var building: Building = BuildingScene.instantiate()
		building.data = load(data_path)
		building.team = info.team
		building.start_complete = info.complete
		building.position = info.position
		building.rotation.y = info.yaw
		_register(building, info.id)
		_container("building_container").add_child(building)


@rpc("authority", "call_remote", "reliable")
func _gone(id: int) -> void:
	var node := node_of(id)
	_entities.erase(id)
	_buffers.erase(id)
	# Dying units and buildings remove themselves after their death animation.
	if node != null and not (node.has_method("is_alive") and not node.is_alive()):
		node.queue_free()


func _container(group: String) -> Node:
	var container := get_tree().get_first_node_in_group(group)
	return container if container != null else _match_root


# --- Host: streaming ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_time += delta
	if not is_streaming():
		return
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = 0.0
		var snapshot := encode_snapshot(_time, _live_creatures())
		for peer: int in _ready_peers:
			_snapshot.rpc_id(peer, snapshot)
	_state_timer += delta
	if _state_timer >= STATE_INTERVAL:
		_state_timer = 0.0
		_send_state()


func _live_creatures() -> Array[Creature]:
	var result: Array[Creature] = []
	for id: int in _entities:
		var node := node_of(id)
		if node is Creature and node.is_alive():
			result.append(node)
	return result


## Where every creature is: [host time, count] then per creature its id,
## position in centimetres and facing in 1/256ths of a turn.
func encode_snapshot(time: float, creatures: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(SNAPSHOT_HEADER + creatures.size() * SNAPSHOT_ENTRY)
	bytes.encode_float(0, time)
	bytes.encode_u16(4, creatures.size())
	var at := SNAPSHOT_HEADER
	for unit: Node3D in creatures:
		var p := unit.global_position * POSITION_SCALE
		bytes.encode_u32(at, id_of(unit))
		bytes.encode_s16(at + 4, clampi(roundi(p.x), -32767, 32767))
		bytes.encode_s16(at + 6, clampi(roundi(p.y), -32767, 32767))
		bytes.encode_s16(at + 8, clampi(roundi(p.z), -32767, 32767))
		bytes.encode_u8(at + 10, posmod(roundi(unit.rotation.y / TAU * 256.0), 256))
		at += SNAPSHOT_ENTRY
	return bytes


## The reverse of encode_snapshot: {"time": float, "units": [[id, position, yaw], ...]}.
static func decode_snapshot(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < SNAPSHOT_HEADER:
		return {}
	var count := bytes.decode_u16(4)
	if bytes.size() < SNAPSHOT_HEADER + count * SNAPSHOT_ENTRY:
		return {}
	var units := []
	var at := SNAPSHOT_HEADER
	for i in count:
		var position := Vector3(bytes.decode_s16(at + 4), bytes.decode_s16(at + 6), bytes.decode_s16(at + 8)) / POSITION_SCALE
		units.append([bytes.decode_u32(at), position, bytes.decode_u8(at + 10) / 256.0 * TAU])
		at += SNAPSHOT_ENTRY
	return {"time": bytes.decode_float(0), "units": units}


## Everything that changed since last time, as one reliable message.
func _send_state() -> void:
	var creatures := {}
	var buildings := {}
	var piles := {}
	for id: int in _entities:
		var node := node_of(id)
		if node == null:
			continue
		var state: Array
		if node is Creature:
			if not node.is_alive():
				continue
			state = node.net_state()
		elif node is Building:
			if not node.is_alive():
				continue
			state = node.net_state()
		else:
			state = [node.amount]
		if _last_sent.get(id) == state:
			continue
		_last_sent[id] = state
		if node is Creature:
			creatures[id] = state
		elif node is Building:
			buildings[id] = state
		else:
			piles[id] = state[0]
	var global := {}
	for team in Teams.active:
		var upgrades := []
		for upgrade: UpgradeData in Upgrades.owned(team):
			upgrades.append(upgrade.resource_path)
		upgrades.sort()
		var row := [snappedf(Economy.coal(team), 0.1), snappedf(Economy.electricity(team), 0.1), Research.level(team), upgrades]
		if _last_global.get(team) != row:
			_last_global[team] = row
			global[team] = row
	if creatures.is_empty() and buildings.is_empty() and piles.is_empty() and global.is_empty():
		return
	var message := {"creatures": creatures, "buildings": buildings, "piles": piles, "global": global}
	for peer: int in _ready_peers:
		_state.rpc_id(peer, message)


## Calls the RPC [param method] with [param args] on every loaded player.
func _broadcast(method: StringName, args: Array) -> void:
	if not Net.is_connected_to_game():
		return
	for peer: int in _ready_peers:
		callv(&"rpc_id", [peer, method] + args)


## Host: something visible happened to [param node] (see the _event handler).
func entity_event(node: Node, event: StringName, args := []) -> void:
	if is_streaming():
		_broadcast(&"_event", [id_of(node), event, _encode_args(node, args)])


func entity_died(node: Node, destroyed := true) -> void:
	if is_streaming():
		_broadcast(&"_died", [id_of(node), destroyed])


## Host: plays [param sound] for [param team]'s player if they're remote.
func send_sound(team: int, sound: String, at: Variant, pitch: float) -> void:
	var peer := Net.peer_of_team(team)
	if is_streaming() and _ready_peers.has(peer):
		_sound.rpc_id(peer, sound, at, pitch)


func _on_alert_raised(team: int, text: String, where: Vector3) -> void:
	var peer := Net.peer_of_team(team)
	if is_streaming() and peer != multiplayer.get_unique_id() and _ready_peers.has(peer):
		_alert.rpc_id(peer, team, text, where)


func _on_game_over(winner: int) -> void:
	_game_over = true
	_send_state()
	_broadcast(&"_match_over", [winner, MatchStats.export_data()])


## Host: the other player disconnected. With nobody left to fight, you win.
func peer_left(peer: int, team: int) -> void:
	_ready_peers.erase(peer)
	if get_tree().paused and not _game_over:
		get_tree().paused = false
	waiting_changed.emit(false)
	var rules := _match_root.get_node_or_null("GameRules") as GameRules if _match_root else null
	if rules != null and rules.winner < 0:
		var remaining := Teams.active.duplicate()
		remaining.erase(team)
		if not remaining.is_empty():
			rules.declare_winner(Teams.alliance(remaining[0]))


## Joining player: the host went away; freeze the view.
func host_left() -> void:
	_buffers.clear()


# --- Joining player: receiving ------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snapshot(bytes: PackedByteArray) -> void:
	var snapshot := decode_snapshot(bytes)
	if snapshot.is_empty():
		return
	var sample: float = snapshot.time - _time
	if not _have_offset or absf(sample - _offset) > 0.5:
		_offset = sample
		_have_offset = true
	else:
		_offset = lerpf(_offset, sample, 0.1)
	for entry: Array in snapshot.units:
		var buffer: Array = _buffers.get(entry[0], [])
		buffer.append([snapshot.time, entry[1], entry[2]])
		if buffer.size() > BUFFER_SIZE:
			buffer.pop_front()
		_buffers[entry[0]] = buffer


func _process(delta: float) -> void:
	if not Net.is_client():
		return
	_time += delta
	if not _have_offset:
		return
	var render_time := _time + _offset - INTERP_DELAY
	for id: int in _buffers.keys():
		var unit := node_of(id) as Creature
		if unit == null or not unit.is_alive():
			_buffers.erase(id)
			continue
		var sample := sample_buffer(_buffers[id], render_time)
		var before := unit.global_position
		unit.global_position = sample[0]
		unit.rotation.y = sample[1]
		var moved: Vector3 = (unit.global_position - before) / maxf(delta, 0.0001)
		moved.y = 0.0
		unit.velocity = unit.velocity.lerp(moved, clampf(delta * 12.0, 0.0, 1.0))


## Position and yaw at [param time], blended between the two buffered
## snapshots around it (held at the ends rather than guessed).
static func sample_buffer(buffer: Array, time: float) -> Array:
	if time <= buffer[0][0]:
		return [buffer[0][1], buffer[0][2]]
	for i in range(1, buffer.size()):
		var b: Array = buffer[i]
		if time <= b[0]:
			var a: Array = buffer[i - 1]
			var t := inverse_lerp(a[0], b[0], time) if b[0] > a[0] else 1.0
			return [a[1].lerp(b[1], t), lerp_angle(a[2], b[2], t)]
	var last: Array = buffer[buffer.size() - 1]
	return [last[1], last[2]]


@rpc("authority", "call_remote", "reliable")
func _state(message: Dictionary) -> void:
	for id: int in message.creatures:
		var unit := node_of(id) as Creature
		if unit != null:
			unit.apply_net_state(message.creatures[id])
	for id: int in message.buildings:
		var building := node_of(id) as Building
		if building != null:
			building.apply_net_state(message.buildings[id])
	for id: int in message.piles:
		var pile := node_of(id) as CoalPile
		if pile != null:
			pile.set_amount(message.piles[id])
	for team: int in message.global:
		var row: Array = message.global[team]
		Economy.set_stock(team, row[0], row[1])
		if Research.level(team) != row[2]:
			Research.set_level(team, row[2])
		for path: String in row[3]:
			if not path.begins_with(UPGRADE_DIR) or not ResourceLoader.exists(path):
				continue
			var upgrade := load(path) as UpgradeData
			if upgrade != null and not Upgrades.has(team, upgrade.id):
				Upgrades.grant(team, upgrade)


@rpc("authority", "call_remote", "reliable")
func _event(id: int, event: StringName, args: Array) -> void:
	var node := node_of(id)
	if node == null:
		return
	var decoded: Variant = _decode_args(node, args)
	if decoded == null:
		return
	match event:
		&"attack":
			if node is Creature and decoded[0] != null:
				node.show_attack(decoded[0])
		&"puff":
			if node is Creature:
				node.callv(&"_show_puff", decoded)
		&"leap":
			if node is Creature:
				node.show_leap()
		&"beam":
			if node is Building and decoded[0] != null:
				node.show_beam(decoded[0])


@rpc("authority", "call_remote", "reliable")
func _died(id: int, destroyed: bool) -> void:
	var node := node_of(id)
	_buffers.erase(id)
	if node is Creature and node.is_alive():
		node.die_from_network()
	elif node is Building and node.is_alive():
		node.die_from_network(destroyed)


@rpc("authority", "call_remote", "reliable")
func _sound(sound: String, at: Variant, pitch: float) -> void:
	if at is Vector3:
		Sfx.play_at(sound, at, pitch)
	else:
		Sfx.play(sound, pitch)


@rpc("authority", "call_remote", "reliable")
func _alert(team: int, text: String, where: Vector3) -> void:
	Alerts.report(team, where, text)


@rpc("authority", "call_remote", "reliable")
func _rejected(text: String) -> void:
	Net.command_rejected.emit(text)


@rpc("authority", "call_remote", "reliable")
func _match_over(winner: int, stats: Dictionary) -> void:
	_game_over = true
	MatchStats.import_data(stats)
	var rules := _match_root.get_node_or_null("GameRules") as GameRules if _match_root else null
	if rules != null:
		rules.declare_winner(winner)


# --- Commands -----------------------------------------------------------------

## Joining player: asks the host to call [param method] on [param node].
## [param queued]: Shift-queued after the unit's current orders.
func send_command(node: Node, method: StringName, args: Array, queued: bool) -> void:
	var id := id_of(node)
	if id == 0 or not Net.is_connected_to_game():
		return
	_command.rpc_id(1, id, method, _encode_args(node, args), queued)


## Joining player: asks the host to place a [param data] site at [param point]
## and send [param builders] to build it.
func send_place(data: BuildingData, point: Vector3, builders: Array) -> void:
	if not Net.is_connected_to_game():
		return
	var ids := []
	for builder: Node in builders:
		ids.append(id_of(builder))
	_place.rpc_id(1, data.resource_path, point, ids)


@rpc("any_peer", "call_remote", "reliable")
func _command(id: int, method: StringName, args: Array, queued: bool) -> void:
	if not Net.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var node := node_of(id)
	if node == null or not node.has_method(method) or node.team != Net.team_of_peer(peer) or args.size() > 3:
		return
	if not (node is Creature and method in CREATURE_COMMANDS) and not (node is Building and method in BUILDING_COMMANDS):
		return
	var decoded: Variant = _decode_args(node, args)
	if decoded == null:
		return
	if queued:
		if node is Creature:
			node.queue_order(Callable(node, method).bindv(decoded))
		return
	var result: Variant = node.callv(method, decoded)
	if result is String and result != "":
		_rejected.rpc_id(peer, result)


@rpc("any_peer", "call_remote", "reliable")
func _place(data_path: String, point: Vector3, builder_ids: Array) -> void:
	if not Net.is_host() or _placer == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	var team := Net.team_of_peer(peer)
	if team < 0 or not data_path.begins_with(BUILDING_DIR) or not ResourceLoader.exists(data_path):
		return
	_placer.data = load(data_path)
	_placer.team = team
	var site := _placer.place(point)
	var error := _placer.last_error
	_placer.data = null
	if site == null:
		_rejected.rpc_id(peer, error)
		return
	for id in builder_ids:
		var builder := node_of(int(id)) as Henchman
		if builder != null and builder.team == team:
			builder.command_build(site)


## Units, buildings and coal piles travel as {"$": id}; recipes as their place
## in [param owner]'s production list; upgrades by file.
func _encode_args(owner: Node, args: Array) -> Array:
	var result := []
	for arg in args:
		if arg is Node:
			result.append({"$": id_of(arg)})
		elif arg is UnitRecipe:
			result.append({"recipe": owner.production_options().find(arg) if owner is Building else -1})
		elif arg is UpgradeData:
			result.append({"upgrade": arg.resource_path})
		else:
			result.append(arg)
	return result


## The reverse of _encode_args, or null if anything is unknown or unexpected.
func _decode_args(owner: Node, args: Array) -> Variant:
	var result := []
	for arg in args:
		if arg is Dictionary:
			if arg.has("$"):
				var id := int(arg["$"])
				var node := node_of(id)
				if id != 0 and node == null:
					return null
				result.append(node)
			elif arg.has("recipe") and owner is Building:
				var options: Array[UnitRecipe] = owner.production_options()
				var index := int(arg.recipe)
				if index < 0 or index >= options.size():
					return null
				result.append(options[index])
			elif arg.has("upgrade"):
				var path := str(arg.upgrade)
				if not path.begins_with(UPGRADE_DIR) or not ResourceLoader.exists(path):
					return null
				result.append(load(path))
			else:
				return null
		elif arg == null or arg is bool or arg is int or arg is float or arg is Vector3 or arg is Color:
			result.append(arg)
		else:
			return null
	return result
