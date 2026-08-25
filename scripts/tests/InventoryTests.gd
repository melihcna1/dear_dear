extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	await process_frame
	assert(catalog.all_definitions().size() >= 10)
	assert(_count_model_items(catalog) == 277)

	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	assert(inventory.slots.size() == 50)
	inventory.seed_defaults(catalog)

	assert(_count_items(inventory) == 23)
	assert(_find_stack(inventory, "candle_ver2").size() == 8)
	assert(_find_stack(inventory, "basic_pot").size() == 4)
	assert(_find_stack(inventory, "winged_sheep").size() == 1)

	var candle_slot := _find_slot(inventory, "candle_ver2")
	var empty_slot := _find_empty_slot(inventory)
	inventory.move_stack(candle_slot, empty_slot, catalog, true)
	assert(inventory.get_slot_stack(candle_slot).size() == 4)
	assert(inventory.get_slot_stack(empty_slot).size() == 4)

	var reserved := inventory.reserve_one(empty_slot)
	assert(reserved != null)
	var committed := inventory.commit_reserved(empty_slot, reserved.instance_id)
	assert(committed.instance_id == reserved.instance_id)
	assert(inventory.get_slot_stack(empty_slot).size() == 3)

	var sheep_slot := _find_slot(inventory, "winged_sheep")
	inventory.get_slot_stack(sheep_slot).clear()
	assert(not inventory.contains_definition("winged_sheep"))
	assert(inventory.restore_missing_unique_items(catalog) == 1)
	assert(inventory.contains_definition("winged_sheep"))

	var snapshot := inventory.to_dict()
	var restored := InventoryModel.new()
	root.add_child(restored)
	await process_frame
	restored.load_dict(snapshot)
	assert(_count_items(restored) == _count_items(inventory))

	for definition in catalog.all_definitions():
		if definition.is_placeable:
			assert(definition.model_scene != null or not definition.model_path.is_empty())

	var wallet := WalletModel.new()
	root.add_child(wallet)
	await process_frame
	assert(wallet.coins == WalletModel.DEFAULT_COINS)
	assert(wallet.spend(100))
	assert(wallet.coins == WalletModel.DEFAULT_COINS - 100)
	wallet.earn(50)
	assert(wallet.coins == WalletModel.DEFAULT_COINS - 50)

	var market := MarketModel.new()
	root.add_child(market)
	assert(not market.add_to_cart("banana", 11))
	assert(market.add_to_cart("banana", 10))
	assert(not market.add_to_cart("banana", 1))
	assert(int(market.cart["banana"]) == 10)

	var blocked_inventory := InventoryModel.new()
	root.add_child(blocked_inventory)
	await process_frame
	blocked_inventory.resize(1, 1)
	assert(blocked_inventory.add_instance(catalog.create_instance("winged_sheep"), catalog))
	market.clear_cart()
	assert(market.add_to_cart("turntable", 1))
	assert(not market.purchase(wallet, blocked_inventory, catalog))
	assert(not market.cart.is_empty())

	var poor_wallet := WalletModel.new()
	root.add_child(poor_wallet)
	await process_frame
	poor_wallet.coins = 0
	var purchase_inventory := InventoryModel.new()
	root.add_child(purchase_inventory)
	await process_frame
	market.clear_cart()
	assert(market.add_to_cart("banana", 1))
	assert(not market.purchase(poor_wallet, purchase_inventory, catalog))
	assert(not market.cart.is_empty())

	wallet.coins = 100
	market.clear_cart()
	assert(market.add_to_cart("banana", 3))
	assert(market.purchase(wallet, purchase_inventory, catalog))
	assert(wallet.coins == 76)
	assert(market.cart.is_empty())
	assert(_find_stack(purchase_inventory, "banana").size() == 3)

	market.clear_cart()
	assert(market.add_to_cart("banana", 2))
	var direct_purchase_cart := market.cart.duplicate(true)
	var direct_purchase_coins := wallet.coins
	assert(market.purchase_single_placeable("basic_pot", wallet, catalog))
	assert(wallet.coins == direct_purchase_coins - catalog.get_definition("basic_pot").buy_price)
	assert(market.cart == direct_purchase_cart)
	var coins_after_direct_purchase := wallet.coins
	assert(not market.purchase_single_placeable("banana", wallet, catalog))
	assert(wallet.coins == coins_after_direct_purchase)
	assert(market.cart == direct_purchase_cart)
	poor_wallet.coins = 0
	assert(not market.purchase_single_placeable("turntable", poor_wallet, catalog))
	assert(poor_wallet.coins == 0)

	var preview_inventory_count := _count_items(purchase_inventory)
	var preview_cart := market.cart.duplicate(true)
	var placement := PlacementController.new()
	root.add_child(placement)
	await process_frame
	placement.setup(catalog, purchase_inventory)
	assert(is_equal_approx(placement.clamp_item_scale(-10.0, "basic_pot"), 0.7))
	assert(is_equal_approx(placement.clamp_item_scale(10.0, "basic_pot"), 1.3))
	assert(placement.begin_market_preview("basic_pot"))
	assert(placement.is_market_preview_active())
	assert(not placement.is_market_preview_ready())
	assert(placement.get_placed_items().is_empty())
	assert(_count_items(purchase_inventory) == preview_inventory_count)
	assert(market.cart == preview_cart)
	assert(placement.confirm_market_preview_position())
	assert(placement.is_market_preview_ready())
	var placed_from_market := placement.commit_market_preview()
	assert(placed_from_market != null)
	assert(not placement.is_market_preview_active())
	assert(placement.get_placed_items().size() == 1)
	assert(_count_items(purchase_inventory) == preview_inventory_count)
	assert(market.cart == preview_cart)
	for _i in 40:
		placed_from_market.scale_around_world(placed_from_market.global_position, 1.1)
	assert(placed_from_market.scale.is_equal_approx(Vector3.ONE * 1.3))
	for _i in 80:
		placed_from_market.scale_around_world(placed_from_market.global_position, 0.9)
	assert(placed_from_market.scale.is_equal_approx(Vector3.ONE * 0.7))
	var placed_save := placed_from_market.to_save_dict()
	var restored_placement := PlacementController.new()
	root.add_child(restored_placement)
	await process_frame
	restored_placement.setup(catalog, purchase_inventory)
	restored_placement.load_world([placed_save])
	assert(restored_placement.get_placed_items().size() == 1)
	var restored_market_item: PlacementItem = restored_placement.get_placed_items()[0]
	assert(restored_market_item.global_transform.is_equal_approx(placed_from_market.global_transform))
	assert(restored_market_item.scale.is_equal_approx(placed_from_market.scale))

	assert(placement.begin_market_preview("turntable"))
	placement.cancel_market_preview()
	assert(not placement.is_market_preview_active())
	assert(placement.get_placed_items().size() == 1)

	market.clear_cart()
	assert(market.is_sellable(catalog.get_definition("banana")))
	assert(market.is_sellable(catalog.get_definition("lemonade")))
	assert(market.is_sellable(catalog.get_definition("river_fish")))
	assert(not market.is_sellable(catalog.get_definition("banana_seed")))
	assert(not market.is_sellable(catalog.get_definition("basic_pot")))
	assert(MarketUI.market_category_path(catalog.get_definition("basic_pot")) == {"top": "furniture", "sub": "decor"})
	assert(MarketUI.market_category_path(catalog.get_definition("portal")) == {"top": "furniture", "sub": "fantasy"})
	assert(MarketUI.market_category_path(catalog.get_definition("banana_seed")) == {"top": "other", "sub": "seed"})
	assert(MarketUI.market_category_path(catalog.get_definition("pink_chat_bubble")) == {"top": "other", "sub": "chat_bubble"})
	assert(MarketUI.market_category_display_path(catalog.get_definition("pink_chat_bubble")) == "Other / Chat Bubble")
	assert(InventoryUI.inventory_slot_matches_filters([], null, "all", "all", ""))
	assert(not InventoryUI.inventory_slot_matches_filters([], null, "furniture", "all", ""))
	assert(InventoryUI.inventory_slot_matches_filters(_find_stack(inventory, "basic_pot"), catalog.get_definition("basic_pot"), "furniture", "decor", ""))
	assert(InventoryUI.inventory_slot_matches_filters(_find_stack(inventory, "candle_ver2"), catalog.get_definition("candle_ver2"), "furniture", "decor", ""))
	assert(InventoryUI.inventory_slot_matches_filters(_find_stack(inventory, "frame"), catalog.get_definition("frame"), "furniture", "decor", ""))
	assert(InventoryUI.inventory_slot_matches_filters([catalog.create_instance("banana_seed")], catalog.get_definition("banana_seed"), "other", "seed", ""))
	assert(InventoryUI.inventory_slot_matches_filters([catalog.create_instance("pink_chat_bubble")], catalog.get_definition("pink_chat_bubble"), "other", "chat_bubble", ""))
	assert(InventoryUI.inventory_slot_matches_filters(_find_stack(inventory, "basic_pot"), catalog.get_definition("basic_pot"), "furniture", "decor", "pot"))
	assert(not InventoryUI.inventory_slot_matches_filters(_find_stack(inventory, "basic_pot"), catalog.get_definition("basic_pot"), "furniture", "decor", "portal"))

	var banana_slot := _find_slot(purchase_inventory, "banana")
	var before_sale := wallet.coins
	assert(market.sell_slot_quantity(banana_slot, 2, wallet, purchase_inventory, catalog))
	assert(wallet.coins == before_sale + 10)
	assert(_find_stack(purchase_inventory, "banana").size() == 1)

	var gardening_catalog := GardeningCatalog.new()
	root.add_child(gardening_catalog)
	await process_frame
	assert(gardening_catalog.is_seed("banana_seed"))
	assert(gardening_catalog.get_by_seed("banana_seed").crop_item_id == "banana")

	var gardening := GardeningController.new()
	root.add_child(gardening)
	gardening.setup(placement, purchase_inventory, catalog, gardening_catalog)
	assert(purchase_inventory.add_instance(catalog.create_instance("banana_seed"), catalog))
	var seed_slot := _find_slot(purchase_inventory, "banana_seed")
	assert(gardening.begin_seed_selection(seed_slot))
	assert(gardening.handle_placed_item_clicked(placed_from_market))
	assert(_find_stack(purchase_inventory, "banana_seed").is_empty())
	assert(gardening.is_planted(placed_from_market))
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_SEED)
	assert(purchase_inventory.add_instance(catalog.create_instance("banana_seed"), catalog))
	assert(gardening.begin_seed_selection(_find_slot(purchase_inventory, "banana_seed")))
	assert(not gardening.handle_placed_item_clicked(placed_from_market))
	assert(not _find_stack(purchase_inventory, "banana_seed").is_empty())
	gardening.cancel_seed_selection()

	placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["next_at"] = int(Time.get_unix_time_from_system()) - 1
	assert(gardening.refresh_item(placed_from_market))
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_SAPLING)
	assert(gardening.handle_placed_item_clicked(placed_from_market))
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_GROWING)
	placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["next_at"] = int(Time.get_unix_time_from_system()) - 1
	assert(gardening.refresh_item(placed_from_market))
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_READY)
	var bananas_before_harvest := _count_definition(purchase_inventory, "banana")
	assert(gardening.handle_placed_item_clicked(placed_from_market))
	assert(_count_definition(purchase_inventory, "banana") == bananas_before_harvest + 1)
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_GROWING)
	placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] = GardeningController.STAGE_READY
	placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["wither_at"] = int(Time.get_unix_time_from_system()) - 1
	assert(gardening.refresh_item(placed_from_market))
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_WITHERED)
	var bananas_before_clear := _count_definition(purchase_inventory, "banana")
	assert(gardening.handle_placed_item_clicked(placed_from_market))
	assert(_count_definition(purchase_inventory, "banana") == bananas_before_clear)
	assert(placed_from_market.item_metadata[GardeningController.GARDENING_KEY]["stage"] == GardeningController.STAGE_GROWING)
	gardening.remove_plant(placed_from_market)
	assert(not placed_from_market.item_metadata.has(GardeningController.GARDENING_KEY))
	assert(gardening.begin_seed_selection(_find_slot(purchase_inventory, "banana_seed")))
	var non_pot := placement.create_placeable(catalog.create_instance("turntable"))
	root.add_child(non_pot)
	assert(not gardening.handle_placed_item_clicked(non_pot))
	assert(not _find_stack(purchase_inventory, "banana_seed").is_empty())
	non_pot.queue_free()
	gardening.cancel_seed_selection()

	var save_service := SaveService.new()
	save_service.save_path = "user://inventory_tests_savegame.json"
	assert(purchase_inventory.add_instance(catalog.create_instance("banana_seed"), catalog))
	assert(gardening.begin_seed_selection(_find_slot(purchase_inventory, "banana_seed")))
	assert(gardening.handle_placed_item_clicked(placed_from_market))
	assert(save_service.save_game(purchase_inventory, [placed_from_market], wallet))
	var saved := save_service.load_game()
	assert(not saved.is_empty())
	assert(saved.get("world", []).size() == 1)
	assert(saved["world"][0]["metadata"].has(GardeningController.GARDENING_KEY))
	var loaded_inventory := InventoryModel.new()
	root.add_child(loaded_inventory)
	await process_frame
	loaded_inventory.load_dict(saved.get("inventory", {}))
	var loaded_wallet := WalletModel.new()
	root.add_child(loaded_wallet)
	await process_frame
	loaded_wallet.load_dict(saved.get("wallet", {}))
	assert(_count_items(loaded_inventory) == _count_items(purchase_inventory))
	assert(loaded_wallet.coins == wallet.coins)

	print("InventoryTests: PASS")
	quit()


func _count_items(inventory: InventoryModel) -> int:
	var count := 0
	for stack in inventory.slots:
		count += stack.size()
	return count


func _count_model_items(catalog: ItemCatalog) -> int:
	var count := 0
	for definition in catalog.all_definitions():
		if definition.model_scene != null or not definition.model_path.is_empty():
			count += 1
	return count


func _count_definition(inventory: InventoryModel, definition_id: String) -> int:
	var count := 0
	for stack in inventory.slots:
		if not stack.is_empty() and stack[0].definition_id == definition_id:
			count += stack.size()
	return count


func _find_slot(inventory: InventoryModel, definition_id: String) -> int:
	for i in inventory.slots.size():
		var stack := inventory.get_slot_stack(i)
		if not stack.is_empty() and stack[0].definition_id == definition_id:
			return i
	return -1


func _find_empty_slot(inventory: InventoryModel) -> int:
	for i in inventory.slots.size():
		if inventory.get_slot_stack(i).is_empty():
			return i
	return -1


func _find_stack(inventory: InventoryModel, definition_id: String) -> Array:
	var index := _find_slot(inventory, definition_id)
	return inventory.get_slot_stack(index) if index >= 0 else []
