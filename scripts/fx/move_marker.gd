extends Node3D
## Short-lived ring shown where a move order was issued.

@export var lifetime := 0.5


func _ready() -> void:
	scale = Vector3.ONE * 1.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.3, lifetime)
	tween.tween_callback(queue_free)
