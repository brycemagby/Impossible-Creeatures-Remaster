class_name CombinerScreen
extends Control
## The creature combiner: pick two animals, choose which one each body part
## comes from, preview the hybrid and its stats, and build an army of up to
## Armies.MAX_SIZE designs for the Creature Chamber to produce.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const Slot := CreatureDesign.Slot
const PREVIEW_SPIN := 0.6

var animals: Array[AnimalData] = []
## The design being edited.
var design: CreatureDesign
var army: Array[CreatureDesign] = []
## Index in [member army] being edited, or -1 for a new design.
var editing_index := -1

var list_a: ItemList
var list_b: ItemList
var name_edit: LineEdit
var stats_label: Label
var army_list: ItemList
var army_title: Label
var message_label: Label
var add_button: Button
## Per slot: [button for A, button for B, (wings only) button for none].
var slot_buttons: Array = []
var preview_pivot: Node3D
var preview_model: CreatureModel
var preview_camera: Camera3D


func _ready() -> void:
	animals = Armies.all_animals()
	for saved in Armies.designs(0):
		army.append(saved.duplicate_design())
	_build_layout()
	if army.is_empty():
		var picks: Array[int] = [0, 0, 1, 1, 0, CreatureDesign.NONE]
		design = CreatureDesign.create(animals[0], animals[1], picks)
		_sync_lists()
		refresh()
	else:
		select_army_item(0)


func _process(delta: float) -> void:
	preview_pivot.rotate_y(PREVIEW_SPIN * delta)


# --- Editing ------------------------------------------------------------------

func set_animals(a: AnimalData, b: AnimalData) -> void:
	design.animal_a = a
	design.animal_b = b
	# Drop wings that the new animal doesn't have.
	design.set_pick(Slot.WINGS, design.picks[Slot.WINGS])
	_sync_lists()
	refresh()


func set_pick(slot: Slot, pick: int) -> void:
	design.set_pick(slot, pick)
	refresh()


func current_stats() -> CreatureStats:
	return CreatureCombiner.build_stats(design)


## Adds the current design to the army as a new entry. Returns false if full.
func add_to_army() -> bool:
	if army.size() >= Armies.MAX_SIZE:
		_show_message("Your army is full (%d creatures). Remove one first." % Armies.MAX_SIZE)
		return false
	army.append(design.duplicate_design())
	editing_index = army.size() - 1
	_refresh_army()
	return true


## Saves the edits back over the selected army entry.
func update_selected() -> void:
	if editing_index < 0 or editing_index >= army.size():
		add_to_army()
		return
	army[editing_index] = design.duplicate_design()
	_refresh_army()


func remove_selected() -> void:
	if editing_index < 0 or editing_index >= army.size():
		return
	army.remove_at(editing_index)
	editing_index = -1
	_refresh_army()


func select_army_item(index: int) -> void:
	if index < 0 or index >= army.size():
		return
	editing_index = index
	design = army[index].duplicate_design()
	_sync_lists()
	refresh()


## Stores the army for the Creature Chamber and on disk.
func save_army() -> void:
	Armies.set_designs(0, army)
	var error := Armies.save_player_army()
	_show_message("Army saved." if error == OK else "Couldn't save the army (error %d)." % error)


# --- Display ------------------------------------------------------------------

func refresh() -> void:
	var stats := current_stats()
	var recipe := CreatureCombiner.make_recipe(design)
	name_edit.placeholder_text = CreatureDesign.generated_name(design.animal_a, design.animal_b)
	if name_edit.text != design.custom_name:
		name_edit.text = design.custom_name

	for slot in Slot.size():
		var buttons: Array = slot_buttons[slot]
		buttons[0].text = design.animal_a.display_name
		buttons[1].text = design.animal_b.display_name
		if slot == Slot.WINGS:
			buttons[0].disabled = not design.animal_a.has_wings
			buttons[1].disabled = not design.animal_b.has_wings
			buttons[2].set_pressed_no_signal(design.picks[slot] == CreatureDesign.NONE)
		buttons[0].set_pressed_no_signal(design.picks[slot] == CreatureDesign.FROM_A)
		buttons[1].set_pressed_no_signal(design.picks[slot] == CreatureDesign.FROM_B)

	var lines := PackedStringArray()
	lines.append("Level %d%s" % [stats.level, "  (needs research level %d to produce)" % stats.level if stats.level > 1 else ""])
	lines.append("Cost  %d coal%s   %.1fs" % [recipe.cost_coal,
			"  %d electricity" % recipe.cost_electricity if recipe.cost_electricity > 0 else "", recipe.build_time])
	lines.append("")
	lines.append("Health   %d" % stats.max_health)
	lines.append("Armor    %d" % stats.armor)
	if stats.is_ranged():
		lines.append("Attack   %.1f ranged (quills, %dm) every %.2fs" % [stats.attack_damage, stats.attack_range, stats.attack_cooldown])
	else:
		lines.append("Attack   %.1f melee every %.2fs" % [stats.attack_damage, stats.attack_cooldown])
	lines.append("Speed    %.1f" % stats.move_speed)
	lines.append("Size     %.2f" % stats.size)
	var abilities := PackedStringArray()
	if stats.can_fly:
		abilities.append("Flying")
	if stats.poison_dps > 0.0:
		abilities.append("Poison (%d/s for %ds)" % [stats.poison_dps, stats.poison_duration])
	if stats.is_ranged():
		abilities.append("Ranged")
	if stats.can_charge:
		abilities.append("Charge")
	if stats.can_leap:
		abilities.append("Leap")
	lines.append("")
	lines.append("Abilities: " + (", ".join(abilities) if not abilities.is_empty() else "none"))
	if CreatureCombiner.too_heavy_to_fly(design):
		lines.append("Too heavy to fly (size over %.1f)" % CreatureCombiner.MAX_FLYING_SIZE)
	stats_label.text = "\n".join(lines)

	preview_model.build(design)
	preview_model.scale = Vector3.ONE * stats.size
	preview_camera.position = Vector3(0, 0.9 + stats.size * 0.7, 1.5 + stats.size * 1.2)
	preview_camera.look_at(Vector3(0, 0.7 * stats.size, 0))
	add_button.disabled = army.size() >= Armies.MAX_SIZE


