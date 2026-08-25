class_name ItemCatalog
extends Node

const ITEMS_PATH := "res://data/items.json"
const SELL_PRICES_PATH := "res://data/sell_prices.json"
const DEV_ASSET_ROOT := "res://assets/dev_model"
const ORIGINAL_STARTER_IDS := [
	"winged_sheep", "turntable", "street_lamp", "portal", "frame",
	"ocak", "lambacik", "basic_pot_ver2", "basic_pot", "candle_ver2",
]
const AVATAR_STARTER_IDS := [
	"f_cloth_fullbody_310013", "f_cloth_top_310044",
	"f_cloth_bottom_310157", "f_cloth_hair_310180",
	"m_cloth_fullbody_310148", "m_cloth_top_310000",
	"m_cloth_bottom_310009", "m_cloth_hair_310188",
]
const RENTAL_PRICING := [
	{"duration_days": 1, "currency_type": WalletModel.SOFT, "price": 100},
	{"duration_days": 7, "currency_type": WalletModel.SOFT, "price": 500},
	{"duration_days": 30, "currency_type": WalletModel.HARD, "price": 50},
	{"duration_days": 365, "currency_type": WalletModel.HARD, "price": 300},
]
const FURNITURE_PRICES := {
	"decor": 100,
	"electronics": 300,
	"garden": 150,
	"seating": 200,
}

var definitions: Dictionary = {}
var sell_prices: Dictionary = {}


func _ready() -> void:
	build_default_catalog()


func build_default_catalog() -> void:
	definitions.clear()
	_load_sell_prices()
	var rows := _read_json_array(ITEMS_PATH)
	if rows.is_empty():
		_register_fallback_catalog()
	else:
		for row in rows:
			if row is Dictionary:
				_register_from_row(row)
	_mark_original_starters()
	_register_dev_asset_catalog()
	_configure_anchovy()


func get_definition(definition_id: String) -> PlaceableItemDefinition:
	return definitions.get(definition_id)


func all_definitions() -> Array:
	return definitions.values()


func buyable_definitions() -> Array:
	var result: Array = []
	for definition in all_definitions():
		if definition.is_buyable:
			result.append(definition)
	return result


func is_avatar_definition_compatible(definition: PlaceableItemDefinition, gender: String) -> bool:
	if not definition or definition.avatar_slot.is_empty():
		return false
	return definition.gender.is_empty() or definition.gender == AvatarProfile.normalized_gender(gender)


func get_sell_price(definition_id: String) -> int:
	return int(sell_prices.get(definition_id, 0))


func create_instance(definition_id: String, metadata: Dictionary = {}, duration_days := 0, user_id := "") -> ItemInstance:
	var definition := get_definition(definition_id)
	var combined := definition.default_metadata.duplicate(true) if definition else {}
	combined.merge(metadata, true)
	var item := ItemInstance.new(definition_id, combined)
	if definition:
		item.item_type = definition.item_type
		item.duration_days = duration_days if definition.item_type == "RENTAL" else 0
	item.user_id = user_id
	return item


func _register_from_row(row: Dictionary) -> void:
	var definition := PlaceableItemDefinition.new()
	definition.definition_id = str(row.get("id", ""))
	if definition.definition_id.is_empty():
		return
	definition.item_name = str(row.get("item_name", definition.definition_id))
	definition.description = str(row.get("description", ""))
	definition.category = str(row.get("category", "Utilities"))
	definition.sub_category = str(row.get("sub_category", ""))
	definition.buy_price = int(row.get("buy_price", 0))
	definition.duration_type = str(row.get("duration_type", ""))
	definition.duration_value = int(row.get("duration_value", 0))
	definition.item_type = str(row.get("item_type", "STANDARD"))
	definition.avatar_slot = str(row.get("avatar_slot", ""))
	definition.gender = str(row.get("gender", ""))
	definition.pricing_options = row.get("pricing_options", []).duplicate(true)
	definition.swatch_path = str(row.get("swatch_path", ""))
	definition.is_starter = bool(row.get("is_starter", false))
	definition.is_buyable = bool(row.get("is_buyable", false))
	definition.is_sellable = bool(row.get("is_sellable", false))
	definition.is_placeable = bool(row.get("is_placeable", true))
	definition.is_cooking_station = bool(row.get("is_cooking_station", false))
	definition.max_stack_size = int(row.get("max_stack_size", 1))
	definition.sell_price = get_sell_price(definition.definition_id)
	definition.model_path = str(row.get("model_path", ""))
	definition.default_metadata = {"source": "items_json"}
	definitions[definition.definition_id] = definition


