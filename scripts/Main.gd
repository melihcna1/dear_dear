extends Node3D

const PlayerControllerScript := preload("res://scripts/PlayerController.gd")

var catalog: ItemCatalog
var inventory: InventoryModel
var wallet: WalletModel
var market: MarketModel
var profile: AvatarProfile
var avatar_equipment: AvatarEquipmentModel
var avatar_store: AvatarStoreModel
var gardening_catalog: GardeningCatalog
var gardening: GardeningController
var cooking_catalog: CookingCatalog
var cooking: CookingController
var cooking_ui: CookingUI
var fishing_catalog: FishingCatalog
var fishing: FishingController
var fishing_ui: FishingUI
var fishing_zone: FishingZone
var inventory_ui: InventoryUI
var market_ui: MarketUI
var avatar_store_ui: AvatarStoreUI
var wardrobe_ui: WardrobeUI
var onboarding_ui: OnboardingUI
var avatar_toast_ui: AvatarToastUI
var placement: PlacementController
var player: PlayerController
var save_service := SaveService.new()
var _autosave_queued := false
var _expiration_elapsed := 0.0


func _ready() -> void:
	catalog = ItemCatalog.new()
	catalog.name = "ItemCatalog"
	add_child(catalog)

	inventory = InventoryModel.new()
	inventory.name = "Inventory"
	add_child(inventory)

	wallet = WalletModel.new()
	wallet.name = "Wallet"
	add_child(wallet)

	market = MarketModel.new()
	market.name = "Market"
	add_child(market)

	profile = AvatarProfile.new()
	profile.name = "AvatarProfile"
	add_child(profile)

	avatar_equipment = AvatarEquipmentModel.new()
	avatar_equipment.name = "AvatarEquipment"
	add_child(avatar_equipment)
	avatar_equipment.setup(inventory, catalog, profile)

	avatar_store = AvatarStoreModel.new()
	avatar_store.name = "AvatarStore"
	add_child(avatar_store)

	gardening_catalog = GardeningCatalog.new()
	gardening_catalog.name = "GardeningCatalog"
	add_child(gardening_catalog)

	cooking_catalog = CookingCatalog.new()
	cooking_catalog.name = "CookingCatalog"
	add_child(cooking_catalog)
	cooking_catalog.setup(catalog)

	fishing_catalog = FishingCatalog.new()
	fishing_catalog.name = "FishingCatalog"
	add_child(fishing_catalog)
	fishing_catalog.setup(catalog)

	placement = PlacementController.new()
	placement.name = "PlacementController"
	add_child(placement)
	placement.setup(catalog, inventory)
	placement.world_changed.connect(_queue_autosave)
	placement.market_preview_cancel_requested.connect(_on_market_preview_cancelled)

	fishing_zone = FishingZone.new()
	fishing_zone.name = "PrototypeFishingPond"
	fishing_zone.position = Vector3(3.5, 0.02, -2.0)
	placement.add_child(fishing_zone)

	gardening = GardeningController.new()
	gardening.name = "GardeningController"
	add_child(gardening)
	gardening.setup(placement, inventory, catalog, gardening_catalog)
	gardening.changed.connect(_queue_autosave)
	gardening.status_changed.connect(_on_gardening_status_changed)

	player = PlayerControllerScript.new() as PlayerController
	player.name = "Player"
	add_child(player)
	player.setup(placement, [fishing_zone.get_navigation_rect()])
	player.setup_avatar(catalog, avatar_equipment)
	placement.world_changed.connect(player.refresh_navigation)
	placement.quick_right_click.connect(_on_world_right_clicked)

	fishing_ui = FishingUI.new()
	fishing_ui.name = "FishingUI"
	add_child(fishing_ui)

	fishing = FishingController.new()
	fishing.name = "FishingController"
	add_child(fishing)
	fishing.setup(player, inventory, catalog, fishing_catalog, placement, fishing_ui)
	fishing.register_zone(fishing_zone)
	fishing.state_changed.connect(_on_fishing_state_changed)

	inventory_ui = InventoryUI.new()
	inventory_ui.name = "InventoryUI"
	add_child(inventory_ui)
	inventory_ui.setup(inventory, catalog, wallet)
	inventory_ui.item_placement_requested.connect(_on_item_placement_requested)
	inventory_ui.seed_use_requested.connect(_on_seed_use_requested)
	inventory.changed.connect(_queue_autosave)
	wallet.changed.connect(_queue_autosave)

	market_ui = MarketUI.new()
	market_ui.name = "MarketUI"
	add_child(market_ui)
	market_ui.setup(market, wallet, inventory, catalog)
	market_ui.purchase_completed.connect(_queue_autosave)
	market_ui.sale_completed.connect(_queue_autosave)
	market_ui.preview_requested.connect(_on_market_preview_requested)
	market_ui.preview_purchase_requested.connect(_on_market_preview_purchase_requested)
	market_ui.preview_cancel_requested.connect(_on_market_preview_cancelled)
	market_ui.avatar_store_requested.connect(_open_avatar_store)

	avatar_store_ui = AvatarStoreUI.new()
	avatar_store_ui.name = "AvatarStoreUI"
	add_child(avatar_store_ui)
	avatar_store_ui.setup(avatar_store, wallet, inventory, catalog, profile, avatar_equipment, player.avatar)
	avatar_store_ui.close_requested.connect(_close_avatar_store_to_market)
	avatar_store_ui.purchase_completed.connect(_queue_autosave)

	wardrobe_ui = WardrobeUI.new()
	wardrobe_ui.name = "WardrobeUI"
	add_child(wardrobe_ui)
	wardrobe_ui.setup(inventory, catalog, avatar_equipment, player.avatar)
	wardrobe_ui.close_requested.connect(_close_wardrobe)
	wardrobe_ui.appearance_committed.connect(_queue_autosave)
	wardrobe_ui.onboarding_requested.connect(_reopen_onboarding)

	onboarding_ui = OnboardingUI.new()
	onboarding_ui.name = "OnboardingUI"
	add_child(onboarding_ui)
	onboarding_ui.setup(profile, avatar_equipment, catalog, player.avatar)
	onboarding_ui.completed.connect(_on_onboarding_completed)
	onboarding_ui.cancelled.connect(_on_onboarding_cancelled)

	avatar_toast_ui = AvatarToastUI.new()
	avatar_toast_ui.name = "AvatarToastUI"
	add_child(avatar_toast_ui)
	avatar_equipment.item_expired.connect(_on_avatar_item_expired)
	profile.changed.connect(_on_avatar_profile_changed)

	cooking_ui = CookingUI.new()
	cooking_ui.name = "CookingUI"
	add_child(cooking_ui)

	cooking = CookingController.new()
	cooking.name = "CookingController"
	add_child(cooking)
	cooking.setup(placement, inventory, catalog, cooking_catalog, cooking_ui)
	cooking_ui.setup(cooking, inventory, catalog, cooking_catalog)
	cooking.changed.connect(_queue_autosave)
	cooking_ui.closed.connect(_on_cooking_closed)
	placement.status_changed.connect(cooking_ui.show_toast)
	placement.placed_item_clicked.connect(_on_placed_item_clicked)

	var saved := save_service.load_game()
	if saved.is_empty():
		inventory.seed_defaults(catalog)
	else:
		inventory.load_dict(saved.get("inventory", {}))
		wallet.load_dict(saved.get("wallet", {}))
		profile.load_dict(saved.get("profile", {}))
		placement.load_world(saved.get("world", []))
	gardening.refresh_all()
	cooking.refresh_all()
	inventory.restore_missing_unique_items(catalog)
	avatar_equipment.sweep_expired()
	player.avatar.apply_state(avatar_equipment.appearance_state())
	if not profile.has_completed_onboarding:
		call_deferred("_open_onboarding")


