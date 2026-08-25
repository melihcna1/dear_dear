extends SceneTree

const FISH_IDS := ["river_fish", "bubblebelly", "mossback", "moonwhisker", "glimmergill", "star_koi"]
const SELL_PRICES := [12, 18, 26, 38, 55, 90]

var _reached_positions: Array[Vector3] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	await process_frame

	var fishing_catalog := FishingCatalog.new()
	root.add_child(fishing_catalog)
	fishing_catalog.setup(catalog)
	assert(fishing_catalog.all_definitions().size() == 6)
	assert(is_equal_approx(fishing_catalog.total_weight, 100.0))
	for i in FISH_IDS.size():
		var item_definition := catalog.get_definition(FISH_IDS[i])
		assert(item_definition != null)
		assert(item_definition.category == "Fish")
		assert(item_definition.sub_category == "Freshwater")
		assert(not item_definition.is_buyable)
		assert(item_definition.is_sellable)
		assert(not item_definition.is_placeable)
		assert(item_definition.max_stack_size == 0)
		assert(item_definition.sell_price == SELL_PRICES[i])
		assert(fishing_catalog.get_definition(FISH_IDS[i]) != null)

	var selection_rng := RandomNumberGenerator.new()
	selection_rng.seed = 98421
	var selection_counts := {}
	for _i in 2000:
		var selected := fishing_catalog.choose_fish(selection_rng)
		selection_counts[selected.item_id] = int(selection_counts.get(selected.item_id, 0)) + 1
	for fish_id in FISH_IDS:
		assert(int(selection_counts.get(fish_id, 0)) > 0)
	assert(int(selection_counts["river_fish"]) > int(selection_counts["star_koi"]))

	_test_minigame(fishing_catalog)

	var pond_rect := Rect2(Vector2(2.0, -3.5), Vector2(3.0, 3.0))
	var nav := PlayerNavigationGrid.new()
	nav.configure(0.5, Vector2(-6.0, -6.0), Vector2(6.0, 6.0), 0.25)
	nav.rebuild([], [pond_rect])
	assert(not nav.is_walkable(nav.world_to_cell(Vector3(3.5, 0.0, -2.0))))
	var nearest_shore := nav.nearest_walkable_to_world(Vector3(3.5, 0.0, -2.0), nav.world_to_cell(Vector3.ZERO))
	assert(nearest_shore != PlayerController.SENTINEL_CELL)
	assert(not pond_rect.has_point(Vector2(nav.cell_to_world(nearest_shore).x, nav.cell_to_world(nearest_shore).z)))

	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	var placement := PlacementController.new()
	root.add_child(placement)
	await process_frame
	placement.setup(catalog, inventory)
	placement.set_excluded_ground_regions([pond_rect])
	assert(placement.is_ground_position_excluded(Vector3(3.5, 0.0, -2.0)))
	assert(not placement.is_ground_position_excluded(Vector3.ZERO))
	assert(placement.begin_market_preview("basic_pot"))
	placement._mouse_world_position = Vector3(3.5, 0.0, -2.0)
	placement._apply_preview_transform()
	assert(not placement._preview.valid_placement)
	assert(not placement.confirm_market_preview_position())
	placement.cancel_market_preview()
	var dragged_item := placement.create_placeable(catalog.create_instance("basic_pot"))
	placement._placed_root.add_child(dragged_item)
	dragged_item.global_position = Vector3.ZERO
	placement._selected = dragged_item
	placement._drag_start_transform = dragged_item.global_transform
	placement._dragging_selected = true
	dragged_item.global_position = Vector3(3.5, 0.0, -2.0)
	dragged_item.valid_placement = false
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_LEFT
	drag_release.pressed = false
	placement._unhandled_input(drag_release)
	assert(dragged_item.global_position.is_equal_approx(Vector3.ZERO))
	dragged_item.queue_free()
	await process_frame

	var zone := FishingZone.new()
	zone.position = Vector3(3.5, 0.02, -2.0)
	placement.add_child(zone)
	await process_frame
	assert(zone.contains_world_point(Vector3(3.5, 0.0, -2.0)))
	assert(not zone.contains_world_point(Vector3.ZERO))
	var clamped_cast := zone.resolve_cast_target(Vector3(3.5, 0.0, -2.0), Vector3(1.5, 0.0, -2.0))
	assert(zone.contains_world_point(clamped_cast))
	assert(Vector2(clamped_cast.x, clamped_cast.z).distance_to(Vector2(1.5, -2.0)) <= zone.max_cast_distance)

	var player := PlayerController.new()
	root.add_child(player)
	await process_frame
	player.setup(placement, [pond_rect])
	player.destination_reached.connect(_on_player_reached)
	assert(player.move_to_world_position(Vector3(3.5, 0.0, -2.0)))
	for _i in 240:
		if not _reached_positions.is_empty():
			break
		await physics_frame
	assert(not _reached_positions.is_empty())
	var reached: Vector3 = _reached_positions.back()
	assert(not pond_rect.has_point(Vector2(reached.x, reached.z)))

	_test_inventory_replacement(catalog)
	await _test_controller_flow(catalog, fishing_catalog, placement, player, zone)
	player.global_position = Vector3(-5.0, player.global_position.y, 5.0)
	await _test_main_smoke()

	print("FishingTests: PASS")
	quit()


