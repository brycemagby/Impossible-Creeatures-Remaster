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

## Colour-blind palette (Settings.colorblind): friends in blues, enemies in
## warm colours, chosen to stay apart with red-green and blue-yellow colour
## blindness.
const CB_ALLY_COLORS: Array[Color] = [Color(0.45, 0.85, 0.95), Color(0.1, 0.65, 0.55)]
const CB_ENEMY_COLORS: Array[Color] = [Color(0.95, 0.58, 0.1), Color(0.95, 0.9, 0.3), Color(0.82, 0.45, 0.78), Color(0.92, 0.92, 0.92)]

## Teams in the current match.
var active: Array[int] = [0, 1]
## The local player's team (always 0 for now).
var player_team := 0
var _alliance := {}
var _colors := {}
var _colorblind := false


func _ready() -> void:
	_colorblind = Settings.colorblind
	Settings.changed.connect(_on_settings_changed)


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
			var ally_colors := CB_ALLY_COLORS if Settings.colorblind else ALLY_COLORS
			_colors[team] = ally_colors[allies % ally_colors.size()]
			allies += 1
		else:
			var enemy_colors := CB_ENEMY_COLORS if Settings.colorblind else ENEMY_COLORS
			_colors[team] = enemy_colors[enemies % enemy_colors.size()]
			enemies += 1


func _on_settings_changed() -> void:
	if Settings.colorblind == _colorblind:
		return
	_colorblind = Settings.colorblind
	_assign_colors()
	changed.emit()
	get_tree().call_group("targets", "refresh_team_color")


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
