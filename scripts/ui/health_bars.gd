class_name HealthBars
extends Control
## Draws health bars above creatures and buildings that are selected or damaged.

const BAR_HEIGHT := 5.0
const PIXELS_PER_METRE := 40.0
const FRIENDLY_COLOR := Color(0.35, 0.9, 0.35)
const ENEMY_COLOR := Color(0.95, 0.3, 0.25)
const ALLY_COLOR := Color(0.35, 0.65, 1.0)
const BACKGROUND_COLOR := Color(0, 0, 0, 0.7)

@export var camera: Camera3D
@export var player_team := 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		if not target.is_visible_in_tree() or (not target.is_selected and target.health >= target.get_max_health()):
			continue
		var top: Vector3 = target.global_position + Vector3.UP * target.bar_height()
		if camera.is_position_behind(top):
			continue
		var size: Vector2 = Vector2(clampf(target.radius() * PIXELS_PER_METRE, 30.0, 110.0), BAR_HEIGHT)
		var rect := Rect2(camera.unproject_position(top) - Vector2(size.x / 2.0, size.y), size)
		draw_rect(rect.grow(1.0), BACKGROUND_COLOR)
		var fraction: float = clampf(target.health / target.get_max_health(), 0.0, 1.0)
		var color := FRIENDLY_COLOR if target.team == player_team else (
				ALLY_COLOR if Teams.are_allies(player_team, target.team) else ENEMY_COLOR)
		draw_rect(Rect2(rect.position, Vector2(size.x * fraction, size.y)), color)
