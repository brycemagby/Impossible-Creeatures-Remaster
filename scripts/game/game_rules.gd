class_name GameRules
extends Node
## Win condition: a team is eliminated when it has no creatures and no
## buildings left. The last alliance standing wins (in a free-for-all every
## team is its own alliance).

## [param winner] is the winning alliance id (see Teams).
signal game_over(winner: int)

const CHECK_INTERVAL := 0.5

## Winning alliance, or -1 while the game is still going.
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
		if target.team in Teams.active:
			alive[Teams.alliance(target.team)] = true
	if alive.size() == 1:
		winner = alive.keys()[0]
		game_over.emit(winner)


## Teams knocked out so far (no creatures or buildings left).
func eliminated_teams() -> Array[int]:
	var alive := {}
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		alive[target.team] = true
	var result: Array[int] = []
	for team in Teams.active:
		if not alive.has(team):
			result.append(team)
	return result
