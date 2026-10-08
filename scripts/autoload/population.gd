extends Node
## Population, AoE2-style: every creature and Henchman takes one slot.
## Finished buildings with a population value (Lab 10, House 5) raise the
## cap, up to MAX_POPULATION. A building only starts its next unit if there's
## room, and holds that slot until the unit comes out.
##
## Loop variables are untyped on purpose: naming the Building/Creature classes
## from an autoload creates a script reference cycle that Godot 4.3 reports
## as leaked instances at exit.

const MAX_POPULATION := 100


## Population room [param team] has.
func cap(team: int) -> int:
	var total := 0
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.is_complete:
			total += building.data.population
	return mini(total, MAX_POPULATION)


## Living creatures and Henchmen, plus units already being produced.
func used(team: int) -> int:
	var count := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.team == team:
			count += 1
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.production_reserved:
			count += 1
	return count


func has_room(team: int) -> bool:
	return used(team) < cap(team)
