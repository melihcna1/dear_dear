extends SceneTree

const SOURCE_TEST_ROOT := "res://asset_import_sources/_queue_selection_test"
const JOURNAL_TEST_PATH := "user://asset_importer_queue_selection/state.json"


class QueueHarness extends DearDearAssetImporterMain:
	func _ready() -> void:
		# The production _ready() loads user state and may contact Sheets. This
		# harness builds only the UI/state needed to exercise file selection.
		pass


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
	assert(await _wait_for_source_preview(importer._studio, importer._drafts[0].source_path, 0))
	var first_signature := importer._studio.get_presented_signature()

	# Reproduce the Windows picker failure exactly: it may return the stale old
	# path together with the newly selected path. The new draft must win.
	importer._on_files_selected(PackedStringArray([first_source, second_source]))
	assert(importer._drafts.size() == 2)
	assert(importer._current_index == 1)
	assert(await _wait_for_source_preview(importer._studio, importer._drafts[1].source_path, first_signature))
	var second_signature := importer._studio.get_presented_signature()
	assert(importer._studio.get_loaded_source_path() == importer._drafts[1].source_path)

	# Selecting a file that is already queued must switch to and reload that
	# existing draft instead of silently leaving the other model on screen.
	importer._on_files_selected(PackedStringArray([first_source]))
	assert(importer._drafts.size() == 2)
	assert(importer._current_index == 0)
	assert("already queued" in importer._global_status.text.to_lower())
	assert(await _wait_for_source_preview(importer._studio, importer._drafts[0].source_path, second_signature))
	assert(importer._studio.get_loaded_source_path() == importer._drafts[0].source_path)

	var copied_paths := PackedStringArray()
	for draft in importer._drafts:
		copied_paths.append(ProjectSettings.globalize_path(draft.source_path))
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
