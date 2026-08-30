@tool
class_name DearDearAssetImporterMain
extends Control

const AssetSourceRepository := preload("res://addons/dear_dear_asset_importer/asset_source_repository.gd")
const STATUS_COLORS := {
	DearDearAssetDraft.STATUS_DRAFT: Color(0.78, 0.80, 0.84),
	DearDearAssetDraft.STATUS_RESERVED: Color(0.95, 0.77, 0.32),
	DearDearAssetDraft.STATUS_CAPTURED: Color(0.44, 0.77, 0.96),
	DearDearAssetDraft.STATUS_EXPORTED: Color(0.50, 0.86, 0.58),
	DearDearAssetDraft.STATUS_SYNCED: Color(0.34, 0.90, 0.54),
	DearDearAssetDraft.STATUS_ERROR: Color(1.0, 0.42, 0.42),
}

var _config := DearDearAssetToolConfig.new()
var _catalog := DearDearAssetCatalogRepository.new()
var _id_index := DearDearAssetIdIndex.new()
var _journal := DearDearAssetJournal.new()
var _source_repository := AssetSourceRepository.new()
var _sheets: DearDearSheetsClient
var _studio: DearDearPreviewStudio
var _drafts: Array[DearDearAssetDraft] = []
var _camera_profiles: Dictionary = {}
var _lighting_profile: Dictionary = {}
var _remote_ids := PackedStringArray()
var _current_index := -1
var _updating_form := false
var _busy := false
var _journal_save_queued := false

var _file_dialog: FileDialog
var _replace_source_dialog: FileDialog
var _error_dialog: AcceptDialog
var _settings_dialog: AcceptDialog
var _settings_url: LineEdit
var _settings_token: LineEdit
var _lighting_dialog: AcceptDialog
var _lighting_ambient: SpinBox
var _lighting_key: SpinBox
var _lighting_fill: SpinBox
var _lighting_rim: SpinBox
var _queue: ItemList
var _category_option: OptionButton
var _subcategory_option: OptionButton
var _gender_option: OptionButton
var _buyable_check: CheckBox
var _sellable_check: CheckBox
var _include_id_check: CheckBox
var _auto_id_check: CheckBox
var _overwrite_check: CheckBox
var _item_name_line: LineEdit
var _item_id_line: LineEdit
var _sprite_name_line: LineEdit
var _asset_name_line: LineEdit
var _next_id_label: Label
var _source_label: Label
var _record_status_label: Label
var _global_status: Label
var _connection_label: Label
var _audit_label: Label
var _capture_button: Button
var _export_button: Button
var _sync_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if not _config.load_from_disk():
		_show_error(_config.error_message)
		return
	var catalog_result := _catalog.load_catalog()
	if not catalog_result.ok:
		_show_error(str(catalog_result.error))
	_load_journal()
	_sheets = DearDearSheetsClient.new()
	add_child(_sheets)
	_populate_categories()
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	_update_audit()
	_update_connection_status()
	if not _drafts.is_empty():
		_select_index(0)
	else:
		_clear_form()
	call_deferred("_refresh_remote_snapshot")


func save_plugin_state() -> void:
	_flush_journal()


func set_workspace_visible(workspace_visible: bool) -> void:
	visible = workspace_visible
	if not _studio:
		return
	if workspace_visible:
		call_deferred("_activate_visible_preview")
	else:
		_studio.set_preview_active(false)


