class_name GardeningDefinition
extends RefCounted

var id := 0
var seed_item_id := ""
var crop_item_id := ""
var initial_growth_minutes := 0
var regrowth_minutes := 0
var regrowth_model_name := ""
var wither_minutes := 0
var withered_model_name := ""


static func from_row(row: Dictionary) -> GardeningDefinition:
	var definition := GardeningDefinition.new()
	definition.id = int(row.get("id", 0))
	definition.seed_item_id = str(row.get("item_name", ""))
	definition.crop_item_id = definition._crop_id_from_seed(definition.seed_item_id)
	definition.initial_growth_minutes = int(row.get("initial_growth_time", 0))
	definition.regrowth_minutes = int(row.get("regrowth_time", 0))
	definition.regrowth_model_name = str(row.get("regrowth_model_name", ""))
	definition.wither_minutes = int(row.get("wither_time_min", 0))
	definition.withered_model_name = str(row.get("withered_model_name", ""))
	return definition


func _crop_id_from_seed(seed_id: String) -> String:
	return seed_id.substr(0, seed_id.length() - 5) if seed_id.ends_with("_seed") else seed_id
