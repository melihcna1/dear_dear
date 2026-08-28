class_name AvatarEquipmentModel
extends Node

signal changed
signal item_expired(item_name: String)

const FEMALE_STARTERS := {
	"fullbody": "",
	"top": "",
	"bottom": "",
	"hair": "",
}
const MALE_STARTERS := {
	"fullbody": "",
	"top": "",
	"bottom": "",
	"hair": "",
}
const STARTERS := {
	AvatarProfile.FEMALE: FEMALE_STARTERS,
	AvatarProfile.MALE: MALE_STARTERS,
}
# Female aliases preserve compatibility for existing scripts and version-4
# tests while new code uses starter_for_gender().
const STARTER_FULLBODY := ""
const STARTER_TOP := ""
const STARTER_BOTTOM := ""
const STARTER_HAIR := ""

var inventory: InventoryModel
var catalog: ItemCatalog
var profile: AvatarProfile
var clock: UtcClock = UtcClock.new()


func setup(p_inventory: InventoryModel, p_catalog: ItemCatalog, p_profile: AvatarProfile, p_clock: UtcClock = null) -> void:
	inventory = p_inventory
	catalog = p_catalog
	profile = p_profile
	if p_clock:
		clock = p_clock


func appearance_state(gender_override := "") -> Dictionary:
	var active_gender := AvatarProfile.normalized_gender(
		gender_override if not gender_override.is_empty() else profile.gender
	)
	var equipped := {"top": "", "bottom": "", "fullbody": "", "hair": ""}
	for item in inventory.all_instances():
		if not item.is_equipped or item.is_expired(clock.now_unix()):
			continue
		var definition := catalog.get_definition(item.definition_id)
		if definition and definition.gender == active_gender and equipped.has(definition.avatar_slot):
			equipped[definition.avatar_slot] = definition.definition_id
	if not str(equipped["fullbody"]).is_empty():
		equipped["top"] = ""
		equipped["bottom"] = ""
	elif not str(equipped["top"]).is_empty() or not str(equipped["bottom"]).is_empty():
		if str(equipped["top"]).is_empty():
			equipped["top"] = starter_for_gender(active_gender, "top")
		if str(equipped["bottom"]).is_empty():
			equipped["bottom"] = starter_for_gender(active_gender, "bottom")
	else:
		equipped["fullbody"] = starter_for_gender(active_gender, "fullbody")
	if str(equipped["hair"]).is_empty():
		equipped["hair"] = starter_for_gender(active_gender, "hair")
	equipped["gender"] = active_gender
	equipped["hair_color"] = profile.current_hair_color_id
	equipped["skin_tone"] = profile.current_skin_tone_id
	return equipped


static func starter_for_gender(gender: String, slot: String) -> String:
	var normalized := AvatarProfile.normalized_gender(gender)
	var starters: Dictionary = STARTERS.get(normalized, FEMALE_STARTERS)
	return str(starters.get(slot, ""))


func equip_rental(instance_id: String) -> bool:
	var item := inventory.find_instance(instance_id)
	if not item or item.item_type != "RENTAL" or item.is_expired(clock.now_unix()):
		return false
	var definition := catalog.get_definition(item.definition_id)
	if (
		not definition
		or definition.avatar_slot.is_empty()
		or definition.gender != profile.gender
	):
		return false
	if not item.is_activated:
		item.is_activated = true
		item.activated_at = clock.now_unix()
		item.expires_at = int(item.activated_at) + item.duration_days * 86400
	_clear_conflicts(definition.avatar_slot, definition.gender)
	item.is_equipped = true
	inventory.notify_changed()
	changed.emit()
	return true


func apply_consumable(instance_id: String) -> bool:
	var item := inventory.find_instance(instance_id)
	if not item or item.item_type != "CONSUMABLE":
		return false
	var definition := catalog.get_definition(item.definition_id)
	if not definition or not catalog.is_avatar_definition_compatible(definition, profile.gender):
		return false
	match definition.avatar_slot:
		"hair_color":
			if profile.current_hair_color_id == definition.definition_id:
				return false
			profile.set_hair_color(definition.definition_id)
		"skin_tone":
			if profile.current_skin_tone_id == definition.definition_id:
				return false
			profile.set_skin_tone(definition.definition_id)
		_:
			return false
	inventory.remove_instance_by_id(instance_id)
	changed.emit()
	return true


func sweep_expired() -> int:
	var expired: Array[ItemInstance] = []
	var now := clock.now_unix()
	for item in inventory.all_instances():
		if item.is_expired(now):
			expired.append(item)
	for item in expired:
		var definition := catalog.get_definition(item.definition_id)
		inventory.remove_instance_by_id(item.instance_id)
		item_expired.emit(definition.item_name if definition else item.definition_id)
	if not expired.is_empty():
		changed.emit()
	return expired.size()


func _clear_conflicts(slot: String, gender: String) -> void:
	var conflicts: Array[String] = [slot]
	if slot == "fullbody":
		conflicts.append_array(["top", "bottom"])
	elif slot in ["top", "bottom"]:
		conflicts.append("fullbody")
	for owned in inventory.all_instances():
		if not owned.is_equipped:
			continue
		var definition := catalog.get_definition(owned.definition_id)
		if definition and definition.gender == gender and definition.avatar_slot in conflicts:
			owned.is_equipped = false
