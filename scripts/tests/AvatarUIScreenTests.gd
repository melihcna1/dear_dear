extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var save_path := "user://avatar_ui_tests_savegame.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var main := preload("res://scripts/Main.gd").new()
	main.save_service.save_path = save_path
	root.add_child(main)
	await process_frame
	await process_frame
	assert(main.onboarding_ui.is_open())
	assert(main.onboarding_ui.gender_picker.item_count == 2)
	assert(main.onboarding_ui._gender_ids == [AvatarProfile.FEMALE, AvatarProfile.MALE])
	main.onboarding_ui.gender_picker.select(1)
	main.onboarding_ui.gender_picker.item_selected.emit(1)
	assert(main.player.avatar.current_gender == AvatarProfile.MALE)
	assert(main.profile.gender == AvatarProfile.FEMALE)
	main.onboarding_ui.gender_picker.select(0)
	main.onboarding_ui.gender_picker.item_selected.emit(0)
	main.onboarding_ui._confirm()
	assert(main.profile.has_completed_onboarding)
	assert(main.profile.gender == AvatarProfile.FEMALE)
	assert(not main.onboarding_ui.is_open())

	main._toggle_market()
	assert(main.market_ui.is_open())
	main._open_avatar_store()
	assert(main.avatar_store_ui.is_open())
	assert(not main.market_ui.is_open())
	assert(main.avatar_store_ui.title_label.text == "Female Avatar Store")
	assert(_tree_contains_text(main.avatar_store_ui.item_list, "Female Top 310045"))
	assert(not _tree_contains_text(main.avatar_store_ui.item_list, "Male Top 310001"))
	assert(main.avatar_store.select_item("f_cloth_top_310045", 1, main.catalog, main.profile.gender))
	await process_frame
	assert(main.player.avatar.current_state()["top"] == "f_cloth_top_310045")
	main._close_avatar_store_to_market()
	assert(not main.avatar_store_ui.is_open())
	assert(main.market_ui.is_open())
	assert(main.player.avatar.current_state() == main.avatar_equipment.appearance_state())
	main._toggle_market()
	assert(not main.market_ui.is_open())

	main._toggle_wardrobe()
	assert(main.wardrobe_ui.is_open())
	var redo_button := main.wardrobe_ui.panel.find_child("RedoAppearanceSetup", true, false) as Button
	assert(redo_button != null)
	redo_button.pressed.emit()
	assert(not main.wardrobe_ui.is_open())
	assert(main.onboarding_ui.is_open())
	assert(main.profile.has_completed_onboarding)
	assert(main.onboarding_ui.cancel_button.visible)
	assert(main.onboarding_ui._hair_ids[main.onboarding_ui.hair_picker.selected] == main.profile.current_hair_color_id)
	assert(main.onboarding_ui._skin_ids[main.onboarding_ui.skin_picker.selected] == main.profile.current_skin_tone_id)
	main.onboarding_ui.gender_picker.select(1)
	main.onboarding_ui.gender_picker.item_selected.emit(1)
	main.onboarding_ui.hair_picker.select(1)
	main.onboarding_ui.hair_picker.item_selected.emit(1)
	main.onboarding_ui.skin_picker.select(1)
	main.onboarding_ui.skin_picker.item_selected.emit(1)
	assert(main.player.avatar.current_gender == AvatarProfile.MALE)
	assert(main.profile.gender == AvatarProfile.FEMALE)
	assert(main.profile.current_hair_color_id == AvatarProfile.DEFAULT_HAIR_COLOR_ID)
	assert(main.profile.current_skin_tone_id == AvatarProfile.DEFAULT_SKIN_TONE_ID)
	main.onboarding_ui._cancel()
	assert(main.profile.has_completed_onboarding)
	assert(main.profile.gender == AvatarProfile.FEMALE)
	assert(main.player.avatar.current_gender == AvatarProfile.FEMALE)
	assert(main.player.avatar.current_state() == main.avatar_equipment.appearance_state())

	main._toggle_wardrobe()
	redo_button = main.wardrobe_ui.panel.find_child("RedoAppearanceSetup", true, false) as Button
	redo_button.pressed.emit()
	main.onboarding_ui.gender_picker.select(1)
	main.onboarding_ui.gender_picker.item_selected.emit(1)
	main.onboarding_ui._confirm()
	assert(main.profile.has_completed_onboarding)
	assert(main.profile.gender == AvatarProfile.MALE)
	assert(not main.onboarding_ui.is_open())

	main._toggle_market()
	main._open_avatar_store()
	assert(main.avatar_store_ui.title_label.text == "Male Avatar Store")
	assert(_tree_contains_text(main.avatar_store_ui.item_list, "Male Top 310001"))
	assert(not _tree_contains_text(main.avatar_store_ui.item_list, "Female Top 310045"))
	main._close_avatar_store_to_market()
	main._toggle_market()

	var rental := main.catalog.create_instance("m_cloth_fullbody_310154", {}, 7, main.profile.user_id)
	assert(main.inventory.add_instance(rental, main.catalog))
	var female_rental := main.catalog.create_instance("f_cloth_fullbody_310014", {}, 7, main.profile.user_id)
	assert(main.inventory.add_instance(female_rental, main.catalog))
	main._toggle_wardrobe()
	assert(main.wardrobe_ui.is_open())
	assert(_tree_contains_text(main.wardrobe_ui.item_list, "Male Full Body 310154"))
	assert(not _tree_contains_text(main.wardrobe_ui.item_list, "Female Full Body 310014"))
	main.wardrobe_ui._preview_instance(female_rental.instance_id)
	assert(main.wardrobe_ui._selected_instance_id.is_empty())
	assert(main.player.avatar.current_state() == main.avatar_equipment.appearance_state())
	main.wardrobe_ui._preview_instance(rental.instance_id)
	assert(not rental.is_activated)
	main.wardrobe_ui._apply_selected()
	assert(rental.is_activated)
	assert(rental.is_equipped)
	main._close_wardrobe()
	assert(not main.wardrobe_ui.is_open())
	assert(main.player.avatar.current_state()["fullbody"] == rental.definition_id)

	main.profile.set_gender(AvatarProfile.FEMALE)
	assert(main.avatar_equipment.equip_rental(female_rental.instance_id))
	assert(female_rental.is_equipped and rental.is_equipped)
	main.profile.set_gender(AvatarProfile.MALE)
	assert(main.avatar_equipment.appearance_state()["fullbody"] == rental.definition_id)
	main._save()
	main.profile.gender = AvatarProfile.FEMALE
	rental.is_equipped = false
	female_rental.is_equipped = false
	main._load()
	assert(main.profile.gender == AvatarProfile.MALE)
	assert(main.avatar_equipment.appearance_state()["fullbody"] == rental.definition_id)
	assert(_find_instance(main, rental.definition_id).is_equipped)
	assert(_find_instance(main, female_rental.definition_id).is_equipped)

	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("AvatarUIScreenTests: PASS")
	quit()


func _tree_contains_text(root_node: Node, needle: String) -> bool:
	var normalized_needle := needle.to_lower()
	if root_node is Label and (root_node as Label).text.to_lower().contains(normalized_needle):
		return true
	if root_node is Button and (root_node as Button).text.to_lower().contains(normalized_needle):
		return true
	for child in root_node.get_children():
		if _tree_contains_text(child, needle):
			return true
	return false


func _find_instance(main: Node, definition_id: String) -> ItemInstance:
	for item in main.inventory.all_instances():
		if item.definition_id == definition_id:
			return item
	return null