func _process(_delta: float) -> void:
	if placement and placement.is_market_preview_active():
		market_ui.set_preview_ready(placement.is_market_preview_ready())
	_expiration_elapsed += _delta
	if _expiration_elapsed >= 60.0:
		_expiration_elapsed = 0.0
		if avatar_equipment.sweep_expired() > 0:
			_queue_autosave()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if onboarding_ui and onboarding_ui.is_open():
			get_viewport().set_input_as_handled()
			return
		if avatar_store_ui and avatar_store_ui.is_open():
			if event.keycode == KEY_ESCAPE:
				_close_avatar_store_to_market()
			elif event.keycode == KEY_M:
				avatar_store_ui.close()
				placement.exit_market_camera()
				_update_interaction_enabled()
			get_viewport().set_input_as_handled()
			return
		if wardrobe_ui and wardrobe_ui.is_open():
			if event.keycode in [KEY_ESCAPE, KEY_W]:
				_close_wardrobe()
			get_viewport().set_input_as_handled()
			return
		if cooking_ui and cooking_ui.is_open():
			if event.keycode == KEY_ESCAPE:
				cooking_ui.close()
			get_viewport().set_input_as_handled()
			return
		if fishing and fishing.is_busy():
			if event.keycode == KEY_ESCAPE:
				fishing.cancel()
				get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_I, KEY_M, KEY_F5, KEY_F8, KEY_F9]:
				get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_I:
				inventory_ui.toggle()
				_update_interaction_enabled()
				get_viewport().set_input_as_handled()
			KEY_M:
				_toggle_market()
				get_viewport().set_input_as_handled()
			KEY_W:
				_toggle_wardrobe()
				get_viewport().set_input_as_handled()
			KEY_F5:
				_save()
				get_viewport().set_input_as_handled()
			KEY_F9:
				_load()
				get_viewport().set_input_as_handled()
			KEY_F8:
				_restore_unique_items()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				gardening.cancel_seed_selection()


