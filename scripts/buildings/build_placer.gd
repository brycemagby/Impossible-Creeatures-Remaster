class_name BuildPlacer
extends Node3D
## Building placement: shows a ghost that follows the cursor, turns red where
## the building won't fit, and creates the construction site.

const BuildingScene := preload("res://scenes/buildings/building.tscn")
## world, units, buildings and resources all block placement.
const BLOCKING_MASK := 1 | 2 | 4 | 8
## Gap kept around buildings so units can still walk between them.
const CLEARANCE := 0.75
const GRID := 1.0
## A shore building's footprint must come this close to deep water.
const SHORE_DISTANCE := 3.0
const VALID_COLOR := Color(0.3, 1.0, 0.4, 0.4)
const INVALID_COLOR := Color(1.0, 0.25, 0.2, 0.4)

## Area (world XZ) the whole footprint must fit inside.
@export var bounds := Rect2(-48, -48, 96, 96)

var data: BuildingData = null
var team := 0
## Why the last place() call failed.
var last_error := ""

var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D


func is_active() -> bool:
	return data != null


func start(building_data: BuildingData, placing_team: int) -> void:
	cancel()
	data = building_data
	team = placing_team
	var mesh := BoxMesh.new()
	mesh.size = data.size
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost = MeshInstance3D.new()
	_ghost.mesh = mesh
	_ghost.material_override = _ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func cancel() -> void:
	data = null
	if _ghost:
		_ghost.queue_free()
		_ghost = null


## Moves the ghost to [param world_point] (null hides it).
func update_ghost(world_point: Variant) -> void:
	if _ghost == null:
		return
	_ghost.visible = world_point != null
	if world_point == null:
		return
	var spot := snap(world_point)
	_ghost.global_position = spot + Vector3.UP * data.size.y / 2.0
	_ghost_material.albedo_color = VALID_COLOR if can_place_at(spot) else INVALID_COLOR


func snap(point: Vector3) -> Vector3:
	return Vector3(snappedf(point.x, GRID), 0.0, snappedf(point.z, GRID))


func can_place_at(spot: Vector3) -> bool:
	var footprint := Rect2(spot.x - data.size.x / 2.0, spot.z - data.size.z / 2.0, data.size.x, data.size.z)
	if not bounds.encloses(footprint):
		return false
	if WaterArea.touches_water(get_tree(), footprint.grow(CLEARANCE)):
		return false
	if data.needs_shore and not is_on_shore(spot):
		return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(data.size.x + CLEARANCE * 2.0, data.size.y, data.size.z + CLEARANCE * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Lift the box slightly so it doesn't touch the ground collider.
	query.transform = Transform3D(Basis(), spot + Vector3.UP * (data.size.y / 2.0 + 0.1))
	query.collision_mask = BLOCKING_MASK
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Whether a building centred on [param spot] is close enough to deep water.
func is_on_shore(spot: Vector3) -> bool:
	var half := maxf(data.size.x, data.size.z) / 2.0
	return WaterArea.distance_to_deep_water(get_tree(), spot) <= half + CLEARANCE + SHORE_DISTANCE


## Pays for and creates a construction site at [param world_point]. Returns
## the new building, or null (see [member last_error]).
func place(world_point: Vector3) -> Building:
	var spot := snap(world_point)
	if Research.level(team) < data.required_research:
		last_error = "Requires research level %d" % data.required_research
		return null
	if not can_place_at(spot):
		last_error = "Must be built on a shore" if data.needs_shore and not is_on_shore(spot) else "Can't build there"
		return null
	if not Economy.spend(team, data.cost_coal, data.cost_electricity):
		last_error = Economy.shortfall(team, data.cost_coal, data.cost_electricity)
		return null
	var building: Building = BuildingScene.instantiate()
	building.data = data
	building.team = team
	building.start_complete = false
	building.position = spot
	# Buildings must sit under the navigation region so rebakes include them.
	var container := get_tree().get_first_node_in_group("building_container")
	if container == null:
		container = get_tree().current_scene
	container.add_child(building)
	get_tree().call_group("navmesh", "request_rebake")
	last_error = ""
	return building