func _mark_original_starters() -> void:
	for id in ORIGINAL_STARTER_IDS:
		var definition := get_definition(id)
		if definition:
			definition.is_starter = true


func _register_dev_asset_catalog() -> void:
	for gender in AvatarProfile.VALID_GENDERS:
		for slot in ["top", "bottom", "fullbody", "hair"]:
			_register_wearable_directory(gender, slot)
	_register_color_directory("hair", "hair_color", 100)
	_register_color_directory("skin", "skin_tone", 150)
	_register_furniture_directory()


func _register_wearable_directory(gender: String, slot: String) -> void:
	var directory: String = "%s/clothes/%s/%s" % [DEV_ASSET_ROOT, gender, slot]
	var files := Array(DirAccess.get_files_at(directory))
	files.sort()
	for file_value in files:
		var file_name := str(file_value)
		if file_name.get_extension().to_lower() != "glb":
			continue
		var base_name: String = file_name.get_basename().trim_suffix("_Rig")
		var item_id: String = base_name.to_lower()
		var parts: PackedStringArray = item_id.split("_")
		var numeric_id: String = parts[parts.size() - 1]
		var definition := PlaceableItemDefinition.new()
		definition.definition_id = item_id
		var gender_name := AvatarProfile.display_gender(gender)
		definition.item_name = "%s %s %s" % [gender_name, _display_slot(slot), numeric_id]
		definition.description = "%s %s style %s." % [gender_name, _display_slot(slot).to_lower(), numeric_id]
		definition.category = "Cloth"
		definition.sub_category = _display_slot(slot)
		definition.item_type = "RENTAL"
		definition.avatar_slot = slot
		definition.gender = gender
		definition.pricing_options = RENTAL_PRICING.duplicate(true)
		definition.buy_price = 100
		definition.is_starter = item_id in AVATAR_STARTER_IDS
		definition.is_buyable = not definition.is_starter
		definition.is_sellable = false
		definition.is_placeable = false
		definition.max_stack_size = 1
		definition.model_path = "%s/%s" % [directory, file_name]
		definition.preview_camera_padding = 1.15
		definition.default_metadata = {"source": "dev_model", "gender": gender}
		definitions[item_id] = definition


func _register_color_directory(folder: String, slot: String, price: int) -> void:
	var directory: String = "%s/colors/%s" % [DEV_ASSET_ROOT, folder]
	var files := Array(DirAccess.get_files_at(directory))
	files.sort()
	for file_value in files:
		var file_name := str(file_value)
		if file_name.get_extension().to_lower() != "png":
			continue
		var base_name: String = file_name.get_basename().to_lower()
		var item_id: String = "%s_%s" % [slot, base_name.trim_prefix("skin_color_") if slot == "skin_tone" else base_name]
		var definition := PlaceableItemDefinition.new()
		definition.definition_id = item_id
		definition.item_name = _display_color_name(slot, base_name)
		definition.description = "A single-use avatar color consumable."
		definition.category = "Cloth"
		definition.sub_category = "Hair Color" if slot == "hair_color" else "Skin Tone"
		definition.item_type = "CONSUMABLE"
		definition.avatar_slot = slot
		# Permanent colors are shared by both avatar rigs.
		definition.gender = ""
		definition.pricing_options = [{"duration_days": 0, "currency_type": WalletModel.SOFT, "price": price}]
		definition.buy_price = price
		definition.is_buyable = true
		definition.is_sellable = false
		definition.is_placeable = false
		definition.max_stack_size = 99
		definition.swatch_path = "%s/%s" % [directory, file_name]
		definition.default_metadata = {"source": "dev_model", "gender": "unisex"}
		definitions[item_id] = definition


