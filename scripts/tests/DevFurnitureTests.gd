extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	await process_frame
	var furniture: Array = []
	var category_counts := {"Decor": 0, "Electronics": 0, "Garden": 0, "Seating": 0}
	var category_prices := {"Decor": 100, "Electronics": 300, "Garden": 150, "Seating": 200}
	for definition in catalog.all_definitions():
		if definition.model_path.begins_with(ItemCatalog.DEV_ASSET_ROOT + "/furniture/"):
			furniture.append(definition)
			category_counts[definition.sub_category] += 1
			assert(definition.buy_price == category_prices[definition.sub_category])
			assert(definition.is_buyable and definition.is_placeable)
			assert(not definition.is_starter)
	furniture.sort_custom(func(a, b): return a.definition_id < b.definition_id)
	assert(furniture.size() == 72)
	assert(category_counts == {"Decor": 31, "Electronics": 4, "Garden": 6, "Seating": 31})

	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	inventory.restore_missing_unique_items(catalog)
	for definition in furniture:
		assert(not inventory.contains_definition(definition.definition_id))

	var wallet := WalletModel.new()
	root.add_child(wallet)
	await process_frame
	wallet.coins = 20000
	var market := MarketModel.new()
	root.add_child(market)
	var placement := PlacementController.new()
	root.add_child(placement)
	await process_frame
	placement.setup(catalog, inventory)

	var expected_spend := 0
	for index in furniture.size():
		var definition: PlaceableItemDefinition = furniture[index]
		assert(placement.begin_market_preview(definition.definition_id))
		assert(placement.confirm_market_preview_position())
		assert(market.purchase_single_placeable(definition.definition_id, wallet, catalog))
		var placed := placement.commit_market_preview()
		assert(placed != null)
		placed.global_position.x = float(index % 9) * 0.5 - 2.0
		placed.global_position.z = float(index / 9) * 0.5 - 2.0
		expected_spend += definition.buy_price
	assert(placement.get_placed_items().size() == 72)
	assert(wallet.coins == 20000 - expected_spend)

	var save_path := "user://dev_furniture_tests_savegame.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var save_service := SaveService.new()
	save_service.save_path = save_path
	assert(save_service.save_game(inventory, placement.get_placed_items(), wallet))
	var saved := save_service.load_game()
	assert(saved.get("world", []).size() == 72)

	var restored := PlacementController.new()
	root.add_child(restored)
	await process_frame
	restored.setup(catalog, inventory)
	restored.load_world(saved.get("world", []))
	assert(restored.get_placed_items().size() == 72)
	var restored_ids: Dictionary = {}
	for item in restored.get_placed_items():
		restored_ids[item.definition_id] = true
	for definition in furniture:
		assert(restored_ids.has(definition.definition_id))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("DevFurnitureTests: PASS")
	quit()
