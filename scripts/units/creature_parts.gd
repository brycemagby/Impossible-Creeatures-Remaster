class_name CreatureParts
extends RefCounted
## Builds each animal's body parts for CreatureModel out of simple low-poly
## shapes: a stand-in until hand-made models replace them (see
## CreatureModel.ART_DIR for dropping in real art per part).
##
## Conventions, at a lion-sized scale of 1.0, facing -Z:
## - torso: origin at the body's centre; sets the "extents" meta (width,
##   height, length) that CreatureModel places the other parts from.
## - head: origin at the neck joint, extending forwards (-Z).
## - leg: origin at the hip, hanging down to the ground at -length. The
##   lower half sits under a "Knee" child so it can bend.
## - tail: origin at the base, extending backwards (+Z) as a chain of
##   "Seg" pivots, each a child of the one before, so it can sway.
## - wing: origin at the shoulder, extending sideways towards [param side].

const BLACK := Color(0.06, 0.05, 0.05)
const WHITE := Color(0.95, 0.93, 0.88)
const IVORY := Color(0.93, 0.9, 0.78)
const PINK := Color(0.85, 0.5, 0.5)
const YELLOW := Color(0.95, 0.75, 0.2)

## Second colours (manes, bellies, markings) per animal id.
const ACCENTS := {
	"lion": Color(0.55, 0.3, 0.12),
	"cheetah": Color(0.98, 0.92, 0.75),
	"wolf": Color(0.82, 0.82, 0.84),
	"eagle": WHITE,
	"elephant": Color(0.45, 0.45, 0.5),
	"rhino": Color(0.42, 0.38, 0.33),
	"bison": Color(0.25, 0.16, 0.1),
	"gorilla": Color(0.42, 0.38, 0.38),
	"kangaroo": Color(0.9, 0.78, 0.62),
	"bat": Color(0.45, 0.35, 0.42),
	"crocodile": Color(0.75, 0.75, 0.5),
	"scorpion": Color(0.45, 0.35, 0.22),
	"shark": WHITE,
	"electric_eel": Color(0.55, 0.85, 0.95),
	"porcupine": Color(0.85, 0.8, 0.7),
	"skunk": WHITE,
	"chameleon": Color(0.9, 0.75, 0.25),
}

## Torso shape per animal: width, height, length (lion: 0.6, 0.55, 1.1).
const TORSO_SHAPES := {
	"lion": Vector3(0.6, 0.55, 1.1), "cheetah": Vector3(0.5, 0.45, 1.15), "wolf": Vector3(0.52, 0.5, 1.05),
	"eagle": Vector3(0.5, 0.5, 0.85), "elephant": Vector3(0.8, 0.75, 1.15), "rhino": Vector3(0.72, 0.65, 1.15),
	"bison": Vector3(0.7, 0.65, 1.1), "gorilla": Vector3(0.75, 0.75, 0.85), "kangaroo": Vector3(0.55, 0.6, 0.9),
	"bat": Vector3(0.5, 0.45, 0.75), "crocodile": Vector3(0.65, 0.35, 1.3), "scorpion": Vector3(0.65, 0.3, 1.0),
	"shark": Vector3(0.55, 0.6, 1.35), "electric_eel": Vector3(0.38, 0.4, 1.45), "porcupine": Vector3(0.6, 0.5, 0.9),
	"skunk": Vector3(0.55, 0.45, 0.95), "chameleon": Vector3(0.45, 0.55, 0.95),
}

## Leg length per animal (lion: 0.55); a hybrid's body rests on its legs.
const LEG_LENGTHS := {
	"elephant": 0.7, "rhino": 0.55, "bison": 0.6, "cheetah": 0.62, "wolf": 0.58, "gorilla": 0.6,
	"kangaroo": 0.62, "crocodile": 0.32, "scorpion": 0.35, "porcupine": 0.38, "skunk": 0.38,
	"chameleon": 0.42, "bat": 0.4, "eagle": 0.5,
}

## Front legs relative to back legs, where they differ (kangaroo arms are short).
const FRONT_LEG_FACTORS := {"kangaroo": 0.75, "gorilla": 1.1}

var model: CreatureModel


func _init(owner_model: CreatureModel) -> void:
	model = owner_model


static func id_of(animal: AnimalData) -> String:
	if animal == null:
		return ""
	var file := animal.resource_path.get_file().get_basename()
	return file if file != "" else animal.display_name.to_snake_case()