func _activate_visible_preview() -> void:
	if not visible or not is_inside_tree() or not _studio:
		return
	# Main-screen plugins are built while hidden. Reload only after Godot has
	# made the workspace visible and assigned its final Control dimensions.
	if _current_index >= 0 and not _busy:
		_load_current_preview()
	_studio.set_preview_active(true)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	var title := Label.new()
	title.text = "Asset Importer"
	title.add_theme_font_size_override("font_size", 20)
	toolbar.add_child(title)
	toolbar.add_spacer(false)
	_connection_label = Label.new()
	toolbar.add_child(_connection_label)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh IDs"
	refresh_button.tooltip_text = "Rescan local assets and refresh the remote ID snapshot."
	refresh_button.pressed.connect(_refresh_all_ids)
	toolbar.add_child(refresh_button)
	var settings_button := Button.new()
	settings_button.text = "Sheets Settings"
	settings_button.pressed.connect(_open_settings)
	toolbar.add_child(settings_button)

	var split := HSplitContainer.new()
	split.name = "MainPanel"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 700
	root.add_child(split)

	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left_panel.add_child(left)
	var studio_title := Label.new()
	studio_title.text = "3D Viewport & Capture Studio"
	studio_title.add_theme_font_size_override("font_size", 16)
	left.add_child(studio_title)
	_studio = DearDearPreviewStudio.new()
	_studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_studio.camera_profile_changed.connect(_on_camera_profile_changed)
	left.add_child(_studio)
	var camera_help := Label.new()
	camera_help.text = "Left-drag: orbit   •   Shift-left or middle-drag: pan   •   Wheel: zoom"
	camera_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(camera_help)
	var camera_actions := HBoxContainer.new()
	left.add_child(camera_actions)
	var reset_button := Button.new()
	reset_button.text = "Reset Camera Angle"
	reset_button.pressed.connect(_reset_camera)
	camera_actions.add_child(reset_button)
	var test_capture_button := Button.new()
	test_capture_button.text = "Temporary Capture Test"
	test_capture_button.tooltip_text = "Captures to user:// without reserving an ID or writing project assets."
	test_capture_button.pressed.connect(_temporary_capture)
	camera_actions.add_child(test_capture_button)
	var lighting_button := Button.new()
	lighting_button.text = "Lighting Settings"
	lighting_button.tooltip_text = "Adjust the studio lights used by both the preview and final PNG capture."
	lighting_button.pressed.connect(_open_lighting_settings)
	camera_actions.add_child(lighting_button)
	camera_actions.add_spacer(false)
	_source_label = Label.new()
	_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_actions.add_child(_source_label)

	var right_split := VSplitContainer.new()
	right_split.custom_minimum_size = Vector2(390, 0)
	right_split.split_offset = 430
	split.add_child(right_split)
	_build_metadata_panel(right_split)
	_build_queue_panel(right_split)

	var status_bar := HBoxContainer.new()
	root.add_child(status_bar)
	_global_status = Label.new()
	_global_status.text = "Ready."
	_global_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_global_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_bar.add_child(_global_status)
	_audit_label = Label.new()
	status_bar.add_child(_audit_label)

	_file_dialog = FileDialog.new()
	_file_dialog.title = "Select GLB Files"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	# Godot's embedded picker is used intentionally. The Windows native picker
	# can retain and resubmit the previous filename even after another row is
	# highlighted, which made the importer appear to ignore model changes.
	_file_dialog.use_native_dialog = false
	_file_dialog.add_filter("*.glb", "Binary glTF Models")
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)
	_replace_source_dialog = FileDialog.new()
	_replace_source_dialog.title = "Relink or Replace Source GLB"
	_replace_source_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_replace_source_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_replace_source_dialog.use_native_dialog = false
	_replace_source_dialog.add_filter("*.glb", "Binary glTF Models")
	_replace_source_dialog.file_selected.connect(_on_replacement_file_selected)
	add_child(_replace_source_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Asset Importer"
	add_child(_error_dialog)
	_build_settings_dialog()
	_build_lighting_dialog()


func _build_metadata_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	scroll.add_child(form)
	var heading := Label.new()
	heading.text = "Selection, Settings & Info"
	heading.add_theme_font_size_override("font_size", 16)
	form.add_child(heading)

	_category_option = OptionButton.new()
	_category_option.name = "main_category_option"
	_category_option.item_selected.connect(_on_category_selected)
	_add_form_row(form, "Main category", _category_option)
	_subcategory_option = OptionButton.new()
	_subcategory_option.name = "sub_category_option"
	_subcategory_option.item_selected.connect(_on_subcategory_selected)
	_add_form_row(form, "Subcategory", _subcategory_option)
	_gender_option = OptionButton.new()
	_gender_option.name = "gender_option"
	for value in ["Female", "Male", "Unisex"]:
		_gender_option.add_item(value)
		_gender_option.set_item_metadata(_gender_option.item_count - 1, value.to_lower())
	_gender_option.item_selected.connect(_on_form_changed)
	_add_form_row(form, "Gender", _gender_option)

	_item_name_line = LineEdit.new()
	_item_name_line.placeholder_text = "Summer sweater"
	_item_name_line.text_changed.connect(_on_text_form_changed)
	_add_form_row(form, "Item name", _item_name_line)

	var id_box := HBoxContainer.new()
	_item_id_line = LineEdit.new()
	_item_id_line.name = "item_id_line"
	_item_id_line.max_length = 6
	_item_id_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_id_line.text_changed.connect(_on_id_changed)
	id_box.add_child(_item_id_line)
	_auto_id_check = CheckBox.new()
	_auto_id_check.text = "Auto"
	_auto_id_check.button_pressed = true
	_auto_id_check.toggled.connect(_on_auto_id_toggled)
	id_box.add_child(_auto_id_check)
	_add_form_row(form, "Item ID", id_box)

	_next_id_label = Label.new()
	_next_id_label.name = "next_available_id_label"
	_next_id_label.text = "Last: —   Next: —"
	form.add_child(_next_id_label)

	_asset_name_line = LineEdit.new()
	_asset_name_line.editable = false
	_add_form_row(form, "Asset filename", _asset_name_line)
	_sprite_name_line = LineEdit.new()
	_sprite_name_line.name = "sprite_name_line"
	_sprite_name_line.editable = false
	_add_form_row(form, "Sprite name", _sprite_name_line)

	var flags := HBoxContainer.new()
	_buyable_check = CheckBox.new()
	_buyable_check.name = "is_buyable_check"
	_buyable_check.text = "Buyable"
	_buyable_check.toggled.connect(_on_form_changed)
	flags.add_child(_buyable_check)
	_sellable_check = CheckBox.new()
	_sellable_check.name = "is_sellable_check"
	_sellable_check.text = "Sellable"
	_sellable_check.toggled.connect(_on_form_changed)
	flags.add_child(_sellable_check)
	_include_id_check = CheckBox.new()
	_include_id_check.text = "ID in filename"
	_include_id_check.toggled.connect(_on_form_changed)
	flags.add_child(_include_id_check)
	form.add_child(flags)

	_overwrite_check = CheckBox.new()
	_overwrite_check.text = "Confirm update of this record's existing output files"
	_overwrite_check.tooltip_text = "Only files already owned by the same catalog record may be replaced."
	_overwrite_check.toggled.connect(_on_form_changed)
	form.add_child(_overwrite_check)
	_record_status_label = Label.new()
	_record_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_record_status_label)
	var apply_button := Button.new()
	apply_button.text = "Apply Category Settings to Selected"
	apply_button.tooltip_text = "Copies category, subcategory, gender, flags, and filename-ID policy to all selected rows."
	apply_button.pressed.connect(_apply_metadata_to_selected)
	form.add_child(apply_button)


func _build_queue_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "File List & Output Actions"
	heading.add_theme_font_size_override("font_size", 16)
	box.add_child(heading)
	_queue = ItemList.new()
	_queue.name = "file_item_list"
	_queue.select_mode = ItemList.SELECT_MULTI
	_queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_queue.multi_selected.connect(_on_queue_multi_selected)
	_queue.item_clicked.connect(_on_queue_item_clicked)
	_queue.item_activated.connect(_on_queue_item_selected)
	box.add_child(_queue)
	var source_actions := HBoxContainer.new()
	box.add_child(source_actions)
	var add_button := Button.new()
	add_button.text = "Add GLB Files to Project…"
	add_button.tooltip_text = "Copies selected GLBs into the project-local source inbox before queueing them."
	add_button.pressed.connect(_open_file_dialog)
	add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_actions.add_child(add_button)
	var source_folder_button := Button.new()
	source_folder_button.text = "Open Source Folder"
	source_folder_button.tooltip_text = "Opens the project-local raw GLB inbox in the system file browser."
	source_folder_button.pressed.connect(_open_source_folder)
	source_folder_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_actions.add_child(source_folder_button)
	var queue_actions := HBoxContainer.new()
	box.add_child(queue_actions)
	var replace_source_button := Button.new()
	replace_source_button.text = "Relink / Replace Source…"
	replace_source_button.tooltip_text = "Copies a replacement GLB into the project and assigns it to the active record."
	replace_source_button.pressed.connect(_open_replacement_source_dialog)
	queue_actions.add_child(replace_source_button)
	var remove_button := Button.new()
	remove_button.text = "Remove Draft"
	remove_button.pressed.connect(_remove_selected_drafts)
	queue_actions.add_child(remove_button)
	queue_actions.add_spacer(false)
	var count_label := Label.new()
	count_label.name = "DraftCount"
	queue_actions.add_child(count_label)

	_capture_button = Button.new()
	_capture_button.name = "capture_and_save_image_button"
	_capture_button.text = "Capture & Save Market PNG Image"
	_capture_button.pressed.connect(_capture_selected)
	box.add_child(_capture_button)
	var output_actions := HBoxContainer.new()
	box.add_child(output_actions)
	_export_button = Button.new()
	_export_button.name = "export_csv_json_button"
	_export_button.text = "Export CSV / JSON"
	_export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_button.pressed.connect(_export_selected)
	output_actions.add_child(_export_button)
	_sync_button = Button.new()
	_sync_button.name = "sync_google_sheets_button"
	_sync_button.text = "Sync Google Sheets"
	_sync_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sync_button.pressed.connect(_sync_selected)
	output_actions.add_child(_sync_button)


