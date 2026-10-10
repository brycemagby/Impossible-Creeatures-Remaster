class_name UnitRecipe
extends Resource
## Something a building can produce: which creature, and what it costs.

@export var stats: CreatureStats
@export var scene: PackedScene
@export var cost_coal := 50
@export var cost_electricity := 0
## Seconds of production time.
@export var build_time := 8.0
## True for Henchmen (used by the AI to limit how many workers it makes).
@export var is_worker := false


func display_name() -> String:
	return stats.display_name if stats else "Unit"
