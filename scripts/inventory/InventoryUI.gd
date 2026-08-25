class_name InventoryUI
extends CanvasLayer

signal item_placement_requested(slot_index: int)
signal seed_use_requested(slot_index: int)

var inventory: InventoryModel
var catalog: ItemCatalog
var wallet: WalletModel
var panel: PanelContainer
var grid: GridContainer
var wallet_label: Label
var capacity_label: Label
var empty_filter_label: Label
var top_category_dropdown: OptionButton
var sub_category_dropdown: OptionButton
var search_field: LineEdit
var slots: Array[InventorySlot] = []
var _active_top_category := "all"
var _active_sub_category := "all"
var _top_filter_keys: Array[String] = []
var _sub_filter_keys: Array[String] = []


func setup(p_inventory: InventoryModel, p_catalog: ItemCatalog, p_wallet: WalletModel = null) -> void:
	inventory = p_inventory
	catalog = p_catalog
	wallet = p_wallet
	_build_ui()
	inventory.changed.connect(refresh)
	if wallet:
		wallet.changed.connect(refresh)
	refresh()


func toggle() -> void:
	panel.visible = not panel.visible


func is_open() -> bool:
	return panel != null and panel.visible


func refresh() -> void:
	if not inventory or not grid:
		return
	grid.columns = inventory.columns
	if wallet_label:
		wallet_label.text = "Coins: %d | Gems: %d" % [wallet.coins, wallet.gems] if wallet else "Coins: 0 | Gems: 0"
	if capacity_label:
		capacity_label.text = "Slots: %d/%d" % [inventory.occupied_slot_count(), inventory.slots.size()]
	while slots.size() < inventory.slots.size():
		var slot := InventorySlot.new()
		slot.slot_index = slots.size()
		slot.activated.connect(_on_slot_activated)
		slot.move_requested.connect(_on_move_requested)
		slot.dropped_outside.connect(_on_slot_activated)
		grid.add_child(slot)
		slots.append(slot)
	for i in slots.size():
		slots[i].visible = i < inventory.slots.size()
		if i < inventory.slots.size():
			var stack := inventory.get_slot_stack(i)
			var definition := catalog.get_definition(stack[0].definition_id) if not stack.is_empty() else null
			slots[i].visible = _slot_visible_for_filter(stack, definition)
			slots[i].set_contents(stack, definition)
	if empty_filter_label:
		empty_filter_label.visible = _filtered_occupied_count() == 0 and not _filters_are_clear()


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310.0, -275.0)
	panel.custom_minimum_size = Vector2(620.0, 550.0)
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var title := Label.new()
	title.text = "Inventory"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)

	var summary := HBoxContainer.new()
	summary.alignment = BoxContainer.ALIGNMENT_CENTER
	summary.add_theme_constant_override("separation", 16)
	layout.add_child(summary)

	wallet_label = Label.new()
	summary.add_child(wallet_label)

	capacity_label = Label.new()
	summary.add_child(capacity_label)

	_build_filters(layout)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	grid = GridContainer.new()
	grid.columns = inventory.columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	scroll.add_child(grid)

	empty_filter_label = Label.new()
	empty_filter_label.text = "No inventory items match these filters"
	empty_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_filter_label.visible = false
	layout.add_child(empty_filter_label)


func _build_filters(parent: VBoxContainer) -> void:
	var filters := VBoxContainer.new()
	filters.add_theme_constant_override("separation", 6)
	parent.add_child(filters)

	var dropdowns := HBoxContainer.new()
	dropdowns.add_theme_constant_override("separation", 6)
	filters.add_child(dropdowns)

	top_category_dropdown = OptionButton.new()
	top_category_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_category_dropdown.item_selected.connect(_on_top_category_selected)
	dropdowns.add_child(top_category_dropdown)

	sub_category_dropdown = OptionButton.new()
	sub_category_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_category_dropdown.item_selected.connect(_on_sub_category_selected)
	dropdowns.add_child(sub_category_dropdown)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 6)
	filters.add_child(search_row)

	search_field = LineEdit.new()
	search_field.placeholder_text = "Search items"
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.text_changed.connect(_on_search_changed)
	search_row.add_child(search_field)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.pressed.connect(_clear_inventory_filters)
	search_row.add_child(clear_button)

	_refresh_filter_dropdowns()


