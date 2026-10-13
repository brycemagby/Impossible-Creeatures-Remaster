class_name TerrainDecor
extends Node3D
## Scatters grass tufts, pebbles and the odd flower over a map so the ground
## doesn't look like a bare plane. Purely visual: nothing collides with it.
## Keeps clear of water, rocks, coal and the starting bases, and lays out the
## same way every time a map loads.
##
## Real art: assets/terrain/grass, pebble or flower (.tscn or .glb, a single
## MeshInstance3D at the root) replace the placeholder meshes.

const DecorShader := preload("res://shaders/terrain_decor.gdshader")
const TUFTS := 3200
const PEBBLES := 260
const FLOWERS := 160
## Starting bases stay clear for this far around the Lab.
const BASE_CLEARANCE := 9.0
const FLOWER_COLORS := [Color(0.95, 0.85, 0.3), Color(0.92, 0.45, 0.35), Color(0.85, 0.82, 0.95), Color(0.7, 0.45, 0.85)]

## Area to cover (world x, z, width, depth).
@export var area := Rect2(-50, -50, 100, 100)
## Base grass colour; tufts vary around it.
@export var grass_color := Color(0.3, 0.42, 0.2)

## Where each kind of clutter was put (kind -> positions).
var placed := {}
var _blocked: Array[Vector3] = []


func _ready() -> void:
	_collect_obstacles()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(get_parent().scene_file_path if get_parent() else "map")
	_scatter("grass", _tuft_mesh(), TUFTS, rng, 0.06,
			func(r: RandomNumberGenerator) -> Color:
				var shade := r.randf_range(0.75, 1.15)
				return Color(grass_color.r * shade * r.randf_range(0.95, 1.2), grass_color.g * shade, grass_color.b * shade * 0.8),
			Vector2(0.9, 1.7))
	_scatter("pebble", TerrainProps.lump(3), PEBBLES, rng, 0.0,
			func(r: RandomNumberGenerator) -> Color: return Color(0.34, 0.32, 0.29).darkened(r.randf_range(0.0, 0.3)),
			Vector2(0.12, 0.35))
	_scatter("flower", _flower_mesh(), FLOWERS, rng, 0.04,
			func(r: RandomNumberGenerator) -> Color: return FLOWER_COLORS[r.randi() % FLOWER_COLORS.size()],
			Vector2(0.8, 1.2))
	# Pick up the fog texture now that these surfaces exist.
	get_tree().call_group("fog", "refresh_surfaces")


func _collect_obstacles() -> void:
	for node: Node3D in get_tree().get_nodes_in_group("fog_hidden"):
		# Rocks and coal piles.
		_blocked.append(Vector3(node.global_position.x, 0.0, node.global_position.z) + Vector3.UP * 2.2)
	for node: Node3D in get_tree().get_nodes_in_group("start_locations"):
		_blocked.append(Vector3(node.global_position.x, 0.0, node.global_position.z) + Vector3.UP * BASE_CLEARANCE)


func _is_clear(point: Vector3) -> bool:
	for blocker in _blocked:
		if Vector2(point.x - blocker.x, point.z - blocker.z).length() < blocker.y:
			return false
	for water: WaterArea in get_tree().get_nodes_in_group("water_areas"):
		if _near_water(water, point):
			return false
	return true


func _near_water(water: WaterArea, point: Vector3) -> bool:
	# Keep a little bank of bare ground along the shore.
	for offset in [Vector3.ZERO, Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0), Vector3(0, 0, 0.8), Vector3(0, 0, -0.8)]:
		if water.contains(point + offset):
			return true
	return false


func _scatter(kind: String, fallback: Mesh, count: int, rng: RandomNumberGenerator, sway: float,
		tint: Callable, scale_range: Vector2) -> void:
	var mesh := fallback
	var art := TerrainProps.art(kind)
	if art != null:
		var instance := art.instantiate()
		if instance is MeshInstance3D and (instance as MeshInstance3D).mesh != null:
			mesh = (instance as MeshInstance3D).mesh
		instance.free()
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var attempts := 0
	while transforms.size() < count and attempts < count * 4:
		attempts += 1
		var point := Vector3(rng.randf_range(area.position.x, area.end.x), 0.0, rng.randf_range(area.position.y, area.end.y))
		var size := rng.randf_range(scale_range.x, scale_range.y)
		var color: Color = tint.call(rng)
		var spin := rng.randf() * TAU
		if not _is_clear(point):
			continue
		var basis := Basis(Vector3.UP, spin).scaled(Vector3.ONE * size)
		transforms.append(Transform3D(basis, point))
		colors.append(color)
	var spots := PackedVector3Array()
	for t in transforms:
		spots.append(t.origin)
	placed[kind] = spots
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])
	var material := ShaderMaterial.new()
	material.shader = DecorShader
	material.set_shader_parameter("sway", sway)
	material.set_shader_parameter("ground_lit", kind != "pebble")
	var instance := MultiMeshInstance3D.new()
	instance.name = kind.capitalize()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.add_to_group("fog_surfaces")
	add_child(instance)


## Three crossed blades: a little tuft of grass about 0.35 m tall.
static func _tuft_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for blade in 5:
		var angle := blade * TAU / 5.0
		var lean := Vector3(cos(angle), 0, sin(angle))
		var side := lean.cross(Vector3.UP) * 0.045
		var base := lean * 0.04
		var tip := lean * 0.14 + Vector3.UP * (0.3 + 0.06 * (blade % 2))
		tool.add_vertex(base - side)
		tool.add_vertex(base + side)
		tool.add_vertex(tip)
	return tool.commit()


## A stalk with a round bloom on top.
static func _flower_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var bloom := Vector3.UP * 0.28
	var petals := 6
	for i in petals:
		var a := i * TAU / petals
		var b := (i + 1) * TAU / petals
		tool.add_vertex(bloom)
		tool.add_vertex(bloom + Vector3(cos(a), 0.02, sin(a)) * 0.08)
		tool.add_vertex(bloom + Vector3(cos(b), 0.02, sin(b)) * 0.08)
	tool.add_vertex(Vector3(-0.012, 0, 0))
	tool.add_vertex(Vector3(0.012, 0, 0))
	tool.add_vertex(bloom)
	return tool.commit()
