extends Node
## Registers the default keyboard bindings at startup.
##
## Actions that already exist (for example ones defined in Project Settings >
## Input Map) are left untouched, so bindings can be overridden in the editor.

const KEY_BINDINGS := {
	"camera_forward": [KEY_W, KEY_UP],
	"camera_back": [KEY_S, KEY_DOWN],
	"camera_left": [KEY_A, KEY_LEFT],
	"camera_right": [KEY_D, KEY_RIGHT],
	"camera_rotate_left": [KEY_Q],
	"camera_rotate_right": [KEY_E],
	"camera_reset": [KEY_BACKSPACE],
	"deselect": [KEY_ESCAPE],
	"attack_move": [KEY_F],
	"stop": [KEY_H],
	"hold": [KEY_G],
	"patrol": [KEY_P],
	"idle_henchman": [KEY_PERIOD],
	"idle_building": [KEY_COMMA],
	"jump_to_alert": [KEY_SPACE],
	"select_lab": [KEY_HOME],
	"demolish": [KEY_DELETE],
	"pause_menu": [KEY_F10],
	"speed_up": [KEY_EQUAL, KEY_KP_ADD],
	"speed_down": [KEY_MINUS, KEY_KP_SUBTRACT],
}


func _enter_tree() -> void:
	for action: String in KEY_BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
