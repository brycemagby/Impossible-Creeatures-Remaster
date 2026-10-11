class_name CreatureModel
extends Node3D
## A hybrid's 3D model, assembled from its animals' body parts on a simple rig
## (hips and knees, neck, tail segments, wing shoulders) and animated in code,
## so one set of animations works on any combination: a trotting walk, idle
## breathing and tail sway, flapping, swimming and an attack snap. Faces -Z.
##
## Parts come from CreatureParts (placeholder low-poly shapes). Real art can
## replace any part without code changes: put a scene at
## ART_DIR/<animal>/<slot>.tscn (or .glb), where slot is torso, head, leg,
## tail or wing, following the origin conventions in CreatureParts.
##
## Built at size 1.0; the owner scales the whole node.

const Slot := CreatureDesign.Slot
const ART_DIR := "res://assets/creatures/"
## Leg swing at full stride (radians) and how far knees bend.
const STRIDE_SWING := 0.55
const KNEE_BEND := 0.7
## Strides per metre travelled, at size 1.0.
const STRIDES_PER_METRE := 0.45
const FLAP_SPEED := 9.0

var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _material_cache := {}
var _parts: CreatureParts

# Rig, looked up by name so duplicated models (the portrait) animate too.
var _body: Node3D
var _neck: Node3D
var _hips: Array[Node3D] = []
var _tail: Array[Node3D] = []
var _tail_rest: Array[float] = []
var _wings: Array[Node3D] = []
var _rig_ready := false
var _body_height := 0.0
var _aquatic := false
var _hopper := false
var _pitch := 0.0
var _flying := false

## Walking speed (m/s) to animate at when not on a creature, e.g. in a
## preview; negative means stand still.
var preview_speed := -1.0

var _phase := 0.0
var _time := 0.0
var _stride := 0.0
var _attack_tween: Tween
var _dying := false


