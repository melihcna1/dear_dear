@tool
class_name PlacementItem
extends Node3D

signal placement_changed(frame: PlacementFrame)

@export var collision_preview_enabled := true
@export var valid_placement := true:
	set(value):
		valid_placement = value
		_apply_visual_feedback()

var configuration: Dictionary = {}
var definition_id := ""
var instance_id := ""
var item_metadata: Dictionary = {}
var _last_visual_feedback_valid: Variant = null

const SCALE_STEP := 0.1
const MAX_SCALE_STEPS := 3


func get_local_placement() -> PlacementFrame:
	return PlacementFrame.from_transform(transform)


func get_world_placement() -> PlacementFrame:
	return PlacementFrame.from_transform(global_transform)


func set_local_placement(frame: PlacementFrame) -> void:
	transform = _transform_with_scale(frame, scale)
	_emit_placement_changed()


func set_world_placement(frame: PlacementFrame) -> void:
	var preserved_scale := global_transform.basis.get_scale()
	global_transform = _transform_with_scale(frame, preserved_scale)
	_emit_placement_changed()


func set_position_world(world_position: Vector3) -> void:
	var frame := get_world_placement()
	frame.set_position(world_position)
	set_world_placement(frame)


func set_axis_z_world(z_axis: Vector3) -> void:
	var frame := get_world_placement()
	frame.set_z_axis(z_axis)
	set_world_placement(frame)


func set_axis_y_world(y_axis: Vector3) -> void:
	var frame := get_world_placement()
	frame.set_y_axis(y_axis)
	set_world_placement(frame)


func set_placement_world(world_position: Vector3, x_axis: Vector3, z_axis: Vector3) -> void:
	set_world_placement(PlacementFrame.new(world_position, x_axis, z_axis))


func translate_world(delta: Vector3) -> void:
	var frame := get_world_placement()
	frame.translate(delta)
	set_world_placement(frame)


func rotate_around_world(pivot: Vector3, axis: Vector3, angle_radians: float) -> void:
	set_world_placement(get_world_placement().rotated_around(pivot, axis, angle_radians))


func scale_around_world(anchor: Vector3, amount: Variant) -> void:
	var scale_vector := _variant_to_scale(amount)
	var next_scale := _clamp_scale_vector(scale * scale_vector)
	scale_vector = Vector3(
		next_scale.x / maxf(scale.x, 0.001),
		next_scale.y / maxf(scale.y, 0.001),
		next_scale.z / maxf(scale.z, 0.001)
	)
	var frame := get_world_placement().scaled_around(anchor, scale_vector)
	set_world_placement(frame)
	scale = next_scale
	_emit_placement_changed()


func duplicate_item() -> PlacementItem:
	var copy := duplicate(DUPLICATE_SIGNALS | DUPLICATE_GROUPS | DUPLICATE_SCRIPTS) as PlacementItem
	copy.configuration = configuration.duplicate(true)
	copy.definition_id = definition_id
	copy.instance_id = instance_id
	copy.item_metadata = item_metadata.duplicate(true)
	return copy


func get_visual_bounds() -> AABB:
	var data := _calculate_local_visual_bounds()
	if not data.has("valid"):
		return AABB()
	return AABB(data["min"], data["max"] - data["min"])


func center_geometry_on_pivot() -> void:
	var bounds := get_visual_bounds()
	if bounds.size.is_zero_approx():
		return
	var center := bounds.position + bounds.size * 0.5
	for child in get_children():
		if child is Node3D:
			child.position -= center


func to_save_dict(parent_instance_id := "") -> Dictionary:
	var frame := get_world_placement()
	return {
		"definition_id": definition_id,
		"instance_id": instance_id,
		"metadata": item_metadata.duplicate(true),
		"configuration": configuration.duplicate(true),
		"position": [frame.position.x, frame.position.y, frame.position.z],
		"x_axis": [frame.local_x_axis.x, frame.local_x_axis.y, frame.local_x_axis.z],
		"z_axis": [frame.local_z_axis.x, frame.local_z_axis.y, frame.local_z_axis.z],
		"scale": [scale.x, scale.y, scale.z],
		"parent_instance_id": parent_instance_id,
	}


