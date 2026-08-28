class_name PlacementController
extends Node3D

signal world_changed
signal quick_right_click(screen_position: Vector2)
signal market_preview_cancel_requested
signal placed_item_clicked(item: PlacementItem)
signal status_changed(message: String)

const PlacementItemScript := preload("res://scripts/PlacementItem.gd")
const PlacementGizmoScript := preload("res://scripts/PlacementGizmo.gd")
const PlacementSnapperScript := preload("res://scripts/PlacementSnapper.gd")

const GRID_SIZE := 0.5
const RAY_LENGTH := 1000.0
const PICK_RADIUS_MULTIPLIER := 1.25
const MARKET_CAMERA_DURATION := 0.45
const ITEM_SCALE_STEP := 0.1
const MAX_ITEM_SCALE_STEPS := 3

var _camera: Camera3D
var catalog: ItemCatalog
var inventory: InventoryModel
var reserved_slot := -1
var reserved_instance: ItemInstance
var _camera_focus := Vector3.ZERO
var _camera_yaw := deg_to_rad(42.0)
var _camera_pitch := deg_to_rad(-38.0)
var _camera_distance := 8.5
var _camera_orbiting := false
var _camera_orbit_dragged := false
var _placed_root: Node3D
var _preview: PlacementItem
var _market_preview_instance: ItemInstance
var _market_preview_position_locked := false
var _selected: PlacementItem
var _selection_gizmo: PlacementGizmo
var _snapper := PlacementSnapperScript.new()
var _rotation_y := 0.0
var _uniform_scale := 1.0
var _snap_to_grid := true
var _edit_mode := false
var _dragging_selected := false
var _mouse_world_position := Vector3.ZERO
var interaction_enabled := true
var _market_camera_active := false
var _camera_transitioning := false
var _camera_transition_elapsed := 0.0
var _camera_transition_duration := MARKET_CAMERA_DURATION
var _camera_transition_from := Transform3D.IDENTITY
var _camera_transition_to := Transform3D.IDENTITY
var _camera_fov_from := 75.0
var _camera_fov_to := 75.0
var _saved_camera_focus := Vector3.ZERO
var _saved_camera_yaw := 0.0
var _saved_camera_pitch := 0.0
var _saved_camera_distance := 0.0
var _saved_camera_fov := 75.0
var _excluded_ground_regions: Array = []
var _drag_start_transform := Transform3D.IDENTITY


func _ready() -> void:
	_build_world()
	_build_placement_state()


func setup(p_catalog: ItemCatalog, p_inventory: InventoryModel) -> void:
	catalog = p_catalog
	inventory = p_inventory


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	if not enabled:
		_camera_orbiting = false
		_dragging_selected = false


func set_excluded_ground_regions(regions: Array) -> void:
	_excluded_ground_regions = regions.duplicate()
	if _preview:
		_apply_preview_transform()


func is_ground_position_excluded(world_position: Vector3, radius: float = 0.0) -> bool:
	var point := Vector2(world_position.x, world_position.z)
	for region in _excluded_ground_regions:
		if region is Rect2 and region.grow(maxf(radius, 0.0)).has_point(point):
			return true
	return false


func enter_market_camera(subject: Node3D) -> void:
	if not _camera or not subject:
		return
	if not _market_camera_active:
		_saved_camera_focus = _camera_focus
		_saved_camera_yaw = _camera_yaw
		_saved_camera_pitch = _camera_pitch
		_saved_camera_distance = _camera_distance
		_saved_camera_fov = _camera.fov
	_market_camera_active = true
	_camera_orbiting = false
	_dragging_selected = false
	_start_camera_transition(_camera.global_transform, _market_camera_transform_for(subject), _camera.fov, 52.0)


