extends SceneTree

const AssetSourceRepository := preload("res://addons/dear_dear_asset_importer/asset_source_repository.gd")
const AssetImporterMainScript := preload("res://addons/dear_dear_asset_importer/asset_importer_main.gd")
const FURNITURE_GLB := "res://assets/dev_model/character/dear_dear_male_rig_character.glb"
const CLOTH_GLB := "res://assets/dev_model/character/dear_dear_female_rig_character.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DearDearAssetToolConfig.new()
	assert(AssetImporterMainScript != null)
	assert(config.load_from_disk(), config.error_message)
	_test_ranges(config)
	_test_naming(config)
	_test_source_repository()
	_test_drafts(config)
	_test_id_audit(config)
	_test_catalog(config)
	_test_journal(config)
	await _test_sheets_response_parsing()
	await _test_preview_and_capture()
	print("AssetImporterTests: PASS")
	quit()


func _test_ranges(config: DearDearAssetToolConfig) -> void:
	assert(config.id_range("seeds") == Vector2i(110000, 119999))
	assert(config.id_range("furniture") == Vector2i(210000, 299999))
	assert(config.id_range("cloth") == Vector2i(310000, 399999))
	assert(config.id_range("market_shop") == Vector2i(710000, 999999))
	assert(config.is_id_allowed("cloth", "310193"))
	assert(not config.is_id_allowed("cloth", "300001"))
	assert(not config.is_id_allowed("cloth", "31019"))
	assert(config.is_reserved(300000))
	assert(not config.is_reserved(310000))
	assert(not config.can_omit_id("cloth"))
	assert(config.can_omit_id("food"))
	assert(config.destination_path("cloth", "top", "female") == "res://assets/dev_model/clothes/female/top")
	var inferred := config.infer_taxonomy("C:/incoming/clothes/female/shoes/f_cloth_shoes_310180_Rig.glb")
	assert(inferred.main_category == "cloth")
	assert(inferred.sub_category == "shoe")
	assert(inferred.gender == "female")


func _test_naming(config: DearDearAssetToolConfig) -> void:
	assert(DearDearAssetNaming.slugify("  Çizgili Summer-Shirt_Rig ") == "cizgili_summer_shirt")
	var cloth_name := DearDearAssetNaming.asset_name(
		config, "cloth", "top", "female", "Summer Sweater", "310193", true)
	assert(cloth_name == "f_cloth_top_summer_sweater_310193")
	assert(DearDearAssetNaming.sprite_name(cloth_name) == "f_cloth_top_summer_sweater_310193_s")
	var food_name := DearDearAssetNaming.asset_name(
		config, "food", "dessert", "unisex", "Banana Waffles", "130000", false)
	assert(food_name == "food_dessert_banana_waffles")
	assert(DearDearAssetNaming.csv_escape("hello, \"world\"") == "\"hello, \"\"world\"\"\"")


func _test_source_repository() -> void:
	var repository := AssetSourceRepository.new()
	repository.root_path = "user://asset_importer_tests/source_inbox"
	var incoming := ProjectSettings.globalize_path("user://asset_importer_tests/incoming/source.glb")
	DirAccess.make_dir_recursive_absolute(incoming.get_base_dir())
	var incoming_file := FileAccess.open(incoming, FileAccess.WRITE)
	incoming_file.store_buffer(PackedByteArray([1, 2, 3, 4]))
	incoming_file.close()
	var first: Dictionary = repository.store(incoming, "cloth", "shoe", "female")
	assert(first.ok)
	assert(str(first.path).begins_with(repository.root_path))
	assert(FileAccess.file_exists(ProjectSettings.globalize_path(str(first.path))))
	assert(repository.find_by_filename("source.glb").size() == 1)
	incoming_file = FileAccess.open(incoming, FileAccess.WRITE)
	incoming_file.store_buffer(PackedByteArray([5, 6, 7, 8]))
	incoming_file.close()
	var collision_safe: Dictionary = repository.store(incoming, "cloth", "shoe", "female")
	assert(collision_safe.ok)
	assert(collision_safe.path != first.path)
	var replaced: Dictionary = repository.store(incoming, "cloth", "shoe", "female", str(first.path), true)
	assert(replaced.ok)
	assert(replaced.path == first.path)
	assert(FileAccess.get_sha256(ProjectSettings.globalize_path(str(first.path))) == FileAccess.get_sha256(incoming))
	DirAccess.remove_absolute(incoming)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(first.path)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(collision_safe.path)))


