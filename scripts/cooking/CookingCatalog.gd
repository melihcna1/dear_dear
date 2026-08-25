class_name CookingCatalog
extends Node

const DATA_PATH := "res://data/cooking.json"

var definitions: Array[CookingDefinition] = []
var definitions_by_id: Dictionary = {}


func setup(item_catalog: ItemCatalog) -> void:
	definitions.clear()
	definitions_by_id.clear()
	for row in _read_json_array(DATA_PATH):
		if not (row is Dictionary):
			continue
		var definition := CookingDefinition.from_row(row)
		if not _is_valid(definition, item_catalog):
			continue
		if definitions_by_id.has(definition.recipe_id):
			continue
		definitions.append(definition)
		definitions_by_id[definition.recipe_id] = definition


func all_definitions() -> Array[CookingDefinition]:
	return definitions.duplicate()


func get_definition(recipe_id: String) -> CookingDefinition:
	return definitions_by_id.get(recipe_id)


func _is_valid(definition: CookingDefinition, item_catalog: ItemCatalog) -> bool:
	if (
		definition.recipe_id.is_empty()
		or definition.crafted_item_id.is_empty()
		or definition.ingredients.is_empty()
		or definition.cooking_time_sec <= 0
		or not item_catalog
		or not item_catalog.get_definition(definition.crafted_item_id)
	):
		return false
	for ingredient_id in definition.ingredients.keys():
		if int(definition.ingredients[ingredient_id]) <= 0 or not item_catalog.get_definition(str(ingredient_id)):
			return false
	return true


func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []
