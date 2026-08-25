class_name CharacterAvatar
extends Node3D

const IDLE_ANIMATION_PATH := "res://assets/dev_model/animations/Idle.fbx"
const BASE_CHARACTER_PATHS := {
	AvatarProfile.FEMALE: "res://assets/dev_model/character/dear_dear_female_rig_character.glb",
	AvatarProfile.MALE: "res://assets/dev_model/character/dear_dear_male_rig_character.glb",
}
const WALK_ANIMATION_PATHS := {
	AvatarProfile.FEMALE: "res://assets/dev_model/animations/Walking Female.fbx",
	AvatarProfile.MALE: "res://assets/dev_model/animations/male_walk.fbx",
}
const ANIMATION_BLEND_SECONDS := 0.16
const ROOT_BONE_NAME := &"mixamorig_Hips"

var catalog: ItemCatalog
var current_gender := AvatarProfile.DEFAULT_GENDER
var _base_root: Node3D
var _base_skeleton: Skeleton3D
var _slot_roots: Dictionary = {}
var _garment_skeletons: Array[Skeleton3D] = []
var _animation_sources: Dictionary = {}
var _active_animation_skeleton: Skeleton3D
var _moving := false
var _state: Dictionary = {}
var _transition_from: Dictionary = {}
var _transition_elapsed := ANIMATION_BLEND_SECONDS


func _ready() -> void:
	_build_slot_roots()
	switch_gender(current_gender)


func setup(p_catalog: ItemCatalog, state: Dictionary) -> void:
	catalog = p_catalog
	if not is_node_ready():
		await ready
	apply_state(state)


func apply_state(state: Dictionary) -> void:
	if not is_node_ready():
		await ready
	if not catalog:
		return
	var requested_gender := AvatarProfile.normalized_gender(str(state.get("gender", current_gender)))
	switch_gender(requested_gender)
	_state = state.duplicate(true)
	_state["gender"] = current_gender
	_apply_skin_tone(str(_state.get("skin_tone", AvatarProfile.DEFAULT_SKIN_TONE_ID)))
	for slot in ["top", "bottom", "fullbody", "hair"]:
		_set_slot_model(slot, str(_state.get(slot, "")))
	_apply_hair_color(str(_state.get("hair_color", AvatarProfile.DEFAULT_HAIR_COLOR_ID)))


func current_state() -> Dictionary:
	return _state.duplicate(true)


func set_moving(value: bool) -> void:
	if _moving == value:
		return
	_moving = value
	_activate_animation("walk" if value else "idle")


func switch_gender(gender: String) -> bool:
	var normalized := AvatarProfile.normalized_gender(gender)
	if normalized == current_gender and _base_skeleton:
		return true
	_clear_loaded_avatar()
	current_gender = normalized
	_build_base_character(current_gender)
	_build_animation_source("idle", IDLE_ANIMATION_PATH)
	_build_animation_source("walk", str(WALK_ANIMATION_PATHS[current_gender]))
	_activate_animation("walk" if _moving else "idle")
	return _base_skeleton != null


func _process(delta: float) -> void:
	if _active_animation_skeleton and _base_skeleton:
		_transition_elapsed = minf(_transition_elapsed + delta, ANIMATION_BLEND_SECONDS)
		var blend_weight := smoothstep(
			0.0,
			1.0,
			_transition_elapsed / maxf(ANIMATION_BLEND_SECONDS, 0.001)
		)
		_retarget_pose(_active_animation_skeleton, _base_skeleton, blend_weight)
		if blend_weight >= 1.0:
			_transition_from.clear()
	for garment_skeleton in _garment_skeletons:
		if is_instance_valid(garment_skeleton) and _base_skeleton:
			_copy_pose(_base_skeleton, garment_skeleton)


func _build_base_character(gender: String) -> void:
	var path := str(BASE_CHARACTER_PATHS[gender])
	var scene := ResourceLoader.load(path) as PackedScene
	if not scene:
		push_error("%s avatar scene could not be loaded: %s" % [AvatarProfile.display_gender(gender), path])
		return
	_base_root = scene.instantiate() as Node3D
	_base_root.name = "%sBaseCharacter" % AvatarProfile.display_gender(gender)
	add_child(_base_root)
	_base_skeleton = _find_first_skeleton(_base_root)


