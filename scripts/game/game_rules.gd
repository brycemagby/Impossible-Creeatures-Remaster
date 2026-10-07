class_name GameRules
extends Node
## Win condition: a team is eliminated when it has no creatures and no
## buildings left. The last team standing wins.

signal game_over(winner: int)

const CHECK_INTERVAL := 0.5

@export var teams: Array[int] = [0, 1]

## Winning team, or -1 while the game is still going.
var winner := -1
var _timer := 0.0


func _physics_process(delta: float) -> void:
	if winner >= 0:
		return
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	check_now()


func check_now() -> void:
	if winner >= 0:
		return
	var alive := {}
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		alive[target.team] = true
	var remaining := teams.filter(func(team: int) -> bool: return alive.has(team))
	if remaining.size() == 1:
		winner = remaining[0]
		game_over.emit(winner)
