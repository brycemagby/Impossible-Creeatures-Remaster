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
## Sonic screech: damage to every enemy within SONIC_RADIUS, ignoring armor.
const SONIC_DAMAGE := 6.0
const SONIC_RADIUS := 5.0
const SONIC_COOLDOWN := 7.0
## After a screech hits it, a creature is deafened: no more sonic damage for this long.
const SONIC_DEAFEN_TIME := 3.0
const SONIC_COLOR := Color(0.75, 0.6, 1.0, 0.7)
## Pack hunters: extra damage per packmate within PACK_RADIUS, up to PACK_MAX_MATES.
const PACK_BONUS := 0.15
const PACK_RADIUS := 6.0
const PACK_MAX_MATES := 3
## Herding: extra melee and ranged armor per herd mate within HERD_RADIUS, up to HERD_MAX_MATES.
const HERD_ARMOR := 1.0
const HERD_RADIUS := 6.0
const HERD_MAX_MATES := 3
## Frenzy: below this share of health, attacks come this much faster.
const FRENZY_HEALTH := 0.5
const FRENZY_COOLDOWN_FACTOR := 0.6
## Trample: melee hits also deal this share to enemies within TRAMPLE_RADIUS of the target.
const TRAMPLE_SHARE := 0.5
const TRAMPLE_RADIUS := 1.5
## Stink: enemies within STINK_RADIUS deal this much less damage (doesn't stack).
const STINK_PENALTY := 0.25
const STINK_RADIUS := 4.0
const STINK_COLOR := Color(0.55, 0.75, 0.2, 0.35)
const STINK_PUFF_INTERVAL := 1.5
## Camouflage: hidden after standing still this long, unless an enemy is within
## CAMOUFLAGE_DETECT_RADIUS, or an enemy with sonic (echolocation) within
## ECHOLOCATION_RADIUS.
const CAMOUFLAGE_DELAY := 3.0
const CAMOUFLAGE_DETECT_RADIUS := 3.0
const ECHOLOCATION_RADIUS := 12.0
## Electric: every ELECTRIC_COOLDOWN seconds a hit shocks for extra damage
## (through armor) and stuns the target.
const ELECTRIC_DAMAGE := 5.0
const ELECTRIC_STUN := 1.5
const ELECTRIC_COOLDOWN := 6.0
const ELECTRIC_COLOR := Color(1.0, 0.95, 0.35, 0.8)
## How far a swimming body sinks into the water (times its size).
const SWIM_SINK := 0.3
## Melee creatures on land reach this far past their attack range into water.
const SHORE_REACH := 1.0
## A walker this close to its destination that stops getting closer for
## STUCK_TIME seconds counts as arrived (its spot is taken in a crowd).
const STUCK_TIME := 1.0
const STUCK_ARRIVE_DISTANCE := 4.0
const STUCK_PROGRESS := 0.1
## Armor never blocks more than this share of a hit.
const MAX_ARMOR_BLOCK := 0.6
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
var _disc_material: StandardMaterial3D
## Whichever node shows the creature: the hybrid model or the capsule body.
var _visual: Node3D
var _nav_target := Vector3.ZERO
## Team of whoever hit this creature last (for kill statistics), or -1.
var _last_attacker_team := -1
## Shift-queued orders (Callables), run in turn once the current one is done.
var _order_queue: Array[Callable] = []
var _poison_dps := 0.0
var _poison_time := 0.0
var is_charging := false
var _charge_cooldown := 0.0
var _leap_cooldown := 0.0
var _sonic_cooldown := 0.0
var _deafened := 0.0
var _stink_puff := 0.0
## Seconds standing still without fighting or being hit (for camouflage).
var _still_time := 0.0
var _camouflaged := false
var _electric_cooldown := 0.0
var _stunned := 0.0
## In deep water right now (swimmers only).
var _in_water := false
## Closest it has come to its destination lately, and how long since it got closer.
var _best_distance := INF
var _no_progress_time := 0.0
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
	# Headroom for speed upgrades; the actual speed comes from move_speed().
	agent.max_speed = maxf(stats.move_speed, stats.swim_speed) * 1.5 * (CHARGE_SPEED_FACTOR if stats.can_charge else 1.0)
	# Walkers keep to land, fins to water, amphibians use both.
	if stats.water_only:
		agent.navigation_layers = WaterArea.WATER_LAYER
	elif stats.can_swim:
		agent.navigation_layers = WaterArea.LAND_LAYER | WaterArea.WATER_LAYER
	else:
		agent.navigation_layers = WaterArea.LAND_LAYER
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
	_sonic_cooldown = maxf(_sonic_cooldown - delta, 0.0)
	_deafened = maxf(_deafened - delta, 0.0)
	_electric_cooldown = maxf(_electric_cooldown - delta, 0.0)
	if stats.can_swim:
		_update_swimming()
	_update_camouflage(delta)
	if stats.has_stink and attack_target != null:
		_stink_puff -= delta
		if _stink_puff <= 0.0:
			_stink_puff = STINK_PUFF_INTERVAL
			_show_puff(STINK_COLOR, STINK_RADIUS, 0.8)
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
	if _stunned > 0.0:
		_stunned -= delta
		# Avoidance would keep applying the last velocity otherwise.
		if agent.avoidance_enabled:
			agent.velocity = Vector3.ZERO
		else:
			_on_velocity_computed(Vector3.ZERO)
		return
	_update_orders()
	if stats.has_sonic and _sonic_cooldown <= 0.0 and attack_target != null:
		_try_sonic()

	var desired := _desired_velocity()
	if agent.avoidance_enabled:
		agent.velocity = desired
	else:
		_on_velocity_computed(desired)
	_update_facing(delta)


