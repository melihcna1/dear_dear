class_name FishingController
extends Node

signal state_changed(state: int)
signal cast_started(zone: FishingZone, target_world: Vector3)
signal bite_started
signal fish_caught(item_id: String)
signal attempt_finished(success: bool, reason: String)

enum State {
	IDLE,
	APPROACHING,
	WAITING_FOR_BITE,
	HOOK_WINDOW,
	MINIGAME,
	REWARD_PENDING,
	RESULT,
}

const HOOK_WINDOW_SECONDS := 0.9
const RESULT_SECONDS := 1.25

var state := State.IDLE
var player: PlayerController
var inventory: InventoryModel
var item_catalog: ItemCatalog
var fishing_catalog: FishingCatalog
var placement: PlacementController
var fishing_ui: FishingUI
var zones: Array[FishingZone] = []
var minigame := FishingMinigameModel.new()
var rng := RandomNumberGenerator.new()

var _active_zone: FishingZone
var _clicked_target := Vector3.ZERO
var _cast_target := Vector3.ZERO
var _selected_fish: FishingDefinition
var _pending_reward: ItemInstance
var _timer := 0.0
var _control_held := false


func _ready() -> void:
	rng.randomize()


func setup(
		p_player: PlayerController,
		p_inventory: InventoryModel,
		p_item_catalog: ItemCatalog,
		p_fishing_catalog: FishingCatalog,
		p_placement: PlacementController,
		p_ui: FishingUI) -> void:
	player = p_player
	inventory = p_inventory
	item_catalog = p_item_catalog
	fishing_catalog = p_fishing_catalog
	placement = p_placement
	fishing_ui = p_ui
	player.destination_reached.connect(_on_destination_reached)
	player.destination_failed.connect(_on_destination_failed)
	fishing_ui.replace_slot_requested.connect(_on_replace_slot_requested)
	fishing_ui.reward_cancelled.connect(_on_reward_cancelled)
	_sync_world_regions()


func register_zone(zone: FishingZone) -> void:
	if zone and not zones.has(zone):
		zones.append(zone)
		_sync_world_regions()


func zone_at(world_position: Vector3) -> FishingZone:
	for zone in zones:
		if is_instance_valid(zone) and zone.contains_world_point(world_position):
			return zone
	return null


func try_start_at(world_position: Vector3) -> bool:
	var zone := zone_at(world_position)
	if not zone:
		return false
	if state != State.IDLE:
		if state == State.APPROACHING:
			cancel(false)
		else:
			return true
	_selected_fish = fishing_catalog.choose_fish(rng) if fishing_catalog else null
	if not _selected_fish:
		_show_temporary_result("No fish are configured for this pond")
		return true
	_active_zone = zone
	_clicked_target = world_position
	_pending_reward = null
	_set_state(State.APPROACHING)
	fishing_ui.show_prompt("Walking to the fishing spot...")
	player.move_to_world_position(world_position)
	return true


func cancel(show_feedback: bool = true) -> void:
	if state == State.IDLE:
		return
	if state == State.RESULT:
		_reset_to_idle()
		return
	player.cancel_movement()
	_hide_cast()
	_pending_reward = null
	_selected_fish = null
	_control_held = false
	attempt_finished.emit(false, "cancelled")
	if show_feedback:
		_set_state(State.RESULT)
		_timer = RESULT_SECONDS
		fishing_ui.show_result("Fishing cancelled")
	else:
		_reset_to_idle()


func is_busy() -> bool:
	return state != State.IDLE


func locks_world_input() -> bool:
	return state != State.IDLE and state != State.APPROACHING


func _process(delta: float) -> void:
	match state:
		State.WAITING_FOR_BITE:
			_timer -= delta
			if _timer <= 0.0:
				_set_state(State.HOOK_WINDOW)
				_timer = HOOK_WINDOW_SECONDS
				fishing_ui.show_bite()
				bite_started.emit()
		State.HOOK_WINDOW:
			_timer -= delta
			if _timer <= 0.0:
				_finish_failure("The fish got away")
		State.MINIGAME:
			var result := minigame.step(delta, _control_held)
			fishing_ui.update_minigame(minigame)
			if result == FishingMinigameModel.Result.SUCCESS:
				_finish_catch()
			elif result == FishingMinigameModel.Result.FAILURE:
				_finish_failure("The fish got away")
		State.RESULT:
			_timer -= delta
			if _timer <= 0.0:
				_reset_to_idle()


