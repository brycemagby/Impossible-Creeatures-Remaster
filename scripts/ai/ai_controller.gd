class_name AIController
extends Node
## A simple opponent that runs a whole base.
##
## Every THINK_INTERVAL seconds it:
## - keeps Henchmen busy: idle ones gather coal, and two help build any
##   unfinished construction site;
## - builds what's missing: a Creature Chamber first, then Generators to keep
##   electricity flowing (one construction at a time), placed around its Lab;
## - researches the next level at the Lab: once its army is big enough for
##   its current level it stops making creatures and saves up for research;
## - keeps its Lab and Chambers producing Henchmen and creatures it has unlocked.
## - defends: when it sees enemies near its buildings, nearby idle fighters
##   attack-move to them;
## - attacks: every [member wave_interval] seconds, if enough fighters are idle,
##   they attack-move at the nearest enemy building it has scouted, or toward
##   where the enemy base probably is (the far side of the map). Each wave
##   asks for one more creature than the last.
## It only knows what its fog of war shows, like the player.

const THINK_INTERVAL := 1.0
const MAX_QUEUED := 2
const BUILDERS_PER_SITE := 2
const LAB_DATA := preload("res://resources/buildings/lab.tres")
const GENERATOR_DATA := preload("res://resources/buildings/generator.tres")
const CHAMBER_DATA := preload("res://resources/buildings/creature_chamber.tres")
## Distances from the Lab's centre to try when placing a building.
const PLACEMENT_RADII := [9.0, 12.0, 15.0, 18.0, 21.0]
const PLACEMENT_ANGLES := 16
## Enemies this close to one of its buildings trigger a defence.
const DEFEND_RADIUS := 20.0
## Fighters this close to the threat join the defence.
const DEFENDER_RADIUS := 45.0
const MAX_WAVE_SIZE := 12
## [wave interval, min wave size, max henchmen, coal income, army per level].
const DIFFICULTY_SETTINGS := {
	0: [150.0, 5, 5, 0.8, 1],
	1: [100.0, 4, 7, 1.0, 2],
	2: [70.0, 4, 9, 1.3, 2],
}

@export var enabled := true
@export var team := 1
@export var enemy_team := 0
## Seconds between attack waves. 0 disables waves.
@export var wave_interval := 90.0
## Waves only launch when at least this many combat units are idle.
@export var min_wave_size := 4
@export var max_henchmen := 7
@export var formation_spacing := 2.0
## Generators wanted per Creature Chamber (plus one).
@export var generators_per_chamber := 1
## Coal kept back from research so production doesn't stall.
@export var research_reserve := 120
## Combat units wanted before saving up for the next research level:
## army_per_level * current level + army_base.
@export var army_base := 3
@export var army_per_level := 2

var _wave_timer := 0.0
var _think_timer := 0.0
var _placer: BuildPlacer
var waves_sent := 0


func _ready() -> void:
	_placer = BuildPlacer.new()
	add_child(_placer)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_think_timer += delta
	if _think_timer >= THINK_INTERVAL:
		_think_timer = 0.0
		think()
	if wave_interval > 0.0:
		_wave_timer += delta
		if _wave_timer >= wave_interval:
			_wave_timer = 0.0
			launch_wave()


## Applies a GameSettings.Difficulty level.
func apply_difficulty(level: int) -> void:
	var settings: Array = DIFFICULTY_SETTINGS[level]
	wave_interval = settings[0]
	min_wave_size = settings[1]
	max_henchmen = settings[2]
	Economy.set_income_multiplier(team, settings[3])
	army_per_level = settings[4]


## One round of decisions. Public so tests can step the AI.
func think() -> void:
	# Place new sites first so workers are assigned to them straight away.
	manage_construction()
	manage_workers()
	manage_research()
	manage_production()
	defend_base()


# --- Defence ------------------------------------------------------------------

