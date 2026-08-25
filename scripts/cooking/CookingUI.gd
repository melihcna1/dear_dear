class_name CookingUI
extends CanvasLayer

signal closed

const PANEL_SIZE := Vector2(600.0, 520.0)
const ACTIVE_REFRESH_INTERVAL := 0.25

var controller: CookingController
var inventory: InventoryModel
var item_catalog: ItemCatalog
var cooking_catalog: CookingCatalog
var active_station: PlacementItem

var panel: PanelContainer
var title_label: Label
var recipe_section: VBoxContainer
var recipe_list: VBoxContainer
var detail_label: Label
var progress_bar: ProgressBar
var status_label: Label
var action_button: Button
var toast_panel: PanelContainer
var toast_label: Label

var _selected_recipe_id := ""
var _status_message := ""
var _active_refresh_elapsed := 0.0
var _toast_remaining := 0.0


func _ready() -> void:
	layer = 20
	_build_panel()
	_build_toast()


func setup(
		p_controller: CookingController,
		p_inventory: InventoryModel,
		p_item_catalog: ItemCatalog,
		p_cooking_catalog: CookingCatalog) -> void:
	controller = p_controller
	inventory = p_inventory
	item_catalog = p_item_catalog
	cooking_catalog = p_cooking_catalog
	if inventory:
		inventory.changed.connect(refresh)


func _process(delta: float) -> void:
	if _toast_remaining > 0.0:
		_toast_remaining -= delta
		if _toast_remaining <= 0.0:
			toast_panel.visible = false
	if not is_open() or not controller or not is_instance_valid(active_station):
		return
	if controller.station_state(active_station) == CookingController.State.IDLE:
		return
	_active_refresh_elapsed += delta
	if _active_refresh_elapsed >= ACTIVE_REFRESH_INTERVAL:
		_active_refresh_elapsed = 0.0
		refresh()


func open_station(station: PlacementItem) -> void:
	active_station = station
	_status_message = ""
	_active_refresh_elapsed = 0.0
	if _selected_recipe_id.is_empty() and cooking_catalog and not cooking_catalog.definitions.is_empty():
		_selected_recipe_id = cooking_catalog.definitions[0].recipe_id
	panel.visible = true
	refresh()


func close() -> void:
	if not panel or not panel.visible:
		return
	panel.visible = false
	active_station = null
	_status_message = ""
	closed.emit()


func is_open() -> bool:
	return panel != null and panel.visible


func set_status(message: String) -> void:
	if not is_open():
		show_toast(message)
		return
	_status_message = message
	refresh()


func show_toast(message: String) -> void:
	if message.is_empty():
		return
	toast_label.text = message
	toast_panel.visible = true
	_toast_remaining = 2.5


func refresh() -> void:
	if not is_open():
		return
	if not active_station or not is_instance_valid(active_station):
		close()
		return
	var state := controller.station_state(active_station) if controller else CookingController.State.IDLE
	if state == CookingController.State.IDLE:
		_render_idle()
	else:
		_render_active(state)


func _render_idle() -> void:
	title_label.text = "Cooking"
	recipe_section.visible = true
	progress_bar.visible = false
	action_button.visible = true
	var recipes := cooking_catalog.all_definitions() if cooking_catalog else []
	if recipes.is_empty():
		_selected_recipe_id = ""
		_clear_children(recipe_list)
		detail_label.text = "No recipes are configured."
		status_label.text = "Recipe List Empty"
		action_button.text = "Start Cooking"
		action_button.disabled = true
		return
	if not cooking_catalog.get_definition(_selected_recipe_id):
		_selected_recipe_id = recipes[0].recipe_id
	_refresh_recipe_list(recipes)
	var recipe := cooking_catalog.get_definition(_selected_recipe_id)
	var crafted := item_catalog.get_definition(recipe.crafted_item_id) if item_catalog else null
	detail_label.text = "%s\n\nRequires:\n%s\n\nCooking Time: %d seconds\nProduces: 1 %s" % [
		recipe.crafted_item_name,
		_ingredient_lines(recipe),
		recipe.cooking_time_sec,
		crafted.item_name if crafted else recipe.crafted_item_name,
	]
	var can_start := inventory != null and inventory.has_quantities(recipe.ingredients)
	action_button.text = "Start Cooking"
	action_button.disabled = not can_start
	status_label.text = _status_message if not _status_message.is_empty() else ("Ready To Cook" if can_start else "Not Enough Ingredients")


