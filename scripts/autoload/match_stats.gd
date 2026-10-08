extends Node
## Per-team statistics for the current match, shown on the end screen.

const LABELS := {
	"units_produced": "Creatures produced",
	"kills": "Enemy creatures killed",
	"units_lost": "Creatures lost",
	"buildings_built": "Buildings built",
	"buildings_destroyed": "Enemy buildings destroyed",
	"buildings_lost": "Buildings lost",
	"coal_gathered": "Coal gathered",
}

## Game seconds since the match started (stops while paused or after the end).
var elapsed := 0.0
var running := false
var _stats := {}


func reset(teams: Array[int]) -> void:
	_stats.clear()
	for team in teams:
		var row := {}
		for key: String in LABELS:
			row[key] = 0.0
		_stats[team] = row
	elapsed = 0.0
	running = true


func stop() -> void:
	running = false


func add(team: int, key: String, amount := 1.0) -> void:
	if _stats.has(team):
		_stats[team][key] += amount


func get_stat(team: int, key: String) -> float:
	return _stats[team][key] if _stats.has(team) else 0.0


## A creature of [param team] died; [param killer_team] is -1 if unknown.
func record_death(team: int, killer_team: int) -> void:
	add(team, "units_lost")
	if killer_team >= 0 and killer_team != team:
		add(killer_team, "kills")


func record_building_lost(team: int, killer_team: int) -> void:
	add(team, "buildings_lost")
	if killer_team >= 0 and killer_team != team:
		add(killer_team, "buildings_destroyed")


func teams() -> Array:
	return _stats.keys()


func _physics_process(delta: float) -> void:
	if running:
		elapsed += delta
