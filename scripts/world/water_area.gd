class_name WaterArea
extends Node3D
## A patch of water, given as a convex polygon on the ground plane (x, z).
##
## Deep water is carved out of the land navigation mesh, so walkers path
## around it, and gets a navigation region of its own on WATER_LAYER for
## swimmers. Shallow water (a ford) is only a look: everyone can wade it.
## Must sit under the land NavigationRegion3D so its carving is baked in.

## Navigation layers: walkers use LAND_LAYER, swimmers WATER_LAYER, amphibians both.
const LAND_LAYER := 1
const WATER_LAYER := 2
const DEEP_COLOR := Color(0.1, 0.26, 0.48)
const SHALLOW_COLOR := Color(0.3, 0.48, 0.52)
const SURFACE_HEIGHT := 0.03
## Height the baked land navigation mesh ends up at (the bake floats it half a
## metre above the ground); the water mesh matches it so the two join up.
const NAV_HEIGHT := 0.5
## Walkers keep this far back from the water's edge (the land mesh is carved
## wider than the water), so they don't stand half in it.
const SHORE_GAP := 0.5
## How far apart land and water mesh edges may be and still join; covers the gap.
const EDGE_CONNECTION_MARGIN := 0.8
const FogShader := preload("res://shaders/fog_ground.gdshader")

## Convex outline, in order, on the ground plane (x, z).
@export var polygon := PackedVector2Array()
## A ford: looks like water but anyone can walk through.
@export var shallow := false

var _surface: MeshInstance3D


func _ready() -> void:
	# One winding for every outline, whichever way it was written: the water
	# navigation mesh only joins the land mesh with this one.
	if _signed_area(polygon) < 0.0:
		polygon.reverse()
	add_to_group("water_areas")
	if not shallow:
		add_to_group("deep_water")
	_build_surface()
	if not shallow:
		_build_carving()
		_build_water_navigation()


## Whether [param point] (x, z) is inside this area.
func contains(point: Vector3) -> bool:
	return Geometry2D.is_point_in_polygon(Vector2(point.x, point.z) - _origin(), polygon)


## Whether the ground rectangle [param rect] (x, z) touches this area.
func overlaps(rect: Rect2) -> bool:
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for i in corners.size():
		corners[i] -= _origin()
	return not Geometry2D.intersect_polygons(corners, polygon).is_empty()


## The outline in world coordinates (x, z).
func world_polygon() -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in polygon:
		result.append(point + _origin())
	return result


## Whether [param point] is in deep water (where only swimmers go), at least
## [param margin] metres from the shore.
static func is_deep_water(tree: SceneTree, point: Vector3, margin := 0.0) -> bool:
	for area: WaterArea in tree.get_nodes_in_group("deep_water"):
		if area.contains(point) and (margin <= 0.0 or area._distance_to_edge(point) > margin):
			return true
	return false


## Whether the ground rectangle [param rect] touches any water, deep or shallow.
static func touches_water(tree: SceneTree, rect: Rect2) -> bool:
	for area: WaterArea in tree.get_nodes_in_group("water_areas"):
		if area.overlaps(rect):
			return true
	return false


## Distance from [param point] to the nearest deep water edge (INF without water).
static func distance_to_deep_water(tree: SceneTree, point: Vector3) -> float:
	var best := INF
	var flat := Vector2(point.x, point.z)
	for area: WaterArea in tree.get_nodes_in_group("deep_water"):
		var outline := area.world_polygon()
		if Geometry2D.is_point_in_polygon(flat, outline):
			return 0.0
		for i in outline.size():
			var closest := Geometry2D.get_closest_point_to_segment(flat, outline[i], outline[(i + 1) % outline.size()])
			best = minf(best, closest.distance_to(flat))
	return best


## Positive when the (x, z) outline runs anticlockwise with x right and z up.
static func _signed_area(outline: PackedVector2Array) -> float:
	var area := 0.0
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		area += a.x * b.y - b.x * a.y
	return area / 2.0


func _distance_to_edge(point: Vector3) -> float:
	var flat := Vector2(point.x, point.z)
	var outline := world_polygon()
	var best := INF
	for i in outline.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(flat, outline[i], outline[(i + 1) % outline.size()]).distance_to(flat))
	return best


func _origin() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func _build_surface() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	# A fan over the convex outline, wound to face up.
	for i in range(1, polygon.size() - 1):
		for point in [polygon[0], polygon[i], polygon[i + 1]]:
			tool.add_vertex(Vector3(point.x, 0.0, point.y))
	var material := ShaderMaterial.new()
	material.shader = FogShader
	material.set_shader_parameter("albedo", SHALLOW_COLOR if shallow else DEEP_COLOR)
	_surface = MeshInstance3D.new()
	_surface.mesh = tool.commit()
	_surface.material_override = material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fords sit just above deep water where they meet.
	_surface.position.y = SURFACE_HEIGHT + (0.005 if shallow else 0.0)
	_surface.add_to_group("fog_surfaces")
	add_child(_surface)


## An obstacle that cuts this area out of the baked land navigation mesh.
func _build_carving() -> void:
	var obstacle := NavigationObstacle3D.new()
	var vertices := PackedVector3Array()
	var grown := Geometry2D.offset_polygon(polygon, SHORE_GAP, Geometry2D.JOIN_MITER)
	for point in grown[0] if not grown.is_empty() else polygon:
		vertices.append(Vector3(point.x, 0.0, point.y))
	obstacle.vertices = vertices
	obstacle.height = 2.0
	obstacle.position.y = -0.5
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	# Only for carving: as an avoidance obstacle it would wall off the shore
	# (and fords) for everyone.
	obstacle.avoidance_enabled = false
	obstacle.avoidance_layers = 0
	add_child(obstacle)


## A navigation region over the water for swimmers.
func _build_water_navigation() -> void:
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in polygon.size():
		vertices.append(Vector3(polygon[i].x, NAV_HEIGHT, polygon[i].y))
		indices.append(i)
	mesh.vertices = vertices
	mesh.add_polygon(indices)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	region.navigation_layers = WATER_LAYER
	add_child(region)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_edge_connection_margin(map, maxf(NavigationServer3D.map_get_edge_connection_margin(map), EDGE_CONNECTION_MARGIN))
