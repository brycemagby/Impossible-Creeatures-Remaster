class_name MultiplayerLobby
extends Control
## Play online: host a game or join one by address, then (host) pick the map
## and fog and start once the other player is in. See Net.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var name_edit: LineEdit
var connect_box: VBoxContainer
var host_port: SpinBox
var join_address: LineEdit
var join_port: SpinBox
var lobby_box: VBoxContainer
var players_label: Label
var map_option: OptionButton
var map_description: Label
var fog_check: CheckBox
var address_hint: Label
var status_label: Label
var back_button: Button
var start_button: Button


func _ready() -> void:
	add_child(DecoBackdrop.new())
	if Net.player_name == "Player":
		Net.player_name = _default_name()

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var title := Label.new()
	title.text = "PLAY ONLINE"
	UiTheme.style_title(title, 44)
	column.add_child(title)

	column.add_child(_heading("Your name"))
	name_edit = LineEdit.new()
	name_edit.text = Net.player_name
	name_edit.max_length = 20
	name_edit.text_changed.connect(func(text: String) -> void: Net.player_name = Net._clean_name(text))
	column.add_child(name_edit)

	# Not connected yet: host or join.
	connect_box = VBoxContainer.new()
	connect_box.add_theme_constant_override("separation", 10)
	column.add_child(connect_box)
	connect_box.add_child(_heading("Host a game"))
	var host_row := HBoxContainer.new()
	connect_box.add_child(host_row)
	host_row.add_child(_dim_label("Port"))
	host_port = _port_box()
	host_row.add_child(host_port)
	var host_button := _button("Host", host_game)
	host_row.add_child(host_button)

	connect_box.add_child(_heading("Join a game"))
	var join_row := HBoxContainer.new()
	connect_box.add_child(join_row)
	join_address = LineEdit.new()
	join_address.placeholder_text = "Host's IP address"
	join_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_address.text_submitted.connect(func(_text: String) -> void: join_game())
	join_row.add_child(join_address)
	join_port = _port_box()
	join_row.add_child(join_port)
	join_row.add_child(_button("Join", join_game))

	# Connected: who's here, and the host's match settings.
	lobby_box = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 10)
	column.add_child(lobby_box)
	lobby_box.add_child(_heading("Players"))
	players_label = Label.new()
	lobby_box.add_child(players_label)
	lobby_box.add_child(_heading("Map"))
	map_option = OptionButton.new()
	for map in GameSettings.MAPS:
		map_option.add_item(map.name)
	map_option.item_selected.connect(func(index: int) -> void: Net.set_setting("map_index", index))
	lobby_box.add_child(map_option)
	map_description = _dim_label("")
	map_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_box.add_child(map_description)
	fog_check = CheckBox.new()
	fog_check.text = "Fog of war"
	fog_check.toggled.connect(func(on: bool) -> void: Net.set_setting("fog", on))
	lobby_box.add_child(fog_check)

	address_hint = _dim_label("")
	address_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(address_hint)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", UiTheme.WARNING)
	column.add_child(status_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	back_button = _button("Back", go_back)
	buttons.add_child(back_button)
	start_button = _button("Start", func() -> void: Net.start_match())
	buttons.add_child(start_button)

	Net.lobby_changed.connect(refresh)
	Net.connection_failed.connect(func(reason: String) -> void:
		status_label.text = reason
		refresh())
	Net.disconnected.connect(func(reason: String) -> void:
		status_label.text = reason
		refresh())
	refresh()


func host_game() -> void:
	var error := Net.host(int(host_port.value))
	if error != OK:
		status_label.text = "Couldn't host on port %d (is another game using it?)" % int(host_port.value)
	else:
		status_label.text = ""
	refresh()


func join_game() -> void:
	var address := join_address.text.strip_edges()
	if address == "":
		status_label.text = "Type the host's IP address first"
		return
	var error := Net.join(address, int(join_port.value))
	status_label.text = "Connecting to %s..." % address if error == OK else "Couldn't connect to %s" % address
	refresh()


func go_back() -> void:
	if Net.is_online():
		Net.leave()
		status_label.text = ""
		refresh()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func refresh() -> void:
	var joined := Net.is_host() or (Net.is_client() and not Net.players.is_empty())
	connect_box.visible = not Net.is_online()
	lobby_box.visible = joined
	name_edit.editable = not Net.is_online()
	back_button.text = "Leave" if Net.is_online() else "Back"
	start_button.visible = Net.is_host()
	start_button.disabled = not Net.can_start()
	map_option.disabled = not Net.is_host()
	fog_check.disabled = not Net.is_host()
	map_option.select(Net.settings.map_index)
	map_description.text = GameSettings.MAPS[Net.settings.map_index].description
	fog_check.set_pressed_no_signal(Net.settings.fog)
	var lines := PackedStringArray()
	var peers: Array = Net.players.keys()
	peers.sort_custom(func(a: int, b: int) -> bool: return Net.players[a].team < Net.players[b].team)
	for peer: int in peers:
		var entry: Dictionary = Net.players[peer]
		lines.append("%s%s%s" % [entry.name, "  (host)" if peer == 1 else "",
				"  (you)" if peer == multiplayer.get_unique_id() else ""])
	if Net.is_host() and Net.players.size() < Net.MAX_PLAYERS:
		lines.append("Waiting for someone to join...")
	players_label.text = "\n".join(lines)
	if Net.is_host():
		var addresses := Net.local_addresses()
		address_hint.text = ("On your network, others join with %s (port %d). Over the internet they need your "
				+ "public IP address, and UDP port %d forwarded to this computer on your router.") % [
				" or ".join(addresses) if not addresses.is_empty() else "this computer's address",
				int(host_port.value), int(host_port.value)]
	elif not Net.is_online():
		address_hint.text = "Ask the host for their IP address. Both players need the same version of the game."
	else:
		address_hint.text = "The host picks the map and starts the match." if joined else ""
	if joined and Net.is_client():
		status_label.text = ""


func _default_name() -> String:
	var user := OS.get_environment("USERNAME")
	if user == "":
		user = OS.get_environment("USER")
	return Net._clean_name(user.capitalize())


func _port_box() -> SpinBox:
	var box := SpinBox.new()
	box.min_value = 1024
	box.max_value = 65535
	box.value = Net.DEFAULT_PORT
	box.custom_minimum_size.x = 120
	return box


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(140, 44)
	button.pressed.connect(action)
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	UiTheme.style_heading(label, 18)
	return label


func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	return label
