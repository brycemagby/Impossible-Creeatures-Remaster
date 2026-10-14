extends Node
## Online multiplayer: hosting, joining, the lobby and starting a match.
##
## The game is host-authoritative. The host runs the whole simulation (units,
## combat, economy, AI) exactly as in a skirmish; the other player's game is a
## view of it. Their clicks are sent to the host as commands, and the host
## streams back what happened (see NetSync, which lives under this node as
## "Sync" during an online match). Lockstep would need the simulation to give
## bit-identical results on every machine, which Godot's physics, navigation
## and avoidance don't promise, so the host decides everything instead.
##
## Lobby flow: the host listens on a UDP port; a joining player connects and
## says hello with their name and army roster; the host assigns them a team
## and shares the lobby (players, map, fog). When the host starts, everyone
## gets the same match setup, including every player's roster, and loads the
## map. Everything here is a no-op offline, so skirmish is unchanged.

signal lobby_changed()
## A join attempt failed or the host refused us.
signal connection_failed(reason: String)
## The connection dropped or the other player left (outside a match too).
signal disconnected(reason: String)
## The host turned down one of our commands (e.g. "Not enough coal").
signal command_rejected(text: String)

enum Role { OFFLINE, HOST, CLIENT }

const DEFAULT_PORT := 7777
## Bumped whenever the messages change, so mismatched builds refuse to play.
const PROTOCOL_VERSION := 1
## Players in an online match, the host included.
const MAX_PLAYERS := 2
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var role := Role.OFFLINE
## The team this machine plays (the host is 0, the joining player 1).
var local_team := 0
var player_name := "Player"
## peer id -> {"name": String, "team": int}
var players := {}
## Lobby settings chosen by the host: {"map_index": int, "fog": bool}.
var settings := {"map_index": 0, "fog": true}
## Rosters for the match: team -> encoded designs (see Armies.encode_designs).
var _rosters := {}
## Set during an online match.
var sync: NetSync = null
var in_match := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


## Teams a person plays (the rest, if any, are run by the host's AI).
func human_teams() -> Array[int]:
	var teams: Array[int] = []
	for peer: int in players:
		teams.append(players[peer].team)
	return teams


func team_of_peer(peer: int) -> int:
	return players[peer].team if players.has(peer) else -1


## The peer playing [param team], or 0 if nobody does.
func peer_of_team(team: int) -> int:
	for peer: int in players:
		if players[peer].team == team:
			return peer
	return 0


# --- Hosting and joining ------------------------------------------------------

## Starts listening for a player on [param port]. Returns OK or the error.
func host(port := DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	local_team = 0
	players = {1: {"name": player_name, "team": 0}}
	_rosters = {0: Armies.encode_designs(Armies.designs(0))}
	lobby_changed.emit()
	return OK


## Connects to a host at [param address]. The result arrives later as
## lobby_changed (joined) or connection_failed.
func join(address: String, port := DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	players.clear()
	return OK


## Closes the connection and puts everything back to single player.
func leave() -> void:
	var was_online := is_online()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	role = Role.OFFLINE
	players.clear()
	_rosters.clear()
	in_match = false
	local_team = 0
	_end_sync()
	if was_online:
		Teams.player_team = 0
		Armies.restore_local()
		lobby_changed.emit()


## Host only: changes the map or fog and tells the other player.
func set_setting(key: String, value: Variant) -> void:
	if not is_host():
		return
	settings[key] = value
	_send_lobby()


func can_start() -> bool:
	return is_host() and not in_match and players.size() == MAX_PLAYERS


## Host only: everyone loads the map with the same setup.
func start_match() -> void:
	if not can_start():
		return
	var config := {
		"map_index": settings.map_index,
		"fog": settings.fog,
		"players": players.duplicate(true),
		"rosters": _rosters.duplicate(true),
	}
	_begin.rpc(config)
	_begin(config)


## Called first thing by player commands on units and buildings. On the
## joining player's machine it sends the command to the host and returns true,
## and the caller stops there: only the host changes the game. Elsewhere it
## returns false and the command runs normally.
func forward(node: Node, method: StringName, args := []) -> bool:
	if role != Role.CLIENT:
		return false
	if sync != null:
		sync.send_command(node, method, args, false)
	return true


## Addresses other players on this network can join with.
static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result


# --- Lobby messages -----------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int, name: String, roster: Array) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != PROTOCOL_VERSION:
		reason = "The host is running a different version of the game"
	elif in_match:
		reason = "That game has already started"
	elif players.size() >= MAX_PLAYERS:
		reason = "That game is full"
	if reason != "":
		_refused.rpc_id(peer, reason)
		# Let the refusal arrive before hanging up.
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer != null and peer in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(peer))
		return
	var team := _free_team()
	players[peer] = {"name": _clean_name(name), "team": team}
	_rosters[team] = Armies.encode_designs(Armies.decode_designs(roster))
	_send_lobby()


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	leave()
	connection_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(new_players: Dictionary, new_settings: Dictionary) -> void:
	players = new_players
	settings = new_settings
	local_team = team_of_peer(multiplayer.get_unique_id())
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _begin(config: Dictionary) -> void:
	players = config.players
	_rosters = config.rosters
	local_team = team_of_peer(multiplayer.get_unique_id())
	GameSettings.select_map(config.map_index)
	GameSettings.player_count = 2
	GameSettings.mode = GameSettings.Mode.FREE_FOR_ALL
	GameSettings.fog_enabled = config.fog
	GameSettings.game_speed = 1.0
	for team: int in _rosters:
		Armies.set_designs(team, Armies.decode_designs(_rosters[team]))
	Teams.player_team = local_team
	_end_sync()
	sync = NetSync.new()
	sync.name = "Sync"
	add_child(sync)
	in_match = true
	get_tree().change_scene_to_file(GameSettings.map_path())


func _send_lobby() -> void:
	_lobby.rpc(players, settings)
	lobby_changed.emit()


func _free_team() -> int:
	var taken := human_teams()
	var team := 0
	while team in taken:
		team += 1
	return team


static func _clean_name(name: String) -> String:
	name = name.strip_edges().left(20)
	return name if name != "" else "Player"


func _end_sync() -> void:
	if sync != null:
		sync.queue_free()
		sync = null


# --- Connection events --------------------------------------------------------

func _on_peer_connected(_peer: int) -> void:
	pass


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, PROTOCOL_VERSION, player_name, Armies.encode_designs(Armies.designs(0)))


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("Couldn't reach the host")


func _on_peer_disconnected(peer: int) -> void:
	if not is_host() or not players.has(peer):
		return
	var who: String = players[peer].name
	var team: int = players[peer].team
	players.erase(peer)
	_rosters.erase(team)
	if in_match:
		if sync != null:
			sync.peer_left(peer, team)
		disconnected.emit("%s left the game" % who)
	else:
		_send_lobby()


func _on_server_disconnected() -> void:
	if not in_match:
		leave()
		disconnected.emit("Lost connection to the host")
		return
	# Stay a (frozen) client view until the player leaves via the end screen,
	# which calls leave() and puts single player back.
	multiplayer.multiplayer_peer = null
	if sync != null:
		sync.host_left()
	disconnected.emit("Lost connection to the host")


## True while there's a live connection to send messages over.
func is_connected_to_game() -> bool:
	return multiplayer.multiplayer_peer != null \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
