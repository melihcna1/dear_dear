class_name CookingDefinition
extends Resource

var recipe_id := ""
var crafted_item_id := ""
var crafted_item_name := ""
var ingredients: Dictionary = {}
var cooking_time_sec := 0


static func from_row(row: Dictionary) -> CookingDefinition:
	var definition := CookingDefinition.new()
	definition.recipe_id = str(row.get("recipe_id", "")).strip_edges()
	definition.crafted_item_id = str(row.get("crafted_item_id", "")).strip_edges()
	definition.crafted_item_name = str(row.get("crafted_item_name", "")).strip_edges()
	definition.cooking_time_sec = maxi(int(row.get("cooking_time_sec", 0)), 0)
	var raw_ingredients: Variant = row.get("ingredients", {})
	if raw_ingredients is Dictionary:
		for raw_id in raw_ingredients.keys():
			var ingredient_id := str(raw_id).strip_edges()
			var quantity := int(raw_ingredients[raw_id])
			if not ingredient_id.is_empty() and quantity > 0:
				definition.ingredients[ingredient_id] = quantity
	return definition