func exit_market_camera() -> void:
	if not _camera or not _market_camera_active:
		return
	_market_camera_active = false
	_camera_focus = _saved_camera_focus
	_camera_yaw = _saved_camera_yaw
	_camera_pitch = _saved_camera_pitch
	_camera_distance = _saved_camera_distance
	_start_camera_transition(_camera.global_transform, _gameplay_camera_transform(), _camera.fov, _saved_camera_fov)


func begin_inventory_placement(slot_index: int) -> void:
	if not inventory or not catalog:
		return
	var item := inventory.reserve_one(slot_index)
	if not item:
		return
	reserved_slot = slot_index
	reserved_instance = item
	_rotation_y = 0.0
	_uniform_scale = _default_scale_for(item.definition_id)
	_refresh_preview_item()


func begin_market_preview(definition_id: String) -> bool:
	if not catalog:
		return false
	var definition := catalog.get_definition(definition_id)
	if not definition or not definition.is_buyable or not definition.is_placeable:
		return false
	cancel_inventory_placement()
	cancel_market_preview()
	_market_preview_instance = catalog.create_instance(definition_id, {"source": "market_preview"})
	_market_preview_position_locked = false
	_rotation_y = 0.0
	_uniform_scale = definition.placement_scale.x
	_refresh_preview_item()
	return _preview != null


func cancel_market_preview() -> void:
	_market_preview_instance = null
	_market_preview_position_locked = false
	if _preview and reserved_instance == null:
		_preview.queue_free()
		_preview = null


func commit_market_preview() -> PlacementItem:
	if not _preview or not _market_preview_instance or not _preview.valid_placement or not _market_preview_position_locked:
		return null
	var item := create_placeable(_market_preview_instance)
	item.name = "%s_%03d" % [_market_preview_instance.definition_id, _placed_root.get_child_count() + 1]
	item.valid_placement = true
	item.collision_preview_enabled = false
	_placed_root.add_child(item)
	item.global_transform = _preview.global_transform
	item.scale = _preview.scale
	_market_preview_instance = null
	_market_preview_position_locked = false
	_preview.queue_free()
	_preview = null
	_select_item(item)
	world_changed.emit()
	return item


func is_market_preview_active() -> bool:
	return _market_preview_instance != null


func get_market_preview_definition_id() -> String:
	return _market_preview_instance.definition_id if _market_preview_instance else ""


func is_market_preview_ready() -> bool:
	return is_market_preview_active() and _market_preview_position_locked and _preview != null and _preview.valid_placement


func confirm_market_preview_position() -> bool:
	if not is_market_preview_active() or not _preview or not _preview.valid_placement:
		return false
	_market_preview_position_locked = true
	return true


func cancel_inventory_placement() -> void:
	reserved_slot = -1
	reserved_instance = null
	if _preview:
		_preview.queue_free()
		_preview = null


func _process(_delta: float) -> void:
	if _camera_transitioning:
		_update_camera_transition(_delta)
	elif interaction_enabled:
		_update_camera_keyboard(_delta)
	if not _market_camera_active and not _camera_transitioning:
		_apply_camera_transform()
	if interaction_enabled:
		_update_preview_from_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	if event is InputEventMouseMotion:
		if _camera_orbiting:
			_orbit_camera(event.relative)
			_camera_orbit_dragged = true
		else:
			_mouse_world_position = _ray_to_ground(event.position)
			if _edit_mode and _dragging_selected:
				_move_selected_to_mouse()
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_market_preview_active():
				confirm_market_preview_position()
			elif _edit_mode:
				_select_or_begin_drag(event.position)
			elif _preview == null:
				_emit_placed_item_clicked(event.position)
			else:
				_place_preview()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_camera_orbiting = true
			_camera_orbit_dragged = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(0.5)
		return
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _dragging_selected:
				if _selected and not _selected.valid_placement:
					_selected.global_transform = _drag_start_transform
					_selected.valid_placement = true
				else:
					world_changed.emit()
			_dragging_selected = false
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not _camera_orbit_dragged:
				quick_right_click.emit(event.position)
			_camera_orbiting = false
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_rotate_preview(-15.0)
			KEY_E:
				_rotate_preview(15.0)
			KEY_G:
				_snap_to_grid = not _snap_to_grid
			KEY_TAB:
				_set_edit_mode(not _edit_mode)
			KEY_ESCAPE:
				if is_market_preview_active():
					cancel_market_preview()
					market_preview_cancel_requested.emit()
				else:
					cancel_inventory_placement()
			KEY_X:
				_adjust_active_scale(ITEM_SCALE_STEP)
			KEY_Z:
				_adjust_active_scale(-ITEM_SCALE_STEP)
			KEY_DELETE, KEY_BACKSPACE:
				_delete_selected()
			KEY_D:
				if event.ctrl_pressed:
					_duplicate_selected()
			KEY_P:
				pick_up_selected()


