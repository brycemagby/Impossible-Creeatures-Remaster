class_name BuildingModel
extends Node3D
## A building's 3D model: placeholder retro-futurist art (riveted iron, brass
## domes, art-deco setbacks, valve glow) built from simple shapes, one look
## per building, with a few parts animated in code (spinning gears and dishes,
## pulsing coils, chimney smoke). The origin is the middle of the footprint at
## ground level, the front faces +Z (towards the default camera), and
## everything stays inside the building's footprint and height.
##
## Real art can replace a building without code changes: put a scene at
## ART_DIR/<id>.tscn (or .glb), where id is the building's resource name
## (lab, generator, creature_chamber, ...). Meshes whose names start with
## "Team" are painted in the owner's colour.

const ART_DIR := "res://assets/buildings/"

const BRASS := Color(0.78, 0.6, 0.28)
const COPPER := Color(0.7, 0.4, 0.24)
const IRON := Color(0.2, 0.2, 0.22)
const STEEL := Color(0.45, 0.46, 0.48)
const STONE := Color(0.48, 0.45, 0.4)
const PLASTER := Color(0.76, 0.7, 0.58)
const BRICK := Color(0.55, 0.3, 0.22)
const WOOD := Color(0.5, 0.36, 0.22)
const COAL := Color(0.08, 0.08, 0.09)
const SMOKE := Color(0.55, 0.55, 0.55, 0.6)
const VALVE := Color(1.0, 0.68, 0.3)
const SPARK := Color(0.45, 0.9, 1.0)
const BREW := Color(0.45, 1.0, 0.55)
const WATER := Color(0.35, 0.65, 1.0)
## Colour a construction site's materials lean towards.
const SITE_TINT := Color(0.55, 0.45, 0.25)

## Building id this model was built for (the resource file's name).
var id := ""
var _size := Vector3.ONE
var _wall := Color.GRAY
var _team_material: StandardMaterial3D
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _material_cache := {}
var _unfinished := false
var _flash_tween: Tween

# Animated parts, looked up by meta so duplicated models (the portrait) animate too.
var _spinners: Array[Node3D] = []
var _puffs: Array[Node3D] = []
var _pulse: Array[StandardMaterial3D] = []
var _resolved := false
var _time := 0.0


## Builds the model for [param data] in [param team_color].
func build(data: BuildingData, team_color: Color) -> void:
	for child in get_children():
		child.queue_free()
	_materials.clear()
	_base_colors.clear()
	_material_cache.clear()
	_resolved = false
	id = id_of(data)
	_size = data.size
	_wall = data.color
	_team_material = StandardMaterial3D.new()
	_team_material.albedo_color = team_color
	_team_material.roughness = 0.6
	_team_material.metallic = 0.2
	var art := _art()
	if art != null:
		add_child(art)
		_paint_team_parts(art)
		return
	match id:
		"lab": _lab()
		"generator": _generator()
		"creature_chamber": _creature_chamber()
		"house": _house()
		"research_center": _research_center()
		"soundbeam_tower": _soundbeam_tower()
		"water_chamber": _water_chamber()
		"aviary": _aviary()
		"workshop": _workshop()
		_: _fallback()
	_scaffold()


static func id_of(data: BuildingData) -> String:
	if data.resource_path != "":
		return data.resource_path.get_file().get_basename()
	return data.display_name.to_snake_case()


func set_team_color(color: Color) -> void:
	_team_material.albedo_color = color


func team_color() -> Color:
	return _team_material.albedo_color


## Construction site look: sepia tint, unlit lamps, scaffolding.
func set_unfinished(unfinished: bool) -> void:
	_unfinished = unfinished
	for i in _materials.size():
		_materials[i].albedo_color = _shown_color(i)
	for node in find_children("*", "", true, false):
		if node.has_meta("lit"):
			(node as Node3D).visible = not unfinished
		elif node.has_meta("scaffold"):
			(node as Node3D).visible = unfinished


## Briefly whitens the model (hit feedback).
func flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween().set_parallel()
	for i in _materials.size():
		_materials[i].albedo_color = Color.WHITE
		_flash_tween.tween_property(_materials[i], "albedo_color", _shown_color(i), 0.12)


