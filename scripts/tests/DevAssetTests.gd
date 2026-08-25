extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var male_wearable_files := 0
	for slot in ["top", "bottom", "fullbody", "hair"]:
		for file_value in DirAccess.get_files_at("res://assets/dev_model/clothes/male/%s" % slot):
			if str(file_value).get_extension().to_lower() == "glb":
				male_wearable_files += 1
	assert(male_wearable_files == 72)
	assert(ResourceLoader.exists("res://assets/dev_model/character/dear_dear_male_rig_character.glb"))
	assert(ResourceLoader.exists("res://assets/dev_model/animations/male_walk.fbx"))
	for excluded_path in [
		"res://assets/dev_model/clothes/male/eski",
		"res://assets/dev_model/clothes/male/ESKİ2",
		"res://assets/dev_model/clothes/male/accessory",
		"res://assets/dev_model/clothes/male/shoe",
		"res://assets/dev_model/_Arşiv (burayı alma)",
	]:
		assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(excluded_path)))

	var catalog := ItemCatalog.new()
	root.add_child(catalog)
	await process_frame
	var checked_models := 0
	var checked_wearables := 0
	var reference_bones_by_gender := {}
	for gender in AvatarProfile.VALID_GENDERS:
		var base_path := str(CharacterAvatar.BASE_CHARACTER_PATHS[gender])
		var base_scene := ResourceLoader.load(base_path) as PackedScene
		assert(base_scene != null)
		var base_model := base_scene.instantiate() as Node3D
		var base_skeleton := _find_skeleton(base_model)
		assert(base_skeleton != null and base_skeleton.get_bone_count() == 52)
		reference_bones_by_gender[gender] = _bone_names(base_skeleton)
		base_model.free()
	var definitions := catalog.all_definitions()
	definitions.sort_custom(func(a, b): return a.definition_id < b.definition_id)
	for definition in definitions:
		if not definition.model_path.begins_with(ItemCatalog.DEV_ASSET_ROOT):
			continue
		assert(ResourceLoader.exists(definition.model_path))
		var model: Node3D = definition.create_model()
		assert(model != null)
		assert(not _find_meshes(model).is_empty())
		checked_models += 1
		if definition.avatar_slot in ["top", "bottom", "fullbody", "hair"]:
			var skeleton := _find_skeleton(model)
			assert(skeleton != null)
			assert(skeleton.get_bone_count() == 52)
			assert(reference_bones_by_gender.has(definition.gender))
			assert(_bone_names(skeleton) == reference_bones_by_gender[definition.gender])
			checked_wearables += 1
		model.free()
	assert(checked_models == 267)
	assert(checked_wearables == 194)

	var profile := AvatarProfile.new()
	root.add_child(profile)
	var inventory := InventoryModel.new()
	root.add_child(inventory)
	await process_frame
	var equipment := AvatarEquipmentModel.new()
	root.add_child(equipment)
	equipment.setup(inventory, catalog, profile)
	var avatar := CharacterAvatar.new()
	root.add_child(avatar)
	await avatar.setup(catalog, equipment.appearance_state())
	await process_frame
	assert(avatar._base_skeleton != null)
	assert(avatar._base_skeleton.get_bone_count() == 52)
	assert(avatar._animation_sources.has("idle"))
	assert(avatar._animation_sources.has("walk"))
	avatar.set_moving(true)
	await _assert_animation_is_stable(avatar)
	avatar.apply_state({
		"gender": AvatarProfile.FEMALE,
		"top": "f_cloth_top_310103",
		"bottom": "f_cloth_bottom_310179",
		"fullbody": "",
		"hair": "f_cloth_hair_310187",
		"hair_color": "hair_color_red",
		"skin_tone": "skin_tone_7",
	})
	await process_frame
	assert(avatar._garment_skeletons.size() == 3)
	var hip_index := avatar._base_skeleton.find_bone("mixamorig_Hips")
	for garment_skeleton in avatar._garment_skeletons:
		var garment_hip := garment_skeleton.find_bone("mixamorig_Hips")
		assert(garment_hip >= 0)
		assert(garment_skeleton.get_bone_pose_position(garment_hip).is_equal_approx(avatar._base_skeleton.get_bone_pose_position(hip_index)))

	var female_base_id := avatar._base_root.get_instance_id()
	avatar.apply_state({
		"gender": AvatarProfile.MALE,
		"top": "m_cloth_top_310008",
		"bottom": "m_cloth_bottom_310153",
		"fullbody": "",
		"hair": "m_cloth_hair_310192",
		"hair_color": "hair_color_red",
		"skin_tone": "skin_tone_7",
	})
	await process_frame
	assert(avatar.current_gender == AvatarProfile.MALE)
	assert(avatar._base_root.name == "MaleBaseCharacter")
	assert(not is_instance_id_valid(female_base_id))
	assert(avatar._base_skeleton.get_bone_count() == 52)
	assert(avatar._animation_sources.size() == 2)
	assert(avatar._garment_skeletons.size() == 3)
	await _assert_animation_is_stable(avatar)
	var male_hip_index := avatar._base_skeleton.find_bone("mixamorig_Hips")
	for garment_skeleton in avatar._garment_skeletons:
		var garment_hip := garment_skeleton.find_bone("mixamorig_Hips")
		assert(garment_hip >= 0)
		assert(garment_skeleton.get_bone_pose_position(garment_hip).is_equal_approx(avatar._base_skeleton.get_bone_pose_position(male_hip_index)))

	print("DevAssetTests: PASS")
	quit()


func _assert_animation_is_stable(avatar: CharacterAvatar) -> void:
	var hip_index := avatar._base_skeleton.find_bone("mixamorig_Hips")
	assert(hip_index >= 0)
	var hip_rest_position := avatar._base_skeleton.get_bone_rest(hip_index).origin
	var previous_rotations: Array[Quaternion] = []
	for bone_index in avatar._base_skeleton.get_bone_count():
		previous_rotations.append(avatar._base_skeleton.get_bone_pose_rotation(bone_index))
	var maximum_frame_rotation := 0.0
	for _frame in 90:
		await process_frame
		assert(avatar._base_skeleton.get_bone_pose_position(hip_index).distance_to(hip_rest_position) < 0.0001)
		for bone_index in avatar._base_skeleton.get_bone_count():
			var current_rotation := avatar._base_skeleton.get_bone_pose_rotation(bone_index)
			maximum_frame_rotation = maxf(maximum_frame_rotation, previous_rotations[bone_index].angle_to(current_rotation))
			previous_rotations[bone_index] = current_rotation
	assert(avatar._moving)
	assert(avatar._active_animation_skeleton != null)
	assert(maximum_frame_rotation < 0.45)


func _find_skeleton(root_node: Node) -> Skeleton3D:
	if root_node is Skeleton3D:
		return root_node
	for child in root_node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


func _find_meshes(root_node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root_node is MeshInstance3D:
		meshes.append(root_node)
	for child in root_node.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes


func _bone_names(skeleton: Skeleton3D) -> Array[StringName]:
	var result: Array[StringName] = []
	for bone_index in skeleton.get_bone_count():
		result.append(skeleton.get_bone_name(bone_index))
	return result