func _build_world() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	add_child(_camera)
	_apply_camera_transform()

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	light.light_energy = 2.5
	add_child(light)

	var grid := MeshInstance3D.new()
	grid.name = "PlacementGrid"
	grid.mesh = _make_grid_mesh(12, GRID_SIZE)
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.vertex_color_use_as_albedo = true
	grid.material_override = grid_material
	add_child(grid)

	var ground := MeshInstance3D.new()
	ground.name = "SnapSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.18, 0.2, 1.0)
	material.roughness = 0.85
	ground.material_override = material
	add_child(ground)


func _build_placement_state() -> void:
	_placed_root = Node3D.new()
	_placed_root.name = "PlacedItems"
	add_child(_placed_root)

	_selection_gizmo = PlacementGizmoScript.new() as PlacementGizmo
	_selection_gizmo.name = "SelectionPlacementGizmo"
	_selection_gizmo.axis_length = 1.35
	_selection_gizmo.visible = false
	add_child(_selection_gizmo)


func _refresh_preview_item() -> void:
	if _preview:
		_preview.queue_free()
	var preview_instance := _market_preview_instance if _market_preview_instance else reserved_instance
	if not preview_instance:
		return
	_preview = create_placeable(preview_instance)
	_preview.name = "PlacementPreview"
	_preview.collision_preview_enabled = true
	_preview._last_visual_feedback_valid = null
	add_child(_preview)
	_preview.visible = not _edit_mode
	_apply_preview_transform()


func _update_preview_from_mouse() -> void:
	if not _preview or _edit_mode or (is_market_preview_active() and _market_preview_position_locked):
		return

	var viewport := get_viewport()
	if viewport:
		_mouse_world_position = _ray_to_ground(viewport.get_mouse_position())

	_apply_preview_transform()


func _apply_preview_transform() -> void:
	var position := _mouse_world_position
	if _snap_to_grid:
		position = _snapper.snap_position(position, PlacementSnapper.SnapMode.GRID, {"grid_size": GRID_SIZE})

	_preview.scale = Vector3.ONE * _uniform_scale
	var rotation := Basis(Vector3.UP, _rotation_y)
	var half_height := _preview_height_offset()
	var surface_height := _placement_surface_height(position, _preview, null)
	_preview.set_placement_world(Vector3(position.x, surface_height + half_height, position.z), rotation.x, rotation.z)
	_preview.valid_placement = not is_ground_position_excluded(position, _placement_radius(_preview))


func _place_preview() -> void:
	if not _preview or not _preview.valid_placement or not reserved_instance:
		return
	var committed := inventory.commit_reserved(reserved_slot, reserved_instance.instance_id)
	if not committed:
		cancel_inventory_placement()
		return
	var item := create_placeable(committed)
	item.name = "%s_%03d" % [committed.definition_id, _placed_root.get_child_count() + 1]
	item.valid_placement = true
	item.collision_preview_enabled = false
	_placed_root.add_child(item)
	item.global_transform = _preview.global_transform
	item.scale = _preview.scale
	_select_item(item)
	world_changed.emit()
	reserved_instance = inventory.reserve_one(reserved_slot)
	if reserved_instance:
		_refresh_preview_item()
	else:
		cancel_inventory_placement()


