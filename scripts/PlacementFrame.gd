class_name PlacementFrame
extends RefCounted

const EPSILON := 0.00001

var position: Vector3
var local_x_axis: Vector3
var local_y_axis: Vector3
var local_z_axis: Vector3


func _init(
		p_position: Vector3 = Vector3.ZERO,
		p_x_axis: Vector3 = Vector3.RIGHT,
		p_z_axis: Vector3 = Vector3.BACK) -> void:
	set_placement(p_position, p_x_axis, p_z_axis)


static func from_transform(transform: Transform3D) -> PlacementFrame:
	var basis := transform.basis.orthonormalized()
	return PlacementFrame.new(transform.origin, basis.x, basis.z)


func duplicate_frame() -> PlacementFrame:
	var frame := PlacementFrame.new()
	frame.position = position
	frame.local_x_axis = local_x_axis
	frame.local_y_axis = local_y_axis
	frame.local_z_axis = local_z_axis
	return frame


func to_basis() -> Basis:
	return Basis(local_x_axis, local_y_axis, local_z_axis).orthonormalized()


func to_transform() -> Transform3D:
	return Transform3D(to_basis(), position)


func set_position(new_position: Vector3) -> void:
	position = new_position


func translate(delta: Vector3) -> void:
	position += delta


func set_placement(new_position: Vector3, x_axis: Vector3, z_axis: Vector3) -> void:
	position = new_position
	local_z_axis = _safe_normalized(z_axis, Vector3.BACK)
	local_x_axis = _orthogonalized_axis(x_axis, local_z_axis, Vector3.RIGHT)
	local_y_axis = local_z_axis.cross(local_x_axis).normalized()
	_normalize_right_handed()


func set_z_axis(z_axis: Vector3) -> void:
	local_z_axis = _safe_normalized(z_axis, local_z_axis)
	local_x_axis = _orthogonalized_axis(local_x_axis, local_z_axis, _fallback_axis(local_z_axis))
	local_y_axis = local_z_axis.cross(local_x_axis).normalized()
	_normalize_right_handed()


func set_y_axis(y_axis: Vector3) -> void:
	local_y_axis = _safe_normalized(y_axis, local_y_axis)
	local_z_axis = _orthogonalized_axis(local_z_axis, local_y_axis, _fallback_axis(local_y_axis))
	local_x_axis = local_y_axis.cross(local_z_axis).normalized()
	_normalize_right_handed()


func rotated_around(pivot: Vector3, axis: Vector3, angle_radians: float) -> PlacementFrame:
	var rotation := Basis(_safe_normalized(axis, Vector3.UP), angle_radians)
	var frame := duplicate_frame()
	frame.position = pivot + rotation * (position - pivot)
	frame.local_x_axis = (rotation * local_x_axis).normalized()
	frame.local_y_axis = (rotation * local_y_axis).normalized()
	frame.local_z_axis = (rotation * local_z_axis).normalized()
	frame._normalize_right_handed()
	return frame


func scaled_around(anchor: Vector3, amount: Variant) -> PlacementFrame:
	var scale_vector := _variant_to_scale(amount)
	var frame := duplicate_frame()
	frame.position = anchor + (position - anchor) * scale_vector
	return frame


func _normalize_right_handed() -> void:
	local_x_axis = _safe_normalized(local_x_axis, Vector3.RIGHT)
	local_z_axis = _orthogonalized_axis(local_z_axis, local_x_axis, Vector3.BACK)
	local_y_axis = local_z_axis.cross(local_x_axis).normalized()
	local_z_axis = local_x_axis.cross(local_y_axis).normalized()


func _safe_normalized(axis: Vector3, fallback: Vector3) -> Vector3:
	if axis.length_squared() <= EPSILON:
		return fallback.normalized()
	return axis.normalized()


func _orthogonalized_axis(axis: Vector3, normal: Vector3, fallback: Vector3) -> Vector3:
	var projected := axis - normal * axis.dot(normal)
	if projected.length_squared() <= EPSILON:
		projected = fallback - normal * fallback.dot(normal)
	if projected.length_squared() <= EPSILON:
		projected = _fallback_axis(normal)
	return projected.normalized()


func _fallback_axis(normal: Vector3) -> Vector3:
	if abs(normal.dot(Vector3.RIGHT)) < 0.8:
		return Vector3.RIGHT
	if abs(normal.dot(Vector3.UP)) < 0.8:
		return Vector3.UP
	return Vector3.BACK


func _variant_to_scale(amount: Variant) -> Vector3:
	if amount is Vector3:
		return amount
	if amount is float or amount is int:
		return Vector3.ONE * float(amount)
	return Vector3.ONE
