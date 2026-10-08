extends Node3D
## Homing projectile fired by ranged creatures.
##
## If the target dies mid-flight the projectile carries on to the last known
## position and fizzles.

var _target: Node3D
var _source: Creature
var _damage := 0.0
var _speed := 20.0
var _aim_point := Vector3.ZERO


func launch(from: Vector3, target: Node3D, damage: float, source: Creature, speed: float) -> void:
	global_position = from
	_target = target
	_source = source
	_damage = damage
	_speed = speed
	_aim_point = _target_point()


func _physics_process(delta: float) -> void:
	if Creature.is_valid_target(_target):
		_aim_point = _target_point()
	var to_target := _aim_point - global_position
	var step := _speed * delta
	if to_target.length() <= step:
		if Creature.is_valid_target(_source):
			_source.deal_hit(_target)
		elif Creature.is_valid_target(_target):
			_target.take_damage(_damage, null, true)
		queue_free()
		return
	global_position += to_target.normalized() * step


func _target_point() -> Vector3:
	return _target.global_position + Vector3.UP * _target.center_height()
