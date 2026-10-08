extends Node
## Options chosen on the skirmish setup screen, read when a match starts.

enum Difficulty { EASY, NORMAL, HARD }

const MAPS := [
	{"name": "Island Clearing", "path": "res://scenes/main.tscn",
		"description": "Bases north and south, open ground with coal in the middle."},
	{"name": "Canyon", "path": "res://scenes/maps/canyon.tscn",
		"description": "Bases east and west, split by a rock wall with three passes."},
]
const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]

var map_index := 0
var difficulty := Difficulty.NORMAL
var fog_enabled := true
## Engine.time_scale during matches (changed from the pause menu or - / =).
var game_speed := 1.0


func map_path() -> String:
	return MAPS[map_index].path
