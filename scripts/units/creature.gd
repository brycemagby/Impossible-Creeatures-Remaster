class_name Creature
extends CharacterBody3D
## A controllable RTS unit: navigation with local avoidance, orders and combat.
##
## Orders:
## - IDLE: stands still, engages enemies that come within sight range, and
##   walks back once it has chased one further than its leash range.
## - MOVE: walks to a point and ignores enemies.
## - ATTACK: chases and attacks one specific target until it dies.
## - ATTACK_MOVE: walks to a point, fighting any enemies met on the way.
##
## Uses placeholder capsule art until real creature models exist.

signal health_changed(current: float, maximum: float)
signal died(creature: Creature)

enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE }

const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.55, 1.0),
	Color(0.9, 0.25, 0.2),
	Color(0.95, 0.8, 0.2),
	Color(0.4, 0.85, 0.35),
]
const TURN_SPEED := 12.0
## Capsule radius and centre height at size 1.0 (see creature.tscn).
const BASE_RADIUS := 0.45
const BASE_CENTER_HEIGHT := 0.85
const SCAN_INTERVAL := 0.25
## Re-path when a chased target has moved this far from the current path goal.
const REPATH_DISTANCE := 0.75
## Idle allies within this radius join in when a creature is attacked.
const ALLY_ALERT_RADIUS := 10.0
## While attack-moving, automatic targets further than sight_range * this are dropped.
const LOSE_SIGHT_FACTOR := 1.5
const ProjectileScene := preload("res://scenes/fx/projectile.tscn")

@export var stats: CreatureStats
@export var team := 0

var health := 0.0
var order := Order.IDLE
var attack_target: Creature = null
var is_selected := false
var is_moving := false

var _order_point := Vector3.ZERO
var _guard_position := Vector3.ZERO
var _auto_target := false
## Caps travel speed so groups ordered together arrive together.
## Ignored while chasing a target, so units still charge at full speed.
var _group_speed := INF
var _cooldown := 0.0
var _scan_timer := 0.0
var _dead := false
var _material: StandardMaterial3D
var _flash_tween: Tween

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var body: MeshInstance3D = $Body
@onready var nose: MeshInstance3D = $Body/Nose
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var selection_ring: MeshInstance3D = $SelectionRing


func _ready() -> void:
	add_to_group("units")
	if stats == null:
		stats = CreatureStats.new()
	health = stats.max_health
	_guard_position = global_position
	# Spread enemy scans across frames so large armies don't all scan at once.
	_scan_timer = randf() * SCAN_INTERVAL
	_apply_size(stats.size)
	agent.max_speed = stats.move_speed
	agent.velocity_computed.connect(_on_velocity_computed)
	_apply_team_color()
	set_selected(false)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_scan_timer -= delta
	_update_orders()

	var desired := _desired_velocity()
	if agent.avoidance_enabled:
		agent.velocity = desired
	else:
		_on_velocity_computed(desired)
	_update_facing(delta)


# --- Orders -------------------------------------------------------------------

## [param group_speed] caps the walking speed so a group keeps pace with its
## slowest member.
func command_move(point: Vector3, group_speed := INF) -> void:
	_clear_target()
	order = Order.MOVE
	_order_point = point
	_group_speed = group_speed
	_navigate(point)


func command_attack(target: Creature) -> void:
	if not is_valid_target(target) or target.team == team:
		return
	order = Order.ATTACK
	attack_target = target
	_auto_target = false
	_group_speed = INF


func command_attack_move(point: Vector3, group_speed := INF) -> void:
	_clear_target()
	order = Order.ATTACK_MOVE
	_order_point = point
	_group_speed = group_speed
	_navigate(point)


func command_stop() -> void:
	_clear_target()
	order = Order.IDLE
	_group_speed = INF
	_halt()
	_guard_position = global_position


# --- Combat -------------------------------------------------------------------

## Applies a hit, reduced by armor. [param source] is retaliated against.
func take_damage(amount: float, source: Creature = null) -> void:
	if _dead:
		return
	var dealt := maxf(amount - stats.armor, 1.0)
	health = maxf(health - dealt, 0.0)
	health_changed.emit(health, stats.max_health)
	_flash()
	if health <= 0.0:
		_die()
		return
	if is_valid_target(source) and source.team != team:
		respond_to_attack(source)
		for ally in _allies_within(ALLY_ALERT_RADIUS):
			ally.respond_to_attack(source)


## Engages [param attacker] unless busy with an explicit order.
func respond_to_attack(attacker: Creature) -> void:
	if attack_target == null and (order == Order.IDLE or order == Order.ATTACK_MOVE):
		_engage(attacker, true)


func is_alive() -> bool:
	return not _dead


static func is_valid_target(unit: Creature) -> bool:
	return is_instance_valid(unit) and unit.is_alive()


func radius() -> float:
	return BASE_RADIUS * stats.size


func center_height() -> float:
	return BASE_CENTER_HEIGHT * stats.size


## Gap between the two creatures' edges on the ground plane.
func surface_distance_to(other: Creature) -> float:
	return _flat_distance(other.global_position) - radius() - other.radius()


