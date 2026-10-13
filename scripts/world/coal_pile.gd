class_name CoalPile
extends StaticBody3D
## A finite coal deposit that Henchmen gather from. It shrinks as it is mined
## and disappears when empty.
##
## Drawn as a mound of glossy faceted lumps (laid out from its position, so a
## map always looks the same), or by drop-in art at
## res://assets/terrain/coal_pile.tscn.

const RADIUS := 1.2
const COAL := Color(0.09, 0.09, 0.1)
const LUMPS := 16

@export var amount := 2500

var _starting_amount := 0

## Holds the pile's look; scaled down as it is mined.
@onready var mesh: Node3D = $Mesh


func _ready() -> void:
	add_to_group("coal_piles")
	add_to_group("fog_hidden")
	_starting_amount = maxi(amount, 1)
	_build_pile()


## Removes up to [param requested] coal and returns how much was taken.
func take(requested: int) -> int:
	var taken := mini(requested, amount)
	amount -= taken
	mesh.scale = Vector3.ONE * lerpf(0.4, 1.0, float(amount) / _starting_amount)
	if amount <= 0:
		_deplete()
	return taken


func is_depleted() -> bool:
	return amount <= 0


func edge_distance_from(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() - RADIUS


func _deplete() -> void:
	remove_from_group("coal_piles")
	collision_layer = 0
	get_tree().call_group("navmesh", "request_rebake")
	queue_free()


func _build_pile() -> void:
	var art := TerrainProps.art("coal_pile")
	if art != null:
		mesh.add_child(art.instantiate())
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(global_position.x * 10.0), roundi(global_position.z * 10.0))) + 7
	var glossy := TerrainProps.material(COAL, true)
	var matte := TerrainProps.material(COAL.lightened(0.06))
	for i in LUMPS:
		# A mound: big lumps low in the middle, smaller ones out and on top.
		var ring := sqrt(float(i) / LUMPS)
		var angle := i * 2.4 + rng.randf() * 0.5
		var size := lerpf(0.95, 0.45, ring) * rng.randf_range(0.8, 1.15)
		var lump := MeshInstance3D.new()
		lump.mesh = TerrainProps.lump(rng.randi())
		lump.material_override = glossy if i % 3 != 0 else matte
		lump.position = Vector3(cos(angle) * ring * 0.95, (1.0 - ring) * 0.55 + size * 0.15, sin(angle) * ring * 0.95)
		lump.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		lump.scale = Vector3.ONE * size
		mesh.add_child(lump)
