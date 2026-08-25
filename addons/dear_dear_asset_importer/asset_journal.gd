@tool
class_name DearDearAssetJournal
extends RefCounted

const JOURNAL_PATH := "res://.godot/dear_dear_asset_importer/state.json"

var journal_path := JOURNAL_PATH


func load_state() -> Dictionary:
	if not FileAccess.file_exists(journal_path):
		return {"drafts": [], "camera_profiles": {}}
	var file := FileAccess.open(journal_path, FileAccess.READ)
	if not file:
		return {"drafts": [], "camera_profiles": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {"drafts": [], "camera_profiles": {}}


func save_state(drafts: Array, camera_profiles: Dictionary) -> bool:
	var absolute := ProjectSettings.globalize_path(journal_path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) not in [OK, ERR_ALREADY_EXISTS]:
		return false
	var rows: Array = []
	for draft in drafts:
		if draft is DearDearAssetDraft:
			rows.append(draft.to_dictionary())
	var file := FileAccess.open(journal_path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify({"drafts": rows, "camera_profiles": camera_profiles}, "\t"))
	return true