func _select_or_begin_drag(screen_position: Vector2) -> void:
	var item := _pick_placed_item(screen_position)
	if item:
		_select_item(item)
		_drag_start_transform = item.global_transform
		_dragging_selected = true
		_move_selected_to_mouse()
	else:
		_clear_selection()


func _select_item(item: PlacementItem) -> void:
	_selected = item
	_selection_gizmo.target = item
	_selection_gizmo.visible = true


func _clear_selection() -> void:
	_selected = null
	_dragging_selected = false
	_selection_gizmo.target = null
	_selection_gizmo.visible = false


func is_item_edit_locked(item: PlacementItem) -> bool:
	if not item:
		return false
	var cooking: Variant = item.item_metadata.get("cooking", {})
	return cooking is Dictionary and not cooking.is_empty()


func _delete_selected() -> void:
	if not _selected:
		return
	if is_item_edit_locked(_selected):
		status_changed.emit("Collect Food Before Deleting This Stove")
		return
	_selected.item_metadata.erase("gardening")
	_selected.queue_free()
	_clear_selection()
	world_changed.emit()


func _duplicate_selected() -> void:
	if not _selected:
		return
	if is_item_edit_locked(_selected):
		status_changed.emit("Collect Food Before Duplicating This Stove")
		return

	var copy := _selected.duplicate_item()
	copy.instance_id = ItemInstance.new(copy.definition_id, copy.item_metadata).instance_id
	copy.item_metadata.erase("gardening")
	copy.item_metadata.erase("cooking")
	copy.name = "%s_copy" % _selected.name
	_placed_root.add_child(copy)
	copy.global_transform = _selected.global_transform
	copy.translate_world(Vector3(GRID_SIZE, 0.0, GRID_SIZE))
	_select_item(copy)
	world_changed.emit()


func pick_up_selected() -> bool:
	if not _selected or not inventory:
		return false
	if is_item_edit_locked(_selected):
		status_changed.emit("Collect Food Before Picking Up This Stove")
		return false
	var metadata := _selected.item_metadata.duplicate(true)
	metadata.erase("gardening")
	var item := ItemInstance.new(_selected.definition_id, metadata, _selected.instance_id)
	if not inventory.add_instance(item, catalog):
		return false
	_selected.queue_free()
	_clear_selection()
	world_changed.emit()
	return true


func _set_edit_mode(enabled: bool) -> void:
	_edit_mode = enabled
	_dragging_selected = false
	if _preview:
		_preview.visible = not _edit_mode


func _move_selected_to_mouse() -> void:
	if not _selected:
		return

	var position := _mouse_world_position
	if _snap_to_grid:
		position = _snapper.snap_position(position, PlacementSnapper.SnapMode.GRID, {"grid_size": GRID_SIZE})

	var half_height := _item_height_offset(_selected)
	var surface_height := _placement_surface_height(position, _selected, _selected)
	_selected.set_position_world(Vector3(position.x, surface_height + half_height, position.z))
	_selected.valid_placement = not is_ground_position_excluded(position, _placement_radius(_selected))


func _update_camera_keyboard(delta: float) -> void:
	if not _camera:
		return

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if (Input.is_key_pressed(KEY_D) and not Input.is_key_pressed(KEY_CTRL)) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_key_pressed(KEY_R):
		input.y += 1.0
	if Input.is_key_pressed(KEY_F):
		input.y -= 1.0

	if input.is_zero_approx():
		return

	input = input.normalized()
	var speed := 5.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed = 10.0

	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.00001 else Vector3.FORWARD
	var right := _camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.00001 else Vector3.RIGHT

	_camera_focus += (right * input.x + forward * -input.z + Vector3.UP * input.y) * speed * delta


