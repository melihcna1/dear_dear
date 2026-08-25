extends SceneTree

const FURNITURE_GLB := "res://assets/dev_model/furniture/furniture_decor_210000.glb"
const CLOTH_GLB := "res://assets/dev_model/clothes/female/top/f_cloth_top_310044_Rig.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := DearDearAssetToolConfig.new()
	assert(config.load_from_disk(), config.error_message)
	_test_ranges(config)
	_test_naming(config)
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


func _test_drafts(config: DearDearAssetToolConfig) -> void:
	var draft := DearDearAssetDraft.create(ProjectSettings.globalize_path(FURNITURE_GLB))
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


func _test_id_audit(config: DearDearAssetToolConfig) -> void:
	var index := DearDearAssetIdIndex.new()
	index.rebuild()
	assert(index.next_available(config.id_range("cloth")) == 310193)
	assert(index.next_available(config.id_range("furniture")) == 210078)
	var collisions := index.duplicates()
	assert(collisions.has("310148"))
	assert(collisions["310148"].size() == 2)
	assert(not collisions.has("210000"))


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
	assert(journal.save_state([draft], {"furniture/decor": {"yaw": 1.25}}))
	var state := journal.load_state()
	assert(state.drafts.size() == 1)
	assert(state.drafts[0].record_id == draft.record_id)
	assert(is_equal_approx(float(state.camera_profiles["furniture/decor"].yaw), 1.25))


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
	var studio := DearDearPreviewStudio.new()
	root.add_child(studio)
	await process_frame
	assert(studio.validate_self_contained_glb(FURNITURE_GLB).ok)
	var before_hash := FileAccess.get_sha256(FURNITURE_GLB)
	assert(studio.load_glb(FURNITURE_GLB).ok)
	studio.set_camera_profile({"yaw": 1.0, "pitch": -0.2, "distance": 4.0, "pan_x": 0.1, "pan_y": -0.1})
	var retained := studio.get_camera_profile()
	assert(is_equal_approx(float(retained.yaw), 1.0))
	assert(studio.load_glb(CLOTH_GLB).ok)
	retained = studio.get_camera_profile()
	assert(is_equal_approx(float(retained.distance), 4.0))
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
	assert(FileAccess.get_sha256(FURNITURE_GLB) == before_hash)
	studio.queue_free()
