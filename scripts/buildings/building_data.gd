class_name BuildingData
extends Resource
## Data describing a building type. Buildings use placeholder boxes sized
## and coloured from this data until real models exist.

@export var display_name := "Building"
@export var max_health := 1000.0
@export var armor := 5.0
@export var cost_coal := 100
@export var cost_electricity := 0
## Henchman-seconds of work to construct (two Henchmen build twice as fast).
@export var build_time := 20.0
## Footprint width (x), height (y) and depth (z) in metres.
@export var size := Vector3(4, 3, 4)
@export var color := Color(0.6, 0.55, 0.5)
## Henchmen can drop gathered coal off here.
@export var is_drop_off := false
@export var electricity_per_second := 0.0
@export var production: Array[UnitRecipe] = []
## Produces the owning team's army roster (see Armies) instead of [member production].
@export var produces_army := false
## Research levels can be studied here (see Research).
@export var can_research := false