func mate_to(target: PlacementItem, local_offset: PlacementFrame = null) -> void:
	var target_transform := target.get_world_placement().to_transform()
	if local_offset:
		set_world_placement(PlacementFrame.from_transform(target_transform * local_offset.to_transform()))
	else:
		set_world_placement(target.get_world_placement())


func recenter_pivot_to_geometry_center() -> void:
	var bounds := _calculate_local_visual_bounds()
	if not bounds.has("valid"):
		return

	var center: Vector3 = bounds["center"]
	if center.is_zero_approx():
		return

	var previous_global := global_transform
	for child in get_children():
		if child is Node3D:
			child.position -= center

	global_position = previous_global * center
	_emit_placement_changed()


func define_axes_world(forward_z_axis: Vector3, up_y_axis: Vector3) -> void:
	var z_axis := forward_z_axis.normalized() if forward_z_axis.length_squared() > 0.00001 else Vector3.BACK
	var projected_up := up_y_axis - z_axis * up_y_axis.dot(z_axis)
	var y_axis := projected_up.normalized() if projected_up.length_squared() > 0.00001 else Vector3.UP
	var x_axis := y_axis.cross(z_axis).normalized()
	set_placement_world(global_position, x_axis, z_axis)


func show_collision_overlap(overlapping: bool) -> void:
	valid_placement = not overlapping


func _transform_with_scale(frame: PlacementFrame, scale_vector: Vector3) -> Transform3D:
	return Transform3D(frame.to_basis().scaled(scale_vector), frame.position)


func _variant_to_scale(amount: Variant) -> Vector3:
	if amount is Vector3:
		return amount
	if amount is float or amount is int:
		return Vector3.ONE * float(amount)
	return Vector3.ONE


func _clamp_scale_vector(value: Vector3) -> Vector3:
	var base_scale := float(configuration.get("base_scale", 1.0))
	var range := SCALE_STEP * MAX_SCALE_STEPS
	var minimum := maxf(base_scale - range, SCALE_STEP)
	var maximum := base_scale + range
	return Vector3(
		clampf(value.x, minimum, maximum),
		clampf(value.y, minimum, maximum),
		clampf(value.z, minimum, maximum)
	)


func _emit_placement_changed() -> void:
	emit_signal("placement_changed", get_world_placement())
	_apply_visual_feedback()


func _apply_visual_feedback() -> void:
	if not is_inside_tree() or not collision_preview_enabled:
		return
	if _last_visual_feedback_valid == valid_placement:
		return
	_last_visual_feedback_valid = valid_placement

	var color := Color(0.35, 0.95, 0.55, 1.0) if valid_placement else Color(1.0, 0.25, 0.16, 1.0)
	for mesh_instance in _find_mesh_instances(self):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.65
		mesh_instance.material_override = material


func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		meshes.append_array(_find_mesh_instances(child))
	return meshes


func _calculate_local_visual_bounds() -> Dictionary:
	var bounds := {"valid": false, "min": Vector3.ZERO, "max": Vector3.ZERO}
	_collect_local_visual_bounds(self, Transform3D.IDENTITY, bounds)
	if not bounds["valid"]:
		return {}
	bounds["center"] = (bounds["min"] + bounds["max"]) * 0.5
	return bounds


func _collect_local_visual_bounds(root: Node, parent_transform: Transform3D, bounds: Dictionary) -> void:
	for child in root.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * child.transform
		if child is MeshInstance3D and child.mesh:
			for corner in _aabb_corners(child.get_aabb()):
				var point := child_transform * corner
				if not bounds["valid"]:
					bounds["min"] = point
					bounds["max"] = point
					bounds["valid"] = true
				else:
					bounds["min"] = bounds["min"].min(point)
					bounds["max"] = bounds["max"].max(point)
		_collect_local_visual_bounds(child, child_transform, bounds)


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var p := aabb.position
	var s := aabb.size
	return [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]
