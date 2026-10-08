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
var rally_point: Variant = null
var is_selected := false

var _dead := false
var _body_material: StandardMaterial3D

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

func take_damage(amount: float, source: Creature = null) -> void:
	if _dead:
		return
	health = maxf(health - maxf(amount - data.armor, 1.0), 0.0)
	_flash()
	if health <= 0.0:
		_die()
		return
	if Creature.is_valid_target(source) and source.team != team:
		for unit: Creature in get_tree().get_nodes_in_group("units"):
			if unit.team == team and edge_distance_from(unit.global_position) <= DEFEND_RADIUS:
				unit.respond_to_attack(source)


func is_alive() -> bool:
	return not _dead


func get_max_health() -> float:
	return data.max_health


func get_armor() -> float:
	return data.armor


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
	band_material.albedo_color = Creature.TEAM_COLORS[team % Creature.TEAM_COLORS.size()]
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
