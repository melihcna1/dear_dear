class_name MarketUI
extends CanvasLayer

signal purchase_completed
signal sale_completed
signal preview_requested(definition_id: String)
signal preview_purchase_requested
signal preview_cancel_requested
signal avatar_store_requested

var market: MarketModel
var wallet: WalletModel
var inventory: InventoryModel
var catalog: ItemCatalog
var panel: PanelContainer
var wallet_label: Label
var status_label: Label
var top_category_dropdown: OptionButton
var sub_category_dropdown: OptionButton
var search_field: LineEdit
var market_list: VBoxContainer
var cart_list: VBoxContainer
var sell_list: VBoxContainer
var preview_panel: PanelContainer
var preview_item_label: Label
var preview_wallet_label: Label
var preview_status_label: Label
var preview_buy_button: Button
var _preview_definition_id := ""
var _preview_ready := false
var _active_top_category := "all"
var _active_sub_category := "all"
var _top_filter_keys: Array[String] = []
var _sub_filter_keys: Array[String] = []

const LEFT_VIEW_RATIO := 0.38
const PANEL_MARGIN := 8.0
const TOP_CATEGORY_ORDER := ["cloth", "furniture", "other"]
const CATEGORY_TAXONOMY := {
	"cloth": ["face", "top", "fullbody", "bottom", "hair", "hair_color", "skin_tone", "shoes", "accessory"],
	"furniture": ["seating", "bed", "table", "electronics", "decor", "garden", "fantasy"],
	"other": ["seed", "beauty", "emote", "box", "effects", "pet", "fishing", "utility", "chat_bubble"],
}
const LEGACY_CATEGORY_MAP := {
	"furniture": "furniture",
	"clothes": "cloth",
	"cloth": "cloth",
	"seeds": "other",
	"seed": "other",
	"beauty": "other",
	"emotes": "other",
	"emote": "other",
	"chat_bubbles": "other",
	"chat bubbles": "other",
	"chat_bubble": "other",
	"utilities": "other",
	"utility": "other",
}
const LEGACY_SUB_CATEGORY_MAP := {
	"creature": "fantasy",
	"display": "table",
	"lighting": "decor",
	"architecture": "fantasy",
	"hearth": "decor",
	"decor": "decor",
	"fruit": "seed",
	"bubble": "chat_bubble",
	"freshwater": "fishing",
	"drink": "utility",
}


func setup(p_market: MarketModel, p_wallet: WalletModel, p_inventory: InventoryModel, p_catalog: ItemCatalog) -> void:
	market = p_market
	wallet = p_wallet
	inventory = p_inventory
	catalog = p_catalog
	_build_ui()
	market.changed.connect(refresh)
	market.status_changed.connect(_set_status)
	wallet.changed.connect(refresh)
	inventory.changed.connect(refresh)
	refresh()


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	panel.visible = true
	_layout_panel()
	refresh()


func close() -> void:
	panel.visible = false


func show_preview_controls(definition_id: String) -> void:
	var definition := catalog.get_definition(definition_id)
	if not definition:
		return
	_preview_definition_id = definition_id
	panel.visible = false
	preview_panel.visible = true
	preview_item_label.text = "%s\n%d coins" % [definition.item_name, definition.buy_price]
	preview_status_label.text = "Move the item, then left click to confirm its position."
	_preview_ready = true
	set_preview_ready(false)
	refresh()


func hide_preview_controls() -> void:
	_preview_definition_id = ""
	if preview_panel:
		preview_panel.visible = false


func show_market_after_preview() -> void:
	hide_preview_controls()
	open()


func set_preview_ready(ready: bool) -> void:
	if _preview_ready == ready:
		return
	_preview_ready = ready
	if preview_buy_button:
		preview_buy_button.disabled = not ready
	if preview_status_label:
		preview_status_label.text = (
			"Position confirmed. Buy to place this item."
			if ready
			else "Move the item, then left click to confirm its position."
		)


func is_open() -> bool:
	return panel != null and panel.visible


