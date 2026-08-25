class_name PlayerController
extends CharacterBody3D

signal destination_reached(world_position: Vector3)
signal destination_failed(requested_world_position: Vector3)

const PlayerNavigationGridScript := preload("res://scripts/PlayerNavigationGrid.gd")
const CharacterAvatarScript := preload("res://scripts/avatar/CharacterAvatar.gd")

const SENTINEL_CELL := Vector2i(2147483647, 2147483647)

@export var move_speed := 2.35
@export var turn_speed := 10.0
@export var agent_radius := 0.25
@export var agent_height := 1.35
@export var waypoint_tolerance := 0.07

var placement: PlacementController
var navigation := PlayerNavigationGridScript.new() as PlayerNavigationGrid
var _path := PackedVector3Array()
var _path_index := 0
var _destination_world := Vector3.ZERO
var _has_destination := false
var _destination_marker: MeshInstance3D
var _collision_proxy_root: Node3D
var _static_navigation_regions: Array = []
var avatar: CharacterAvatar


func _ready() -> void:
	_build_body()
	_build_destination_marker()
	_build_collision_proxy_root()
	global_position = Vector3(0.0, agent_height * 0.5, 0.0)


func setup(p_placement: PlacementController, static_regions: Array = []) -> void:
	placement = p_placement
	_static_navigation_regions = static_regions.duplicate()
	if not is_inside_tree():
		await ready
	_configure_navigation()
	refresh_navigation()


func setup_avatar(catalog: ItemCatalog, equipment: AvatarEquipmentModel) -> void:
	if not is_inside_tree():
		await ready
	await avatar.setup(catalog, equipment.appearance_state())
	equipment.changed.connect(func(): avatar.apply_state(equipment.appearance_state()))


func move_to_screen_position(screen_position: Vector2) -> void:
	if not placement:
		return
	var ground_position := placement.screen_to_ground(screen_position)
	move_to_world_position(ground_position)


func move_to_world_position(world_position: Vector3) -> bool:
	var start := navigation.nearest_walkable_to_world(global_position)
	if start == SENTINEL_CELL:
		_stop()
		destination_failed.emit(world_position)
		return false
	var requested_world := navigation.clamp_world_to_playable(world_position)
	var requested_cell := navigation.world_to_cell(requested_world)
	var target := navigation.nearest_walkable_to_world(requested_world, start)
	if target == SENTINEL_CELL:
		_stop()
		destination_failed.emit(world_position)
		return false
	_destination_world = requested_world if target == requested_cell else navigation.cell_to_world(target)
	_destination_world.y = global_position.y
	_path = navigation.smooth_path_world(global_position, navigation.find_path_cells(start, target), _destination_world)
	_path_index = 0
	_has_destination = not _path.is_empty()
	_update_marker()
	if not _has_destination:
		var flat_distance := Vector2(global_position.x, global_position.z).distance_to(Vector2(_destination_world.x, _destination_world.z))
		_stop()
		if flat_distance <= waypoint_tolerance:
			destination_reached.emit(_destination_world)
			return true
		destination_failed.emit(world_position)
		return false
	return true


func set_static_navigation_regions(regions: Array) -> void:
	_static_navigation_regions = regions.duplicate()
	refresh_navigation()


func cancel_movement() -> void:
	_stop()


func face_world_position(world_position: Vector3) -> void:
	var direction := world_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.00001:
		return
	# Both supplied avatars are authored facing local +Z.
	rotation.y = atan2(direction.x, direction.z)


func refresh_navigation() -> void:
	if not placement:
		return
	_configure_navigation()
	var placed_items := placement.get_placed_items()
	navigation.rebuild(placed_items, _static_navigation_regions)
	_rebuild_collision_proxies(placed_items)
	if _has_destination:
		move_to_world_position(_destination_world)


