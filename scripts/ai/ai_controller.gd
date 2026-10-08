class_name AIController
extends Node
## A simple opponent.
##
## - Economy: idle Henchmen gather the nearest coal, the Lab keeps a few
##   Henchmen around, and production buildings stay busy with random units.
## - Defence is handled by the creatures themselves (they engage enemies in
##   sight, fight back, and come to defend buildings under attack).
## - Every [member wave_interval] seconds, idle combat units attack-move
##   toward the enemy's buildings or army.
##
## It doesn't construct new buildings yet.

const THINK_INTERVAL := 1.0
const MAX_QUEUED := 2

@export var enabled := true
@export var team := 1
@export var enemy_team := 0
## Seconds between attack waves. 0 disables waves.
@export var wave_interval := 90.0
## Waves only launch when at least this many combat units are idle.
@export var min_wave_size := 4
@export var max_henchmen := 5
@export var formation_spacing := 2.0

var _wave_timer := 0.0
var _think_timer := 0.0


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_think_timer += delta
	if _think_timer >= THINK_INTERVAL:
		_think_timer = 0.0
		manage_economy()
	if wave_interval > 0.0:
		_wave_timer += delta
		if _wave_timer >= wave_interval:
			_wave_timer = 0.0
			launch_wave()


func manage_economy() -> void:
	var henchmen := 0
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team != team or not unit is Henchman:
			continue
		henchmen += 1
		if unit.order == Creature.Order.IDLE and unit.attack_target == null:
			var pile: CoalPile = unit.find_coal_pile(INF)
			if pile != null:
				unit.command_gather(pile)

	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team != team or not building.is_complete or building.queue.size() >= MAX_QUEUED:
			continue
		var options: Array[UnitRecipe] = []
		for recipe in building.production_options():
			if recipe.is_worker and henchmen + _queued_henchmen() >= max_henchmen:
				continue
			if Economy.can_afford(team, recipe.cost_coal, recipe.cost_electricity):
				options.append(recipe)
		if not options.is_empty():
			building.enqueue(options.pick_random())


## Sends idle combat units at the enemy. Returns how many were sent.
func launch_wave() -> int:
	var idle: Array[Creature] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team and not unit is Henchman and unit.order == Creature.Order.IDLE and unit.attack_target == null:
			idle.append(unit)
	if idle.size() < min_wave_size:
		return 0
	var target: Variant = _wave_target()
	if target == null:
		return 0
	SelectionManager.assign_formation(idle, target, formation_spacing, &"command_attack_move")
	return idle.size()


## The enemy's nearest building, falling back to their army's centre.
func _wave_target() -> Variant:
	var home := Vector3.ZERO
	var count := 0
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team:
			home += building.global_position
			count += 1
	if count > 0:
		home /= count
	var best: Variant = null
	var best_distance := INF
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == enemy_team and building.global_position.distance_to(home) < best_distance:
			best_distance = building.global_position.distance_to(home)
			best = building.global_position
	if best != null:
		return best
	var center := Vector3.ZERO
	var enemies := 0
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == enemy_team:
			center += unit.global_position
			enemies += 1
	return center / enemies if enemies > 0 else null


func _queued_henchmen() -> int:
	var count := 0
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team:
			for recipe in building.queue:
				if recipe.is_worker:
					count += 1
	return count
