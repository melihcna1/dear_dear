extends SceneTree


var _output_directory := "user://avatar_visual_smoke"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			_output_directory = argument.trim_prefix("--output-dir=")
	var absolute_output := ProjectSettings.globalize_path(_output_directory)
	assert(DirAccess.make_dir_recursive_absolute(absolute_output) == OK)

	var save_path := "user://avatar_visual_smoke_savegame.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var main := preload("res://scripts/Main.gd").new()
	main.save_service.save_path = save_path
	root.add_child(main)
	await process_frame
	await process_frame
	main.placement.enter_market_camera(main.player)
	await create_timer(0.6).timeout
	await _capture("01_onboarding")

	main.onboarding_ui.gender_picker.select(1)
	main.onboarding_ui.gender_picker.item_selected.emit(1)
	await create_timer(0.6).timeout
	await _capture("02_onboarding_male")
	main.onboarding_ui._confirm()
	main._toggle_market()
	await create_timer(0.6).timeout
	main._open_avatar_store()
	assert(main.avatar_store.select_item("m_cloth_top_310008", 30, main.catalog, main.profile.gender))
	assert(main.avatar_store.select_item("m_cloth_bottom_310153", 7, main.catalog, main.profile.gender))
	assert(main.avatar_store.select_item("m_cloth_hair_310192", 365, main.catalog, main.profile.gender))
	await process_frame
	await _capture("03_male_avatar_store")

	main._close_avatar_store_to_market()
	main._toggle_market()
	var rental := main.catalog.create_instance("m_cloth_fullbody_310154", {}, 7, main.profile.user_id)
	assert(main.inventory.add_instance(rental, main.catalog))
	main._toggle_wardrobe()
	main.wardrobe_ui._preview_instance(rental.instance_id)
	await process_frame
	await _capture("04_male_wardrobe")

	main.wardrobe_ui._apply_selected()
	main._close_wardrobe()
	var walk_destination := Vector3(2.0, 0.0, 1.0)
	main.player.move_to_world_position(walk_destination)
	await create_timer(0.4).timeout
	assert(main.player.avatar._moving)
	var flat_direction := walk_destination - main.player.global_position
	flat_direction.y = 0.0
	assert(main.player.global_transform.basis.z.normalized().dot(flat_direction.normalized()) > 0.8)
	await _capture("05_male_gameplay_walk")

	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("AvatarVisualSmoke: PASS")
	quit()


func _capture(file_stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image != null and not image.is_empty())
	var path := _output_directory.path_join(file_stem + ".png")
	assert(image.save_png(ProjectSettings.globalize_path(path)) == OK)
	print("Captured: %s" % ProjectSettings.globalize_path(path))