func _test_minigame(fishing_catalog: FishingCatalog) -> void:
	var definition := fishing_catalog.get_definition("river_fish")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var model := FishingMinigameModel.new()
	model.start(definition, rng)
	assert(is_equal_approx(model.progress, FishingMinigameModel.START_PROGRESS))
	assert(is_equal_approx(model.fish_speed(), 0.25))
	assert(is_equal_approx(model.retarget_interval(), 1.25))
	var initial_bar := model.bar_center
	model.step(0.1, true)
	assert(model.bar_center > initial_bar)

	model.start(definition, rng)
	initial_bar = model.bar_center
	model.step(0.1, false)
	assert(model.bar_center < initial_bar)

	model.start(definition, rng)
	model.progress = 0.99
	model.bar_center = 0.5
	model.fish_position = 0.5
	model.fish_target = 0.5
	assert(model.step(0.05, true) == FishingMinigameModel.Result.SUCCESS)

	model.start(definition, rng)
	model.progress = 0.01
	model.bar_center = FishingMinigameModel.BAR_HEIGHT * 0.5
	model.fish_position = 0.9
	model.fish_target = 0.9
	assert(model.step(0.05, false) == FishingMinigameModel.Result.FAILURE)

	for profile_id in FISH_IDS:
		var profile_definition := fishing_catalog.get_definition(profile_id)
		model.start(profile_definition, rng)
		model.step(0.01, false)
		assert(model.fish_target >= 0.06 and model.fish_target <= 0.94)


func _test_inventory_replacement(catalog: ItemCatalog) -> void:
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	inventory.resize(1, 1)
	assert(inventory.add_instance(catalog.create_instance("banana"), catalog))
	assert(not inventory.add_instance(catalog.create_instance("river_fish"), catalog))
	var replacement := catalog.create_instance("river_fish")
	var discarded := inventory.replace_slot_with_instance(0, replacement, catalog)
	assert(discarded.size() == 1)
	assert(discarded[0].definition_id == "banana")
	assert(inventory.get_slot_stack(0).size() == 1)
	assert(inventory.get_slot_stack(0)[0].definition_id == "river_fish")
	assert(inventory.replace_slot_with_instance(-1, catalog.create_instance("mossback"), catalog).is_empty())
	assert(inventory.get_slot_stack(0)[0].definition_id == "river_fish")