static func leg_length(animal: AnimalData, front := false) -> float:
	if animal.swimming == AnimalData.Swimming.AQUATIC:
		return 0.0
	var length: float = LEG_LENGTHS.get(id_of(animal), 0.55)
	return length * FRONT_LEG_FACTORS.get(id_of(animal), 1.0) if front else length


static func torso_shape(animal: AnimalData) -> Vector3:
	return TORSO_SHAPES.get(id_of(animal), Vector3(0.6, 0.55, 1.1))


func accent(animal: AnimalData) -> Color:
	return ACCENTS.get(id_of(animal), animal.color.lightened(0.3))


# --- Torso --------------------------------------------------------------------

func torso(animal: AnimalData) -> Node3D:
	var id := id_of(animal)
	var e := torso_shape(animal)
	var root := Node3D.new()
	root.name = "Torso"
	root.set_meta("extents", e)
	var c := animal.color
	var a := accent(animal)
	match id:
		"elephant", "rhino", "gorilla", "porcupine", "skunk", "bat":
			ellipsoid(root, e * Vector3(1.0, 1.0, 1.0), Vector3.ZERO, c)
		"shark", "electric_eel":
			ellipsoid(root, e, Vector3.ZERO, c)
			ellipsoid(root, e * Vector3(0.8, 0.5, 0.85), Vector3(0, -e.y * 0.22, 0), a)
		_:
			# A chest and a haunch blended into one body.
			ellipsoid(root, Vector3(e.x, e.y, e.z * 0.62), Vector3(0, 0.02, -e.z * 0.2), c)
			ellipsoid(root, Vector3(e.x * 0.92, e.y * 0.92, e.z * 0.6), Vector3(0, 0, e.z * 0.2), c)
	match id:
		"lion":
			ellipsoid(root, Vector3(e.x * 0.7, e.y * 0.4, e.z * 0.7), Vector3(0, -e.y * 0.3, 0), a.lightened(0.6))
		"cheetah":
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 14:
				var side := -1.0 if i % 2 == 0 else 1.0
				var at := Vector3(side * e.x * rng.randf_range(0.32, 0.46), rng.randf_range(-0.1, 0.4) * e.y,
						rng.randf_range(-0.42, 0.42) * e.z)
				ellipsoid(root, Vector3(0.07, 0.07, 0.07), at, BLACK)
		"wolf":
			ellipsoid(root, Vector3(e.x * 1.1, e.y * 1.05, e.z * 0.35), Vector3(0, 0.03, -e.z * 0.33), a)
		"eagle":
			ellipsoid(root, Vector3(e.x * 0.7, e.y * 0.6, e.z * 0.5), Vector3(0, -e.y * 0.1, -e.z * 0.25), c.lightened(0.15))
		"elephant", "rhino":
			for side in [-1.0, 1.0]:
				ellipsoid(root, Vector3(0.05, e.y * 0.6, e.z * 0.7), Vector3(side * e.x * 0.48, 0.0, 0.0), a)
		"bison":
			ellipsoid(root, Vector3(e.x * 1.05, e.y * 0.9, e.z * 0.55), Vector3(0, e.y * 0.35, -e.z * 0.18), a)
		"gorilla":
			ellipsoid(root, Vector3(e.x * 0.7, e.y * 0.6, e.z * 0.3), Vector3(0, -0.02, -e.z * 0.4), a)
		"kangaroo":
			ellipsoid(root, Vector3(e.x * 0.6, e.y * 0.5, e.z * 0.3), Vector3(0, -e.y * 0.2, -e.z * 0.38), a)
		"crocodile", "chameleon":
			for i in 6:
				var z := lerpf(-0.4, 0.4, i / 5.0) * e.z
				cone(root, 0.06, 0.12, Vector3(0, e.y * 0.48, z), a if id == "chameleon" else c.darkened(0.3))
		"scorpion":
			for i in 4:
				ellipsoid(root, Vector3(e.x * 1.02, 0.06, 0.05), Vector3(0, e.y * 0.3, lerpf(-0.3, 0.35, i / 3.0) * e.z), a)
		"shark":
			var fin := cone(root, 0.18, 0.45, Vector3(0, e.y * 0.6, 0.05), animal.color)
			fin.scale = Vector3(0.3, 1.0, 1.0)
			fin.rotation_degrees.x = 20.0
		"electric_eel":
			for i in 5:
				ellipsoid(root, Vector3(0.04, 0.04, 0.12), Vector3(0, e.y * 0.42, lerpf(-0.4, 0.4, i / 4.0) * e.z),
						a, true)
		"porcupine":
			_quills(root, e, 26, a)
		"skunk":
			ellipsoid(root, Vector3(e.x * 0.35, e.y * 0.25, e.z * 1.02), Vector3(0, e.y * 0.42, 0), WHITE)
		"bat":
			ellipsoid(root, Vector3(e.x * 0.8, e.y * 0.6, e.z * 0.6), Vector3(0, -0.05, -e.z * 0.2), a)
	return root


