extends Node
## Options chosen on the skirmish setup screen, read when a match starts.

enum Difficulty { EASY, NORMAL, HARD }
enum Mode { FREE_FOR_ALL, TEAMS }

const MAPS := [
	{"name": "Island Clearing", "path": "res://scenes/main.tscn", "players": 2,
		"description": "Bases north and south, open ground with coal in the middle."},
	{"name": "Canyon", "path": "res://scenes/maps/canyon.tscn", "players": 2,
		"description": "Bases east and west, split by a rock wall with three passes."},
	{"name": "Crossroads", "path": "res://scenes/maps/crossroads.tscn", "players": 4,
		"description": "Four corner bases around a rocky centre. Up to 4 players: free-for-all, or 2 vs 2 with your southern neighbour."},
]
const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]
const MODE_NAMES := ["Free-for-all", "2 vs 2"]

var map_index := 0
var difficulty := Difficulty.NORMAL
var fog_enabled := true
## Engine.time_scale during matches (changed from the pause menu or - / =).
var game_speed := 1.0
## Players in the match, you included (2 up to the map's maximum).
var player_count := 2
var mode := Mode.FREE_FOR_ALL


func map_path() -> String:
	return MAPS[map_index].path


func max_players() -> int:
	return MAPS[map_index].players


func select_map(index: int) -> void:
	map_index = index
	player_count = clampi(player_count, 2, max_players())
	if not teams_available():
		mode = Mode.FREE_FOR_ALL


## 2 vs 2 needs exactly four players.
func teams_available() -> bool:
	return player_count == 4


## Teams in the match: you are team 0, the AI the rest.
func active_teams() -> Array[int]:
	var teams: Array[int] = []
	for team in clampi(player_count, 2, max_players()):
		teams.append(team)
	return teams


## Team -> alliance (see Teams). Free-for-all: everyone on their own.
func alliances() -> Dictionary:
	if mode == Mode.TEAMS and player_count == 4:
		return {0: 0, 1: 0, 2: 1, 3: 1}
	return {}
