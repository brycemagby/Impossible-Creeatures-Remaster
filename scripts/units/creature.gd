class_name Creature
extends CharacterBody3D
## A controllable RTS unit: navigation with local avoidance, orders and combat.
##
## Orders:
## - IDLE: stands still, engages enemies that come within sight range, and
##   walks back once it has chased one further than its leash range.
## - MOVE: walks to a point and ignores enemies.
## - ATTACK: chases and attacks one specific target (creature or building)
##   until it dies.
## - ATTACK_MOVE: walks to a point, fighting any enemies met on the way.
## - HOLD: stays put and only attacks what comes within reach.
## - PATROL: walks back and forth between two points, fighting on the way.
## - GATHER / BUILD: Henchman-only work orders (see Henchman).
##
## Anything attackable (creatures and buildings) is in the "targets" group and
## provides team, is_alive(), take_damage(), edge_distance_from(),
## center_height(), radius(), bar_height(), get_armor() and get_max_health().
##
## Abilities come from stats: flying creatures hover above the ground, fly
## straight over obstacles and can only be hit by ranged or flying attackers;
## poisonous creatures add damage over time to each hit; chargers sprint at
## distant targets and hit harder on arrival; leapers jump the last few metres.
##
## Hybrids (stats with a design) get a CreatureModel built from their parts;
## hand-authored creatures fall back to a team-coloured capsule.

signal health_changed(current: float, maximum: float)
signal died(creature: Creature)

enum Order { IDLE, MOVE, ATTACK, ATTACK_MOVE, GATHER, BUILD, HOLD, PATROL }

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
## How high flying creatures hover.
const HOVER_HEIGHT := 2.5
const CLIMB_RATE := 4.0
## Target scoring weights (see _target_score).
const SCORE_DAMAGE_WEIGHT := 4.0
const SCORE_WOUNDED_WEIGHT := 3.0
## Bonus per nearby ally already attacking a target, up to FOCUS_MAX_ALLIES.
const SCORE_FOCUS_WEIGHT := 1.5
const FOCUS_RADIUS := 12.0
const FOCUS_MAX_ALLIES := 3
## Kiting: ranged creatures step back when a melee attacker gets this close...
const KITE_TRIGGER_DISTANCE := 2.0
## ...by this far, at most once every KITE_COOLDOWN seconds.
const KITE_DISTANCE := 5.0
const KITE_COOLDOWN := 3.0
## Kite destinations stay this far inside the map edge.
const MAP_HALF_SIZE := 48.0
## Charge: starts when the target is at least this far away.
const CHARGE_MIN_DISTANCE := 4.0
const CHARGE_SPEED_FACTOR := 1.8
const CHARGE_DAMAGE_FACTOR := 2.0
const CHARGE_COOLDOWN := 8.0
## Leap: jumps when the gap to the target is within this range.
const LEAP_MAX_DISTANCE := 7.0
const LEAP_MIN_DISTANCE := 1.5
const LEAP_DURATION := 0.4
const LEAP_HEIGHT := 1.2
const LEAP_COOLDOWN := 6.0
const ProjectileScene := preload("res://scenes/fx/projectile.tscn")

@export var stats: CreatureStats
@export var team := 0

var health := 0.0
var order := Order.IDLE
var attack_target: Node3D = null
var is_selected := false
var is_moving := false

var _order_point := Vector3.ZERO
## Patrol: the end of the route the creature is walking away from.
var _patrol_from := Vector3.ZERO
var _kiting := false
var _kite_cooldown := 0.0
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
var _model: CreatureModel
## Whichever node shows the creature: the hybrid model or the capsule body.
var _visual: Node3D
var _nav_target := Vector3.ZERO
## Team of whoever hit this creature last (for kill statistics), or -1.
var _last_attacker_team := -1
var _poison_dps := 0.0
var _poison_time := 0.0
var is_charging := false
var _charge_cooldown := 0.0
var _leap_cooldown := 0.0
var _leap_time := 0.0
var _leap_velocity := Vector3.ZERO

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var body: MeshInstance3D = $Body
@onready var nose: MeshInstance3D = $Body/Nose
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var selection_ring: MeshInstance3D = $SelectionRing