func _build_settings_dialog() -> void:
	_settings_dialog = AcceptDialog.new()
	_settings_dialog.title = "Google Sheets Webhook Settings"
	_settings_dialog.ok_button_text = "Save"
	_settings_dialog.confirmed.connect(_save_settings)
	var fields := VBoxContainer.new()
	fields.custom_minimum_size = Vector2(560, 0)
	_settings_dialog.add_child(fields)
	var help := Label.new()
	help.text = "Values stay in per-user Godot editor settings. Environment variables override them."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(help)
	_settings_url = LineEdit.new()
	_settings_url.placeholder_text = "https://script.google.com/macros/s/.../exec"
	_add_form_row(fields, "Webhook URL", _settings_url)
	_settings_token = LineEdit.new()
	_settings_token.secret = true
	_settings_token.placeholder_text = "Shared token"
	_add_form_row(fields, "Shared token", _settings_token)
	add_child(_settings_dialog)


func _build_lighting_dialog() -> void:
	_lighting_dialog = AcceptDialog.new()
	_lighting_dialog.title = "Product Preview Lighting"
	_lighting_dialog.ok_button_text = "Apply"
	_lighting_dialog.confirmed.connect(_save_lighting_settings)
	_lighting_dialog.custom_action.connect(_on_lighting_dialog_action)
	var fields := VBoxContainer.new()
	fields.custom_minimum_size = Vector2(430, 0)
	_lighting_dialog.add_child(fields)
	var help := Label.new()
	help.text = "These values affect both the live product preview and the saved 1024×1024 PNG."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(help)
	_lighting_ambient = _create_lighting_spin()
	_add_form_row(fields, "Ambient", _lighting_ambient)
	_lighting_key = _create_lighting_spin()
	_add_form_row(fields, "Key light", _lighting_key)
	_lighting_fill = _create_lighting_spin()
	_add_form_row(fields, "Fill light", _lighting_fill)
	_lighting_rim = _create_lighting_spin()
	_add_form_row(fields, "Rim light", _lighting_rim)
	_lighting_dialog.add_button("Reset Defaults", true, "reset_defaults")
	add_child(_lighting_dialog)


func _create_lighting_spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 5.0
	spin.step = 0.05
	spin.allow_greater = false
	spin.allow_lesser = false
	return spin


func _add_form_row(parent: Control, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 118
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _load_journal() -> void:
	var state := _journal.load_state()
	_camera_profiles = state.get("camera_profiles", {}).duplicate(true)
	_lighting_profile = state.get("lighting", {}).duplicate(true)
	_studio.set_lighting(_lighting_profile)
	_lighting_profile = _studio.get_lighting()
	var migrated_sources := 0
	for row in state.get("drafts", []):
		if row is Dictionary:
			var draft := DearDearAssetDraft.from_dictionary(row)
			if not draft.record_id.is_empty():
				if _migrate_draft_source(draft):
					migrated_sources += 1
				_drafts.append(draft)
	if migrated_sources > 0:
		_queue_journal_save()


func _populate_categories() -> void:
	_category_option.clear()
	for entry in _config.categories():
		_category_option.add_item(str(entry.get("label", entry.get("key", ""))))
		_category_option.set_item_metadata(_category_option.item_count - 1, str(entry.get("key", "")))


func _populate_subcategories(category_key: String, selected_key := "") -> void:
	_subcategory_option.clear()
	for entry in _config.subcategories(category_key):
		_subcategory_option.add_item(str(entry.get("label", entry.get("key", ""))))
		_subcategory_option.set_item_metadata(_subcategory_option.item_count - 1, str(entry.get("key", "")))
		if str(entry.get("key", "")) == selected_key:
			_subcategory_option.select(_subcategory_option.item_count - 1)
	if _subcategory_option.selected < 0 and _subcategory_option.item_count > 0:
		_subcategory_option.select(0)


func _open_file_dialog() -> void:
	_file_dialog.current_dir = ProjectSettings.globalize_path(AssetSourceRepository.DEFAULT_ROOT)
	# Native Windows dialogs retain the previously opened filename. That makes
	# pressing Open after merely hovering another row submit the old GLB again.
	_file_dialog.current_file = ""
	_file_dialog.popup_centered_ratio(0.75)


func _open_source_folder() -> void:
	var absolute := ProjectSettings.globalize_path(AssetSourceRepository.DEFAULT_ROOT)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute)
	if directory_error not in [OK, ERR_ALREADY_EXISTS]:
		_set_status("Could not create the project source folder.", true)
		return
	var open_error := OS.shell_open(absolute)
	if open_error != OK:
		_set_status("Could not open the project source folder.", true)


func _open_replacement_source_dialog() -> void:
	if _busy or _current_index < 0:
		_set_status("Select a queued record first.", true)
		return
	_replace_source_dialog.current_dir = ProjectSettings.globalize_path(AssetSourceRepository.DEFAULT_ROOT)
	# Apply the same stale-native-filename guard as the multi-file picker.
	_replace_source_dialog.current_file = ""
	_replace_source_dialog.popup_centered_ratio(0.75)


func _on_replacement_file_selected(selected_path: String) -> void:
	if _busy or _current_index < 0:
		return
	var validation := _studio.validate_self_contained_glb(selected_path)
	if not validation.ok:
		_set_status(str(validation.error), true)
		return
	var draft := _drafts[_current_index]
	if draft.status in [
		DearDearAssetDraft.STATUS_CAPTURED,
		DearDearAssetDraft.STATUS_EXPORTED,
		DearDearAssetDraft.STATUS_SYNCED,
	] and not draft.overwrite_existing:
		_set_status("Enable the update confirmation before replacing a captured record's source.", true)
		return
	var preferred_path := draft.source_path if _source_repository.is_managed(draft.source_path) else ""
	var source_result := _source_repository.store(
		selected_path, draft.main_category, draft.sub_category, draft.gender, preferred_path, true)
	if not source_result.ok:
		_set_status(str(source_result.error), true)
		return
	_apply_source_to_draft(draft, str(source_result.path), str(source_result.sha256))
	if draft.status in [
		DearDearAssetDraft.STATUS_CAPTURED,
		DearDearAssetDraft.STATUS_EXPORTED,
		DearDearAssetDraft.STATUS_SYNCED,
	]:
		draft.status = DearDearAssetDraft.STATUS_RESERVED
	elif draft.status == DearDearAssetDraft.STATUS_ERROR:
		draft.status = DearDearAssetDraft.STATUS_RESERVED if not draft.item_id.is_empty() else DearDearAssetDraft.STATUS_DRAFT
	draft.refresh_derived(_config)
	_refresh_queue()
	_show_current_draft()
	_load_current_preview()
	_queue_journal_save()
	_set_status("Source copied into the project and linked to %s." % draft.source_path.get_file())


func _on_files_selected(paths: PackedStringArray) -> void:
	var existing_sources := {}
	for index in _drafts.size():
		existing_sources[_drafts[index].source_path] = index
	var added := 0
	var already_queued := 0
	var existing_preview_target_index := -1
	var new_preview_target_index := -1
	for selected_path in paths:
		var validation := _studio.validate_self_contained_glb(selected_path)
		if not validation.ok:
			_set_status("Skipped %s: %s" % [selected_path.get_file(), validation.error], true)
			continue
		var inferred := _config.infer_taxonomy(selected_path)
		var inferred_category := str(inferred.get("main_category", "furniture"))
		var inferred_subcategory := str(inferred.get("sub_category", ""))
		if inferred_subcategory.is_empty() and not _config.subcategories(inferred_category).is_empty():
			inferred_subcategory = str(_config.subcategories(inferred_category)[0].get("key", "general"))
		var inferred_gender := str(inferred.get("gender", "unisex"))
		var source_result := _source_repository.store(
			selected_path, inferred_category, inferred_subcategory, inferred_gender,
			_source_repository.canonical_path(selected_path) if _source_repository.is_managed(selected_path) else "")
		if not source_result.ok:
			_set_status("Skipped %s: %s" % [selected_path.get_file(), source_result.error], true)
			continue
		var path := str(source_result.path)
		if existing_sources.has(path):
			already_queued += 1
			if existing_preview_target_index < 0:
				existing_preview_target_index = int(existing_sources[path])
			continue
		var draft := DearDearAssetDraft.create(path)
		draft.source_sha256 = str(source_result.sha256)
		if inferred.has("main_category"):
			draft.main_category = str(inferred.main_category)
		if inferred.has("sub_category"):
			draft.sub_category = str(inferred.sub_category)
		elif not _config.subcategories(draft.main_category).is_empty():
			draft.sub_category = str(_config.subcategories(draft.main_category)[0].get("key", ""))
		if inferred.has("gender"):
			draft.gender = str(inferred.gender)
		draft.refresh_derived(_config)
		_drafts.append(draft)
		var new_index := _drafts.size() - 1
		existing_sources[path] = new_index
		if new_preview_target_index < 0:
			new_preview_target_index = new_index
		added += 1
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	# Native multi-select dialogs can occasionally return the stale previous file
	# together with the file the user just selected. Always show the newly added
	# draft in that case; fall back to reloading an existing draft only when no
	# new source was received.
	var preview_target_index: int = (
		new_preview_target_index if new_preview_target_index >= 0 else existing_preview_target_index)
	if preview_target_index >= 0:
		_select_index(preview_target_index)
	if added > 0 and already_queued > 0:
		_set_status("Added %d GLB file(s); selected %d existing queued file(s)." % [added, already_queued])
	elif added > 0:
		_set_status("Added %d GLB file(s)." % added)
	elif already_queued > 0 and preview_target_index >= 0:
		_set_status("This GLB was already queued. Selected and reloaded %s." % _drafts[preview_target_index].source_path.get_file())
	_queue_journal_save()


func _migrate_draft_source(draft: DearDearAssetDraft) -> bool:
	var original_path := draft.source_path
	if _source_repository.is_managed(original_path):
		var canonical := _source_repository.canonical_path(original_path)
		var canonical_absolute := ProjectSettings.globalize_path(canonical)
		if FileAccess.file_exists(canonical_absolute):
			_apply_source_to_draft(draft, canonical, FileAccess.get_sha256(canonical_absolute))
			return canonical != original_path
	if FileAccess.file_exists(ProjectSettings.globalize_path(original_path) if original_path.begins_with("res://") else original_path):
		var inferred := _config.infer_taxonomy(original_path)
		var result := _source_repository.store(
			original_path,
			str(inferred.get("main_category", draft.main_category)),
			str(inferred.get("sub_category", draft.sub_category)),
			str(inferred.get("gender", draft.gender)))
		if result.ok:
			_apply_source_to_draft(draft, str(result.path), str(result.sha256))
			return draft.source_path != original_path
	var matches := _source_repository.find_by_filename(original_path.get_file())
	if matches.size() == 1:
		var matched_path := str(matches[0])
		_apply_source_to_draft(draft, matched_path, FileAccess.get_sha256(ProjectSettings.globalize_path(matched_path)))
		return matched_path != original_path
	return false


func _apply_source_to_draft(draft: DearDearAssetDraft, source_path: String, source_hash: String) -> void:
	draft.source_path = source_path
	draft.source_sha256 = source_hash
	if draft.error_message.begins_with("Source GLB no longer exists"):
		draft.error_message = ""
	draft.updated_at_utc = DearDearAssetDraft.now_utc()


func _refresh_queue() -> void:
	var selection := _queue.get_selected_items()
	_queue.clear()
	for index in _drafts.size():
		var draft := _drafts[index]
		var id_text := draft.item_id if not draft.item_id.is_empty() else "unassigned"
		_queue.add_item("[%s] %s  •  %s" % [draft.status.capitalize(), draft.source_path.get_file(), id_text])
		_queue.set_item_tooltip(index, "%s\n%s\n%s" % [draft.source_path, draft.asset_name, draft.error_message])
		_queue.set_item_custom_fg_color(index, STATUS_COLORS.get(draft.status, Color.WHITE))
	for index in selection:
		if index < _queue.item_count:
			_queue.select(index, false)
	var count_label := _queue.get_parent().find_child("DraftCount", false, false) as Label
	if count_label:
		count_label.text = "%d queued" % _drafts.size()
	_update_action_state()


func _select_index(index: int) -> void:
	if index < 0 or index >= _drafts.size():
		_current_index = -1
		_clear_form()
		return
	_current_index = index
	_queue.select(index, false)
	_show_current_draft()
	_load_current_preview()


func _on_queue_item_selected(index: int) -> void:
	if _busy:
		return
	if index != _current_index:
		_select_index(index)


func _on_queue_multi_selected(index: int, selected: bool) -> void:
	if selected and not _busy:
		_on_queue_item_selected(index)


func _on_queue_item_clicked(index: int, _position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT and not _busy:
		_on_queue_item_selected(index)


func _show_current_draft() -> void:
	if _current_index < 0:
		return
	_updating_form = true
	for control in [_category_option, _subcategory_option, _gender_option, _buyable_check, _sellable_check,
		_include_id_check, _auto_id_check, _overwrite_check, _item_name_line, _item_id_line]:
		_set_form_control_enabled(control, true)
	var draft := _drafts[_current_index]
	_select_option_metadata(_category_option, draft.main_category)
	_populate_subcategories(draft.main_category, draft.sub_category)
	_select_option_metadata(_gender_option, draft.gender)
	_item_name_line.text = draft.item_name
	_item_id_line.text = draft.item_id
	_auto_id_check.button_pressed = draft.auto_id
	_item_id_line.editable = not draft.auto_id and draft.status in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]
	_buyable_check.button_pressed = draft.is_buyable
	_sellable_check.button_pressed = draft.is_sellable
	_include_id_check.button_pressed = draft.id_in_filename
	_include_id_check.disabled = not _config.can_omit_id(draft.main_category)
	_overwrite_check.button_pressed = draft.overwrite_existing
	_asset_name_line.text = "%s.glb" % draft.asset_name
	_sprite_name_line.text = draft.sprite_name
	_source_label.text = draft.source_path
	_source_label.tooltip_text = draft.source_path
	_gender_option.disabled = _config.gender_mode(draft.main_category) == "none"
	_record_status_label.text = "Status: %s%s" % [
		draft.status.capitalize(),
		" — %s" % draft.error_message if not draft.error_message.is_empty() else "",
	]
	_update_next_id_label(draft.main_category)
	_updating_form = false


