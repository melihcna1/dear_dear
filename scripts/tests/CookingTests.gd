extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	await process_frame
	var cooking_catalog := CookingCatalog.new()
	root.add_child(cooking_catalog)
	cooking_catalog.setup(catalog)

	_test_catalog(catalog, cooking_catalog)
	await _test_atomic_inventory(catalog)
	await _test_cooking_flow(catalog, cooking_catalog)
	await _test_main_smoke()

	print("CookingTests: PASS")
	quit()


func _test_catalog(catalog: ItemCatalog, cooking_catalog: CookingCatalog) -> void:
	assert(cooking_catalog.all_definitions().size() == 1)
	var recipe := cooking_catalog.get_definition("50000")
	assert(recipe != null)
	assert(recipe.crafted_item_id == "banana_waffles")
	assert(recipe.crafted_item_name == "Banana Waffles")
	assert(recipe.ingredients == {"banana": 2})
	assert(recipe.cooking_time_sec == 60)
	var waffles := catalog.get_definition("banana_waffles")
	assert(waffles != null)
	assert(waffles.category == "Food")
	assert(waffles.is_sellable)
	assert(not waffles.is_buyable)
	assert(not waffles.is_placeable)
	assert(waffles.sell_price == 15)
	assert(catalog.get_definition("ocak").is_cooking_station)
	assert(not catalog.get_definition("winged_sheep").is_cooking_station)
	assert(SaveService.VERSION == 5)


func _test_atomic_inventory(catalog: ItemCatalog) -> void:
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	inventory.resize(2, 1)
	assert(inventory.add_instance(catalog.create_instance("banana"), catalog))
	assert(inventory.add_instance(catalog.create_instance("banana"), catalog))
	assert(inventory.count_definition("banana") == 2)
	assert(not inventory.has_quantities({"banana": 2, "banana_seed": 1}))
	assert(not inventory.consume_quantities({"banana": 2, "banana_seed": 1}))
	assert(inventory.count_definition("banana") == 2)
	assert(inventory.add_instance(catalog.create_instance("banana_seed"), catalog))
	assert(inventory.has_quantities({"banana": 2, "banana_seed": 1}))
	assert(inventory.consume_quantities({"banana": 2, "banana_seed": 1}))
	assert(inventory.count_definition("banana") == 0)
	assert(inventory.count_definition("banana_seed") == 0)
	assert(not inventory.consume_quantities({}))
	inventory.queue_free()
	await process_frame


