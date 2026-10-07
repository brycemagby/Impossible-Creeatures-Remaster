class_name HealthBars
extends Control
## Draws health bars above creatures that are selected or damaged.

const BAR_SIZE := Vector2(36, 5)
const FRIENDLY_COLOR := Color(0.35, 0.9, 0.35)
const ENEMY_COLOR := Color(0.95, 0.3, 0.25)
const BACKGROUND_COLOR := Color(0, 0, 0, 0.7)

@export var camera: Camera3D
@export var player_team := 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not unit.is_selected and unit.health >= unit.stats.max_health:
			continue
		var top := unit.global_position + Vector3.UP * (unit.center_height() * 2.0 + 0.35)
		if camera.is_position_behind(top):
			continue
		var size := BAR_SIZE * Vector2(clampf(unit.stats.size, 0.8, 1.5), 1.0)
		var rect := Rect2(camera.unproject_position(top) - Vector2(size.x / 2.0, size.y), size)
		draw_rect(rect.grow(1.0), BACKGROUND_COLOR)
		var fraction := clampf(unit.health / unit.stats.max_health, 0.0, 1.0)
		var color := FRIENDLY_COLOR if unit.team == player_team else ENEMY_COLOR
		draw_rect(Rect2(rect.position, Vector2(size.x * fraction, size.y)), color)