func _ready() -> void:
	add_to_group("units")
	add_to_group("targets")
	if stats == null:
		stats = CreatureStats.new()
	health = stats.max_health
	_guard_position = global_position
	# Spread enemy scans across frames so large armies don't all scan at once.
	_scan_timer = randf() * SCAN_INTERVAL
	_apply_size(stats.size)
	agent.max_speed = stats.move_speed * (CHARGE_SPEED_FACTOR if stats.can_charge else 1.0)
	agent.velocity_computed.connect(_on_velocity_computed)
	_apply_team_color()
	if stats.design != null:
		_build_model()
	_visual = _model if _model else body
	if stats.can_fly:
		# Flyers pass over rocks and buildings.
		collision_mask = 0
	set_selected(false)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_charge_cooldown = maxf(_charge_cooldown - delta, 0.0)
	_leap_cooldown = maxf(_leap_cooldown - delta, 0.0)
	_kite_cooldown = maxf(_kite_cooldown - delta, 0.0)
	_scan_timer -= delta
	if _poison_time > 0.0:
		_poison_time -= delta
		_lose_health(_poison_dps * delta)
		if _dead:
			return
	if _leap_time > 0.0:
		_update_leap(delta)
		return
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


func command_attack(target: Node3D) -> void:
	if not is_valid_target(target) or target.team == team or not can_attack(target):
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


## Stay here and only attack enemies within reach (no chasing, no kiting).
func command_hold() -> void:
	_clear_target()
	order = Order.HOLD
	_group_speed = INF
	_halt()
	_guard_position = global_position


## Walk back and forth between here and [param point], fighting on the way.
func command_patrol(point: Vector3, group_speed := INF) -> void:
	_clear_target()
	order = Order.PATROL
	_patrol_from = global_position
	_order_point = point
	_group_speed = group_speed
	_navigate(point)


# --- Combat -------------------------------------------------------------------

## Applies a hit, reduced by armor. [param source] is retaliated against.
func take_damage(amount: float, source: Creature = null) -> void:
	if _dead:
		return
	if is_valid_target(source):
		_last_attacker_team = source.team
	_flash()
	_lose_health(maxf(amount - stats.armor, 1.0))
	if _dead:
		return
	if is_valid_target(source) and source.team != team:
		respond_to_attack(source)
		for ally in _allies_within(ALLY_ALERT_RADIUS):
			ally.respond_to_attack(source)


## Poisons this creature: [param dps] damage per second for [param duration]
## seconds, ignoring armor. Doesn't stack; the stronger and longer effect wins.
func apply_poison(dps: float, duration: float) -> void:
	if _dead:
		return
	_poison_dps = maxf(_poison_dps if _poison_time > 0.0 else 0.0, dps)
	_poison_time = maxf(_poison_time, duration)


func is_poisoned() -> bool:
	return _poison_time > 0.0


## Lands one of this creature's attacks on [param target]: damage plus any
## poison. Projectiles call this on arrival.
func deal_hit(target: Node3D) -> void:
	if not is_valid_target(target):
		return
	var damage := stats.attack_damage
	if is_charging:
		damage *= CHARGE_DAMAGE_FACTOR
		is_charging = false
		_charge_cooldown = CHARGE_COOLDOWN
	target.take_damage(damage, self)
	if stats.poison_dps > 0.0 and target is Creature:
		target.apply_poison(stats.poison_dps, stats.poison_duration)


## Engages [param attacker] unless busy with an explicit order.
func respond_to_attack(attacker: Creature) -> void:
	if attack_target == null and _fights_automatically() and can_attack(attacker):
		_engage(attacker, true)


## Orders under which the creature picks its own targets.
func _fights_automatically() -> bool:
	return order in [Order.IDLE, Order.ATTACK_MOVE, Order.HOLD, Order.PATROL]


