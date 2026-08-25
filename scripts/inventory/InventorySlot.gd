class_name InventorySlot
extends PanelContainer

signal activated(index: int)
signal move_requested(from_index: int, to_index: int, split_half: bool)
signal dropped_outside(index: int)

var slot_index := -1
var stack: Array = []
var definition: PlaceableItemDefinition
var _preview: InventoryPreview
var _count_label: Label
var _swatch: TextureRect
var _drag_started := false
var _suppress_click_once := false


func _ready() -> void:
	custom_minimum_size = Vector2(112.0, 112.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	add_child(margin)

	_preview = InventoryPreview.new()
	margin.add_child(_preview)

	_swatch = TextureRect.new()
	_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swatch.visible = false
	margin.add_child(_swatch)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.add_theme_font_size_override("font_size", 18)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_count_label)


func set_contents(new_stack: Array, new_definition: PlaceableItemDefinition) -> void:
	stack = new_stack
	definition = new_definition
	_count_label.text = str(stack.size()) if stack.size() > 1 else ""
	tooltip_text = definition.tooltip_text(stack[0].metadata) if definition and not stack.is_empty() else ""
	var has_swatch := definition != null and not definition.swatch_path.is_empty()
	_preview.visible = definition != null and not has_swatch
	_swatch.visible = has_swatch
	_swatch.texture = ResourceLoader.load(definition.swatch_path) as Texture2D if has_swatch else null
	_preview.set_definition(definition)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if stack.is_empty():
		return null
	_drag_started = true
	var label := Label.new()
	label.text = "%s x%d" % [definition.item_name, stack.size()]
	set_drag_preview(label)
	return {"slot_index": slot_index, "split_half": Input.is_key_pressed(KEY_SHIFT)}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("slot_index")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	move_requested.emit(int(data["slot_index"]), slot_index, bool(data.get("split_half", false)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_started:
		_drag_started = false
		_suppress_click_once = true
		if not get_viewport().gui_is_drag_successful():
			dropped_outside.emit(slot_index)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _suppress_click_once:
			_suppress_click_once = false
			accept_event()
			return
		if event.shift_pressed or _drag_started:
			return
		activated.emit(slot_index)
		accept_event()


func _on_mouse_entered() -> void:
	_preview.set_hovered(true)


func _on_mouse_exited() -> void:
	_preview.set_hovered(false)