# --- Orders -------------------------------------------------------------------

## Runs [param command] now if idle, otherwise after the orders already queued.
func queue_order(command: Callable) -> void:
	if is_idle() and _order_queue.is_empty():
		command.call()
	else:
		_order_queue.append(command)


func clear_order_queue() -> void:
	_order_queue.clear()


func queued_orders() -> int:
	return _order_queue.size()


## True when the creature has no order and isn't fighting.
func is_idle() -> bool:
	return order == Order.IDLE and attack_target == null


## [param group_speed] caps the walking speed so a group keeps pace with its
## slowest member.
func command_move(point: Vector3, group_speed := INF) -> void:
	_clear_target()
	order = Order.MOVE
	_order_point = point
	_group_speed = group_speed
	_navigate(point)


func command_attack(target: Node3D) -> void:
	if not is_valid_target(target) or not Teams.are_enemies(team, target.team) or not can_attack(target):
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

## Applies a hit, reduced by melee or ([param ranged]) ranged armor.
## [param source] (a creature or a tower) is retaliated against.
func take_damage(amount: float, source: Node3D = null, ranged := false) -> void:
	if _dead:
		return
	if is_valid_target(source):
		_last_attacker_team = source.team
	_flash()
	_still_time = 0.0
	_lose_health(damage_after_armor(amount, ranged_armor() if ranged else armor()))
	if _dead:
		return
	if is_valid_target(source) and Teams.are_enemies(source.team, team):
		Alerts.report(team, global_position, "Your Henchmen are under attack!" if has_method("is_working") else "Your creatures are under attack!")
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


func heal(amount: float) -> void:
	if _dead or health >= stats.max_health:
		return
	health = minf(health + amount, stats.max_health)
	health_changed.emit(health, stats.max_health)


func is_poisoned() -> bool:
	return _poison_time > 0.0


## Lands one of this creature's attacks on [param target]: damage plus any
## poison. Projectiles call this on arrival.
func deal_hit(target: Node3D) -> void:
	if not is_valid_target(target):
		return
	var damage := attack_damage()
	if is_charging:
		damage *= CHARGE_DAMAGE_FACTOR
		is_charging = false
		_charge_cooldown = CHARGE_COOLDOWN
	target.take_damage(damage, self, stats.is_ranged())
	if stats.poison_dps > 0.0 and target is Creature:
		target.apply_poison(stats.poison_dps, stats.poison_duration)
	if stats.has_trample and not stats.is_ranged():
		_trample(target, damage * TRAMPLE_SHARE)
	if stats.has_electric and _electric_cooldown <= 0.0 and is_valid_target(target):
		_electric_cooldown = ELECTRIC_COOLDOWN
		target.take_damage(ELECTRIC_DAMAGE + (target.armor() if target is Creature else 0.0), self)
		if target is Creature and is_valid_target(target):
			target.stun(ELECTRIC_STUN)
			target._show_puff(ELECTRIC_COLOR, 1.2, 0.3)


## Trample: [param damage] to the other enemies right next to [param target].
func _trample(target: Node3D, damage: float) -> void:
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit == target or not unit.is_alive() or not Teams.are_enemies(team, unit.team) or not can_attack(unit):
			continue
		if unit.edge_distance_from(target.global_position) <= TRAMPLE_RADIUS:
			unit.take_damage(damage, self)


## Sonic screech: hurts every enemy creature within SONIC_RADIUS, flyers
## included, ignoring armor. Returns how many were hit. Screeches don't stack:
## a creature just hit is deafened for a moment.
func _try_sonic() -> int:
	var hit := 0
	var in_range := 0
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.is_alive() and Teams.are_enemies(team, unit.team) and unit.edge_distance_from(global_position) <= SONIC_RADIUS:
			in_range += 1
			if unit.hear_screech(self):
				hit += 1
	if in_range > 0:
		_sonic_cooldown = SONIC_COOLDOWN
		_show_puff(SONIC_COLOR, SONIC_RADIUS, 0.4, true)
	return hit


## Takes a sonic screech from [param source] unless deafened. Returns whether it hurt.
func hear_screech(source: Creature) -> bool:
	if _deafened > 0.0:
		return false
	_deafened = SONIC_DEAFEN_TIME
	take_damage(SONIC_DAMAGE + armor(), source)
	return true


## An expanding, fading ring (sonic) or cloud (stink) of [param radius].
func _show_puff(color: Color, radius_m: float, duration: float, as_ring := false) -> void:
	var mesh: Mesh
	if as_ring:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.85
		torus.outer_radius = 1.0
		mesh = torus
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 1.0
		mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3.UP * center_height()
	ring.scale = Vector3.ONE * 0.3
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3.ONE * radius_m, duration)
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.chain().tween_callback(ring.queue_free)


## Engages [param attacker] unless busy with an explicit order.
func respond_to_attack(attacker: Node3D) -> void:
	if attack_target == null and _fights_automatically() and can_attack(attacker):
		_engage(attacker, true)


## Orders under which the creature picks its own targets.
func _fights_automatically() -> bool:
	return order in [Order.IDLE, Order.ATTACK_MOVE, Order.HOLD, Order.PATROL]


## Ground melee creatures can't reach flyers.
## Flyers are out of reach of melee, except while they swoop down to fight in
## melee themselves.
func can_attack(target: Node3D) -> bool:
	if target is Creature and target.is_hidden_from(team):
		return false
	if target is Creature and target.stats.can_fly:
		return stats.is_ranged() or stats.can_fly or target.is_swooping()
	# Land melee creatures only reach swimmers close to the shore.
	if target is Creature and target.stats.can_swim and not (stats.is_ranged() or stats.can_fly or stats.can_swim):
		if WaterArea.distance_from_shore(get_tree(), target.global_position) > stats.attack_range + SHORE_REACH:
			return false
	# Creatures stuck in the water only reach what's close to it.
	if stats.water_only:
		var reach: float = stats.attack_range + target.radius() + SHORE_REACH + Upgrades.shore_reach_bonus(team)
		if WaterArea.distance_to_deep_water(get_tree(), target.global_position) > reach:
			return false
	return true


## True while camouflaged (standing still, not fighting) - see is_hidden_from().
func is_camouflaged() -> bool:
	return _camouflaged


## Whether [param viewer_team] can't see this creature: it's camouflaged and no
## creature of theirs is close enough, or echolocating, to spot it.
func is_hidden_from(viewer_team: int) -> bool:
	if not _camouflaged or not Teams.are_enemies(team, viewer_team):
		return false
	var fog := get_tree().get_first_node_in_group("fog") as FogOfWar
	if fog != null and fog.is_exposed(team):
		return false
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if not unit.is_alive() or not Teams.are_allies(unit.team, viewer_team):
			continue
		var distance := _flat_distance(unit.global_position)
		if distance <= CAMOUFLAGE_DETECT_RADIUS or (unit.stats.has_sonic and distance <= ECHOLOCATION_RADIUS):
			return false
	return true


func _update_camouflage(delta: float) -> void:
	if not stats.has_camouflage:
		return
	if is_moving or attack_target != null or _leap_time > 0.0:
		_still_time = 0.0
	else:
		_still_time += delta
	var camouflaged := _still_time >= CAMOUFLAGE_DELAY
	if camouflaged != _camouflaged:
		_camouflaged = camouflaged
		if _model:
			_model.set_ghostly(camouflaged)


