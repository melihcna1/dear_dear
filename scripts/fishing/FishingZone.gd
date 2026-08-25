class_name FishingZone
extends Node3D

@export var size := Vector2(3.0, 3.0)
@export var max_cast_distance := 2.5
@export var water_type := "freshwater"

var _bobber: MeshInstance3D
var _line: MeshInstance3D


func _ready() -> void:
	_build_water()
	_build_placeholder_cast()


func contains_world_point(world_position: Vector3) -> bool:
	return get_navigation_rect().has_point(Vector2(world_position.x, world_position.z))


func get_navigation_rect() -> Rect2:
	var center := Vector2(global_position.x, global_position.z)
	return Rect2(center - size * 0.5, size)


func resolve_cast_target(clicked_world: Vector3, shore_world: Vector3) -> Vector3:
	var rect := get_navigation_rect().grow(-0.06)
	var clicked_2d := Vector2(clicked_world.x, clicked_world.z)
	var clamped_2d := Vector2(
		clampf(clicked_2d.x, rect.position.x, rect.end.x),
		clampf(clicked_2d.y, rect.position.y, rect.end.y)
	)
	var target := Vector3(clamped_2d.x, global_position.y, clamped_2d.y)
	var flat_offset := target - Vector3(shore_world.x, target.y, shore_world.z)
	if flat_offset.length() > max_cast_distance:
		target = Vector3(shore_world.x, target.y, shore_world.z) + flat_offset.normalized() * max_cast_distance
		target.x = clampf(target.x, rect.position.x, rect.end.x)
		target.z = clampf(target.z, rect.position.y, rect.end.y)
	return target


func show_placeholder_cast(from_world: Vector3, target_world: Vector3) -> void:
	if not _bobber or not _line:
		return
	_bobber.visible = true
	_bobber.global_position = target_world + Vector3.UP * 0.10
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate.surface_add_vertex(from_world + Vector3.UP * 0.82)
	immediate.surface_add_vertex(target_world + Vector3.UP * 0.10)
	immediate.surface_end()
	_line.mesh = immediate
	_line.visible = true


func hide_placeholder_cast() -> void:
	if _bobber:
		_bobber.visible = false
	if _line:
		_line.visible = false


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "PrototypeWater"
	var plane := PlaneMesh.new()
	plane.size = size
	water.mesh = plane
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.08, 0.55, 0.78, 0.78)
	water_material.metallic = 0.08
	water_material.roughness = 0.24
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = water_material
	add_child(water)

	var border_material := StandardMaterial3D.new()
	border_material.albedo_color = Color(0.12, 0.76, 0.92, 1.0)
	border_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_border(Vector3(size.x, 0.035, 0.04), Vector3(0.0, 0.018, -size.y * 0.5), border_material)
	_add_border(Vector3(size.x, 0.035, 0.04), Vector3(0.0, 0.018, size.y * 0.5), border_material)
	_add_border(Vector3(0.04, 0.035, size.y), Vector3(-size.x * 0.5, 0.018, 0.0), border_material)
	_add_border(Vector3(0.04, 0.035, size.y), Vector3(size.x * 0.5, 0.018, 0.0), border_material)

	var label := Label3D.new()
	label.name = "FishingHint"
	label.text = "Fishing Pond\nRight-click the water"
	label.position = Vector3(0.0, 0.42, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 28
	label.outline_size = 6
	label.modulate = Color(0.88, 0.98, 1.0, 1.0)
	add_child(label)


func _add_border(border_size: Vector3, border_position: Vector3, material: StandardMaterial3D) -> void:
	var border := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = border_size
	border.mesh = mesh
	border.position = border_position
	border.material_override = material
	add_child(border)


func _build_placeholder_cast() -> void:
	_bobber = MeshInstance3D.new()
	_bobber.name = "PrototypeBobber"
	_bobber.top_level = true
	var bobber_mesh := SphereMesh.new()
	bobber_mesh.radius = 0.07
	bobber_mesh.height = 0.14
	_bobber.mesh = bobber_mesh
	var bobber_material := StandardMaterial3D.new()
	bobber_material.albedo_color = Color(1.0, 0.22, 0.18, 1.0)
	_bobber.material_override = bobber_material
	_bobber.visible = false
	add_child(_bobber)

	_line = MeshInstance3D.new()
	_line.name = "PrototypeFishingLine"
	_line.top_level = true
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.92, 0.96, 1.0, 1.0)
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line.material_override = line_material
	_line.visible = false
	add_child(_line)