func _clear_form() -> void:
	_updating_form = true
	for control in [_category_option, _subcategory_option, _gender_option, _buyable_check, _sellable_check,
		_include_id_check, _auto_id_check, _overwrite_check, _item_name_line, _item_id_line]:
		_set_form_control_enabled(control, false)
	_item_name_line.text = ""
	_item_id_line.text = ""
	_asset_name_line.text = ""
	_sprite_name_line.text = ""
	_source_label.text = "Select or add a GLB file."
	_record_status_label.text = "No active record."
	_updating_form = false
	_update_action_state()


func _load_current_preview() -> void:
	if _current_index < 0:
		_studio.clear_model()
		return
	var draft := _drafts[_current_index]
	var key := _config.profile_key(draft.main_category, draft.sub_category)
	_studio.set_camera_profile(_camera_profiles.get(key, {}))
	var result := _studio.load_glb(draft.source_path)
	if not result.ok:
		draft.status = DearDearAssetDraft.STATUS_ERROR
		draft.error_message = str(result.error)
		_set_status(draft.error_message, true)
		_refresh_queue()


func _on_camera_profile_changed(profile: Dictionary) -> void:
	if _current_index < 0:
		return
	var draft := _drafts[_current_index]
	_camera_profiles[_config.profile_key(draft.main_category, draft.sub_category)] = profile
	_queue_journal_save()


func _reset_camera() -> void:
	if _current_index < 0:
		return
	var draft := _drafts[_current_index]
	var key := _config.profile_key(draft.main_category, draft.sub_category)
	_camera_profiles.erase(key)
	_studio.reset_camera()
	_set_status("Reset camera profile for %s / %s." % [draft.main_category, draft.sub_category])


func _on_category_selected(_index: int) -> void:
	if _busy or _updating_form or _current_index < 0:
		return
	var draft := _drafts[_current_index]
	draft.main_category = str(_category_option.get_selected_metadata())
	_populate_subcategories(draft.main_category)
	draft.sub_category = str(_subcategory_option.get_selected_metadata())
	if _config.gender_mode(draft.main_category) == "none":
		draft.gender = "unisex"
	draft.id_in_filename = true
	draft.auto_id = true
	draft.status = DearDearAssetDraft.STATUS_DRAFT
	draft.error_message = ""
	_refresh_id_index_and_suggestions()
	_commit_form_to_draft()
	_show_current_draft()
	_load_current_preview()


func _on_subcategory_selected(_index: int) -> void:
	if _busy or _updating_form or _current_index < 0:
		return
	var draft := _drafts[_current_index]
	draft.sub_category = str(_subcategory_option.get_selected_metadata())
	draft.auto_id = true
	draft.status = DearDearAssetDraft.STATUS_DRAFT
	draft.error_message = ""
	_refresh_id_index_and_suggestions()
	_commit_form_to_draft()
	_load_current_preview()


func _on_form_changed(_value: Variant = null) -> void:
	if _busy or _updating_form:
		return
	_commit_form_to_draft()


func _on_text_form_changed(_value: String) -> void:
	_on_form_changed()


func _on_id_changed(value: String) -> void:
	if _busy or _updating_form or _current_index < 0:
		return
	if not _auto_id_check.button_pressed:
		var digits := ""
		for character in value:
			if character >= "0" and character <= "9":
				digits += character
		if digits != value:
			_updating_form = true
			_item_id_line.text = digits
			_item_id_line.caret_column = digits.length()
			_updating_form = false
	_commit_form_to_draft()
	_refresh_id_index_and_suggestions(false)


func _on_auto_id_toggled(enabled: bool) -> void:
	if _busy or _updating_form or _current_index < 0:
		return
	var draft := _drafts[_current_index]
	draft.auto_id = enabled
	draft.status = DearDearAssetDraft.STATUS_DRAFT
	_item_id_line.editable = not enabled
	_refresh_id_index_and_suggestions()
	_commit_form_to_draft()
	_show_current_draft()


func _commit_form_to_draft() -> void:
	if _updating_form or _current_index < 0:
		return
	var draft := _drafts[_current_index]
	draft.main_category = str(_category_option.get_selected_metadata())
	draft.sub_category = str(_subcategory_option.get_selected_metadata())
	draft.gender = str(_gender_option.get_selected_metadata())
	draft.item_name = _item_name_line.text
	draft.item_id = _item_id_line.text
	draft.is_buyable = _buyable_check.button_pressed
	draft.is_sellable = _sellable_check.button_pressed
	draft.id_in_filename = _include_id_check.button_pressed
	draft.overwrite_existing = _overwrite_check.button_pressed
	draft.refresh_derived(_config)
	_asset_name_line.text = "%s.glb" % draft.asset_name
	_sprite_name_line.text = draft.sprite_name
	_include_id_check.disabled = not _config.can_omit_id(draft.main_category)
	_gender_option.disabled = _config.gender_mode(draft.main_category) == "none"
	_refresh_queue()
	_queue_journal_save()


func _apply_metadata_to_selected() -> void:
	if _current_index < 0:
		return
	_commit_form_to_draft()
	var source := _drafts[_current_index]
	var changed := 0
	for index in _selected_indices():
		if index == _current_index:
			continue
		var draft := _drafts[index]
		if draft.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
			continue
		draft.main_category = source.main_category
		draft.sub_category = source.sub_category
		draft.gender = source.gender
		draft.is_buyable = source.is_buyable
		draft.is_sellable = source.is_sellable
		draft.id_in_filename = source.id_in_filename
		draft.auto_id = true
		draft.error_message = ""
		draft.status = DearDearAssetDraft.STATUS_DRAFT
		changed += 1
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	_show_current_draft()
	_queue_journal_save()
	_set_status("Applied shared metadata to %d record(s)." % changed)


func _remove_selected_drafts() -> void:
	var indices := _selected_indices()
	var removed := 0
	var removed_reserved := false
	for position in range(indices.size() - 1, -1, -1):
		var index := indices[position]
		if _drafts[index].status not in [
			DearDearAssetDraft.STATUS_DRAFT,
			DearDearAssetDraft.STATUS_ERROR,
			DearDearAssetDraft.STATUS_RESERVED,
		]:
			_set_status("Captured, exported, or synced records cannot be removed from the queue.", true)
			continue
		removed_reserved = removed_reserved or _drafts[index].status == DearDearAssetDraft.STATUS_RESERVED
		_drafts.remove_at(index)
		removed += 1
	_current_index = mini(_current_index, _drafts.size() - 1)
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	if _current_index >= 0:
		_select_index(_current_index)
	else:
		_clear_form()
	_queue_journal_save()
	if removed > 0:
		var suffix := " Any remotely reserved IDs remain permanently reserved." if removed_reserved else ""
		_set_status("Removed %d queued record(s).%s" % [removed, suffix])


