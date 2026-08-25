@tool
class_name DearDearAssetCatalogRepository
extends RefCounted

const CATALOG_PATH := "res://data/asset_catalog.json"
const CSV_PATH := "res://data/asset_exports/asset_catalog.csv"
const COLUMNS := [
	"record_id", "item_id", "item_name", "asset_name", "sprite_name", "main_category",
	"sub_category", "gender", "is_buyable", "is_sellable", "id_in_filename", "model_path",
	"market_image_path", "source_sha256", "created_at_utc", "updated_at_utc",
]

var items: Array = []
var catalog_path := CATALOG_PATH
var csv_path := CSV_PATH


func load_catalog() -> Dictionary:
	items = []
	if not FileAccess.file_exists(catalog_path):
		return {"ok": true, "items": items}
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	if not file:
		return {"ok": false, "error": "Could not open %s" % catalog_path}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("items", []) is Array):
		return {"ok": false, "error": "Asset catalog must contain an items array."}
	items = parsed.get("items", []).duplicate(true)
	return {"ok": true, "items": items}


func upsert_drafts(drafts: Array) -> Dictionary:
	var candidate := items.duplicate(true)
	for draft_value in drafts:
		if not draft_value is DearDearAssetDraft:
			continue
		var row: Dictionary = draft_value.catalog_dictionary()
		var replace_index := -1
		for index in candidate.size():
			var existing: Dictionary = candidate[index]
			if str(existing.get("record_id", "")) == draft_value.record_id:
				replace_index = index
				continue
			if str(existing.get("item_id", "")) == draft_value.item_id:
				return {"ok": false, "error": "ID %s already belongs to another catalog record." % draft_value.item_id}
			if str(existing.get("asset_name", "")) == draft_value.asset_name:
				return {"ok": false, "error": "Asset name %s already belongs to another catalog record." % draft_value.asset_name}
		if replace_index >= 0:
			candidate[replace_index] = row
		else:
			candidate.append(row)
	candidate.sort_custom(_sort_rows)
	var json_result := _atomic_write(catalog_path, JSON.stringify({"schema_version": 1, "items": candidate}, "\t") + "\n")
	if not json_result.ok:
		return json_result
	var csv_result := _atomic_write(csv_path, _csv(candidate))
	if not csv_result.ok:
		return csv_result
	items = candidate
	return {"ok": true, "count": drafts.size()}


func regenerate_exports() -> Dictionary:
	items.sort_custom(_sort_rows)
	var json_result := _atomic_write(catalog_path, JSON.stringify({"schema_version": 1, "items": items}, "\t") + "\n")
	if not json_result.ok:
		return json_result
	return _atomic_write(csv_path, _csv(items))


func _csv(rows: Array) -> String:
	var lines := PackedStringArray([",".join(COLUMNS)])
	for row in rows:
		var cells := PackedStringArray()
		for column in COLUMNS:
			var value: Variant = row.get(column, "")
			if value is bool:
				value = "true" if value else "false"
			cells.append(DearDearAssetNaming.csv_escape(value))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


func _atomic_write(path: String, content: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "Could not create %s" % directory}
	var temporary := "%s.tmp" % absolute
	var backup := "%s.bak" % absolute
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return {"ok": false, "error": "Could not write temporary export %s" % temporary}
	file.store_string(content)
	file.close()
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if FileAccess.file_exists(absolute):
		var backup_error := DirAccess.rename_absolute(absolute, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "error": "Could not prepare atomic replacement for %s" % path}
	var replace_error := DirAccess.rename_absolute(temporary, absolute)
	if replace_error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		return {"ok": false, "error": "Could not replace %s" % path}
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	return {"ok": true}


static func _sort_rows(left: Dictionary, right: Dictionary) -> bool:
	var left_id := int(left.get("item_id", 0))
	var right_id := int(right.get("item_id", 0))
	if left_id == right_id:
		return str(left.get("asset_name", "")) < str(right.get("asset_name", ""))
	return left_id < right_id
