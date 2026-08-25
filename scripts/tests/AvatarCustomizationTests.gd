extends SceneTree

class FakeClock:
	extends UtcClock
	var value := 1000000

	func now_unix() -> int:
		return value


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	await process_frame
	_test_catalog(catalog)
	await _test_atomic_store_failures(catalog)
	await _test_gender_store_compatibility(catalog)

	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	var wallet := WalletModel.new()
	root.add_child(wallet)
	await process_frame
	var profile := AvatarProfile.new()
	root.add_child(profile)
	await process_frame
	profile.complete_onboarding(AvatarProfile.FEMALE, "skin_tone_4", "hair_color_pink")
	assert(profile.has_completed_onboarding)
	assert(profile.gender == AvatarProfile.FEMALE)
	assert(not profile.set_gender("robot"))
	assert(profile.gender == AvatarProfile.FEMALE)

	var fake_clock := FakeClock.new()
	var equipment := AvatarEquipmentModel.new()
	root.add_child(equipment)
	equipment.setup(inventory, catalog, profile, fake_clock)
	var expired_names: Array[String] = []
	equipment.item_expired.connect(func(item_name): expired_names.append(item_name))
	var initial := equipment.appearance_state()
	assert(initial["gender"] == AvatarProfile.FEMALE)
	assert(initial["fullbody"] == AvatarEquipmentModel.STARTER_FULLBODY)
	assert(initial["hair"] == AvatarEquipmentModel.STARTER_HAIR)
	assert(initial["skin_tone"] == "skin_tone_4")

	var store := AvatarStoreModel.new()
	root.add_child(store)
	assert(store.select_item("f_cloth_fullbody_310014", 7, catalog, profile.gender))
	assert(store.cart.has("fullbody"))
	assert(store.select_item("f_cloth_top_310045", 1, catalog, profile.gender))
	assert(not store.cart.has("fullbody"))
	assert(store.cart.has("top"))
	assert(store.select_item("f_cloth_hair_310181", 30, catalog, profile.gender))
	assert(store.totals() == {WalletModel.SOFT: 100, WalletModel.HARD: 50})
	var preview := store.preview_state(initial, catalog)
	assert(preview["top"] == "f_cloth_top_310045")
	assert(preview["bottom"] == AvatarEquipmentModel.starter_for_gender(profile.gender, "bottom"))
	assert(preview["hair"] == "f_cloth_hair_310181")
	assert(not profile.current_hair_color_id == "hair_color_black")

	var coins_before := wallet.coins
	var gems_before := wallet.gems
	assert(store.purchase(wallet, inventory, catalog, profile.user_id, profile.gender))
	assert(wallet.coins == coins_before - 100)
	assert(wallet.gems == gems_before - 50)
	assert(inventory.all_instances().size() == 2)
	for item in inventory.all_instances():
		assert(item.item_type == "RENTAL")
		assert(not item.is_activated)
		assert(item.activated_at == null)
		assert(item.expires_at == null)

	var top_item := _find_definition_instance(inventory, "f_cloth_top_310045")
	assert(equipment.equip_rental(top_item.instance_id))
	assert(top_item.is_activated)
	assert(top_item.activated_at == fake_clock.value)
	assert(top_item.expires_at == fake_clock.value + 86400)
	var serialized_item := top_item.to_dict()
	var restored_item := ItemInstance.from_dict(serialized_item)
	assert(restored_item.instance_id == top_item.instance_id)
	assert(restored_item.definition_id == top_item.definition_id)
	assert(restored_item.activated_at == top_item.activated_at)
	assert(restored_item.expires_at == top_item.expires_at)
	var legacy_item := ItemInstance.from_dict({"instance_id": "legacy-1", "definition_id": "banana"})
	assert(legacy_item.instance_id == "legacy-1" and legacy_item.definition_id == "banana")
	var original_expiry: int = top_item.expires_at
	fake_clock.value += 3600
	assert(equipment.equip_rental(top_item.instance_id))
	assert(top_item.expires_at == original_expiry)

	var male_bottom := catalog.create_instance("m_cloth_bottom_310010", {}, 7, profile.user_id)
	assert(inventory.add_instance(male_bottom, catalog))
	assert(not equipment.equip_rental(male_bottom.instance_id))
	profile.set_gender(AvatarProfile.MALE)
	var male_starter := equipment.appearance_state()
	assert(male_starter["gender"] == AvatarProfile.MALE)
	assert(male_starter["fullbody"] == AvatarEquipmentModel.starter_for_gender(AvatarProfile.MALE, "fullbody"))
	assert(male_starter["hair"] == AvatarEquipmentModel.starter_for_gender(AvatarProfile.MALE, "hair"))
	assert(equipment.equip_rental(male_bottom.instance_id))
	assert(top_item.is_equipped and male_bottom.is_equipped)
	assert(equipment.appearance_state()["bottom"] == male_bottom.definition_id)
	assert(equipment.appearance_state()["top"] == AvatarEquipmentModel.starter_for_gender(AvatarProfile.MALE, "top"))
	var male_bottom_expiry: int = male_bottom.expires_at
	var male_fullbody := catalog.create_instance("m_cloth_fullbody_310154", {}, 30, profile.user_id)
	assert(inventory.add_instance(male_fullbody, catalog))
	assert(equipment.equip_rental(male_fullbody.instance_id))
	assert(male_fullbody.is_equipped and not male_bottom.is_equipped)
	assert(top_item.is_equipped)
	assert(equipment.equip_rental(male_bottom.instance_id))
	assert(male_bottom.is_equipped and not male_fullbody.is_equipped)
	assert(male_bottom.expires_at == male_bottom_expiry)
	profile.set_gender(AvatarProfile.FEMALE)
	assert(equipment.appearance_state()["top"] == top_item.definition_id)

	var color_item := catalog.create_instance("hair_color_red", {}, 0, profile.user_id)
	assert(inventory.add_instance(color_item, catalog))
	var color_preview := initial.duplicate(true)
	color_preview["hair_color"] = color_item.definition_id
	assert(profile.current_hair_color_id == "hair_color_pink")
	assert(inventory.find_instance(color_item.instance_id) != null)
	assert(equipment.apply_consumable(color_item.instance_id))
	assert(profile.current_hair_color_id == "hair_color_red")
	assert(inventory.find_instance(color_item.instance_id) == null)

	fake_clock.value = original_expiry - 1
	assert(equipment.sweep_expired() == 0)
	fake_clock.value = original_expiry
	assert(equipment.sweep_expired() == 1)
	assert(inventory.find_instance(top_item.instance_id) == null)
	assert(expired_names == ["Female Top 310045"])
	assert(equipment.appearance_state()["fullbody"] == AvatarEquipmentModel.STARTER_FULLBODY)

	profile.set_gender(AvatarProfile.MALE)
	assert(equipment.appearance_state()["bottom"] == male_bottom.definition_id)
	assert(equipment.appearance_state()["hair_color"] == "hair_color_red")
	var serialized_profile := profile.to_dict()
	var restored_profile := AvatarProfile.new()
	root.add_child(restored_profile)
	await process_frame
	restored_profile.load_dict(serialized_profile)
	assert(restored_profile.user_id == profile.user_id)
	assert(restored_profile.current_hair_color_id == "hair_color_red")
	assert(restored_profile.gender == AvatarProfile.MALE)
	assert(restored_profile.has_completed_onboarding)

	var migrated_profile := AvatarProfile.new()
	root.add_child(migrated_profile)
	await process_frame
	migrated_profile.load_dict({
		"user_id": "version-4-user",
		"has_completed_onboarding": true,
		"current_skin_tone_id": "skin_tone_2",
		"current_hair_color_id": "hair_color_brown",
	})
	assert(migrated_profile.gender == AvatarProfile.FEMALE)
	assert(migrated_profile.has_completed_onboarding)

	profile.set_gender(AvatarProfile.FEMALE)
	fake_clock.value = int(male_bottom.expires_at)
	assert(equipment.sweep_expired() == 1)
	assert(inventory.find_instance(male_bottom.instance_id) == null)
	profile.set_gender(AvatarProfile.MALE)
	assert(equipment.appearance_state()["fullbody"] == AvatarEquipmentModel.starter_for_gender(AvatarProfile.MALE, "fullbody"))
	assert(expired_names == ["Female Top 310045", "Male Bottom 310010"])

	print("AvatarCustomizationTests: PASS")
	quit()