func _render_active(state: int) -> void:
	recipe_section.visible = false
	var job := controller.get_station_job(active_station)
	var crafted_item_id := str(job.get("crafted_item_id", ""))
	var crafted := item_catalog.get_definition(crafted_item_id) if item_catalog else null
	var crafted_name := crafted.item_name if crafted else crafted_item_id
	title_label.text = "Cooking - %s" % crafted_name
	if state == CookingController.State.COOKING:
		var remaining := controller.seconds_remaining(active_station)
		detail_label.text = "%s is cooking.\n\nTime Remaining: %s" % [crafted_name, _format_seconds(remaining)]
		progress_bar.visible = true
		progress_bar.value = controller.progress_ratio(active_station) * 100.0
		action_button.visible = false
		status_label.text = _status_message if not _status_message.is_empty() else "Cooking"
	else:
		detail_label.text = "%s is complete.\n\nCollect it when inventory space is available." % crafted_name
		progress_bar.visible = true
		progress_bar.value = 100.0
		action_button.visible = true
		action_button.text = "Collect"
		action_button.disabled = false
		status_label.text = _status_message if not _status_message.is_empty() else "Ready To Collect"


func _refresh_recipe_list(recipes: Array[CookingDefinition]) -> void:
	_clear_children(recipe_list)
	for recipe in recipes:
		var button := Button.new()
		button.text = "%s\n%s | %d sec" % [
			recipe.crafted_item_name,
			_ingredient_summary(recipe),
			recipe.cooking_time_sec,
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = recipe.recipe_id == _selected_recipe_id
		button.pressed.connect(_select_recipe.bind(recipe.recipe_id))
		recipe_list.add_child(button)


func _select_recipe(recipe_id: String) -> void:
	_selected_recipe_id = recipe_id
	_status_message = ""
	refresh()


func _on_action_pressed() -> void:
	if not controller or not active_station:
		return
	if controller.station_state(active_station) == CookingController.State.IDLE:
		controller.try_start(active_station, _selected_recipe_id)
	else:
		controller.try_collect(active_station)


func _ingredient_lines(recipe: CookingDefinition) -> String:
	var lines: Array[String] = []
	for ingredient_id in recipe.ingredients.keys():
		var item_definition := item_catalog.get_definition(str(ingredient_id)) if item_catalog else null
		var owned := inventory.count_definition(str(ingredient_id)) if inventory else 0
		lines.append("%s: %d/%d" % [
			item_definition.item_name if item_definition else str(ingredient_id),
			owned,
			int(recipe.ingredients[ingredient_id]),
		])
	return "\n".join(lines)


func _ingredient_summary(recipe: CookingDefinition) -> String:
	var parts: Array[String] = []
	for ingredient_id in recipe.ingredients.keys():
		var item_definition := item_catalog.get_definition(str(ingredient_id)) if item_catalog else null
		var owned := inventory.count_definition(str(ingredient_id)) if inventory else 0
		parts.append("%s %d/%d" % [
			item_definition.item_name if item_definition else str(ingredient_id),
			owned,
			int(recipe.ingredients[ingredient_id]),
		])
	return ", ".join(parts)


func _format_seconds(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "CookingPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -PANEL_SIZE * 0.5
	panel.custom_minimum_size = PANEL_SIZE
	panel.visible = false
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	title_label = Label.new()
	title_label.text = "Cooking"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	header.add_child(close_button)

	recipe_section = VBoxContainer.new()
	recipe_section.add_theme_constant_override("separation", 6)
	recipe_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(recipe_section)
	var recipe_heading := Label.new()
	recipe_heading.text = "Recipes"
	recipe_heading.add_theme_font_size_override("font_size", 18)
	recipe_section.add_child(recipe_heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 145.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_section.add_child(scroll)
	recipe_list = VBoxContainer.new()
	recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list.add_theme_constant_override("separation", 5)
	scroll.add_child(recipe_list)

	detail_label = Label.new()
	detail_label.custom_minimum_size = Vector2(0.0, 120.0)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layout.add_child(detail_label)

	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = true
	progress_bar.visible = false
	layout.add_child(progress_bar)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.modulate = Color(1.0, 0.82, 0.45, 1.0)
	layout.add_child(status_label)

	action_button = Button.new()
	action_button.custom_minimum_size = Vector2(0.0, 42.0)
	action_button.pressed.connect(_on_action_pressed)
	layout.add_child(action_button)


func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.name = "CookingStatusToast"
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position = Vector2(-230.0, 22.0)
	toast_panel.custom_minimum_size = Vector2(460.0, 58.0)
	toast_panel.visible = false
	add_child(toast_panel)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_panel.add_child(toast_label)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
