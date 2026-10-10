extends Node
## "Under attack" alerts. Each area alerts at most once per [constant QUIET_TIME]
## so a long fight doesn't spam the player; the latest alert can be jumped to.

signal raised(team: int, text: String, position: Vector3)

## Seconds before an area that already alerted can alert again.
const QUIET_TIME := 15.0
## Hits within this distance of a recent alert count as the same fight.
const AREA_RADIUS := 25.0

var _clock := 0.0
## team -> Array of [position, time] for recent alerts.
var _recent := {}
## team -> position of the latest alert.
var _latest := {}


func _process(delta: float) -> void:
	_clock += delta


func reset() -> void:
	_recent.clear()
	_latest.clear()


## Called when something of [param team]'s is hit by an enemy at [param where].
func report(team: int, where: Vector3, text: String) -> void:
	var recent: Array = _recent.get(team, [])
	recent = recent.filter(func(entry: Array) -> bool: return _clock - entry[1] < QUIET_TIME)
	_recent[team] = recent
	for entry: Array in recent:
		if entry[0].distance_to(where) <= AREA_RADIUS:
			return
	recent.append([where, _clock])
	_latest[team] = where
	raised.emit(team, text, where)


func has_alert(team: int) -> bool:
	return _latest.has(team)


## Where [param team]'s latest alert happened.
func latest(team: int) -> Vector3:
	return _latest.get(team, Vector3.ZERO)
