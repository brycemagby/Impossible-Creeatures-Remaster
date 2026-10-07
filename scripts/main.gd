extends Node3D
## Root of the skirmish map: sets up the economy and keeps the navmesh in sync
## with buildings being placed or destroyed.

@export var starting_coal := 300.0
@export var starting_electricity := 100.0

var _baking := false
var _rebake_pending := false

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	add_to_group("navmesh")
	Economy.reset([0, 1], starting_coal, starting_electricity)
	navigation_region.bake_finished.connect(_on_bake_finished)
	# Bake from the ground, rock, building and coal colliders.
	navigation_region.bake_navigation_mesh(false)


## Rebakes the navmesh in the background, coalescing overlapping requests.
func request_rebake() -> void:
	if _baking:
		_rebake_pending = true
		return
	_baking = true
	navigation_region.bake_navigation_mesh(true)


func is_baking() -> bool:
	return _baking or _rebake_pending


func _on_bake_finished() -> void:
	_baking = false
	if _rebake_pending:
		_rebake_pending = false
		request_rebake()