## Sends nearby idle fighters at the closest visible enemy threatening a
## building. Returns how many were sent.
func defend_base() -> int:
	var threat: Creature = null
	var threat_distance := DEFEND_RADIUS
	var buildings := _buildings(true) + _buildings(false)
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team != enemy_team or not _can_see(unit.global_position):
			continue
		for building in buildings:
			var distance := building.edge_distance_from(unit.global_position)
			if distance < threat_distance:
				threat_distance = distance
				threat = unit
	if threat == null:
		return 0
	var sent := 0
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team != team or unit is Henchman or unit.attack_target != null:
			continue
		if unit.order != Creature.Order.IDLE and unit.order != Creature.Order.MOVE:
			continue
		if unit.global_position.distance_to(threat.global_position) <= DEFENDER_RADIUS:
			unit.command_attack_move(threat.global_position)
			sent += 1
	return sent


# --- Workers ------------------------------------------------------------------

func manage_workers() -> void:
	var henchmen := _henchmen()
	for site in _buildings(false):
		var builders := henchmen.filter(func(h: Henchman) -> bool: return h.build_target == site)
		for henchman in henchmen:
			if builders.size() >= BUILDERS_PER_SITE:
				break
			if henchman.order == Creature.Order.BUILD or henchman.attack_target != null:
				continue
			henchman.command_build(site)
			builders.append(henchman)
	for henchman in henchmen:
		if henchman.order == Creature.Order.IDLE and henchman.attack_target == null:
			var pile: CoalPile = henchman.find_coal_pile(INF)
			if pile != null:
				henchman.command_gather(pile)


# --- Construction -------------------------------------------------------------

func manage_construction() -> void:
	if not _buildings(false).is_empty() or _henchmen().is_empty():
		return
	var wanted := next_building()
	if wanted != null and Economy.can_afford(team, wanted.cost_coal, wanted.cost_electricity):
		place_building(wanted)


## What to build next, or null if the base is complete.
func next_building() -> BuildingData:
	var chambers := _count(CHAMBER_DATA)
	if _count(LAB_DATA) == 0:
		return LAB_DATA
	if chambers == 0:
		return CHAMBER_DATA
	if _count(GENERATOR_DATA) < 1 + chambers * generators_per_chamber:
		return GENERATOR_DATA
	return null


## Finds a free spot around the Lab, facing the middle of the map first, and
## starts a construction site there. Returns it, or null.
func place_building(data: BuildingData) -> Building:
	var home := _home()
	var anchor: Vector3
	if home != null:
		anchor = home.global_position
	elif not _henchmen().is_empty():
		# Lost every building: start again where the workers are.
		anchor = _henchmen()[0].global_position
	else:
		return null
	var toward_center := -anchor
	toward_center.y = 0.0
	var base_angle := atan2(toward_center.x, toward_center.z)
	_placer.start(data, team)
	var site: Building = null
	for radius: float in PLACEMENT_RADII:
		for i in PLACEMENT_ANGLES:
			# Alternate either side of the centre direction: 0, +1, -1, +2...
			var step := ceili(i / 2.0) * (1 if i % 2 == 1 else -1)
			var angle := base_angle + step * TAU / PLACEMENT_ANGLES
			var spot := anchor + Vector3(sin(angle), 0.0, cos(angle)) * radius
			if _placer.can_place_at(_placer.snap(spot)):
				site = _placer.place(spot)
				break
		if site != null:
			break
	_placer.cancel()
	return site


# --- Research and production ----------------------------------------------------

func manage_research() -> void:
	var target := Research.next_level(team)
	if target == 0 or _count(CHAMBER_DATA, true) == 0:
		return
	var reserve := 0 if is_saving_for_research() else research_reserve
	if Economy.coal(team) < Research.coal_cost(target) + reserve:
		return
	for lab in _buildings(true):
		if lab.data.can_research and lab.start_research() == "":
			return


