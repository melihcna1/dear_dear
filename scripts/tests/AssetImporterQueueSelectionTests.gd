extends SceneTree

const SOURCE_TEST_ROOT := "res://asset_import_sources/_queue_selection_test"
const JOURNAL_TEST_PATH := "user://asset_importer_queue_selection/state.json"


class QueueHarness extends DearDearAssetImporterMain:
	var captured_record_ids := PackedStringArray()

	func _ready() -> void:
		# The production _ready() loads user state and may contact Sheets. This
		# harness builds only the UI/state needed to exercise file selection.
		pass

	func _capture_draft(draft: DearDearAssetDraft) -> Dictionary:
		captured_record_ids.append(draft.record_id)
		await get_tree().process_frame
		return {"ok": true}


class FakeCatalog extends DearDearAssetCatalogRepository:
	var exported_record_ids := PackedStringArray()

	func upsert_drafts(drafts: Array) -> Dictionary:
		for draft in drafts:
			exported_record_ids.append(draft.record_id)
		return {"ok": true, "count": drafts.size()}


class FakeSheets extends DearDearSheetsClient:
	var synced_record_ids := PackedStringArray()

	func _ready() -> void:
		pass

	func is_configured() -> bool:
		return true

	func call_action(action: String, payload: Dictionary = {}) -> Dictionary:
		if action == "upsert":
			for row in payload.get("rows", []):
				synced_record_ids.append(str(row.get("record_id", "")))
		await get_tree().process_frame
		return {"ok": true, "data": {}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dev_root := OS.get_environment("DEAR_DEAR_DEV_MODEL_ROOT")
	var first_source := dev_root.path_join("clothes/female/top/f_cloth_top_310083_Rig.glb")
	var second_source := dev_root.path_join("clothes/female/top/f_cloth_top_310057_Rig.glb")
	assert(FileAccess.file_exists(first_source), "Missing queue fixture 310083.")
	assert(FileAccess.file_exists(second_source), "Missing queue fixture 310057.")

	var importer := QueueHarness.new()
	importer._journal.journal_path = JOURNAL_TEST_PATH
	importer._source_repository.root_path = SOURCE_TEST_ROOT
	root.add_child(importer)
	importer._build_ui()
	assert(importer._config.load_from_disk(), importer._config.error_message)
	importer._populate_categories()
	await process_frame

	importer._on_files_selected(PackedStringArray([first_source]))
	assert(importer._drafts.size() == 1)
	assert(importer._current_index == 0)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0]))
	assert(await _wait_for_source_preview(importer._studio, importer._drafts[0].source_path, 0))
	var first_signature := importer._studio.get_presented_signature()

	# Reproduce the Windows picker failure exactly: it may return the stale old
	# path together with the newly selected path. The new draft must win.
	importer._on_files_selected(PackedStringArray([first_source, second_source]))
	assert(importer._drafts.size() == 2)
	assert(importer._current_index == 1)
	assert(importer._queue.get_selected_items() == PackedInt32Array([1]))
	assert(await _wait_for_source_preview(importer._studio, importer._drafts[1].source_path, first_signature))
	var second_signature := importer._studio.get_presented_signature()
	assert(importer._studio.get_loaded_source_path() == importer._drafts[1].source_path)

	# Reproduce the capture bug from the video: an older synced row is still
	# selected behind the active row. Capture must process only the active record.
	var first_record_id: String = importer._drafts[0].record_id
	var second_record_id: String = importer._drafts[1].record_id
	importer._drafts[0].status = DearDearAssetDraft.STATUS_SYNCED
	importer._drafts[1].status = DearDearAssetDraft.STATUS_RESERVED
	importer._queue.select(0, false)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0, 1]))
	await importer._capture_selected()
	assert(importer.captured_record_ids == PackedStringArray([second_record_id]))
	assert(importer._drafts[0].record_id == first_record_id)
	assert(importer._drafts[0].status == DearDearAssetDraft.STATUS_SYNCED)
	assert(importer._drafts[1].status == DearDearAssetDraft.STATUS_CAPTURED)

	# Export and Sheets sync are also current-record actions. Even with the same
	# stale two-row selection, neither may touch the older synced record.
	var fake_catalog := FakeCatalog.new()
	importer._catalog = fake_catalog
	importer._export_selected()
	assert(fake_catalog.exported_record_ids == PackedStringArray([second_record_id]))
	assert(importer._drafts[0].status == DearDearAssetDraft.STATUS_SYNCED)
	assert(importer._drafts[1].status == DearDearAssetDraft.STATUS_EXPORTED)
	var fake_sheets := FakeSheets.new()
	importer.add_child(fake_sheets)
	importer._sheets = fake_sheets
	await importer._sync_selected()
	assert(fake_sheets.synced_record_ids == PackedStringArray([second_record_id]))
	assert(importer._drafts[0].status == DearDearAssetDraft.STATUS_SYNCED)
	assert(importer._drafts[1].status == DearDearAssetDraft.STATUS_SYNCED)

	# Godot emits item_clicked after Ctrl-deselecting a row. The click handler must
	# not reselect or activate the row the user just removed from the selection.
	importer._queue.deselect(0)
	importer._on_queue_multi_selected(0, false)
	importer._on_queue_item_clicked(0, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	assert(importer._queue.get_selected_items() == PackedInt32Array([1]))
	assert(importer._current_index == 1)

	# Selecting a file that is already queued must switch to and reload that
	# existing draft instead of silently leaving the other model on screen.
	importer._on_files_selected(PackedStringArray([first_source]))
	assert(importer._drafts.size() == 2)
	assert(importer._current_index == 0)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0]))
	assert("already synced" in importer._global_status.text.to_lower())
	assert(await _wait_for_source_preview(importer._studio, importer._drafts[0].source_path, second_signature))
	assert(importer._studio.get_loaded_source_path() == importer._drafts[0].source_path)

	var copied_paths := PackedStringArray()
	for draft in importer._drafts:
		copied_paths.append(ProjectSettings.globalize_path(draft.source_path))

	# Rebuilding the queue must preserve explicit multi-selection without changing
	# the plugin's active record.
	importer._queue.select(1, false)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0, 1]))
	importer._refresh_queue()
	assert(importer._current_index == 0)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0, 1]))

	# Remove Draft is also an active-record action. A stale multi-selection must
	# not delete both records.
	importer._drafts[0].status = DearDearAssetDraft.STATUS_DRAFT
	importer._drafts[1].status = DearDearAssetDraft.STATUS_DRAFT
	importer._select_index(1)
	importer._queue.select(0, false)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0, 1]))
	importer._remove_selected_drafts()
	assert(importer._drafts.size() == 1)
	assert(importer._drafts[0].record_id == first_record_id)
	assert(importer._current_index == 0)
	assert(importer._queue.get_selected_items() == PackedInt32Array([0]))
	importer.queue_free()
	await process_frame
	for copied_path in copied_paths:
		if FileAccess.file_exists(copied_path):
			DirAccess.remove_absolute(copied_path)
	_remove_empty_tree(ProjectSettings.globalize_path(SOURCE_TEST_ROOT))
	var journal_absolute := ProjectSettings.globalize_path(JOURNAL_TEST_PATH)
	if FileAccess.file_exists(journal_absolute):
		DirAccess.remove_absolute(journal_absolute)
	_remove_empty_tree(journal_absolute.get_base_dir())
	print("AssetImporterQueueSelectionTests: PASS")
	quit()


func _wait_for_source_preview(
	studio: DearDearPreviewStudio,
	expected_source: String,
	rejected_signature: int,
) -> bool:
	for unused in 300:
		if (
			studio.get_loaded_source_path() == expected_source
			and studio.get_presented_texture()
			and studio.get_presented_signature() != 0
			and (rejected_signature == 0 or studio.get_presented_signature() != rejected_signature)
		):
			return true
		await process_frame
	return false


func _remove_empty_tree(absolute_directory: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_directory):
		return
	for child_directory in DirAccess.get_directories_at(absolute_directory):
		_remove_empty_tree(absolute_directory.path_join(child_directory))
	DirAccess.remove_absolute(absolute_directory)