## Draws every mesh with [param material] instead (placement and fog ghosts).
func use_material(material: Material) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.has_meta("scaffold"):
			mesh.visible = false


func _process(delta: float) -> void:
	if not _resolved:
		_resolve()
	if _unfinished:
		return
	_time += delta
	for node in _spinners:
		var spin: Vector3 = node.get_meta("spin")
		node.rotate_object_local(spin.normalized(), spin.length() * delta)
	for i in _puffs.size():
		var puff := _puffs[i]
		var t := fmod(_time * 0.45 + float(i) / _puffs.size(), 1.0)
		var base: Vector3 = puff.get_meta("puff")
		puff.position = base + Vector3(t * 0.4, t * 1.6, t * 0.15)
		puff.scale = Vector3.ONE * lerpf(0.5, 1.6, t) * (1.0 - smoothstep(0.75, 1.0, t))
	for material in _pulse:
		material.emission_energy_multiplier = 1.4 + 0.9 * sin(_time * 4.0)


func _resolve() -> void:
	_resolved = true
	_spinners.clear()
	_puffs.clear()
	_pulse.clear()
	for node in find_children("*", "Node3D", true, false):
		if node.has_meta("spin"):
			_spinners.append(node)
		if node.has_meta("puff"):
			_puffs.append(node)
		if node.has_meta("pulse") and node is MeshInstance3D:
			var material := (node as MeshInstance3D).material_override as StandardMaterial3D
			if material != null and not _pulse.has(material):
				_pulse.append(material)


func _shown_color(i: int) -> Color:
	var color := _base_colors[i]
	return color.lerp(SITE_TINT, 0.6) if _unfinished else color


# --- Shapes -------------------------------------------------------------------