func _orbit_camera(relative_motion: Vector2) -> void:
	_camera_yaw -= relative_motion.x * 0.008
	_camera_pitch = clampf(_camera_pitch - relative_motion.y * 0.008, deg_to_rad(-82.0), deg_to_rad(-12.0))


func _zoom_camera(delta_distance: float) -> void:
	_camera_distance = clampf(_camera_distance + delta_distance, 2.5, 24.0)


func _apply_camera_transform() -> void:
	if not _camera:
		return
	_camera.global_transform = _gameplay_camera_transform()


func _gameplay_camera_transform() -> Transform3D:
	var direction := Vector3(
		sin(_camera_yaw) * cos(_camera_pitch),
		-sin(_camera_pitch),
		cos(_camera_yaw) * cos(_camera_pitch)
	)
	var transform := Transform3D.IDENTITY
	transform.origin = _camera_focus + direction * _camera_distance
	return transform.looking_at(_camera_focus, Vector3.UP)


func _market_camera_transform_for(subject: Node3D) -> Transform3D:
	var subject_position := subject.global_position
	# PlayerController's origin is already at the avatar's vertical center. Keep
	# the full character in frame while reserving the right side for market UI.
	var subject_center := subject_position
	var camera_position := subject_position + Vector3(-1.55, 0.75, 2.7)
	var transform := Transform3D.IDENTITY
	transform.origin = camera_position
	var centered_transform := transform.looking_at(subject_center, Vector3.UP)
	var framing_target := subject_center + centered_transform.basis.x * 1.15
	return transform.looking_at(framing_target, Vector3.UP)


func _start_camera_transition(from_transform: Transform3D, to_transform: Transform3D, from_fov: float, to_fov: float) -> void:
	_camera_transitioning = true
	_camera_transition_elapsed = 0.0
	_camera_transition_duration = MARKET_CAMERA_DURATION
	_camera_transition_from = from_transform
	_camera_transition_to = to_transform
	_camera_fov_from = from_fov
	_camera_fov_to = to_fov


func _update_camera_transition(delta: float) -> void:
	_camera_transition_elapsed += delta
	var raw_t := clampf(_camera_transition_elapsed / maxf(_camera_transition_duration, 0.001), 0.0, 1.0)
	var t := raw_t * raw_t * (3.0 - 2.0 * raw_t)
	_camera.global_transform = _interpolate_transform(_camera_transition_from, _camera_transition_to, t)
	_camera.fov = lerpf(_camera_fov_from, _camera_fov_to, t)
	if raw_t >= 1.0:
		_camera_transitioning = false
		_camera.global_transform = _camera_transition_to
		_camera.fov = _camera_fov_to


func _interpolate_transform(from_transform: Transform3D, to_transform: Transform3D, t: float) -> Transform3D:
	var result := Transform3D.IDENTITY
	result.origin = from_transform.origin.lerp(to_transform.origin, t)
	var from_quat := from_transform.basis.get_rotation_quaternion()
	var to_quat := to_transform.basis.get_rotation_quaternion()
	result.basis = Basis(from_quat.slerp(to_quat, t))
	return result


func _rotate_preview(degrees: float) -> void:
	if _edit_mode and _selected:
		_selected.rotate_around_world(_selected.global_position, Vector3.UP, deg_to_rad(degrees))
		_selected.valid_placement = true
		world_changed.emit()
	else:
		_rotation_y += deg_to_rad(degrees)


func _adjust_scale(delta: float) -> void:
	var definition_id := (
		_market_preview_instance.definition_id
		if _market_preview_instance
		else reserved_instance.definition_id if reserved_instance else ""
	)
	_uniform_scale = clamp_item_scale(_uniform_scale + delta, definition_id)


