class_name CreatureModel
extends Node3D
## Placeholder 3D model for a hybrid, assembled from simple shapes. Each body
## part is coloured like the animal it came from and scaled by that animal's
## size, so you can read a design at a glance. Faces -Z.
##
## Built at size 1.0; the owner scales the whole node.

const Slot := CreatureDesign.Slot

var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []


func build(design: CreatureDesign) -> void:
	for child in get_children():
		child.queue_free()
	_materials.clear()
	_base_colors.clear()
	var overall := _overall_size(design)

	var torso := design.source(Slot.TORSO)
	_add_box(torso, Vector3(0.7, 0.55, 1.1), Vector3(0, 0.8, 0), 1.0)

	var head := design.source(Slot.HEAD)
	var head_scale := _part_scale(head, overall)
	_add_sphere(head, 0.28 * head_scale, Vector3(0, 1.0 + 0.05 * head_scale, -0.62 - 0.12 * head_scale))
	if head.head_ability == AnimalData.Ability.POISON:
		_add_box(null, Vector3(0.12, 0.08, 0.12), Vector3(0, 0.95, -0.95), 1.0, Color(0.4, 0.9, 0.2))
	elif head.head_ability == AnimalData.Ability.CHARGE:
		var horn := _add_cone(Color(0.9, 0.88, 0.8), 0.08 * head_scale, 0.4 * head_scale,
				Vector3(0, 1.05 + 0.05 * head_scale, -0.8 - 0.3 * head_scale))
		horn.rotation_degrees.x = -70.0

	var front := design.source(Slot.FRONT_LEGS)
	var back := design.source(Slot.BACK_LEGS)
	for side in [-1.0, 1.0]:
		_add_leg(front, _part_scale(front, overall), Vector3(0.24 * side, 0, -0.35))
		var hind_scale := _part_scale(back, overall)
		if back.back_leg_ability == AnimalData.Ability.LEAP:
			# Big jumping thighs.
			_add_sphere(back, 0.17 * hind_scale, Vector3(0.26 * side, 0.6, 0.38))
			_add_leg(back, hind_scale * 1.3, Vector3(0.24 * side, 0, 0.45))
		else:
			_add_leg(back, hind_scale, Vector3(0.24 * side, 0, 0.35))

	var tail := design.source(Slot.TAIL)
	var tail_scale := _part_scale(tail, overall)
	var tail_node := _add_cylinder(tail, 0.06 * tail_scale, 0.6 * tail_scale, Vector3(0, 0.95, 0.75))
	tail_node.rotation_degrees.x = 60.0
	match tail.tail_ability:
		AnimalData.Ability.POISON:
			_add_box(null, Vector3(0.12, 0.2, 0.12), Vector3(0, 1.25, 0.95), 1.0, Color(0.4, 0.9, 0.2))
		AnimalData.Ability.STINK:
			# A big bushy tail.
			_add_sphere(tail, 0.22 * tail_scale, Vector3(0, 1.25, 0.95))
		AnimalData.Ability.QUILLS:
			for i in 5:
				var quill := _add_cylinder(tail, 0.025, 0.55, Vector3((i - 2) * 0.12, 1.15, 0.45))
				quill.rotation_degrees = Vector3(-35.0, 0.0, (i - 2) * 18.0)

	var wings := design.source(Slot.WINGS)
	if wings != null:
		var span := 0.9 * _part_scale(wings, overall)
		for side in [-1.0, 1.0]:
			var wing := _add_box(wings, Vector3(span, 0.05, 0.55), Vector3(side * (0.35 + span / 2.0), 1.05, -0.05), 1.0)
			wing.rotation_degrees.z = side * 12.0


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


static func _overall_size(design: CreatureDesign) -> float:
	var size := 0.0
	for slot: CreatureDesign.Slot in CreatureCombiner.SIZE_WEIGHTS:
		size += design.source(slot).size * CreatureCombiner.SIZE_WEIGHTS[slot]
	return size


## How big a part looks relative to the body it's attached to.
static func _part_scale(animal: AnimalData, overall: float) -> float:
	return clampf(animal.size / overall, 0.6, 1.6)


func _add_leg(animal: AnimalData, scale_factor: float, at: Vector3) -> void:
	if animal.swimming == AnimalData.Swimming.AQUATIC:
		# Fins instead of legs.
		var fin := _add_box(animal, Vector3(0.35, 0.05, 0.25) * scale_factor, at + Vector3(signf(at.x) * 0.15, 0.6, 0), 1.0)
		fin.rotation_degrees.z = signf(at.x) * -25.0
		return
	var length := 0.55
	var radius := 0.08 * scale_factor
	_add_cylinder(animal, radius, length, at + Vector3(0, length / 2.0, 0))


func _add_cone(color: Color, radius: float, height: float, at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	return _add_mesh(mesh, at, color)


func _add_box(animal: AnimalData, box_size: Vector3, at: Vector3, scale_factor: float, color := Color.WHITE) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size * scale_factor
	return _add_mesh(mesh, at, animal.color if animal else color)


func _add_sphere(animal: AnimalData, radius: float, at: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _add_mesh(mesh, at, animal.color)


func _add_cylinder(animal: AnimalData, radius: float, height: float, at: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	return _add_mesh(mesh, at, animal.color)


func _add_mesh(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	_materials.append(material)
	_base_colors.append(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	add_child(instance)
	return instance
