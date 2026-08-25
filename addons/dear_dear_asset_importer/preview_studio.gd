@tool
class_name DearDearPreviewStudio
extends Control

signal camera_profile_changed(profile: Dictionary)

const CAPTURE_SIZE := Vector2i(1024, 1024)
const DEFAULT_PROFILE := {
	"yaw": 0.65,
	"pitch": -0.32,
	"distance": 3.2,
	"pan_x": 0.0,
	"pan_y": 0.0,
}

var _viewport: SubViewport
var _presented_texture: ImageTexture
var _normalizer: Node3D
var _camera: Camera3D
var _model: Node3D
var _profile := DEFAULT_PROFILE.duplicate(true)
var _drag_button := MOUSE_BUTTON_NONE
var _last_mouse := Vector2.ZERO
var _preview_poll_timer: Timer
var _preview_poll_attempts := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(460, 420)
	_build_world()
	_preview_poll_timer = Timer.new()
	_preview_poll_timer.wait_time = 0.08
	_preview_poll_timer.one_shot = false
	_preview_poll_timer.timeout.connect(_poll_preview_frame)
	add_child(_preview_poll_timer)
	gui_input.connect(_on_gui_input)
	resized.connect(queue_redraw)


func _draw() -> void:
	if not _presented_texture:
		return
	var texture_size := Vector2(_presented_texture.get_size())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var scale_factor := minf(size.x / texture_size.x, size.y / texture_size.y)
	var draw_size := texture_size * scale_factor
	var draw_position := (size - draw_size) * 0.5
	draw_texture_rect(_presented_texture, Rect2(draw_position, draw_size), false)


func load_glb(path: String) -> Dictionary:
	clear_model()
	var dependency_result := validate_self_contained_glb(path)
	if not dependency_result.ok:
		return dependency_result
	var scene_root: Node = null
	var project_resource_path := _project_resource_path(path)
	if not project_resource_path.is_empty() and ResourceLoader.exists(project_resource_path):
		var packed := ResourceLoader.load(project_resource_path) as PackedScene
		if packed:
			scene_root = packed.instantiate()
	else:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(path, state)
		if error != OK:
			return {"ok": false, "error": "Could not load GLB: %s" % error_string(error)}
		scene_root = document.generate_scene(state)
	if not scene_root:
		return {"ok": false, "error": "The GLB did not produce a scene."}
	if scene_root is Node3D:
		_model = scene_root
	else:
		_model = Node3D.new()
		_model.add_child(scene_root)
	_normalizer.add_child(_model)
	_normalize_model()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_queue_preview_refresh()
	return {"ok": true}


func _project_resource_path(path: String) -> String:
	if path.begins_with("res://"):
		return path
	var normalized_path := path.replace("\\", "/")
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if not project_root.ends_with("/"):
		project_root += "/"
	if normalized_path.to_lower().begins_with(project_root.to_lower()):
		return "res://%s" % normalized_path.substr(project_root.length())
	return ""


func clear_model() -> void:
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_normalizer.position = Vector3.ZERO
	_normalizer.scale = Vector3.ONE
	_presented_texture = null
	_preview_poll_attempts = 0
	if _preview_poll_timer:
		_preview_poll_timer.stop()
	queue_redraw()


func set_preview_active(active: bool) -> void:
	if not _viewport:
		return
	if active:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_queue_preview_refresh()
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_preview_poll_attempts = 0
		if _preview_poll_timer:
			_preview_poll_timer.stop()


func set_camera_profile(profile: Dictionary) -> void:
	_profile = DEFAULT_PROFILE.duplicate(true)
	for key in DEFAULT_PROFILE:
		if profile.has(key):
			_profile[key] = float(profile[key])
	_update_camera(false)


func get_camera_profile() -> Dictionary:
	return _profile.duplicate(true)


func reset_camera() -> void:
	_profile = DEFAULT_PROFILE.duplicate(true)
	_update_camera()


