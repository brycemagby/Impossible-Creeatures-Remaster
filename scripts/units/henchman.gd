class_name Henchman
extends Creature
## Worker unit: gathers coal and constructs buildings.
##
## Gathering loops automatically: walk to a coal pile, mine a load, carry it
## to the nearest finished drop-off building (the Lab), and go back. When a
## pile runs out the Henchman looks for another one nearby.

## Coal carried per trip without the Coal Sacks upgrade (see Upgrades).
const CARRY_CAPACITY := Upgrades.BASE_CARRY
const GATHER_TIME := 1.5
## How close (edge to edge) a Henchman must be to mine, drop off or build.
const WORK_REACH := 0.8
## How far to look for another pile when the current one runs out.
const PILE_SEARCH_RADIUS := 25.0

var carried_coal := 0
var gather_target: CoalPile = null
var build_target: Building = null

var _work_timer := 0.0
## The pile it was mining before being sent to build, to go back to afterwards.
var _last_pile: CoalPile = null


func command_gather(pile: CoalPile) -> void:
	_stop_work()
	_clear_target()
	order = Order.GATHER
	gather_target = pile
	_last_pile = pile
	_group_speed = INF
	_halt()


## Builds [param site], or repairs it if it's finished but damaged.
func command_build(site: Building) -> void:
	if not Creature.is_valid_target(site) or not site.needs_work() or site.team != team:
		return
	_stop_work()
	_clear_target()
	order = Order.BUILD
	build_target = site
	_group_speed = INF
	_halt()


func command_move(point: Vector3, group_speed := INF) -> void:
	_stop_work()
	super(point, group_speed)


func command_attack(target: Node3D) -> void:
	_stop_work()
	super(target)


func command_attack_move(point: Vector3, group_speed := INF) -> void:
	_stop_work()
	super(point, group_speed)


func command_stop() -> void:
	_stop_work()
	super()


func command_hold() -> void:
	_stop_work()
	super()


func command_patrol(point: Vector3, group_speed := INF) -> void:
	_stop_work()
	super(point, group_speed)


func move_speed() -> float:
	return stats.move_speed * Upgrades.henchman_speed_multiplier(team)


func is_working() -> bool:
	return order == Order.GATHER or order == Order.BUILD


func _update_orders() -> void:
	match order:
		Order.GATHER:
			_update_gather(get_physics_process_delta_time())
		Order.BUILD:
			_update_build(get_physics_process_delta_time())
		_:
			super()


func _update_gather(delta: float) -> void:
	if not is_instance_valid(gather_target) or gather_target.is_depleted():
		gather_target = find_coal_pile(PILE_SEARCH_RADIUS)

	var capacity := Upgrades.carry_capacity(team)
	if carried_coal >= capacity or (gather_target == null and carried_coal > 0):
		_return_coal()
		return
	if gather_target == null:
		_become_idle()
		return

	if gather_target.edge_distance_from(global_position) - radius() <= WORK_REACH:
		_halt()
		_face(gather_target.global_position)
		_work_timer += delta
		if _work_timer >= GATHER_TIME * Upgrades.gather_time_factor(team):
			_work_timer = 0.0
			carried_coal += gather_target.take(capacity - carried_coal)
	elif not is_moving:
		_work_timer = 0.0
		_navigate(gather_target.global_position)


func _return_coal() -> void:
	var drop_off := _find_drop_off()
	if drop_off == null:
		_become_idle()
		return
	if drop_off.edge_distance_from(global_position) - radius() <= WORK_REACH:
		_halt()
		Economy.deposit_coal(team, carried_coal)
		carried_coal = 0
	elif not is_moving:
		_navigate(drop_off.global_position)


func _update_build(delta: float) -> void:
	if not Creature.is_valid_target(build_target) or not build_target.needs_work():
		build_target = null
		_back_to_work()
		return
	if build_target.edge_distance_from(global_position) - radius() <= WORK_REACH:
		_halt()
		_face(build_target.global_position)
		var work := delta * Upgrades.build_speed_multiplier(team)
		if not build_target.is_complete:
			build_target.add_build_work(work)
		elif not build_target.add_repair_work(work):
			# Out of coal to pay for repairs.
			build_target = null
			_back_to_work()
	elif not is_moving:
		_navigate(build_target.global_position)


func find_coal_pile(max_distance: float) -> CoalPile:
	var best: CoalPile = null
	var best_distance := max_distance
	for pile: CoalPile in get_tree().get_nodes_in_group("coal_piles"):
		var distance := pile.edge_distance_from(global_position)
		if distance < best_distance:
			best_distance = distance
			best = pile
	return best


func _find_drop_off() -> Building:
	var best: Building = null
	var best_distance := INF
	for building: Building in get_tree().get_nodes_in_group("buildings"):
		if building.team != team or not building.is_complete or not building.data.is_drop_off:
			continue
		var distance := building.edge_distance_from(global_position)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


## After building or repairing: back to the coal it was mining (or the
## nearest), unless it has queued orders to get on with.
func _back_to_work() -> void:
	if queued_orders() > 0:
		_become_idle()
		return
	var pile := _last_pile if is_instance_valid(_last_pile) and not _last_pile.is_depleted() else find_coal_pile(PILE_SEARCH_RADIUS)
	if pile != null:
		command_gather(pile)
	else:
		_become_idle()


func _become_idle() -> void:
	order = Order.IDLE
	_guard_position = global_position
	_halt()


func _stop_work() -> void:
	gather_target = null
	build_target = null
	_work_timer = 0.0


func _face(point: Vector3) -> void:
	var look := point - global_position
	if Vector2(look.x, look.z).length_squared() > 0.0001:
		rotation.y = atan2(-look.x, -look.z)