func _quills(root: Node3D, e: Vector3, count: int, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in count:
		var angle := rng.randf_range(-1.2, 1.2)
		var z := rng.randf_range(-0.4, 0.45) * e.z
		var at := Vector3(sin(angle) * e.x * 0.45, cos(angle) * e.y * 0.45, z)
		var quill := cone(root, 0.025, 0.4, at, color)
		quill.rotation = Vector3(deg_to_rad(55.0), 0.0, -angle)
		ellipsoid(quill, Vector3(0.03, 0.08, 0.03), Vector3(0, 0.17, 0), BLACK)


# --- Head ---------------------------------------------------------------------

func head(animal: AnimalData) -> Node3D:
	var id := id_of(animal)
	var root := Node3D.new()
	root.name = "Head"
	var c := animal.color
	var a := accent(animal)
	match id:
		"lion":
			ellipsoid(root, Vector3(0.62, 0.62, 0.42), Vector3(0, 0.02, -0.08), a)
			_skull(root, c, 0.4, 0.38)
			_muzzle(root, c.lightened(0.15), Vector3(0.22, 0.16, 0.2), -0.3)
			_ears(root, c, 0.08, 0.17, 0.18, false)
		"cheetah":
			_skull(root, c, 0.32, 0.34)
			_muzzle(root, a, Vector3(0.17, 0.12, 0.16), -0.26)
			_ears(root, c, 0.06, 0.13, 0.14, false)
			for side in [-1.0, 1.0]:
				box(root, Vector3(0.025, 0.12, 0.02), Vector3(side * 0.07, -0.01, -0.29), BLACK)
		"wolf":
			_skull(root, c, 0.34, 0.36)
			var snout := ellipsoid(root, Vector3(0.17, 0.15, 0.36), Vector3(0, -0.05, -0.32), c)
			snout.rotation_degrees.x = 5.0
			ellipsoid(root, Vector3(0.15, 0.07, 0.3), Vector3(0, -0.1, -0.3), a)
			ellipsoid(root, Vector3(0.07, 0.06, 0.06), Vector3(0, -0.01, -0.5), BLACK)
			_ears(root, c, 0.07, 0.2, 0.13, true)
		"eagle":
			_skull(root, WHITE, 0.3, 0.3)
			var beak := cone(root, 0.07, 0.24, Vector3(0, -0.02, -0.28), YELLOW)
			beak.rotation_degrees.x = -110.0
			_eyes(root, 0.12, 0.05, -0.1, 0.04)
			return root
		"elephant":
			_skull(root, c, 0.55, 0.55)
			for side in [-1.0, 1.0]:
				var ear := ellipsoid(root, Vector3(0.05, 0.4, 0.32), Vector3(side * 0.3, 0.06, 0.12), c.darkened(0.08))
				ear.rotation_degrees.y = side * 35.0
				var tusk := cone(root, 0.04, 0.32, Vector3(side * 0.12, -0.2, -0.32), IVORY)
				tusk.rotation_degrees.x = -105.0
			_trunk(root, c)
		"rhino":
			var skull := ellipsoid(root, Vector3(0.34, 0.32, 0.62), Vector3(0, -0.04, -0.22), c)
			skull.rotation_degrees.x = 14.0
			ellipsoid(root, Vector3(0.26, 0.2, 0.2), Vector3(0, -0.13, -0.47), c.lightened(0.08))
			var horn := cone(root, 0.09, 0.38, Vector3(0, 0.02, -0.46), IVORY)
			horn.rotation_degrees.x = -25.0
			var small := cone(root, 0.06, 0.18, Vector3(0, 0.07, -0.28), IVORY)
			small.rotation_degrees.x = -15.0
			_ears(root, c, 0.05, 0.14, 0.12, true, 0.06)
		"bison":
			ellipsoid(root, Vector3(0.5, 0.48, 0.45), Vector3(0, 0.02, -0.08), a)
			_skull(root, c, 0.36, 0.36)
			_muzzle(root, c.darkened(0.2), Vector3(0.24, 0.18, 0.16), -0.28)
			for side in [-1.0, 1.0]:
				var horn := cone(root, 0.05, 0.22, Vector3(side * 0.22, 0.14, -0.1), IVORY)
				horn.rotation_degrees = Vector3(0, 0, -side * 70.0)
		"gorilla":
			_skull(root, c, 0.4, 0.42)
			ellipsoid(root, Vector3(0.28, 0.24, 0.12), Vector3(0, -0.05, -0.19), a)
			box(root, Vector3(0.3, 0.06, 0.1), Vector3(0, 0.06, -0.17), c)
		"kangaroo":
			_skull(root, c, 0.28, 0.3)
			var snout := ellipsoid(root, Vector3(0.14, 0.13, 0.26), Vector3(0, -0.04, -0.2), c.lightened(0.1))
			snout.rotation_degrees.x = 10.0
			_ears(root, c, 0.06, 0.26, 0.08, true)
		"bat":
			_skull(root, c, 0.3, 0.28)
			_muzzle(root, a, Vector3(0.12, 0.1, 0.1), -0.18)
			_ears(root, c, 0.09, 0.28, 0.1, true)
			for side in [-1.0, 1.0]:
				var fang := cone(root, 0.015, 0.06, Vector3(side * 0.03, -0.09, -0.2), WHITE)
				fang.rotation_degrees.x = 180.0
		"crocodile":
			box(root, Vector3(0.32, 0.18, 0.3), Vector3(0, 0, -0.08), c)
			box(root, Vector3(0.24, 0.08, 0.5), Vector3(0, 0.0, -0.45), c)
			box(root, Vector3(0.22, 0.06, 0.48), Vector3(0, -0.08, -0.44), a)
			for i in 6:
				for side in [-1.0, 1.0]:
					var tooth := cone(root, 0.015, 0.05, Vector3(side * 0.11, -0.04, -0.28 - i * 0.07), WHITE)
					tooth.rotation_degrees.x = 180.0
			_eyes(root, 0.1, 0.05, -0.12, 0.1)
			return root
		"scorpion":
			ellipsoid(root, Vector3(0.36, 0.16, 0.3), Vector3(0, 0, -0.1), c)
			_eyes(root, 0.05, 0.03, -0.2, 0.06)
			return root
		"shark":
			var snout := ellipsoid(root, Vector3(0.42, 0.4, 0.6), Vector3(0, 0, -0.2), c)
			snout.rotation_degrees.x = 5.0
			ellipsoid(root, Vector3(0.3, 0.12, 0.4), Vector3(0, -0.13, -0.2), a)
			for i in 5:
				var tooth := cone(root, 0.015, 0.05, Vector3((i - 2) * 0.05, -0.1, -0.42 + absf(i - 2) * 0.03), WHITE)
				tooth.rotation_degrees.x = 180.0
			_eyes(root, 0.17, 0.04, -0.3, 0.04)
			return root
		"electric_eel":
			ellipsoid(root, Vector3(0.3, 0.28, 0.42), Vector3(0, 0, -0.14), c)
			ellipsoid(root, Vector3(0.22, 0.1, 0.3), Vector3(0, -0.09, -0.16), a)
			_eyes(root, 0.1, 0.035, -0.26, 0.05)
			return root
		"porcupine":
			_skull(root, c.lightened(0.15), 0.26, 0.28)
			var snout := cone(root, 0.09, 0.2, Vector3(0, -0.04, -0.24), c.lightened(0.15))
			snout.rotation_degrees.x = -90.0
			ellipsoid(root, Vector3(0.05, 0.05, 0.05), Vector3(0, -0.04, -0.34), BLACK)
			_ears(root, c, 0.04, 0.06, 0.1, false)
		"skunk":
			_skull(root, c, 0.28, 0.3)
			_muzzle(root, c, Vector3(0.12, 0.1, 0.14), -0.22)
			box(root, Vector3(0.05, 0.03, 0.3), Vector3(0, 0.12, -0.1), WHITE)
			_ears(root, c, 0.05, 0.08, 0.1, false)
		"chameleon":
			_skull(root, c, 0.26, 0.3)
			var casque := cone(root, 0.12, 0.26, Vector3(0, 0.15, 0.05), c.darkened(0.1))
			casque.rotation_degrees.x = 35.0
			for side in [-1.0, 1.0]:
				ellipsoid(root, Vector3(0.12, 0.12, 0.12), Vector3(side * 0.13, 0.04, -0.08), a)
				ellipsoid(root, Vector3(0.04, 0.04, 0.04), Vector3(side * 0.18, 0.05, -0.1), BLACK)
			return root
		_:
			_skull(root, c, 0.36, 0.36)
			_muzzle(root, c.lightened(0.1), Vector3(0.18, 0.14, 0.16), -0.27)
	_eyes(root, 0.1, 0.05, -0.2, 0.08)
	return root


func _skull(root: Node3D, color: Color, width: float, length: float) -> void:
	ellipsoid(root, Vector3(width, width * 0.92, length), Vector3(0, 0, -length * 0.35), color)


func _muzzle(root: Node3D, color: Color, size: Vector3, z: float) -> void:
	ellipsoid(root, size, Vector3(0, -0.05, z), color)
	ellipsoid(root, Vector3(0.07, 0.05, 0.05), Vector3(0, -0.01, z - size.z * 0.45), BLACK)


func _ears(root: Node3D, color: Color, radius: float, height: float, spread: float, pointy: bool, z := 0.0) -> void:
	for side in [-1.0, 1.0]:
		var ear: MeshInstance3D
		if pointy:
			ear = cone(root, radius, height, Vector3(side * spread, 0.15 + height * 0.35, z - 0.05), color)
		else:
			ear = ellipsoid(root, Vector3(radius * 2.0, height, radius), Vector3(side * spread, 0.16, z - 0.05), color)
		ear.rotation_degrees.z = -side * 15.0


func _eyes(root: Node3D, spread: float, size: float, z: float, y: float) -> void:
	for side in [-1.0, 1.0]:
		ellipsoid(root, Vector3.ONE * size * 1.3, Vector3(side * spread, y, z), WHITE)
		ellipsoid(root, Vector3.ONE * size, Vector3(side * spread * 1.05, y, z - size * 0.35), BLACK)


func _trunk(root: Node3D, color: Color) -> void:
	var parent: Node3D = root
	var at := Vector3(0, -0.05, -0.4)
	for i in 4:
		var joint := Node3D.new()
		joint.name = "Seg%d" % i
		joint.position = at
		joint.rotation_degrees.x = 12.0 if i == 0 else -14.0
		parent.add_child(joint)
		var radius := 0.09 - i * 0.015
		cylinder(joint, radius, 0.2, Vector3(0, -0.1, 0), color)
		parent = joint
		at = Vector3(0, -0.19, 0)


# --- Legs ---------------------------------------------------------------------

## A leg hanging from the hip, [param length] long. [param front] picks the
## front variant where animals differ (pincers, gorilla arms, kangaroo feet).
func leg(animal: AnimalData, length: float, thickness: float, front: bool, side := 1.0) -> Node3D:
	var id := id_of(animal)
	var root := Node3D.new()
	root.name = "Leg"
	var c := animal.color
	var upper := length * 0.5
	var t := thickness
	if id == "scorpion":
		_scorpion_legs(root, animal, length, thickness / 0.08, front, side)
		return root
	if animal.swimming == AnimalData.Swimming.AQUATIC:
		var fin := ellipsoid(root, Vector3(0.36, 0.05, 0.22) * t / 0.08, Vector3(0.12, 0, 0), c.darkened(0.1))
		fin.rotation_degrees.z = -25.0
		var knee_fin := Node3D.new()
		knee_fin.name = "Knee"
		root.add_child(knee_fin)
		return root
	match id:
		"elephant", "rhino":
			t *= 1.7
		"bison", "gorilla":
			t *= 1.35
		"eagle", "bat", "chameleon", "scorpion":
			t *= 0.6
	# Upper leg: a thigh tapering to the knee.
	var thigh_color := c
	if id == "cheetah" or id == "lion":
		thigh_color = c.darkened(0.05)
	ellipsoid(root, Vector3(t * 2.6, upper * 1.25, t * 2.8), Vector3(0, -upper * 0.42, 0), thigh_color)
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(0, -upper, 0)
	root.add_child(knee)
	var lower := length - upper
	match id:
		"elephant", "rhino":
			cylinder(knee, t, lower, Vector3(0, -lower / 2.0, 0), c)
			for i in 3:
				ellipsoid(knee, Vector3(0.06, 0.05, 0.04), Vector3((i - 1) * t * 0.6, -lower + 0.03, -t * 0.85), IVORY)
		"bison":
			cylinder(knee, t * 0.8, lower, Vector3(0, -lower / 2.0, 0), c)
			box(knee, Vector3(t * 1.8, 0.07, t * 2.0), Vector3(0, -lower + 0.035, -0.01), BLACK)
		"eagle":
			cylinder(knee, t * 0.8, lower, Vector3(0, -lower / 2.0, 0), YELLOW)
			_talons(knee, lower, YELLOW.darkened(0.2))
		"bat":
			cylinder(knee, t * 0.7, lower, Vector3(0, -lower / 2.0, 0), c)
			_talons(knee, lower, BLACK)
		"scorpion":
			cylinder(knee, t, lower, Vector3(0, -lower / 2.0, 0), c)
			if front:
				_pincer(knee, lower, c, accent(animal))
		"gorilla":
			cylinder(knee, t, lower, Vector3(0, -lower / 2.0, 0), c)
			ellipsoid(knee, Vector3(t * 2.6, t * 1.6, t * 2.8), Vector3(0, -lower + t * 0.6, -t * 0.4),
					c if not front else accent(animal))
		"kangaroo":
			cylinder(knee, t * 0.9, lower, Vector3(0, -lower / 2.0, 0), c)
			if not front:
				box(knee, Vector3(t * 1.6, 0.06, 0.34), Vector3(0, -lower + 0.03, -0.12), c.darkened(0.1))
			else:
				ellipsoid(knee, Vector3(t * 1.5, t * 1.5, t * 1.8), Vector3(0, -lower + t * 0.6, -0.02), c)
		"crocodile", "chameleon":
			cylinder(knee, t * 0.85, lower, Vector3(0, -lower / 2.0, 0), c)
			for i in 3:
				var toe := box(knee, Vector3(0.03, 0.03, 0.12), Vector3((i - 1) * 0.05, -lower + 0.015, -0.06), c.darkened(0.2))
				toe.rotation_degrees.y = (i - 1) * 25.0
		_:
			cylinder(knee, t * 0.8, lower, Vector3(0, -lower / 2.0, 0), c)
			# A paw.
			ellipsoid(knee, Vector3(t * 2.2, t * 1.2, t * 2.8), Vector3(0, -lower + t * 0.5, -t * 0.5), c.darkened(0.08))
	return root


## Arachnid legs splayed out to the side: each rises from the body to a high
## knee, then reaches down and out to the ground. The back pair of hips
## carries three legs a side; the front pair carries a pincer arm and one leg.
## Each leg is a "Splay" pivot (its rest yaw in meta) that CreatureModel
## sweeps forwards and back.
func _scorpion_legs(root: Node3D, animal: AnimalData, length: float, s: float, front: bool, side: float) -> void:
	root.set_meta("splay", true)
	var c := animal.color
	var joint_color := accent(animal)
	var fans: Array[float] = [-25.0]
	if not front:
		fans.assign([-5.0, 15.0, 35.0])
	for i in fans.size():
		var pivot := Node3D.new()
		pivot.name = "Splay%d" % i
		pivot.position = Vector3(0, 0, (i - (fans.size() - 1) / 2.0) * 0.13 * s)
		# Positive yaw turns a +X leg backwards; mirror for the left side.
		var yaw := deg_to_rad(fans[i]) * side
		pivot.rotation.y = yaw
		pivot.set_meta("rest_yaw", yaw)
		root.add_child(pivot)
		var knee := Vector3(side * 0.24 * s, 0.16 * s, 0)
		var foot := Vector3(side * 0.42 * s, -length, 0)
		_limb(pivot, Vector3.ZERO, knee, 0.03 * s, c)
		ellipsoid(pivot, Vector3.ONE * 0.07 * s, knee, joint_color)
		_limb(pivot, knee, foot, 0.022 * s, c)
	if front:
		# The pincer arm reaches forwards, raised off the ground.
		var arm := Node3D.new()
		arm.name = "Knee"
		root.add_child(arm)
		arm.scale = Vector3.ONE * s
		var elbow := Vector3(side * 0.2, 0.08, -0.12)
		var wrist := Vector3(side * 0.16, 0.06, -0.36)
		_limb(arm, Vector3.ZERO, elbow, 0.045, c)
		ellipsoid(arm, Vector3.ONE * 0.09, elbow, joint_color)
		_limb(arm, elbow, wrist, 0.04, c)
		var claw := Node3D.new()
		claw.name = "Pincer"
		claw.position = wrist + Vector3(0, 0, -0.08)
		arm.add_child(claw)
		ellipsoid(claw, Vector3(0.17, 0.11, 0.24), Vector3.ZERO, c)
		for finger_side: float in [-1.0, 1.0]:
			var finger := cone(claw, 0.045, 0.2, Vector3(finger_side * 0.045, 0, -0.18), joint_color)
			finger.rotation_degrees = Vector3(-90.0, 0, finger_side * 12.0)


## A cylinder from [param from] to [param to].
func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var limb := cylinder(parent, radius, from.distance_to(to), (from + to) / 2.0, color)
	limb.basis = Basis(Quaternion(Vector3.UP, (to - from).normalized()))
	return limb


func _talons(knee: Node3D, lower: float, color: Color) -> void:
	for i in 3:
		var talon := cone(knee, 0.02, 0.1, Vector3((i - 1) * 0.04, -lower + 0.02, -0.04), color)
		talon.rotation_degrees = Vector3(-100.0, (i - 1) * 25.0, 0)
	var back := cone(knee, 0.02, 0.08, Vector3(0, -lower + 0.02, 0.04), color)
	back.rotation_degrees.x = 80.0


func _pincer(knee: Node3D, lower: float, color: Color, inner: Color) -> void:
	var claw := Node3D.new()
	claw.name = "Pincer"
	claw.position = Vector3(0, -lower * 0.6, -0.12)
	knee.add_child(claw)
	ellipsoid(claw, Vector3(0.16, 0.1, 0.22), Vector3.ZERO, color)
	for side in [-1.0, 1.0]:
		var finger := cone(claw, 0.04, 0.2, Vector3(side * 0.04, 0, -0.18), inner)
		finger.rotation_degrees = Vector3(-90.0, 0, side * 12.0)


# --- Tail ---------------------------------------------------------------------

func tail(animal: AnimalData) -> Node3D:
	var id := id_of(animal)
	var root := Node3D.new()
	root.name = "Tail"
	var c := animal.color
	var a := accent(animal)
	match id:
		"lion", "bison", "elephant", "rhino":
			var tip := _chain(root, 4, 0.14, 0.04 if id != "elephant" else 0.035, 0.03, c, 50.0, 8.0)
			ellipsoid(tip, Vector3(0.12, 0.12, 0.16), Vector3(0, 0, 0.12), a if id == "lion" else BLACK)
		"cheetah":
			var tip := _chain(root, 6, 0.13, 0.04, 0.03, c, 60.0, -6.0)
			ellipsoid(tip, Vector3(0.08, 0.08, 0.12), Vector3(0, 0, 0.1), BLACK)
		"wolf":
			_chain(root, 4, 0.12, 0.09, 0.06, c, 40.0, 4.0, a)
		"kangaroo":
			_chain(root, 5, 0.18, 0.12, 0.05, c, 70.0, -10.0)
		"crocodile":
			_chain(root, 6, 0.2, 0.14, 0.04, c, 90.0, 0.0, c.darkened(0.25), true)
		"scorpion":
			var tip := _chain(root, 6, 0.13, 0.07, 0.05, c, 10.0, -32.0, a)
			var sting := cone(tip, 0.05, 0.16, Vector3(0, 0.0, 0.12), Color(0.4, 0.9, 0.2) if animal.tail_ability == AnimalData.Ability.POISON else BLACK)
			sting.rotation_degrees.x = 140.0
		"shark":
			var tip := _chain(root, 3, 0.18, 0.12, 0.06, c, 90.0, 0.0)
			var fin := ellipsoid(tip, Vector3(0.05, 0.6, 0.25), Vector3(0, 0.08, 0.12), c)
			fin.rotation_degrees.x = -25.0
		"electric_eel":
			var tip := _chain(root, 6, 0.18, 0.12, 0.03, c, 90.0, 0.0, a, false, true)
			ellipsoid(tip, Vector3(0.03, 0.18, 0.2), Vector3(0, -0.02, 0.1), c)
		"skunk":
			var tip := _chain(root, 4, 0.16, 0.18, 0.22, c, 25.0, -22.0, WHITE)
			ellipsoid(tip, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.05, 0.1), c)
		"porcupine":
			var stub := _chain(root, 1, 0.16, 0.1, 0.08, c, 80.0, 0.0)
			_quills(stub, Vector3(0.25, 0.25, 0.3), 9, a)
		"chameleon":
			var tip := _chain(root, 6, 0.1, 0.05, 0.02, c, 90.0, 38.0)
			ellipsoid(tip, Vector3(0.05, 0.05, 0.05), Vector3.ZERO, c)
		"eagle":
			var fan := _chain(root, 1, 0.06, 0.05, 0.05, c, 80.0, 0.0)
			for i in 5:
				var feather := ellipsoid(fan, Vector3(0.08, 0.02, 0.32), Vector3((i - 2) * 0.05, 0, 0.16), WHITE.darkened(0.05))
				feather.rotation_degrees.y = (i - 2) * 12.0
		"bat":
			_chain(root, 2, 0.08, 0.025, 0.02, c, 70.0, 0.0)
		"gorilla":
			pass
		_:
			_chain(root, 4, 0.13, 0.05, 0.03, c, 55.0, 0.0)
	return root