func _clear_loaded_avatar() -> void:
	for root_value in _slot_roots.values():
		var slot_root := root_value as Node3D
		for child in slot_root.get_children():
			child.free()
	_garment_skeletons.clear()
	for source_value in _animation_sources.values():
		var source: Dictionary = source_value
		var animation_root := source.get("root") as Node3D
		if is_instance_valid(animation_root):
			animation_root.free()
	_animation_sources.clear()
	_active_animation_skeleton = null
	if is_instance_valid(_base_root):
		_base_root.free()
	_base_root = null
	_base_skeleton = null
	_transition_from.clear()


func _build_slot_roots() -> void:
	for slot in ["top", "bottom", "fullbody", "hair"]:
		var root := Node3D.new()
		root.name = "%sSlot" % slot.capitalize()
		add_child(root)
		_slot_roots[slot] = root


func _set_slot_model(slot: String, definition_id: String) -> void:
	var root: Node3D = _slot_roots.get(slot)
	if not root:
		return
	for child in root.get_children():
		child.free()
	if definition_id.is_empty():
		_rebuild_garment_skeletons()
		return
	var definition := catalog.get_definition(definition_id)
	if not definition or definition.avatar_slot != slot or definition.gender != current_gender:
		push_warning("Invalid %s avatar item: %s" % [slot, definition_id])
		_rebuild_garment_skeletons()
		return
	var model := definition.create_model()
	model.name = definition_id
	root.add_child(model)
	_rebuild_garment_skeletons()


func _apply_skin_tone(definition_id: String) -> void:
	var definition := catalog.get_definition(definition_id)
	if not definition or definition.swatch_path.is_empty() or not _base_root:
		return
	_apply_swatch(_base_root, definition.swatch_path)


func _apply_hair_color(definition_id: String) -> void:
	var definition := catalog.get_definition(definition_id)
	var hair_root: Node3D = _slot_roots.get("hair")
	if not definition or definition.swatch_path.is_empty() or not hair_root:
		return
	_apply_swatch(hair_root, definition.swatch_path)


func _apply_swatch(root: Node, swatch_path: String) -> void:
	var texture := ResourceLoader.load(swatch_path) as Texture2D
	if not texture:
		return
	for mesh in _find_meshes(root):
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.roughness = 0.58
		material.metallic = 0.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = material


func _build_animation_source(key: String, path: String) -> void:
	var scene := ResourceLoader.load(path) as PackedScene
	if not scene:
		push_warning("Avatar animation could not be loaded: %s" % path)
		return
	var root := scene.instantiate() as Node3D
	root.name = "%sAnimationSource" % key.capitalize()
	root.visible = false
	add_child(root)
	var skeleton := _find_first_skeleton(root)
	var player := _find_first_animation_player(root)
	if not skeleton or not player:
		push_warning("Avatar animation scene is missing a skeleton or AnimationPlayer: %s" % path)
		return
	var animation_name := _first_playable_animation(player)
	if animation_name.is_empty():
		push_warning("Avatar animation scene has no playable animation: %s" % path)
		return
	var animation := player.get_animation(animation_name)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR
	_animation_sources[key] = {"root": root, "skeleton": skeleton, "player": player, "animation": animation_name}


func _activate_animation(key: String) -> void:
	var source: Dictionary = _animation_sources.get(key, {})
	if source.is_empty():
		return
	_capture_transition_pose()
	for candidate in _animation_sources.values():
		(candidate["player"] as AnimationPlayer).stop()
	var player := source["player"] as AnimationPlayer
	player.play(source["animation"])
	_active_animation_skeleton = source["skeleton"] as Skeleton3D
	_transition_elapsed = 0.0