func _adjust_active_scale(delta: float) -> void:
	if _edit_mode and _selected:
		var next_scale := clamp_item_scale(_selected.scale.x + delta, _selected.definition_id)
		var scale_factor := next_scale / maxf(_selected.scale.x, 0.001)
		_selected.scale_around_world(_selected.global_position, scale_factor)
		var position := _selected.global_position
		var surface_height := _placement_surface_height(position, _selected, _selected)
		_selected.set_position_world(Vector3(position.x, surface_height + _item_height_offset(_selected), position.z))
		_selected.valid_placement = true
		world_changed.emit()
	else:
		_adjust_scale(delta)


func _placement_surface_height(position: Vector3, moving_item: PlacementItem, ignored_item: PlacementItem) -> float:
	var height := 0.0
	var moving_radius := _placement_radius(moving_item)

	for child in _placed_root.get_children():
		if child is PlacementItem:
			if child == ignored_item:
				continue

			var horizontal_distance := Vector2(position.x, position.z).distance_to(Vector2(child.global_position.x, child.global_position.z))
			var support_radius := (_placement_radius(child) + moving_radius) * 0.55
			if horizontal_distance <= support_radius:
				height = maxf(height, child.global_position.y + _item_height_offset(child))

	return height


func _pick_placed_item(screen_position: Vector2) -> PlacementItem:
	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	var best_item: PlacementItem = null
	var best_distance := INF

	for child in _placed_root.get_children():
		if not (child is PlacementItem):
			continue

		var item := child as PlacementItem
		var radius := _placement_radius(item) * PICK_RADIUS_MULTIPLIER
		var hit_distance := _ray_sphere_distance(ray_origin, ray_direction, item.global_position, radius)
		if hit_distance >= 0.0 and hit_distance < best_distance:
			best_item = item
			best_distance = hit_distance

	return best_item


func _emit_placed_item_clicked(screen_position: Vector2) -> void:
	var item := _pick_placed_item(screen_position)
	if item:
		placed_item_clicked.emit(item)


