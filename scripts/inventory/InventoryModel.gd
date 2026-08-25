class_name InventoryModel
extends Node

signal changed

const DEFAULT_COLUMNS := 5
const DEFAULT_ROWS := 10
const DEFAULT_MAX_CAPACITY := 500

@export var columns := DEFAULT_COLUMNS
@export var rows := DEFAULT_ROWS
@export var max_capacity := DEFAULT_MAX_CAPACITY

var slots: Array = []


func _ready() -> void:
	resize(columns, rows)


func resize(new_columns: int, new_rows: int) -> void:
	columns = maxi(new_columns, 1)
	rows = maxi(new_rows, 1)
	var desired_size := mini(columns * rows, max_capacity)
	var previous := slots.duplicate(true)
	slots.resize(desired_size)
	for i in slots.size():
		slots[i] = previous[i] if i < previous.size() else []
	changed.emit()


func seed_defaults(catalog: ItemCatalog) -> void:
	clear()
	for id in ["winged_sheep", "turntable", "street_lamp", "portal", "frame", "ocak", "lambacik"]:
		add_instance(catalog.create_instance(id), catalog)
	for _i in 4:
		add_instance(catalog.create_instance("basic_pot_ver2"), catalog)
		add_instance(catalog.create_instance("basic_pot"), catalog)
	for _i in 8:
		add_instance(catalog.create_instance("candle_ver2"), catalog)


func restore_missing_unique_items(catalog: ItemCatalog) -> int:
	var restored := 0
	for definition in catalog.all_definitions():
		if definition.is_placeable and definition.is_starter and not contains_definition(definition.definition_id):
			if add_instance(catalog.create_instance(definition.definition_id), catalog):
				restored += 1
	return restored


func all_instances() -> Array:
	var result: Array = []
	for stack in slots:
		result.append_array(stack)
	return result


func find_instance(instance_id: String) -> ItemInstance:
	for item in all_instances():
		if item.instance_id == instance_id:
			return item
	return null


func remove_instance_by_id(instance_id: String) -> ItemInstance:
	for stack in slots:
		for i in stack.size():
			if stack[i].instance_id == instance_id:
				var removed: ItemInstance = stack.pop_at(i)
				changed.emit()
				return removed
	return null


func can_add_instances(items: Array, catalog: ItemCatalog) -> bool:
	var simulated: Array = []
	for stack in slots:
		simulated.append(stack.duplicate())
	for item in items:
		if not item is ItemInstance:
			return false
		var definition := catalog.get_definition(item.definition_id)
		if not definition or not _simulate_add_instance(simulated, item, definition):
			return false
	return true


func notify_changed() -> void:
	changed.emit()


func contains_definition(definition_id: String) -> bool:
	for stack in slots:
		if not stack.is_empty() and stack[0].definition_id == definition_id:
			return true
	return false


func clear() -> void:
	for i in slots.size():
		slots[i] = []
	changed.emit()


func get_slot_stack(index: int) -> Array:
	return slots[index] if index >= 0 and index < slots.size() else []


func count_definition(definition_id: String) -> int:
	var total := 0
	for stack in slots:
		if not stack.is_empty() and stack[0].definition_id == definition_id:
			total += stack.size()
	return total


func has_quantities(requirements: Dictionary) -> bool:
	if requirements.is_empty():
		return false
	for definition_id in requirements.keys():
		var id := str(definition_id)
		var quantity := int(requirements[definition_id])
		if id.is_empty() or quantity <= 0 or count_definition(id) < quantity:
			return false
	return true


func consume_quantities(requirements: Dictionary) -> bool:
	if not has_quantities(requirements):
		return false
	for definition_id in requirements.keys():
		var remaining := int(requirements[definition_id])
		for stack in slots:
			if remaining <= 0:
				break
			if stack.is_empty() or stack[0].definition_id != str(definition_id):
				continue
			for _i in mini(remaining, stack.size()):
				stack.pop_back()
				remaining -= 1
	changed.emit()
	return true


func add_instance(item: ItemInstance, catalog: ItemCatalog) -> bool:
	var definition := catalog.get_definition(item.definition_id)
	if not definition:
		return false

	if definition.max_stack_size != 1:
		for stack in slots:
			if not stack.is_empty() and stack[0].is_stack_compatible(item) and _stack_has_room(stack, definition):
				stack.append(item)
				changed.emit()
				return true

	for i in slots.size():
		if slots[i].is_empty():
			slots[i] = [item]
			changed.emit()
			return true
	return false