func find_nearest_enemy(max_distance: float) -> Creature:
	var best: Creature = null
	var best_distance := max_distance
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team or not unit.is_alive():
			continue
		var distance := _flat_distance(unit.global_position)
		if distance < best_distance:
			best_distance = distance
			best = unit
	return best


func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value


# --- Behaviour ----------------------------------------------------------------

func _update_orders() -> void:
	if attack_target != null and not _should_keep_target():
		_lose_target()

	if attack_target == null and (order == Order.IDLE or order == Order.ATTACK_MOVE) and _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		var enemy := find_nearest_enemy(stats.sight_range)
		if enemy != null:
			_engage(enemy, true)

	if attack_target != null:
		_pursue_and_attack(attack_target)


func _should_keep_target() -> bool:
	if not is_valid_target(attack_target):
		return false
	if not _auto_target:
		return true
	if order == Order.IDLE:
		return _flat_distance(_guard_position) <= stats.leash_range
	# Attack-moving units have no post to leash to, so they give up on
	# targets that run out of sight instead of chasing across the map.
	return _flat_distance(attack_target.global_position) <= stats.sight_range * LOSE_SIGHT_FACTOR


func _lose_target() -> void:
	var target_alive := is_valid_target(attack_target)
	_clear_target()
	match order:
		Order.ATTACK:
			order = Order.IDLE
			_guard_position = global_position
			_halt()
		Order.ATTACK_MOVE:
			_navigate(_order_point)
		Order.IDLE:
			if target_alive:
				# Chased too far: walk back to the guard post, ignoring enemies.
				order = Order.MOVE
				_group_speed = INF
				_navigate(_guard_position)
			else:
				_halt()


func _engage(target: Creature, automatic: bool) -> void:
	attack_target = target
	_auto_target = automatic


func _clear_target() -> void:
	attack_target = null
	_auto_target = false


func _pursue_and_attack(target: Creature) -> void:
	if surface_distance_to(target) <= stats.attack_range:
		_halt()
		if _cooldown <= 0.0:
			_cooldown = stats.attack_cooldown
			_perform_attack(target)
	elif not is_moving or agent.target_position.distance_to(target.global_position) > REPATH_DISTANCE:
		_navigate(target.global_position)


func _perform_attack(target: Creature) -> void:
	if stats.is_ranged():
		var projectile := ProjectileScene.instantiate()
		get_tree().current_scene.add_child(projectile)
		var muzzle := global_position + Vector3.UP * center_height() * 1.2
		projectile.launch(muzzle, target, stats.attack_damage, self, stats.projectile_speed)
	else:
		target.take_damage(stats.attack_damage, self)
		_lunge()


func _die() -> void:
	_dead = true
	remove_from_group("units")
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	agent.avoidance_enabled = false
	velocity = Vector3.ZERO
	_clear_target()
	set_selected(false)
	died.emit(self)

	var tween := create_tween()
	tween.tween_property(self, "rotation:z", PI / 2.0 * (1.0 if randf() > 0.5 else -1.0), 0.35)
	tween.tween_interval(0.8)
	tween.tween_property(self, "position:y", -1.5, 1.0)
	tween.tween_callback(queue_free)


func _allies_within(max_distance: float) -> Array[Creature]:
	var allies: Array[Creature] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit != self and unit.team == team and _flat_distance(unit.global_position) <= max_distance:
			allies.append(unit)
	return allies


# --- Movement -----------------------------------------------------------------

func _navigate(point: Vector3) -> void:
	agent.target_position = point
	is_moving = true


func _halt() -> void:
	is_moving = false


func _desired_velocity() -> Vector3:
	if not is_moving:
		return Vector3.ZERO
	if agent.is_navigation_finished():
		is_moving = false
		_on_arrived()
		return Vector3.ZERO
	var to_next := agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		return Vector3.ZERO
	var speed := stats.move_speed if attack_target != null else minf(stats.move_speed, _group_speed)
	return to_next.normalized() * speed


func _on_arrived() -> void:
	if attack_target == null and (order == Order.MOVE or order == Order.ATTACK_MOVE):
		order = Order.IDLE
		_group_speed = INF
		_guard_position = global_position


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = Vector3(safe_velocity.x, 0.0, safe_velocity.z)
	move_and_slide()


func _update_facing(delta: float) -> void:
	var look := Vector3.ZERO
	if attack_target != null and not is_moving:
		look = attack_target.global_position - global_position
	elif velocity.length_squared() > 0.05:
		look = velocity
	look.y = 0.0
	if look.length_squared() > 0.0001:
		var target_yaw := atan2(-look.x, -look.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


# --- Visuals ------------------------------------------------------------------

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
	_material = StandardMaterial3D.new()
	_material.albedo_color = _team_color()
	_material.roughness = 0.7
	body.material_override = _material
	nose.material_override = _material


func _team_color() -> Color:
	return TEAM_COLORS[team % TEAM_COLORS.size()]


func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_material.albedo_color = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "albedo_color", _team_color(), 0.15)


func _lunge() -> void:
	var tween := create_tween()
	tween.tween_property(body, "position:z", -0.3 * stats.size, 0.08)
	tween.tween_property(body, "position:z", 0.0, 0.15)
