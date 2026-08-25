class_name FishingMinigameModel
extends RefCounted

enum Result {
	RUNNING,
	SUCCESS,
	FAILURE,
}

const BAR_HEIGHT := 0.22
const UPWARD_ACCELERATION := 2.1
const GRAVITY := 1.7
const MAX_VELOCITY := 1.35
const BOUNDARY_REBOUND := 0.25
const START_PROGRESS := 0.35
const FILL_RATE := 0.30
const DRAIN_RATE := 0.24

var definition: FishingDefinition
var result := Result.RUNNING
var progress := START_PROGRESS
var bar_center := 0.5
var bar_velocity := 0.0
var fish_position := 0.5
var fish_target := 0.5

var _rng: RandomNumberGenerator
var _retarget_timer := 0.0


func start(p_definition: FishingDefinition, p_rng: RandomNumberGenerator = null) -> void:
	definition = p_definition
	_rng = p_rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	result = Result.RUNNING
	progress = START_PROGRESS
	bar_center = 0.5
	bar_velocity = 0.0
	fish_position = 0.5
	fish_target = 0.5
	_retarget_timer = 0.0


func step(delta: float, control_held: bool) -> int:
	if result != Result.RUNNING or definition == null or delta <= 0.0:
		return result

	_update_bar(delta, control_held)
	_update_fish(delta)
	progress += (FILL_RATE if is_overlapping() else -DRAIN_RATE) * delta
	progress = clampf(progress, 0.0, 1.0)
	if progress >= 1.0:
		result = Result.SUCCESS
	elif progress <= 0.0:
		result = Result.FAILURE
	return result


func is_overlapping() -> bool:
	return absf(fish_position - bar_center) <= BAR_HEIGHT * 0.5


func fish_speed() -> float:
	return 0.18 + 0.07 * definition.difficulty if definition else 0.0


func retarget_interval() -> float:
	if not definition:
		return 1.25
	return lerpf(1.25, 0.42, (definition.difficulty - 1.0) / 4.0)


func _update_bar(delta: float, control_held: bool) -> void:
	bar_velocity += (UPWARD_ACCELERATION if control_held else -GRAVITY) * delta
	bar_velocity = clampf(bar_velocity, -MAX_VELOCITY, MAX_VELOCITY)
	bar_center += bar_velocity * delta
	var half_height := BAR_HEIGHT * 0.5
	if bar_center < half_height:
		bar_center = half_height
		bar_velocity = absf(bar_velocity) * BOUNDARY_REBOUND
	elif bar_center > 1.0 - half_height:
		bar_center = 1.0 - half_height
		bar_velocity = -absf(bar_velocity) * BOUNDARY_REBOUND


func _update_fish(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_choose_new_target()
		_retarget_timer = retarget_interval()
		if definition.movement_profile == "darting":
			_retarget_timer *= 0.72
		elif definition.movement_profile == "chaotic":
			_retarget_timer *= 0.55
	fish_position = move_toward(fish_position, fish_target, fish_speed() * delta)


func _choose_new_target() -> void:
	match definition.movement_profile:
		"top_biased":
			fish_target = _rng.randf_range(0.45, 0.94)
		"bottom_biased":
			fish_target = _rng.randf_range(0.06, 0.55)
		"darting":
			fish_target = _far_or_random_target(0.35)
		"chaotic":
			fish_target = _far_or_random_target(0.50)
		_:
			fish_target = _rng.randf_range(0.06, 0.94)


func _far_or_random_target(chance: float) -> float:
	if _rng.randf() < chance:
		return 0.06 if fish_position > 0.5 else 0.94
	return _rng.randf_range(0.06, 0.94)
