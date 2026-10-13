class_name TerrainProps
## Shared pieces for the placeholder terrain art: faceted low-poly lumps
## (boulders, coal, pebbles) and drop-in art lookups.
##
## Real art replaces a prop without code changes: put a scene at
## ART_DIR/<name>.tscn (or .glb): rock, coal_pile, grass, pebble or flower.

const ART_DIR := "res://assets/terrain/"
const LUMP_VARIANTS := 6

static var _lumps: Array[ArrayMesh] = []


## A rough, flat-shaded lump about one metre across (radius 0.5), one of a
## few cached shapes picked by [param variant].
static func lump(variant: int) -> ArrayMesh:
	if _lumps.is_empty():
		for i in LUMP_VARIANTS:
			_lumps.append(_make_lump(i))
	return _lumps[posmod(variant, LUMP_VARIANTS)]


## The drop-in art scene for [param name], or null.
static func art(name: String) -> PackedScene:
	for extension in [".tscn", ".glb", ".gltf"]:
		var path: String = ART_DIR + name + extension
		if ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


## A material for terrain props; [param shine] gives coal its glassy facets.
static func material(color: Color, shine := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.35 if shine else 0.95
	result.metallic = 0.35 if shine else 0.0
	return result


static func _make_lump(seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 4
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137 + seed_value * 101
	# Push each corner in or out by its own amount; corners that share a
	# position (the seam) must move together, so key the jitter by position.
	var jitter := {}
	for i in vertices.size():
		var key := Vector3i((vertices[i] * 1000.0).round())
		if not jitter.has(key):
			jitter[key] = rng.randf_range(0.78, 1.12)
		vertices[i] *= jitter[key]
		# Flatten the underside so lumps sit on the ground.
		if vertices[i].y < -0.2:
			vertices[i].y = -0.2
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	arrays[Mesh.ARRAY_TEX_UV] = null
	var smooth := ArrayMesh.new()
	smooth.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(smooth, 0)
	tool.deindex()
	tool.generate_normals()
	return tool.commit()
