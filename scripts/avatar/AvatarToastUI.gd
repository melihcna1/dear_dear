class_name AvatarToastUI
extends CanvasLayer

var panel: PanelContainer
var label: Label
var _timer := 0.0


func _ready() -> void:
	layer = 30
	panel = PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-230.0, 22.0)
	panel.custom_minimum_size = Vector2(460.0, 54.0)
	add_child(panel)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)


func show_message(message: String, seconds := 4.0) -> void:
	label.text = message
	panel.visible = true
	_timer = seconds


func _process(delta: float) -> void:
	if _timer <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		panel.visible = false