func _test_catalog(catalog: ItemCatalog) -> void:
	var slots := {"top": 0, "bottom": 0, "fullbody": 0, "hair": 0, "hair_color": 0, "skin_tone": 0}
	var female_slots := {"top": 0, "bottom": 0, "fullbody": 0, "hair": 0}
	var male_slots := {"top": 0, "bottom": 0, "fullbody": 0, "hair": 0}
	var furniture_count := 0
	var model_count := 0
	for definition in catalog.all_definitions():
		if slots.has(definition.avatar_slot):
			slots[definition.avatar_slot] += 1
		if definition.gender == AvatarProfile.FEMALE and female_slots.has(definition.avatar_slot):
			female_slots[definition.avatar_slot] += 1
		elif definition.gender == AvatarProfile.MALE and male_slots.has(definition.avatar_slot):
			male_slots[definition.avatar_slot] += 1
		if definition.definition_id.begins_with("furniture_"):
			furniture_count += 1
		if not definition.model_path.is_empty() or definition.model_scene != null:
			model_count += 1
		if definition.model_path.begins_with(ItemCatalog.DEV_ASSET_ROOT):
			assert(definition.model_scene == null)
			assert(not definition.model_path.to_lower().contains("_arşiv"))
			assert(not definition.model_path.to_lower().contains("/eski"))
	assert(slots == {"top": 69, "bottom": 77, "fullbody": 35, "hair": 13, "hair_color": 27, "skin_tone": 10})
	assert(female_slots == {"top": 60, "bottom": 23, "fullbody": 31, "hair": 8})
	assert(male_slots == {"top": 9, "bottom": 54, "fullbody": 4, "hair": 5})
	assert(furniture_count == 72)
	assert(model_count == 277)
	assert(catalog.get_definition("river_fish").item_name == "Anchovy")
	assert(catalog.get_definition("river_fish").model_path.ends_with("hamsi.glb"))
	var buyable_wearables := 0
	var buyable_male_wearables := 0
	for definition in catalog.all_definitions():
		if definition.item_type == "RENTAL" and definition.is_buyable:
			buyable_wearables += 1
			assert(definition.pricing_options == ItemCatalog.RENTAL_PRICING)
			if definition.gender == AvatarProfile.MALE:
				buyable_male_wearables += 1
	assert(buyable_wearables == 186)
	assert(buyable_male_wearables == 68)
	assert(catalog.get_definition(AvatarEquipmentModel.STARTER_FULLBODY).is_starter)
	assert(not catalog.get_definition(AvatarEquipmentModel.STARTER_FULLBODY).is_buyable)
	assert(catalog.get_definition(AvatarEquipmentModel.STARTER_TOP).is_starter)
	assert(not catalog.get_definition(AvatarEquipmentModel.STARTER_TOP).is_buyable)
	for slot in ["fullbody", "top", "bottom", "hair"]:
		var male_starter := catalog.get_definition(AvatarEquipmentModel.starter_for_gender(AvatarProfile.MALE, slot))
		assert(male_starter != null)
		assert(male_starter.gender == AvatarProfile.MALE)
		assert(male_starter.is_starter)
		assert(not male_starter.is_buyable)
	assert(catalog.get_definition("hair_color_red").buy_price == 100)
	assert(catalog.get_definition("hair_color_red").gender.is_empty())
	assert(catalog.get_definition("skin_tone_10").buy_price == 150)
	assert(catalog.get_definition("skin_tone_10").gender.is_empty())
	for definition in catalog.all_definitions():
		if definition.definition_id.begins_with("furniture_"):
			assert(not definition.is_starter)