func _refresh_id_index_and_suggestions(refresh_form := true) -> void:
	var fixed_drafts: Array = []
	for draft in _drafts:
		if not draft.auto_id or draft.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
			fixed_drafts.append(draft)
	_id_index.rebuild(_catalog.items, fixed_drafts)
	for item_id in _remote_ids:
		_id_index.add_usage(item_id, "remote")
	for draft in _drafts:
		if draft.auto_id and draft.status in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
			var suggestion := _id_index.next_available(_config.id_range(draft.main_category))
			draft.item_id = "%06d" % suggestion if suggestion >= 0 else ""
			draft.refresh_derived(_config)
			if suggestion >= 0:
				_id_index.add_usage(draft.item_id, "suggestion:%s" % draft.record_id)
	_update_audit()
	if refresh_form and _current_index >= 0:
		_show_current_draft()


func _update_next_id_label(category_key: String) -> void:
	var index_without_suggestions := DearDearAssetIdIndex.new()
	var fixed: Array = []
	for draft in _drafts:
		if not draft.auto_id or draft.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
			fixed.append(draft)
	index_without_suggestions.rebuild(_catalog.items, fixed)
	for item_id in _remote_ids:
		index_without_suggestions.add_usage(item_id, "remote")
	var range_value := _config.id_range(category_key)
	var next_value := index_without_suggestions.next_available(range_value)
	var last_text := str(index_without_suggestions.last_used(range_value)) if next_value > range_value.x else "None"
	var next_text := "%06d" % next_value if next_value >= 0 else "Range exhausted"
	_next_id_label.text = "Last: %s   Next available: %s" % [last_text, next_text]


func _update_audit() -> void:
	var duplicates := _id_index.duplicates()
	if duplicates.is_empty():
		_audit_label.text = "Local ID audit: no model collisions"
		_audit_label.tooltip_text = ""
		return
	var ids := PackedStringArray()
	for item_id in duplicates:
		ids.append(str(item_id))
	ids.sort()
	_audit_label.text = "Local ID audit: %d collision(s)" % ids.size()
	var details := PackedStringArray()
	for item_id in ids:
		details.append("%s: %s" % [item_id, ", ".join(duplicates[item_id])])
	_audit_label.tooltip_text = "\n".join(details)


func _refresh_all_ids() -> void:
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	await _refresh_remote_snapshot()
	_set_status("Refreshed local and remote ID state.")


func _refresh_remote_snapshot() -> void:
	if not _sheets or not _sheets.is_configured() or _busy:
		_update_connection_status()
		return
	var result: Dictionary = await _sheets.call_action("snapshot")
	if result.ok:
		_remote_ids = PackedStringArray(result.get("data", {}).get("used_ids", []))
		_refresh_id_index_and_suggestions()
		_update_connection_status(true)
	else:
		_update_connection_status(false, _response_error(result))


func _capture_selected() -> void:
	if _busy:
		return
	_commit_form_to_draft()
	var indices := _selected_indices()
	if indices.is_empty():
		_set_status("Select one or more queued files.", true)
		return
	_busy = true
	_update_action_state()
	var completed_all := true
	for index in indices:
		var draft := _drafts[index]
		_set_status("Preparing %s…" % draft.source_path.get_file())
		var result: Dictionary = await _capture_draft(draft)
		if not result.ok:
			draft.status = DearDearAssetDraft.STATUS_ERROR if draft.status == DearDearAssetDraft.STATUS_DRAFT else draft.status
			draft.error_message = str(result.error)
			_set_status("%s: %s" % [draft.source_path.get_file(), draft.error_message], true)
			completed_all = false
			break
		draft.status = DearDearAssetDraft.STATUS_CAPTURED
		draft.error_message = ""
		draft.updated_at_utc = DearDearAssetDraft.now_utc()
		_queue_journal_save()
		_refresh_queue()
	_busy = false
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	_show_current_draft()
	_load_current_preview()
	_update_action_state()
	if completed_all:
		_set_status("Capture complete. Next: Export CSV / JSON, then Sync Google Sheets.")


func _capture_draft(draft: DearDearAssetDraft) -> Dictionary:
	var validation_errors := draft.validate(_config)
	if not validation_errors.is_empty():
		return {"ok": false, "error": " ".join(validation_errors)}
	var current_source_hash := FileAccess.get_sha256(
		ProjectSettings.globalize_path(draft.source_path) if draft.source_path.begins_with("res://") else draft.source_path)
	if current_source_hash != draft.source_sha256:
		if draft.status in [
			DearDearAssetDraft.STATUS_CAPTURED,
			DearDearAssetDraft.STATUS_EXPORTED,
			DearDearAssetDraft.STATUS_SYNCED,
		] and not draft.overwrite_existing:
			return {"ok": false, "error": "The project-local source changed. Enable the update confirmation before recapturing it."}
		draft.source_sha256 = current_source_hash
		draft.updated_at_utc = DearDearAssetDraft.now_utc()
	# Check manual IDs before calling reserve so a known local collision does not
	# consume a permanent remote reservation and the user sees its exact owner.
	if not draft.auto_id and draft.status in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
		var manual_collisions := _local_id_collision_sources(draft)
		if not manual_collisions.is_empty():
			return {"ok": false, "error": _format_id_collision(draft.item_id, manual_collisions)}
	if draft.status in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
		var reserve_result: Dictionary = await _reserve_id(draft)
		if not reserve_result.ok:
			return reserve_result
	var collision_sources := _local_id_collision_sources(draft)
	if not collision_sources.is_empty():
		return {"ok": false, "error": _format_id_collision(draft.item_id, collision_sources)}
	draft.refresh_derived(_config)
	var ownership := _validate_output_ownership(draft)
	if not ownership.ok:
		return ownership
	var preview_result := _studio.load_glb(draft.source_path)
	if not preview_result.ok:
		return preview_result
	var profile_key := _config.profile_key(draft.main_category, draft.sub_category)
	_studio.set_camera_profile(_camera_profiles.get(profile_key, {}))
	var staged_model := "%s.dear_tmp.glb" % draft.model_path.trim_suffix(".glb")
	var staged_image := "%s.dear_tmp.png" % draft.market_image_path.trim_suffix(".png")
	var stage_model_result := _stage_source_copy(draft.source_path, staged_model)
	if not stage_model_result.ok:
		return stage_model_result
	var capture_result: Dictionary = await _studio.capture_png(staged_image)
	if not capture_result.ok:
		_remove_file_if_present(staged_model)
		return capture_result
	var model_commit := _commit_staged_file(staged_model, draft.model_path)
	if not model_commit.ok:
		_remove_file_if_present(staged_image)
		return model_commit
	var image_commit := _commit_staged_file(staged_image, draft.market_image_path)
	if not image_commit.ok:
		_rollback_file_commit(model_commit)
		return image_commit
	_finish_file_commit(model_commit)
	_finish_file_commit(image_commit)
	return {"ok": true}


