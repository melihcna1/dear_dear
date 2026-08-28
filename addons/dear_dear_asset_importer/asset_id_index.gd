@tool
class_name DearDearAssetIdIndex
extends RefCounted

var usages: Dictionary = {}


func rebuild(catalog_items: Array = [], drafts: Array = []) -> void:
	usages.clear()
	_scan_directory("res://assets")
	for row in catalog_items:
		if row is Dictionary:
			_add(str(row.get("item_id", "")), "catalog:%s" % str(row.get("record_id", "unknown")))
	for value in drafts:
		if value is DearDearAssetDraft:
			_add(value.item_id, "draft:%s" % value.record_id)


func next_available(range_value: Vector2i) -> int:
	var maximum := range_value.x - 1
	for key in usages:
		var value := int(key)
		if value >= range_value.x and value <= range_value.y:
			maximum = maxi(maximum, value)
	return maximum + 1 if maximum < range_value.y else -1


func last_used(range_value: Vector2i) -> int:
	var next_value := next_available(range_value)
	return range_value.y if next_value < 0 else next_value - 1


func is_used(item_id: String, ignored_record_id := "") -> bool:
	if not usages.has(item_id):
		return false
	if ignored_record_id.is_empty():
		return true
	for source in usages[item_id]:
		if not str(source).ends_with(ignored_record_id):
			return true
	return false


func sources_for(item_id: String) -> Array:
	return usages.get(item_id, []).duplicate()


func duplicates() -> Dictionary:
	var result := {}
	for item_id in usages:
		var sources: Array = usages[item_id]
		var file_sources := sources.filter(func(source): return str(source).begins_with("res://"))
		if file_sources.size() > 1:
			result[item_id] = file_sources
	return result


func used_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for item_id in usages:
		result.append(str(item_id))
	result.sort()
	return result


func add_usage(item_id: String, source: String) -> void:
	_add(item_id, source)


func _scan_directory(path: String) -> void:
	for file_name in DirAccess.get_files_at(path):
		if file_name.get_extension().to_lower() not in ["glb", "fbx"]:
			continue
		var matcher := RegEx.new()
		matcher.compile("(?:^|_)(\\d{6})(?:_|\\.|$)")
		var match_value := matcher.search(file_name)
		if match_value:
			_add(match_value.get_string(1), "%s/%s" % [path, file_name])
	for directory_name in DirAccess.get_directories_at(path):
		_scan_directory("%s/%s" % [path, directory_name])


func _add(item_id: String, source: String) -> void:
	if item_id.length() != 6 or not item_id.is_valid_int():
		return
	if not usages.has(item_id):
		usages[item_id] = []
	usages[item_id].append(source)
