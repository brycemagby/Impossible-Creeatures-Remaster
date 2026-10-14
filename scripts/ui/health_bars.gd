class_name HealthBars
extends Control
## Draws health bars above creatures and buildings that are selected or
## damaged (or always, if the player chose that in Options).

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
	if Net.is_online():
		player_team = Net.local_team


func _process(_delta: float) -> void:
	queue_redraw()


## Whether [param target] gets a bar.
func shows(target: Node3D) -> bool:
	if not target.is_visible_in_tree():
		return false
	return Settings.health_bars == Settings.BARS_ALWAYS or target.is_selected or target.health < target.get_max_health()


func _draw() -> void:
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		if not shows(target):
			continue
		var top: Vector3 = target.global_position + Vector3.UP * target.bar_height()
		if camera.is_position_behind(top):
			continue
		var size: Vector2 = Vector2(clampf(target.radius() * PIXELS_PER_METRE, 30.0, 110.0), BAR_HEIGHT)
		var rect := Rect2(camera.unproject_position(top) - Vector2(size.x / 2.0, size.y), size)
		draw_rect(rect.grow(1.0), BACKGROUND_COLOR)
		var fraction: float = clampf(target.health / target.get_max_health(), 0.0, 1.0)
		var enemy := Teams.are_enemies(player_team, target.team)
		var color := FRIENDLY_COLOR if target.team == player_team else (ENEMY_COLOR if enemy else ALLY_COLOR)
		if Settings.colorblind:
			color = Teams.color(target.team)
		draw_rect(Rect2(rect.position, Vector2(size.x * fraction, size.y)), color)
		if enemy:
			# Enemies are told apart by shape too, not only colour: a small
			# downward pointer on the bar's left end.
			var tip := rect.position + Vector2(-5.0, size.y / 2.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-6, -6), tip + Vector2(0, -6), tip + Vector2(-3, 1)]), BACKGROUND_COLOR)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -5), tip + Vector2(-1, -5), tip + Vector2(-3, -1)]), color)
