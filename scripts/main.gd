extends Node3D
## Root of the skirmish test map.

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	# Bake from the ground and rock colliders so map edits don't need a manual rebake.
	navigation_region.bake_navigation_mesh(false)
