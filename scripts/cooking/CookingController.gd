class_name CookingController
extends Node

signal changed
signal status_changed(message: String)

enum State {
	IDLE,
	COOKING,
	READY,
}

const COOKING_KEY := "cooking"
const READY_INDICATOR_NAME := "CookingReadyIndicator"
const REFRESH_INTERVAL := 1.0

var placement: PlacementController
var inventory: InventoryModel
var item_catalog: ItemCatalog
var cooking_catalog: CookingCatalog
var cooking_ui: CookingUI
var _refresh_elapsed := 0.0


func setup(
		p_placement: PlacementController,
		p_inventory: InventoryModel,
		p_item_catalog: ItemCatalog,
		p_cooking_catalog: CookingCatalog,
		p_ui: CookingUI = null) -> void:
	placement = p_placement
	inventory = p_inventory
	item_catalog = p_item_catalog
	cooking_catalog = p_cooking_catalog
	cooking_ui = p_ui
	if cooking_ui:
		status_changed.connect(cooking_ui.set_status)
		changed.connect(cooking_ui.refresh)


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	refresh_all()


func is_station(item: PlacementItem) -> bool:
	if not item or not item_catalog:
		return false
	var definition := item_catalog.get_definition(item.definition_id)
	return definition != null and definition.is_cooking_station


func open_station(item: PlacementItem) -> bool:
	if not is_station(item):
		return false
	refresh_station(item)
	if cooking_ui:
		cooking_ui.open_station(item)
	return true


func station_state(item: PlacementItem) -> int:
	var cooking := _station_job(item)
	if cooking.is_empty():
		return State.IDLE
	return State.READY if _now() >= int(cooking.get("finish_at", 0)) else State.COOKING


func is_occupied(item: PlacementItem) -> bool:
	return station_state(item) != State.IDLE


func get_station_job(item: PlacementItem) -> Dictionary:
	return _station_job(item).duplicate(true)


func seconds_remaining(item: PlacementItem) -> int:
	var cooking := _station_job(item)
	if cooking.is_empty():
		return 0
	return maxi(int(cooking.get("finish_at", 0)) - _now(), 0)


func progress_ratio(item: PlacementItem) -> float:
	var cooking := _station_job(item)
	if cooking.is_empty():
		return 0.0
	var started_at := int(cooking.get("started_at", 0))
	var finish_at := int(cooking.get("finish_at", 0))
	if finish_at <= started_at:
		return 1.0
	return clampf(float(_now() - started_at) / float(finish_at - started_at), 0.0, 1.0)


func try_start(item: PlacementItem, recipe_id: String) -> bool:
	if not is_station(item):
		status_changed.emit("Select a Cooking Station")
		return false
	if is_occupied(item):
		status_changed.emit("Cooking Slot Occupied")
		return false
	var recipe := cooking_catalog.get_definition(recipe_id) if cooking_catalog else null
	if not recipe:
		status_changed.emit("Recipe Not Available")
		return false
	if not item_catalog.get_definition(recipe.crafted_item_id):
		status_changed.emit("Recipe Output Is Missing")
		return false
	if not inventory or not inventory.has_quantities(recipe.ingredients):
		status_changed.emit("Not Enough Ingredients")
		return false
	if not inventory.consume_quantities(recipe.ingredients):
		status_changed.emit("Not Enough Ingredients")
		return false
	var now := _now()
	item.item_metadata[COOKING_KEY] = {
		"recipe_id": recipe.recipe_id,
		"crafted_item_id": recipe.crafted_item_id,
		"started_at": now,
		"finish_at": now + recipe.cooking_time_sec,
	}
	_apply_ready_indicator(item, false)
	status_changed.emit("Cooking Started")
	changed.emit()
	return true


func try_collect(item: PlacementItem) -> bool:
	if not is_station(item):
		return false
	if station_state(item) == State.COOKING:
		status_changed.emit("Still Cooking")
		return false
	if station_state(item) != State.READY:
		status_changed.emit("Nothing To Collect")
		return false
	var cooking := _station_job(item)
	var crafted_item_id := str(cooking.get("crafted_item_id", ""))
	var crafted_definition := item_catalog.get_definition(crafted_item_id) if item_catalog else null
	if not crafted_definition:
		_clear_invalid_job(item)
		status_changed.emit("Cooking Job Was Invalid")
		changed.emit()
		return false
	if not inventory.add_instance(item_catalog.create_instance(crafted_item_id), item_catalog):
		status_changed.emit("Inventory Full")
		_apply_ready_indicator(item, true)
		return false
	item.item_metadata.erase(COOKING_KEY)
	_apply_ready_indicator(item, false)
	status_changed.emit("%s Added To Inventory" % crafted_definition.item_name)
	changed.emit()
	return true


func refresh_all() -> bool:
	if not placement:
		return false
	var any_changed := false
	for item in placement.get_placed_items():
		if item is PlacementItem:
			any_changed = refresh_station(item) or any_changed
	if any_changed:
		changed.emit()
	return any_changed


func refresh_station(item: PlacementItem) -> bool:
	if not item:
		return false
	var cooking := _station_job(item)
	if cooking.is_empty():
		_apply_ready_indicator(item, false)
		return false
	if not is_station(item):
		_clear_invalid_job(item)
		return true
	var crafted_item_id := str(cooking.get("crafted_item_id", ""))
	if (
		crafted_item_id.is_empty()
		or not item_catalog
		or not item_catalog.get_definition(crafted_item_id)
		or int(cooking.get("finish_at", 0)) <= 0
	):
		_clear_invalid_job(item)
		status_changed.emit("Invalid Cooking Job Cleared")
		return true
	_apply_ready_indicator(item, station_state(item) == State.READY)
	return false


func _station_job(item: PlacementItem) -> Dictionary:
	if not item:
		return {}
	var cooking: Variant = item.item_metadata.get(COOKING_KEY, {})
	return cooking if cooking is Dictionary else {}


func _clear_invalid_job(item: PlacementItem) -> void:
	item.item_metadata.erase(COOKING_KEY)
	_apply_ready_indicator(item, false)


func _apply_ready_indicator(item: PlacementItem, ready: bool) -> void:
	if not item or not item.is_inside_tree():
		return
	var indicator := item.get_node_or_null(READY_INDICATOR_NAME) as Label3D
	if not ready:
		if indicator:
			indicator.visible = false
		return
	if not indicator:
		indicator = Label3D.new()
		indicator.name = READY_INDICATOR_NAME
		indicator.text = "Ready To Collect"
		indicator.font_size = 30
		indicator.outline_size = 8
		indicator.modulate = Color(1.0, 0.84, 0.28, 1.0)
		indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		indicator.no_depth_test = true
		indicator.fixed_size = true
		item.add_child(indicator)
	var bounds := item.get_visual_bounds()
	indicator.position = Vector3(0.0, maxf(bounds.size.y * 0.5 + 0.4, 0.65), 0.0)
	indicator.visible = true


func _now() -> int:
	return int(Time.get_unix_time_from_system())
