@tool
class_name DearDearAssetNaming
extends RefCounted

const GENDER_CODES := {
	"female": "f",
	"male": "m",
	"unisex": "u",
}


static func slugify(value: String) -> String:
	var result := value.strip_edges().trim_suffix("_Rig").trim_suffix("_rig").to_lower()
	var replacements := {
		"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u",
		"á": "a", "à": "a", "ä": "a", "â": "a", "é": "e", "è": "e",
		"ë": "e", "ê": "e", "í": "i", "ì": "i", "ï": "i", "ó": "o",
		"ò": "o", "ô": "o", "ú": "u", "ù": "u", "û": "u", "ñ": "n",
	}
	for source in replacements:
		result = result.replace(source, replacements[source])
	var invalid := RegEx.new()
	invalid.compile("[^a-z0-9]+")
	result = invalid.sub(result, "_", true)
	while result.begins_with("_"):
		result = result.trim_prefix("_")
	while result.ends_with("_"):
		result = result.trim_suffix("_")
	return result


static func inferred_item_name(source_path: String) -> String:
	var base_name := source_path.get_file().get_basename().trim_suffix("_Rig").trim_suffix("_rig")
	var trailing_id := RegEx.new()
	trailing_id.compile("_\\d{6}$")
	base_name = trailing_id.sub(base_name, "")
	return base_name.replace("_", " ").capitalize()


static func asset_name(
		config: DearDearAssetToolConfig,
		category_key: String,
		subcategory_key: String,
		gender: String,
		item_name: String,
		item_id: String,
		include_id: bool) -> String:
	var category := config.category(category_key)
	var subcategory := config.subcategory(category_key, subcategory_key)
	var parts: Array[String] = []
	if category_key == "cloth":
		parts.append(str(GENDER_CODES.get(gender, "u")))
	parts.append(slugify(str(category.get("prefix", category_key))))
	parts.append(slugify(str(subcategory.get("prefix", subcategory_key))))
	parts.append(slugify(item_name))
	if include_id and not item_id.is_empty():
		parts.append(item_id)
	var clean_parts: Array[String] = []
	for part in parts:
		if not part.is_empty():
			clean_parts.append(part)
	return "_".join(clean_parts)


static func sprite_name(asset_base_name: String) -> String:
	return "%s_s" % asset_base_name


static func csv_escape(value: Variant) -> String:
	var text := str(value)
	if text.contains(",") or text.contains("\"") or text.contains("\n") or text.contains("\r"):
		return "\"%s\"" % text.replace("\"", "\"\"")
	return text
