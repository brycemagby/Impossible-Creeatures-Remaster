class_name FogOfWar
extends Node
## Fog of war on a 1 m grid, shared within each alliance (see Teams).
##
## Every UPDATE_INTERVAL seconds each team's creatures and buildings reveal
## the cells within their vision range. Cells a team has ever seen stay
## "explored". For the local player:
## - the ground is darkened (unexplored: almost black, explored: dim),
## - enemy creatures are hidden unless currently visible,
## - enemy buildings are hidden until explored, then stay shown;
## - rocks and coal piles (group "fog_hidden") are hidden until explored;
## - an enemy building destroyed while out of sight leaves a "last seen"
##   ghost until the player looks at that spot again.
## The AI asks is_explored()/is_visible() too, so it doesn't cheat.

const UPDATE_INTERVAL := 0.2
const UNEXPLORED := 0
const EXPLORED := 128
const VISIBLE := 255
const GHOST_COLOR := Color(0.6, 0.6, 0.6, 0.35)

## When false, everyone sees everything (the setting in the skirmish menu).
@export var enabled := true:
	set(value):
		enabled = value
		_refresh_shader()
## The local player still gets fog data, but sees the whole map (debugging, tests).
@export var reveal_all := false:
	set(value):
		reveal_all = value
		_refresh_shader()
@export var player_team := 0
## Map area the grid covers, in world XZ.
@export var bounds := Rect2(-50, -50, 100, 100)
## Ground mesh whose ShaderMaterial (fog_ground.gdshader) shows the fog.
@export var ground: MeshInstance3D

var texture: ImageTexture
var _width := 0
var _depth := 0
## Keyed by alliance id: allies share what they see.
var _visible := {}
var _explored := {}
var _image: Image
var _timer := 0.0
var _material: ShaderMaterial
## Last-seen ghosts: [{position, size, node}].
var ghosts: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("fog")
	add_to_group("building_watchers")
	_width = int(bounds.size.x)
	_depth = int(bounds.size.y)
	_image = Image.create(_width, _depth, false, Image.FORMAT_R8)
	texture = ImageTexture.create_from_image(_image)
	if ground and ground.mesh.surface_get_material(0) is ShaderMaterial:
		# Each match gets its own copy, since scenes share sub-resources.
		_material = ground.mesh.surface_get_material(0).duplicate()
		ground.material_override = _material
	_refresh_shader()
	# Let units finish spawning before the first pass.
	update_now.call_deferred()


func _physics_process(delta: float) -> void:
	_timer += delta
	if _timer >= UPDATE_INTERVAL:
		_timer = 0.0
		update_now()


func update_now() -> void:
	for alliance: int in _visible:
		_visible[alliance].fill(0)
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		if target.is_alive() and target.team in Teams.active:
			_reveal(_grids(target.team), target.global_position, target.vision_range())
	_update_texture()
	_apply_to_player()
	_clear_seen_ghosts()


func is_visible(team: int, point: Vector3) -> bool:
	if not enabled:
		return true
	var index := _index(point)
	return index >= 0 and _grids(team)[0][index] == 1


func is_explored(team: int, point: Vector3) -> bool:
	if not enabled:
		return true
	var index := _index(point)
	return index >= 0 and _grids(team)[1][index] == 1


## [visible, explored] grids for [param team]'s alliance, created on demand.
func _grids(team: int) -> Array[PackedByteArray]:
	var alliance := Teams.alliance(team)
	if not _visible.has(alliance):
		var visible := PackedByteArray()
		visible.resize(_width * _depth)
		var explored := PackedByteArray()
		explored.resize(_width * _depth)
		_visible[alliance] = visible
		_explored[alliance] = explored
	return [_visible[alliance], _explored[alliance]]


## Whether the local player can see [param node] (used by picking and the HUD).
func player_can_see(node: Node3D) -> bool:
	return node.is_visible_in_tree()


