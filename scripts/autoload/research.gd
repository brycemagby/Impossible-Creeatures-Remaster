extends Node
## Each team's research level (1-5). The Creature Chamber can only produce
## hybrids whose level is at or below it; the next level is researched at a
## Lab (see Building.start_research).

signal changed(team: int)

const MAX_LEVEL := 5
## Cost and time to research each level: [coal, electricity, seconds].
const COSTS := {
	2: [100, 50, 25.0],
	3: [200, 100, 40.0],
	4: [300, 175, 55.0],
	5: [400, 250, 70.0],
}

var _levels := {}


func reset(teams: Array[int], starting_level := 1) -> void:
	_levels.clear()
	for team in teams:
		_levels[team] = starting_level
		changed.emit(team)


func level(team: int) -> int:
	return _levels.get(team, 1)


func set_level(team: int, value: int) -> void:
	_levels[team] = clampi(value, 1, MAX_LEVEL)
	changed.emit(team)


## The next level [param team] can research, or 0 when fully researched.
func next_level(team: int) -> int:
	return level(team) + 1 if level(team) < MAX_LEVEL else 0


func coal_cost(target_level: int) -> int:
	return COSTS[target_level][0]


func electricity_cost(target_level: int) -> int:
	return COSTS[target_level][1]


func duration(target_level: int) -> float:
	return COSTS[target_level][2]


## Hand-authored creatures (no design) and Henchmen are never locked.
func can_produce(team: int, recipe: UnitRecipe) -> bool:
	return recipe.stats.design == null or recipe.stats.level <= level(team)
