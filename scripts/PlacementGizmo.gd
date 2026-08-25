@tool
class_name PlacementGizmo
extends MeshInstance3D

@export var target: Node3D
@export var axis_length := 1.5
@export var show_bounding_box := true

var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	material_override = _material
	_rebuild()


func _process(_delta: float) -> void:
	if target:
		global_transform = target.global_transform
	_rebuild()


func _rebuild() -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	_add_line(immediate, Vector3.ZERO, Vector3.RIGHT * axis_length, Color.RED)
	_add_line(immediate, Vector3.ZERO, Vector3.UP * axis_length, Color.GREEN)
	_add_line(immediate, Vector3.ZERO, Vector3.BACK * axis_length, Color(0.18, 0.45, 1.0, 1.0))

	if show_bounding_box and target:
		_add_bounding_box(immediate, _target_local_bounds(), Color(1.0, 0.85, 0.2, 1.0))

	immediate.surface_end()
	mesh = immediate


func _add_line(immediate: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	immediate.surface_set_color(color)
	immediate.surface_add_vertex(from)
	immediate.surface_add_vertex(to)


func _add_bounding_box(immediate: ImmediateMesh, bounds: AABB, color: Color) -> void:
	if bounds.size.is_zero_approx():
		return

	var p := bounds.position
	var s := bounds.size
	var corners := [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(s.x, s.y, s.z),
		p + Vector3(0.0, s.y, s.z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]

	for edge in edges:
		_add_line(immediate, corners[edge[0]], corners[edge[1]], color)


func _target_local_bounds() -> AABB:
	var meshes := _find_mesh_instances(target)
	if meshes.is_empty():
		return AABB()

	var has_point := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	var to_target := target.global_transform.affine_inverse()

	for mesh_instance in meshes:
		var aabb := mesh_instance.get_aabb()
		var mesh_to_target := to_target * mesh_instance.global_transform
		for corner in _aabb_corners(aabb):
			var point := mesh_to_target * corner
			if not has_point:
				min_point = point
				max_point = point
				has_point = true
			else:
				min_point = min_point.min(point)
				max_point = max_point.max(point)

	return AABB(min_point, max_point - min_point)


func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if not root:
		return meshes

	for child in root.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		meshes.append_array(_find_mesh_instances(child))
	return meshes


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