func _test_drafts(config: DearDearAssetToolConfig) -> void:
	var draft_fixture := ProjectSettings.globalize_path("user://asset_importer_tests/draft_fixture.glb")
	DirAccess.make_dir_recursive_absolute(draft_fixture.get_base_dir())
	var fixture_file := FileAccess.open(draft_fixture, FileAccess.WRITE)
	fixture_file.store_string("draft fixture")
	fixture_file.close()
	var draft := DearDearAssetDraft.create(draft_fixture)
	draft.main_category = "furniture"
	draft.sub_category = "decor"
	draft.item_name = "Teal Book"
	draft.item_id = "210078"
	draft.refresh_derived(config)
	assert(draft.asset_name == "furniture_decor_teal_book_210078")
	assert(draft.sprite_name == "furniture_decor_teal_book_210078_s")
	assert(draft.model_path.ends_with("furniture_decor_teal_book_210078.glb"))
	assert(draft.market_image_path.ends_with("furniture_decor_teal_book_210078_s.png"))
	assert(draft.validate(config).is_empty())
	var restored := DearDearAssetDraft.from_dictionary(draft.to_dictionary())
	assert(restored.record_id == draft.record_id)
	assert(restored.source_sha256 == draft.source_sha256)
	assert(restored.asset_name == draft.asset_name)
	DirAccess.remove_absolute(draft_fixture)


func _test_id_audit(config: DearDearAssetToolConfig) -> void:
	var index := DearDearAssetIdIndex.new()
	index.rebuild()
	var next_cloth_id := index.next_available(config.id_range("cloth"))
	assert(next_cloth_id >= 310000 and next_cloth_id <= 399999)
	assert(index.last_used(config.id_range("cloth")) == next_cloth_id - 1)
	assert(not index.is_used("%06d" % next_cloth_id))
	var next_furniture_id := index.next_available(config.id_range("furniture"))
	assert(next_furniture_id >= 210000 and next_furniture_id <= 299999)
	assert(not index.is_used("%06d" % next_furniture_id))
	var collisions := index.duplicates()
	assert(not collisions.has("310219"))


func _test_catalog(config: DearDearAssetToolConfig) -> void:
	var repository := DearDearAssetCatalogRepository.new()
	repository.catalog_path = "user://asset_importer_tests/catalog.json"
	repository.csv_path = "user://asset_importer_tests/catalog.csv"
	var draft := DearDearAssetDraft.create(ProjectSettings.globalize_path(FURNITURE_GLB))
	draft.main_category = "furniture"
	draft.sub_category = "decor"
	draft.item_name = "Comma, Quote \"Test\""
	draft.item_id = "210078"
	draft.refresh_derived(config)
	var result := repository.upsert_drafts([draft])
	assert(result.ok, str(result.get("error", "")))
	var reloaded := DearDearAssetCatalogRepository.new()
	reloaded.catalog_path = repository.catalog_path
	reloaded.csv_path = repository.csv_path
	assert(reloaded.load_catalog().ok)
	assert(reloaded.items.size() == 1)
	assert(reloaded.items[0].record_id == draft.record_id)
	var csv := FileAccess.get_file_as_string(repository.csv_path)
	assert(csv.begins_with("record_id,item_id,item_name"))
	assert(csv.contains("\"Comma, Quote \"\"Test\"\"\""))
	draft.is_sellable = true
	assert(repository.upsert_drafts([draft]).ok)
	assert(repository.items.size() == 1)
	assert(bool(repository.items[0].is_sellable))


func _test_journal(config: DearDearAssetToolConfig) -> void:
	var journal := DearDearAssetJournal.new()
	journal.journal_path = "user://asset_importer_tests/state.json"
	var draft := DearDearAssetDraft.create(ProjectSettings.globalize_path(FURNITURE_GLB))
	draft.item_id = "210078"
	draft.item_name = "Journal Test"
	draft.refresh_derived(config)
	assert(journal.save_state(
		[draft],
		{"furniture/decor": {"yaw": 1.25}},
		{"ambient_energy": 0.8, "key_energy": 2.2, "fill_energy": 1.1, "rim_energy": 0.7}))
	var state := journal.load_state()
	assert(state.drafts.size() == 1)
	assert(state.drafts[0].record_id == draft.record_id)
	assert(is_equal_approx(float(state.camera_profiles["furniture/decor"].yaw), 1.25))
	assert(is_equal_approx(float(state.lighting.ambient_energy), 0.8))
	assert(is_equal_approx(float(state.lighting.key_energy), 2.2))


