class_name Player
extends CharacterBody2D

signal died

# 與攻擊目標中心點的距離，需大於雙方碰撞體相加的大小才碰得到
@export var attack_range: float = 48.0

# 與目標的距離小於此值就視為抵達，避免在目標點來回抖動
const ARRIVE_DISTANCE: float = 4.0
# enemies 碰撞層（第 2 層）的位元值
const ENEMIES_LAYER_MASK: int = 1 << 1
# attack_speed 的下限，避免算攻擊間隔時除以 0
const MIN_ATTACK_SPEED: float = 0.01
# 除錯用，階段 4 有裝備後移除
const DEBUG_STRENGTH_SOURCE: String = "debug_strength"
const DEAD_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0)
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/ui/damage_number.tscn")
const DAMAGE_NUMBER_OFFSET: Vector2 = Vector2(0.0, -38.0)
const DAMAGE_NUMBER_COLOR: Color = Color(1.0, 0.25, 0.25, 1.0)

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _is_following_cursor: bool = false
var _attack_target: Monster = null
var _attack_cooldown: float = 0.0
var _base_color: Color = Color.WHITE

@onready var _polygon: Polygon2D = $Polygon2D
@onready var _stats: StatsComponent = $StatsComponent
@onready var _health: HealthComponent = $HealthComponent
@onready var _health_bar: HealthBar = $HealthBar


func _ready() -> void:
	_base_color = _polygon.color
	_health.health_changed.connect(_health_bar.update_health)
	_health.damage_taken.connect(_on_damage_taken)
	_health.died.connect(_on_died)
	_stats.stats_changed.connect(_on_stats_changed)
	# 最大生命由屬性元件的 life 決定，開場時補滿
	_on_stats_changed()
	_health.revive()


func _unhandled_input(event: InputEvent) -> void:
	# 除錯用，階段 4 有裝備後移除
	if event.is_action_pressed("debug_toggle_strength"):
		if _stats.has_source(DEBUG_STRENGTH_SOURCE):
			_stats.remove_source(DEBUG_STRENGTH_SOURCE)
		else:
			_stats.add_source(
				DEBUG_STRENGTH_SOURCE, [{"stat": "strength", "value": 10, "type": "flat"}]
			)
		return

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

	if _is_attack_target_alive():
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


func take_damage(amount: int) -> void:
	_health.take_damage(amount)


func is_dead() -> bool:
	return _health.is_dead()


func get_stats() -> StatsComponent:
	return _stats


func revive(spawn_position: Vector2) -> void:
	global_position = spawn_position
	_health.revive()
	_polygon.color = _base_color
	_clear_targets()
	_attack_cooldown = 0.0
	set_physics_process(true)
	set_process_unhandled_input(true)


func _process_attack(delta: float) -> void:
	if not _move_toward(_attack_target.global_position, attack_range, delta):
		return
	if _attack_cooldown > 0.0:
		return
	_attack_target.take_damage(_roll_damage())
	# attack_speed 是每秒攻擊次數
	_attack_cooldown = 1.0 / maxf(_stats.get_stat("attack_speed"), MIN_ATTACK_SPEED)


# 屬性是 float，擲傷害時才四捨五入成整數，並確保最大值不小於最小值
func _roll_damage() -> int:
	var damage_min: int = roundi(_stats.get_stat("damage_min"))
	var damage_max: int = maxi(roundi(_stats.get_stat("damage_max")), damage_min)
	return randi_range(damage_min, damage_max)


# 怪物死亡後會被移除，目標可能已被釋放或正等待釋放
func _is_attack_target_alive() -> bool:
	return is_instance_valid(_attack_target) and not _attack_target.is_queued_for_deletion()


# 朝 target 直線移動，進入 stop_distance 內就停下並回傳 true
func _move_toward(target: Vector2, stop_distance: float, delta: float) -> bool:
	var to_target: Vector2 = target - global_position
	var distance: float = to_target.length()
	if distance <= stop_distance:
		velocity = Vector2.ZERO
		return true

	# 最後一步限制速度，剛好停在停止距離上而不會衝過頭
	var move_speed: float = _stats.get_stat("move_speed")
	var remaining: float = distance - stop_distance
	var step_speed: float = minf(move_speed, remaining / delta)
	velocity = to_target / distance * step_speed
	move_and_slide()
	# 走完最後一步就算抵達，不等下一幀再比距離：浮點誤差可能讓距離永遠略大於 stop_distance
	return remaining <= move_speed * delta


func _find_enemy_at(point: Vector2) -> Monster:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = ENEMIES_LAYER_MASK
	var results: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(query)
	for result: Dictionary in results:
		var monster: Monster = result["collider"] as Monster
		if monster != null and monster.is_in_group("enemies") and not monster.is_queued_for_deletion():
			return monster
	return null


func _set_target(target: Vector2) -> void:
	_target_position = target
	_has_target = true


# 數字加到主場景而不是自己底下
func _on_damage_taken(amount: int) -> void:
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	number.setup(amount, DAMAGE_NUMBER_COLOR)
	number.position = global_position + DAMAGE_NUMBER_OFFSET
	get_tree().current_scene.add_child(number)


func _on_stats_changed() -> void:
	_health.set_max_health(roundi(_stats.get_stat("life")))


func _on_died() -> void:
	print("玩家死亡")
	_polygon.color = DEAD_COLOR
	_clear_targets()
	# 死亡後不再處理移動、攻擊與輸入，revive() 會恢復
	set_physics_process(false)
	set_process_unhandled_input(false)
	died.emit()


func _clear_targets() -> void:
	_attack_target = null
	_has_target = false
	_is_following_cursor = false
	velocity = Vector2.ZERO
