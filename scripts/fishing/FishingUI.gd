class_name FishingUI
extends CanvasLayer

signal replace_slot_requested(slot_index: int)
signal reward_cancelled

const TRACK_SIZE := Vector2(84.0, 300.0)

var prompt_panel: PanelContainer
var prompt_label: Label
var result_preview: InventoryPreview
var minigame_panel: PanelContainer
var fish_name_label: Label
var fish_preview: InventoryPreview
var track: Control
var catch_bar: ColorRect
var fish_marker: ColorRect
var progress_bar: ProgressBar
var replacement_panel: PanelContainer
var replacement_title: Label
var replacement_list: VBoxContainer
var replacement_confirmation: ConfirmationDialog

var _replacement_inventory: InventoryModel
var _replacement_catalog: ItemCatalog
var _confirmation_slot := -1


func _ready() -> void:
	layer = 20
	_build_prompt()
	_build_minigame()
	_build_replacement()


func show_prompt(message: String) -> void:
	prompt_label.text = message
	result_preview.visible = false
	prompt_panel.visible = true


func show_waiting() -> void:
	minigame_panel.visible = false
	show_prompt("Waiting for a bite...\nPressing now will reel in too early")


func show_bite() -> void:
	show_prompt("!  BITE  !\nPress Space or left mouse")


func show_minigame(definition: PlaceableItemDefinition, model: FishingMinigameModel) -> void:
	prompt_panel.visible = false
	replacement_panel.visible = false
	fish_name_label.text = definition.item_name if definition else "Fish"
	if fish_preview:
		fish_preview.set_definition(definition)
	minigame_panel.visible = true
	update_minigame(model)


func update_minigame(model: FishingMinigameModel) -> void:
	if not model or not minigame_panel.visible:
		return
	var catch_height := TRACK_SIZE.y * FishingMinigameModel.BAR_HEIGHT
	var catch_center_y := (1.0 - model.bar_center) * TRACK_SIZE.y
	catch_bar.position = Vector2(4.0, clampf(catch_center_y - catch_height * 0.5, 0.0, TRACK_SIZE.y - catch_height))
	catch_bar.size = Vector2(TRACK_SIZE.x - 8.0, catch_height)
	var fish_y := (1.0 - model.fish_position) * TRACK_SIZE.y
	fish_marker.position = Vector2(TRACK_SIZE.x * 0.5 - 10.0, clampf(fish_y - 6.0, 0.0, TRACK_SIZE.y - 12.0))
	progress_bar.value = model.progress * 100.0


func show_result(message: String, definition: PlaceableItemDefinition = null) -> void:
	minigame_panel.visible = false
	replacement_panel.visible = false
	if replacement_confirmation.visible:
		replacement_confirmation.hide()
	prompt_label.text = message
	result_preview.visible = definition != null
	if definition:
		result_preview.set_definition(definition)
	prompt_panel.visible = true


func show_replacement(
		fish_definition: PlaceableItemDefinition,
		inventory: InventoryModel,
		catalog: ItemCatalog) -> void:
	_replacement_inventory = inventory
	_replacement_catalog = catalog
	prompt_panel.visible = false
	minigame_panel.visible = false
	replacement_panel.visible = true
	replacement_title.text = "Inventory full\nChoose a stack to discard and keep %s" % fish_definition.item_name
	_clear_children(replacement_list)
	for i in inventory.slots.size():
		var stack := inventory.get_slot_stack(i)
		if stack.is_empty():
			continue
		var definition := catalog.get_definition(stack[0].definition_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		replacement_list.add_child(row)
		var label := Label.new()
		label.text = "Slot %d: %s x%d" % [i + 1, definition.item_name if definition else stack[0].definition_id, stack.size()]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var replace_button := Button.new()
		replace_button.text = "Discard & Keep Fish"
		replace_button.pressed.connect(_request_replacement_confirmation.bind(i))
		row.add_child(replace_button)


func hide_all() -> void:
	prompt_panel.visible = false
	minigame_panel.visible = false
	replacement_panel.visible = false
	if replacement_confirmation.visible:
		replacement_confirmation.hide()


func _build_prompt() -> void:
	prompt_panel = PanelContainer.new()
	prompt_panel.name = "FishingPrompt"
	prompt_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	prompt_panel.position = Vector2(-210.0, 22.0)
	prompt_panel.custom_minimum_size = Vector2(420.0, 72.0)
	prompt_panel.visible = false
	add_child(prompt_panel)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_panel.add_child(layout)
	var preview_center := CenterContainer.new()
	preview_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview_center)
	result_preview = InventoryPreview.new()
	result_preview.custom_minimum_size = Vector2(72.0, 72.0)
	result_preview.visible = false
	preview_center.add_child(result_preview)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(prompt_label)


