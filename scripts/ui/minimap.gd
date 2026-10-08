class_name Minimap
extends Control
## Overview of the whole map: terrain under the fog of war, coal, buildings,
## creatures (enemies only where you can see them) and the camera's view.
## Left click / drag moves the camera; right click orders the selection there
## (Ctrl + right click: attack-move).

const MAP_SIZE := 200.0
const BORDER_COLOR := Color(0, 0, 0, 0.8)
const VIEW_COLOR := Color(1, 1, 1, 0.85)
const COAL_COLOR := Color(0.05, 0.05, 0.05)
const UNIT_DOT := 3.0
const GHOST_COLOR := Color(0.6, 0.6, 0.6, 0.6)

@export var camera_rig: RTSCamera
@export var selection_manager: SelectionManager
@export var fog: FogOfWar
@export var bounds := Rect2(-50, -50, 100, 100)
@export var ground_color := Color(0.3, 0.42, 0.2)

var _terrain: TextureRect
var _overlay: Control
var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_terrain = TextureRect.new()
	_terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_terrain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_terrain.stretch_mode = TextureRect.STRETCH_SCALE
	_terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/minimap_fog.gdshader")
	material.set_shader_parameter("ground_color", ground_color)
	_terrain.material = material
	add_child(_terrain)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(_delta: float) -> void:
	if fog and _terrain.texture != fog.texture:
		_terrain.texture = fog.texture
	if fog:
		(_terrain.material as ShaderMaterial).set_shader_parameter("fog_enabled", fog.enabled and not fog.reveal_all)
	_overlay.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				camera_rig.focus_on(map_to_world(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			selection_manager.issue_order_at_world(map_to_world(event.position), event.ctrl_pressed)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		camera_rig.focus_on(map_to_world(event.position))
		accept_event()


func world_to_map(point: Vector3) -> Vector2:
	return (Vector2(point.x, point.z) - bounds.position) / bounds.size * size


func map_to_world(local: Vector2) -> Vector3:
	var flat := bounds.position + local / size * bounds.size
	return Vector3(flat.x, 0.0, flat.y)


func _draw_overlay() -> void:
	var player := selection_manager.player_team
	for pile: CoalPile in get_tree().get_nodes_in_group("coal_piles"):
		if fog == null or fog.is_explored(player, pile.global_position):
			_overlay.draw_rect(Rect2(world_to_map(pile.global_position) - Vector2(2, 2), Vector2(4, 4)), COAL_COLOR)
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if not building.is_visible_in_tree():
			continue
		var extent := Vector2(building.data.size.x, building.data.size.z) / bounds.size * size
		var rect := Rect2(world_to_map(building.global_position) - extent / 2.0, extent)
		_overlay.draw_rect(rect.grow(1.0), BORDER_COLOR)
		_overlay.draw_rect(rect, _team_color(building.team))
	if fog:
		for ghost in fog.ghosts:
			var ghost_extent := Vector2(ghost.size.x, ghost.size.z) / bounds.size * size
			_overlay.draw_rect(Rect2(world_to_map(ghost.position) - ghost_extent / 2.0, ghost_extent), GHOST_COLOR)
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not unit.is_visible_in_tree():
			continue
		var at := world_to_map(unit.global_position)
		var color := Color.WHITE if unit.is_selected else _team_color(unit.team)
		_overlay.draw_rect(Rect2(at - Vector2.ONE * UNIT_DOT / 2.0, Vector2.ONE * UNIT_DOT), color)
	_draw_camera_view()
	_overlay.draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)


## Outline of the ground area the camera currently shows.
func _draw_camera_view() -> void:
	var camera := camera_rig.camera
	var screen := get_viewport().get_visible_rect().size
	var ground := Plane(Vector3.UP, 0.0)
	var points := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)]:
		var hit: Variant = ground.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
		if hit == null:
			return
		points.append(world_to_map(hit).clamp(Vector2.ZERO, size))
	points.append(points[0])
	_overlay.draw_polyline(points, VIEW_COLOR, 1.5)


static func _team_color(team: int) -> Color:
	return Creature.TEAM_COLORS[team % Creature.TEAM_COLORS.size()]
