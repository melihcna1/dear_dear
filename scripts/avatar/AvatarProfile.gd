class_name AvatarProfile
extends Node

signal changed

const FEMALE := "female"
const MALE := "male"
const DEFAULT_GENDER := FEMALE
const VALID_GENDERS := [FEMALE, MALE]
const DEFAULT_SKIN_TONE_ID := "skin_tone_1"
const DEFAULT_HAIR_COLOR_ID := "hair_color_black"

var user_id := ""
var has_completed_onboarding := false
var gender := DEFAULT_GENDER
var current_skin_tone_id := DEFAULT_SKIN_TONE_ID
var current_hair_color_id := DEFAULT_HAIR_COLOR_ID


func _ready() -> void:
	ensure_user_id()


func ensure_user_id() -> void:
	if user_id.is_empty():
		user_id = "usr-%s-%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]


func complete_onboarding(p_gender: String, skin_tone_id: String, hair_color_id: String) -> void:
	ensure_user_id()
	gender = normalized_gender(p_gender)
	current_skin_tone_id = skin_tone_id
	current_hair_color_id = hair_color_id
	has_completed_onboarding = true
	changed.emit()


func set_gender(value: String) -> bool:
	var requested := value.to_lower()
	if requested not in VALID_GENDERS:
		return false
	var normalized := requested
	if normalized == gender:
		return false
	gender = normalized
	changed.emit()
	return true


func set_skin_tone(item_id: String) -> void:
	current_skin_tone_id = item_id
	changed.emit()


func set_hair_color(item_id: String) -> void:
	current_hair_color_id = item_id
	changed.emit()


func to_dict() -> Dictionary:
	ensure_user_id()
	return {
		"user_id": user_id,
		"has_completed_onboarding": has_completed_onboarding,
		"gender": gender,
		"current_skin_tone_id": current_skin_tone_id,
		"current_hair_color_id": current_hair_color_id,
	}


func load_dict(data: Dictionary) -> void:
	user_id = str(data.get("user_id", ""))
	ensure_user_id()
	has_completed_onboarding = bool(data.get("has_completed_onboarding", false))
	# Version-4 and older profiles did not persist a selectable gender. They
	# remain female and retain their onboarding completion state.
	gender = normalized_gender(str(data.get("gender", DEFAULT_GENDER)))
	current_skin_tone_id = str(data.get("current_skin_tone_id", DEFAULT_SKIN_TONE_ID))
	current_hair_color_id = str(data.get("current_hair_color_id", DEFAULT_HAIR_COLOR_ID))
	changed.emit()


static func normalized_gender(value: String) -> String:
	var normalized := value.to_lower()
	return normalized if normalized in VALID_GENDERS else DEFAULT_GENDER


static func display_gender(value: String) -> String:
	return normalized_gender(value).capitalize()
