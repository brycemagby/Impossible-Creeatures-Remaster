extends Node
## Upgrades each team has bought at a Workshop, and their effects.

signal changed(team: int)

const COAL_SACKS := &"coal_sacks"
const THICK_HIDES := &"thick_hides"
const FLEET_FEET := &"fleet_feet"

const BASE_CARRY := 10
const SACKS_CARRY := 15
const HIDES_ARMOR := 2.0
const FLEET_SPEED := 1.1

var _owned := {}


func reset(teams: Array[int]) -> void:
	_owned.clear()
	for team in teams:
		_owned[team] = {}
		changed.emit(team)


func has(team: int, id: StringName) -> bool:
	return _owned.has(team) and _owned[team].has(id)


func grant(team: int, id: StringName) -> void:
	if not _owned.has(team):
		_owned[team] = {}
	_owned[team][id] = true
	changed.emit(team)


## Coal a Henchman of [param team] carries per trip.
func carry_capacity(team: int) -> int:
	return SACKS_CARRY if has(team, COAL_SACKS) else BASE_CARRY


func armor_bonus(team: int) -> float:
	return HIDES_ARMOR if has(team, THICK_HIDES) else 0.0


func speed_multiplier(team: int) -> float:
	return FLEET_SPEED if has(team, FLEET_FEET) else 1.0