func _copy_pose(source: Skeleton3D, target: Skeleton3D) -> void:
	for target_index in target.get_bone_count():
		var source_index := source.find_bone(target.get_bone_name(target_index))
		if source_index < 0:
			continue
		target.set_bone_pose_position(target_index, source.get_bone_pose_position(source_index))
		target.set_bone_pose_rotation(target_index, source.get_bone_pose_rotation(source_index))
		target.set_bone_pose_scale(target_index, source.get_bone_pose_scale(source_index))


func _retarget_pose(source: Skeleton3D, target: Skeleton3D, blend_weight := 1.0) -> void:
	# The supplied FBX animation rigs use centimeter-scale bones under a 100x
	# skeleton transform, while the GLB avatar uses meter-scale bones. Applying
	# their raw local positions collapses the avatar. Transfer animation deltas
	# from each source rest pose onto the corresponding target rest pose instead.
	for target_index in target.get_bone_count():
		var source_index := source.find_bone(target.get_bone_name(target_index))
		if source_index < 0:
			continue
		var source_pose := Transform3D(
			Basis(source.get_bone_pose_rotation(source_index)).scaled(source.get_bone_pose_scale(source_index)),
			source.get_bone_pose_position(source_index)
		)
		var source_rest := source.get_bone_rest(source_index)
		var target_rest := target.get_bone_rest(target_index)
		var animation_delta := source_rest.affine_inverse() * source_pose
		var source_length := source_rest.origin.length()
		if source_length > 0.000001:
			animation_delta.origin *= target_rest.origin.length() / source_length
		else:
			animation_delta.origin = Vector3.ZERO
		var target_pose := target_rest * animation_delta
		# CharacterBody3D owns locomotion. The Mixamo walk contains about one
		# meter of forward hip translation and snaps that translation back at the
		# loop boundary, so never transfer root motion into the rendered avatar.
		if target.get_bone_name(target_index) == ROOT_BONE_NAME:
			target_pose.origin = target_rest.origin
		var transition_pose: Variant = _transition_from.get(target.get_bone_name(target_index))
		if transition_pose is Transform3D and blend_weight < 1.0:
			target_pose = _interpolate_pose(transition_pose, target_pose, blend_weight)
		target.set_bone_pose_position(target_index, target_pose.origin)
		target.set_bone_pose_rotation(target_index, target_pose.basis.get_rotation_quaternion())
		target.set_bone_pose_scale(target_index, target_pose.basis.get_scale())


func _capture_transition_pose() -> void:
	_transition_from.clear()
	if not _base_skeleton:
		return
	for bone_index in _base_skeleton.get_bone_count():
		_transition_from[_base_skeleton.get_bone_name(bone_index)] = Transform3D(
			Basis(_base_skeleton.get_bone_pose_rotation(bone_index)).scaled(_base_skeleton.get_bone_pose_scale(bone_index)),
			_base_skeleton.get_bone_pose_position(bone_index)
		)


func _interpolate_pose(from_pose: Transform3D, to_pose: Transform3D, weight: float) -> Transform3D:
	var from_scale := from_pose.basis.get_scale()
	var to_scale := to_pose.basis.get_scale()
	var rotation := from_pose.basis.get_rotation_quaternion().slerp(to_pose.basis.get_rotation_quaternion(), weight)
	return Transform3D(
		Basis(rotation).scaled(from_scale.lerp(to_scale, weight)),
		from_pose.origin.lerp(to_pose.origin, weight)
	)


func _rebuild_garment_skeletons() -> void:
	_garment_skeletons.clear()
	for root in _slot_roots.values():
		var skeleton := _find_first_skeleton(root)
		if skeleton:
			_garment_skeletons.append(skeleton)


func _find_first_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var result := _find_first_skeleton(child)
		if result:
			return result
	return null


func _find_first_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var result := _find_first_animation_player(child)
		if result:
			return result
	return null


func _find_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for child in root.get_children():
		meshes.append_array(_find_meshes(child))
	return meshes


func _first_playable_animation(player: AnimationPlayer) -> StringName:
	for animation_name in player.get_animation_list():
		if str(animation_name) != "RESET":
			return animation_name
	return &""
