extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var nav := PlayerNavigationGrid.new()
	nav.configure(0.5, Vector2(-2.0, -2.0), Vector2(2.0, 2.0), 0.25)
	nav.rebuild([])

	assert(nav.is_walkable(Vector2i(0, 0)))
	assert(not nav.is_walkable(Vector2i(-4, 0)))
	assert(nav.clamp_world_to_playable(Vector3(99.0, 0.0, 99.0)).is_equal_approx(Vector3(1.5, 0.0, 1.5)))
	var raw_open_path := nav.find_path_cells(Vector2i(-3, -3), Vector2i(3, 2))
	var smooth_open_path := nav.smooth_path_world(Vector3(-1.5, 0.0, -1.5), raw_open_path, Vector3(1.45, 0.0, 1.2))
	assert(smooth_open_path.size() == 1)
	assert(smooth_open_path[0].is_equal_approx(Vector3(1.45, 0.0, 1.2)))

	var obstacle := _make_obstacle(Vector3(0.0, 0.0, 0.0), Vector3(0.5, 1.0, 0.5))
	root.add_child(obstacle)
	await process_frame
	nav.rebuild([obstacle])
	assert(not nav.is_walkable(Vector2i(0, 0)))
	var detour := nav.find_path_world(Vector3(-1.5, 0.0, 0.0), Vector3(1.5, 0.0, 0.0))
	assert(detour.size() > 0)
	for point in detour:
		assert(not point.is_equal_approx(Vector3.ZERO))

	var nearest := nav.nearest_walkable_to_world(Vector3(0.0, 0.0, 0.0), Vector2i(-3, 0))
	assert(nearest != Vector2i(0, 0))
	assert(nearest != Vector2i(2147483647, 2147483647))

	var wall := _make_obstacle(Vector3(0.0, 0.0, 0.0), Vector3(0.5, 1.0, 4.0))
	root.add_child(wall)
	await process_frame
	nav.rebuild([wall])
	assert(nav.find_path_cells(Vector2i(-3, 0), Vector2i(3, 0)).is_empty())

	nav.rebuild([])
	assert(not nav.find_path_cells(Vector2i(-3, 0), Vector2i(3, 0)).is_empty())

	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	var placement := PlacementController.new()
	root.add_child(placement)
	await process_frame
	placement.setup(catalog, inventory)
	var player := PlayerController.new()
	root.add_child(player)
	await process_frame
	player.setup(placement)
	var target := Vector3(2.0, 0.0, 1.5)
	assert(player.move_to_world_position(target))
	var previous_position := player.global_position
	var maximum_step := 0.0
	for _frame in 300:
		await physics_frame
		var step_distance := Vector2(previous_position.x, previous_position.z).distance_to(Vector2(player.global_position.x, player.global_position.z))
		maximum_step = maxf(maximum_step, step_distance)
		previous_position = player.global_position
		if not player._has_destination:
			break
	assert(not player._has_destination)
	assert(Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(target.x, target.z)) <= player.waypoint_tolerance)
	assert(maximum_step < 0.12)
	var expected_visual_forward := Vector3(target.x, 0.0, target.z).normalized()
	var actual_visual_forward := (player.global_transform.basis * Vector3.BACK).normalized()
	assert(actual_visual_forward.dot(expected_visual_forward) > 0.99)

	print("PlayerNavigationTests: PASS")
	quit()


func _make_obstacle(world_position: Vector3, size: Vector3) -> PlacementItem:
	var item := PlacementItem.new()
	item.name = "TestObstacle"
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	item.add_child(mesh_instance)
	item.position = world_position
	return item
