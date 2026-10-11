extends Node3D
## Root of a skirmish map: sets up the teams for the chosen player count
## (removing unused bases), the economy, one AI per opponent, each side's
## starting army from its roster, and keeps the navmesh in sync with buildings
## being placed or destroyed.
##
## Maps hold bases for up to 4 teams: ArmySpawnN markers, and each team's
## Lab, Generator and Henchmen. You are team 0, except when you joined an
## online game (see Net): then the host runs the match and this map is a view.

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
	var teams := _match_teams()
	Teams.setup(teams, GameSettings.alliances())
	_remove_unused_bases(teams)
	get_tree().call_group("targets", "refresh_team_color")
	Economy.reset(teams, starting_coal, starting_electricity)
	Research.reset(teams)
	MatchStats.reset(teams)
	Upgrades.reset(teams)
	Alerts.reset()
	_apply_settings()
	navigation_region.bake_finished.connect(_on_bake_finished)
	# Bake from the ground, rock, building and coal colliders.
	navigation_region.bake_navigation_mesh(false)
	if Net.sync:
		# Numbers every map-placed unit and building the same on both machines.
		Net.sync.begin_match(self)
		_focus_camera_on_base(Net.local_team)
	# Online, the host spawns everything and the other player is told.
	if spawn_starting_army and not Net.is_client():
		for team in teams:
			spawn_army(team, get_node("ArmySpawn%d" % team))


## The chosen number of players, limited to the bases this map has.
func _match_teams() -> Array[int]:
	var bases := 0
	while has_node("ArmySpawn%d" % bases):
		bases += 1
	var teams: Array[int] = []
	for team in GameSettings.active_teams():
		if team < bases:
			teams.append(team)
	return teams


## Takes out the buildings and Henchmen of bases nobody is playing.
func _remove_unused_bases(teams: Array[int]) -> void:
	for node: Node3D in get_tree().get_nodes_in_group("targets"):
		if node.team not in teams and is_ancestor_of(node):
			# Out of the tree right away, so the navmesh bake doesn't see it.
			node.get_parent().remove_child(node)
			node.queue_free()


## Applies the skirmish setup choices (fog, AI difficulty).
func _apply_settings() -> void:
	var fog := get_node_or_null("FogOfWar") as FogOfWar
	if fog:
		fog.enabled = GameSettings.fog_enabled
	# The scene's EnemyAI plays team 1; every further opponent gets its own.
	# Online, people play their teams and only the host runs any AI.
	var humans: Array[int] = [0]
	if Net.is_online():
		humans = Net.human_teams()
	var scene_ai := get_node_or_null("EnemyAI")
	if scene_ai != null and (Net.is_client() or 1 in humans):
		remove_child(scene_ai)
		scene_ai.queue_free()
	for team in Teams.active:
		if team in humans or Net.is_client():
			continue
		var ai := get_node_or_null("EnemyAI") as AIController if team == 1 else null
		if ai == null:
			ai = AIController.new()
			ai.name = "AI%d" % team
			ai.team = team
			add_child(ai)
		ai.apply_difficulty(GameSettings.difficulty)
	Engine.time_scale = GameSettings.game_speed


## Starts the camera on [param team]'s base the way the map frames team 0's:
## the same offset and angle, turned to face the middle of the map from there.
func _focus_camera_on_base(team: int) -> void:
	var home := _base_marker(0)
	var marker := _base_marker(team)
	var rig := get_node_or_null("RTSCamera") as Node3D
	if team == 0 or home == null or marker == null or rig == null:
		return
	var turn := _yaw_to_center(marker.global_position) - _yaw_to_center(home.global_position)
	var offset := (rig.global_position - home.global_position).rotated(Vector3.UP, turn)
	rig.global_position = marker.global_position + offset
	rig.rotation.y += turn


func _base_marker(team: int) -> Node3D:
	var marker := get_node_or_null("StartLocation%d" % team) as Node3D
	return marker if marker != null else get_node_or_null("ArmySpawn%d" % team) as Node3D


## Camera yaw that looks from [param point] towards the middle of the map.
static func _yaw_to_center(point: Vector3) -> float:
	return atan2(point.x, point.z)


func _exit_tree() -> void:
	# Leaving a match (menu, restart, end screen) never leaves the game paused
	# or sped up.
	get_tree().paused = false
	Engine.time_scale = 1.0


## Spawns [param team]'s starting army in a grid around [param marker],
## facing the middle of the map. Returns the new creatures.
func spawn_army(team: int, marker: Node3D) -> Array[Creature]:
	# Creatures that can only swim would be stranded on land.
	var walkers: Array[UnitRecipe] = []
	for recipe in Armies.recipes(team):
		if not recipe.stats.water_only:
			walkers.append(recipe)
	var picks := pick_starting_army(walkers, starting_army_budget)
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
	# Online, only the host's units find their way around.
	if Net.is_client():
		return
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
