class_name Creature
extends CharacterBody3D
## A controllable RTS unit with navigation, local avoidance and a selection ring.
##
## Uses placeholder capsule art until real creature models exist.

const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0),
	Color(0.9, 0.25, 0.2),
	Color(0.95, 0.8, 0.2),
	Color(0.4, 0.85, 0.35),
]
const TURN_SPEED := 12.0

@export var stats: CreatureStats
@export var team := 0

var is_selected := false
var is_moving := false

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var body: MeshInstance3D = $Body
@onready var nose: MeshInstance3D = $Body/Nose
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var selection_ring: MeshInstance3D = $SelectionRing


func _ready() -> void:
	add_to_group("units")
	if stats == null:
		stats = CreatureStats.new()
	_apply_size(stats.size)
	agent.max_speed = stats.move_speed
	agent.velocity_computed.connect(_on_velocity_computed)
	_apply_team_color()
	set_selected(false)


func _physics_process(delta: float) -> void:
	var desired := Vector3.ZERO
	if is_moving:
		if agent.is_navigation_finished():
			is_moving = false
		else:
			var to_next := agent.get_next_path_position() - global_position
			to_next.y = 0.0
			if to_next.length_squared() > 0.0001:
				desired = to_next.normalized() * stats.move_speed

	if agent.avoidance_enabled:
		agent.velocity = desired
	else:
		_on_velocity_computed(desired)

	if velocity.length_squared() > 0.05:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


## Orders the creature to path to [param target].
func move_to(target: Vector3) -> void:
	agent.target_position = target
	is_moving = true


func stop() -> void:
	is_moving = false
	agent.target_position = global_position


func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = Vector3(safe_velocity.x, 0.0, safe_velocity.z)
	move_and_slide()


func _apply_size(s: float) -> void:
	body.scale = Vector3.ONE * s
	body.position.y *= s
	var shape := collision.shape.duplicate() as CapsuleShape3D
	shape.radius *= s
	shape.height *= s
	collision.shape = shape
	collision.position.y *= s
	selection_ring.scale = Vector3(s, 1.0, s)
	agent.radius *= s
	agent.height *= s


func _apply_team_color() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = TEAM_COLORS[team % TEAM_COLORS.size()]
	material.roughness = 0.7
	body.material_override = material
	nose.material_override = material
