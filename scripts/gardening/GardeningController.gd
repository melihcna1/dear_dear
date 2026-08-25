class_name GardeningController
extends Node

signal changed
signal status_changed(message: String)

const GARDENING_KEY := "gardening"
const POT_IDS := ["basic_pot", "basic_pot_ver2"]
const DEFAULT_MAX_ACTIVE_POTS := 8
const REFRESH_INTERVAL := 1.0

const STAGE_SEED := "seed"
const STAGE_SAPLING := "sapling"
const STAGE_GROWING := "plant_growing"
const STAGE_READY := "harvest_ready"
const STAGE_WITHERED := "withered"

var placement: PlacementController
var inventory: InventoryModel
var item_catalog: ItemCatalog
var gardening_catalog: GardeningCatalog
var selected_seed_slot := -1
var selected_seed_instance_id := ""
var max_active_pots := DEFAULT_MAX_ACTIVE_POTS
var _refresh_elapsed := 0.0


func setup(
		p_placement: PlacementController,
		p_inventory: InventoryModel,
		p_item_catalog: ItemCatalog,
		p_gardening_catalog: GardeningCatalog) -> void:
	placement = p_placement
	inventory = p_inventory
	item_catalog = p_item_catalog
	gardening_catalog = p_gardening_catalog


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	_refresh_elapsed = 0.0
	if refresh_all():
		changed.emit()


func begin_seed_selection(slot_index: int) -> bool:
	var stack := inventory.get_slot_stack(slot_index) if inventory else []
	if stack.is_empty():
		return false
	var seed: ItemInstance = stack.back()
	if not gardening_catalog or not gardening_catalog.is_seed(seed.definition_id):
		return false
	selected_seed_slot = slot_index
	selected_seed_instance_id = seed.instance_id
	status_changed.emit("Select an empty pot")
	return true


func cancel_seed_selection() -> void:
	selected_seed_slot = -1
	selected_seed_instance_id = ""


func handle_placed_item_clicked(item: PlacementItem) -> bool:
	if not item:
		return false
	refresh_item(item)
	if has_pending_seed():
		return _try_plant_selected_seed(item)
	if not is_pot(item) or not is_planted(item):
		return false
	if Input.is_key_pressed(KEY_SHIFT):
		remove_plant(item)
		status_changed.emit("Plant removed")
		return true
	var gardening := _gardening_state(item)
	match str(gardening.get("stage", "")):
		STAGE_SAPLING:
			convert_sapling_to_plant(item)
			return true
		STAGE_READY:
			harvest(item)
			return true
		STAGE_WITHERED:
			clear_withered(item)
			return true
	return false


func has_pending_seed() -> bool:
	return selected_seed_slot >= 0 and not selected_seed_instance_id.is_empty()


func is_pot(item: PlacementItem) -> bool:
	return item != null and item.definition_id in POT_IDS


func is_planted(item: PlacementItem) -> bool:
	return _gardening_state(item).size() > 0


func refresh_all() -> bool:
	if not placement:
		return false
	var any_changed := false
	for item in placement.get_placed_items():
		if item is PlacementItem:
			any_changed = refresh_item(item) or any_changed
	return any_changed


func refresh_item(item: PlacementItem) -> bool:
	if not is_pot(item):
		return false
	var gardening := _gardening_state(item)
	if gardening.is_empty():
		_clear_visual(item)
		return false
	var now := _now()
	var previous_stage := str(gardening.get("stage", ""))
	var next_at := int(gardening.get("next_at", 0))
	var wither_at := int(gardening.get("wither_at", 0))
	if previous_stage == STAGE_SEED and next_at > 0 and now >= next_at:
		gardening["stage"] = STAGE_SAPLING
		gardening.erase("next_at")
	elif previous_stage == STAGE_GROWING and next_at > 0 and now >= next_at:
		var definition := _definition_for_state(gardening)
		if not definition:
			return false
		gardening["stage"] = STAGE_READY
		gardening["ready_at"] = next_at
		gardening["wither_at"] = next_at + definition.wither_minutes * 60
		gardening.erase("next_at")
	elif previous_stage == STAGE_READY and wither_at > 0 and now >= wither_at:
		gardening["stage"] = STAGE_WITHERED
	item.item_metadata[GARDENING_KEY] = gardening
	_apply_visual(item)
	return previous_stage != str(gardening.get("stage", ""))


func convert_sapling_to_plant(item: PlacementItem) -> void:
	var gardening := _gardening_state(item)
	var definition := _definition_for_state(gardening)
	if not definition:
		return
	var now := _now()
	gardening["stage"] = STAGE_GROWING
	gardening["cycle_started_at"] = now
	gardening["next_at"] = now + definition.regrowth_minutes * 60
	gardening.erase("ready_at")
	gardening.erase("wither_at")
	item.item_metadata[GARDENING_KEY] = gardening
	_apply_visual(item)
	status_changed.emit("Plant is growing")
	changed.emit()


func harvest(item: PlacementItem) -> bool:
	var gardening := _gardening_state(item)
	var definition := _definition_for_state(gardening)
	if not definition or not inventory or not item_catalog:
		return false
	var crop := item_catalog.create_instance(definition.crop_item_id)
	if not inventory.add_instance(crop, item_catalog):
		status_changed.emit("Not enough inventory space")
		return false
	_start_regrowth(item, gardening, definition)
	status_changed.emit("Harvested %s" % definition.crop_item_id)
	return true