func build(design: CreatureDesign) -> void:
	for child in get_children():
		child.queue_free()
	_materials.clear()
	_base_colors.clear()
	_material_cache.clear()
	_parts = CreatureParts.new(self)
	var overall := _overall_size(design)

	var rig := Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var body := Node3D.new()
	body.name = "Body"
	rig.add_child(body)

	var torso_animal := design.source(Slot.TORSO)
	var torso := _part(torso_animal, "torso", func() -> Node3D: return _parts.torso(torso_animal))
	body.add_child(torso)
	var e: Vector3 = torso.get_meta("extents", CreatureParts.torso_shape(torso_animal))

	var front := design.source(Slot.FRONT_LEGS)
	var back := design.source(Slot.BACK_LEGS)
	var front_scale := _part_scale(front, overall)
	var back_scale := _part_scale(back, overall)
	var front_length := CreatureParts.leg_length(front, true) * clampf(front_scale, 0.8, 1.3)
	var back_length := CreatureParts.leg_length(back) * clampf(back_scale, 0.8, 1.3)
	if back.back_leg_ability == AnimalData.Ability.LEAP:
		back_length *= 1.15
	var aquatic := front.swimming == AnimalData.Swimming.AQUATIC and back.swimming == AnimalData.Swimming.AQUATIC
	# Birds stand on their two hind legs; kangaroo legs hop upright with the
	# front legs held up off the ground.
	var biped := CreatureParts.is_biped(front) and CreatureParts.is_biped(back)
	var hopper := back.back_leg_ability == AnimalData.Ability.LEAP and not aquatic
	var hip_y := -e.y * 0.25
	var hip_z := e.z * 0.33
	var back_hip_z := e.z * 0.05 if biped else hip_z
	var pitch := 0.0
	var height := 0.0
	if biped or hopper:
		pitch = 0.3 if biped else 0.4
		# Lift the body until the back feet touch the ground once tilted.
		height = back_length - (hip_y * cos(pitch) - back_hip_z * sin(pitch))
	elif not aquatic:
		# Longer back legs tip the nose down, longer front legs lift it.
		pitch = atan2(front_length - back_length, hip_z * 2.0)
		height = (front_length + back_length) / 2.0 - hip_y
	height = maxf(height, e.y * 0.5 + 0.15)
	body.position.y = height
	body.rotation.x = pitch
	body.set_meta("height", height)
	body.set_meta("aquatic", aquatic)
	body.set_meta("hopper", hopper)

	var legs := [[front, front_scale, front_length, -hip_z, true, "F"], [back, back_scale, back_length, back_hip_z, false, "B"]]
	if biped:
		legs.pop_front()
	for entry: Array in legs:
		var animal: AnimalData = entry[0]
		for side: float in [-1.0, 1.0]:
			var hip := Node3D.new()
			hip.name = "Hip%s%s" % [entry[5], "L" if side < 0 else "R"]
			hip.position = Vector3(side * e.x * 0.32, hip_y, entry[3])
			hip.rotation.x = -body.rotation.x
			if hopper and entry[4]:
				# Front legs held up and forwards.
				hip.rotation.x = 0.9 - body.rotation.x
				hip.set_meta("tucked", true)
			body.add_child(hip)
			var length: float = entry[2]
			var thickness: float = 0.08 * entry[1]
			var is_front: bool = entry[4]
			var leg := _part(animal, "leg", func() -> Node3D: return _parts.leg(animal, length, thickness, is_front, side))
			if animal.swimming == AnimalData.Swimming.AQUATIC:
				hip.position = Vector3(side * e.x * 0.45, 0.0, entry[3] * 0.6)
				leg.scale.x = side
			hip.add_child(leg)

	var head_animal := design.source(Slot.HEAD)
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, e.y * 0.28, -e.z * 0.46)
	neck.rotation.x = -body.rotation.x * 0.6
	body.add_child(neck)
	var head := _part(head_animal, "head", func() -> Node3D: return _parts.head(head_animal))
	head.scale = Vector3.ONE * _part_scale(head_animal, overall)
	neck.add_child(head)
	if head_animal.head_ability == AnimalData.Ability.POISON:
		_parts.ellipsoid(head, Vector3(0.1, 0.06, 0.1), Vector3(0, -0.1, -0.3), Color(0.4, 0.9, 0.2), true)

	var tail_animal := design.source(Slot.TAIL)
	var tail_base := Node3D.new()
	tail_base.name = "TailBase"
	tail_base.position = Vector3(0, e.y * 0.15, e.z * 0.45)
	body.add_child(tail_base)
	var tail := _part(tail_animal, "tail", func() -> Node3D: return _parts.tail(tail_animal))
	tail.scale = Vector3.ONE * _part_scale(tail_animal, overall)
	tail_base.add_child(tail)

	var wing_animal := design.source(Slot.WINGS)
	if wing_animal != null:
		var span := 0.9 * _part_scale(wing_animal, overall)
		for side: float in [-1.0, 1.0]:
			var shoulder := Node3D.new()
			shoulder.name = "Wing%s" % ("L" if side < 0 else "R")
			shoulder.position = Vector3(side * e.x * 0.4, e.y * 0.35, -e.z * 0.05)
			body.add_child(shoulder)
			var wing := _part(wing_animal, "wing", func() -> Node3D: return _parts.wing(wing_animal, span, side))
			if wing.get_meta("from_art", false) and side < 0:
				wing.scale.x = -1.0
			shoulder.add_child(wing)
	_rig_ready = false


## A Henchman: a little worker in overalls of [param team_material], with a
## flat cap, brass goggles and a sack of coal on its back when carrying.
## Arms hang from the front "hips" so they swing opposite the legs.
func build_henchman(team_material: StandardMaterial3D) -> void:
	for child in get_children():
		child.queue_free()
	_materials.clear()
	_base_colors.clear()
	_material_cache.clear()
	_parts = CreatureParts.new(self)
	var skin := Color(0.93, 0.74, 0.6)
	var leather := Color(0.38, 0.24, 0.14)
	var brass := Color(0.85, 0.65, 0.3)
	var rig := Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var body := Node3D.new()
	body.name = "Body"
	body.position.y = 0.62
	body.set_meta("height", 0.62)
	rig.add_child(body)
	# Overalls, belt and shirt sleeves.
	var torso := _parts.ellipsoid(body, Vector3(0.5, 0.62, 0.36), Vector3(0, 0.3, 0), Color.WHITE)
	torso.material_override = team_material
	_parts.box(body, Vector3(0.48, 0.07, 0.36), Vector3(0, 0.06, 0), leather)
	_parts.box(body, Vector3(0.06, 0.3, 0.02), Vector3(-0.1, 0.38, -0.18), leather)
	_parts.box(body, Vector3(0.06, 0.3, 0.02), Vector3(0.1, 0.38, -0.18), leather)
	var sack := _parts.ellipsoid(body, Vector3(0.38, 0.4, 0.26), Vector3(0, 0.34, 0.28), Color(0.55, 0.45, 0.3))
	sack.name = "Sack"
	_parts.ellipsoid(sack, Vector3(0.6, 0.35, 0.6), Vector3(0, 0.5, 0), CreatureParts.BLACK)
	sack.visible = false
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.name = "HipB%s" % ("L" if side < 0 else "R")
		hip.position = Vector3(side * 0.12, 0.02, 0)
		body.add_child(hip)
		var leg := Node3D.new()
		leg.name = "Leg"
		hip.add_child(leg)
		var thigh := _parts.cylinder(leg, 0.075, 0.32, Vector3(0, -0.16, 0), Color.WHITE)
		thigh.material_override = team_material
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position.y = -0.32
		leg.add_child(knee)
		_parts.cylinder(knee, 0.065, 0.26, Vector3(0, -0.13, 0), team_material.albedo_color.darkened(0.25))
		_parts.box(knee, Vector3(0.13, 0.08, 0.22), Vector3(0, -0.27, -0.04), leather)
		var shoulder := Node3D.new()
		shoulder.name = "HipF%s" % ("L" if side < 0 else "R")
		shoulder.position = Vector3(side * 0.3, 0.5, 0)
		shoulder.set_meta("bend", 1.0)
		body.add_child(shoulder)
		var arm := Node3D.new()
		arm.name = "Arm"
		shoulder.add_child(arm)
		_parts.cylinder(arm, 0.06, 0.26, Vector3(0, -0.13, 0), Color(0.85, 0.82, 0.72))
		var elbow := Node3D.new()
		elbow.name = "Knee"
		elbow.position.y = -0.26
		arm.add_child(elbow)
		_parts.cylinder(elbow, 0.055, 0.22, Vector3(0, -0.11, 0), skin)
		_parts.ellipsoid(elbow, Vector3(0.12, 0.12, 0.12), Vector3(0, -0.25, 0), leather)
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.62, 0)
	body.add_child(neck)
	_parts.ellipsoid(neck, Vector3(0.34, 0.36, 0.34), Vector3(0, 0.16, 0), skin)
	# A big goofy nose, a flat cap and goggles pushed up on the forehead.
	_parts.ellipsoid(neck, Vector3(0.11, 0.1, 0.14), Vector3(0, 0.12, -0.18), skin.darkened(0.12))
	_parts.ellipsoid(neck, Vector3(0.38, 0.12, 0.38), Vector3(0, 0.3, 0.01), leather)
	_parts.box(neck, Vector3(0.3, 0.03, 0.14), Vector3(0, 0.27, -0.2), leather)
	for side: float in [-1.0, 1.0]:
		var lens := _parts.cylinder(neck, 0.055, 0.05, Vector3(side * 0.08, 0.22, -0.16), brass)
		lens.rotation_degrees.x = 90.0
		_parts.ellipsoid(neck, Vector3(0.06, 0.06, 0.02), Vector3(side * 0.08, 0.22, -0.19), Color(0.5, 0.9, 0.9), true)
		_parts.ellipsoid(neck, Vector3(0.05, 0.05, 0.03), Vector3(side * 0.07, 0.15, -0.16), CreatureParts.BLACK)
	_parts.box(neck, Vector3(0.36, 0.03, 0.3), Vector3(0, 0.22, 0.0), leather)
	_rig_ready = false


## Makes the whole model see-through (camouflaged, as its owner sees it) or solid.
func set_ghostly(ghostly: bool) -> void:
	for i in _materials.size():
		_base_colors[i].a = 0.35 if ghostly else 1.0
		_materials[i].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if ghostly else BaseMaterial3D.TRANSPARENCY_DISABLED
		_materials[i].albedo_color = _base_colors[i]


## Briefly whitens every part (hit feedback).
func flash() -> void:
	for i in _materials.size():
		var material := _materials[i]
		material.albedo_color = Color.WHITE
		create_tween().tween_property(material, "albedo_color", _base_colors[i], 0.15)


## The death pratfall, timed to the slide-whistle sound: a startled hop,
## then the creature keels over onto its side with a bounce, legs stiff in
## the air, head lolling, and its legs give a last twitch. Then use fade().
func die() -> void:
	_resolve_rig()
	_dying = true
	if _attack_tween:
		_attack_tween.kill()
	var rig := get_node_or_null("Rig") as Node3D
	if rig == null:
		return
	var side := -1.0 if randf() < 0.5 else 1.0
	# Tipping over about the feet would sink the body into the ground, so the
	# rig also slides back over the spot and lifts by half the body's width.
	var height := _body_height if _body != null else 0.5
	var half_width := 0.25
	if _body != null:
		for child in _body.get_children():
			if child.has_meta("extents"):
				half_width = (child.get_meta("extents") as Vector3).x / 2.0
				break
	var hop := create_tween()
	hop.tween_property(rig, "position:y", 0.35 + half_width, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(rig, "position:y", half_width, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var topple := create_tween()
	topple.tween_interval(0.1)
	topple.tween_property(rig, "rotation:z", side * PI / 2.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	topple.parallel().tween_property(rig, "position:x", side * height, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	topple.tween_callback(_dust)
	if _body == null:
		return
	var limp := create_tween().set_parallel()
	for i in _hips.size():
		if _hips[i].get_child_count() == 0:
			continue
		var leg := _hips[i].get_child(0) as Node3D
		# Legs splay stiffly, front ones forwards and back ones back.
		limp.tween_property(leg, "rotation:x", 0.45 if i < 2 else -0.45, 0.25)
		var knee := leg.get_node_or_null("Knee") as Node3D
		if knee != null:
			limp.tween_property(knee, "rotation:x", 0.0, 0.25)
			var twitch := create_tween()
			twitch.tween_interval(0.75 + i * 0.05)
			for k in 2:
				twitch.tween_property(knee, "rotation:x", 0.5, 0.06)
				twitch.tween_property(knee, "rotation:x", 0.0, 0.1)
				twitch.tween_interval(0.12)
	if _neck != null:
		limp.tween_property(_neck, "rotation", Vector3(0.5, 0.0, side * 0.3), 0.4)
	for seg in _tail:
		limp.tween_property(seg, "rotation", Vector3.ZERO, 0.4)
	for wing in _wings:
		var wing_side := -1.0 if wing.name.ends_with("L") else 1.0
		limp.tween_property(wing, "rotation", Vector3(0.0, 0.0, wing_side * 0.9), 0.3)


## Fades the whole model out over [param duration] seconds.
func fade(duration: float) -> void:
	var seen := {}
	var tween := create_tween().set_parallel()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := mesh.material_override as StandardMaterial3D
		if material == null or seen.has(material):
			continue
		seen[material] = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(material, "albedo_color:a", 0.0, duration)


## A ring of dust puffs where the body hits the ground.
func _dust() -> void:
	var owner_node := get_parent() as Node3D
	if owner_node == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.66, 0.52, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = 0.16 * scale.x
	mesh.height = 0.32 * scale.x
	mesh.radial_segments = 8
	mesh.rings = 4
	var tween := owner_node.create_tween().set_parallel()
	var count := 6
	for i in count:
		var puff := MeshInstance3D.new()
		puff.name = "Dust%d" % i
		puff.mesh = mesh
		puff.material_override = material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / count + randf() * 0.4)
		puff.position = direction * 0.3 * scale.x + Vector3.UP * 0.1
		owner_node.add_child(puff)
		tween.tween_property(puff, "position", puff.position + direction * 0.7 * scale.x + Vector3.UP * 0.25, 0.6) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "scale", Vector3.ONE * 1.8, 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.6)


## A bite and a swipe: the head snaps forward and the front legs strike.
func attack() -> void:
	_resolve_rig()
	if _neck == null:
		return
	if _attack_tween:
		_attack_tween.kill()
	_attack_tween = create_tween().set_parallel()
	var rest := _neck.rotation.x
	_attack_tween.tween_property(_neck, "rotation:x", rest + 0.45, 0.07)
	_attack_tween.chain().tween_property(_neck, "rotation:x", rest, 0.18)
	for hip in _hips.slice(0, 2):
		if hip.get_child_count() == 0:
			continue
		var knee := hip.get_child(0).get_node_or_null("Knee") as Node3D
		if knee != null:
			var swipe := create_tween()
			swipe.tween_property(knee, "rotation:x", 0.9, 0.07)
			swipe.tween_property(knee, "rotation:x", 0.0, 0.2)


## Adds a shape for CreatureParts, sharing one material per colour.
func add_shape(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	# A touch darker than the animal's swatch colour, so bright coats don't
	# wash out under the map's sun.
	if not glow:
		color = color.darkened(0.12)
	var key := [color, glow]
	var material: StandardMaterial3D = _material_cache.get(key)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.75
		if glow:
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 1.5
		_material_cache[key] = material
		_materials.append(material)
		_base_colors.append(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


# --- Animation ----------------------------------------------------------------

func _process(delta: float) -> void:
	_resolve_rig()
	if _body == null or _dying:
		return
	_time += delta
	var creature := get_parent() as Creature
	var speed := maxf(preview_speed, 0.0)
	if creature != null and creature.is_alive():
		speed = Vector2(creature.velocity.x, creature.velocity.z).length() / maxf(scale.x, 0.1)
		_flying = creature.stats.can_fly
		if creature is Henchman:
			var sack := _body.get_node_or_null("Sack") as Node3D
			if sack != null:
				sack.visible = creature.carried_coal > 0
	# Ease in and out of the stride rather than snapping.
	_stride = move_toward(_stride, clampf(speed / 2.5, 0.0, 1.0), delta * 4.0)
	var rate := STRIDES_PER_METRE * (0.6 if _hopper else 1.0)
	_phase = fmod(_phase + TAU * speed * rate * delta, TAU)

	var breathe := sin(_time * 2.2) * 0.012
	if _hopper:
		_animate_hop(delta, breathe)
	elif _aquatic:
		_body.position.y = _body_height + sin(_time * 1.6) * 0.04
		_body.rotation.y = sin(_time * 3.0 + _phase) * (0.06 + 0.1 * _stride)
	else:
		_body.position.y = _body_height + absf(sin(_phase)) * 0.05 * _stride + breathe
		_body.rotation.z = sin(_phase) * 0.03 * _stride

	for i in _hips.size():
		var hip := _hips[i]
		var leg := hip.get_child(0) if hip.get_child_count() > 0 else null
		if leg == null or _hopper:
			continue
		# Trot: front-left with back-right, front-right with back-left.
		var offset := 0.0 if i == 0 or i == 3 else PI
		var swing := sin(_phase + offset)
		if _aquatic:
			leg.rotation.z = sin(_time * 4.0 + offset) * 0.35
			continue
		if _flying:
			leg.rotation.x = lerpf(leg.rotation.x, 0.7, delta * 4.0)
			continue
		if leg.get_meta("splay", false):
			# Splayed legs sweep forwards and back in a ripple.
			var k := 0
			for pivot in leg.get_children():
				if pivot.name.begins_with("Splay"):
					pivot.rotation.y = pivot.get_meta("rest_yaw", 0.0) + sin(_phase * 2.0 + offset + k * 2.1) * 0.3 * _stride
					k += 1
			continue
		leg.rotation.x = swing * STRIDE_SWING * _stride
		var knee := leg.get_node_or_null("Knee") as Node3D
		if knee != null and (_attack_tween == null or not _attack_tween.is_running() or i > 1):
			# Knees fold the lower leg back; elbows (meta "bend": 1) fold forwards.
			var bend: float = hip.get_meta("bend", -1.0)
			knee.rotation.x = bend * maxf(0.0, cos(_phase + offset)) * KNEE_BEND * _stride

	if _neck != null and (_attack_tween == null or not _attack_tween.is_running()):
		_neck.rotation.z = sin(_time * 0.7) * 0.06 * (1.0 - _stride)
		_neck.rotation.y = sin(_time * 0.45) * 0.18 * (1.0 - _stride)

	var wag := 0.25 + 0.2 * _stride
	for i in _tail.size():
		_tail[i].rotation.y = sin(_time * 2.6 - i * 0.7) * wag * (0.4 + i * 0.15)
		var balance := -cos(_phase) * 0.15 * _stride if _hopper else 0.0
		_tail[i].rotation.x = _tail_rest[i] + sin(_time * 1.3 - i * 0.5) * 0.05 + balance

	for wing in _wings:
		var side := -1.0 if wing.name.ends_with("L") else 1.0
		if _flying:
			wing.rotation.z = side * sin(_time * FLAP_SPEED) * 0.6
		else:
			# Folded back along the body.
			wing.rotation.z = side * -0.35
			wing.rotation.y = side * -0.9


## Kangaroo legs: both hind legs push off together and the body bounds along
## in arcs, tail swinging to balance; the front legs stay tucked up.
func _animate_hop(delta: float, breathe: float) -> void:
	var air := maxf(0.0, sin(_phase))
	_body.position.y = _body_height + air * 0.35 * _stride + breathe
	_body.rotation.x = _pitch + cos(_phase) * 0.12 * _stride
	for hip in _hips:
		if hip.get_child_count() == 0:
			continue
		var leg := hip.get_child(0) as Node3D
		var knee := leg.get_node_or_null("Knee") as Node3D
		if hip.get_meta("tucked", false):
			if knee != null and (_attack_tween == null or not _attack_tween.is_running()):
				knee.rotation.x = lerpf(knee.rotation.x, 0.9, delta * 6.0)
			continue
		# Legs trail behind in the air and swing forwards to land.
		leg.rotation.x = (-0.6 * air + 0.35 * cos(_phase)) * _stride
		if knee != null:
			knee.rotation.x = -(1.0 - air) * 0.5 * _stride


func _resolve_rig() -> void:
	if _rig_ready:
		return
	_body = get_node_or_null("Rig/Body") as Node3D
	if _body == null or _body.is_queued_for_deletion():
		_body = null
		return
	_rig_ready = true
	_body_height = _body.get_meta("height", _body.position.y)
	_aquatic = _body.get_meta("aquatic", false)
	_hopper = _body.get_meta("hopper", false)
	_pitch = _body.rotation.x
	_neck = _body.get_node_or_null("Neck") as Node3D
	_hips.clear()
	_wings.clear()
	for hip_name: String in ["HipFL", "HipFR", "HipBL", "HipBR"]:
		var hip := _body.get_node_or_null(hip_name) as Node3D
		if hip != null:
			_hips.append(hip)
	for wing_name: String in ["WingL", "WingR"]:
		var wing := _body.get_node_or_null(wing_name) as Node3D
		if wing != null:
			_wings.append(wing)
	_tail.clear()
	_tail_rest.clear()
	var tail_base := _body.get_node_or_null("TailBase")
	var node: Node = tail_base.get_child(0) if tail_base != null and tail_base.get_child_count() > 0 else null
	if node != null:
		node = node.get_node_or_null("Seg0")
	while node != null:
		_tail.append(node)
		_tail_rest.append(node.rotation.x)
		var next: Node = null
		for child in node.get_children():
			if child.name.begins_with("Seg"):
				next = child
		node = next


# --- Building -----------------------------------------------------------------

## A drop-in art scene for [param slot] of [param animal] if there is one,
## otherwise the placeholder from [param fallback].
func _part(animal: AnimalData, slot: String, fallback: Callable) -> Node3D:
	var id := CreatureParts.id_of(animal)
	for extension in [".tscn", ".glb", ".gltf"]:
		var path: String = ART_DIR + id + "/" + slot + extension
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				var node := scene.instantiate() as Node3D
				node.set_meta("from_art", true)
				return node
	return fallback.call()


static func _overall_size(design: CreatureDesign) -> float:
	var size := 0.0
	for slot: CreatureDesign.Slot in CreatureCombiner.SIZE_WEIGHTS:
		size += design.source(slot).size * CreatureCombiner.SIZE_WEIGHTS[slot]
	return size


## How big a part looks relative to the body it's attached to.
static func _part_scale(animal: AnimalData, overall: float) -> float:
	return clampf(animal.size / overall, 0.6, 1.6)