## Ground melee creatures can't reach flyers.
func can_attack(target: Node3D) -> bool:
	if target is Creature and target.stats.can_fly:
		return stats.is_ranged() or stats.can_fly
	return true


func is_alive() -> bool:
	return not _dead


## Untyped on purpose: callers pass references that may already be freed
## (a typed parameter would reject those with an error instead of false).
static func is_valid_target(target) -> bool:
	return is_instance_valid(target) and target.is_alive()


func radius() -> float:
	return BASE_RADIUS * stats.size


func center_height() -> float:
	return BASE_CENTER_HEIGHT * stats.size


func bar_height() -> float:
	return center_height() * 2.0 + 0.35


func get_max_health() -> float:
	return stats.max_health


func get_armor() -> float:
	return stats.armor


## How far this creature reveals the fog of war.
func vision_range() -> float:
	return maxf(stats.sight_range, 9.0) + (3.0 if stats.can_fly else 0.0)


## Distance from [param point] to this creature's edge on the ground plane.
func edge_distance_from(point: Vector3) -> float:
	return _flat_distance(point) - radius()


## Gap between this creature's edge and [param target]'s edge.
func surface_distance_to(target: Node3D) -> float:
	return target.edge_distance_from(global_position) - radius()


## Best enemy within [param max_distance] to attack. Creatures are preferred
## over buildings so units don't hit walls while being attacked; among
## creatures, see _target_score.
func find_best_enemy(max_distance: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var candidates: Array[Creature] = []
	# How many nearby allies are already on each target, for focus fire.
	var focus := {}
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team:
			if unit != self and unit.attack_target is Creature and _flat_distance(unit.global_position) <= FOCUS_RADIUS:
				focus[unit.attack_target] = focus.get(unit.attack_target, 0) + 1
			continue
		if not unit.is_alive() or not can_attack(unit) or unit.edge_distance_from(global_position) > max_distance:
			continue
		candidates.append(unit)
	for unit in candidates:
		var score := _target_score(unit, focus.get(unit, 0))
		if score < best_score:
			best_score = score
			best = unit
	if best != null:
		return best
	var best_distance := max_distance
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team == team or not building.is_alive():
			continue
		var distance := building.edge_distance_from(global_position)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


## Lower is better: close targets, ones our attack gets through the armor of,
## wounded ones (to finish them off), and ones nearby allies are already
## attacking (focus fire, so groups kill one enemy at a time).
func _target_score(target: Creature, allies_on_target := 0) -> float:
	var distance := target.edge_distance_from(global_position)
	var effectiveness := maxf(stats.attack_damage - target.stats.armor, 1.0) / maxf(stats.attack_damage, 1.0)
	var wounded := 1.0 - target.health / target.stats.max_health
	var focus := mini(allies_on_target, FOCUS_MAX_ALLIES) * SCORE_FOCUS_WEIGHT
	return distance - effectiveness * SCORE_DAMAGE_WEIGHT - wounded * SCORE_WOUNDED_WEIGHT - focus


func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value


# --- Behaviour ----------------------------------------------------------------

func _update_orders() -> void:
	if attack_target != null and not _should_keep_target():
		_lose_target()

	var scanning := _fights_automatically() and stats.sight_range > 0.0
	# Re-scan when idle, or when auto-attacking a building in case a creature
	# shows up that is more urgent.
	var retarget := attack_target == null or (_auto_target and attack_target is Building)
	if scanning and retarget and _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		# Holding creatures only look as far as they can hit.
		var scan_range := stats.attack_range + radius() if order == Order.HOLD else stats.sight_range
		var enemy := find_best_enemy(scan_range)
		if enemy != null and (attack_target == null or enemy is Creature):
			_engage(enemy, true)

	if attack_target != null:
		_pursue_and_attack(attack_target)


func _should_keep_target() -> bool:
	if not is_valid_target(attack_target):
		return false
	if not _auto_target:
		return true
	if order == Order.HOLD:
		return surface_distance_to(attack_target) <= stats.attack_range + 0.3
	if order == Order.IDLE:
		return _flat_distance(_guard_position) <= stats.leash_range
	# Attack-moving units have no post to leash to, so they give up on
	# targets that run out of sight instead of chasing across the map.
	return attack_target.edge_distance_from(global_position) <= stats.sight_range * LOSE_SIGHT_FACTOR


func _lose_target() -> void:
	var target_alive := is_valid_target(attack_target)
	_clear_target()
	match order:
		Order.ATTACK:
			order = Order.IDLE
			_guard_position = global_position
			_halt()
		Order.ATTACK_MOVE, Order.PATROL:
			_navigate(_order_point)
		Order.HOLD:
			_halt()
		Order.IDLE:
			if target_alive:
				# Chased too far: walk back to the guard post, ignoring enemies.
				order = Order.MOVE
				_group_speed = INF
				_navigate(_guard_position)
			else:
				_halt()


func _engage(target: Node3D, automatic: bool) -> void:
	attack_target = target
	_auto_target = automatic


func _clear_target() -> void:
	attack_target = null
	_auto_target = false
	is_charging = false
	_kiting = false


func _pursue_and_attack(target: Node3D) -> void:
	if _kiting:
		if is_moving:
			return
		_kiting = false
	var gap := surface_distance_to(target)
	if _should_kite(target, gap):
		_start_kite(target)
		return
	if gap <= stats.attack_range:
		_halt()
		if _cooldown <= 0.0:
			_cooldown = stats.attack_cooldown
			_perform_attack(target)
		return
	if order == Order.HOLD:
		return
	if stats.can_leap and _leap_cooldown <= 0.0 and gap >= LEAP_MIN_DISTANCE and gap <= LEAP_MAX_DISTANCE:
		_start_leap(target, gap)
		return
	if stats.can_charge and not is_charging and _charge_cooldown <= 0.0 and gap >= CHARGE_MIN_DISTANCE:
		is_charging = true
	if not is_moving or agent.target_position.distance_to(target.global_position) > REPATH_DISTANCE:
		_navigate(target.global_position)


## Ranged creatures back off from a melee creature that's coming for them.
func _should_kite(target: Node3D, gap: float) -> bool:
	if not stats.is_ranged() or order == Order.HOLD or _kite_cooldown > 0.0:
		return false
	if not target is Creature or target.stats.is_ranged() or not target.can_attack(self):
		return false
	return target.attack_target == self and gap < KITE_TRIGGER_DISTANCE


func _start_kite(target: Node3D) -> void:
	var away := global_position - target.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.BACK
	var point := global_position + away.normalized() * KITE_DISTANCE
	point.x = clampf(point.x, -MAP_HALF_SIZE, MAP_HALF_SIZE)
	point.z = clampf(point.z, -MAP_HALF_SIZE, MAP_HALF_SIZE)
	_kiting = true
	_kite_cooldown = KITE_COOLDOWN
	_navigate(point)


func is_kiting() -> bool:
	return _kiting


## Jumps straight at [param target], landing within attack reach.
func _start_leap(target: Node3D, gap: float) -> void:
	var direction := target.global_position - global_position
	direction.y = 0.0
	direction = direction.normalized()
	var distance := gap - stats.attack_range * 0.5
	_leap_velocity = direction * (distance / LEAP_DURATION)
	_leap_time = LEAP_DURATION
	_leap_cooldown = LEAP_COOLDOWN
	_halt()
	rotation.y = atan2(-direction.x, -direction.z)
	var hop := create_tween()
	hop.tween_property(_visual, "position:y", _visual.position.y + LEAP_HEIGHT * stats.size, LEAP_DURATION / 2.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	hop.tween_property(_visual, "position:y", _visual.position.y, LEAP_DURATION / 2.0) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _update_leap(delta: float) -> void:
	_leap_time -= delta
	velocity = _leap_velocity
	move_and_slide()
	if _leap_time <= 0.0:
		velocity = Vector3.ZERO


func is_leaping() -> bool:
	return _leap_time > 0.0


func _perform_attack(target: Node3D) -> void:
	if stats.is_ranged():
		var projectile := ProjectileScene.instantiate()
		get_tree().current_scene.add_child(projectile)
		var muzzle := global_position + Vector3.UP * center_height() * 1.2
		projectile.launch(muzzle, target, stats.attack_damage, self, stats.projectile_speed)
	else:
		deal_hit(target)
		_lunge()


func _lose_health(amount: float) -> void:
	if _dead:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, stats.max_health)
	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	remove_from_group("units")
	remove_from_group("targets")
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	agent.avoidance_enabled = false
	velocity = Vector3.ZERO
	_clear_target()
	set_selected(false)
	MatchStats.record_death(team, _last_attacker_team)
	died.emit(self)

	var tween := create_tween()
	tween.tween_property(self, "rotation:z", PI / 2.0 * (1.0 if randf() > 0.5 else -1.0), 0.35)
	tween.tween_interval(0.8)
	tween.tween_property(self, "position:y", -1.5, 1.0 + position.y * 0.3)
	tween.tween_callback(queue_free)


func _allies_within(max_distance: float) -> Array[Creature]:
	var allies: Array[Creature] = []
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit != self and unit.team == team and _flat_distance(unit.global_position) <= max_distance:
			allies.append(unit)
	return allies


# --- Movement -----------------------------------------------------------------

func _navigate(point: Vector3) -> void:
	_nav_target = point
	agent.target_position = point
	is_moving = true


func _halt() -> void:
	is_moving = false


func _desired_velocity() -> Vector3:
	if not is_moving:
		return Vector3.ZERO
	if stats.can_fly:
		return _flying_velocity()
	if agent.is_navigation_finished():
		is_moving = false
		_on_arrived()
		return Vector3.ZERO
	var to_next := agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		return Vector3.ZERO
	var speed := stats.move_speed if attack_target != null else minf(stats.move_speed, _group_speed)
	if is_charging and attack_target != null:
		speed *= CHARGE_SPEED_FACTOR
	return to_next.normalized() * speed


## Flyers ignore the navmesh and head straight for their destination.
func _flying_velocity() -> Vector3:
	var to_target := _nav_target - global_position
	to_target.y = 0.0
	if to_target.length() <= agent.target_desired_distance:
		is_moving = false
		_on_arrived()
		return Vector3.ZERO
	var speed := stats.move_speed if attack_target != null else minf(stats.move_speed, _group_speed)
	return to_target.normalized() * speed


func _on_arrived() -> void:
	if attack_target == null and order == Order.PATROL:
		var next := _patrol_from
		_patrol_from = _order_point
		_order_point = next
		_navigate(next)
		return
	if attack_target == null and (order == Order.MOVE or order == Order.ATTACK_MOVE):
		order = Order.IDLE
		_group_speed = INF
		_guard_position = global_position


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	var climb := 0.0
	if stats.can_fly:
		climb = clampf((HOVER_HEIGHT - global_position.y) * 3.0, -CLIMB_RATE, CLIMB_RATE)
	velocity = Vector3(safe_velocity.x, climb, safe_velocity.z)
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
	if _model:
		_model.flash()
		return
	if _flash_tween:
		_flash_tween.kill()
	_material.albedo_color = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "albedo_color", _team_color(), 0.15)


func _lunge() -> void:
	var tween := create_tween()
	tween.tween_property(_visual, "position:z", -0.3 * stats.size, 0.08)
	tween.tween_property(_visual, "position:z", 0.0, 0.15)


func _build_model() -> void:
	body.visible = false
	_model = CreatureModel.new()
	_model.scale = Vector3.ONE * stats.size
	add_child(_model)
	_model.build(stats.design)
	# Hybrids are coloured like their animals, so show the team on a base disc.
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.6 * stats.size
	mesh.bottom_radius = 0.6 * stats.size
	mesh.height = 0.04
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _team_color()
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.03
	add_child(disc)
