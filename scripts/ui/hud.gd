extends Control
## Minimal HUD: shows what is selected plus a controls cheat sheet.

@export var selection_manager: SelectionManager

@onready var selection_label: Label = $SelectionLabel


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	selection_label.text = _describe(selection_manager.selected)


func _describe(units: Array[Creature]) -> String:
	var alive := units.filter(func(u: Creature) -> bool: return Creature.is_valid_target(u))
	var lines := PackedStringArray()
	if selection_manager.attack_move_armed:
		lines.append("ATTACK-MOVE: left click a target  (right click / Esc to cancel)")
	if alive.is_empty():
		lines.append("No units selected")
	elif alive.size() == 1:
		var unit: Creature = alive[0]
		var s := unit.stats
		lines.append(s.display_name)
		lines.append("  Health  %d / %d" % [ceili(unit.health), s.max_health])
		lines.append("  Damage  %d every %.1fs (%s)" % [s.attack_damage, s.attack_cooldown,
				"ranged %dm" % s.attack_range if s.is_ranged() else "melee"])
		lines.append("  Armor   %d    Speed  %.1f" % [s.armor, s.move_speed])
	else:
		var counts := {}
		for unit: Creature in alive:
			counts[unit.stats.display_name] = counts.get(unit.stats.display_name, 0) + 1
		lines.append("Selected: %d" % alive.size())
		for unit_name: String in counts:
			lines.append("  %dx %s" % [counts[unit_name], unit_name])
	return "\n".join(lines)