func _on_slot_activated(index: int) -> void:
	var stack := inventory.get_slot_stack(index)
	if stack.is_empty():
		return
	var definition := catalog.get_definition(stack[0].definition_id)
	if not definition:
		return
	if _is_seed_definition(definition):
		seed_use_requested.emit(index)
		return
	if not definition.is_placeable:
		return
	item_placement_requested.emit(index)


func _on_move_requested(from_index: int, to_index: int, split_half: bool) -> void:
	inventory.move_stack(from_index, to_index, catalog, split_half)


func _on_top_category_selected(index: int) -> void:
	if index < 0 or index >= _top_filter_keys.size():
		return
	_active_top_category = _top_filter_keys[index]
	_active_sub_category = "all"
	_refresh_filter_dropdowns()
	refresh()


func _on_sub_category_selected(index: int) -> void:
	if index < 0 or index >= _sub_filter_keys.size():
		return
	_active_sub_category = _sub_filter_keys[index]
	refresh()


func _on_search_changed(_text: String) -> void:
	refresh()


func _clear_inventory_filters() -> void:
	_active_top_category = "all"
	_active_sub_category = "all"
	if search_field:
		search_field.text = ""
	_refresh_filter_dropdowns()
	refresh()


func _refresh_filter_dropdowns() -> void:
	if not top_category_dropdown or not sub_category_dropdown:
		return

	_top_filter_keys = ["all"]
	top_category_dropdown.clear()
	top_category_dropdown.add_item("All")
	for key in MarketUI.TOP_CATEGORY_ORDER:
		_top_filter_keys.append(key)
		top_category_dropdown.add_item(MarketUI._display_key(key))
	top_category_dropdown.selected = max(0, _top_filter_keys.find(_active_top_category))

	_sub_filter_keys = ["all"]
	sub_category_dropdown.clear()
	sub_category_dropdown.add_item("All subcategories")
	if _active_top_category == "all":
		sub_category_dropdown.disabled = true
		sub_category_dropdown.selected = 0
		return

	sub_category_dropdown.disabled = false
	for key in MarketUI.CATEGORY_TAXONOMY.get(_active_top_category, []):
		_sub_filter_keys.append(key)
		sub_category_dropdown.add_item(MarketUI._display_key(key))
	sub_category_dropdown.selected = max(0, _sub_filter_keys.find(_active_sub_category))


func _slot_visible_for_filter(stack: Array, definition: PlaceableItemDefinition) -> bool:
	return inventory_slot_matches_filters(
		stack,
		definition,
		_active_top_category,
		_active_sub_category,
		search_field.text if search_field else ""
	)


static func inventory_slot_matches_filters(
		stack: Array,
		definition: PlaceableItemDefinition,
		top_category: String,
		sub_category: String,
		search_text: String) -> bool:
	var filters_clear := top_category == "all" and sub_category == "all" and search_text.strip_edges().is_empty()
	if stack.is_empty():
		return filters_clear
	if not definition:
		return false

	var path := MarketUI.market_category_path(definition)
	if top_category != "all" and path["top"] != top_category:
		return false
	if sub_category != "all" and path["sub"] != sub_category:
		return false

	var query := search_text.strip_edges().to_lower()
	if query.is_empty():
		return true
	var haystack := "%s %s %s %s %s" % [
		definition.item_name,
		definition.description,
		definition.category,
		definition.sub_category,
		MarketUI.market_category_display_path(definition),
	]
	return haystack.to_lower().contains(query)


static func _is_seed_definition(definition: PlaceableItemDefinition) -> bool:
	return definition != null and (
		definition.category.strip_edges().to_lower() == "seeds"
		or definition.definition_id.ends_with("_seed")
	)


func _filtered_occupied_count() -> int:
	var count := 0
	for i in inventory.slots.size():
		var stack := inventory.get_slot_stack(i)
		if stack.is_empty():
			continue
		var definition := catalog.get_definition(stack[0].definition_id)
		if _slot_visible_for_filter(stack, definition):
			count += 1
	return count


func _filters_are_clear() -> bool:
	return _active_top_category == "all" and _active_sub_category == "all" and (not search_field or search_field.text.strip_edges().is_empty())
