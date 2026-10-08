class_name AIController
extends Node
## A simple opponent that runs a whole base.
##
## Every THINK_INTERVAL seconds it:
## - keeps Henchmen busy: idle ones gather coal, and two help build any
##   unfinished construction site;
## - builds what's missing: a Creature Chamber first, then Generators to keep
##   electricity flowing, then (from research level 2) a Workshop and a
##   Soundbeam Tower per Lab; one construction at a time, placed around its Lab;
## - buys Workshop and Research Center upgrades when it can spare the coal;
## - researches the next level at the Lab: once its army is big enough for
##   its current level it stops making creatures and saves up for research;
## - keeps its Lab and Chambers producing Henchmen and creatures it has unlocked.
## - defends: when it sees enemies near its buildings, nearby idle fighters
##   attack-move to them;
## - attacks: every [member wave_interval] seconds, if enough fighters are idle,
##   they attack-move at the nearest enemy building it has scouted, or toward
##   the nearest enemy start location it hasn't checked yet (with no start
##   locations on the map: the far side). Each wave asks for one more
##   creature than the last.
## Works for any number of enemies; allies (see Teams) are left alone.
## - pulls badly wounded fighters back to a Lab to heal, and sends them out
##   again once they're healthy;
## - expands: when the coal near its Labs runs low (or it's rich), it builds
##   another Lab next to unclaimed coal and moves some workers there.
## It only knows what its fog of war shows, like the player.

const THINK_INTERVAL := 1.0
const MAX_QUEUED := 2
const BUILDERS_PER_SITE := 2
const LAB_DATA := preload("res://resources/buildings/lab.tres")
const GENERATOR_DATA := preload("res://resources/buildings/generator.tres")
const CHAMBER_DATA := preload("res://resources/buildings/creature_chamber.tres")
const WORKSHOP_DATA := preload("res://resources/buildings/workshop.tres")
const RESEARCH_CENTER_DATA := preload("res://resources/buildings/research_center.tres")
const TOWER_DATA := preload("res://resources/buildings/soundbeam_tower.tres")
const HOUSE_DATA := preload("res://resources/buildings/house.tres")
## Build a House when population is within this many slots of the cap.
const HOUSE_MARGIN := 3
## The AI waits for this research level before building a Workshop, so the
## coal goes into its first creatures instead.
const AI_WORKSHOP_LEVEL := 2
## Distances from the Lab's centre to try when placing a building.
const PLACEMENT_RADII := [9.0, 12.0, 15.0, 18.0, 21.0]
const PLACEMENT_ANGLES := 16
## Enemies this close to one of its buildings trigger a defence.
const DEFEND_RADIUS := 20.0
## Fighters this close to the threat join the defence.
const DEFENDER_RADIUS := 45.0
const MAX_WAVE_SIZE := 12
## Retreat below this fraction of health; rejoin above RETURN_HEALTH.
const RETREAT_HEALTH := 0.3
const RETURN_HEALTH := 0.9
## Coal piles this close to a Lab count as that Lab's.
const BASE_COAL_RADIUS := 25.0
## Expand when the coal left near its Labs falls below this...
const EXPANSION_COAL_THRESHOLD := 1000
## ...or when it has this much coal banked and only one Lab.
const EXPANSION_RICH_COAL := 700
const MAX_LABS := 3
const EXPANSION_RADII := [6.0, 8.0, 10.0, 12.0]
## Workers sent to each newly built Lab's coal.
const EXPANSION_WORKERS := 2
## [wave interval, min wave size, max henchmen, coal income, army per level].
const DIFFICULTY_SETTINGS := {
	0: [150.0, 5, 5, 0.8, 1],
	1: [100.0, 4, 7, 1.0, 2],
	2: [70.0, 4, 9, 1.3, 2],
}

@export var enabled := true
@export var team := 1
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
## Fighters currently pulled back to heal.
var retreating: Array[Creature] = []


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
	manage_upgrades()
	manage_production()
	manage_retreats()
	defend_base()


# --- Retreats -----------------------------------------------------------------

## Sends badly wounded fighters to the nearest healing Lab and releases the
## ones that have recovered. Returns how many are retreating.
func manage_retreats() -> int:
	for unit in retreating.duplicate():
		if not Creature.is_valid_target(unit):
			retreating.erase(unit)
		elif unit.health >= unit.stats.max_health * RETURN_HEALTH:
			retreating.erase(unit)
			unit.command_stop()
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team != team or unit is Henchman or unit in retreating:
			continue
		if unit.health > unit.stats.max_health * RETREAT_HEALTH:
			continue
		var healer := _nearest_healer(unit.global_position)
		if healer == null or healer.heals_at(unit.global_position):
			continue
		var toward := (unit.global_position - healer.global_position)
		toward.y = 0.0
		unit.command_move(healer.global_position + toward.normalized() * (healer.radius() + 3.0))
		retreating.append(unit)
	return retreating.size()


