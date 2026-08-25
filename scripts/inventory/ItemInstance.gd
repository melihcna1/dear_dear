class_name ItemInstance
extends RefCounted

var instance_id := ""
var definition_id := ""
var metadata: Dictionary = {}
var user_id := ""
var item_type := "STANDARD"
var duration_days := 0
var is_activated := false
var activated_at: Variant = null
var expires_at: Variant = null
var is_equipped := false


func _init(p_definition_id: String = "", p_metadata: Dictionary = {}, p_instance_id: String = "") -> void:
	definition_id = p_definition_id
	metadata = p_metadata.duplicate(true)
	instance_id = p_instance_id if not p_instance_id.is_empty() else _make_id()


func duplicate_instance() -> ItemInstance:
	var copy := ItemInstance.new(definition_id, metadata, instance_id)
	copy.user_id = user_id
	copy.item_type = item_type
	copy.duration_days = duration_days
	copy.is_activated = is_activated
	copy.activated_at = activated_at
	copy.expires_at = expires_at
	copy.is_equipped = is_equipped
	return copy


func is_stack_compatible(other: ItemInstance) -> bool:
	return other != null and definition_id == other.definition_id and metadata == other.metadata


func to_dict() -> Dictionary:
	return {
		"user_item_id": instance_id,
		"user_id": user_id,
		"item_id": definition_id,
		"item_type": item_type,
		"duration_days": duration_days,
		"is_activated": is_activated,
		"activated_at": activated_at,
		"expires_at": expires_at,
		"is_equipped": is_equipped,
		# Legacy aliases keep older placement/save tooling compatible.
		"instance_id": instance_id,
		"definition_id": definition_id,
		"metadata": metadata.duplicate(true),
	}


static func from_dict(data: Dictionary) -> ItemInstance:
	var item := ItemInstance.new(
		str(data.get("item_id", data.get("definition_id", ""))),
		data.get("metadata", {}),
		str(data.get("user_item_id", data.get("instance_id", "")))
	)
	item.user_id = str(data.get("user_id", ""))
	item.item_type = str(data.get("item_type", "STANDARD"))
	item.duration_days = int(data.get("duration_days", 0))
	item.is_activated = bool(data.get("is_activated", false))
	item.activated_at = data.get("activated_at", null)
	item.expires_at = data.get("expires_at", null)
	item.is_equipped = bool(data.get("is_equipped", false))
	return item


func is_expired(now_unix: int) -> bool:
	return item_type == "RENTAL" and is_activated and expires_at != null and now_unix >= int(expires_at)


func _make_id() -> String:
	return "%s-%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]
