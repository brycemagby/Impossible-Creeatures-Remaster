extends Node
## Loads and runs tests/run_tests.gd. If that script doesn't compile, exit
## with an error instead of idling forever.


func _ready() -> void:
	var script := load("res://tests/run_tests.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("tests/run_tests.gd failed to load; see the errors above.")
		get_tree().quit(1)
		return
	var runner := Node.new()
	runner.name = "Tests"
	runner.set_script(script)
	add_child(runner)
