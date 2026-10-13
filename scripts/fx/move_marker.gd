extends Node3D
## Short-lived ring shown where an order was issued, or a red cross that
## wobbles where an order couldn't be carried out (e.g. a building that
## doesn't fit), so failures show where they happened, not only as text.

const FAILED_COLOR := Color(1.0, 0.3, 0.25)

@export var lifetime := 0.5
@export var color := Color(0.35, 1.0, 0.4)
@export var failed := false

@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FAILED_COLOR if failed else color
	mesh.material_override = material
	if failed:
		_show_cross(material)
		return
	scale = Vector3.ONE * 1.5
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.3, lifetime)
	tween.tween_callback(queue_free)


func _show_cross(material: Material) -> void:
	mesh.visible = false
	var bar := BoxMesh.new()
	bar.size = Vector3(1.6, 0.06, 0.28)
	for angle in [PI / 4.0, -PI / 4.0]:
		var stroke := MeshInstance3D.new()
		stroke.mesh = bar
		stroke.material_override = material
		stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stroke.rotation.y = angle
		add_child(stroke)
	# A quick head-shake, then shrink away.
	var tween := create_tween()
	for i in 3:
		tween.tween_property(self, "rotation:y", 0.25, 0.06)
		tween.tween_property(self, "rotation:y", -0.25, 0.06)
	tween.tween_property(self, "rotation:y", 0.0, 0.05)
	tween.tween_interval(0.25)
	tween.tween_property(self, "scale", Vector3.ONE * 0.2, 0.25)
	tween.tween_callback(queue_free)