func clear_withered(item: PlacementItem) -> void:
	var gardening := _gardening_state(item)
	var definition := _definition_for_state(gardening)
	if not definition:
		return
	_start_regrowth(item, gardening, definition)
	status_changed.emit("Rotten crop cleared")


func remove_plant(item: PlacementItem) -> void:
	if not item:
		return
	if item.item_metadata.erase(GARDENING_KEY):
		_clear_visual(item)
		changed.emit()


func _try_plant_selected_seed(item: PlacementItem) -> bool:
	if not is_pot(item):
		status_changed.emit("Select a pot")
		return false
	if is_planted(item):
		status_changed.emit("Pot is occupied")
		return false
	if _active_pot_count() >= max_active_pots:
		status_changed.emit("Active pot limit reached")
		return false
	var stack := inventory.get_slot_stack(selected_seed_slot)
	if stack.is_empty():
		cancel_seed_selection()
		return false
	var seed: ItemInstance = null
	for candidate in stack:
		if candidate.instance_id == selected_seed_instance_id:
			seed = candidate
			break
	if not seed:
		cancel_seed_selection()
		return false
	var definition := gardening_catalog.get_by_seed(seed.definition_id)
	if not definition:
		cancel_seed_selection()
		return false
	var consumed := inventory.commit_reserved(selected_seed_slot, selected_seed_instance_id)
	if not consumed:
		cancel_seed_selection()
		return false
	var now := _now()
	item.item_metadata[GARDENING_KEY] = {
		"seed_item_id": definition.seed_item_id,
		"crop_item_id": definition.crop_item_id,
		"stage": STAGE_SEED,
		"planted_at": now,
		"next_at": now + definition.initial_growth_minutes * 60,
	}
	cancel_seed_selection()
	_apply_visual(item)
	status_changed.emit("Seed planted")
	changed.emit()
	return true


func _start_regrowth(item: PlacementItem, gardening: Dictionary, definition: GardeningDefinition) -> void:
	var now := _now()
	gardening["stage"] = STAGE_GROWING
	gardening["cycle_started_at"] = now
	gardening["next_at"] = now + definition.regrowth_minutes * 60
	gardening.erase("ready_at")
	gardening.erase("wither_at")
	item.item_metadata[GARDENING_KEY] = gardening
	_apply_visual(item)
	changed.emit()


func _active_pot_count() -> int:
	var count := 0
	if not placement:
		return count
	for item in placement.get_placed_items():
		if item is PlacementItem and is_pot(item) and is_planted(item):
			count += 1
	return count


func _gardening_state(item: PlacementItem) -> Dictionary:
	if not item:
		return {}
	var state: Variant = item.item_metadata.get(GARDENING_KEY, {})
	if not (state is Dictionary):
		return {}
	return state.duplicate(true)


func _definition_for_state(gardening: Dictionary) -> GardeningDefinition:
	if not gardening_catalog:
		return null
	return gardening_catalog.get_by_seed(str(gardening.get("seed_item_id", "")))


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _apply_visual(item: PlacementItem) -> void:
	_clear_visual(item)
	var gardening := _gardening_state(item)
	if gardening.is_empty():
		return
	var stage := str(gardening.get("stage", ""))
	var root := Node3D.new()
	root.name = "GardeningVisual"
	item.add_child(root)
	root.position = Vector3(0.0, _visual_y_offset(item), 0.0)
	match stage:
		STAGE_SEED:
			_add_sphere(root, Vector3(0.0, 0.06, 0.0), 0.08, Color(0.38, 0.22, 0.09, 1.0))
		STAGE_SAPLING:
			_add_stem(root, 0.28, Color(0.25, 0.62, 0.21, 1.0))
			_add_sphere(root, Vector3(0.0, 0.32, 0.0), 0.12, Color(0.34, 0.86, 0.34, 1.0))
		STAGE_GROWING:
			_add_stem(root, 0.5, Color(0.22, 0.55, 0.18, 1.0))
			_add_sphere(root, Vector3(0.0, 0.55, 0.0), 0.22, Color(0.22, 0.72, 0.28, 1.0))
		STAGE_READY:
			_add_stem(root, 0.5, Color(0.22, 0.55, 0.18, 1.0))
			_add_sphere(root, Vector3(0.0, 0.55, 0.0), 0.22, Color(0.24, 0.76, 0.29, 1.0))
			_add_sphere(root, Vector3(0.14, 0.48, 0.02), 0.07, Color(1.0, 0.86, 0.18, 1.0))
		STAGE_WITHERED:
			_add_stem(root, 0.4, Color(0.38, 0.25, 0.12, 1.0))
			_add_sphere(root, Vector3(0.0, 0.43, 0.0), 0.18, Color(0.45, 0.33, 0.18, 1.0))


func _clear_visual(item: PlacementItem) -> void:
	if not item:
		return
	var existing := item.get_node_or_null("GardeningVisual")
	if existing:
		item.remove_child(existing)
		existing.queue_free()


func _visual_y_offset(item: PlacementItem) -> float:
	var bounds := item.get_visual_bounds()
	return maxf(bounds.size.y * 0.5, 0.08)


func _add_stem(parent: Node3D, height: float, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.035
	mesh.height = height
	mesh.radial_segments = 10
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, height * 0.5, 0.0)
	mesh_instance.material_override = _material(color)
	parent.add_child(mesh_instance)


func _add_sphere(parent: Node3D, position: Vector3, radius: float, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.material_override = _material(color)
	parent.add_child(mesh_instance)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
