class_name Building
extends StaticBody3D
## A team-owned structure: constructed by Henchmen, produces units, can be
## attacked and destroyed.
##
## Drawn by a [BuildingModel] (placeholder art per building, swappable for
## real art); collision is a box the size of its [BuildingData] footprint.

signal completed(building: Building)
signal production_changed(building: Building)
signal died(building: Building)

const MAX_QUEUE := 5
## A fresh construction site starts with this fraction of its health.
const SITE_HEALTH_FRACTION := 0.1
## Idle units within this radius come to defend a building under attack.
const DEFEND_RADIUS := 15.0
const SPAWN_GAP := 1.2
const HEAL_INTERVAL := 0.5
const BEAM_COLOR := Color(0.45, 0.75, 1.0, 0.95)

@export var data: BuildingData
@export var team := 0
## Pre-placed buildings start finished; placed ones start as construction sites.
@export var start_complete := true

## Coal owed for repairs so far, paid a whole unit at a time.
var _repair_debt := 0.0
var health := 0.0
var is_complete := false
## Construction progress from 0 to 1.
var build_progress := 0.0
var queue: Array[UnitRecipe] = []
## Seconds spent on the unit at the front of the queue.
var production_time := 0.0
## The unit at the front of the queue has a population slot and is in progress.
var production_reserved := false
## The front unit is waiting for population room (build more Houses).
var population_blocked := false
## Research level being studied here, or 0.
var researching := 0
var research_time := 0.0
var rally_point: Variant = null
## Coal pile the rally point is on, if any: new Henchmen start gathering it.
var rally_pile: CoalPile = null
var is_selected := false

var _dead := false
var _last_attacker_team := -1
var _heal_timer := 0.0
var _attack_timer := 0.0
## Workshop: the upgrade being bought, and progress in seconds.
var upgrading: UpgradeData = null
var upgrade_time := 0.0

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var model: BuildingModel = $Model
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var rally_flag: Node3D = $RallyFlag


func _ready() -> void:
	add_to_group("buildings")
	add_to_group("targets")
	_build_visuals()
	set_selected(false)
	if start_complete:
		health = data.max_health
		_finish_construction(false)
	else:
		health = data.max_health * SITE_HEALTH_FRACTION
		_update_construction_visual()
	if Net.sync:
		Net.sync.entity_ready(self)


func _physics_process(delta: float) -> void:
	# Online, only the host runs buildings; the other player sees its state.
	if not is_complete or Net.is_client():
		return
	if data.electricity_per_second > 0.0:
		Economy.add(team, 0.0, data.electricity_per_second * delta)
	if data.attack_damage > 0.0:
		_update_tower(delta)
	if upgrading != null:
		upgrade_time += delta
		if upgrade_time >= upgrading.duration:
			Upgrades.grant(team, upgrading)
			Sfx.play_for(team, "research_done")
			upgrading = null
			upgrade_time = 0.0
			production_changed.emit(self)
	if data.heal_radius > 0.0:
		_heal_timer += delta
		if _heal_timer >= HEAL_INTERVAL:
			_heal_nearby(data.heal_per_second * _heal_timer)
			_heal_timer = 0.0
	if researching > 0:
		research_time += delta
		if research_time >= Research.duration(researching):
			Research.set_level(team, researching)
			Sfx.play_for(team, "research_done")
			researching = 0
			research_time = 0.0
			production_changed.emit(self)
	if not queue.is_empty():
		if not production_reserved:
			production_reserved = Population.has_room(team)
			if population_blocked == production_reserved:
				population_blocked = not production_reserved
				production_changed.emit(self)
		if production_reserved:
			production_time += delta
			if production_time >= queue[0].build_time:
				production_time = 0.0
				production_reserved = false
				_spawn(queue.pop_front())
				Sfx.play_for(team, "unit_ready", global_position)
				production_changed.emit(self)


# --- Production ---------------------------------------------------------------

## What this building can make right now.
func production_options() -> Array[UnitRecipe]:
	if not data.produces_army:
		return data.production
	var options: Array[UnitRecipe] = []
	for recipe in Armies.recipes(team):
		var stats := recipe.stats
		var makes := stats.can_fly if data.flyer_production else (stats.can_swim if data.water_production
				else not stats.water_only and not stats.can_fly)
		if makes:
			options.append(recipe)
	return options


