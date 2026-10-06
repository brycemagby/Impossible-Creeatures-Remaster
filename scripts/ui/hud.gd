extends Control
## Minimal HUD: shows what is selected plus a controls cheat sheet.

@export var selection_manager: SelectionManager

@onready var selection_label: Label = $SelectionLabel


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	selection_manager.selection_changed.connect(_on_selection_changed)
	_on_selection_changed([])


func _on_selection_changed(units: Array) -> void:
	if units.is_empty():
		selection_label.text = "No units selected"
		return
	var counts := {}
	for unit: Creature in units:
		var unit_name := unit.stats.display_name
		counts[unit_name] = counts.get(unit_name, 0) + 1
	var lines := PackedStringArray(["Selected: %d" % units.size()])
	for unit_name: String in counts:
		lines.append("  %dx %s" % [counts[unit_name], unit_name])
	selection_label.text = "\n".join(lines)