func _input(event: InputEvent) -> void:
	if state == State.IDLE:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if not _is_control_event(event):
		return
	if state == State.WAITING_FOR_BITE and event.pressed:
		_finish_failure("Too early! The line came back empty")
	elif state == State.HOOK_WINDOW and event.pressed:
		_start_minigame()
		_control_held = true
	elif state == State.MINIGAME:
		_control_held = event.pressed
	else:
		return
	get_viewport().set_input_as_handled()


func _on_destination_reached(shore_world: Vector3) -> void:
	if state != State.APPROACHING or not _active_zone:
		return
	_cast_target = _active_zone.resolve_cast_target(_clicked_target, shore_world)
	player.face_world_position(_cast_target)
	_active_zone.show_placeholder_cast(player.global_position, _cast_target)
	_set_state(State.WAITING_FOR_BITE)
	_timer = rng.randf_range(1.0, 3.0)
	fishing_ui.show_waiting()
	cast_started.emit(_active_zone, _cast_target)


func _on_destination_failed(_requested_world: Vector3) -> void:
	if state == State.APPROACHING:
		_finish_failure("No reachable fishing spot")


func _start_minigame() -> void:
	_set_state(State.MINIGAME)
	minigame.start(_selected_fish, rng)
	var definition := item_catalog.get_definition(_selected_fish.item_id)
	fishing_ui.show_minigame(definition, minigame)


func _finish_catch() -> void:
	_pending_reward = item_catalog.create_instance(_selected_fish.item_id)
	if inventory.add_instance(_pending_reward, item_catalog):
		_complete_reward()
		return
	_set_state(State.REWARD_PENDING)
	_control_held = false
	var definition := item_catalog.get_definition(_pending_reward.definition_id)
	fishing_ui.show_replacement(definition, inventory, item_catalog)


func _on_replace_slot_requested(slot_index: int) -> void:
	if state != State.REWARD_PENDING or not _pending_reward:
		return
	var discarded := inventory.replace_slot_with_instance(slot_index, _pending_reward, item_catalog)
	if discarded.is_empty():
		var definition := item_catalog.get_definition(_pending_reward.definition_id)
		fishing_ui.show_replacement(definition, inventory, item_catalog)
		return
	_complete_reward()


func _on_reward_cancelled() -> void:
	if state == State.REWARD_PENDING:
		_pending_reward = null
		_finish_failure("The fish was released")


func _complete_reward() -> void:
	var caught_id := _pending_reward.definition_id
	var definition := item_catalog.get_definition(caught_id)
	_pending_reward = null
	_hide_cast()
	fish_caught.emit(caught_id)
	attempt_finished.emit(true, caught_id)
	_set_state(State.RESULT)
	_timer = RESULT_SECONDS
	fishing_ui.show_result("Caught %s!" % definition.item_name, definition)


func _finish_failure(message: String) -> void:
	_hide_cast()
	_pending_reward = null
	_control_held = false
	attempt_finished.emit(false, message)
	_set_state(State.RESULT)
	_timer = RESULT_SECONDS
	fishing_ui.show_result(message)


func _show_temporary_result(message: String) -> void:
	_set_state(State.RESULT)
	_timer = RESULT_SECONDS
	fishing_ui.show_result(message)


func _reset_to_idle() -> void:
	_hide_cast()
	_active_zone = null
	_selected_fish = null
	_pending_reward = null
	_control_held = false
	fishing_ui.hide_all()
	_set_state(State.IDLE)


func _hide_cast() -> void:
	if _active_zone and is_instance_valid(_active_zone):
		_active_zone.hide_placeholder_cast()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	state = next_state
	state_changed.emit(state)


func _sync_world_regions() -> void:
	var regions: Array = []
	for zone in zones:
		if is_instance_valid(zone):
			regions.append(zone.get_navigation_rect())
	if placement:
		placement.set_excluded_ground_regions(regions)
	if player:
		player.set_static_navigation_regions(regions)


func _is_control_event(event: InputEvent) -> bool:
	return (
		(event is InputEventKey and event.keycode == KEY_SPACE and not event.echo)
		or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	)
