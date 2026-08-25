class_name FishingCatalog
extends Node

const DATA_PATH := "res://data/fishing.json"
const VALID_PROFILES := ["smooth", "top_biased", "bottom_biased", "mixed", "darting", "chaotic"]

var definitions: Array[FishingDefinition] = []
var total_weight := 0.0


func setup(item_catalog: ItemCatalog) -> void:
	definitions.clear()
	total_weight = 0.0
	for row in _read_json_array(DATA_PATH):
		if not (row is Dictionary):
			continue
		var definition := FishingDefinition.from_row(row)
		var item_definition := item_catalog.get_definition(definition.item_id) if item_catalog else null
		if (
			definition.item_id.is_empty()
			or definition.weight <= 0.0
			or not item_definition
			or item_definition.category != "Fish"
			or not item_definition.is_sellable
		):
			continue
		if not definition.movement_profile in VALID_PROFILES:
			definition.movement_profile = "smooth"
		definitions.append(definition)
		total_weight += definition.weight


func all_definitions() -> Array[FishingDefinition]:
	return definitions.duplicate()


func get_definition(item_id: String) -> FishingDefinition:
	for definition in definitions:
		if definition.item_id == item_id:
			return definition
	return null


func choose_fish(rng: RandomNumberGenerator) -> FishingDefinition:
	if definitions.is_empty() or total_weight <= 0.0:
		return null
	var random := rng
	if random == null:
		random = RandomNumberGenerator.new()
		random.randomize()
	var roll := random.randf_range(0.0, total_weight)
	var cumulative := 0.0
	for definition in definitions:
		cumulative += definition.weight
		if roll <= cumulative:
			return definition
	return definitions.back()


func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []
