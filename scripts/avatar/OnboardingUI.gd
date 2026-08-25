class_name OnboardingUI
extends CanvasLayer

signal completed
signal cancelled

var profile: AvatarProfile
var equipment: AvatarEquipmentModel
var catalog: ItemCatalog
var avatar: CharacterAvatar
var panel: PanelContainer
var title_label: Label
var hint_label: Label
var gender_picker: OptionButton
var hair_picker: OptionButton
var skin_picker: OptionButton
var confirm_button: Button
var cancel_button: Button
var _gender_ids: Array[String] = [AvatarProfile.FEMALE, AvatarProfile.MALE]
var _hair_ids: Array[String] = []
var _skin_ids: Array[String] = []
var _saved_state: Dictionary = {}
var _redo_mode := false


func setup(p_profile: AvatarProfile, p_equipment: AvatarEquipmentModel, p_catalog: ItemCatalog, p_avatar: CharacterAvatar) -> void:
	profile = p_profile
	equipment = p_equipment
	catalog = p_catalog
	avatar = p_avatar
	_build_ui()


func open(redo_mode := false) -> void:
	_redo_mode = redo_mode
	_saved_state = equipment.appearance_state()
	_select_id(gender_picker, _gender_ids, profile.gender)
	_select_id(hair_picker, _hair_ids, profile.current_hair_color_id)
	_select_id(skin_picker, _skin_ids, profile.current_skin_tone_id)
	cancel_button.visible = _redo_mode
	panel.visible = true
	_update_labels()
	_preview()


func is_open() -> bool:
	return panel != null and panel.visible


func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.name = "FirstTimeAvatarSetup"
	panel.visible = false
	panel.anchor_left = 0.55
	panel.anchor_top = 0.18
	panel.anchor_right = 0.94
	panel.anchor_bottom = 0.82
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	panel.add_child(layout)
	title_label = Label.new()
	title_label.text = "Create Your Character"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	layout.add_child(title_label)
	hint_label = Label.new()
	hint_label.text = "Choose your avatar and permanent starter colors. Additional colors are single-use Market items."
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(hint_label)
	layout.add_child(_label("Avatar"))
	gender_picker = OptionButton.new()
	for gender in _gender_ids:
		gender_picker.add_item(AvatarProfile.display_gender(gender))
	layout.add_child(gender_picker)
	layout.add_child(_label("Hair Color"))
	hair_picker = OptionButton.new()
	layout.add_child(hair_picker)
	layout.add_child(_label("Skin Tone"))
	skin_picker = OptionButton.new()
	layout.add_child(skin_picker)
	var definitions := catalog.all_definitions()
	definitions.sort_custom(func(a, b): return a.definition_id < b.definition_id)
	for definition in definitions:
		if definition.avatar_slot == "hair_color":
			_hair_ids.append(definition.definition_id)
			hair_picker.add_icon_item(_small_swatch(definition.swatch_path), definition.item_name)
		elif definition.avatar_slot == "skin_tone":
			_skin_ids.append(definition.definition_id)
			skin_picker.add_icon_item(_small_swatch(definition.swatch_path), definition.item_name)
	gender_picker.item_selected.connect(func(_index): _on_appearance_option_changed())
	hair_picker.item_selected.connect(func(_index): _on_appearance_option_changed())
	skin_picker.item_selected.connect(func(_index): _preview())
	_select_id(gender_picker, _gender_ids, profile.gender)
	_select_id(hair_picker, _hair_ids, profile.current_hair_color_id)
	_select_id(skin_picker, _skin_ids, profile.current_skin_tone_id)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	layout.add_child(actions)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.visible = false
	cancel_button.pressed.connect(_cancel)
	actions.add_child(cancel_button)
	confirm_button = Button.new()
	confirm_button.text = "Confirm Character"
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.pressed.connect(_confirm)
	actions.add_child(confirm_button)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _small_swatch(path: String) -> Texture2D:
	var source := ResourceLoader.load(path) as Texture2D
	if not source:
		return null
	var image := source.get_image()
	image.resize(24, 24, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


func _preview() -> void:
	if not avatar or _gender_ids.is_empty() or _hair_ids.is_empty() or _skin_ids.is_empty():
		return
	var gender := _selected_gender()
	var state := equipment.appearance_state(gender)
	state["hair_color"] = _hair_ids[hair_picker.selected]
	state["skin_tone"] = _skin_ids[skin_picker.selected]
	avatar.apply_state(state)


func _confirm() -> void:
	if _hair_ids.is_empty() or _skin_ids.is_empty():
		return
	profile.complete_onboarding(
		_selected_gender(),
		_skin_ids[skin_picker.selected],
		_hair_ids[hair_picker.selected]
	)
	panel.visible = false
	avatar.apply_state(equipment.appearance_state())
	completed.emit()


func _cancel() -> void:
	if not _redo_mode:
		return
	panel.visible = false
	avatar.apply_state(_saved_state)
	cancelled.emit()


func _on_appearance_option_changed() -> void:
	_update_labels()
	_preview()


func _update_labels() -> void:
	if not confirm_button:
		return
	var gender_name := AvatarProfile.display_gender(_selected_gender())
	title_label.text = "Update Your Character" if _redo_mode else "Create Your Character"
	confirm_button.text = "Confirm %s Character" % gender_name


func _selected_gender() -> String:
	if not gender_picker or gender_picker.selected < 0 or gender_picker.selected >= _gender_ids.size():
		return profile.gender
	return _gender_ids[gender_picker.selected]


func _select_id(picker: OptionButton, ids: Array[String], item_id: String) -> void:
	var index := ids.find(item_id)
	picker.selected = maxi(index, 0)
