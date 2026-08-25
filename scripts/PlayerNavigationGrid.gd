class_name PlayerNavigationGrid
extends RefCounted

const DEFAULT_GRID_SIZE := 0.5
const DEFAULT_EXTENT := 6.0

var grid_size := DEFAULT_GRID_SIZE
var min_world := Vector2(-DEFAULT_EXTENT, -DEFAULT_EXTENT)
var max_world := Vector2(DEFAULT_EXTENT, DEFAULT_EXTENT)
var agent_radius := 0.25
var _astar := AStarGrid2D.new()
var _region := Rect2i()
var _walkable_ids: Array[Vector2i] = []
var _blocked: Dictionary = {}


func configure(p_grid_size: float, p_min_world: Vector2, p_max_world: Vector2, p_agent_radius: float) -> void:
	grid_size = maxf(p_grid_size, 0.01)
	min_world = p_min_world
	max_world = p_max_world
	agent_radius = maxf(p_agent_radius, 0.0)
	_rebuild_empty_grid()


func rebuild(placed_items: Array, blocked_regions: Array = []) -> void:
	_rebuild_empty_grid()
	_blocked.clear()
	for item in placed_items:
		if item is PlacementItem:
			_mark_item_blocked(item)
	for region in blocked_regions:
		if region is Rect2:
			_mark_region_blocked(region)
	for id in _blocked.keys():
		if _region.has_point(id):
			_astar.set_point_solid(id, true)


func is_walkable(id: Vector2i) -> bool:
	return _region.has_point(id) and not _astar.is_point_solid(id)


func world_to_cell(position: Vector3) -> Vector2i:
	return Vector2i(roundi(position.x / grid_size), roundi(position.z / grid_size))


func cell_to_world(id: Vector2i) -> Vector3:
	return Vector3(float(id.x) * grid_size, 0.0, float(id.y) * grid_size)


func clamp_world_to_playable(position: Vector3) -> Vector3:
	var min_x := float(_region.position.x) * grid_size
	var max_x := float(_region.position.x + _region.size.x - 1) * grid_size
	var min_z := float(_region.position.y) * grid_size
	var max_z := float(_region.position.y + _region.size.y - 1) * grid_size
	return Vector3(clampf(position.x, min_x, max_x), 0.0, clampf(position.z, min_z, max_z))