func refresh() -> void:
	if not panel:
		return
	_layout_panel()
	wallet_label.text = "Coins: %d | Gems: %d" % [wallet.coins, wallet.gems]
	if preview_wallet_label:
		preview_wallet_label.text = "Coins: %d | Gems: %d" % [wallet.coins, wallet.gems]
	_refresh_market_list()
	_refresh_cart_list()
	_refresh_sell_list()


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "MarketPanel"
	panel.visible = false
	panel.anchor_left = LEFT_VIEW_RATIO
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = PANEL_MARGIN
	panel.offset_top = PANEL_MARGIN
	panel.offset_right = -PANEL_MARGIN
	panel.offset_bottom = -PANEL_MARGIN
	panel.custom_minimum_size = Vector2(520.0, 420.0)
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 24)
	layout.add_child(header)

	var title := Label.new()
	title.text = "Market"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)

	wallet_label = Label.new()
	header.add_child(wallet_label)

	var avatar_store_button := Button.new()
	avatar_store_button.text = "Avatar Store"
	avatar_store_button.pressed.connect(func(): avatar_store_requested.emit())
	header.add_child(avatar_store_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(status_label)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	layout.add_child(columns)

	var market_column := _make_scroll_column_container(columns, "Market")
	_build_market_filters(market_column)
	market_list = _make_scroll_list(market_column)
	cart_list = _make_scroll_column(columns, "Cart")
	sell_list = _make_scroll_column(columns, "Sell")

	var purchase_button := Button.new()
	purchase_button.text = "Purchase Cart"
	purchase_button.pressed.connect(_on_purchase_pressed)
	layout.add_child(purchase_button)
	_build_preview_controls()


func _build_preview_controls() -> void:
	preview_panel = PanelContainer.new()
	preview_panel.name = "MarketPreviewPanel"
	preview_panel.visible = false
	preview_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	preview_panel.position = Vector2(-292.0, 16.0)
	preview_panel.custom_minimum_size = Vector2(276.0, 0.0)
	add_child(preview_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	preview_panel.add_child(layout)

	var title := Label.new()
	title.text = "Decor Preview"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	layout.add_child(title)

	preview_item_label = Label.new()
	preview_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(preview_item_label)

	preview_wallet_label = Label.new()
	preview_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(preview_wallet_label)

	preview_status_label = Label.new()
	preview_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(preview_status_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	layout.add_child(buttons)

	preview_buy_button = Button.new()
	preview_buy_button.text = "Buy & Place"
	preview_buy_button.disabled = true
	preview_buy_button.pressed.connect(func(): preview_purchase_requested.emit())
	buttons.add_child(preview_buy_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(func(): preview_cancel_requested.emit())
	buttons.add_child(cancel_button)


func _make_scroll_column(parent: Control, title_text: String) -> VBoxContainer:
	var column := _make_scroll_column_container(parent, title_text)
	return _make_scroll_list(column)


func _make_scroll_column_container(parent: Control, title_text: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	return column


func _make_scroll_list(column: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _build_market_filters(parent: VBoxContainer) -> void:
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
	clear_button.pressed.connect(_clear_market_filters)
	search_row.add_child(clear_button)

	_refresh_filter_dropdowns()


func _refresh_market_list() -> void:
	_clear_children(market_list)
	var added := false
	for definition in catalog.buyable_definitions():
		if definition.item_type != "STANDARD":
			continue
		if not _definition_matches_market_filters(definition):
			continue
		added = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		market_list.add_child(row)

		var label := Label.new()
		label.text = "%s\n%s | %d coins" % [
			definition.item_name,
			market_category_display_path(definition),
			definition.buy_price,
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = MarketModel.MAX_CART_QUANTITY
		quantity.value = 1
		quantity.custom_minimum_size = Vector2(64.0, 0.0)
		row.add_child(quantity)

		var add_button := Button.new()
		add_button.text = "Add"
		add_button.pressed.connect(_on_add_to_cart_pressed.bind(definition.definition_id, quantity))
		row.add_child(add_button)

		if definition.is_placeable:
			var preview_button := Button.new()
			preview_button.text = "Preview"
			preview_button.pressed.connect(_on_preview_pressed.bind(definition.definition_id))
			row.add_child(preview_button)
	if not added:
		var empty := Label.new()
		empty.text = "No items match these filters"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		market_list.add_child(empty)


func _refresh_cart_list() -> void:
	_clear_children(cart_list)
	if market.cart.is_empty():
		var empty := Label.new()
		empty.text = "Cart is empty"
		cart_list.add_child(empty)
	else:
		for id in market.cart.keys():
			var definition := catalog.get_definition(str(id))
			if not definition:
				continue
			var quantity := int(market.cart[id])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			cart_list.add_child(row)

			var label := Label.new()
			label.text = "%s x%d\n%d coins" % [definition.item_name, quantity, definition.buy_price * quantity]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)

			var remove_button := Button.new()
			remove_button.text = "Remove"
			remove_button.pressed.connect(market.remove_from_cart.bind(str(id)))
			row.add_child(remove_button)

	var total := Label.new()
	total.text = "Total: %d" % market.cart_total(catalog)
	cart_list.add_child(total)


func _refresh_sell_list() -> void:
	_clear_children(sell_list)
	var added := false
	for i in inventory.slots.size():
		var stack := inventory.get_slot_stack(i)
		if stack.is_empty():
			continue
		var definition := catalog.get_definition(stack[0].definition_id)
		if not market.is_sellable(definition):
			continue
		added = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		sell_list.add_child(row)

		var label := Label.new()
		label.text = "%s x%d\n%d coins each" % [definition.item_name, stack.size(), definition.sell_price]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var quantity := SpinBox.new()
		quantity.min_value = 1
		quantity.max_value = stack.size()
		quantity.value = 1
		quantity.custom_minimum_size = Vector2(64.0, 0.0)
		row.add_child(quantity)

		var sell_button := Button.new()
		sell_button.text = "Sell"
		sell_button.pressed.connect(_on_sell_pressed.bind(i, quantity))
		row.add_child(sell_button)
	if not added:
		var empty := Label.new()
		empty.text = "No sellable items"
		sell_list.add_child(empty)


func _on_add_to_cart_pressed(definition_id: String, quantity: SpinBox) -> void:
	market.add_to_cart(definition_id, int(quantity.value))


func _on_preview_pressed(definition_id: String) -> void:
	preview_requested.emit(definition_id)


func _on_purchase_pressed() -> void:
	if market.purchase(wallet, inventory, catalog):
		purchase_completed.emit()


func _on_sell_pressed(slot_index: int, quantity: SpinBox) -> void:
	if market.sell_slot_quantity(slot_index, int(quantity.value), wallet, inventory, catalog):
		sale_completed.emit()


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


func _clear_market_filters() -> void:
	_active_top_category = "all"
	_active_sub_category = "all"
	if search_field:
		search_field.text = ""
	_refresh_filter_dropdowns()
	refresh()


func _set_status(message: String) -> void:
	status_label.text = message
	if preview_panel and preview_panel.visible:
		preview_status_label.text = message


func _layout_panel() -> void:
	if not panel:
		return
	panel.anchor_left = LEFT_VIEW_RATIO
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = PANEL_MARGIN
	panel.offset_top = PANEL_MARGIN
	panel.offset_right = -PANEL_MARGIN
	panel.offset_bottom = -PANEL_MARGIN


func _refresh_filter_dropdowns() -> void:
	if not top_category_dropdown or not sub_category_dropdown:
		return

	_top_filter_keys = ["all"]
	top_category_dropdown.clear()
	top_category_dropdown.add_item("All")
	for key in TOP_CATEGORY_ORDER:
		_top_filter_keys.append(key)
		top_category_dropdown.add_item(_display_key(key))
	top_category_dropdown.selected = max(0, _top_filter_keys.find(_active_top_category))

	_sub_filter_keys = ["all"]
	sub_category_dropdown.clear()
	sub_category_dropdown.add_item("All subcategories")
	if _active_top_category == "all":
		sub_category_dropdown.disabled = true
		sub_category_dropdown.selected = 0
		return

	sub_category_dropdown.disabled = false
	for key in CATEGORY_TAXONOMY.get(_active_top_category, []):
		_sub_filter_keys.append(key)
		sub_category_dropdown.add_item(_display_key(key))
	sub_category_dropdown.selected = max(0, _sub_filter_keys.find(_active_sub_category))


func _definition_matches_market_filters(definition: PlaceableItemDefinition) -> bool:
	var path := market_category_path(definition)
	if _active_top_category != "all" and path["top"] != _active_top_category:
		return false
	if _active_sub_category != "all" and path["sub"] != _active_sub_category:
		return false

	var query := search_field.text.strip_edges().to_lower() if search_field else ""
	if query.is_empty():
		return true
	var haystack := "%s %s %s %s %s" % [
		definition.item_name,
		definition.description,
		definition.category,
		definition.sub_category,
		market_category_display_path(definition),
	]
	return haystack.to_lower().contains(query)


static func market_category_path(definition: PlaceableItemDefinition) -> Dictionary:
	if not definition:
		return {"top": "other", "sub": "utility"}

	var category_key := _normalize_key(definition.category)
	var sub_key := _normalize_key(definition.sub_category)
	var top := str(LEGACY_CATEGORY_MAP.get(category_key, ""))
	if top.is_empty() and category_key in TOP_CATEGORY_ORDER:
		top = category_key
	if top.is_empty():
		top = "other"

	var sub := str(LEGACY_SUB_CATEGORY_MAP.get(sub_key, sub_key))
	if sub.is_empty():
		sub = _default_subcategory_for_top(top)
	if not (sub in CATEGORY_TAXONOMY.get(top, [])):
		sub = _default_subcategory_for_top(top)
	return {"top": top, "sub": sub}


static func market_category_display_path(definition: PlaceableItemDefinition) -> String:
	var path := market_category_path(definition)
	return "%s / %s" % [_display_key(str(path["top"])), _display_key(str(path["sub"]))]


static func _default_subcategory_for_top(top: String) -> String:
	match top:
		"cloth":
			return "accessory"
		"furniture":
			return "decor"
		_:
			return "utility"


static func _normalize_key(value: String) -> String:
	return value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")


static func _display_key(value: String) -> String:
	var words := value.replace("_", " ").split(" ", false)
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
