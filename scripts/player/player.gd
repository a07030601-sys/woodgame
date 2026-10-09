extends CharacterBody2D

@export var move_speed: float = 200.0

# 與目標的距離小於此值就視為抵達，避免在目標點來回抖動
const ARRIVE_DISTANCE: float = 4.0

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _is_following_cursor: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_click"):
		_is_following_cursor = true
		_set_target(get_global_mouse_position())


func _physics_process(delta: float) -> void:
	if _is_following_cursor:
		if Input.is_action_pressed("move_click"):
			_set_target(get_global_mouse_position())
		else:
			_is_following_cursor = false

	if not _has_target:
		return

	var to_target: Vector2 = _target_position - global_position
	var distance: float = to_target.length()
	if distance <= ARRIVE_DISTANCE:
		_has_target = false
		velocity = Vector2.ZERO
		return

	# 最後一步限制速度，剛好停在目標點而不會衝過頭
	var step_speed: float = minf(move_speed, distance / delta)
	velocity = to_target / distance * step_speed
	move_and_slide()


func _set_target(target: Vector2) -> void:
	_target_position = target
	_has_target = true
