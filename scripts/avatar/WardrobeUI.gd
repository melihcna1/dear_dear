class_name WardrobeUI
extends CanvasLayer

signal close_requested
signal appearance_committed
signal onboarding_requested

var inventory: InventoryModel
var catalog: ItemCatalog
var equipment: AvatarEquipmentModel
var profile: AvatarProfile
var avatar: CharacterAvatar
var clock: UtcClock

var panel: PanelContainer
var title_label: Label
var item_list: VBoxContainer
var status_label: Label
var apply_button: Button
var _base_state: Dictionary = {}
var _selected_instance_id := ""


func setup(p_inventory: InventoryModel, p_catalog: ItemCatalog, p_equipment: AvatarEquipmentModel, p_avatar: CharacterAvatar) -> void:
	inventory = p_inventory
	catalog = p_catalog
	equipment = p_equipment
	profile = p_equipment.profile
	avatar = p_avatar
	clock = equipment.clock
	_build_ui()
	inventory.changed.connect(_refresh)


func open() -> void:
	equipment.sweep_expired()
	_base_state = equipment.appearance_state()
	_selected_instance_id = ""
	panel.visible = true
	avatar.apply_state(_base_state)
	_refresh()


func close() -> void:
	if avatar and not _base_state.is_empty():
		avatar.apply_state(_base_state)
	panel.visible = false
	_selected_instance_id = ""


func is_open() -> bool:
	return panel != null and panel.visible


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "WardrobePanel"
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
	layout.add_child(header)
	title_label = Label.new()
	title_label.text = "Wardrobe"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var onboarding_button := Button.new()
	onboarding_button.name = "RedoAppearanceSetup"
	onboarding_button.text = "Redo Appearance Setup"
	onboarding_button.tooltip_text = "Change gender, hair color, or skin tone with a live preview."
	onboarding_button.pressed.connect(func(): onboarding_requested.emit())
	header.add_child(onboarding_button)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func(): close_requested.emit())
	header.add_child(close_button)
	status_label = Label.new()
	status_label.text = "Previewing does not activate or consume an item."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.add_theme_constant_override("separation", 6)
	scroll.add_child(item_list)
	apply_button = Button.new()
	apply_button.text = "Apply Selected Item"
	apply_button.disabled = true
	apply_button.pressed.connect(_apply_selected)
	layout.add_child(apply_button)


func _refresh() -> void:
	if not item_list:
		return
	_clear_children(item_list)
	if title_label:
		title_label.text = "%s Wardrobe" % AvatarProfile.display_gender(profile.gender)
	var any := false
	for slot_index in inventory.slots.size():
		var stack := inventory.get_slot_stack(slot_index)
		if stack.is_empty():
			continue
		var item: ItemInstance = stack.back()
		var definition := catalog.get_definition(item.definition_id)
		if not definition or not definition.item_type in ["RENTAL", "CONSUMABLE"]:
			continue
		if not catalog.is_avatar_definition_compatible(definition, profile.gender):
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		item_list.add_child(row)
		if not definition.swatch_path.is_empty():
			var swatch := TextureRect.new()
			swatch.custom_minimum_size = Vector2(34.0, 34.0)
			swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			swatch.texture = ResourceLoader.load(definition.swatch_path) as Texture2D
			row.add_child(swatch)
		var label := Label.new()
		label.text = _item_status(item, definition, stack.size())
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var preview := Button.new()
		preview.text = "Preview"
		preview.pressed.connect(_preview_instance.bind(item.instance_id))
		row.add_child(preview)
	if not any:
		var empty := Label.new()
		empty.text = "No rental or consumable avatar items owned."
		item_list.add_child(empty)
	apply_button.disabled = _selected_instance_id.is_empty()


func _item_status(item: ItemInstance, definition: PlaceableItemDefinition, quantity: int) -> String:
	if item.item_type == "CONSUMABLE":
		return "%s x%d\nSingle-use consumable" % [definition.item_name, quantity]
	if not item.is_activated:
		return "%s\nPackaged | %d days" % [definition.item_name, item.duration_days]
	var remaining := maxi(int(item.expires_at) - clock.now_unix(), 0)
	return "%s\n%s | %dh %dm remaining" % [definition.item_name, "Equipped" if item.is_equipped else "Active", remaining / 3600, (remaining % 3600) / 60]


func _preview_instance(instance_id: String) -> void:
	var item := inventory.find_instance(instance_id)
	if not item:
		return
	var definition := catalog.get_definition(item.definition_id)
	if not definition or not catalog.is_avatar_definition_compatible(definition, profile.gender):
		status_label.text = "This item is not compatible with the current avatar."
		return
	var state := _base_state.duplicate(true)
	var active_gender := str(state.get("gender", profile.gender))
	match definition.avatar_slot:
		"fullbody":
			state["fullbody"] = definition.definition_id
			state["top"] = ""
			state["bottom"] = ""
		"top", "bottom":
			state[definition.avatar_slot] = definition.definition_id
			state["fullbody"] = ""
			if str(state.get("top", "")).is_empty(): state["top"] = AvatarEquipmentModel.starter_for_gender(active_gender, "top")
			if str(state.get("bottom", "")).is_empty(): state["bottom"] = AvatarEquipmentModel.starter_for_gender(active_gender, "bottom")
		"hair": state["hair"] = definition.definition_id
		"hair_color": state["hair_color"] = definition.definition_id
		"skin_tone": state["skin_tone"] = definition.definition_id
	_selected_instance_id = instance_id
	apply_button.disabled = false
	status_label.text = "Previewing %s" % definition.item_name
	avatar.apply_state(state)


func _apply_selected() -> void:
	var item := inventory.find_instance(_selected_instance_id)
	if not item:
		return
	var success := equipment.apply_consumable(item.instance_id) if item.item_type == "CONSUMABLE" else equipment.equip_rental(item.instance_id)
	if not success:
		status_label.text = "Item could not be applied."
		return
	_base_state = equipment.appearance_state()
	avatar.apply_state(_base_state)
	_selected_instance_id = ""
	status_label.text = "Appearance saved."
	apply_button.disabled = true
	appearance_committed.emit()
	_refresh()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
