class_name AvatarStoreUI
extends CanvasLayer

signal close_requested
signal purchase_completed

const SLOT_ORDER := ["all", "fullbody", "top", "bottom", "hair", "hair_color", "skin_tone"]

var store: AvatarStoreModel
var wallet: WalletModel
var inventory: InventoryModel
var catalog: ItemCatalog
var profile: AvatarProfile
var equipment: AvatarEquipmentModel
var avatar: CharacterAvatar

var panel: PanelContainer
var title_label: Label
var wallet_label: Label
var status_label: Label
var slot_filter: OptionButton
var search_field: LineEdit
var item_list: VBoxContainer
var cart_list: VBoxContainer
var _active_slot := "all"
var _base_state: Dictionary = {}


func setup(
		p_store: AvatarStoreModel,
		p_wallet: WalletModel,
		p_inventory: InventoryModel,
		p_catalog: ItemCatalog,
		p_profile: AvatarProfile,
		p_equipment: AvatarEquipmentModel,
		p_avatar: CharacterAvatar) -> void:
	store = p_store
	wallet = p_wallet
	inventory = p_inventory
	catalog = p_catalog
	profile = p_profile
	equipment = p_equipment
	avatar = p_avatar
	_build_ui()
	store.changed.connect(_on_store_changed)
	store.status_changed.connect(_set_status)
	store.purchase_completed.connect(func(): purchase_completed.emit())
	wallet.changed.connect(_refresh_header)
	profile.changed.connect(_on_profile_changed)
	_refresh_all()


func open() -> void:
	equipment.sweep_expired()
	_base_state = equipment.appearance_state()
	panel.visible = true
	avatar.apply_state(store.preview_state(_base_state, catalog))
	_refresh_all()


func close() -> void:
	store.clear()
	if avatar and not _base_state.is_empty():
		avatar.apply_state(_base_state)
	panel.visible = false


func is_open() -> bool:
	return panel != null and panel.visible


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "AvatarStorePanel"
	panel.visible = false
	panel.anchor_left = 0.38
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	layout.add_child(header)
	title_label = Label.new()
	title_label.text = "Avatar Store"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	wallet_label = Label.new()
	header.add_child(wallet_label)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): close_requested.emit())
	header.add_child(back)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(status_label)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	layout.add_child(filters)
	slot_filter = OptionButton.new()
	for slot in SLOT_ORDER:
		slot_filter.add_item("All" if slot == "all" else slot.replace("_", " ").capitalize())
	slot_filter.item_selected.connect(_on_slot_filter_selected)
	filters.add_child(slot_filter)
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search avatar items"
	search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.text_changed.connect(func(_text): _refresh_item_list())
	filters.add_child(search_field)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	layout.add_child(columns)
	item_list = _make_scroll_column(columns, "Items")
	cart_list = _make_scroll_column(columns, "Dressing Cart")

	var purchase := Button.new()
	purchase.text = "Purchase Packaged Items"
	purchase.pressed.connect(_purchase)
	layout.add_child(purchase)


func _make_scroll_column(parent: Control, title_text: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func _refresh_all() -> void:
	_refresh_header()
	_refresh_item_list()
	_refresh_cart()


func _refresh_header() -> void:
	if title_label:
		title_label.text = "%s Avatar Store" % AvatarProfile.display_gender(profile.gender)
	if wallet_label:
		wallet_label.text = "Coins: %d  |  Gems: %d" % [wallet.coins, wallet.gems]


func _refresh_item_list() -> void:
	if not item_list:
		return
	_clear_children(item_list)
	var definitions := catalog.buyable_definitions()
	definitions.sort_custom(func(a, b): return a.definition_id < b.definition_id)
	var query := search_field.text.strip_edges().to_lower() if search_field else ""
	for definition in definitions:
		if definition.avatar_slot.is_empty():
			continue
		if not catalog.is_avatar_definition_compatible(definition, profile.gender):
			continue
		if _active_slot != "all" and definition.avatar_slot != _active_slot:
			continue
		if not query.is_empty() and not (definition.item_name + " " + definition.definition_id).to_lower().contains(query):
			continue
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		item_list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		card.add_child(row)
		if not definition.swatch_path.is_empty():
			var swatch := TextureRect.new()
			swatch.custom_minimum_size = Vector2(30.0, 30.0)
			swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			swatch.texture = ResourceLoader.load(definition.swatch_path) as Texture2D
			row.add_child(swatch)
		var label := Label.new()
		label.text = "%s\n%s" % [definition.item_name, definition.avatar_slot.replace("_", " ").capitalize()]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var controls := HBoxContainer.new()
		controls.add_theme_constant_override("separation", 6)
		card.add_child(controls)
		var duration := OptionButton.new()
		duration.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option in definition.pricing_options:
			var currency_name := "Gems" if option.get("currency_type", WalletModel.SOFT) == WalletModel.HARD else "Coins"
			var days := int(option.get("duration_days", 0))
			duration.add_item("%s%s - %d %s" % [days, "d" if days > 0 else "", int(option.get("price", 0)), currency_name])
			duration.set_item_metadata(duration.item_count - 1, option.duplicate(true))
		controls.add_child(duration)
		var add_button := Button.new()
		add_button.text = "Preview + Add"
		add_button.pressed.connect(_select_item.bind(definition.definition_id, duration))
		controls.add_child(add_button)


func _refresh_cart() -> void:
	if not cart_list:
		return
	_clear_children(cart_list)
	if store.cart.is_empty():
		var empty := Label.new()
		empty.text = "Select items to dress the avatar"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cart_list.add_child(empty)
	else:
		for slot in SLOT_ORDER:
			if slot == "all" or not store.cart.has(slot):
				continue
			var line: Dictionary = store.cart[slot]
			var definition := catalog.get_definition(str(line.get("definition_id", "")))
			var row := HBoxContainer.new()
			cart_list.add_child(row)
			var label := Label.new()
			var currency_name := "Gems" if line.get("currency_type") == WalletModel.HARD else "Coins"
			label.text = "%s\n%d%s | %d %s" % [definition.item_name, int(line.get("duration_days", 0)), "d" if int(line.get("duration_days", 0)) > 0 else "", int(line.get("price", 0)), currency_name]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var remove := Button.new()
			remove.text = "Remove"
			remove.pressed.connect(store.remove_slot.bind(slot))
			row.add_child(remove)
	var totals := store.totals()
	var total_label := Label.new()
	total_label.text = "Total: %d Coins + %d Gems" % [totals[WalletModel.SOFT], totals[WalletModel.HARD]]
	cart_list.add_child(total_label)


func _select_item(definition_id: String, duration: OptionButton) -> void:
	if duration.item_count <= 0:
		return
	var option: Dictionary = duration.get_item_metadata(duration.selected)
	store.select_item(definition_id, int(option.get("duration_days", 0)), catalog, profile.gender)


func _purchase() -> void:
	if store.purchase(wallet, inventory, catalog, profile.user_id, profile.gender):
		_base_state = equipment.appearance_state()
		avatar.apply_state(_base_state)


func _on_store_changed() -> void:
	if avatar and not _base_state.is_empty():
		avatar.apply_state(store.preview_state(_base_state, catalog))
	_refresh_cart()


func _on_slot_filter_selected(index: int) -> void:
	_active_slot = SLOT_ORDER[index] if index >= 0 and index < SLOT_ORDER.size() else "all"
	_refresh_item_list()


func _set_status(message: String) -> void:
	if status_label:
		status_label.text = message


func _on_profile_changed() -> void:
	if not panel:
		return
	_base_state = equipment.appearance_state()
	store.clear()
	_refresh_all()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
