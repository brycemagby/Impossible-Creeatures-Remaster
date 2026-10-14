extends Node
## AI-vs-AI soak match for balance checks. Run headless:
##   godot --headless --path . --fixed-fps 30 res://tests/soak.tscn
## Env: SOAK_MAP (map index, default 0), SOAK_MINUTES (cap, default 25),
## SOAK_DIFFICULTY (0-2, default 1). Prints one SOAK line with the results.

var _time := 0.0
var _cap := 25.0 * 60.0
var _first_hit := {}
var _spawned := {}
var _hit_to_death: Array[float] = []
var _lifetimes: Array[float] = []
var _first_death := -1.0
var _winner := -1
var _done := false


func _ready() -> void:
	Settings.persist = false
	Settings.game_speed = 1.0
	GameSettings.map_index = int(OS.get_environment("SOAK_MAP")) if OS.has_environment("SOAK_MAP") else 0
	GameSettings.player_count = 2
	GameSettings.mode = GameSettings.Mode.FREE_FOR_ALL
	GameSettings.fog_enabled = false
	var difficulty := int(OS.get_environment("SOAK_DIFFICULTY")) if OS.has_environment("SOAK_DIFFICULTY") else GameSettings.Difficulty.NORMAL
	GameSettings.difficulty = difficulty
	if OS.has_environment("SOAK_MINUTES"):
		_cap = float(OS.get_environment("SOAK_MINUTES")) * 60.0
	get_tree().node_added.connect(_on_node_added)
	var map := (load(GameSettings.map_path()) as PackedScene).instantiate()
	add_child(map)
	var ai := AIController.new()
	ai.name = "AI0"
	ai.team = 0
	map.add_child(ai)
	ai.apply_difficulty(difficulty)
	Engine.time_scale = 1.0
	(map.get_node("GameRules") as GameRules).game_over.connect(func(w: int) -> void: _winner = w; _finish())
	for unit: Node in get_tree().get_nodes_in_group("units"):
		_on_node_added(unit)


func _on_node_added(node: Node) -> void:
	if node is Creature and not _spawned.has(node):
		_spawned[node] = _time
		node.health_changed.connect(_on_health_changed.bind(node))
		node.died.connect(_on_died)


func _on_health_changed(current: float, maximum: float, creature: Creature) -> void:
	if current < maximum and not _first_hit.has(creature):
		_first_hit[creature] = _time


func _on_died(creature: Creature) -> void:
	if _first_death < 0.0:
		_first_death = _time
	_lifetimes.append(_time - _spawned.get(creature, 0.0))
	_hit_to_death.append(_time - _first_hit.get(creature, _time))


func _physics_process(delta: float) -> void:
	_time += delta
	if _time >= _cap:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	print("SOAK %s" % JSON.stringify({
		"map": GameSettings.map_index,
		"winner": _winner,
		"minutes": snappedf(_time / 60.0, 0.1),
		"first_death_s": snappedf(_first_death, 0.1),
		"deaths": _lifetimes.size(),
		"spawned": _spawned.size(),
		"median_hit_to_death_s": snappedf(_median(_hit_to_death), 0.1),
		"median_lifetime_s": snappedf(_median(_lifetimes), 0.1),
	}))
	get_tree().quit()


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
