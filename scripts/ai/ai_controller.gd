class_name AIController
extends Node
## A very simple opponent.
##
## Defending is handled by the creatures themselves (they engage enemies in
## sight and call idle allies for help when hit). On top of that, every
## [member wave_interval] seconds this controller sends its idle units to
## attack-move toward the enemy army.

@export var team := 1
@export var enemy_team := 0
## Seconds between attack waves. 0 disables waves.
@export var wave_interval := 90.0
## Waves only launch when at least this many units are idle.
@export var min_wave_size := 3
@export var formation_spacing := 2.0

var _wave_timer := 0.0


func _process(delta: float) -> void:
	if wave_interval <= 0.0:
		return
	_wave_timer += delta
	if _wave_timer >= wave_interval:
		_wave_timer = 0.0
		launch_wave()


## Sends idle units at the enemy army's centre. Returns how many were sent.
func launch_wave() -> int:
	var idle: Array[Creature] = []
	var enemy_center := Vector3.ZERO
	var enemy_count := 0
	for unit: Creature in get_tree().get_nodes_in_group("units"):
		if unit.team == team and unit.order == Creature.Order.IDLE and unit.attack_target == null:
			idle.append(unit)
		elif unit.team == enemy_team:
			enemy_center += unit.global_position
			enemy_count += 1
	if enemy_count == 0 or idle.size() < min_wave_size:
		return 0
	enemy_center /= enemy_count
	SelectionManager.assign_formation(idle, enemy_center, formation_spacing, &"command_attack_move")
	return idle.size()
