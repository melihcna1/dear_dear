class_name GardeningCatalog
extends Node

const GARDENING_PATH := "res://data/gardening.json"

var definitions_by_seed: Dictionary = {}


func _ready() -> void:
	build_default_catalog()


func build_default_catalog() -> void:
	definitions_by_seed.clear()
	for row in _read_json_array(GARDENING_PATH):
		if not (row is Dictionary):
			continue
		var definition := GardeningDefinition.from_row(row)
		if not definition.seed_item_id.is_empty():
			definitions_by_seed[definition.seed_item_id] = definition


func get_by_seed(seed_item_id: String) -> GardeningDefinition:
	return definitions_by_seed.get(seed_item_id)


func is_seed(seed_item_id: String) -> bool:
	return definitions_by_seed.has(seed_item_id)


func _read_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []
