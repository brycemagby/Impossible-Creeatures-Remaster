class_name RTSCamera
extends Node3D
## Top-down RTS camera rig.
##
## The rig node sits on the ground plane and handles panning and yaw; the child
## Camera3D is offset along a fixed pitch and moved in and out to zoom.
## Controls: WASD/arrows or screen edges to pan, middle mouse drag to pan,
## Q/E to rotate, mouse wheel to zoom.

@export var pan_speed := 20.0
@export var edge_scroll_enabled := true
@export var edge_scroll_margin := 12.0
@export var drag_pan_sensitivity := 0.05
@export var rotate_speed := 1.8
@export var zoom_step := 2.5
@export var min_zoom := 8.0
@export var max_zoom := 50.0
@export var zoom_smoothing := 10.0
@export_range(20.0, 89.0) var pitch_degrees := 55.0
## Area (in world XZ) the rig's focus point is clamped to.
@export var bounds := Rect2(-50, -50, 100, 100)

var zoom := 25.0
var target_zoom := 25.0
var _drag_panning := false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	# Edge scrolling is meaningless without a real window (e.g. headless tests).
	if DisplayServer.get_name() == "headless":
		edge_scroll_enabled = false
	target_zoom = clampf(target_zoom, min_zoom, max_zoom)
	zoom = target_zoom
	_apply_zoom()


func _process(delta: float) -> void:
	var pan := Input.get_vector("camera_left", "camera_right", "camera_forward", "camera_back")
	if edge_scroll_enabled and not _drag_panning:
		pan += _edge_scroll_vector()
	if pan != Vector2.ZERO:
		pan_by(pan.limit_length(1.0) * pan_speed * _zoom_factor() * delta)

	var turn := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	rotation.y += turn * rotate_speed * delta

	zoom = lerpf(zoom, target_zoom, clampf(zoom_smoothing * delta, 0.0, 1.0))
	_apply_zoom()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					target_zoom = clampf(target_zoom - zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					target_zoom = clampf(target_zoom + zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_MIDDLE:
				_drag_panning = event.pressed
	elif event is InputEventMouseMotion and _drag_panning:
		pan_by(-event.relative * drag_pan_sensitivity * _zoom_factor())


## Moves the focus point by [param offset] in screen-aligned axes
## (x = right, y = toward the camera).
func pan_by(offset: Vector2) -> void:
	position += Vector3(offset.x, 0.0, offset.y).rotated(Vector3.UP, rotation.y)
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


## Instantly centres the camera on a world position.
func focus_on(world_position: Vector3) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	pan_by(Vector2.ZERO)


func _apply_zoom() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0.0, sin(pitch) * zoom, cos(pitch) * zoom)
	camera.rotation = Vector3(-pitch, 0.0, 0.0)


## Pan faster when zoomed out so the speed feels constant on screen.
func _zoom_factor() -> float:
	return zoom / 25.0


func _edge_scroll_vector() -> Vector2:
	if not get_window().has_focus():
		return Vector2.ZERO
	var rect := get_viewport().get_visible_rect()
	var mouse := get_viewport().get_mouse_position()
	if not rect.has_point(mouse):
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if mouse.x < edge_scroll_margin:
		dir.x -= 1.0
	elif mouse.x > rect.size.x - edge_scroll_margin:
		dir.x += 1.0
	if mouse.y < edge_scroll_margin:
		dir.y -= 1.0
	elif mouse.y > rect.size.y - edge_scroll_margin:
		dir.y += 1.0
	return dir