func _build_minigame() -> void:
	minigame_panel = PanelContainer.new()
	minigame_panel.name = "FishingMinigame"
	minigame_panel.set_anchors_preset(Control.PRESET_CENTER)
	minigame_panel.position = Vector2(-110.0, -230.0)
	minigame_panel.custom_minimum_size = Vector2(220.0, 460.0)
	minigame_panel.visible = false
	add_child(minigame_panel)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 8)
	minigame_panel.add_child(layout)
	fish_name_label = Label.new()
	fish_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fish_name_label.add_theme_font_size_override("font_size", 22)
	fish_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(fish_name_label)
	var preview_center := CenterContainer.new()
	preview_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview_center)
	fish_preview = InventoryPreview.new()
	fish_preview.custom_minimum_size = Vector2(76.0, 76.0)
	preview_center.add_child(fish_preview)
	var track_center := CenterContainer.new()
	track_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(track_center)
	track = Control.new()
	track.custom_minimum_size = TRACK_SIZE
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_center.add_child(track)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.09, 0.12, 0.96)
	background.position = Vector2.ZERO
	background.size = TRACK_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(background)
	catch_bar = ColorRect.new()
	catch_bar.color = Color(0.28, 0.86, 0.42, 0.75)
	catch_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(catch_bar)
	fish_marker = ColorRect.new()
	fish_marker.color = Color(1.0, 0.72, 0.18, 1.0)
	fish_marker.size = Vector2(20.0, 12.0)
	fish_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fish_marker)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.custom_minimum_size = Vector2(170.0, 24.0)
	var progress_center := CenterContainer.new()
	progress_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_center.add_child(progress_bar)
	layout.add_child(progress_center)
	var help := Label.new()
	help.text = "Hold Space / Left Mouse to rise\nRelease to fall  •  Esc to cancel"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(help)


func _build_replacement() -> void:
	replacement_panel = PanelContainer.new()
	replacement_panel.name = "FishingRewardReplacement"
	replacement_panel.set_anchors_preset(Control.PRESET_CENTER)
	replacement_panel.position = Vector2(-270.0, -260.0)
	replacement_panel.custom_minimum_size = Vector2(540.0, 520.0)
	replacement_panel.visible = false
	add_child(replacement_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	replacement_panel.add_child(layout)
	replacement_title = Label.new()
	replacement_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	replacement_title.add_theme_font_size_override("font_size", 21)
	layout.add_child(replacement_title)
	var warning := Label.new()
	warning.text = "The selected stack will be permanently discarded."
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.modulate = Color(1.0, 0.72, 0.45, 1.0)
	layout.add_child(warning)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	replacement_list = VBoxContainer.new()
	replacement_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replacement_list.add_theme_constant_override("separation", 6)
	scroll.add_child(replacement_list)
	var cancel_button := Button.new()
	cancel_button.text = "Release Fish"
	cancel_button.pressed.connect(reward_cancelled.emit)
	layout.add_child(cancel_button)
	replacement_confirmation = ConfirmationDialog.new()
	replacement_confirmation.title = "Discard inventory stack?"
	replacement_confirmation.confirmed.connect(_confirm_replacement)
	add_child(replacement_confirmation)


func _request_replacement_confirmation(slot_index: int) -> void:
	var stack := _replacement_inventory.get_slot_stack(slot_index) if _replacement_inventory else []
	if stack.is_empty():
		return
	var definition := _replacement_catalog.get_definition(stack[0].definition_id) if _replacement_catalog else null
	_confirmation_slot = slot_index
	replacement_confirmation.dialog_text = "Discard %s x%d and keep the caught fish?" % [
		definition.item_name if definition else stack[0].definition_id,
		stack.size(),
	]
	replacement_confirmation.popup_centered(Vector2i(420, 150))


func _confirm_replacement() -> void:
	if _confirmation_slot >= 0:
		replace_slot_requested.emit(_confirmation_slot)
	_confirmation_slot = -1


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