func _nearest_healer(point: Vector3) -> Building:
	var best: Building = null
	for building in _buildings(true):
		if building.data.heal_radius > 0.0 and (best == null
				or building.global_position.distance_to(point) < best.global_position.distance_to(point)):
			best = building
	return best


# --- Defence ------------------------------------------------------------------

## Sends nearby idle fighters at the closest visible enemy threatening a
## building. Returns how many were sent.
func defend_base() -> int:
	var threat: Creature = null
	var threat_distance := DEFEND_RADIUS
	var buildings := _buildings(true) + _buildings(false)
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not Teams.are_enemies(unit.team, team) or not _can_see(unit.global_position):
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
		if unit.team != team or unit is Henchman or unit.attack_target != null or unit in retreating:
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
	_staff_expansions(henchmen)


## Makes sure every Lab with coal nearby has a few workers on that coal.
func _staff_expansions(henchmen: Array[Henchman]) -> void:
	for lab in _buildings(true):
		if not lab.data.is_drop_off:
			continue
		var piles := _piles_near(lab.global_position)
		if piles.is_empty():
			continue
		var working_here := henchmen.filter(func(h: Henchman) -> bool:
			return h.order == Creature.Order.GATHER and is_instance_valid(h.gather_target) and h.gather_target in piles)
		for henchman in henchmen:
			if working_here.size() >= EXPANSION_WORKERS:
				break
			if henchman.order != Creature.Order.GATHER or henchman in working_here:
				continue
			henchman.command_gather(piles[0])
			working_here.append(henchman)


# --- Construction -------------------------------------------------------------

func manage_construction() -> void:
	if not _buildings(false).is_empty() or _henchmen().is_empty():
		return
	var wanted := next_building()
	if wanted != null and Economy.can_afford(team, wanted.cost_coal, wanted.cost_electricity):
		if wanted == LAB_DATA and _count(LAB_DATA) > 0:
			var pile := expansion_site()
			if pile != null:
				place_building(wanted, pile.global_position, EXPANSION_RADII)
		elif wanted == TOWER_DATA:
			place_building(wanted, _unguarded_lab().global_position, EXPANSION_RADII)
		else:
			place_building(wanted)


## What to build next, or null if the base is complete.
func next_building() -> BuildingData:
	var chambers := _count(CHAMBER_DATA)
	if _count(LAB_DATA) == 0:
		return LAB_DATA
	if needs_house():
		return HOUSE_DATA
	if chambers == 0:
		return CHAMBER_DATA
	if _count(GENERATOR_DATA) < 1 + chambers * generators_per_chamber:
		return GENERATOR_DATA
	if Research.level(team) >= AI_WORKSHOP_LEVEL and _count(WORKSHOP_DATA) == 0:
		return WORKSHOP_DATA
	if Research.level(team) >= AI_WORKSHOP_LEVEL and _count(RESEARCH_CENTER_DATA) == 0:
		return RESEARCH_CENTER_DATA
	if Research.level(team) >= TOWER_DATA.required_research and _count(TOWER_DATA) < _count(LAB_DATA):
		return TOWER_DATA
	if wants_expansion():
		return LAB_DATA
	return null


## True when population is close to the cap and the cap can still grow.
func needs_house() -> bool:
	var cap := Population.cap(team)
	return cap < Population.MAX_POPULATION and Population.used(team) + HOUSE_MARGIN >= cap


## True when the coal around its Labs is running low, or when it's rich and
## has only one Lab, and there's somewhere to expand to.
func wants_expansion() -> bool:
	var labs := _count(LAB_DATA)
	if labs == 0 or labs >= MAX_LABS or expansion_site() == null:
		return false
	var nearby_coal := 0
	for building in _buildings(true):
		if building.data.is_drop_off:
			for pile in _piles_near(building.global_position):
				nearby_coal += pile.amount
	return nearby_coal < EXPANSION_COAL_THRESHOLD or (labs == 1 and Economy.coal(team) >= EXPANSION_RICH_COAL)


