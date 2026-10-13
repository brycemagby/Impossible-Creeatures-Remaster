extends StaticBody3D
## A rock outcrop: a big faceted boulder with a few smaller ones around it,
## sometimes with a cap of moss. The layout is picked from the rock's
## position, so a map always looks the same. Collision stays the simple
## cylinder from the scene.

const GREYS := [Color(0.3, 0.28, 0.26), Color(0.34, 0.31, 0.27), Color(0.28, 0.28, 0.29)]
const MOSS := Color(0.2, 0.3, 0.12)


func _ready() -> void:
	var art := TerrainProps.art("rock")
	if art != null:
		add_child(art.instantiate())
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)))
	var grey: Color = GREYS[rng.randi() % GREYS.size()]
	var stone := TerrainProps.material(grey)
	var dark := TerrainProps.material(grey.darkened(0.15))
	# The main boulder fills the collision cylinder (radius 1.6, 2.5 tall).
	var main := _boulder(rng, stone, Vector3(0, 0.45, 0), Vector3(2.8, 2.6, 2.6))
	if rng.randf() < 0.6:
		var moss := MeshInstance3D.new()
		moss.mesh = TerrainProps.lump(rng.randi())
		moss.material_override = TerrainProps.material(MOSS)
		moss.position = Vector3(rng.randf_range(-0.12, 0.12), 0.4, rng.randf_range(-0.12, 0.12))
		moss.scale = Vector3(0.5, 0.16, 0.5)
		main.add_child(moss)
	for i in rng.randi_range(2, 4):
		var angle := rng.randf() * TAU
		var size := rng.randf_range(0.55, 0.95)
		var spot := Vector3(cos(angle), 0, sin(angle)) * rng.randf_range(1.0, 1.3)
		_boulder(rng, dark if i % 2 == 0 else stone, spot + Vector3.UP * size * 0.2, Vector3(size, size * 0.8, size))


func _boulder(rng: RandomNumberGenerator, stone: Material, at: Vector3, size: Vector3) -> MeshInstance3D:
	var boulder := MeshInstance3D.new()
	boulder.mesh = TerrainProps.lump(rng.randi())
	boulder.material_override = stone
	boulder.position = at
	boulder.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
	boulder.scale = size
	add_child(boulder)
	return boulder