func _test_cooking_flow(catalog: ItemCatalog, cooking_catalog: CookingCatalog) -> void:
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	inventory.resize(5, 2)
	for _i in 6:
		assert(inventory.add_instance(catalog.create_instance("banana"), catalog))

	var placement := PlacementController.new()
	root.add_child(placement)
	await process_frame
	placement.setup(catalog, inventory)
	var placed_root := placement.get_node("PlacedItems")
	var station_a := placement.create_placeable(catalog.create_instance("ocak"))
	var station_b := placement.create_placeable(catalog.create_instance("ocak"))
	placed_root.add_child(station_a)
	placed_root.add_child(station_b)

	var controller := CookingController.new()
	root.add_child(controller)
	controller.setup(placement, inventory, catalog, cooking_catalog)
	assert(controller.try_start(station_a, "50000"))
	assert(inventory.count_definition("banana") == 4)
	assert(controller.station_state(station_a) == CookingController.State.COOKING)
	assert(not controller.try_start(station_a, "50000"))
	assert(inventory.count_definition("banana") == 4)
	assert(controller.try_start(station_b, "50000"))
	assert(inventory.count_definition("banana") == 2)
	assert(controller.is_occupied(station_a))
	assert(controller.is_occupied(station_b))

	_make_ready(station_a)
	assert(controller.station_state(station_a) == CookingController.State.READY)
	assert(controller.refresh_station(station_a) == false)
	var indicator := station_a.get_node_or_null(CookingController.READY_INDICATOR_NAME) as Label3D
	assert(indicator != null and indicator.visible)
	assert(controller.try_collect(station_a))
	assert(inventory.count_definition("banana_waffles") == 1)
	assert(controller.station_state(station_a) == CookingController.State.IDLE)
	assert(not indicator.visible)

	_make_ready(station_b)
	var save_service := SaveService.new()
	save_service.save_path = "user://cooking_tests_savegame.json"
	assert(save_service.save_game(inventory, [station_b]))
	var saved := save_service.load_game()
	assert(saved.get("version", 0) == 5)
	assert(saved["world"][0]["metadata"].has(CookingController.COOKING_KEY))

	var restored_placement := PlacementController.new()
	root.add_child(restored_placement)
	await process_frame
	restored_placement.setup(catalog, inventory)
	restored_placement.load_world(saved.get("world", []))
	var restored_controller := CookingController.new()
	root.add_child(restored_controller)
	restored_controller.setup(restored_placement, inventory, catalog, cooking_catalog)
	assert(not restored_controller.refresh_all())
	var restored_station: PlacementItem = restored_placement.get_placed_items()[0]
	assert(restored_controller.station_state(restored_station) == CookingController.State.READY)
	var restored_indicator := restored_station.get_node_or_null(CookingController.READY_INDICATOR_NAME) as Label3D
	assert(restored_indicator != null and restored_indicator.visible)
	assert(restored_placement.is_item_edit_locked(restored_station))

	restored_placement._select_item(restored_station)
	var placed_count := restored_placement.get_placed_items().size()
	assert(not restored_placement.pick_up_selected())
	restored_placement._duplicate_selected()
	assert(restored_placement.get_placed_items().size() == placed_count)
	restored_placement._delete_selected()
	await process_frame
	assert(restored_placement.get_placed_items().size() == placed_count)

	var full_inventory := InventoryModel.new()
	root.add_child(full_inventory)
	await process_frame
	full_inventory.resize(1, 1)
	assert(full_inventory.add_instance(catalog.create_instance("winged_sheep"), catalog))
	var full_station := placement.create_placeable(catalog.create_instance("ocak"))
	placed_root.add_child(full_station)
	full_station.item_metadata[CookingController.COOKING_KEY] = _ready_job()
	var full_controller := CookingController.new()
	root.add_child(full_controller)
	full_controller.setup(placement, full_inventory, catalog, cooking_catalog)
	assert(not full_controller.try_collect(full_station))
	assert(full_station.item_metadata.has(CookingController.COOKING_KEY))
	assert(full_inventory.count_definition("banana_waffles") == 0)
	full_inventory.clear()
	assert(full_inventory.add_instance(catalog.create_instance("banana_waffles"), catalog))
	assert(full_controller.try_collect(full_station))
	assert(full_inventory.count_definition("banana_waffles") == 2)

	var invalid_station := placement.create_placeable(catalog.create_instance("ocak"))
	placed_root.add_child(invalid_station)
	invalid_station.item_metadata[CookingController.COOKING_KEY] = {
		"recipe_id": "missing",
		"crafted_item_id": "missing_item",
		"started_at": 1,
		"finish_at": 2,
	}
	assert(controller.refresh_station(invalid_station))
	assert(not invalid_station.item_metadata.has(CookingController.COOKING_KEY))
	assert(not placement.is_item_edit_locked(invalid_station))

	var market := MarketModel.new()
	root.add_child(market)
	var wallet := WalletModel.new()
	root.add_child(wallet)
	await process_frame
	var waffle_slot := _find_slot(inventory, "banana_waffles")
	var coins_before := wallet.coins
	assert(market.sell_slot_quantity(waffle_slot, 1, wallet, inventory, catalog))
	assert(wallet.coins == coins_before + 15)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_service.save_path))
	placement.queue_free()
	restored_placement.queue_free()
	controller.queue_free()
	restored_controller.queue_free()
	full_controller.queue_free()
	inventory.queue_free()
	full_inventory.queue_free()
	market.queue_free()
	wallet.queue_free()
	await process_frame


func _test_main_smoke() -> void:
	var save_path := "user://cooking_main_smoke_savegame.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var main := preload("res://scripts/Main.gd").new()
	main.save_service.save_path = save_path
	root.add_child(main)
	await process_frame
	if main.onboarding_ui.is_open():
		main.onboarding_ui._confirm()
	assert(main.cooking != null)
	assert(main.cooking_ui != null)
	assert(main.cooking_catalog.all_definitions().size() == 1)
	var station := main.placement.create_placeable(main.catalog.create_instance("ocak"))
	main.placement.get_node("PlacedItems").add_child(station)
	main._on_placed_item_clicked(station)
	assert(main.cooking_ui.is_open())
	assert(not main.placement.interaction_enabled)
	main.cooking_ui.close()
	assert(main.placement.interaction_enabled)
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _make_ready(station: PlacementItem) -> void:
	var job: Dictionary = station.item_metadata[CookingController.COOKING_KEY]
	job["finish_at"] = int(Time.get_unix_time_from_system()) - 1
	station.item_metadata[CookingController.COOKING_KEY] = job


func _ready_job() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	return {
		"recipe_id": "50000",
		"crafted_item_id": "banana_waffles",
		"started_at": now - 60,
		"finish_at": now - 1,
	}


func _find_slot(inventory: InventoryModel, definition_id: String) -> int:
	for i in inventory.slots.size():
		var stack := inventory.get_slot_stack(i)
		if not stack.is_empty() and stack[0].definition_id == definition_id:
			return i
	return -1