## Pays for and queues [param recipe]. Returns "" on success, or the reason it
## couldn't be queued.
func enqueue(recipe: UnitRecipe) -> String:
	if not is_complete:
		return "Still under construction"
	if queue.size() >= MAX_QUEUE:
		return "Queue is full"
	if not Research.can_produce(team, recipe):
		return "Requires research level %d" % recipe.stats.level
	if Net.is_client():
		var shortfall := Economy.shortfall(team, recipe.cost_coal, recipe.cost_electricity)
		if shortfall == "":
			Net.forward(self, &"enqueue", [recipe])
		return shortfall
	if not Economy.spend(team, recipe.cost_coal, recipe.cost_electricity):
		return Economy.shortfall(team, recipe.cost_coal, recipe.cost_electricity)
	queue.append(recipe)
	production_changed.emit(self)
	return ""


## Removes the last queued unit and refunds its cost.
func cancel_last() -> void:
	cancel_at(queue.size() - 1)


## Removes the queued unit at [param index] and refunds its cost. Cancelling
## the one in progress starts the next from scratch.
func cancel_at(index: int) -> void:
	if index < 0 or index >= queue.size() or Net.forward(self, &"cancel_at", [index]):
		return
	var recipe: UnitRecipe = queue.pop_at(index)
	Economy.add(team, recipe.cost_coal, recipe.cost_electricity)
	if index == 0:
		production_time = 0.0
		production_reserved = false
		population_blocked = false
	production_changed.emit(self)


## A finished building that can make units but is making, researching and
## upgrading nothing.
func is_idle() -> bool:
	return is_complete and is_alive() and queue.is_empty() and researching == 0 and upgrading == null \
			and not production_options().is_empty()


# --- Towers -------------------------------------------------------------------

