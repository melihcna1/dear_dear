@tool
class_name DearDearAssetToolConfig
extends RefCounted

const CONFIG_PATH := "res://data/asset_import_categories.json"

var data: Dictionary = {}
var error_message := ""


func load_from_disk() -> bool:
	error_message = ""
	if not FileAccess.file_exists(CONFIG_PATH):
		error_message = "Missing category configuration: %s" % CONFIG_PATH
		return false
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		error_message = "Could not open category configuration."
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not parsed.has("categories"):
		error_message = "Category configuration is not valid JSON."
		return false
	data = parsed
	return true


func categories() -> Array:
	return data.get("categories", [])


func category(category_key: String) -> Dictionary:
	for entry in categories():
		if entry is Dictionary and str(entry.get("key", "")) == category_key:
			return entry
	return {}


func subcategories(category_key: String) -> Array:
	return category(category_key).get("subcategories", [])


func subcategory(category_key: String, subcategory_key: String) -> Dictionary:
	for entry in subcategories(category_key):
		if entry is Dictionary and str(entry.get("key", "")) == subcategory_key:
			return entry
	return {}


func id_range(category_key: String) -> Vector2i:
	var entry := category(category_key)
	return Vector2i(int(entry.get("id_start", 0)), int(entry.get("id_end", -1)))


func is_id_allowed(category_key: String, item_id: String) -> bool:
	if not item_id.is_valid_int() or item_id.length() != 6:
		return false
	var value := int(item_id)
	var range_value := id_range(category_key)
	return value >= range_value.x and value <= range_value.y and not is_reserved(value)


func is_reserved(value: int) -> bool:
	for value_range in data.get("reserved_ranges", []):
		if value_range is Array and value_range.size() == 2:
			if value >= int(value_range[0]) and value <= int(value_range[1]):
				return true
	return false


func destination_path(category_key: String, subcategory_key: String, gender: String) -> String:
	var template := str(category(category_key).get("destination", "res://assets/dev_model/imported"))
	return template.replace("{gender}", gender).replace("{sub_category}", subcategory_key)


func market_image_path(category_key: String, subcategory_key: String) -> String:
	var root := str(data.get("market_image_root", "res://assets/market")).trim_suffix("/")
	return "%s/%s/%s" % [root, category_key, subcategory_key]


func gender_mode(category_key: String) -> String:
	return str(category(category_key).get("gender_mode", "none"))


func can_omit_id(category_key: String) -> bool:
	return bool(category(category_key).get("can_omit_id", false))


func profile_key(category_key: String, subcategory_key: String) -> String:
	return "%s/%s" % [category_key, subcategory_key]


func infer_taxonomy(source_path: String) -> Dictionary:
	var normalized := source_path.replace("\\", "/").to_lower()
	var filename_slug := DearDearAssetNaming.slugify(normalized.get_file().get_basename())
	var path_slugs := PackedStringArray()
	for segment in normalized.get_base_dir().split("/", false):
		path_slugs.append(DearDearAssetNaming.slugify(segment))
	var result := {}
	for category_entry in categories():
		if not category_entry is Dictionary:
			continue
		var category_key := str(category_entry.get("key", ""))
		var aliases := PackedStringArray([
			DearDearAssetNaming.slugify(category_key),
			DearDearAssetNaming.slugify(str(category_entry.get("prefix", ""))),
			DearDearAssetNaming.slugify(str(category_entry.get("label", ""))),
		])
		if category_key == "cloth":
			aliases.append("clothes")
		if _has_taxonomy_alias(path_slugs, filename_slug, aliases):
			result.main_category = category_key
			break
	if result.is_empty():
		return result
	var category_key := str(result.main_category)
	for subcategory_entry in subcategories(category_key):
		if not subcategory_entry is Dictionary:
			continue
		var subcategory_key := str(subcategory_entry.get("key", ""))
		var aliases := PackedStringArray([
			DearDearAssetNaming.slugify(subcategory_key),
			DearDearAssetNaming.slugify(str(subcategory_entry.get("prefix", ""))),
			DearDearAssetNaming.slugify(str(subcategory_entry.get("label", ""))),
		])
		if _has_taxonomy_alias(path_slugs, filename_slug, aliases):
			result.sub_category = subcategory_key
			break
	if gender_mode(category_key) != "none":
		if "female" in path_slugs or filename_slug.begins_with("f_"):
			result.gender = "female"
		elif "male" in path_slugs or filename_slug.begins_with("m_"):
			result.gender = "male"
		elif "unisex" in path_slugs or filename_slug.begins_with("u_"):
			result.gender = "unisex"
	return result


func _has_taxonomy_alias(path_slugs: PackedStringArray, filename_slug: String, aliases: PackedStringArray) -> bool:
	var filename_tokens := Array(filename_slug.split("_", false))
	for alias in aliases:
		if alias.is_empty():
			continue
		if alias in path_slugs or alias in filename_tokens:
			return true
	return false
