@tool
class_name DearDearAssetImporterMain
extends Control

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
var _sheets: DearDearSheetsClient
var _studio: DearDearPreviewStudio
var _drafts: Array[DearDearAssetDraft] = []
var _camera_profiles: Dictionary = {}
var _remote_ids := PackedStringArray()
var _current_index := -1
var _updating_form := false
var _busy := false
var _journal_save_queued := false

var _file_dialog: FileDialog
var _error_dialog: AcceptDialog
var _settings_dialog: AcceptDialog
var _settings_url: LineEdit
var _settings_token: LineEdit
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
	if _current_index >= 0:
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
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.glb", "Binary glTF Models")
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Asset Importer"
	add_child(_error_dialog)
	_build_settings_dialog()


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
	_queue.item_selected.connect(_on_queue_item_selected)
	box.add_child(_queue)
	var queue_actions := HBoxContainer.new()
	box.add_child(queue_actions)
	var add_button := Button.new()
	add_button.text = "Add GLB Files…"
	add_button.pressed.connect(_open_file_dialog)
	queue_actions.add_child(add_button)
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
	for row in state.get("drafts", []):
		if row is Dictionary:
			var draft := DearDearAssetDraft.from_dictionary(row)
			if not draft.record_id.is_empty():
				_drafts.append(draft)


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
	_file_dialog.popup_centered_ratio(0.75)


func _on_files_selected(paths: PackedStringArray) -> void:
	var existing_sources := {}
	for draft in _drafts:
		existing_sources[draft.source_path] = true
	var added := 0
	for path in paths:
		if existing_sources.has(path):
			continue
		var validation := _studio.validate_self_contained_glb(path)
		if not validation.ok:
			_set_status("Skipped %s: %s" % [path.get_file(), validation.error], true)
			continue
		var draft := DearDearAssetDraft.create(path)
		if _current_index >= 0:
			var source := _drafts[_current_index]
			draft.main_category = source.main_category
			draft.sub_category = source.sub_category
			draft.gender = source.gender
			draft.is_buyable = source.is_buyable
			draft.is_sellable = source.is_sellable
			draft.id_in_filename = source.id_in_filename
		draft.refresh_derived(_config)
		_drafts.append(draft)
		added += 1
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	if added > 0:
		_select_index(_drafts.size() - added)
		_set_status("Added %d GLB file(s)." % added)
	_queue_journal_save()


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
	_select_index(index)


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
	if _updating_form or _current_index < 0:
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
	if _updating_form or _current_index < 0:
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
	if _updating_form:
		return
	_commit_form_to_draft()


func _on_text_form_changed(_value: String) -> void:
	_on_form_changed()


func _on_id_changed(value: String) -> void:
	if _updating_form or _current_index < 0:
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
	if _updating_form or _current_index < 0:
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
	for position in range(indices.size() - 1, -1, -1):
		var index := indices[position]
		if _drafts[index].status != DearDearAssetDraft.STATUS_DRAFT:
			_set_status("Only unreserved Draft records can be removed.", true)
			continue
		_drafts.remove_at(index)
	_current_index = mini(_current_index, _drafts.size() - 1)
	_refresh_id_index_and_suggestions()
	_refresh_queue()
	if _current_index >= 0:
		_select_index(_current_index)
	else:
		_clear_form()
	_queue_journal_save()


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
	EditorInterface.get_resource_filesystem().scan()
	if completed_all:
		_set_status("Capture complete. Next: Export CSV / JSON, then Sync Google Sheets.")


func _capture_draft(draft: DearDearAssetDraft) -> Dictionary:
	var validation_errors := draft.validate(_config)
	if not validation_errors.is_empty():
		return {"ok": false, "error": " ".join(validation_errors)}
	if draft.status in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]:
		var reserve_result: Dictionary = await _reserve_id(draft)
		if not reserve_result.ok:
			return reserve_result
	var local_collision_index := DearDearAssetIdIndex.new()
	var other_fixed: Array = []
	for other in _drafts:
		if other.record_id != draft.record_id and (not other.auto_id or other.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]):
			other_fixed.append(other)
	local_collision_index.rebuild(_catalog.items, other_fixed)
	if local_collision_index.is_used(draft.item_id):
		return {"ok": false, "error": "ID %s already exists in a local model, catalog record, or reserved draft." % draft.item_id}
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


func _reserve_id(draft: DearDearAssetDraft) -> Dictionary:
	if not _sheets.is_configured():
		return {"ok": false, "error": "Configure and connect the Sheets webhook before final asset capture."}
	var blocked_index := DearDearAssetIdIndex.new()
	var fixed: Array = []
	for other in _drafts:
		if other.record_id != draft.record_id and (not other.auto_id or other.status not in [DearDearAssetDraft.STATUS_DRAFT, DearDearAssetDraft.STATUS_ERROR]):
			fixed.append(other)
	blocked_index.rebuild(_catalog.items, fixed)
	var result: Dictionary = await _sheets.call_action("reserve", {
		"record_id": draft.record_id,
		"category_key": draft.main_category,
		"requested_id": "" if draft.auto_id else draft.item_id,
		"blocked_ids": Array(blocked_index.used_ids()),
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
	if _current_index < 0:
		_set_status("Select a model first.", true)
		return
	var draft := _drafts[_current_index]
	var preview_result := _studio.load_glb(draft.source_path)
	if not preview_result.ok:
		_set_status(str(preview_result.error), true)
		return
	var path := "user://asset_importer_test_%s.png" % draft.record_id
	var result: Dictionary = await _studio.capture_png(path)
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
	_journal.save_state(_drafts, _camera_profiles)