## True while an enemy stinker is close enough to put this creature off its stroke.
func is_stunk() -> bool:
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.stats.has_stink and unit.is_alive() and Teams.are_enemies(team, unit.team) \
				and unit.edge_distance_from(global_position) <= STINK_RADIUS:
			return true
	return false


## True while this flyer is fighting in melee, low enough to be hit back.
func is_swooping() -> bool:
	return stats.can_fly and not stats.is_ranged() and is_valid_target(attack_target) \
			and surface_distance_to(attack_target) <= stats.attack_range + 1.0


## Damage a hit of [param amount] does through [param armor_value].
static func damage_after_armor(amount: float, armor_value: float) -> float:
	return maxf(amount - armor_value, maxf(amount * (1.0 - MAX_ARMOR_BLOCK), 1.0))


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
	return armor()


## Melee armor including the team's upgrades.
func armor() -> float:
	return stats.armor + Upgrades.melee_armor_bonus(team) + HERD_ARMOR * herd_mates()


## Ranged armor including the team's upgrades.
func ranged_armor() -> float:
	return stats.ranged_armor + Upgrades.ranged_armor_bonus(team) + HERD_ARMOR * herd_mates()


## Damage per hit including the team's melee or ranged damage upgrades.
func attack_damage() -> float:
	var bonus := Upgrades.ranged_damage_bonus(team) if stats.is_ranged() else Upgrades.melee_damage_bonus(team)
	var damage := (stats.attack_damage + bonus) * (1.0 + PACK_BONUS * packmates())
	if is_stunk():
		damage *= 1.0 - STINK_PENALTY
	return damage


## Other pack hunters of this team close enough to hunt with (0 if not a pack hunter).
func packmates() -> int:
	if not stats.pack_hunter:
		return 0
	return mini(_mates_with(&"pack_hunter", PACK_RADIUS), PACK_MAX_MATES)


## Other herding creatures of this team close enough to shield (0 if not herding).
func herd_mates() -> int:
	if not stats.herding:
		return 0
	return mini(_mates_with(&"herding", HERD_RADIUS), HERD_MAX_MATES)


## Living creatures of this team within [param distance] whose stats have [param flag] set.
func _mates_with(flag: StringName, distance: float) -> int:
	var mates := 0
	for ally in _allies_within(distance):
		if ally.team == team and ally.stats.get(flag) and ally.is_alive():
			mates += 1
	return mates


## Seconds between attacks: shorter while frenzied.
func attack_cooldown() -> float:
	return stats.attack_cooldown * (FRENZY_COOLDOWN_FACTOR if is_frenzied() else 1.0)


func is_frenzied() -> bool:
	return stats.has_frenzy and health <= stats.max_health * FRENZY_HEALTH


## Walking speed including the team's upgrades.
func move_speed() -> float:
	var swimming := stats.water_only or _in_water
	var base := stats.swim_speed * Upgrades.swim_speed_multiplier(team) if swimming else stats.move_speed
	if stats.can_fly:
		base *= Upgrades.flyer_speed_multiplier(team)
	return base * Upgrades.speed_multiplier(team)


## How far this creature notices enemies, including flyers' sight upgrades.
func sight_range() -> float:
	return stats.sight_range + (Upgrades.flyer_sight_bonus(team) if stats.can_fly else 0.0)


## True while swimming in deep water.
func is_in_water() -> bool:
	return _in_water


func _update_swimming() -> void:
	_in_water = stats.water_only or WaterArea.is_deep_water(get_tree(), global_position)
	if _visual and _leap_time <= 0.0:
		_visual.position.y = -SWIM_SINK * stats.size if _in_water else 0.0


## Stops this creature in its tracks (no moving or attacking) for [param seconds].
func stun(seconds: float) -> void:
	_stunned = maxf(_stunned, seconds)


func is_stunned() -> bool:
	return _stunned > 0.0


## How far this creature reveals the fog of war.
func vision_range() -> float:
	return maxf(sight_range(), 9.0) + (3.0 if stats.can_fly else 0.0)


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
		if not Teams.are_enemies(unit.team, team):
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
		if not Teams.are_enemies(building.team, team) or not building.is_alive() or not can_attack(building):
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
	var their_armor := target.ranged_armor() if stats.is_ranged() else target.armor()
	var effectiveness := maxf(attack_damage() - their_armor, 1.0) / maxf(attack_damage(), 1.0)
	var wounded := 1.0 - target.health / target.stats.max_health
	var focus := mini(allies_on_target, FOCUS_MAX_ALLIES) * SCORE_FOCUS_WEIGHT
	return distance - effectiveness * SCORE_DAMAGE_WEIGHT - wounded * SCORE_WOUNDED_WEIGHT - focus


