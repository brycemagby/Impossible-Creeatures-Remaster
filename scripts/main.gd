extends Node3D
## Root of the skirmish map: sets up the economy, spawns each side's starting
## army from its roster, and keeps the navmesh in sync with buildings being
## placed or destroyed.

const CreatureScene := preload("res://scenes/units/creature.tscn")
const ARMY_SPACING := 2.4

@export var starting_coal := 300.0
@export var starting_electricity := 100.0
## Spawn each team's starting creatures from its army roster.
@export var spawn_starting_army := true
## Starting creatures are picked from the roster until this much coal is spent.
@export var starting_army_budget := 600

var _baking := false
var _rebake_pending := false

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	add_to_group("navmesh")
	Economy.reset([0, 1], starting_coal, starting_electricity)
	Research.reset([0, 1])
	MatchStats.reset([0, 1])
	Upgrades.reset([0, 1])
	_apply_settings()
	navigation_region.bake_finished.connect(_on_bake_finished)
	# Bake from the ground, rock, building and coal colliders.
	navigation_region.bake_navigation_mesh(false)
	if spawn_starting_army:
		spawn_army(0, $PlayerArmySpawn)
		spawn_army(1, $EnemyArmySpawn)


## Applies the skirmish setup choices (fog, AI difficulty).
func _apply_settings() -> void:
	var fog := get_node_or_null("FogOfWar") as FogOfWar
	if fog:
		fog.enabled = GameSettings.fog_enabled
	var ai := get_node_or_null("EnemyAI") as AIController
	if ai:
		ai.apply_difficulty(GameSettings.difficulty)
	Engine.time_scale = GameSettings.game_speed


func _exit_tree() -> void:
	# Leaving a match (menu, restart, end screen) never leaves the game paused
	# or sped up.
	get_tree().paused = false
	Engine.time_scale = 1.0


## Spawns [param team]'s starting army in a grid around [param marker],
## facing the middle of the map. Returns the new creatures.
func spawn_army(team: int, marker: Node3D) -> Array[Creature]:
	var picks := pick_starting_army(Armies.recipes(team), starting_army_budget)
	var to_center := -marker.global_position
	var yaw := atan2(-to_center.x, -to_center.z)
	var spawned: Array[Creature] = []
	var offsets := SelectionManager.formation_offsets(picks.size(), ARMY_SPACING, yaw)
	for i in picks.size():
		var unit: Creature = CreatureScene.instantiate()
		unit.stats = picks[i].stats
		unit.team = team
		unit.position = marker.global_position + offsets[i]
		unit.rotation.y = yaw
		$Units.add_child(unit)
		spawned.append(unit)
	return spawned


## Walks the roster in order, over and over, taking each design that still
## fits in [param budget] coal, until nothing more fits. This keeps starting
## armies fair whatever mix of cheap and expensive designs a roster has.
static func pick_starting_army(recipes: Array[UnitRecipe], budget: int) -> Array[UnitRecipe]:
	var picks: Array[UnitRecipe] = []
	var remaining := budget
	var added := true
	while added:
		added = false
		for recipe in recipes:
			if recipe.cost_coal <= remaining:
				picks.append(recipe)
				remaining -= recipe.cost_coal
				added = true
	return picks


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
