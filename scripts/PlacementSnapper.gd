class_name PlacementSnapper
extends RefCounted

enum SnapMode {
	VERTEX,
	SURFACE,
	EDGE,
	GRID,
	PIVOT,
}

var grid_size := 1.0


func snap_position(position: Vector3, mode: int, context: Dictionary = {}) -> Vector3:
	match mode:
		SnapMode.GRID:
			return snap_to_grid(position, context.get("grid_size", grid_size))
		SnapMode.PIVOT:
			return context.get("pivot", position)
		SnapMode.VERTEX:
			return _nearest_point(position, context.get("vertices", []))
		SnapMode.EDGE:
			return _nearest_edge_point(position, context.get("edges", []))
		SnapMode.SURFACE:
			return _surface_point(position, context)
		_:
			return position


func snap_to_grid(position: Vector3, size: float = -1.0) -> Vector3:
	if size < 0.0:
		size = grid_size
	if size <= 0.0:
		return position
	return Vector3(
		roundf(position.x / size) * size,
		roundf(position.y / size) * size,
		roundf(position.z / size) * size
	)


func _nearest_point(position: Vector3, points: Array) -> Vector3:
	if points.is_empty():
		return position

	var best: Vector3 = points[0]
	var best_distance := position.distance_squared_to(best)
	for point in points:
		var distance := position.distance_squared_to(point)
		if distance < best_distance:
			best = point
			best_distance = distance
	return best


func _nearest_edge_point(position: Vector3, edges: Array) -> Vector3:
	if edges.is_empty():
		return position

	var best := position
	var best_distance := INF
	for edge in edges:
		if not (edge is Array) or edge.size() < 2:
			continue
		var point := _closest_point_on_segment(position, edge[0], edge[1])
		var distance := position.distance_squared_to(point)
		if distance < best_distance:
			best = point
			best_distance = distance
	return best


func _surface_point(position: Vector3, context: Dictionary) -> Vector3:
	var surface_origin: Vector3 = context.get("origin", position)
	var surface_normal: Vector3 = context.get("normal", Vector3.UP)
	if surface_normal.length_squared() <= 0.00001:
		return position

	var normal := surface_normal.normalized()
	var distance := normal.dot(position - surface_origin)
	return position - normal * distance


func _closest_point_on_segment(position: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.00001:
		return a

	var t := clampf((position - a).dot(segment) / length_squared, 0.0, 1.0)
	return a + segment * t