func _refresh_army() -> void:
	army_list.clear()
	for entry in army:
		var stats := CreatureCombiner.build_stats(entry)
		army_list.add_item("%s   (L%d)" % [entry.display_name(), stats.level])
	if editing_index >= 0 and editing_index < army.size():
		army_list.select(editing_index)
	army_title.text = "Army  %d / %d" % [army.size(), Armies.MAX_SIZE]
	add_button.disabled = army.size() >= Armies.MAX_SIZE


func _sync_lists() -> void:
	list_a.select(animals.find(design.animal_a))
	list_b.select(animals.find(design.animal_b))
	_refresh_army()


func _show_message(text: String) -> void:
	message_label.text = text


# --- Layout -------------------------------------------------------------------

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color(0.11, 0.12, 0.11)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "CREATURE COMBINER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	root.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	root.add_child(columns)

	# Animals
	var animal_column := VBoxContainer.new()
	animal_column.custom_minimum_size.x = 200
	columns.add_child(animal_column)
	list_a = _animal_list(animal_column, "Animal A")
	list_b = _animal_list(animal_column, "Animal B")
	list_a.item_selected.connect(func(i: int) -> void: set_animals(animals[i], design.animal_b))
	list_b.item_selected.connect(func(i: int) -> void: set_animals(design.animal_a, animals[i]))

	# Preview and body parts
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	middle.add_child(_build_preview())
	var parts := GridContainer.new()
	parts.columns = 4
	parts.add_theme_constant_override("h_separation", 8)
	middle.add_child(parts)
	for slot in Slot.size():
		var label := Label.new()
		label.text = CreatureDesign.SLOT_NAMES[slot]
		label.custom_minimum_size.x = 100
		parts.add_child(label)
		var group := ButtonGroup.new()
		var buttons := []
		var picks := [CreatureDesign.FROM_A, CreatureDesign.FROM_B]
		if slot == Slot.WINGS:
			picks.append(CreatureDesign.NONE)
		for pick in picks:
			var button := Button.new()
			button.toggle_mode = true
			button.button_group = group
			button.custom_minimum_size.x = 130
			button.text = "None" if pick == CreatureDesign.NONE else ""
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_color_override("font_pressed_color", Color(1.0, 0.8, 0.35))
			button.add_theme_color_override("font_hover_pressed_color", Color(1.0, 0.85, 0.45))
			button.pressed.connect(set_pick.bind(slot, pick))
			parts.add_child(button)
			buttons.append(button)
		if slot != Slot.WINGS:
			parts.add_child(Control.new())
		slot_buttons.append(buttons)

	# Stats and army
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 360
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	name_edit = LineEdit.new()
	name_edit.max_length = 24
	name_edit.text_changed.connect(func(text: String) -> void:
		design.custom_name = text.strip_edges()
		name_edit.placeholder_text = CreatureDesign.generated_name(design.animal_a, design.animal_b))
	right.add_child(name_edit)
	stats_label = Label.new()
	stats_label.custom_minimum_size.y = 250
	right.add_child(stats_label)
	var edit_row := HBoxContainer.new()
	right.add_child(edit_row)
	add_button = _button(edit_row, "Add to army", add_to_army)
	_button(edit_row, "Update", update_selected)
	_button(edit_row, "Remove", remove_selected)
	army_title = Label.new()
	right.add_child(army_title)
	army_list = ItemList.new()
	army_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	army_list.item_selected.connect(select_army_item)
	right.add_child(army_list)
	message_label = Label.new()
	message_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.4))
	right.add_child(message_label)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	_button(bottom, "Back", func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	_button(bottom, "Save army", save_army)
	_button(bottom, "Save and play", func() -> void:
		save_army()
		get_tree().change_scene_to_file(GameSettings.map_path()))


func _animal_list(parent: Control, heading: String) -> ItemList:
	var label := Label.new()
	label.text = heading
	parent.add_child(label)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for animal in animals:
		var swatch := Image.create(14, 14, false, Image.FORMAT_RGB8)
		swatch.fill(animal.color)
		list.add_item(animal.display_name + ("  (wings)" if animal.has_wings else ""), ImageTexture.create_from_image(swatch))
	parent.add_child(list)
	return list


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(460, 340)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	container.add_child(viewport)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.24, 0.2)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	viewport.add_child(light)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.5
	disc.bottom_radius = 2.5
	disc.height = 0.05
	ground.mesh = disc
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.3, 0.38, 0.25)
	ground.material_override = ground_material
	viewport.add_child(ground)

	preview_pivot = Node3D.new()
	preview_pivot.rotation_degrees.y = -35.0
	viewport.add_child(preview_pivot)
	preview_model = CreatureModel.new()
	preview_pivot.add_child(preview_model)
	preview_camera = Camera3D.new()
	viewport.add_child(preview_camera)
	return container


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 40)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
