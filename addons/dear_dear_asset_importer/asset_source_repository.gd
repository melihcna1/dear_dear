@tool
class_name DearDearAssetSourceRepository
extends RefCounted

const DEFAULT_ROOT := "res://asset_import_sources"

var root_path := DEFAULT_ROOT


func store(
	source_path: String,
	main_category: String,
	sub_category: String,
	gender: String,
	preferred_path := "",
	overwrite := false,
) -> Dictionary:
	var source_absolute := _absolute(source_path)
	if not FileAccess.file_exists(source_absolute):
		return {"ok": false, "error": "Source GLB no longer exists: %s" % source_path}
	if source_path.get_extension().to_lower() != "glb":
		return {"ok": false, "error": "Only .glb source files can be stored."}
	var source_hash := FileAccess.get_sha256(source_absolute)
	if source_hash.is_empty():
		return {"ok": false, "error": "Source GLB could not be read."}
	var destination := preferred_path if is_managed(preferred_path) else _destination(
		source_path, main_category, sub_category, gender)
	var destination_absolute := _absolute(destination)
	if source_absolute.replace("\\", "/").to_lower() == destination_absolute.replace("\\", "/").to_lower():
		return {"ok": true, "path": destination, "sha256": source_hash, "copied": false}
	if FileAccess.file_exists(destination_absolute):
		if FileAccess.get_sha256(destination_absolute) == source_hash:
			return {"ok": true, "path": destination, "sha256": source_hash, "copied": false}
		if not overwrite:
			destination = _collision_safe_path(destination, source_hash)
			destination_absolute = _absolute(destination)
			if FileAccess.file_exists(destination_absolute) and FileAccess.get_sha256(destination_absolute) == source_hash:
				return {"ok": true, "path": destination, "sha256": source_hash, "copied": false}
	var directory_error := DirAccess.make_dir_recursive_absolute(destination_absolute.get_base_dir())
	if directory_error not in [OK, ERR_ALREADY_EXISTS]:
		return {"ok": false, "error": "Could not create the project source inbox folder."}
	var staged_absolute := "%s.dear_tmp" % destination_absolute
	var backup_absolute := "%s.dear_backup" % destination_absolute
	_remove_if_present(staged_absolute)
	_remove_if_present(backup_absolute)
	var bytes := FileAccess.get_file_as_bytes(source_absolute)
	if bytes.is_empty():
		return {"ok": false, "error": "Source GLB could not be read."}
	var staged_file := FileAccess.open(staged_absolute, FileAccess.WRITE)
	if not staged_file:
		return {"ok": false, "error": "Could not stage the project-local source copy."}
	staged_file.store_buffer(bytes)
	staged_file.close()
	if FileAccess.file_exists(destination_absolute):
		var backup_error := DirAccess.rename_absolute(destination_absolute, backup_absolute)
		if backup_error != OK:
			_remove_if_present(staged_absolute)
			return {"ok": false, "error": "Could not prepare the existing inbox source for replacement."}
	var install_error := DirAccess.rename_absolute(staged_absolute, destination_absolute)
	if install_error != OK:
		if FileAccess.file_exists(backup_absolute):
			DirAccess.rename_absolute(backup_absolute, destination_absolute)
		return {"ok": false, "error": "Could not install the project-local source copy."}
	_remove_if_present(backup_absolute)
	return {"ok": true, "path": destination, "sha256": source_hash, "copied": true}


func find_by_filename(file_name: String) -> PackedStringArray:
	var matches := PackedStringArray()
	_find_recursive(root_path, file_name.to_lower(), matches)
	return matches


func is_managed(path: String) -> bool:
	if path.is_empty():
		return false
	var normalized := _absolute(path).replace("\\", "/").to_lower()
	var root_absolute := _absolute(root_path).replace("\\", "/").trim_suffix("/").to_lower()
	return normalized == root_absolute or normalized.begins_with("%s/" % root_absolute)


func canonical_path(path: String) -> String:
	if not is_managed(path):
		return path
	var normalized := _absolute(path).replace("\\", "/")
	var root_absolute := _absolute(root_path).replace("\\", "/").trim_suffix("/")
	var relative := normalized.substr(root_absolute.length()).trim_prefix("/")
	return "%s/%s" % [root_path.trim_suffix("/"), relative]


func _destination(source_path: String, main_category: String, sub_category: String, gender: String) -> String:
	var segments := PackedStringArray([root_path.trim_suffix("/"), _safe_segment(main_category, "unclassified")])
	if main_category == "cloth":
		segments.append(_safe_segment(gender, "unisex"))
	segments.append(_safe_segment(sub_category, "general"))
	segments.append(source_path.get_file())
	return "/".join(segments)


func _collision_safe_path(path: String, source_hash: String) -> String:
	return "%s_%s.glb" % [path.trim_suffix(".glb"), source_hash.substr(0, 8)]


func _safe_segment(value: String, fallback: String) -> String:
	var slug := DearDearAssetNaming.slugify(value)
	return slug if not slug.is_empty() else fallback


func _find_recursive(directory: String, target_name: String, matches: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(_absolute(directory)):
		return
	for file_name in DirAccess.get_files_at(directory):
		if file_name.to_lower() == target_name:
			matches.append("%s/%s" % [directory.trim_suffix("/"), file_name])
	for child_directory in DirAccess.get_directories_at(directory):
		_find_recursive("%s/%s" % [directory.trim_suffix("/"), child_directory], target_name, matches)


func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path


func _remove_if_present(absolute_path: String) -> void:
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