func _local_id_collision_sources(draft: DearDearAssetDraft) -> Array:
	var local_collision_index := DearDearAssetIdIndex.new()
	var other_fixed: Array = []
	for other in _drafts:
		if other.record_id != draft.record_id and (not other.auto_id or other.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]):
			other_fixed.append(other)
	local_collision_index.rebuild(_catalog.items, other_fixed)
	var ignored_sources := {
		"catalog:%s" % draft.record_id: true,
		"draft:%s" % draft.record_id: true,
	}
	for row in _catalog.items:
		if str(row.get("record_id", "")) == draft.record_id:
			var catalog_model_path := str(row.get("model_path", ""))
			if not catalog_model_path.is_empty():
				ignored_sources[catalog_model_path] = true
			break
	var current_output_owned := draft.status in [
		DearDearAssetDraft.STATUS_CAPTURED,
		DearDearAssetDraft.STATUS_EXPORTED,
		DearDearAssetDraft.STATUS_SYNCED,
	]
	if not current_output_owned and draft.status in [DearDearAssetDraft.STATUS_RESERVED, DearDearAssetDraft.STATUS_ERROR]:
		current_output_owned = (
			FileAccess.file_exists(draft.model_path)
			and FileAccess.get_sha256(draft.model_path) == draft.source_sha256)
	if current_output_owned and not draft.model_path.is_empty():
		ignored_sources[draft.model_path] = true
	var collisions: Array = []
	for source in local_collision_index.sources_for(draft.item_id):
		if not ignored_sources.has(str(source)):
			collisions.append(source)
	return collisions


func _format_id_collision(item_id: String, sources: Array) -> String:
	var owners := PackedStringArray()
	for source_value in sources:
		var source := str(source_value)
		if source.begins_with("catalog:"):
			owners.append("catalog record %s" % source.trim_prefix("catalog:"))
		elif source.begins_with("draft:"):
			owners.append("queued draft %s" % source.trim_prefix("draft:"))
		else:
			owners.append(source)
	return "ID %s is already used by: %s" % [item_id, "; ".join(owners)]


func _reserve_id(draft: DearDearAssetDraft) -> Dictionary:
	if not _sheets.is_configured():
		return {"ok": false, "error": "Configure and connect the Sheets webhook before final asset capture."}
	var blocked_index := DearDearAssetIdIndex.new()
	var fixed: Array = []
	for other in _drafts:
		if other.record_id != draft.record_id and (not other.auto_id or other.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]):
			fixed.append(other)
	blocked_index.rebuild(_catalog.items, fixed)
	var blocked_ids := Array(blocked_index.used_ids())
	# An idempotent retry may see its own catalog/output entry in the local scan.
	# Do not send that one as a server-side block when no foreign owner exists.
	if not draft.item_id.is_empty() and _local_id_collision_sources(draft).is_empty():
		blocked_ids.erase(draft.item_id)
	var result: Dictionary = await _sheets.call_action("reserve", {
		"record_id": draft.record_id,
		"category_key": draft.main_category,
		"requested_id": "" if draft.auto_id else draft.item_id,
		"blocked_ids": blocked_ids,
	})
	if not result.ok:
		return {"ok": false, "error": _response_error(result)}
	var assigned_id := str(result.get("data", {}).get("item_id", ""))
	if not _config.is_id_allowed(draft.main_category, assigned_id):
		return {"ok": false, "error": "Server returned an invalid ID for this category: %s" % assigned_id}
	draft.item_id = assigned_id
	draft.status = DearDearAssetDraft.STATUS_RESERVED
	draft.error_message = ""
	draft.refresh_derived(_config)
	_remote_ids.append(assigned_id)
	_queue_journal_save()
	return {"ok": true}


func _validate_output_ownership(draft: DearDearAssetDraft) -> Dictionary:
	var catalog_row: Dictionary = {}
	for row in _catalog.items:
		if str(row.get("record_id", "")) == draft.record_id:
			catalog_row = row
			break
	var recoverable_output_pair := (
		draft.status in [DearDearAssetDraft.STATUS_RESERVED, DearDearAssetDraft.STATUS_ERROR]
		and FileAccess.file_exists(draft.model_path)
		and FileAccess.file_exists(draft.market_image_path)
		and FileAccess.get_sha256(draft.model_path) == draft.source_sha256)
	for output_path in [draft.model_path, draft.market_image_path]:
		if not FileAccess.file_exists(output_path):
			continue
		var catalog_owns_path: bool = not catalog_row.is_empty() and output_path in [
			str(catalog_row.get("model_path", "")), str(catalog_row.get("market_image_path", ""))]
		var captured_draft_owns_path := draft.status in [
			DearDearAssetDraft.STATUS_CAPTURED,
			DearDearAssetDraft.STATUS_EXPORTED,
			DearDearAssetDraft.STATUS_SYNCED,
		]
		if not catalog_owns_path and not captured_draft_owns_path and not recoverable_output_pair:
			return {"ok": false, "error": "Output already exists and is not owned by this record: %s" % output_path}
		if not draft.overwrite_existing:
			return {"ok": false, "error": "Enable the update confirmation before replacing %s" % output_path}
	return {"ok": true}


func _stage_source_copy(source_path: String, staged_path: String) -> Dictionary:
	var source_absolute := ProjectSettings.globalize_path(source_path) if source_path.begins_with("res://") else source_path
	var destination_absolute := ProjectSettings.globalize_path(staged_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(destination_absolute.get_base_dir())
	if directory_error not in [OK, ERR_ALREADY_EXISTS]:
		return {"ok": false, "error": "Could not create destination folder."}
	_remove_file_if_present(staged_path)
	var bytes := FileAccess.get_file_as_bytes(source_absolute)
	if bytes.is_empty():
		return {"ok": false, "error": "Source GLB could not be read."}
	var file := FileAccess.open(destination_absolute, FileAccess.WRITE)
	if not file:
		return {"ok": false, "error": "Could not stage the GLB copy."}
	file.store_buffer(bytes)
	file.close()
	return {"ok": true}


func _commit_staged_file(staged_path: String, final_path: String) -> Dictionary:
	var staged_absolute := ProjectSettings.globalize_path(staged_path)
	var final_absolute := ProjectSettings.globalize_path(final_path)
	var backup_absolute := "%s.dear_backup" % final_absolute
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)
	if FileAccess.file_exists(final_absolute):
		var backup_error := DirAccess.rename_absolute(final_absolute, backup_absolute)
		if backup_error != OK:
			return {"ok": false, "error": "Could not prepare update for %s" % final_path}
	var install_error := DirAccess.rename_absolute(staged_absolute, final_absolute)
	if install_error != OK:
		if FileAccess.file_exists(backup_absolute):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		return {"ok": false, "error": "Could not install %s" % final_path}
	return {"ok": true, "final": final_absolute, "backup": backup_absolute}


func _rollback_file_commit(result: Dictionary) -> void:
	if not result.get("ok", false):
		return
	var final_path := str(result.get("final", ""))
	var backup_path := str(result.get("backup", ""))
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(backup_path, final_path)


func _finish_file_commit(result: Dictionary) -> void:
	var backup_path := str(result.get("backup", ""))
	if not backup_path.is_empty() and FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)


