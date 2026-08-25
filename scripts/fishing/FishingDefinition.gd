class_name FishingDefinition
extends Resource

var item_id := ""
var weight := 0.0
var difficulty := 1.0
var movement_profile := "smooth"


static func from_row(row: Dictionary) -> FishingDefinition:
	var definition := FishingDefinition.new()
	definition.item_id = str(row.get("item_id", ""))
	definition.weight = maxf(float(row.get("weight", 0.0)), 0.0)
	definition.difficulty = clampf(float(row.get("difficulty", 1.0)), 1.0, 5.0)
	definition.movement_profile = str(row.get("movement_profile", "smooth")).strip_edges().to_lower()
	return definition