func capture_png(path: String) -> Dictionary:
	if not _model:
		return {"ok": false, "error": "Load a model before capturing."}
	# Keep the studio live and allow imported meshes/materials to reach the
	# RenderingServer before reading the render target. A single UPDATE_ONCE
	# frame can return a valid-sized but fully transparent image in the editor.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var image: Image = null
	for unused in 12:
		await RenderingServer.frame_post_draw
		var viewport_texture := _viewport.get_texture()
		if not viewport_texture:
			continue
		var candidate: Image = viewport_texture.get_image()
		if not candidate or candidate.is_empty():
			continue
		if candidate.get_size() != CAPTURE_SIZE:
			candidate.resize(CAPTURE_SIZE.x, CAPTURE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		if _image_has_visible_content(candidate):
			image = candidate
			break
	if not image:
		return {"ok": false, "error": "The capture rendered no visible pixels. Check the preview, camera, and model visibility."}
	_present_preview_image(image)
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error not in [OK, ERR_ALREADY_EXISTS]:
		return {"ok": false, "error": "Could not create the market image folder."}
	var error := image.save_png(absolute)
	return {"ok": error == OK, "error": "" if error == OK else "Could not save PNG: %s" % error_string(error)}


func validate_self_contained_glb(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "glb":
		return {"ok": false, "error": "Only binary .glb files are supported."}
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var file := FileAccess.open(absolute, FileAccess.READ)
	if not file:
		return {"ok": false, "error": "Could not open the GLB file."}
	file.big_endian = false
	if file.get_length() < 20 or file.get_32() != 0x46546C67:
		return {"ok": false, "error": "The file is not a valid binary glTF container."}
	file.get_32()
	file.get_32()
	var json_length := file.get_32()
	var chunk_type := file.get_32()
	if chunk_type != 0x4E4F534A or json_length <= 0 or json_length > file.get_length() - 20:
		return {"ok": false, "error": "The GLB JSON chunk is invalid."}
	var json_text := file.get_buffer(json_length).get_string_from_utf8().strip_edges()
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "The GLB JSON chunk could not be parsed."}
	for group_name in ["buffers", "images"]:
		for entry in parsed.get(group_name, []):
			if entry is Dictionary and entry.has("uri"):
				var uri := str(entry.get("uri", ""))
				if not uri.is_empty() and not uri.begins_with("data:"):
					return {"ok": false, "error": "GLB uses an external dependency: %s" % uri}
	return {"ok": true}


func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "CaptureViewport"
	_viewport.size = CAPTURE_SIZE
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.82)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	_normalizer = Node3D.new()
	_normalizer.name = "Preview3DNode"
	_viewport.add_child(_normalizer)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 35.0
	_camera.near = 0.01
	_camera.far = 100.0
	_viewport.add_child(_camera)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key_light.light_energy = 2.0
	key_light.shadow_enabled = true
	_viewport.add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "FillLight"
	fill_light.position = Vector3(-2.4, 1.8, 2.6)
	fill_light.light_energy = 1.4
	fill_light.omni_range = 10.0
	_viewport.add_child(fill_light)

	var rim_light := OmniLight3D.new()
	rim_light.name = "RimLight"
	rim_light.position = Vector3(2.0, 2.7, -2.2)
	rim_light.light_color = Color(0.72, 0.82, 1.0)
	rim_light.light_energy = 1.0
	rim_light.omni_range = 10.0
	_viewport.add_child(rim_light)
	_update_camera(false)


func _normalize_model() -> void:
	var bounds := _calculate_bounds(_model, Transform3D.IDENTITY)
	if bounds.size.is_zero_approx():
		_normalizer.position = Vector3.ZERO
		_normalizer.scale = Vector3.ONE
		return
	var center := bounds.position + bounds.size * 0.5
	var maximum_dimension := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var uniform_scale := 2.0 / maxf(maximum_dimension, 0.001)
	_normalizer.scale = Vector3.ONE * uniform_scale
	_normalizer.position = -center * uniform_scale


func _queue_preview_refresh() -> void:
	if not _model or not _viewport:
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_poll_attempts = 250
	if _preview_poll_timer and _preview_poll_timer.is_stopped():
		_preview_poll_timer.start()


func _poll_preview_frame() -> void:
	if not _model or not is_instance_valid(_viewport) or _preview_poll_attempts <= 0:
		_preview_poll_timer.stop()
		return
	_preview_poll_attempts -= 1
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	var viewport_texture := _viewport.get_texture()
	if not viewport_texture:
		return
	var image: Image = viewport_texture.get_image()
	if image and _image_has_visible_content(image):
		_present_preview_image(image)
		_preview_poll_timer.stop()


func _image_has_visible_content(image: Image) -> bool:
	if not image or image.is_empty() or not image.get_used_rect().has_area():
		return false
	var sample := image.duplicate()
	sample.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	for y in sample.get_height():
		for x in sample.get_width():
			var color: Color = sample.get_pixel(x, y)
			if color.a > 0.01 and maxf(color.r, maxf(color.g, color.b)) > 0.01:
				return true
	return false


func _present_preview_image(image: Image) -> void:
	if image.is_empty():
		return
	if _presented_texture:
		_presented_texture.update(image)
	else:
		_presented_texture = ImageTexture.create_from_image(image)
	queue_redraw()


func get_presented_texture() -> ImageTexture:
	return _presented_texture


func _calculate_bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var found := false
	var result := AABB()
	for child in node.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * child.transform
		if child is MeshInstance3D and child.mesh:
			var transformed: AABB = child_transform * child.get_aabb()
			result = transformed if not found else result.merge(transformed)
			found = true
		var nested := _calculate_bounds(child, child_transform)
		if not nested.size.is_zero_approx():
			result = nested if not found else result.merge(nested)
			found = true
	return result


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_drag_button = event.button_index if event.pressed else MOUSE_BUTTON_NONE
			_last_mouse = event.position
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
			_profile.distance = clampf(float(_profile.distance) * factor, 1.35, 8.0)
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		var delta: Vector2 = event.position - _last_mouse
		_last_mouse = event.position
		if _drag_button == MOUSE_BUTTON_MIDDLE or event.shift_pressed:
			_profile.pan_x = clampf(float(_profile.pan_x) - delta.x * 0.0035, -1.0, 1.0)
			_profile.pan_y = clampf(float(_profile.pan_y) + delta.y * 0.0035, -1.0, 1.0)
		else:
			_profile.yaw = float(_profile.yaw) - delta.x * 0.008
			_profile.pitch = clampf(float(_profile.pitch) - delta.y * 0.008, -1.35, 1.35)
		_update_camera()
		accept_event()


func _update_camera(emit_change := true) -> void:
	if not _camera:
		return
	var target := Vector3(float(_profile.pan_x), float(_profile.pan_y), 0.0)
	var rotation_basis := Basis.from_euler(Vector3(float(_profile.pitch), float(_profile.yaw), 0.0))
	_camera.position = target + rotation_basis * Vector3(0.0, 0.0, float(_profile.distance))
	_camera.look_at(target, Vector3.UP)
	if _model:
		_queue_preview_refresh()
	if emit_change:
		camera_profile_changed.emit(get_camera_profile())
