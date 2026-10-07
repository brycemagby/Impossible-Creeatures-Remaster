extends Node3D
## Short-lived ring shown where an order was issued.

@export var lifetime := 0.5
@export var color := Color(0.35, 1.0, 0.4)

@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	scale = Vector3.ONE * 1.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.3, lifetime)
	tween.tween_callback(queue_free)