## The coal pile closest to home that no Lab covers and no known enemy
## building sits near, or null.
func expansion_site() -> CoalPile:
	var home := _home()
	var from := home.global_position if home else Vector3.ZERO
	var best: CoalPile = null
	for pile: CoalPile in get_tree().get_nodes_in_group("coal_piles"):
		var claimed := false
		for building: Building in get_tree().get_nodes_in_group("buildings"):
			var mine := building.team == team and building.data.is_drop_off
			var hostile := Teams.are_enemies(building.team, team) and _has_explored(building.global_position)
			if (mine or hostile) and building.global_position.distance_to(pile.global_position) < BASE_COAL_RADIUS:
				claimed = true
				break
		if claimed:
			continue
		if best == null or pile.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = pile
	return best


func _piles_near(point: Vector3) -> Array[CoalPile]:
	var result: Array[CoalPile] = []
	for pile: CoalPile in get_tree().get_nodes_in_group("coal_piles"):
		if pile.global_position.distance_to(point) < BASE_COAL_RADIUS:
			result.append(pile)
	return result


## Finds a free spot around [param near] (default: its Lab), facing the
## middle of the map first, and starts a construction site there. Returns it,
## or null.
func place_building(data: BuildingData, near: Variant = null, radii: Array = PLACEMENT_RADII) -> Building:
	var home := _home()
	var anchor: Vector3
	if near != null:
		anchor = near
	elif home != null:
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
	for radius: float in radii:
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
	if target == 0 or _count(CHAMBER_DATA, true) == 0 or is_saving_for_expansion():
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


## True while it wants a new Lab but can't afford one yet: creature
## production and research wait so the coal can build up.
func is_saving_for_expansion() -> bool:
	if not _buildings(false).is_empty() or next_building() != LAB_DATA or _count(LAB_DATA) == 0:
		return false
	return not Economy.can_afford(team, LAB_DATA.cost_coal, LAB_DATA.cost_electricity)


## Buys the next affordable Workshop or Research Center upgrade, keeping some coal in reserve.
func manage_upgrades() -> void:
	if is_saving_for_expansion() or is_saving_for_research():
		return
	for workshop in _buildings(true):
		if workshop.data.upgrades.is_empty() or workshop.upgrading != null:
			continue
		for upgrade in workshop.data.upgrades:
			if Upgrades.has(team, upgrade.id) or Research.level(team) < upgrade.required_research:
				continue
			if upgrade.requires != &"" and not Upgrades.has(team, upgrade.requires):
				continue
			if Economy.coal(team) >= upgrade.cost_coal + research_reserve and workshop.start_upgrade(upgrade) == "":
				return


## A Lab with no Soundbeam Tower near it (the home Lab first).
func _unguarded_lab() -> Building:
	var labs := _buildings(true).filter(func(b: Building) -> bool: return b.data == LAB_DATA)
	labs.sort_custom(func(a: Building, b: Building) -> bool: return a == _home())
	for lab: Building in labs:
		var guarded := false
		for tower in _buildings(true) + _buildings(false):
			if tower.data == TOWER_DATA and tower.global_position.distance_to(lab.global_position) < BASE_COAL_RADIUS:
				guarded = true
		if not guarded:
			return lab
	return _home()


func manage_production() -> void:
	var henchmen := _henchmen().size() + _queued_henchmen()
	var saving := is_saving_for_research() or is_saving_for_expansion()
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
		if unit.team == team and not unit is Henchman and unit.order == Creature.Order.IDLE and unit.attack_target == null \
				and unit not in retreating:
			idle.append(unit)
	if idle.size() < mini(min_wave_size + waves_sent, MAX_WAVE_SIZE):
		return 0
	var target: Variant = wave_target()
	if target == null:
		return 0
	SelectionManager.assign_formation(idle, target, formation_spacing, &"command_attack_move")
	waves_sent += 1
	return idle.size()


## The nearest enemy building this team has scouted; otherwise the nearest
## enemy start location it hasn't explored yet; otherwise the mirror image of
## its own base.
func wave_target() -> Variant:
	var home := _home()
	var from := home.global_position if home else Vector3.ZERO
	var best: Variant = null
	var best_distance := INF
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if not Teams.are_enemies(building.team, team) or not _has_explored(building.global_position):
			continue
		var distance := building.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = building.global_position
	if best != null:
		return best
	for start: Node3D in get_tree().get_nodes_in_group("start_locations"):
		var owner_team: int = start.get_meta("team", -1)
		if owner_team not in Teams.active or not Teams.are_enemies(owner_team, team) or _has_explored(start.global_position):
			continue
		var distance := start.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = start.global_position
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
