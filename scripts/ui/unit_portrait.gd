class_name UnitPortrait
extends Control
## A brass porthole in the console showing the selected creature or building
## as a slowly turning 3D model, like the original's unit portrait.

const SIZE := 176.0
## Diameter of the glass inside the porthole ring.
const GLASS := 136.0
const TURN_SPEED := 0.6
const BACKGROUND := Color(0.04, 0.11, 0.13)

const CIRCLE_SHADER := """
shader_type canvas_item;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = texture(TEXTURE, UV);
	// Darken towards the rim, like looking through thick glass.
	COLOR.rgb *= mix(1.0, 0.45, smoothstep(0.3, 0.5, d));
	COLOR.a *= 1.0 - smoothstep(0.49, 0.5, d);
}
"""

## What the portrait shows now (a Creature or Building), or null.
var subject: Node3D = null

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(int(GLASS), int(GLASS))
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.6)
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = UiTheme.GLOW
	rim.light_energy = 0.6
	_viewport.add_child(rim)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	_viewport.add_child(_camera)

	var glass := TextureRect.new()
	glass.texture = _viewport.get_texture()
	glass.position = Vector2.ONE * (SIZE - GLASS) / 2.0
	glass.size = Vector2(GLASS, GLASS)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = CIRCLE_SHADER
	glass.material = material
	add_child(glass)
	var ring := TextureRect.new()
	ring.texture = preload("res://assets/ui/porthole.png")
	ring.size = Vector2(SIZE, SIZE)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)


func _process(delta: float) -> void:
	_pivot.rotate_y(TURN_SPEED * delta)


## Shows [param target] (anything with portrait_visual()), or empties the glass.
func show_subject(target: Node3D) -> void:
	if target == subject:
		return
	subject = target
	for child in _pivot.get_children():
		child.queue_free()
	if target == null:
		return
	var model: Node3D = target.portrait_visual()
	_pivot.add_child(model)
	_pivot.rotation = Vector3(0, -0.6, 0)
	_frame(model)


## Points the camera so [param model] fills the glass.
func _frame(model: Node3D) -> void:
	var bounds := AABB()
	var first := true
	for node in [model] + model.find_children("*", "VisualInstance3D", true, false):
		if node is VisualInstance3D:
			var box: AABB = node.global_transform * node.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	if first:
		return
	var radius := maxf(bounds.size.length() / 2.0, 0.1)
	var centre := bounds.get_center()
	var distance := radius / tan(deg_to_rad(_camera.fov / 2.0)) * 1.3
	_camera.position = centre + Vector3(0, radius * 0.45, distance)
	_camera.look_at(centre)