## A tail of [param count] segments, each a pivot named SegN. [param droop]
## tilts the first segment down from straight back; [param curl] bends each
## following one (negative curls upwards). Returns the last pivot.
func _chain(root: Node3D, count: int, length: float, start_radius: float, end_radius: float, color: Color,
		droop: float, curl: float, stripe := Color.TRANSPARENT, spikes := false, flat := false) -> Node3D:
	var parent := root
	for i in count:
		var joint := Node3D.new()
		joint.name = "Seg%d" % i
		joint.position = Vector3(0, 0, 0 if i == 0 else length * 0.92)
		# Positive angles about X bend a +Z segment downwards.
		joint.rotation_degrees.x = droop if i == 0 else curl
		parent.add_child(joint)
		var radius := lerpf(start_radius, end_radius, float(i) / maxf(count - 1, 1))
		var color_i := stripe if stripe.a > 0.0 and i % 2 == 1 else color
		var size := Vector3(radius * 2.0, radius * (0.7 if flat else 2.0), length * 1.15)
		ellipsoid(joint, size, Vector3(0, 0, length / 2.0), color_i)
		if spikes:
			cone(joint, radius * 0.4, radius * 0.9, Vector3(0, radius * 0.9, length / 2.0), color.darkened(0.3))
		parent = joint
	return parent


