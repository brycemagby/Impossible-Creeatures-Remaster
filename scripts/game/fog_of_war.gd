class_name FogOfWar
extends Node
## Per-team fog of war on a 1 m grid.
##
## Every UPDATE_INTERVAL seconds each team's creatures and buildings reveal
## the cells within their vision range. Cells a team has ever seen stay
## "explored". For the local player:
## - the ground is darkened (unexplored: almost black, explored: dim),
## - enemy creatures are hidden unless currently visible,
## - enemy buildings are hidden until explored, then stay shown.
## The AI asks is_explored()/is_visible() too, so it doesn't cheat.

const UPDATE_INTERVAL := 0.2
const UNEXPLORED := 0
const EXPLORED := 128
const VISIBLE := 255

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
@export var teams: Array[int] = [0, 1]
## Map area the grid covers, in world XZ.
@export var bounds := Rect2(-50, -50, 100, 100)
## Ground mesh whose ShaderMaterial (fog_ground.gdshader) shows the fog.
@export var ground: MeshInstance3D

var texture: ImageTexture
var _width := 0
var _depth := 0
var _visible := {}
var _explored := {}
var _image: Image
var _timer := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	add_to_group("fog")
	_width = int(bounds.size.x)
	_depth = int(bounds.size.y)
	for team in teams:
		_visible[team] = PackedByteArray()
		_visible[team].resize(_width * _depth)
		_explored[team] = PackedByteArray()
		_explored[team].resize(_width * _depth)
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
	for team in teams:
		_visible[team].fill(0)
	for target: Node3D in get_tree().get_nodes_in_group("targets"):
		if target.is_alive() and _visible.has(target.team):
			_reveal(target.team, target.global_position, target.vision_range())
	_update_texture()
	_apply_to_player()


func is_visible(team: int, point: Vector3) -> bool:
	if not enabled or not _visible.has(team):
		return true
	var index := _index(point)
	return index >= 0 and _visible[team][index] == 1


func is_explored(team: int, point: Vector3) -> bool:
	if not enabled or not _explored.has(team):
		return true
	var index := _index(point)
	return index >= 0 and _explored[team][index] == 1


## Whether the local player can see [param node] (used by picking and the HUD).
func player_can_see(node: Node3D) -> bool:
	return node.is_visible_in_tree()


## Fraction of the map [param team] has explored, from 0 to 1.
func explored_fraction(team: int) -> float:
	var count := 0
	for value in _explored[team]:
		count += value
	return float(count) / _explored[team].size()


func _refresh_shader() -> void:
	if _material == null or texture == null:
		return
	_material.set_shader_parameter("fog", texture)
	_material.set_shader_parameter("map_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	_material.set_shader_parameter("fog_enabled", enabled and not reveal_all)


func _reveal(team: int, point: Vector3, radius: float) -> void:
	var cx := int(floor(point.x - bounds.position.x))
	var cz := int(floor(point.z - bounds.position.y))
	var r := int(ceil(radius))
	var radius_squared := radius * radius
	var visible: PackedByteArray = _visible[team]
	var explored: PackedByteArray = _explored[team]
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
	if not _visible.has(player_team):
		return
	var data := PackedByteArray()
	data.resize(_width * _depth)
	var visible: PackedByteArray = _visible[player_team]
	var explored: PackedByteArray = _explored[player_team]
	for i in data.size():
		data[i] = VISIBLE if visible[i] == 1 else (EXPLORED if explored[i] == 1 else UNEXPLORED)
	_image.set_data(_width, _depth, false, Image.FORMAT_R8, data)
	texture.update(_image)


func _apply_to_player() -> void:
	var see_all := not enabled or reveal_all
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team != player_team:
			unit.visible = see_all or is_visible(player_team, unit.global_position)
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team != player_team:
			building.visible = see_all or _footprint_explored(building)


func _footprint_explored(building: Building) -> bool:
	var half := building.data.size / 2.0
	for offset in [Vector3.ZERO, Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z),
			Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, -half.z)]:
		if is_explored(player_team, building.global_position + offset):
			return true
	return false
