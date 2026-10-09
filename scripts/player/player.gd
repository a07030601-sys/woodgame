extends CharacterBody2D

@export var move_speed: float = 200.0
# 與攻擊目標中心點的距離，需大於雙方碰撞體相加的大小才碰得到
@export var attack_range: float = 48.0
@export var attack_interval: float = 0.8
@export var min_damage: int = 3
@export var max_damage: int = 6

# 與目標的距離小於此值就視為抵達，避免在目標點來回抖動
const ARRIVE_DISTANCE: float = 4.0
# enemies 碰撞層（第 2 層）的位元值
const ENEMIES_LAYER_MASK: int = 1 << 1

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _is_following_cursor: bool = false
var _attack_target: Monster = null
var _attack_cooldown: float = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_click"):
		var click_position: Vector2 = get_global_mouse_position()
		_attack_target = _find_enemy_at(click_position)
		if _attack_target != null:
			_is_following_cursor = false
			_has_target = false
		else:
			_is_following_cursor = true
			_set_target(click_position)


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)

	if is_instance_valid(_attack_target):
		_process_attack(delta)
		return
	_attack_target = null

	if _is_following_cursor:
		if Input.is_action_pressed("move_click"):
			_set_target(get_global_mouse_position())
		else:
			_is_following_cursor = false

	if not _has_target:
		return

	if _move_toward(_target_position, ARRIVE_DISTANCE, delta):
		_has_target = false


func _process_attack(delta: float) -> void:
	if not _move_toward(_attack_target.global_position, attack_range, delta):
		return
	if _attack_cooldown > 0.0:
		return
	_attack_target.take_damage(randi_range(min_damage, max_damage))
	_attack_cooldown = attack_interval


# 朝 target 直線移動，進入 stop_distance 內就停下並回傳 true
func _move_toward(target: Vector2, stop_distance: float, delta: float) -> bool:
	var to_target: Vector2 = target - global_position
	var distance: float = to_target.length()
	if distance <= stop_distance:
		velocity = Vector2.ZERO
		return true

	# 最後一步限制速度，剛好停在停止距離上而不會衝過頭
	var step_speed: float = minf(move_speed, (distance - stop_distance) / delta)
	velocity = to_target / distance * step_speed
	move_and_slide()
	return false


func _find_enemy_at(point: Vector2) -> Monster:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = ENEMIES_LAYER_MASK
	var results: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(query)
	for result: Dictionary in results:
		var monster: Monster = result["collider"] as Monster
		if monster != null and monster.is_in_group("enemies"):
			return monster
	return null


func _set_target(target: Vector2) -> void:
	_target_position = target
	_has_target = true
