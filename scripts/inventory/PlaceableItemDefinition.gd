class_name PlaceableItemDefinition
extends Resource

@export var definition_id := ""
@export var item_name := ""
@export_multiline var description := ""
@export var category := "Decor"
@export var sub_category := ""
@export var buy_price := 0
@export var sell_price := 0
@export var duration_type := ""
@export var duration_value := 0
@export var item_type := "STANDARD"
@export var avatar_slot := ""
@export var gender := ""
@export var pricing_options: Array = []
@export var swatch_path := ""
@export var is_starter := false
@export var is_buyable := false
@export var is_sellable := false
@export var is_placeable := true
@export var is_cooking_station := false
@export var model_scene: PackedScene
@export var model_path := ""
@export var max_stack_size := 1
@export var placement_scale := Vector3.ONE
@export var rotation_step_degrees := 15.0
@export var grid_size := 0.5
@export var preview_rotation_speed := 0.45
@export var preview_camera_padding := 1.35
@export var default_metadata: Dictionary = {}


func create_model() -> Node3D:
	if not model_scene and not model_path.is_empty():
		model_scene = ResourceLoader.load(model_path) as PackedScene
	if not model_scene:
		return Node3D.new()
	var model := model_scene.instantiate()
	if model is Node3D:
		return model
	var wrapper := Node3D.new()
	wrapper.add_child(model)
	return wrapper


func price_for_duration(duration_days: int) -> Dictionary:
	for option in pricing_options:
		if option is Dictionary and int(option.get("duration_days", 0)) == duration_days:
			return option.duplicate(true)
	return {}


func tooltip_text(metadata: Dictionary = {}) -> String:
	var stack_text := "No limit" if max_stack_size <= 0 else str(max_stack_size)
	var price_text := "Buy: %d | Sell: %d" % [buy_price, sell_price]
	var placement := "Grid: %.2f | Rotate: %.0f deg | Scale: %s" % [
		grid_size,
		rotation_step_degrees,
		str(placement_scale),
	]
	var custom := metadata if not metadata.is_empty() else default_metadata
	return "%s\n%s\nCategory: %s\n%s\n%s\nMax stack: %s\nMetadata: %s" % [
		item_name,
		description,
		category,
		price_text,
		placement,
		stack_text,
		JSON.stringify(custom),
	]
