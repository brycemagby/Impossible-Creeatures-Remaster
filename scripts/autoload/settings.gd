extends Node
## Player options, saved to user://settings.cfg and applied as they change:
## sound volumes, window mode, UI scale, camera, health bars, the colour-blind
## palette and key bindings. The Options screen (OptionsMenu) edits these.

signal changed()

const PATH := "user://settings.cfg"
const BUSES := ["Effects", "Voices"]
## Health bar modes.
const BARS_DAMAGED := "damaged"
const BARS_ALWAYS := "always"
const UI_SCALES := [0.75, 0.9, 1.0, 1.15, 1.3, 1.5]

## 0 to 1.
var master_volume := 1.0
var effects_volume := 1.0
## Creature voices (selection, orders, "unit ready").
var voice_volume := 0.8
var fullscreen := false
## Interface size on top of following the window size.
var ui_scale := 1.0
var edge_scroll := true
## Multiplies the camera's pan speed.
var pan_speed := 1.0
var health_bars := BARS_DAMAGED
## Blue / orange / yellow team colours instead of blue / red / green.
var colorblind := false
## Game speed the last match was played at.
var game_speed := 1.0
## Action -> physical keycodes, for actions the player rebound.
var bindings := {}
## Off in tests, so they never touch the player's saved options.
var persist := true

var _defaults := {}


func _enter_tree() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	for key: String in _keys():
		_defaults[key] = get(key)
	load_settings()
	apply()


## Changes [param key] to [param value], applies and saves it.
func set_value(key: String, value: Variant) -> void:
	set(key, value)
	apply()
	save_settings()


func reset_to_defaults() -> void:
	for key: String in _defaults:
		set(key, _defaults[key])
	bindings = {}
	_apply_bindings_reset()
	apply()
	save_settings()


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Effects", effects_volume)
	_set_bus("Voices", voice_volume)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and not (mode == DisplayServer.WINDOW_MODE_WINDOWED
				and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(mode)
	var root := get_tree().root if is_inside_tree() else null
	if root != null:
		root.content_scale_factor = ui_scale
	_apply_bindings()
	changed.emit()


## Binds [param action] to [param keycodes] (replacing its keys).
func bind(action: String, keycodes: Array) -> void:
	bindings[action] = keycodes.duplicate()
	_apply_bindings()
	save_settings()
	changed.emit()


## The keys [param action] responds to, as text ("W, Up"), or just the
## first with [param first_only].
func key_names(action: String, first_only := false) -> String:
	var names := PackedStringArray()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			# Name the key as printed on this keyboard layout where the platform can tell.
			if key.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(code)
			names.append(OS.get_keycode_string(code))
	if first_only and not names.is_empty():
		return names[0]
	return ", ".join(names)


## The action already using [param keycode], or "".
func action_for_key(keycode: Key) -> String:
	for action: String in InputActions.KEY_BINDINGS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == keycode:
				return action
	return ""


func load_settings() -> void:
	if not persist:
		return
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key: String in _keys():
		if file.has_section_key("options", key):
			var value: Variant = file.get_value("options", key)
			if typeof(value) == typeof(_defaults[key]) or (typeof(_defaults[key]) == TYPE_FLOAT and typeof(value) == TYPE_INT):
				set(key, value)
	var saved: Variant = file.get_value("keys", "bindings", {})
	if saved is Dictionary:
		bindings = saved


func save_settings() -> void:
	if not persist:
		return
	var file := ConfigFile.new()
	for key: String in _keys():
		file.set_value("options", key, get(key))
	file.set_value("keys", "bindings", bindings)
	file.save(PATH)


func _keys() -> PackedStringArray:
	return PackedStringArray(["master_volume", "effects_volume", "voice_volume", "fullscreen", "ui_scale",
			"edge_scroll", "pan_speed", "health_bars", "colorblind", "game_speed"])


func _set_bus(bus: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(index, volume <= 0.0)


func _apply_bindings() -> void:
	for action: String in bindings:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for keycode: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode as Key
			InputMap.action_add_event(action, event)


func _apply_bindings_reset() -> void:
	for action: String in InputActions.KEY_BINDINGS:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for key: Key in InputActions.KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