func _on_item_placement_requested(slot_index: int) -> void:
	gardening.cancel_seed_selection()
	inventory_ui.panel.visible = false
	_update_interaction_enabled()
	placement.begin_inventory_placement(slot_index)


func _on_seed_use_requested(slot_index: int) -> void:
	placement.cancel_inventory_placement()
	if not gardening.begin_seed_selection(slot_index):
		return
	inventory_ui.panel.visible = false
	_update_interaction_enabled()


func _on_world_right_clicked(screen_position: Vector2) -> void:
	if not player:
		return
	var world_position := placement.screen_to_ground(screen_position)
	if fishing and fishing.try_start_at(world_position):
		gardening.cancel_seed_selection()
		placement.cancel_inventory_placement()
		_update_interaction_enabled()
		return
	if fishing and fishing.is_busy():
		fishing.cancel(false)
	player.move_to_world_position(world_position)


func _on_placed_item_clicked(item: PlacementItem) -> void:
	if cooking and cooking.is_station(item):
		gardening.cancel_seed_selection()
		placement.cancel_inventory_placement()
		inventory_ui.panel.visible = false
		if market_ui.is_open():
			market_ui.close()
			placement.exit_market_camera()
		if cooking.open_station(item):
			_update_interaction_enabled()
		return
	gardening.handle_placed_item_clicked(item)


func _queue_autosave() -> void:
	if _autosave_queued:
		return
	_autosave_queued = true
	get_tree().create_timer(0.35).timeout.connect(_save)


func _save() -> void:
	_autosave_queued = false
	save_service.save_game(inventory, placement.get_placed_items(), wallet, profile)


func _load() -> void:
	var saved := save_service.load_game()
	if saved.is_empty():
		return
	placement.cancel_inventory_placement()
	inventory.load_dict(saved.get("inventory", {}))
	wallet.load_dict(saved.get("wallet", {}))
	profile.load_dict(saved.get("profile", {}))
	placement.load_world(saved.get("world", []))
	gardening.refresh_all()
	cooking.refresh_all()
	inventory.restore_missing_unique_items(catalog)
	avatar_equipment.sweep_expired()
	player.avatar.apply_state(avatar_equipment.appearance_state())


func _restore_unique_items() -> void:
	inventory.restore_missing_unique_items(catalog)
	_save()