func _physics_process(delta: float) -> void:
	if _path.is_empty() or _path_index >= _path.size():
		_stop_velocity()
		return

	var waypoint := _path[_path_index]
	waypoint.y = global_position.y
	var offset := waypoint - global_position
	offset.y = 0.0

	if offset.length() <= waypoint_tolerance:
		_path_index += 1
		if _path_index >= _path.size():
			var reached_position := _destination_world
			_stop()
			destination_reached.emit(reached_position)
			return
		waypoint = _path[_path_index]
		waypoint.y = global_position.y
		offset = waypoint - global_position
		offset.y = 0.0

	var direction := offset.normalized()
	var frame_speed := minf(move_speed, offset.length() / maxf(delta, 0.000001))
	velocity.x = direction.x * frame_speed
	velocity.y = 0.0
	velocity.z = direction.z * frame_speed
	_rotate_toward(direction, delta)
	move_and_slide()
	if avatar:
		avatar.set_moving(Vector2(velocity.x, velocity.z).length_squared() > 0.001)
	global_position = navigation.clamp_world_to_playable(global_position) + Vector3.UP * (agent_height * 0.5)


func _configure_navigation() -> void:
	var bounds := placement.get_playable_bounds()
	navigation.configure(
		placement.get_grid_size(),
		Vector2(bounds.position.x, bounds.position.z),
		Vector2(bounds.position.x + bounds.size.x, bounds.position.z + bounds.size.z),
		agent_radius
	)


func _build_body() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "PlayerCapsuleCollision"
	var shape := CapsuleShape3D.new()
	shape.radius = agent_radius
	shape.height = agent_height
	collision.shape = shape
	add_child(collision)

	avatar = CharacterAvatarScript.new() as CharacterAvatar
	avatar.name = "CharacterAvatar"
	avatar.position = Vector3(0.0, -agent_height * 0.5, 0.0)
	add_child(avatar)


func _build_destination_marker() -> void:
	_destination_marker = MeshInstance3D.new()
	_destination_marker.name = "DestinationMarker"
	_destination_marker.top_level = true
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.18
	mesh.height = 0.025
	mesh.radial_segments = 36
	_destination_marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 1.0, 0.52, 0.78)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_destination_marker.material_override = material
	_destination_marker.visible = false
	add_child(_destination_marker)


func _build_collision_proxy_root() -> void:
	_collision_proxy_root = Node3D.new()
	_collision_proxy_root.name = "NavigationCollisionProxies"
	var owner := get_parent()
	if owner:
		owner.add_child(_collision_proxy_root)
	else:
		add_child(_collision_proxy_root)


func _exit_tree() -> void:
	if is_instance_valid(_collision_proxy_root):
		_collision_proxy_root.queue_free()


func _rebuild_collision_proxies(placed_items: Array) -> void:
	for child in _collision_proxy_root.get_children():
		child.queue_free()
	for item in placed_items:
		if item is PlacementItem:
			_add_collision_proxy(item)


func _add_collision_proxy(item: PlacementItem) -> void:
	var bounds := item.get_visual_bounds()
	if bounds.size.is_zero_approx():
		return
	var world_bounds := _item_world_aabb(item, bounds)
	var body := StaticBody3D.new()
	body.name = "%sNavCollision" % item.name
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		maxf(world_bounds.size.x, 0.08),
		maxf(world_bounds.size.y, 0.2),
		maxf(world_bounds.size.z, 0.08)
	)
	shape_node.shape = shape
	body.add_child(shape_node)
	_collision_proxy_root.add_child(body)
	body.global_position = world_bounds.position + world_bounds.size * 0.5


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


func _rotate_toward(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.00001:
		return
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _update_marker() -> void:
	if not _destination_marker:
		return
	_destination_marker.global_position = Vector3(_destination_world.x, 0.035, _destination_world.z)
	_destination_marker.visible = _has_destination


func _stop() -> void:
	_path.clear()
	_path_index = 0
	_has_destination = false
	_stop_velocity()
	if _destination_marker:
		_destination_marker.visible = false


func _stop_velocity() -> void:
	velocity = Vector3.ZERO
	if avatar:
		avatar.set_moving(false)
