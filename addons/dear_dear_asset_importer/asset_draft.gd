@tool
class_name DearDearAssetDraft
extends RefCounted

const STATUS_DRAFT := "draft"
const STATUS_RESERVED := "reserved"
const STATUS_CAPTURED := "captured"
const STATUS_EXPORTED := "exported"
const STATUS_SYNCED := "synced"
const STATUS_ERROR := "error"

var record_id := ""
var source_path := ""
var source_sha256 := ""
var item_id := ""
var item_name := ""
var asset_name := ""
var sprite_name := ""
var main_category := "furniture"
var sub_category := "decor"
var gender := "unisex"
var is_buyable := true
var is_sellable := false
var id_in_filename := true
var model_path := ""
var market_image_path := ""
var created_at_utc := ""
var updated_at_utc := ""
var status := STATUS_DRAFT
var error_message := ""
var auto_id := true
var overwrite_existing := false


static func create(source_file: String) -> DearDearAssetDraft:
	var draft := DearDearAssetDraft.new()
	draft.record_id = _uuid()
	draft.source_path = source_file
	draft.source_sha256 = FileAccess.get_sha256(source_file) if FileAccess.file_exists(source_file) else ""
	draft.item_name = DearDearAssetNaming.inferred_item_name(source_file)
	draft.created_at_utc = now_utc()
	draft.updated_at_utc = draft.created_at_utc
	return draft


func refresh_derived(config: DearDearAssetToolConfig) -> void:
	if not config.can_omit_id(main_category):
		id_in_filename = true
	asset_name = DearDearAssetNaming.asset_name(
		config, main_category, sub_category, gender, item_name, item_id, id_in_filename)
	sprite_name = DearDearAssetNaming.sprite_name(asset_name)
	var destination := config.destination_path(main_category, sub_category, gender)
	model_path = "%s/%s.glb" % [destination.trim_suffix("/"), asset_name]
	var image_destination := config.market_image_path(main_category, sub_category)
	market_image_path = "%s/%s.png" % [image_destination.trim_suffix("/"), sprite_name]
	updated_at_utc = now_utc()


func validate(config: DearDearAssetToolConfig) -> PackedStringArray:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(source_path):
		errors.append("Source GLB no longer exists.")
	if source_path.get_extension().to_lower() != "glb":
		errors.append("Only .glb files are supported.")
	if config.category(main_category).is_empty():
		errors.append("Choose a valid main category.")
	if config.subcategory(main_category, sub_category).is_empty():
		errors.append("Choose a valid subcategory.")
	if DearDearAssetNaming.slugify(item_name).is_empty():
		errors.append("Item name must contain letters or numbers.")
	if config.gender_mode(main_category) == "required" and not gender in ["female", "male", "unisex"]:
		errors.append("Choose Female, Male, or Unisex.")
	if not item_id.is_empty() and not config.is_id_allowed(main_category, item_id):
		errors.append("ID must be six digits in the active category range.")
	return errors


func to_dictionary() -> Dictionary:
	return {
		"record_id": record_id,
		"source_path": source_path,
		"source_sha256": source_sha256,
		"item_id": item_id,
		"item_name": item_name,
		"asset_name": asset_name,
		"sprite_name": sprite_name,
		"main_category": main_category,
		"sub_category": sub_category,
		"gender": gender,
		"is_buyable": is_buyable,
		"is_sellable": is_sellable,
		"id_in_filename": id_in_filename,
		"model_path": model_path,
		"market_image_path": market_image_path,
		"created_at_utc": created_at_utc,
		"updated_at_utc": updated_at_utc,
		"status": status,
		"error_message": error_message,
		"auto_id": auto_id,
		"overwrite_existing": overwrite_existing,
	}


func catalog_dictionary() -> Dictionary:
	var result := to_dictionary()
	result.erase("source_path")
	result.erase("status")
	result.erase("error_message")
	result.erase("auto_id")
	result.erase("overwrite_existing")
	return result


static func from_dictionary(row: Dictionary) -> DearDearAssetDraft:
	var draft := DearDearAssetDraft.new()
	for property_name in [
		"record_id", "source_path", "source_sha256", "item_id", "item_name", "asset_name",
		"sprite_name", "main_category", "sub_category", "gender", "model_path",
		"market_image_path", "created_at_utc", "updated_at_utc", "status", "error_message",
	]:
		if row.has(property_name):
			draft.set(property_name, str(row[property_name]))
	draft.is_buyable = bool(row.get("is_buyable", true))
	draft.is_sellable = bool(row.get("is_sellable", false))
	draft.id_in_filename = bool(row.get("id_in_filename", true))
	draft.auto_id = bool(row.get("auto_id", true))
	draft.overwrite_existing = bool(row.get("overwrite_existing", false))
	return draft


static func now_utc() -> String:
	return Time.get_datetime_string_from_system(true, false)


static func _uuid() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12),
	]