func _find_definition_instance(inventory: InventoryModel, definition_id: String) -> ItemInstance:
	for item in inventory.all_instances():
		if item.definition_id == definition_id:
			return item
	return null


func _test_atomic_store_failures(catalog: ItemCatalog) -> void:
	var blocked_inventory := InventoryModel.new()
	root.add_child(blocked_inventory)
	await process_frame
	blocked_inventory.resize(1, 1)
	assert(blocked_inventory.add_instance(catalog.create_instance("winged_sheep"), catalog))
	var wallet := WalletModel.new()
	root.add_child(wallet)
	await process_frame
	var store := AvatarStoreModel.new()
	root.add_child(store)
	assert(store.select_item("f_cloth_top_310045", 1, catalog))
	assert(store.select_item("f_cloth_hair_310181", 30, catalog))
	var coins_before := wallet.coins
	var gems_before := wallet.gems
	assert(not store.purchase(wallet, blocked_inventory, catalog, "atomic-user"))
	assert(wallet.coins == coins_before and wallet.gems == gems_before)
	assert(blocked_inventory.all_instances().size() == 1)
	assert(store.cart.size() == 2)

	var poor_inventory := InventoryModel.new()
	root.add_child(poor_inventory)
	await process_frame
	var poor_wallet := WalletModel.new()
	root.add_child(poor_wallet)
	await process_frame
	poor_wallet.coins = 0
	poor_wallet.gems = 0
	var poor_store := AvatarStoreModel.new()
	root.add_child(poor_store)
	assert(poor_store.select_item("f_cloth_fullbody_310014", 365, catalog))
	assert(not poor_store.purchase(poor_wallet, poor_inventory, catalog, "atomic-user"))
	assert(poor_inventory.all_instances().is_empty())
	assert(poor_store.cart.has("fullbody"))


func _test_gender_store_compatibility(catalog: ItemCatalog) -> void:
	var store := AvatarStoreModel.new()
	root.add_child(store)
	assert(not store.select_item("m_cloth_top_310001", 1, catalog, AvatarProfile.FEMALE))
	assert(not store.select_item("f_cloth_top_310045", 1, catalog, AvatarProfile.MALE))
	assert(store.select_item("hair_color_cyan", 0, catalog, AvatarProfile.MALE))
	assert(store.select_item("m_cloth_top_310001", 1, catalog, AvatarProfile.MALE))
	assert(store.cart.has("hair_color") and store.cart.has("top"))

	var wallet := WalletModel.new()
	root.add_child(wallet)
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	var coins_before := wallet.coins
	assert(not store.purchase(wallet, inventory, catalog, "gender-user", AvatarProfile.FEMALE))
	assert(wallet.coins == coins_before)
	assert(inventory.all_instances().is_empty())
	assert(store.purchase(wallet, inventory, catalog, "gender-user", AvatarProfile.MALE))
	assert(inventory.all_instances().size() == 2)