func nearest_walkable_to_world(position: Vector3, reachable_from: Vector2i = Vector2i(2147483647, 2147483647)) -> Vector2i:
	var target := world_to_cell(clamp_world_to_playable(position))
	if is_walkable(target) and _is_reachable_if_needed(reachable_from, target):
		return target

	var max_radius := maxi(_region.size.x, _region.size.y)
	for radius in range(1, max_radius + 1):
		var best := Vector2i(2147483647, 2147483647)
		var best_distance := INF
		for x in range(target.x - radius, target.x + radius + 1):
			for y in range(target.y - radius, target.y + radius + 1):
				if abs(x - target.x) != radius and abs(y - target.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if not is_walkable(candidate):
					continue
				if not _is_reachable_if_needed(reachable_from, candidate):
					continue
				var distance := cell_to_world(candidate).distance_squared_to(position)
				if distance < best_distance:
					best = candidate
					best_distance = distance
		if best.x != 2147483647:
			return best
	return Vector2i(2147483647, 2147483647)


func find_path_world(from_world: Vector3, to_world: Vector3) -> PackedVector3Array:
	var start := nearest_walkable_to_world(from_world)
	if start.x == 2147483647:
		return PackedVector3Array()
	var end := nearest_walkable_to_world(to_world, start)
	if end.x == 2147483647:
		return PackedVector3Array()
	return find_path_cells(start, end)


func find_path_cells(start: Vector2i, end: Vector2i) -> PackedVector3Array:
	if not is_walkable(start) or not is_walkable(end):
		return PackedVector3Array()
	var ids := _astar.get_id_path(start, end)
	var points := PackedVector3Array()
	for id in ids:
		points.append(cell_to_world(id))
	return points


func smooth_path_world(start_world: Vector3, path: PackedVector3Array, final_world: Vector3) -> PackedVector3Array:
	var candidates := PackedVector3Array()
	for i in range(1, path.size()):
		candidates.append(path[i])
	if not candidates.is_empty():
		candidates[candidates.size() - 1] = final_world
	elif is_segment_walkable(start_world, final_world):
		candidates.append(final_world)

	var smoothed := PackedVector3Array()
	var anchor := start_world
	var index := 0
	while index < candidates.size():
		var best := index
		for next_index in range(candidates.size() - 1, index - 1, -1):
			if is_segment_walkable(anchor, candidates[next_index]):
				best = next_index
				break
		var waypoint := candidates[best]
		smoothed.append(waypoint)
		anchor = waypoint
		index = best + 1
	return smoothed


func is_segment_walkable(from_world: Vector3, to_world: Vector3) -> bool:
	var from_point := clamp_world_to_playable(from_world)
	var to_point := clamp_world_to_playable(to_world)
	var distance := Vector2(from_point.x, from_point.z).distance_to(Vector2(to_point.x, to_point.z))
	var steps := maxi(1, ceili(distance / maxf(grid_size * 0.35, 0.01)))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var point := from_point.lerp(to_point, t)
		if not is_walkable(world_to_cell(point)):
			return false
	return true


func get_walkable_ids() -> Array[Vector2i]:
	return _walkable_ids.duplicate()


func _rebuild_empty_grid() -> void:
	var min_id := Vector2i(
		ceili((min_world.x + agent_radius) / grid_size),
		ceili((min_world.y + agent_radius) / grid_size)
	)
	var max_id := Vector2i(
		floori((max_world.x - agent_radius) / grid_size),
		floori((max_world.y - agent_radius) / grid_size)
	)
	_region = Rect2i(min_id, max_id - min_id + Vector2i.ONE)
	_astar = AStarGrid2D.new()
	_astar.region = _region
	_astar.cell_size = Vector2(grid_size, grid_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	_walkable_ids.clear()
	for x in range(_region.position.x, _region.position.x + _region.size.x):
		for y in range(_region.position.y, _region.position.y + _region.size.y):
			_walkable_ids.append(Vector2i(x, y))


func _mark_item_blocked(item: PlacementItem) -> void:
	var bounds := item.get_visual_bounds()
	if bounds.size.is_zero_approx():
		return
	var world_bounds := _item_world_aabb(item, bounds).grow(agent_radius)
	var min_id := world_to_cell(Vector3(world_bounds.position.x, 0.0, world_bounds.position.z))
	var max_corner := world_bounds.position + world_bounds.size
	var max_id := world_to_cell(Vector3(max_corner.x, 0.0, max_corner.z))
	for x in range(min_id.x, max_id.x + 1):
		for y in range(min_id.y, max_id.y + 1):
			_blocked[Vector2i(x, y)] = true


func _mark_region_blocked(region: Rect2) -> void:
	var grown := region.grow(agent_radius)
	var min_id := world_to_cell(Vector3(grown.position.x, 0.0, grown.position.y))
	var max_id := world_to_cell(Vector3(grown.end.x, 0.0, grown.end.y))
	for x in range(min_id.x, max_id.x + 1):
		for y in range(min_id.y, max_id.y + 1):
			_blocked[Vector2i(x, y)] = true


func _item_world_aabb(item: PlacementItem, bounds: AABB) -> AABB:
	var has_point := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	for corner in _aabb_corners(bounds):
		var point := item.global_transform * corner
		if not has_point:
			min_point = point
			max_point = point
			has_point = true
		else:
			min_point = min_point.min(point)
			max_point = max_point.max(point)
	return AABB(min_point, max_point - min_point)


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


func _is_reachable_if_needed(start: Vector2i, end: Vector2i) -> bool:
	if start.x == 2147483647:
		return true
	if not is_walkable(start) or not is_walkable(end):
		return false
	return not _astar.get_id_path(start, end).is_empty()
