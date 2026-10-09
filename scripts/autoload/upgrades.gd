extends Node
## Upgrades each team has bought, and their combined effects.

signal changed(team: int)

const BASE_CARRY := 10
## Gathering can't get faster than this fraction of the normal time.
const MIN_GATHER_FACTOR := 0.4

## team -> {id: UpgradeData}
var _owned := {}


func reset(teams: Array[int]) -> void:
	_owned.clear()
	for team in teams:
		_owned[team] = {}
		changed.emit(team)


func has(team: int, id: StringName) -> bool:
	return _owned.has(team) and _owned[team].has(id)


func grant(team: int, upgrade: UpgradeData) -> void:
	if not _owned.has(team):
		_owned[team] = {}
	_owned[team][upgrade.id] = upgrade
	changed.emit(team)


func owned(team: int) -> Array:
	return _owned[team].values() if _owned.has(team) else []


## Sum of [param property] over the team's upgrades.
func total(team: int, property: StringName) -> float:
	var sum := 0.0
	for upgrade in owned(team):
		sum += upgrade.get(property)
	return sum


func melee_damage_bonus(team: int) -> float:
	return total(team, &"melee_damage")


func ranged_damage_bonus(team: int) -> float:
	return total(team, &"ranged_damage")


func melee_armor_bonus(team: int) -> float:
	return total(team, &"melee_armor")


func ranged_armor_bonus(team: int) -> float:
	return total(team, &"ranged_armor")


func speed_multiplier(team: int) -> float:
	return 1.0 + total(team, &"creature_speed")


func flyer_speed_multiplier(team: int) -> float:
	return 1.0 + total(team, &"flyer_speed")


func flyer_sight_bonus(team: int) -> float:
	return total(team, &"flyer_sight")


func henchman_speed_multiplier(team: int) -> float:
	return 1.0 + total(team, &"henchman_speed")


## Coal a Henchman of [param team] carries per trip.
func carry_capacity(team: int) -> int:
	return BASE_CARRY + int(total(team, &"carry"))


## Multiplier on the time a Henchman takes to mine one load.
func gather_time_factor(team: int) -> float:
	return maxf(1.0 - total(team, &"gather_speed"), MIN_GATHER_FACTOR)


func build_speed_multiplier(team: int) -> float:
	return 1.0 + total(team, &"build_speed")