func replace_slot_with_instance(index: int, item: ItemInstance, catalog: ItemCatalog) -> Array:
	if index < 0 or index >= slots.size() or item == null:
		return []
	if not catalog or not catalog.get_definition(item.definition_id):
		return []
	var discarded: Array = slots[index].duplicate()
	slots[index] = [item]
	changed.emit()
	return discarded


func can_add_cart(cart: Dictionary, catalog: ItemCatalog) -> bool:
	var simulated: Array = []
	for stack in slots:
		simulated.append(stack.duplicate())
	for id in cart.keys():
		var definition := catalog.get_definition(str(id))
		if not definition:
			return false
		for _i in int(cart[id]):
			var item := catalog.create_instance(str(id))
			if not _simulate_add_instance(simulated, item, definition):
				return false
	return true


func remove_quantity_from_slot(index: int, quantity: int) -> Array:
	var stack := get_slot_stack(index)
	if stack.is_empty() or quantity <= 0:
		return []
	var removed: Array = []
	for _i in mini(quantity, stack.size()):
		removed.append(stack.pop_back())
	changed.emit()
	return removed


func occupied_slot_count() -> int:
	var count := 0
	for stack in slots:
		if not stack.is_empty():
			count += 1
	return count


func reserve_one(index: int) -> ItemInstance:
	var stack := get_slot_stack(index)
	return stack.back() if not stack.is_empty() else null


func commit_reserved(index: int, instance_id: String) -> ItemInstance:
	var stack := get_slot_stack(index)
	for i in stack.size():
		if stack[i].instance_id == instance_id:
			var item: ItemInstance = stack.pop_at(i)
			changed.emit()
			return item
	return null


func move_stack(from_index: int, to_index: int, catalog: ItemCatalog, split_half := false) -> void:
	if from_index == to_index:
		return
	var source := get_slot_stack(from_index)
	var target := get_slot_stack(to_index)
	if source.is_empty():
		return

	var moving: Array = []
	var amount := ceili(source.size() * 0.5) if split_half else source.size()
	for _i in amount:
		moving.push_front(source.pop_back())

	if target.is_empty():
		slots[to_index] = moving
	elif target[0].is_stack_compatible(moving[0]):
		var definition := catalog.get_definition(moving[0].definition_id)
		var room := moving.size() if definition.max_stack_size <= 0 else definition.max_stack_size - target.size()
		for _i in mini(room, moving.size()):
			target.append(moving.pop_front())
		source.append_array(moving)
	else:
		source.append_array(moving)
		if not split_half:
			slots[from_index] = target
			slots[to_index] = source
	changed.emit()


func to_dict() -> Dictionary:
	var serialized_slots: Array = []
	for stack in slots:
		var serialized_stack: Array = []
		for item in stack:
			serialized_stack.append(item.to_dict())
		serialized_slots.append(serialized_stack)
	return {"columns": columns, "rows": rows, "max_capacity": max_capacity, "slots": serialized_slots}


func load_dict(data: Dictionary) -> void:
	max_capacity = int(data.get("max_capacity", DEFAULT_MAX_CAPACITY))
	var serialized_slots: Array = data.get("slots", [])
	var saved_columns := int(data.get("columns", DEFAULT_COLUMNS))
	var saved_rows := int(data.get("rows", DEFAULT_ROWS))
	var desired_size := maxi(maxi(saved_columns * saved_rows, serialized_slots.size()), DEFAULT_COLUMNS * DEFAULT_ROWS)
	desired_size = mini(desired_size, max_capacity)
	columns = DEFAULT_COLUMNS
	rows = ceili(float(desired_size) / float(columns))
	slots.clear()
	for serialized_stack in serialized_slots:
		var stack: Array = []
		for item_data in serialized_stack:
			stack.append(ItemInstance.from_dict(item_data))
		slots.append(stack)
	while slots.size() < columns * rows:
		slots.append([])
	while slots.size() > columns * rows:
		slots.pop_back()
	changed.emit()


func _stack_has_room(stack: Array, definition: PlaceableItemDefinition) -> bool:
	return definition.max_stack_size <= 0 or stack.size() < definition.max_stack_size


func _simulate_add_instance(simulated_slots: Array, item: ItemInstance, definition: PlaceableItemDefinition) -> bool:
	if definition.max_stack_size != 1:
		for stack in simulated_slots:
			if not stack.is_empty() and stack[0].is_stack_compatible(item) and _stack_has_room(stack, definition):
				stack.append(item)
				return true
	for i in simulated_slots.size():
		if simulated_slots[i].is_empty():
			simulated_slots[i] = [item]
			return true
	return false