func add_shape(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var key := [color, glow]
	var material: StandardMaterial3D = _material_cache.get(key)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.8
		if color == BRASS or color == COPPER or color == STEEL:
			material.metallic = 0.55
			material.roughness = 0.45
		if color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if glow:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 1.8
		_material_cache[key] = material
		_materials.append(material)
		_base_colors.append(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


## A team-coloured shape (flags, bands, doors).
func add_team(parent: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "Team" + str(parent.get_child_count())
	instance.mesh = mesh
	instance.material_override = _team_material
	instance.position = at
	parent.add_child(instance)
	return instance


## A box resting on [param base_y] (its bottom), centred at x, z.
func block(parent: Node3D, size: Vector3, x: float, base_y: float, z: float, color: Color) -> MeshInstance3D:
	return add_shape(parent, box(size), Vector3(x, base_y + size.y / 2.0, z), color)


## An upright cylinder resting on [param base_y].
func drum(parent: Node3D, radius: float, height: float, x: float, base_y: float, z: float, color: Color,
		sides := 16, top := -1.0) -> MeshInstance3D:
	return add_shape(parent, cylinder(radius, height, sides, top), Vector3(x, base_y + height / 2.0, z), color)


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func cylinder(radius: float, height: float, sides := 16, top := -1.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return mesh


static func sphere(radius: float, hemisphere := false) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if hemisphere else 2.0)
	mesh.is_hemisphere = hemisphere
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func ring(radius: float, thickness: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 24
	mesh.ring_segments = 6
	return mesh


## A triangular roof [param size] wide (x), tall (y) and long (z);
## [param ridge] places the ridge from the left (0) to the right (1) edge.
static func roof(size: Vector3, ridge := 0.5) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = ridge
	return mesh


## A row of rivets along x on the face at z, height y.
func rivets(parent: Node3D, from_x: float, to_x: float, y: float, z: float, count: int) -> void:
	var stud := sphere(0.06)
	for i in count:
		var x := lerpf(from_x, to_x, (i + 0.5) / count)
		add_shape(parent, stud, Vector3(x, y, z), BRASS)


## A glowing window with a brass frame on the +Z face at [param z].
func window(parent: Node3D, x: float, y: float, z: float, w: float, h: float, porthole := false) -> void:
	if porthole:
		var frame := add_shape(parent, ring(w / 2.0, 0.06), Vector3(x, y, z + 0.02), BRASS)
		frame.rotation.x = PI / 2.0
		var pane := add_shape(parent, cylinder(w / 2.0 - 0.03, 0.04, 12), Vector3(x, y, z), IRON)
		pane.rotation.x = PI / 2.0
		var lit := add_shape(parent, cylinder(w / 2.0 - 0.03, 0.05, 12), Vector3(x, y, z + 0.01), VALVE, true)
		lit.rotation.x = PI / 2.0
		lit.set_meta("lit", true)
		return
	add_shape(parent, box(Vector3(w + 0.12, h + 0.12, 0.05)), Vector3(x, y, z), BRASS)
	add_shape(parent, box(Vector3(w, h, 0.07)), Vector3(x, y, z), IRON)
	add_shape(parent, box(Vector3(w, h, 0.08)), Vector3(x, y, z), VALVE, true).set_meta("lit", true)


## A chimney stack with smoke puffs.
func chimney(parent: Node3D, x: float, base_y: float, z: float, height: float, radius := 0.22) -> void:
	drum(parent, radius, height, x, base_y, z, BRICK, 8)
	drum(parent, radius + 0.06, 0.15, x, base_y + height - 0.15, z, IRON, 8)
	var puff_mesh := sphere(0.22)
	for i in 3:
		var puff := add_shape(parent, puff_mesh, Vector3(x, base_y + height, z), SMOKE)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.set_meta("puff", puff.position)
		puff.set_meta("lit", true)


## A cog of [param radius] facing +Z, spinning at [param speed] rad/s.
func gear(parent: Node3D, at: Vector3, radius: float, speed: float, color := BRASS) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	if speed != 0.0:
		pivot.set_meta("spin", Vector3(0, 0, speed))
	parent.add_child(pivot)
	add_shape(pivot, cylinder(radius, 0.14, 16), Vector3.ZERO, color).rotation.x = PI / 2.0
	add_shape(pivot, cylinder(radius * 0.3, 0.2, 8), Vector3.ZERO, IRON).rotation.x = PI / 2.0
	var tooth := box(Vector3(radius * 0.32, radius * 0.3, 0.14))
	var teeth := 10
	for i in teeth:
		var angle := TAU * i / teeth
		var t := add_shape(pivot, tooth, Vector3(cos(angle), sin(angle), 0) * radius, color)
		t.rotation.z = angle
	return pivot


## A team pennant on a brass pole, rising from [param base].
func pennant(parent: Node3D, base: Vector3, height := 1.2) -> void:
	add_shape(parent, cylinder(0.04, height, 6), base + Vector3.UP * height / 2.0, BRASS)
	add_shape(parent, sphere(0.07), base + Vector3.UP * height, BRASS)
	var flag := add_team(parent, roof(Vector3(0.36, 0.55, 0.03)), base + Vector3(0.28, height - 0.2, 0))
	flag.rotation.z = -PI / 2.0


## A team-coloured band around a box of [param size] at height y.
func band(parent: Node3D, size: Vector3, y: float, z_offset := 0.0, depth := 0.22) -> void:
	add_team(parent, box(Vector3(size.x + 0.08, depth, size.z + 0.08)), Vector3(0, y, z_offset))


## Wooden poles and planks, shown while the building is a construction site.
func _scaffold() -> void:
	var hx := _size.x / 2.0
	var hz := _size.z / 2.0
	var h := _size.y
	var pole := cylinder(0.06, h, 6)
	for corner in [Vector2(hx, hz), Vector2(-hx, hz), Vector2(hx, -hz), Vector2(-hx, -hz)]:
		add_shape(self, pole, Vector3(corner.x, h / 2.0, corner.y), WOOD).set_meta("scaffold", true)
	for y in [h * 0.35, h * 0.75]:
		for side in [-1.0, 1.0]:
			add_shape(self, box(Vector3(_size.x, 0.06, 0.18)), Vector3(0, y, hz * side), WOOD).set_meta("scaffold", true)
			add_shape(self, box(Vector3(0.18, 0.06, _size.z)), Vector3(hx * side, y, 0), WOOD).set_meta("scaffold", true)
	for node in get_children():
		if node.has_meta("scaffold"):
			(node as Node3D).visible = false


# --- The buildings ------------------------------------------------------------

## Headquarters: a stepped art-deco hall with a brass observatory dome, a
## coal hopper on the side and a smoking chimney.
func _lab() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.35, s.z), 0, 0, 0, STONE)
	var hall := Vector3(s.x - 1.6, 2.1, s.z - 1.0)
	block(self, hall, -0.5, 0.35, 0, _wall)
	band(self, Vector3(hall.x, 0, hall.z), 2.3, 0.0)
	get_child(get_child_count() - 1).position.x = -0.5
	block(self, Vector3(hall.x - 1.2, 0.7, hall.z - 1.2), -0.5, 2.45, 0, _wall.lightened(0.1))
	block(self, Vector3(hall.x - 1.0, 0.1, hall.z - 1.0), -0.5, 2.45, 0, BRASS)
	# Observatory dome and telescope.
	add_shape(self, sphere(1.25, true), Vector3(-0.5, 3.15, 0), BRASS)
	add_shape(self, ring(1.25, 0.06), Vector3(-0.5, 3.15, 0), IRON)
	var scope := add_shape(self, cylinder(0.16, 1.6, 10, 0.22), Vector3(-0.5, 3.9, 0.55), IRON)
	scope.rotation.x = 0.85
	# Front: deco door with fins and lit windows.
	var front := 0.0 + hall.z / 2.0
	block(self, Vector3(1.1, 1.5, 0.12), -0.5, 0.35, front, IRON)
	add_team(self, box(Vector3(1.3, 0.22, 0.14)), Vector3(-0.5, 2.0, front))
	for fx in [-1.25, 0.25]:
		block(self, Vector3(0.18, 2.2, 0.2), fx, 0.35, front + 0.05, BRASS)
	for wx in [-1.75, 0.95]:
		window(self, wx, 1.45, front + 0.02, 0.5, 0.8)
	rivets(self, -0.5 - hall.x / 2.0, -0.5 + hall.x / 2.0, 0.55, front + 0.04, 9)
	# Coal hopper on the east side: a funnel bin full of coal.
	var hx := s.x / 2.0 - 0.75
	block(self, Vector3(0.12, 1.2, 0.12), hx - 0.45, 0.35, -0.45, IRON)
	block(self, Vector3(0.12, 1.2, 0.12), hx + 0.45, 0.35, -0.45, IRON)
	block(self, Vector3(0.12, 1.2, 0.12), hx - 0.45, 0.35, 0.45, IRON)
	block(self, Vector3(0.12, 1.2, 0.12), hx + 0.45, 0.35, 0.45, IRON)
	var bin := add_shape(self, cylinder(0.7, 1.0, 4, 0.35), Vector3(hx, 2.05, 0), IRON)
	bin.rotation = Vector3(PI, PI / 4.0, 0)
	add_shape(self, sphere(0.55, true), Vector3(hx, 2.5, 0), COAL).scale = Vector3(1, 0.5, 1)
	chimney(self, -2.1, 2.45, -1.6, 1.3)
	pennant(self, Vector3(1.0, 2.45, -1.6))


## Electrical Generator: a riveted drum with a glowing core in a glass jacket
## and a pair of Tesla coils with spinning rings.
func _generator() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.3, s.z), 0, 0, 0, STONE)
	drum(self, 1.15, 2.0, 0, 0.3, 0, _wall, 12)
	for y in [0.55, 1.45, 2.2]:
		add_shape(self, ring(1.17, 0.05), Vector3(0, y, 0), BRASS)
	add_team(self, cylinder(1.2, 0.25, 12), Vector3(0, 1.0, 0))
	drum(self, 0.95, 0.2, 0, 2.3, 0, BRASS, 12)
	# The core: a valve in a glass jacket.
	drum(self, 0.45, 1.1, 0, 2.5, 0, Color(0.6, 0.9, 1.0, 0.35), 12)
	var core := drum(self, 0.25, 0.9, 0, 2.6, 0, SPARK, 10)
	_glow(core)
	drum(self, 0.5, 0.15, 0, 3.6, 0, BRASS, 12)
	add_shape(self, cone(0.12, 0.35), Vector3(0, 3.92, 0), BRASS)
	# Tesla coils at the front corners.
	for side in [-1.0, 1.0]:
		var x: float = side * 1.15
		drum(self, 0.16, 2.6, x, 0.3, 1.05, COPPER, 8, 0.1)
		var rings := Node3D.new()
		rings.position = Vector3(x, 2.4, 1.05)
		rings.set_meta("spin", Vector3(0, 3.0 * side, 0))
		add_child(rings)
		for i in 3:
			add_shape(rings, ring(0.28 - i * 0.06, 0.035), Vector3(0, -0.5 + i * 0.25, 0), BRASS).rotation.z = 0.25
		_glow(add_shape(self, sphere(0.18), Vector3(x, 3.0, 1.05), SPARK, true))
	# Cables to the ground.
	block(self, Vector3(0.5, 0.5, 0.5), 1.0, 0.3, -1.0, IRON)
	window(self, 0, 1.45, 1.16, 0.4, 0.4, true)


## Creature Chamber: a squat riveted octagonal vat with bubbling glass tanks
## on top and a round hatch door.
func _creature_chamber() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.3, s.z), 0, 0, 0, STONE)
	var vat := drum(self, 2.35, 1.9, 0, 0.3, 0, _wall, 8)
	vat.rotation.y = PI / 8.0
	add_shape(self, ring(2.2, 0.07), Vector3(0, 0.45, 0), BRASS).rotation.y = PI / 8.0
	add_team(self, cylinder(2.3, 0.22, 8), Vector3(0, 2.1, 0)).rotation.y = PI / 8.0
	drum(self, 2.0, 0.25, 0, 2.2, 0, IRON, 8).rotation.y = PI / 8.0
	# Hatch with a brass ring and wheel.
	var hatch := add_shape(self, cylinder(0.7, 0.15, 16), Vector3(0, 1.15, 2.2), IRON)
	hatch.rotation.x = PI / 2.0
	add_shape(self, ring(0.72, 0.07), Vector3(0, 1.15, 2.28), BRASS).rotation.x = PI / 2.0
	gear(self, Vector3(0, 1.15, 2.32), 0.3, 0.0)
	# Glass tanks with glowing brew.
	for spot in [Vector3(-0.9, 2.45, -0.4), Vector3(0.9, 2.45, -0.4), Vector3(0, 2.45, 0.8)]:
		var p: Vector3 = spot
		drum(self, 0.42, 0.12, p.x, p.y, p.z, BRASS, 12)
		drum(self, 0.36, 0.8, p.x, p.y + 0.12, p.z, Color(0.7, 1.0, 0.8, 0.35), 12)
		_glow(drum(self, 0.3, 0.55, p.x, p.y + 0.14, p.z, BREW, 10))
		add_shape(self, sphere(0.36, true), Vector3(p.x, p.y + 0.92, p.z), BRASS)
	# Feed pipes down the sides.
	for side in [-1.0, 1.0]:
		var pipe := add_shape(self, cylinder(0.1, 2.4, 8), Vector3(side * 2.15, 1.3, -1.2), COPPER)
		pipe.rotation.x = 0.2
	pennant(self, Vector3(-1.6, 2.45, 1.4))


## House: a little plastered cottage with a pitched roof, porthole window and
## a team-coloured door.
func _house() -> void:
	var s := _size
	var walls := Vector3(s.x - 0.4, 1.4, s.z - 0.5)
	block(self, Vector3(s.x - 0.2, 0.2, s.z - 0.3), 0, 0, 0, STONE)
	block(self, walls, 0, 0.2, 0, PLASTER)
	add_shape(self, roof(Vector3(s.x, 0.85, s.z - 0.2)), Vector3(0, 2.02, 0), _wall)
	block(self, Vector3(s.x - 0.3, 0.08, walls.z + 0.1), 0, 1.58, 0, BRASS)
	var front := walls.z / 2.0
	add_team(self, box(Vector3(0.5, 0.9, 0.08)), Vector3(-0.45, 0.65, front))
	add_shape(self, sphere(0.04), Vector3(-0.3, 0.65, front + 0.06), BRASS)
	window(self, 0.45, 0.95, front + 0.01, 0.42, 0.42, true)
	chimney(self, 0.6, 1.6, -0.4, 0.75, 0.14)


## Research Center: a stepped deco tower with lit window bands and a radio
## mast whose dish turns.
func _research_center() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.3, s.z), 0, 0, 0, STONE)
	var tiers := [Vector3(3.9, 1.3, 3.9), Vector3(3.0, 0.9, 3.0), Vector3(2.1, 0.7, 2.1)]
	var y := 0.3
	for i in tiers.size():
		var t: Vector3 = tiers[i]
		block(self, t, 0, y, 0, _wall.lightened(0.08 * i))
		block(self, Vector3(t.x + 0.08, 0.08, t.z + 0.08), 0, y + t.y - 0.08, 0, BRASS)
		if i == 0:
			for wx in [-1.25, 1.25]:
				window(self, wx, y + t.y * 0.55, t.z / 2.0 + 0.01, 0.8, 0.3)
		else:
			window(self, 0, y + t.y * 0.5, t.z / 2.0 + 0.01, t.x * 0.65, 0.22)
		y += t.y
	band(self, tiers[0], 0.3 + 1.05, 0.0, 0.18)
	# Front fins either side of the door.
	for fx in [-0.55, 0.55]:
		block(self, Vector3(0.14, 2.0, 0.25), fx, 0.3, 1.95, BRASS)
	block(self, Vector3(0.8, 0.9, 0.1), 0, 0.3, 1.95, IRON)
	# Mast and dish.
	drum(self, 0.07, 0.7, 0, y, 0, STEEL, 6)
	var dish := Node3D.new()
	dish.position = Vector3(0, y + 0.65, 0)
	dish.set_meta("spin", Vector3(0, 0.8, 0))
	add_child(dish)
	var bowl := add_shape(dish, cylinder(0.65, 0.22, 16, 0.2), Vector3(0, 0, 0.12), STEEL)
	bowl.rotation.x = -PI / 2.0 + 0.5
	var feed := add_shape(dish, cylinder(0.03, 0.5, 6), Vector3(0, 0.12, 0.35), BRASS)
	feed.rotation.x = -PI / 2.0 + 0.5
	_glow(add_shape(dish, sphere(0.07), Vector3(0, 0.25, 0.58), SPARK, true))
	pennant(self, Vector3(-1.6, 1.6, -1.6), 1.0)


## Soundbeam Tower: a tapering lattice pylon carrying a big brass horn that
## sweeps the approaches.
func _soundbeam_tower() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.3, s.z), 0, 0, 0, STONE)
	var top := 4.3
	var leg_mesh := cylinder(0.08, top - 0.2, 6)
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var c: Vector2 = corner
		var leg := add_shape(self, leg_mesh, Vector3(c.x * 0.7, 0.3 + (top - 0.2) / 2.0, c.y * 0.7), _wall)
		leg.rotation = Vector3(-c.y * 0.12, 0, c.x * 0.12)
	for y in [1.2, 2.3, 3.4]:
		var w := lerpf(2.0, 1.0, (y - 0.3) / top)
		block(self, Vector3(w, 0.08, 0.08), 0, y, w / 2.0, BRASS)
		block(self, Vector3(w, 0.08, 0.08), 0, y, -w / 2.0, BRASS)
		block(self, Vector3(0.08, 0.08, w), w / 2.0, y, 0, BRASS)
		block(self, Vector3(0.08, 0.08, w), -w / 2.0, y, 0, BRASS)
	add_team(self, box(Vector3(1.6, 0.25, 1.6)), Vector3(0, 1.75, 0))
	block(self, Vector3(1.4, 0.15, 1.4), 0, top, 0, IRON)
	# The horn turns on a brass turntable.
	var head := Node3D.new()
	head.position = Vector3(0, top + 0.15, 0)
	head.set_meta("spin", Vector3(0, 0.6, 0))
	add_child(head)
	drum(head, 0.45, 0.2, 0, 0, 0, BRASS, 12)
	_glow(drum(head, 0.3, 0.35, 0, 0.2, 0, SPARK, 10))
	var horn := add_shape(head, cylinder(0.12, 1.1, 14, 0.6), Vector3(0, 0.95, 0.45), BRASS)
	horn.rotation.x = PI / 2.0 - 0.35
	var mouth := add_shape(head, ring(0.6, 0.05), Vector3(0, 1.16, 0.98), COPPER)
	mouth.rotation.x = PI / 2.0 - 0.35
	for i in 3:
		add_shape(head, ring(0.25, 0.04), Vector3(0, 0.6, 0), COPPER).position.y = 0.45 + i * 0.12


## Water Chamber: a blue pump house on the shore with a turning paddle wheel
## and a water tank.
func _water_chamber() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.3, s.z), 0, 0, 0, STONE)
	var house := Vector3(3.2, 1.8, 3.6)
	block(self, house, -0.6, 0.3, 0, _wall)
	add_shape(self, roof(Vector3(house.x + 0.3, 0.7, house.z + 0.2)), Vector3(-0.6, 2.45, 0), IRON)
	band(self, house, 1.9, 0.0, 0.18)
	get_child(get_child_count() - 1).position.x = -0.6
	window(self, -1.3, 1.3, house.z / 2.0 + 0.01, 0.45, 0.45, true)
	window(self, 0.1, 1.3, house.z / 2.0 + 0.01, 0.45, 0.45, true)
	block(self, Vector3(0.8, 1.1, 0.1), -0.6, 0.3, house.z / 2.0, IRON)
	# Paddle wheel on the east wall.
	var wheel := Node3D.new()
	wheel.position = Vector3(1.6, 1.35, 0)
	wheel.rotation.y = PI / 2.0
	add_child(wheel)
	var spinner := Node3D.new()
	spinner.set_meta("spin", Vector3(0, 0, -1.5))
	wheel.add_child(spinner)
	for z in [-0.35, 0.35]:
		var rim := add_shape(spinner, ring(1.0, 0.05), Vector3(0, 0, z), WOOD)
		rim.rotation.x = PI / 2.0
	for i in 8:
		var angle := TAU * i / 8.0
		var paddle := add_shape(spinner, box(Vector3(0.45, 0.06, 0.8)), Vector3(cos(angle), sin(angle), 0) * 0.85, WOOD)
		paddle.rotation.z = angle + PI / 2.0
	add_shape(spinner, cylinder(0.12, 0.9, 8), Vector3.ZERO, IRON).rotation.x = PI / 2.0
	# Tank and pipes behind.
	drum(self, 0.65, 1.4, 1.5, 0.3, -1.5, STEEL, 12)
	add_shape(self, sphere(0.65, true), Vector3(1.5, 1.7, -1.5), BRASS)
	_glow(drum(self, 0.66, 0.15, 1.5, 0.9, -1.5, WATER, 12))
	var pipe := add_shape(self, cylinder(0.1, 1.4, 8), Vector3(1.0, 1.2, -1.3), COPPER)
	pipe.rotation.z = PI / 2.0


## Aviary: a brass birdcage dome on a stone drum, with a weathervane.
func _aviary() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.3, s.z), 0, 0, 0, STONE)
	drum(self, 2.4, 0.7, 0, 0.3, 0, _wall, 16)
	add_team(self, cylinder(2.45, 0.2, 16), Vector3(0, 0.85, 0))
	drum(self, 2.3, 0.08, 0, 1.0, 0, BRASS, 16)
	# Cage bars: straight uprights, then bent in towards the top.
	var bars := 14
	var bar_low := cylinder(0.04, 1.6, 4)
	var bar_high := cylinder(0.04, 1.5, 4)
	for i in bars:
		var angle := TAU * i / bars
		var dir := Vector3(cos(angle), 0, sin(angle))
		add_shape(self, bar_low, dir * 2.2 + Vector3.UP * 1.85, BRASS)
		var upper := add_shape(self, bar_high, dir * 1.65 + Vector3.UP * 3.15, BRASS)
		upper.rotation = Vector3(0, -angle, 0)
		upper.rotate_object_local(Vector3(0, 0, 1), 0.75)
	for y in [1.9, 2.6]:
		add_shape(self, ring(2.2, 0.04), Vector3(0, y, 0), BRASS)
	add_shape(self, ring(1.1, 0.04), Vector3(0, 3.65, 0), BRASS)
	add_shape(self, sphere(1.0, true), Vector3(0, 3.65, 0), COPPER).scale = Vector3(1, 0.55, 1)
	# Perches inside.
	block(self, Vector3(0.12, 1.4, 0.12), 0, 1.0, 0, WOOD)
	block(self, Vector3(1.6, 0.08, 0.08), 0, 2.2, 0, WOOD)
	# Weathervane.
	drum(self, 0.05, 0.6, 0, 4.2, 0, BRASS, 6)
	var vane := Node3D.new()
	vane.position = Vector3(0, 4.7, 0)
	vane.set_meta("spin", Vector3(0, 0.7, 0))
	add_child(vane)
	add_shape(vane, box(Vector3(0.7, 0.05, 0.05)), Vector3.ZERO, BRASS)
	add_team(vane, roof(Vector3(0.3, 0.3, 0.03)), Vector3(-0.35, 0.05, 0)).rotation.z = PI / 2.0


## Workshop: a brick shed with a sawtooth roof, a big gear turning on the
## front, a crane arm and an anvil.
func _workshop() -> void:
	var s := _size
	block(self, Vector3(s.x, 0.25, s.z), 0, 0, 0, STONE)
	var shed := Vector3(s.x - 0.6, 1.6, s.z - 0.8)
	block(self, shed, 0, 0.25, -0.1, BRICK)
	# Sawtooth roof, teeth running left to right.
	for i in 3:
		var z := -0.1 - shed.z / 2.0 + (i + 0.5) * shed.z / 3.0
		# Upright glazed face to the front, slope down to the back.
		var tooth := add_shape(self, roof(Vector3(shed.z / 3.0, 0.7, shed.x), 0.0), Vector3(0, 2.2, z), _wall)
		tooth.rotation.y = PI / 2.0
		var glazing := block(self, Vector3(shed.x - 0.3, 0.5, 0.04), 0, 1.9, z + shed.z / 6.0, VALVE)
		glazing.set_meta("lit", true)
	band(self, shed, 1.75, -0.1, 0.16)
	var front := -0.1 + shed.z / 2.0
	block(self, Vector3(1.4, 1.2, 0.08), -0.5, 0.25, front, IRON)
	add_team(self, box(Vector3(1.5, 0.15, 0.1)), Vector3(-0.5, 1.5, front + 0.01))
	gear(self, Vector3(0.95, 1.15, front + 0.08), 0.5, 1.2)
	gear(self, Vector3(0.95 - 0.5, 0.45, front + 0.12), 0.25, -2.4, COPPER)
	# Crane arm on the roof and an anvil out front.
	drum(self, 0.08, 0.9, -1.4, 1.85, -1.2, IRON, 6)
	var arm := block(self, Vector3(1.4, 0.08, 0.08), -0.85, 2.7, -1.2, IRON)
	arm.rotation.z = -0.1
	block(self, Vector3(0.02, 0.6, 0.02), -0.25, 2.1, -1.2, STEEL)
	block(self, Vector3(0.3, 0.25, 0.25), 1.3, 0.25, front + 0.45, IRON)
	block(self, Vector3(0.45, 0.12, 0.2), 1.3, 0.5, front + 0.45, IRON)
	chimney(self, 1.3, 1.85, -1.4, 0.9, 0.18)


func _fallback() -> void:
	block(self, _size, 0, 0, 0, _wall)
	band(self, _size, _size.y - 0.3)


static func cone(radius: float, height: float) -> CylinderMesh:
	return cylinder(radius, height, 10, 0.0)


func _glow(mesh: MeshInstance3D) -> MeshInstance3D:
	var material := mesh.material_override as StandardMaterial3D
	if not material.emission_enabled:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 1.8
	mesh.set_meta("pulse", true)
	mesh.set_meta("lit", true)
	return mesh


func _art() -> Node3D:
	for extension in [".tscn", ".glb", ".gltf"]:
		var path: String = ART_DIR + id + extension
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				var node := scene.instantiate() as Node3D
				node.set_meta("from_art", true)
				return node
	return null


func _paint_team_parts(root: Node) -> void:
	for node in root.find_children("Team*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = _team_material