func _update_tower(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	if _attack_timer > 0.0:
		return
	var target := find_tower_target()
	if target == null:
		return
	_attack_timer = data.attack_cooldown
	show_beam(target)
	target.take_damage(data.attack_damage, self, true)


## The nearest enemy creature in range (flyers included), or null.
func find_tower_target() -> Creature:
	var best: Creature = null
	var best_gap := data.attack_range
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not Teams.are_enemies(unit.team, team) or not unit.is_alive() or unit.is_hidden_from(team):
			continue
		var gap := edge_distance_from(unit.global_position) - unit.radius()
		if gap <= best_gap:
			best_gap = gap
			best = unit
	return best


## The tower's zap at [param target] (also played by online puppets).
func show_beam(target: Creature) -> void:
	if Net.sync:
		Net.sync.entity_event(self, &"beam", [target])
	var from := global_position + Vector3.UP * data.size.y * 0.9
	var to := target.global_position + Vector3.UP * target.center_height()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.18
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BEAM_COLOR
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = material
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(beam)
	beam.global_position = (from + to) / 2.0
	if not from.is_equal_approx(to):
		beam.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
		beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tween := beam.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(beam.queue_free)


# --- Upgrades -----------------------------------------------------------------

## Pays for and starts [param upgrade]. Returns "" or the reason it can't.
func start_upgrade(upgrade: UpgradeData) -> String:
	if not is_complete:
		return "Still under construction"
	if upgrading != null:
		return "Already upgrading"
	if Upgrades.has(team, upgrade.id) or _team_is_upgrading(upgrade.id):
		return "Already bought"
	if upgrade.requires != &"" and not Upgrades.has(team, upgrade.requires):
		return "Needs the previous tier first"
	if Research.level(team) < upgrade.required_research:
		return "Requires research level %d" % upgrade.required_research
	if Net.is_client():
		var shortfall := Economy.shortfall(team, upgrade.cost_coal, upgrade.cost_electricity)
		if shortfall == "":
			Net.forward(self, &"start_upgrade", [upgrade])
		return shortfall
	if not Economy.spend(team, upgrade.cost_coal, upgrade.cost_electricity):
		return Economy.shortfall(team, upgrade.cost_coal, upgrade.cost_electricity)
	upgrading = upgrade
	upgrade_time = 0.0
	production_changed.emit(self)
	return ""


func cancel_upgrade() -> void:
	if upgrading == null or Net.forward(self, &"cancel_upgrade"):
		return
	Economy.add(team, upgrading.cost_coal, upgrading.cost_electricity)
	upgrading = null
	upgrade_time = 0.0
	production_changed.emit(self)


func upgrade_fraction() -> float:
	return upgrade_time / upgrading.duration if upgrading != null else 0.0


func _team_is_upgrading(id: StringName) -> bool:
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.upgrading != null and building.upgrading.id == id:
			return true
	return false


func _heal_nearby(amount: float) -> void:
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team and edge_distance_from(unit.global_position) <= data.heal_radius:
			unit.heal(amount)


## Whether [param point] is close enough to be healed by this building.
func heals_at(point: Vector3) -> bool:
	return is_complete and data.heal_radius > 0.0 and edge_distance_from(point) <= data.heal_radius


## Pays for and starts researching the team's next level. Returns "" on
## success, or the reason it couldn't start.
func start_research() -> String:
	if not data.can_research:
		return "Can't research here"
	if not is_complete:
		return "Still under construction"
	if researching > 0 or _team_is_researching():
		return "Already researching"
	var target := Research.next_level(team)
	if target == 0:
		return "Fully researched"
	if Net.is_client():
		var shortfall := Economy.shortfall(team, Research.coal_cost(target), Research.electricity_cost(target))
		if shortfall == "":
			Net.forward(self, &"start_research")
		return shortfall
	if not Economy.spend(team, Research.coal_cost(target), Research.electricity_cost(target)):
		return Economy.shortfall(team, Research.coal_cost(target), Research.electricity_cost(target))
	researching = target
	research_time = 0.0
	production_changed.emit(self)
	return ""


func cancel_research() -> void:
	if researching == 0 or Net.forward(self, &"cancel_research"):
		return
	Economy.add(team, Research.coal_cost(researching), Research.electricity_cost(researching))
	researching = 0
	research_time = 0.0
	production_changed.emit(self)


func research_fraction() -> float:
	return research_time / Research.duration(researching) if researching > 0 else 0.0


func _team_is_researching() -> bool:
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team and building.researching > 0:
			return true
	return false


## Progress of the unit currently being produced, from 0 to 1.
func production_fraction() -> float:
	return production_time / queue[0].build_time if not queue.is_empty() else 0.0


## [param pile] makes new Henchmen gather there instead of just walking over.
func set_rally_point(point: Variant, pile: CoalPile = null) -> void:
	if Net.forward(self, &"set_rally_point", [point, pile]):
		return
	rally_point = point
	rally_pile = pile
	_update_rally_flag()


# --- Construction -------------------------------------------------------------

## Repairs heal this share of the building's health per build-time second
## (so a full repair takes 1 / REPAIR_RATE times its build time)...
const REPAIR_RATE := 0.5
## ...and cost this share of its coal price for a full repair.
const REPAIR_COST_SHARE := 0.3
## Share of the price refunded when an unfinished site is demolished.
const SITE_REFUND := 0.75


## True when it's finished but damaged.
func needs_repair() -> bool:
	return is_complete and not _dead and health < data.max_health


## True when Henchmen have something to do here: finish it or repair it.
func needs_work() -> bool:
	return not _dead and (not is_complete or needs_repair())


## Adds [param seconds] of repair work, paying coal as it goes. Returns false
## when the team can't pay for any more.
func add_repair_work(seconds: float) -> bool:
	if not needs_repair() or Economy.coal(team) < 1.0:
		return false
	var heal := minf(data.max_health * REPAIR_RATE * seconds / data.build_time, data.max_health - health)
	_repair_debt += heal * data.cost_coal * REPAIR_COST_SHARE / data.max_health
	var owed := floori(_repair_debt)
	if owed > 0:
		if not Economy.spend(team, owed, 0):
			return false
		_repair_debt -= owed
	health += heal
	return true


## Pulls the building down: an unfinished site refunds most of its price,
## a finished building just goes.
func demolish() -> void:
	if _dead or Net.forward(self, &"demolish"):
		return
	if not is_complete:
		Economy.add(team, int(data.cost_coal * SITE_REFUND), int(data.cost_electricity * SITE_REFUND))
	_die(false)


## Adds [param seconds] of Henchman work. Health grows along with progress.
func add_build_work(seconds: float) -> void:
	if is_complete or _dead:
		return
	var step := seconds / data.build_time
	build_progress = minf(build_progress + step, 1.0)
	health = minf(health + data.max_health * (1.0 - SITE_HEALTH_FRACTION) * step, data.max_health)
	if build_progress >= 1.0:
		_finish_construction(true)
	else:
		_update_construction_visual()


# --- Combat -------------------------------------------------------------------

func take_damage(amount: float, source: Node3D = null, _ranged := false) -> void:
	if _dead:
		return
	if Creature.is_valid_target(source):
		_last_attacker_team = source.team
	health = maxf(health - maxf(amount - data.armor, 1.0), 0.0)
	_flash()
	if health <= 0.0:
		_die()
		return
	if Creature.is_valid_target(source) and Teams.are_enemies(source.team, team):
		Alerts.report(team, global_position, "Your %s is under attack!" % data.display_name)
		for unit: Creature in get_tree().get_nodes_in_group("units"):
			if Teams.are_allies(unit.team, team) and edge_distance_from(unit.global_position) <= DEFEND_RADIUS:
				unit.respond_to_attack(source)


## A copy of this building's model for the HUD portrait, at the origin.
func portrait_visual() -> Node3D:
	var copy := model.duplicate() as BuildingModel
	copy.scale = Vector3.ONE
	return copy


func is_alive() -> bool:
	return not _dead


func get_max_health() -> float:
	return data.max_health


func get_armor() -> float:
	return data.armor


func vision_range() -> float:
	if not is_complete:
		return radius() + 4.0
	# Labs see far enough to show their own coal fields.
	return radius() + (17.0 if data.is_drop_off else 8.0)


## Distance from [param point] to the nearest edge of the footprint.
func edge_distance_from(point: Vector3) -> float:
	var offset := point - global_position
	var dx := maxf(absf(offset.x) - data.size.x / 2.0, 0.0)
	var dz := maxf(absf(offset.z) - data.size.z / 2.0, 0.0)
	return Vector2(dx, dz).length()


func radius() -> float:
	return maxf(data.size.x, data.size.z) / 2.0


func center_height() -> float:
	return data.size.y / 2.0


func bar_height() -> float:
	return data.size.y + 0.8


## Re-applies the team colour (after the match decides who's allied with whom).
func refresh_team_color() -> void:
	model.set_team_color(Teams.color(team))


func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value
	_update_rally_flag()


# --- Internals ----------------------------------------------------------------

func _finish_construction(notify: bool) -> void:
	is_complete = true
	build_progress = 1.0
	_update_construction_visual()
	if notify:
		MatchStats.add(team, "buildings_built")
		if team == Sfx.player_team:
			Sfx.play("building_done")
		completed.emit(self)


func _spawn(recipe: UnitRecipe) -> void:
	var unit: Creature = recipe.scene.instantiate()
	unit.stats = recipe.stats
	unit.team = team
	# Exit on the side facing the rally point, or the map centre by default.
	var toward: Vector3 = rally_point if rally_point != null else Vector3.ZERO
	var direction := toward - global_position
	direction.y = 0.0
	if direction.length() < 0.1:
		direction = Vector3.BACK
	direction = direction.normalized()
	var reach := absf(direction.x) * data.size.x / 2.0 + absf(direction.z) * data.size.z / 2.0
	var container := get_tree().get_first_node_in_group("unit_container")
	if container == null:
		container = get_tree().current_scene
	unit.position = global_position + direction * (reach + SPAWN_GAP)
	# Swimmers from the Water Chamber come out into the water.
	if data.water_production and recipe.stats.can_swim:
		unit.position = WaterArea.nearest_water_spot(get_tree(), global_position)
	container.add_child(unit)
	if not recipe.is_worker:
		MatchStats.add(team, "units_produced")
	if unit is Henchman and is_instance_valid(rally_pile) and not rally_pile.is_depleted():
		unit.command_gather(rally_pile)
	elif rally_point != null:
		unit.command_move(rally_point)


## [param destroyed]: knocked down by an enemy (counts in the stats, may leave
## a ghost); false when demolished by its owner.
func _die(destroyed := true) -> void:
	if Net.sync:
		Net.sync.entity_died(self, destroyed)
	_dead = true
	remove_from_group("buildings")
	remove_from_group("targets")
	set_physics_process(false)
	collision_layer = 0
	set_selected(false)
	if Net.is_client():
		# The host does the refunds.
		queue.clear()
		researching = 0
		upgrading = null
	# Refund anything still queued, like most RTS games do.
	while not queue.is_empty():
		cancel_last()
	cancel_research()
	cancel_upgrade()
	Sfx.play_at("death", global_position, 0.55)
	if destroyed:
		MatchStats.record_building_lost(team, _last_attacker_team)
		get_tree().call_group("building_watchers", "building_destroyed", self)
	died.emit(self)
	get_tree().call_group("navmesh", "request_rebake")
	var tween := create_tween()
	tween.tween_property(self, "position:y", -data.size.y - 0.5, 1.5)
	tween.tween_callback(queue_free)


## Online puppets: the host says this building came down.
func die_from_network(destroyed: bool) -> void:
	_die(destroyed)


# --- Online -------------------------------------------------------------------

const NET_COMPLETE := 1
const NET_RESERVED := 2
const NET_BLOCKED := 4


## What the joining player's copy needs (sent when it changes). The queue
## travels as places in production_options(), which match on both machines
## because both have every player's roster.
func net_state() -> Array:
	var options := production_options()
	var queued := []
	for recipe in queue:
		queued.append(options.find(recipe))
	var flags := (NET_COMPLETE if is_complete else 0) | (NET_RESERVED if production_reserved else 0) \
			| (NET_BLOCKED if population_blocked else 0)
	return [snappedf(health, 0.1), flags, snappedf(build_progress, 0.001), queued, snappedf(production_time, 0.05),
			researching, snappedf(research_time, 0.05), upgrading.resource_path if upgrading else "",
			snappedf(upgrade_time, 0.05), rally_point, Net.sync.id_of(rally_pile)]


func apply_net_state(state: Array) -> void:
	if _dead:
		return
	var new_health: float = state[0]
	if new_health < health - 0.05:
		_flash()
	health = new_health
	var flags: int = state[1]
	production_reserved = flags & NET_RESERVED != 0
	population_blocked = flags & NET_BLOCKED != 0
	if not is_equal_approx(build_progress, state[2]) and not is_complete:
		build_progress = state[2]
		_update_construction_visual()
	if flags & NET_COMPLETE and not is_complete:
		_finish_construction(true)
	var options := production_options()
	var new_queue: Array[UnitRecipe] = []
	for index: int in state[3]:
		if index >= 0 and index < options.size():
			new_queue.append(options[index])
	var path: String = state[7]
	var new_upgrade: UpgradeData = load(path) as UpgradeData if path.begins_with(NetSync.UPGRADE_DIR) and ResourceLoader.exists(path) else null
	var changed: bool = new_queue != queue or researching != state[5] or upgrading != new_upgrade
	queue = new_queue
	production_time = state[4]
	researching = state[5]
	research_time = state[6]
	upgrading = new_upgrade
	upgrade_time = state[8]
	rally_point = state[9]
	rally_pile = Net.sync.node_of(state[10]) as CoalPile if state[10] != 0 else null
	_update_rally_flag()
	if changed:
		production_changed.emit(self)


func _build_visuals() -> void:
	var shape := BoxShape3D.new()
	shape.size = data.size
	collision.shape = shape
	collision.position.y = data.size.y / 2.0

	model.build(data, Teams.color(team))

	var ring_scale := radius() * 1.25 / 0.8
	selection_ring.scale = Vector3(ring_scale, 1.0, ring_scale)


func _update_construction_visual() -> void:
	# Sites rise out of the ground as they are built.
	var height_scale := lerpf(0.15, 1.0, build_progress)
	model.scale = Vector3(1.0, height_scale, 1.0)
	model.set_unfinished(not is_complete)


func _update_rally_flag() -> void:
	if rally_flag == null:
		return
	rally_flag.visible = is_selected and rally_point != null
	if rally_point != null:
		rally_flag.global_position = rally_point


func _flash() -> void:
	model.flash()
