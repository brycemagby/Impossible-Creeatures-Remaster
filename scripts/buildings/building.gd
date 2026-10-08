class_name Building
extends StaticBody3D
## A team-owned structure: constructed by Henchmen, produces units, can be
## attacked and destroyed.
##
## Uses placeholder box art sized and coloured from its [BuildingData].

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

var health := 0.0
var is_complete := false
## Construction progress from 0 to 1.
var build_progress := 0.0
var queue: Array[UnitRecipe] = []
## Seconds spent on the unit at the front of the queue.
var production_time := 0.0
## Research level being studied here, or 0.
var researching := 0
var research_time := 0.0
var rally_point: Variant = null
var is_selected := false

var _dead := false
var _body_material: StandardMaterial3D
var _last_attacker_team := -1
var _heal_timer := 0.0
var _attack_timer := 0.0
## Workshop: the upgrade being bought, and progress in seconds.
var upgrading: UpgradeData = null
var upgrade_time := 0.0

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var body: MeshInstance3D = $Body
@onready var team_band: MeshInstance3D = $TeamBand
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


func _physics_process(delta: float) -> void:
	if not is_complete:
		return
	if data.electricity_per_second > 0.0:
		Economy.add(team, 0.0, data.electricity_per_second * delta)
	if data.attack_damage > 0.0:
		_update_tower(delta)
	if upgrading != null:
		upgrade_time += delta
		if upgrade_time >= upgrading.duration:
			Upgrades.grant(team, upgrading.id)
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
			researching = 0
			research_time = 0.0
			production_changed.emit(self)
	if not queue.is_empty():
		production_time += delta
		if production_time >= queue[0].build_time:
			production_time = 0.0
			_spawn(queue.pop_front())
			production_changed.emit(self)


# --- Production ---------------------------------------------------------------

## What this building can make right now.
func production_options() -> Array[UnitRecipe]:
	return Armies.recipes(team) if data.produces_army else data.production


## Pays for and queues [param recipe]. Returns "" on success, or the reason it
## couldn't be queued.
func enqueue(recipe: UnitRecipe) -> String:
	if not is_complete:
		return "Still under construction"
	if queue.size() >= MAX_QUEUE:
		return "Queue is full"
	if not Research.can_produce(team, recipe):
		return "Requires research level %d" % recipe.stats.level
	if not Economy.spend(team, recipe.cost_coal, recipe.cost_electricity):
		return Economy.shortfall(team, recipe.cost_coal, recipe.cost_electricity)
	queue.append(recipe)
	production_changed.emit(self)
	return ""


## Removes the last queued unit and refunds its cost.
func cancel_last() -> void:
	if queue.is_empty():
		return
	var recipe: UnitRecipe = queue.pop_back()
	Economy.add(team, recipe.cost_coal, recipe.cost_electricity)
	if queue.is_empty():
		production_time = 0.0
	production_changed.emit(self)


# --- Towers -------------------------------------------------------------------

func _update_tower(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	if _attack_timer > 0.0:
		return
	var target := find_tower_target()
	if target == null:
		return
	_attack_timer = data.attack_cooldown
	_fire_beam(target)
	target.take_damage(data.attack_damage, self)


## The nearest enemy creature in range (flyers included), or null.
func find_tower_target() -> Creature:
	var best: Creature = null
	var best_gap := data.attack_range
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not Teams.are_enemies(unit.team, team) or not unit.is_alive():
			continue
		var gap := edge_distance_from(unit.global_position) - unit.radius()
		if gap <= best_gap:
			best_gap = gap
			best = unit
	return best


func _fire_beam(target: Creature) -> void:
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
	if Research.level(team) < upgrade.required_research:
		return "Requires research level %d" % upgrade.required_research
	if not Economy.spend(team, upgrade.cost_coal, upgrade.cost_electricity):
		return Economy.shortfall(team, upgrade.cost_coal, upgrade.cost_electricity)
	upgrading = upgrade
	upgrade_time = 0.0
	production_changed.emit(self)
	return ""


func cancel_upgrade() -> void:
	if upgrading == null:
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
	if not Economy.spend(team, Research.coal_cost(target), Research.electricity_cost(target)):
		return Economy.shortfall(team, Research.coal_cost(target), Research.electricity_cost(target))
	researching = target
	research_time = 0.0
	production_changed.emit(self)
	return ""


func cancel_research() -> void:
	if researching == 0:
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


func set_rally_point(point: Variant) -> void:
	rally_point = point
	_update_rally_flag()


# --- Construction -------------------------------------------------------------

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

func take_damage(amount: float, source: Node3D = null) -> void:
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
		for unit: Creature in get_tree().get_nodes_in_group("units"):
			if Teams.are_allies(unit.team, team) and edge_distance_from(unit.global_position) <= DEFEND_RADIUS:
				unit.respond_to_attack(source)


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
	(team_band.material_override as StandardMaterial3D).albedo_color = Teams.color(team)


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
	container.add_child(unit)
	if not recipe.is_worker:
		MatchStats.add(team, "units_produced")
	if rally_point != null:
		unit.command_move(rally_point)


func _die() -> void:
	_dead = true
	remove_from_group("buildings")
	remove_from_group("targets")
	set_physics_process(false)
	collision_layer = 0
	set_selected(false)
	# Refund anything still queued, like most RTS games do.
	while not queue.is_empty():
		cancel_last()
	cancel_research()
	cancel_upgrade()
	MatchStats.record_building_lost(team, _last_attacker_team)
	get_tree().call_group("building_watchers", "building_destroyed", self)
	died.emit(self)
	get_tree().call_group("navmesh", "request_rebake")
	var tween := create_tween()
	tween.tween_property(self, "position:y", -data.size.y - 0.5, 1.5)
	tween.tween_callback(queue_free)


func _build_visuals() -> void:
	var shape := BoxShape3D.new()
	shape.size = data.size
	collision.shape = shape
	collision.position.y = data.size.y / 2.0

	var box := BoxMesh.new()
	box.size = data.size
	body.mesh = box
	body.position.y = data.size.y / 2.0
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = data.color
	_body_material.roughness = 0.85
	body.material_override = _body_material

	var band := BoxMesh.new()
	band.size = Vector3(data.size.x + 0.1, 0.35, data.size.z + 0.1)
	team_band.mesh = band
	team_band.position.y = data.size.y - 0.3
	var band_material := StandardMaterial3D.new()
	band_material.albedo_color = Teams.color(team)
	team_band.material_override = band_material

	var ring_scale := radius() * 1.25 / 0.8
	selection_ring.scale = Vector3(ring_scale, 1.0, ring_scale)


func _update_construction_visual() -> void:
	# Sites rise out of the ground as they are built.
	var height_scale := lerpf(0.15, 1.0, build_progress)
	body.scale = Vector3(1.0, height_scale, 1.0)
	body.position.y = data.size.y * height_scale / 2.0
	team_band.visible = is_complete
	_body_material.albedo_color = data.color if is_complete else data.color.lerp(Color(0.55, 0.45, 0.25), 0.6)


func _update_rally_flag() -> void:
	if rally_flag == null:
		return
	rally_flag.visible = is_selected and rally_point != null
	if rally_point != null:
		rally_flag.global_position = rally_point


func _flash() -> void:
	var tween := create_tween()
	var base := _body_material.albedo_color
	_body_material.albedo_color = Color.WHITE
	tween.tween_property(_body_material, "albedo_color", base, 0.12)
