class_name CoalPile
extends StaticBody3D
## A finite coal deposit that Henchmen gather from. It shrinks as it is mined
## and disappears when empty.

const RADIUS := 1.2

@export var amount := 2500

var _starting_amount := 0

@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group("coal_piles")
	add_to_group("fog_hidden")
	_starting_amount = maxi(amount, 1)


## Removes up to [param requested] coal and returns how much was taken.
func take(requested: int) -> int:
	var taken := mini(requested, amount)
	amount -= taken
	_update_size()
	if amount <= 0:
		_deplete()
	return taken


## Online: the host says how much is left.
func set_amount(value: int) -> void:
	amount = value
	_update_size()


func _update_size() -> void:
	mesh.scale = Vector3.ONE * lerpf(0.4, 1.0, float(maxi(amount, 0)) / _starting_amount)


func is_depleted() -> bool:
	return amount <= 0


func edge_distance_from(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() - RADIUS


func _deplete() -> void:
	remove_from_group("coal_piles")
	collision_layer = 0
	get_tree().call_group("navmesh", "request_rebake")
	queue_free()
