class_name SelectionBox
extends Control
## Draws the drag-select rectangle.

@export var fill_color := Color(0.3, 0.8, 0.4, 0.15)
@export var border_color := Color(0.4, 1.0, 0.5, 0.9)

var _rect := Rect2()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


func show_box(rect: Rect2) -> void:
	_rect = rect
	visible = true
	queue_redraw()


func hide_box() -> void:
	visible = false


func _draw() -> void:
	draw_rect(_rect, fill_color, true)
	draw_rect(_rect, border_color, false, 1.0)