func _test_controller_flow(
		catalog: ItemCatalog,
		fishing_catalog: FishingCatalog,
		placement: PlacementController,
		player: PlayerController,
		zone: FishingZone) -> void:
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	var ui := FishingUI.new()
	root.add_child(ui)
	await process_frame
	var anchovy_definition := catalog.get_definition("river_fish")
	ui.show_result("Caught Anchovy!", anchovy_definition)
	await process_frame
	assert(ui.result_preview.visible)
	assert(ui.result_preview._model_root.get_child_count() == 1)
	ui.hide_all()
	var anchovy_slot := InventorySlot.new()
	root.add_child(anchovy_slot)
	await process_frame
	anchovy_slot.set_contents([catalog.create_instance("river_fish")], anchovy_definition)
	await process_frame
	assert(anchovy_slot._preview.visible)
	assert(anchovy_slot._preview._model_root.get_child_count() == 1)
	anchovy_slot.queue_free()
	var controller := FishingController.new()
	root.add_child(controller)
	controller.rng.seed = 12345
	controller.setup(player, inventory, catalog, fishing_catalog, placement, ui)
	controller.register_zone(zone)

	assert(not controller.try_start_at(Vector3.ZERO))
	assert(controller.try_start_at(Vector3(3.5, 0.0, -2.0)))
	assert(controller.state == FishingController.State.APPROACHING)
	controller._on_destination_reached(Vector3(1.5, 0.0, -2.0))
	assert(controller.state == FishingController.State.WAITING_FOR_BITE)
	var control_press := _control_event(true)
	controller._input(control_press)
	assert(controller.state == FishingController.State.RESULT)
	controller._reset_to_idle()

	controller.try_start_at(Vector3(3.5, 0.0, -2.0))
	controller._on_destination_reached(Vector3(1.5, 0.0, -2.0))
	controller._process(3.1)
	assert(controller.state == FishingController.State.HOOK_WINDOW)
	controller._process(1.0)
	assert(controller.state == FishingController.State.RESULT)
	controller._reset_to_idle()

	var count_before := _count_items(inventory)
	controller.try_start_at(Vector3(3.5, 0.0, -2.0))
	controller._on_destination_reached(Vector3(1.5, 0.0, -2.0))
	controller._process(3.1)
	assert(controller.state == FishingController.State.HOOK_WINDOW)
	controller._input(control_press)
	assert(controller.state == FishingController.State.MINIGAME)
	assert(ui.fish_preview.visible)
	assert(ui.fish_preview._model_root.get_child_count() == 1)
	controller.minigame.progress = 0.99
	controller.minigame.bar_center = 0.5
	controller.minigame.fish_position = 0.5
	controller.minigame.fish_target = 0.5
	controller._process(0.05)
	assert(controller.state == FishingController.State.RESULT)
	assert(_count_items(inventory) == count_before + 1)
	var caught_id: String = inventory.get_slot_stack(0)[0].definition_id
	assert(caught_id in FISH_IDS)

	var market := MarketModel.new()
	root.add_child(market)
	var wallet := WalletModel.new()
	root.add_child(wallet)
	await process_frame
	var coins_before := wallet.coins
	assert(market.sell_slot_quantity(0, 1, wallet, inventory, catalog))
	assert(wallet.coins == coins_before + catalog.get_definition(caught_id).sell_price)

	controller._reset_to_idle()
	var full_inventory := InventoryModel.new()
	root.add_child(full_inventory)
	full_inventory.resize(1, 1)
	assert(full_inventory.add_instance(catalog.create_instance("banana"), catalog))
	var full_ui := FishingUI.new()
	root.add_child(full_ui)
	await process_frame
	var full_controller := FishingController.new()
	root.add_child(full_controller)
	full_controller.rng.seed = 42
	full_controller.setup(player, full_inventory, catalog, fishing_catalog, placement, full_ui)
	full_controller.register_zone(zone)
	full_controller.try_start_at(Vector3(3.5, 0.0, -2.0))
	full_controller._on_destination_reached(Vector3(1.5, 0.0, -2.0))
	full_controller._process(3.1)
	full_controller._input(control_press)
	full_controller.minigame.progress = 0.99
	full_controller.minigame.bar_center = 0.5
	full_controller.minigame.fish_position = 0.5
	full_controller.minigame.fish_target = 0.5
	full_controller._process(0.05)
	assert(full_controller.state == FishingController.State.REWARD_PENDING)
	assert(full_inventory.get_slot_stack(0)[0].definition_id == "banana")
	full_controller._on_replace_slot_requested(0)
	assert(full_controller.state == FishingController.State.RESULT)
	assert(full_inventory.get_slot_stack(0)[0].definition_id in FISH_IDS)

	full_controller._reset_to_idle()
	full_inventory.clear()
	assert(full_inventory.add_instance(catalog.create_instance("banana"), catalog))
	full_controller.try_start_at(Vector3(3.5, 0.0, -2.0))
	full_controller._on_destination_reached(Vector3(1.5, 0.0, -2.0))
	full_controller._process(3.1)
	full_controller._input(control_press)
	full_controller.minigame.progress = 0.99
	full_controller.minigame.bar_center = 0.5
	full_controller.minigame.fish_position = 0.5
	full_controller.minigame.fish_target = 0.5
	full_controller._process(0.05)
	assert(full_controller.state == FishingController.State.REWARD_PENDING)
	full_controller._on_reward_cancelled()
	assert(full_controller.state == FishingController.State.RESULT)
	assert(full_inventory.get_slot_stack(0)[0].definition_id == "banana")

	full_controller._reset_to_idle()
	full_inventory.clear()
	assert(full_inventory.add_instance(catalog.create_instance("river_fish"), catalog))

	var save_service := SaveService.new()
	save_service.save_path = "user://fishing_tests_savegame.json"
	assert(save_service.save_game(full_inventory, [], wallet))
	var saved := save_service.load_game()
	var loaded := InventoryModel.new()
	root.add_child(loaded)
	await process_frame
	loaded.load_dict(saved.get("inventory", {}))
	assert(loaded.get_slot_stack(0)[0].definition_id == full_inventory.get_slot_stack(0)[0].definition_id)


func _test_main_smoke() -> void:
	var main := preload("res://scripts/Main.gd").new()
	main.save_service.save_path = "user://fishing_main_smoke_savegame.json"
	root.add_child(main)
	await process_frame
	assert(main.fishing != null)
	assert(main.fishing_zone != null)
	assert(main.fishing_catalog.all_definitions().size() == 6)
	var camera := main.placement.get_camera()
	var pond_screen_position := camera.unproject_position(main.fishing_zone.global_position)
	main._on_world_right_clicked(pond_screen_position)
	assert(main.fishing.state == FishingController.State.APPROACHING)
	for _i in 300:
		if main.fishing.state != FishingController.State.APPROACHING:
			break
		await physics_frame
	assert(main.fishing.state == FishingController.State.WAITING_FOR_BITE)
	main.fishing.cancel(false)
	assert(main.fishing.state == FishingController.State.IDLE)
	main.queue_free()
	await process_frame


func _control_event(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = pressed
	return event


func _on_player_reached(world_position: Vector3) -> void:
	_reached_positions.append(world_position)


func _count_items(inventory: InventoryModel) -> int:
	var count := 0
	for stack in inventory.slots:
		count += stack.size()
	return count