func _test_sheets_response_parsing() -> void:
	var client := DearDearSheetsClient.new()
	root.add_child(client)
	await process_frame
	var success := client.parse_http_response(
		HTTPRequest.RESULT_SUCCESS, 200, '{"ok":true,"data":{"item_id":"310193"}}'.to_utf8_buffer())
	assert(success.ok)
	assert(success.data.item_id == "310193")
	var authentication := client.parse_http_response(
		HTTPRequest.RESULT_SUCCESS, 200, '{"ok":false,"error":{"code":"unauthorized","message":"Invalid token"}}'.to_utf8_buffer())
	assert(not authentication.ok)
	assert(authentication.error.code == "unauthorized")
	var malformed := client.parse_http_response(HTTPRequest.RESULT_SUCCESS, 200, 'not json'.to_utf8_buffer())
	assert(not malformed.ok)
	assert(malformed.error.code == "malformed_response")
	var timeout := client.parse_http_response(HTTPRequest.RESULT_TIMEOUT, 0, PackedByteArray())
	assert(not timeout.ok)
	assert(timeout.error.code == "transport_error")
	var redirect_headers := PackedStringArray([
		"Content-Type: application/binary",
		"Location: https://script.googleusercontent.com/macros/echo?user_content_key=test",
	])
	var redirect_url := client.redirect_location(redirect_headers)
	assert(redirect_url == "https://script.googleusercontent.com/macros/echo?user_content_key=test")
	assert(client.is_trusted_apps_script_redirect(redirect_url))
	assert(not client.is_trusted_apps_script_redirect("https://example.com/macros/echo"))
	client.queue_free()


func _test_preview_and_capture() -> void:
	var source_glb := _available_preview_fixture()
	if source_glb.is_empty():
		print("AssetImporterTests: preview test skipped (no GLB fixture available)")
		return
	var studio := DearDearPreviewStudio.new()
	root.add_child(studio)
	await process_frame
	var transparent := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	transparent.fill(Color(0.0, 0.0, 0.0, 0.0))
	assert(not studio._image_has_visible_content(transparent))
	var opaque_black := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	opaque_black.fill(Color(0.0, 0.0, 0.0, 1.0))
	assert(studio._image_has_visible_content(opaque_black))
	assert(studio.validate_self_contained_glb(source_glb).ok)
	var before_hash := FileAccess.get_sha256(source_glb)
	assert(studio.load_glb(source_glb).ok)
	assert(studio.get_loaded_source_path() == source_glb)
	var first_model_instance_id := studio.get_model_instance_id()
	assert(first_model_instance_id != 0)
	studio.set_lighting({"ambient_energy": 0.8, "key_energy": 2.4, "fill_energy": 1.2, "rim_energy": 0.6})
	var lighting := studio.get_lighting()
	assert(is_equal_approx(float(lighting.ambient_energy), 0.8))
	assert(is_equal_approx(float(lighting.key_energy), 2.4))
	studio.set_camera_profile({"yaw": 1.0, "pitch": -0.2, "distance": 4.0, "pan_x": 0.1, "pan_y": -0.1})
	var retained := studio.get_camera_profile()
	assert(is_equal_approx(float(retained.yaw), 1.0))
	assert(studio.load_glb(source_glb).ok)
	assert(studio.get_loaded_source_path() == source_glb)
	var second_model_instance_id := studio.get_model_instance_id()
	assert(second_model_instance_id != first_model_instance_id)
	assert(not is_instance_id_valid(first_model_instance_id))
	retained = studio.get_camera_profile()
	assert(is_equal_approx(float(retained.distance), 4.0))
	assert(studio.load_glb(source_glb).ok)
	assert(studio.get_loaded_source_path() == source_glb)
	assert(not is_instance_id_valid(second_model_instance_id))
	assert(studio.load_glb(source_glb).ok)
	assert(studio.get_loaded_source_path() == source_glb)
	var capture_path := "user://asset_importer_tests/capture.png"
	var capture_result: Dictionary = await studio.capture_png(capture_path)
	assert(capture_result.ok, str(capture_result.get("error", "")))
	assert(studio.get_presented_texture() is ImageTexture)
	var image := Image.load_from_file(ProjectSettings.globalize_path(capture_path))
	assert(not image.is_empty())
	assert(image.get_size() == Vector2i(1024, 1024))
	assert(image.detect_alpha() != Image.ALPHA_NONE)
	assert(image.get_pixel(0, 0).a < 0.05)
	assert(image.get_used_rect().has_area())
	assert(FileAccess.get_sha256(source_glb) == before_hash)
	var external_fixture := ProjectSettings.globalize_path("user://asset_importer_tests/external_fixture.glb")
	DirAccess.make_dir_recursive_absolute(external_fixture.get_base_dir())
	assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(source_glb) if source_glb.begins_with("res://") else source_glb, external_fixture) == OK)
	assert(studio.load_glb(external_fixture).ok)
	assert(studio.get_renderable_mesh_count() > 0)
	var external_capture: Dictionary = await studio.capture_png("user://asset_importer_tests/external_capture.png")
	assert(external_capture.ok, str(external_capture.get("error", "")))
	DirAccess.remove_absolute(external_fixture)
	studio.queue_free()


func _available_preview_fixture() -> String:
	for path in [OS.get_environment("DEAR_DEAR_TEST_GLB"), FURNITURE_GLB, CLOTH_GLB]:
		if path.is_empty():
			continue
		var absolute: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
		if FileAccess.file_exists(absolute):
			return path
	return ""