func set_selected(value: bool) -> void:
	is_selected = value
	selection_ring.visible = value


# --- Behaviour ----------------------------------------------------------------

func _update_orders() -> void:
	while is_idle() and not _order_queue.is_empty():
		var command: Callable = _order_queue.pop_front()
		if command.is_valid():
			command.call()
	if attack_target != null and not _should_keep_target():
		_lose_target()

	var scanning := _fights_automatically() and stats.sight_range > 0.0
	# Re-scan when idle, or when auto-attacking a building in case a creature
	# shows up that is more urgent.
	var retarget := attack_target == null or (_auto_target and attack_target is Building)
	if scanning and retarget and _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		# Holding creatures only look as far as they can hit.
		var scan_range := stats.attack_range + radius() if order == Order.HOLD else sight_range()
		var enemy := find_best_enemy(scan_range)
		if enemy != null and (attack_target == null or enemy is Creature):
			_engage(enemy, true)

	if attack_target != null:
		_pursue_and_attack(attack_target)


func _should_keep_target() -> bool:
	if not is_valid_target(attack_target):
		return false
	# A flyer that stops swooping is out of a melee creature's reach again.
	if not can_attack(attack_target):
		return false
	if not _auto_target:
		return true
	if order == Order.HOLD:
		return surface_distance_to(attack_target) <= stats.attack_range + 0.3
	if order == Order.IDLE:
		return _flat_distance(_guard_position) <= stats.leash_range
	# Attack-moving units have no post to leash to, so they give up on
	# targets that run out of sight instead of chasing across the map.
	return attack_target.edge_distance_from(global_position) <= sight_range() * LOSE_SIGHT_FACTOR


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
			_cooldown = attack_cooldown()
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
		if unit != self and Teams.are_allies(unit.team, team) and _flat_distance(unit.global_position) <= max_distance:
			allies.append(unit)
	return allies


# --- Movement -----------------------------------------------------------------

func _navigate(point: Vector3) -> void:
	_nav_target = point
	agent.target_position = point
	is_moving = true
	_best_distance = INF
	_no_progress_time = 0.0


func _halt() -> void:
	is_moving = false


func _desired_velocity() -> Vector3:
	if not is_moving:
		return Vector3.ZERO
	if stats.can_fly:
		return _flying_velocity()
	if agent.is_navigation_finished() or _blocked_near_destination():
		is_moving = false
		_on_arrived()
		return Vector3.ZERO
	var to_next := agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		return Vector3.ZERO
	var speed := move_speed() if attack_target != null else minf(move_speed(), _group_speed)
	if is_charging and attack_target != null:
		speed *= CHARGE_SPEED_FACTOR
	return to_next.normalized() * speed


## True when it's close to where it's going but hasn't got any closer for a
## while: in a crowd, someone else is standing on its spot.
func _blocked_near_destination() -> bool:
	if attack_target != null:
		return false
	var distance := _flat_distance(_nav_target)
	if distance < _best_distance - STUCK_PROGRESS:
		_best_distance = distance
		_no_progress_time = 0.0
		return false
	_no_progress_time += get_physics_process_delta_time()
	return _no_progress_time >= STUCK_TIME and distance <= STUCK_ARRIVE_DISTANCE + radius()


## Flyers ignore the navmesh and head straight for their destination.
func _flying_velocity() -> Vector3:
	var to_target := _nav_target - global_position
	to_target.y = 0.0
	if to_target.length() <= agent.target_desired_distance:
		is_moving = false
		_on_arrived()
		return Vector3.ZERO
	var speed := move_speed() if attack_target != null else minf(move_speed(), _group_speed)
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
	if _stunned > 0.0:
		# Not even avoidance moves a stunned creature.
		safe_velocity = Vector3.ZERO
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
	return Teams.color(team)


## Re-applies team colours (after the match decides who's allied with whom).
func refresh_team_color() -> void:
	_material.albedo_color = _team_color()
	if _disc_material:
		_disc_material.albedo_color = _team_color()


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
	_disc_material = material
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.03
	add_child(disc)
