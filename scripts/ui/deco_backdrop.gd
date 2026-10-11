class_name DecoBackdrop
extends Control
## Menu background: deep teal-black with an art deco sunburst rising from the
## bottom, faint scan lines and a brass horizon line. Drawn in code so it
## scales to any window size.

const RAYS := 28
const RAY_COLOR := Color(0.86, 0.66, 0.34, 0.05)
const SCAN_COLOR := Color(0.36, 0.92, 0.88, 0.025)
const SCAN_SPACING := 4.0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, UiTheme.BACKDROP)
	# Glow pooled behind the sunburst's centre.
	var centre := Vector2(size.x / 2.0, size.y * 1.05)
	for i in 12:
		var radius := size.y * (1.1 - i * 0.08)
		draw_circle(centre, radius, Color(0.08, 0.2, 0.22, 0.06))
	# Sunburst: alternate wedges, fanning upwards.
	var reach := size.length()
	for i in RAYS:
		if i % 2 == 1:
			continue
		var a0 := PI + PI * i / RAYS
		var a1 := PI + PI * (i + 1) / RAYS
		draw_colored_polygon(PackedVector2Array([centre,
				centre + Vector2.from_angle(a0) * reach,
				centre + Vector2.from_angle(a1) * reach]), RAY_COLOR)
	# Concentric deco arcs.
	for i in 4:
		draw_arc(centre, size.y * (0.35 + i * 0.16), PI, TAU, 96, Color(0.86, 0.66, 0.34, 0.08 - i * 0.015), 2.0, true)
	# Scan lines.
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), SCAN_COLOR, 1.0)
		y += SCAN_SPACING
	# Brass rules top and bottom, with a cyan pin-stripe inside.
	for edge: float in [18.0, size.y - 18.0]:
		draw_line(Vector2(40, edge), Vector2(size.x - 40, edge), Color(UiTheme.BRASS, 0.55), 2.0)
		var inner := edge + (6.0 if edge < size.y / 2.0 else -6.0)
		draw_line(Vector2(80, inner), Vector2(size.x - 80, inner), Color(UiTheme.GLOW, 0.25), 1.0)
		for x: float in [40.0, size.x - 40.0]:
			_draw_diamond(Vector2(x, edge), 6.0)


func _draw_diamond(at: Vector2, r: float) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]),
			UiTheme.BRASS)