func _ray_sphere_distance(origin: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var offset := origin - center
	var a := direction.dot(direction)
	var b := 2.0 * offset.dot(direction)
	var c := offset.dot(offset) - radius * radius
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0

	var distance := (-b - sqrt(discriminant)) / (2.0 * a)
	if distance >= 0.0:
		return distance
	return (-b + sqrt(discriminant)) / (2.0 * a)


func _placement_radius(item: PlacementItem) -> float:
	if not item:
		return 0.1
	var bounds := item.get_visual_bounds()
	var horizontal := maxf(bounds.size.x * item.scale.x, bounds.size.z * item.scale.z)
	return maxf(horizontal * 0.5, 0.1)


func _preview_height_offset() -> float:
	return _item_height_offset(_preview)


func _item_height_offset(item: PlacementItem) -> float:
	if not item:
		return 0.0
	var bounds := item.get_visual_bounds()
	return maxf(bounds.size.y * 0.5 * item.scale.y, 0.05)


func _ray_to_ground(screen_position: Vector2) -> Vector3:
	if not _camera:
		return Vector3.ZERO

	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if abs(direction.y) <= 0.00001:
		return _mouse_world_position

	var distance := -origin.y / direction.y
	if distance < 0.0 or distance > RAY_LENGTH:
		return _mouse_world_position
	return origin + direction * distance


func create_placeable(instance: ItemInstance) -> PlacementItem:
	if not instance or not catalog:
		return null
	var definition := catalog.get_definition(instance.definition_id)
	if not definition:
		push_warning("Skipping placeable with missing definition: %s" % instance.definition_id)
		return null
	var item := PlacementItemScript.new() as PlacementItem
	item.name = definition.item_name
	item.definition_id = instance.definition_id
	item.instance_id = instance.instance_id
	item.item_metadata = instance.metadata.duplicate(true)
	item.collision_preview_enabled = false
	var model := definition.create_model()
	model.name = "Model"
	item.add_child(model)
	item.configuration = {
		"grid_size": definition.grid_size,
		"rotation_step_degrees": definition.rotation_step_degrees,
		"base_scale": definition.placement_scale.x,
	}
	item.scale = definition.placement_scale
	item.center_geometry_on_pivot()
	return item


func get_placed_items() -> Array:
	return _collect_placed(_placed_root)


func get_grid_size() -> float:
	return GRID_SIZE


func get_playable_bounds() -> AABB:
	var extent := 12.0 * GRID_SIZE
	return AABB(Vector3(-extent, 0.0, -extent), Vector3(extent * 2.0, 0.0, extent * 2.0))


func get_camera() -> Camera3D:
	return _camera


func screen_to_ground(screen_position: Vector2) -> Vector3:
	return _ray_to_ground(screen_position)


func clear_placed_items() -> void:
	for child in _placed_root.get_children():
		child.queue_free()
	_clear_selection()


func load_world(entries: Array) -> void:
	clear_placed_items()
	var by_id: Dictionary = {}
	for data in entries:
		var instance := ItemInstance.from_dict({
			"definition_id": data.get("definition_id", ""),
			"instance_id": data.get("instance_id", ""),
			"metadata": data.get("metadata", {}),
		})
		var item := create_placeable(instance)
		if not item:
			continue
		item.configuration.merge(data.get("configuration", {}), true)
		_placed_root.add_child(item)
		item.set_placement_world(_array_to_vec3(data["position"]), _array_to_vec3(data["x_axis"]), _array_to_vec3(data["z_axis"]))
		item.scale = clamp_item_scale_vector(
			_array_to_vec3(data.get("scale", [1, 1, 1])),
			item.definition_id
		)
		by_id[item.instance_id] = item
	for data in entries:
		var parent_id := str(data.get("parent_instance_id", ""))
		var item: PlacementItem = by_id.get(str(data.get("instance_id", "")))
		var parent: PlacementItem = by_id.get(parent_id)
		if item and parent:
			item.reparent(parent, true)
	world_changed.emit()


func _collect_placed(root: Node) -> Array:
	var result: Array = []
	for child in root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is PlacementItem:
			result.append(child)
			result.append_array(_collect_placed(child))
	return result


func _array_to_vec3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _default_scale_for(definition_id: String) -> float:
	var definition := catalog.get_definition(definition_id) if catalog else null
	return definition.placement_scale.x if definition else 1.0


func clamp_item_scale(value: float, definition_id: String) -> float:
	var base_scale := _default_scale_for(definition_id)
	var range := ITEM_SCALE_STEP * MAX_ITEM_SCALE_STEPS
	return clampf(value, maxf(base_scale - range, ITEM_SCALE_STEP), base_scale + range)


func clamp_item_scale_vector(value: Vector3, definition_id: String) -> Vector3:
	var definition := catalog.get_definition(definition_id) if catalog else null
	var base := definition.placement_scale if definition else Vector3.ONE
	var range := ITEM_SCALE_STEP * MAX_ITEM_SCALE_STEPS
	return Vector3(
		clampf(value.x, maxf(base.x - range, ITEM_SCALE_STEP), base.x + range),
		clampf(value.y, maxf(base.y - range, ITEM_SCALE_STEP), base.y + range),
		clampf(value.z, maxf(base.z - range, ITEM_SCALE_STEP), base.z + range)
	)


func _make_grid_mesh(extent: int, step: float) -> ImmediateMesh:
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	var color := Color(0.36, 0.39, 0.43, 1.0)
	for i in range(-extent, extent + 1):
		var v := i * step
		grid.surface_set_color(color)
		grid.surface_add_vertex(Vector3(v, 0.01, -extent * step))
		grid.surface_add_vertex(Vector3(v, 0.01, extent * step))
		grid.surface_add_vertex(Vector3(-extent * step, 0.01, v))
		grid.surface_add_vertex(Vector3(extent * step, 0.01, v))
	grid.surface_end()
	return grid
