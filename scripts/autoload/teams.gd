extends Node
## Which teams are playing and who is allied with whom. Allies don't fight,
## share fog-of-war vision and win together. With no setup every team is on
## its own (free-for-all), which is what 1v1 needs.

signal changed()

const BLUE := Color(0.25, 0.55, 1.0)
const RED := Color(0.9, 0.25, 0.2)
const YELLOW := Color(0.95, 0.8, 0.2)
const GREEN := Color(0.4, 0.85, 0.35)
## Colours handed out in order: the local player is always blue, allies get
## green, enemies red then yellow (then the rest).
const ALLY_COLORS: Array[Color] = [GREEN, Color(0.3, 0.85, 0.85)]
const ENEMY_COLORS: Array[Color] = [RED, YELLOW, Color(0.85, 0.45, 0.9), Color(0.95, 0.55, 0.2)]

## Teams in the current match.
var active: Array[int] = [0, 1]
## The local player's team (always 0 for now).
var player_team := 0
var _alliance := {}
var _colors := {}


## [param alliances] maps team -> alliance id; teams left out are on their own.
func setup(teams: Array[int], alliances := {}) -> void:
	active = teams.duplicate()
	_alliance = alliances.duplicate()
	_assign_colors()
	changed.emit()


## The colour that marks [param team]'s units and buildings.
func color(team: int) -> Color:
	if _colors.is_empty():
		_assign_colors()
	if _colors.has(team):
		return _colors[team]
	return BLUE if team == player_team else ENEMY_COLORS[(team - 1) % ENEMY_COLORS.size()]


func _assign_colors() -> void:
	_colors.clear()
	var allies := 0
	var enemies := 0
	for team in active:
		if team == player_team:
			_colors[team] = BLUE
		elif are_allies(team, player_team):
			_colors[team] = ALLY_COLORS[allies % ALLY_COLORS.size()]
			allies += 1
		else:
			_colors[team] = ENEMY_COLORS[enemies % ENEMY_COLORS.size()]
			enemies += 1


func alliance(team: int) -> int:
	return _alliance.get(team, team)


func are_enemies(a: int, b: int) -> bool:
	return alliance(a) != alliance(b)


func are_allies(a: int, b: int) -> bool:
	return alliance(a) == alliance(b)


func enemies_of(team: int) -> Array[int]:
	var result: Array[int] = []
	for other in active:
		if are_enemies(team, other):
			result.append(other)
	return result


## Every active team in [param alliance_id].
func members(alliance_id: int) -> Array[int]:
	var result: Array[int] = []
	for team in active:
		if alliance(team) == alliance_id:
			result.append(team)
	return result