# --- Wings --------------------------------------------------------------------

func wing(animal: AnimalData, span: float, side: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Wing"
	var c := animal.color
	if id_of(animal) == "bat":
		# Finger bones with membrane between them.
		box(root, Vector3(span * 0.5, 0.04, 0.05), Vector3(side * span * 0.25, 0, 0), c.darkened(0.2))
		for i in 3:
			var angle := deg_to_rad(-25.0 + i * 28.0)
			var bone := box(root, Vector3(span * 0.55, 0.03, 0.03), Vector3.ZERO, c.darkened(0.3))
			bone.position = Vector3(side * (span * 0.5 + cos(angle) * span * 0.25), 0, sin(angle) * span * 0.25)
			bone.rotation.y = -side * angle
		box(root, Vector3(span * 0.95, 0.015, span * 0.5), Vector3(side * span * 0.5, -0.01, span * 0.12), accent(animal))
	else:
		# Layered feathers, lighter tips.
		box(root, Vector3(span * 0.5, 0.06, span * 0.32), Vector3(side * span * 0.25, 0, 0.02), c)
		for i in 6:
			var feather := box(root, Vector3(0.09, 0.03, span * 0.45), Vector3.ZERO, c.darkened(0.15) if i % 2 == 0 else c)
			feather.position = Vector3(side * (span * 0.45 + i * span * 0.09), -0.01, span * 0.18)
			feather.rotation.y = side * deg_to_rad(i * 6.0)
	return root


# --- Shape helpers ------------------------------------------------------------

func ellipsoid(parent: Node3D, size: Vector3, at: Vector3, color: Color, glow := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var instance := model.add_shape(parent, mesh, at, color, glow)
	instance.scale = size
	return instance


func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return model.add_shape(parent, mesh, at, color)


func cone(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	return model.add_shape(parent, mesh, at, color)


func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.85
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	return model.add_shape(parent, mesh, at, color)