func _register_furniture_directory() -> void:
	var directory: String = "%s/furniture" % DEV_ASSET_ROOT
	var files := Array(DirAccess.get_files_at(directory))
	files.sort()
	for file_value in files:
		var file_name := str(file_value)
		if file_name.get_extension().to_lower() != "glb":
			continue
		var item_id: String = file_name.get_basename().to_lower()
		var parts: PackedStringArray = item_id.split("_")
		if parts.size() < 3:
			continue
		var subcategory := str(parts[1])
		var numeric_id := str(parts[2])
		var definition := PlaceableItemDefinition.new()
		definition.definition_id = item_id
		definition.item_name = "Furniture %s %s" % [subcategory.capitalize(), numeric_id]
		definition.description = "Dev Model %s furniture style %s." % [subcategory, numeric_id]
		definition.category = "Furniture"
		definition.sub_category = subcategory.capitalize()
		definition.item_type = "STANDARD"
		definition.buy_price = int(FURNITURE_PRICES.get(subcategory, 100))
		definition.is_buyable = true
		definition.is_sellable = false
		definition.is_placeable = true
		definition.max_stack_size = 1
		definition.model_path = "%s/%s" % [directory, file_name]
		definition.default_metadata = {"source": "dev_model"}
		definitions[item_id] = definition


func _configure_anchovy() -> void:
	var definition := get_definition("river_fish")
	if not definition:
		return
	definition.item_name = "Anchovy"
	definition.description = "A small silver anchovy caught in the pond."
	definition.model_path = "%s/fish/hamsi.glb" % DEV_ASSET_ROOT
	definition.model_scene = null
	definition.preview_camera_padding = 1.15


func _display_slot(slot: String) -> String:
	return "Full Body" if slot == "fullbody" else slot.capitalize()


func _display_color_name(slot: String, base_name: String) -> String:
	if slot == "skin_tone":
		return "Skin Tone %s" % base_name.trim_prefix("skin_color_")
	return "Hair Color %s" % base_name.replace("_", " ").capitalize()


func _load_sell_prices() -> void:
	sell_prices.clear()
	for row in _read_json_array(SELL_PRICES_PATH):
		if row is Dictionary:
			sell_prices[str(row.get("id", ""))] = int(row.get("sell_price", 0))


func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _register_fallback_catalog() -> void:
	_register("winged_sheep", "Winged Sheep", "A curious winged sheep.", "Furniture", "Creature", "res://assets/models/winged_sheep.fbx", 1, 420)
	_register("turntable", "Turntable", "A rotating display platform.", "Furniture", "Display", "res://assets/models/turntable.fbx", 1, 180)
	_register("street_lamp", "Street Lamp", "A tall outdoor lamp.", "Furniture", "Lighting", "res://assets/models/street_lamp.fbx", 1, 125)
	_register("portal", "Portal", "A mysterious architectural portal.", "Furniture", "Architecture", "res://assets/models/portal.fbx", 1, 360)
	_register("frame", "Frame", "A decorative frame.", "Furniture", "Decor", "res://assets/models/frame.fbx", 1, 70)
	_register("ocak", "Ocak", "A traditional hearth.", "Furniture", "Hearth", "res://assets/models/ocak.fbx", 1, 210)
	_register("lambacik", "Lambacik", "A small decorative light.", "Furniture", "Lighting", "res://assets/models/lambacik.fbx", 1, 95)
	_register("basic_pot_ver2", "Basic Pot Ver. 2", "A stackable ceramic pot.", "Furniture", "Decor", "res://assets/models/basic_pot_ver2.fbx", 4, 35)
	_register("basic_pot", "Basic Pot", "A stackable ceramic pot.", "Furniture", "Decor", "res://assets/models/basic_pot.fbx", 4, 30)
	_register("candle_ver2", "Candle", "A small stackable candle.", "Furniture", "Lighting", "res://assets/models/candle_ver2.fbx", 8, 15)
	var stove: PlaceableItemDefinition = definitions.get("ocak")
	if stove:
		stove.is_cooking_station = true


func _register(
		id: String,
		display_name: String,
		description: String,
		category: String,
		sub_category: String,
		scene_path: String,
		max_stack: int,
		buy_price: int) -> void:
	var definition := PlaceableItemDefinition.new()
	definition.definition_id = id
	definition.item_name = display_name
	definition.description = description
	definition.category = category
	definition.sub_category = sub_category
	definition.buy_price = buy_price
	definition.is_buyable = true
	definition.is_sellable = false
	definition.is_placeable = true
	definition.max_stack_size = max_stack
	definition.model_path = scene_path
	definition.is_starter = true
	definition.default_metadata = {"source": "starter_catalog"}
	definitions[id] = definition