func _remove_file_if_present(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)


func _temporary_capture() -> void:
	if _busy:
		return
	if _current_index < 0:
		_set_status("Select a model first.", true)
		return
	_commit_form_to_draft()
	var draft := _drafts[_current_index]
	_busy = true
	_update_action_state()
	var preview_result := _studio.load_glb(draft.source_path)
	if not preview_result.ok:
		_busy = false
		_update_action_state()
		_set_status(str(preview_result.error), true)
		return
	var path := "user://asset_importer_test_%s.png" % draft.record_id
	var result: Dictionary = await _studio.capture_png(path)
	_busy = false
	_update_action_state()
	if result.ok:
		_set_status("Temporary capture saved to %s" % ProjectSettings.globalize_path(path))
	else:
		_set_status(str(result.error), true)


func _export_selected() -> void:
	if _busy:
		return
	var selected: Array = []
	for index in _selected_indices():
		var draft := _drafts[index]
		if draft.status not in [DearDearAssetDraft.STATUS_CAPTURED, DearDearAssetDraft.STATUS_EXPORTED, DearDearAssetDraft.STATUS_SYNCED]:
			_show_error("Capture every selected record before exporting.")
			return
		selected.append(draft)
	var result := _catalog.upsert_drafts(selected)
	if not result.ok:
		_show_error(str(result.error))
		return
	for draft in selected:
		if draft.status != DearDearAssetDraft.STATUS_SYNCED:
			draft.status = DearDearAssetDraft.STATUS_EXPORTED
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	_show_current_draft()
	_queue_journal_save()
	EditorInterface.get_resource_filesystem().update_file(DearDearAssetCatalogRepository.CATALOG_PATH)
	_set_status("Exported %d record(s) to JSON and CSV. Next: Sync Google Sheets." % selected.size())


func _sync_selected() -> void:
	if _busy:
		return
	if not _sheets.is_configured():
		_show_error("Configure the Sheets webhook URL and token first.")
		return
	var rows: Array = []
	var selected_drafts: Array[DearDearAssetDraft] = []
	for index in _selected_indices():
		var draft := _drafts[index]
		if draft.status not in [DearDearAssetDraft.STATUS_EXPORTED, DearDearAssetDraft.STATUS_SYNCED]:
			_show_error("Export every selected record to JSON / CSV before syncing.")
			return
		rows.append(draft.catalog_dictionary())
		selected_drafts.append(draft)
	if rows.is_empty():
		_show_error("Select at least one captured record.")
		return
	_busy = true
	_update_action_state()
	_set_status("Syncing %d record(s) to Google Sheets…" % rows.size())
	var result: Dictionary = await _sheets.call_action("upsert", {"rows": rows})
	_busy = false
	if not result.ok:
		_set_status(_response_error(result), true)
		_update_action_state()
		return
	for draft in selected_drafts:
		draft.status = DearDearAssetDraft.STATUS_SYNCED
		draft.error_message = ""
	_refresh_queue()
	_show_current_draft()
	_queue_journal_save()
	_update_action_state()
	_set_status("Synced %d record(s) to Google Sheets." % rows.size())


func _selected_indices() -> PackedInt32Array:
	var selected := _queue.get_selected_items()
	if selected.is_empty() and _current_index >= 0:
		selected.append(_current_index)
	return selected


func _select_option_metadata(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
	if option.item_count > 0:
		option.select(0)


func _set_form_control_enabled(control: Control, enabled: bool) -> void:
	if control is LineEdit:
		control.editable = enabled
	elif control is BaseButton:
		control.disabled = not enabled


func _update_action_state() -> void:
	if not _capture_button:
		return
	var has_drafts := not _drafts.is_empty()
	_capture_button.disabled = _busy or not has_drafts
	_export_button.disabled = _busy or not has_drafts
	_sync_button.disabled = _busy or not has_drafts


func _open_settings() -> void:
	_settings_url.text = _sheets.webhook_url() if _sheets else ""
	_settings_token.text = _sheets.shared_token() if _sheets else ""
	_settings_dialog.popup_centered()


func _open_lighting_settings() -> void:
	var lighting := _studio.get_lighting()
	_lighting_ambient.value = float(lighting.ambient_energy)
	_lighting_key.value = float(lighting.key_energy)
	_lighting_fill.value = float(lighting.fill_energy)
	_lighting_rim.value = float(lighting.rim_energy)
	_lighting_dialog.popup_centered()


func _save_lighting_settings() -> void:
	_lighting_profile = {
		"ambient_energy": _lighting_ambient.value,
		"key_energy": _lighting_key.value,
		"fill_energy": _lighting_fill.value,
		"rim_energy": _lighting_rim.value,
	}
	_studio.set_lighting(_lighting_profile)
	_lighting_profile = _studio.get_lighting()
	_queue_journal_save()
	_set_status("Studio lighting applied to preview and capture.")


func _on_lighting_dialog_action(action: StringName) -> void:
	if action != &"reset_defaults":
		return
	_studio.reset_lighting()
	_lighting_profile = _studio.get_lighting()
	_lighting_ambient.value = float(_lighting_profile.ambient_energy)
	_lighting_key.value = float(_lighting_profile.key_energy)
	_lighting_fill.value = float(_lighting_profile.fill_energy)
	_lighting_rim.value = float(_lighting_profile.rim_energy)
	_queue_journal_save()
	_set_status("Studio lighting reset to defaults.")


func _save_settings() -> void:
	_sheets.save_settings(_settings_url.text, _settings_token.text)
	_update_connection_status()
	call_deferred("_refresh_remote_snapshot")


func _update_connection_status(connected := false, detail := "") -> void:
	if not _sheets or not _sheets.is_configured():
		_connection_label.text = "Sheets: not configured"
		_connection_label.tooltip_text = "Final ID-based writes are disabled until the webhook is configured."
	elif connected:
		_connection_label.text = "Sheets: connected"
		_connection_label.tooltip_text = "Remote ID snapshot loaded."
	else:
		_connection_label.text = "Sheets: configured"
		_connection_label.tooltip_text = detail


func _response_error(result: Dictionary) -> String:
	var error_value: Variant = result.get("error", "Unknown Sheets error.")
	if error_value is Dictionary:
		return str(error_value.get("message", error_value.get("code", "Unknown Sheets error.")))
	return str(error_value)


func _set_status(message: String, is_error := false) -> void:
	_global_status.text = message
	_global_status.modulate = Color(1.0, 0.52, 0.52) if is_error else Color.WHITE


func _show_error(message: String) -> void:
	_set_status(message, true)
	_error_dialog.dialog_text = message
	_error_dialog.popup_centered()


func _queue_journal_save() -> void:
	if _journal_save_queued or not is_inside_tree():
		return
	_journal_save_queued = true
	get_tree().create_timer(0.25).timeout.connect(_flush_journal)


func _flush_journal() -> void:
	_journal_save_queued = false
	_journal.save_state(_drafts, _camera_profiles, _lighting_profile)