## True when the army is big enough for the current research level and the
## next level is still to come (and not already being researched).
func is_saving_for_research() -> bool:
	if Research.next_level(team) == 0:
		return false
	for lab in _buildings(true):
		if lab.researching > 0:
			return false
	return _fighter_count() >= army_base + army_per_level * Research.level(team)


func manage_production() -> void:
	var henchmen := _henchmen().size() + _queued_henchmen()
	var saving := is_saving_for_research()
	for building in _buildings(true):
		if building.queue.size() >= MAX_QUEUED:
			continue
		var options: Array[UnitRecipe] = []
		for recipe in building.production_options():
			if recipe.is_worker and henchmen >= max_henchmen:
				continue
			if saving and not recipe.is_worker:
				continue
			if not Research.can_produce(team, recipe):
				continue
			if Economy.can_afford(team, recipe.cost_coal, recipe.cost_electricity):
				options.append(recipe)
		if not options.is_empty():
			# Prefer the strongest creatures it can afford.
			var best_level := 0
			for option in options:
				best_level = maxi(best_level, option.stats.level)
			var recipe: UnitRecipe = options.filter(
					func(r: UnitRecipe) -> bool: return r.stats.level >= best_level - 1).pick_random()
			building.enqueue(recipe)
			if recipe.is_worker:
				henchmen += 1


# --- Attack waves -------------------------------------------------------------

## Sends idle combat units at the enemy. Returns how many were sent.
func launch_wave() -> int:
	var idle: Array[Creature] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team and not unit is Henchman and unit.order == Creature.Order.IDLE and unit.attack_target == null:
			idle.append(unit)
	if idle.size() < mini(min_wave_size + waves_sent, MAX_WAVE_SIZE):
		return 0
	var target: Variant = wave_target()
	if target == null:
		return 0
	SelectionManager.assign_formation(idle, target, formation_spacing, &"command_attack_move")
	waves_sent += 1
	return idle.size()


## The nearest enemy building this team has scouted; otherwise the mirror
## image of its own base, where the enemy most likely lives.
func wave_target() -> Variant:
	var home := _home()
	var from := home.global_position if home else Vector3.ZERO
	var best: Variant = null
	var best_distance := INF
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team != enemy_team or not _has_explored(building.global_position):
			continue
		var distance := building.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = building.global_position
	if best != null:
		return best
	return Vector3(-from.x, 0.0, -from.z) if home else null


func _fog() -> FogOfWar:
	return get_tree().get_first_node_in_group("fog") as FogOfWar


func _can_see(point: Vector3) -> bool:
	var fog := _fog()
	return fog == null or fog.is_visible(team, point)


func _has_explored(point: Vector3) -> bool:
	var fog := _fog()
	return fog == null or fog.is_explored(team, point)


# --- Helpers ------------------------------------------------------------------

## This team's buildings, finished ([param complete] true) or still under
## construction (false).
func _buildings(complete: bool) -> Array[Building]:
	var result: Array[Building] = []
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.is_complete == complete:
			result.append(building)
	return result


## How many buildings of [param data] this team has (sites count too unless
## [param complete_only]).
func _count(data: BuildingData, complete_only := false) -> int:
	var count := 0
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.data == data and (building.is_complete or not complete_only):
			count += 1
	return count


func _home() -> Building:
	for building in _buildings(true):
		if building.data.is_drop_off:
			return building
	var all := _buildings(true)
	return all[0] if not all.is_empty() else null


func _henchmen() -> Array[Henchman]:
	var result: Array[Henchman] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team and unit is Henchman:
			result.append(unit)
	return result


func _fighter_count() -> int:
	var count := 0
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team and not unit is Henchman:
			count += 1
	for building in _buildings(true):
		for recipe in building.queue:
			if not recipe.is_worker:
				count += 1
	return count


func _queued_henchmen() -> int:
	var count := 0
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team:
			for recipe in building.queue:
				if recipe.is_worker:
					count += 1
	return count