## Fraction of the map [param team] has explored, from 0 to 1.
func explored_fraction(team: int) -> float:
	var explored: PackedByteArray = _grids(team)[1]
	var count := 0
	for value in explored:
		count += value
	return float(count) / explored.size()


func _refresh_shader() -> void:
	if _material == null or texture == null:
		return
	_material.set_shader_parameter("fog", texture)
	_material.set_shader_parameter("map_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	_material.set_shader_parameter("fog_enabled", enabled and not reveal_all)
	# Other ground-level surfaces (water) darken with the same fog.
	for surface: MeshInstance3D in get_tree().get_nodes_in_group("fog_surfaces"):
		var material := surface.material_override as ShaderMaterial
		if material:
			material.set_shader_parameter("fog", texture)
			material.set_shader_parameter("map_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
			material.set_shader_parameter("fog_enabled", enabled and not reveal_all)


func _reveal(grids: Array[PackedByteArray], point: Vector3, radius: float) -> void:
	var cx := int(floor(point.x - bounds.position.x))
	var cz := int(floor(point.z - bounds.position.y))
	var r := int(ceil(radius))
	var radius_squared := radius * radius
	var visible: PackedByteArray = grids[0]
	var explored: PackedByteArray = grids[1]
	for z in range(maxi(cz - r, 0), mini(cz + r + 1, _depth)):
		var dz := z - cz
		for x in range(maxi(cx - r, 0), mini(cx + r + 1, _width)):
			var dx := x - cx
			if dx * dx + dz * dz <= radius_squared:
				var index := z * _width + x
				visible[index] = 1
				explored[index] = 1


func _index(point: Vector3) -> int:
	var x := int(floor(point.x - bounds.position.x))
	var z := int(floor(point.z - bounds.position.y))
	if x < 0 or z < 0 or x >= _width or z >= _depth:
		return -1
	return z * _width + x


func _update_texture() -> void:
	var data := PackedByteArray()
	data.resize(_width * _depth)
	var grids := _grids(player_team)
	var visible: PackedByteArray = grids[0]
	var explored: PackedByteArray = grids[1]
	for i in data.size():
		data[i] = VISIBLE if visible[i] == 1 else (EXPLORED if explored[i] == 1 else UNEXPLORED)
	_image.set_data(_width, _depth, false, Image.FORMAT_R8, data)
	texture.update(_image)


func _apply_to_player() -> void:
	var see_all := not enabled or reveal_all
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if Teams.are_enemies(unit.team, player_team):
			# Camouflage hides creatures even with the fog off.
			unit.visible = (see_all or is_visible(player_team, unit.global_position)) and not unit.is_hidden_from(player_team)
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if Teams.are_enemies(building.team, player_team):
			building.visible = see_all or _footprint_explored(building)
	for prop: Node3D in get_tree().get_nodes_in_group("fog_hidden"):
		prop.visible = see_all or is_explored(player_team, prop.global_position)


## Called by buildings as they are destroyed (group "building_watchers").
func building_destroyed(building: Building) -> void:
	if not enabled or reveal_all or not Teams.are_enemies(building.team, player_team) or not building.visible:
		return
	if is_visible(player_team, building.global_position):
		return
	var mesh := BoxMesh.new()
	mesh.size = building.data.size
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = GHOST_COLOR
	var ghost := MeshInstance3D.new()
	ghost.mesh = mesh
	ghost.material_override = material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	ghost.global_position = building.global_position + Vector3.UP * building.data.size.y / 2.0
	ghosts.append({"position": building.global_position, "size": building.data.size, "node": ghost})


func _clear_seen_ghosts() -> void:
	for ghost in ghosts.duplicate():
		if not enabled or reveal_all or is_visible(player_team, ghost.position):
			ghost.node.queue_free()
			ghosts.erase(ghost)


func _footprint_explored(building: Building) -> bool:
	var half := building.data.size / 2.0
	for offset in [Vector3.ZERO, Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z),
			Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, -half.z)]:
		if is_explored(player_team, building.global_position + offset):
			return true
	return false