func _toggle_market() -> void:
	if wardrobe_ui.is_open():
		_close_wardrobe()
	if placement.is_market_preview_active():
		placement.cancel_market_preview()
		market_ui.hide_preview_controls()
		_update_interaction_enabled()
		return
	if market_ui.is_open():
		market_ui.close()
		placement.exit_market_camera()
	else:
		inventory_ui.panel.visible = false
		market_ui.open()
		placement.enter_market_camera(player)
	_update_interaction_enabled()


func _open_avatar_store() -> void:
	market_ui.close()
	avatar_store_ui.open()
	_update_interaction_enabled()


func _close_avatar_store_to_market() -> void:
	avatar_store_ui.close()
	market_ui.open()
	_update_interaction_enabled()


func _toggle_wardrobe() -> void:
	if market_ui.is_open():
		market_ui.close()
	if placement.is_market_preview_active():
		placement.cancel_market_preview()
		market_ui.hide_preview_controls()
	if wardrobe_ui.is_open():
		_close_wardrobe()
	else:
		inventory_ui.panel.visible = false
		avatar_store_ui.close()
		wardrobe_ui.open()
		placement.enter_market_camera(player)
		_update_interaction_enabled()


func _close_wardrobe() -> void:
	wardrobe_ui.close()
	placement.exit_market_camera()
	_update_interaction_enabled()


func _open_onboarding(redo_mode := false) -> void:
	placement.enter_market_camera(player)
	onboarding_ui.open(redo_mode)
	_update_interaction_enabled()


func _reopen_onboarding() -> void:
	wardrobe_ui.close()
	_open_onboarding(true)


func _on_onboarding_completed() -> void:
	placement.exit_market_camera()
	_queue_autosave()
	_update_interaction_enabled()


func _on_onboarding_cancelled() -> void:
	placement.exit_market_camera()
	_update_interaction_enabled()


func _on_avatar_profile_changed() -> void:
	if player and player.avatar:
		player.avatar.apply_state(avatar_equipment.appearance_state())
	_queue_autosave()


func _on_avatar_item_expired(item_name: String) -> void:
	avatar_toast_ui.show_message("Your %s has expired." % item_name)


func _on_market_preview_requested(definition_id: String) -> void:
	gardening.cancel_seed_selection()
	placement.exit_market_camera()
	if not placement.begin_market_preview(definition_id):
		return
	market_ui.show_preview_controls(definition_id)
	_update_interaction_enabled()


func _on_market_preview_purchase_requested() -> void:
	if not placement.is_market_preview_ready():
		return
	var definition_id := placement.get_market_preview_definition_id()
	if not market.purchase_single_placeable(definition_id, wallet, catalog):
		return
	if not placement.commit_market_preview():
		return
	market_ui.purchase_completed.emit()
	market_ui.show_market_after_preview()
	placement.enter_market_camera(player)
	_update_interaction_enabled()


func _on_market_preview_cancelled() -> void:
	placement.cancel_market_preview()
	market_ui.show_market_after_preview()
	placement.enter_market_camera(player)
	_update_interaction_enabled()


func _update_interaction_enabled() -> void:
	var fishing_locked := fishing != null and fishing.locks_world_input()
	var cooking_locked := cooking_ui != null and cooking_ui.is_open()
	var avatar_store_locked := avatar_store_ui != null and avatar_store_ui.is_open()
	var wardrobe_locked := wardrobe_ui != null and wardrobe_ui.is_open()
	var onboarding_locked := onboarding_ui != null and onboarding_ui.is_open()
	placement.set_interaction_enabled(
		not inventory_ui.is_open()
		and not market_ui.is_open()
		and not fishing_locked
		and not cooking_locked
		and not avatar_store_locked
		and not wardrobe_locked
		and not onboarding_locked
	)


func _on_fishing_state_changed(_state: int) -> void:
	_update_interaction_enabled()


func _on_cooking_closed() -> void:
	_update_interaction_enabled()


func _on_gardening_status_changed(message: String) -> void:
	if market:
		market.status_changed.emit(message)
