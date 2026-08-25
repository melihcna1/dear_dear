class_name InventoryPreview
extends SubViewportContainer

var _viewport: SubViewport
var _model_root: Node3D
var _camera: Camera3D
var _active := false
var _rotation_speed := 0.45
var _padding := 1.35


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.size = Vector2i(192, 192)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	add_child(_viewport)

	_model_root = Node3D.new()
	_model_root.name = "ModelRoot"
	_viewport.add_child(_model_root)

	_camera = Camera3D.new()
	_camera.current = true
	_viewport.add_child(_camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	light.light_energy = 2.2
	_viewport.add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.0, 2.0)
	fill.light_energy = 1.2
	fill.omni_range = 10.0
	_viewport.add_child(fill)


func _process(delta: float) -> void:
	if _active:
		_model_root.rotate_y(delta * _rotation_speed)


func set_definition(definition: PlaceableItemDefinition) -> void:
	if not is_node_ready():
		await ready
	for child in _model_root.get_children():
		child.queue_free()
	if not definition:
		return

	_rotation_speed = definition.preview_rotation_speed
	_padding = definition.preview_camera_padding
	var model := definition.create_model()
	_model_root.add_child(model)
	call_deferred("_fit_model")


func set_hovered(hovered: bool) -> void:
	_active = hovered


func _fit_model() -> void:
	var bounds := _calculate_bounds(_model_root, Transform3D.IDENTITY)
	if bounds.size.is_zero_approx():
		_camera.position = Vector3(2.0, 1.5, 2.0)
		_camera.look_at(Vector3.ZERO)
		return

	var center := bounds.position + bounds.size * 0.5
	for child in _model_root.get_children():
		if child is Node3D:
			child.position -= center

	var radius := maxf(bounds.size.length() * 0.5, 0.1)
	var distance := radius * _padding / tan(deg_to_rad(_camera.fov * 0.5))
	_camera.position = Vector3(distance * 0.8, distance * 0.55, distance)
	_camera.near = maxf(distance * 0.01, 0.01)
	_camera.far = maxf(distance * 8.0, 20.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _calculate_bounds(root: Node, parent_transform: Transform3D) -> AABB:
	var has_bounds := false
	var result := AABB()
	for child in root.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * child.transform
		if child is MeshInstance3D and child.mesh:
			var transformed: AABB = child_transform * child.get_aabb()
			result = transformed if not has_bounds else result.merge(transformed)
			has_bounds = true
		var nested := _calculate_bounds(child, child_transform)
		if not nested.size.is_zero_approx():
			result = nested if not has_bounds else result.merge(nested)
			has_bounds = true
	return result
