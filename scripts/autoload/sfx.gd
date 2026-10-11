extends Node
## Plays the placeholder sound effects (made by tools/generate_sounds.py):
## gibberish creature voices, bonks, slide whistles and kazoos.
##
## play() is for interface sounds heard at full volume; play_at() places a
## sound in the world so it fades with distance from the camera. Each sound
## has a short cooldown so a big fight doesn't stack fifty bonks at once.

const DIR := "res://assets/sounds/"
## Sound name -> variants picked at random.
const SOUNDS := {
	"select": ["select_1", "select_2", "select_3"],
	"move": ["move_1", "move_2"],
	"attack": ["attack_1", "attack_2"],
	"hit": ["hit"],
	"shoot": ["shoot"],
	"death": ["death"],
	"boing": ["boing"],
	"place": ["place"],
	"building_done": ["building_done"],
	"unit_ready": ["unit_ready"],
	"research_done": ["research_done"],
	"click": ["click"],
	"error": ["error"],
	"alert": ["alert"],
	"victory": ["victory"],
	"defeat": ["defeat"],
}
## Minimum seconds between two plays of the same sound.
const COOLDOWN := {"hit": 0.07, "shoot": 0.07, "death": 0.12, "click": 0.03, "select": 0.15,
		"move": 0.15, "attack": 0.15, "alert": 3.0}
const POOL_2D := 8
const POOL_3D := 16
const VOLUME_DB := -6.0

## The team whose events (buildings done, research, alerts) are announced.
var player_team := 0
## Master volume, 0 (muted) to 1; changed from the pause menu.
var volume := 1.0:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		var bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))
		AudioServer.set_bus_mute(bus, volume <= 0.0)
## Name of the most recent sound played, for tests.
var last_played := ""

var _streams := {}
var _last_time := {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound: String in SOUNDS:
		for file: String in SOUNDS[sound]:
			_streams[file] = load(DIR + file + ".wav")
	for i in POOL_2D:
		var player := AudioStreamPlayer.new()
		player.volume_db = VOLUME_DB
		add_child(player)
		_players_2d.append(player)
	for i in POOL_3D:
		var player := AudioStreamPlayer3D.new()
		player.volume_db = VOLUME_DB
		player.unit_size = 30.0
		player.max_distance = 110.0
		add_child(player)
		_players_3d.append(player)
	# Every button clicks.
	get_tree().node_added.connect(_on_node_added)


## Plays [param sound] at full volume (interface sounds).
func play(sound: String, pitch := 1.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var player := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	player.stream = stream
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	player.play()


## Plays [param sound] in the world at [param where].
func play_at(sound: String, where: Vector3, pitch := 1.0) -> void:
	var stream := _pick(sound)
	if stream == null:
		return
	var player := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	player.stream = stream
	player.global_position = where
	player.pitch_scale = pitch * randf_range(0.92, 1.08)
	player.play()


## Plays [param sound] for [param team]'s player only (at [param where], or
## as an interface sound when null). Online, the host sends it on when that
## player is on the other machine.
func play_for(team: int, sound: String, where: Variant = null, pitch := 1.0) -> void:
	if team == player_team:
		if where is Vector3:
			play_at(sound, where, pitch)
		else:
			play(sound, pitch)
	elif Net.sync:
		Net.sync.send_sound(team, sound, where, pitch)


## A creature's voice line: bigger creatures sound deeper.
func voice(sound: String, creature: Creature) -> void:
	play(sound, voice_pitch(creature))


func voice_pitch(creature: Creature) -> float:
	if creature == null or creature.stats == null:
		return 1.0
	return clampf(1.35 - 0.35 * creature.stats.size, 0.6, 1.6)


func _pick(sound: String) -> AudioStream:
	var files: Array = SOUNDS.get(sound, [])
	if files.is_empty():
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_time.get(sound, -100.0) < COOLDOWN.get(sound, 0.0):
		return null
	_last_time[sound] = now
	last_played = sound
	return _streams[files.pick_random()]


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play.bind("click", 1.0))
