class_name Monster
extends CharacterBody2D

signal died

enum State { IDLE, PATROL, CHASE, ATTACK }

@export var chase_speed: float = 120.0
@export var detection_range: float = 250.0
# 追擊中玩家超出此距離就放棄，需大於 detection_range
@export var give_up_range: float = 400.0
# 與玩家中心點的距離，需大於雙方碰撞體相加的大小，且不大於 attack_range
@export var stop_distance: float = 40.0
# 與玩家中心點的距離，需不小於 stop_distance，停下來時才打得到玩家
@export var attack_range: float = 48.0
# 兩次命中之間的秒數，包含前搖時間
@export var attack_interval: float = 1.2
@export var attack_windup: float = 0.4
@export var min_damage: int = 4
@export var max_damage: int = 8
# 巡邏點以出生位置為中心，在此半徑內隨機選取
@export var patrol_radius: float = 120.0
@export var patrol_speed: float = 60.0
@export var idle_time_min: float = 1.0
@export var idle_time_max: float = 3.0
# 開啟時才 print 狀態切換與巡邏點資訊
@export var debug_ai: bool = false

# 與巡邏點的距離小於此值就視為抵達，避免在目標點來回抖動
const ARRIVE_DISTANCE: float = 4.0
# 巡邏逾時＝預估走到巡邏點的秒數再加上這段緩衝，確保 PATROL 一定會結束
const PATROL_TIMEOUT_MARGIN: float = 1.0
# 前搖期間外觀逐漸放大到這個倍率，當作出手提示
const WINDUP_SCALE: float = 1.4
const FLASH_DURATION: float = 0.15
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/ui/damage_number.tscn")
const DAMAGE_NUMBER_OFFSET: Vector2 = Vector2(0.0, -38.0)
const DAMAGE_NUMBER_COLOR: Color = Color.WHITE

var _state: State = State.IDLE
var _spawn_position: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _idle_time_left: float = 0.0
var _patrol_time_left: float = 0.0
var _attack_cooldown: float = 0.0
var _is_winding_up: bool = false
var _windup_time_left: float = 0.0
var _windup_tween: Tween = null
var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null
var _player: Player = null

@onready var _polygon: Polygon2D = $Polygon2D
@onready var _health: HealthComponent = $HealthComponent
@onready var _health_bar: HealthBar = $HealthBar


func _ready() -> void:
	if stop_distance > attack_range:
		push_warning("%s 的 stop_distance 大於 attack_range，停下來時會打不到玩家" % name)

	_spawn_position = global_position
	_base_color = _polygon.color
	_health.health_changed.connect(_health_bar.update_health)
	_health.damage_taken.connect(_on_damage_taken)
	_health.died.connect(_on_died)
	_health_bar.update_health(_health.current_health, _health.max_health)
	_change_state(State.IDLE)


func _physics_process(delta: float) -> void:
	# 冷卻在所有狀態都會倒數，玩家進出攻擊範圍不會讓怪物打得更快
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)

	match _state:
		State.IDLE:
			_process_idle(delta)
		State.PATROL:
			_process_patrol(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)


func take_damage(amount: int) -> void:
	print("%s 受到 %d 點傷害" % [name, amount])

	# 閃白後漸變回原本的顏色
	if _flash_tween != null:
		_flash_tween.kill()
	_polygon.color = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(_polygon, "color", _base_color, FLASH_DURATION)

	_health.take_damage(amount)


# 所有狀態切換都經過這裡，離開舊狀態的收尾與進入新狀態的初始化也放在這
func _change_state(new_state: State) -> void:
	if _state == State.ATTACK:
		_end_windup()

	_state = new_state
	_debug_log("狀態：%s" % State.keys()[new_state])

	match new_state:
		State.IDLE:
			velocity = Vector2.ZERO
			_idle_time_left = randf_range(idle_time_min, idle_time_max)
		State.PATROL:
			_patrol_target = _pick_patrol_point()
			_patrol_time_left = (
				global_position.distance_to(_patrol_target) / patrol_speed + PATROL_TIMEOUT_MARGIN
			)
			_debug_log("巡邏點：%s" % _patrol_target)
		State.CHASE:
			pass
		State.ATTACK:
			# 冷卻結束後才會開始前搖，剛進入時不沿用上一次的前搖
			_is_winding_up = false


func _process_idle(delta: float) -> void:
	if _get_player_distance() <= detection_range:
		_change_state(State.CHASE)
		return

	_idle_time_left -= delta
	if _idle_time_left <= 0.0:
		_change_state(State.PATROL)


func _process_patrol(delta: float) -> void:
	if _get_player_distance() <= detection_range:
		_change_state(State.CHASE)
		return

	_patrol_time_left -= delta
	if _move_toward(_patrol_target, patrol_speed, ARRIVE_DISTANCE, delta):
		_change_state(State.IDLE)
	elif get_slide_collision_count() > 0 or _patrol_time_left <= 0.0:
		# 路上被擋住或超過預估時間還沒到，就放棄這個巡邏點，之後重新選
		_change_state(State.IDLE)


func _process_chase(delta: float) -> void:
	var distance: float = _get_player_distance()
	# 玩家死亡或不存在時距離為 INF，同樣會放棄追擊
	if distance > give_up_range:
		_change_state(State.PATROL)
		return
	if distance <= attack_range:
		_change_state(State.ATTACK)
		return

	_move_toward(_player.global_position, chase_speed, stop_distance, delta)


func _process_attack(delta: float) -> void:
	var distance: float = _get_player_distance()
	if is_inf(distance):
		_change_state(State.PATROL)
		return
	if distance > attack_range:
		_change_state(State.CHASE)
		return

	# 攻擊時繼續貼近到停止距離，玩家稍微移動才不會馬上脫離攻擊範圍
	_move_toward(_player.global_position, chase_speed, stop_distance, delta)

	if not _is_winding_up:
		if _attack_cooldown <= 0.0:
			_start_windup()
		return

	_windup_time_left -= delta
	if _windup_time_left > 0.0:
		return

	# 玩家離開攻擊範圍時上面已切回 CHASE，走到這裡代表前搖結束時玩家仍在範圍內
	_end_windup()
	_attack_cooldown = maxf(attack_interval - attack_windup, 0.0)
	_player.take_damage(randi_range(min_damage, max_damage))


func _start_windup() -> void:
	_is_winding_up = true
	_windup_time_left = attack_windup
	_windup_tween = create_tween()
	_windup_tween.tween_property(_polygon, "scale", Vector2.ONE * WINDUP_SCALE, attack_windup)


# 出手或前搖被打斷時都會呼叫，把外觀恢復原狀
func _end_windup() -> void:
	_is_winding_up = false
	if _windup_tween != null:
		_windup_tween.kill()
		_windup_tween = null
	_polygon.scale = Vector2.ONE


# 朝 target 直線移動，進入 stop_range 內就停下並回傳 true
func _move_toward(target: Vector2, speed: float, stop_range: float, delta: float) -> bool:
	var to_target: Vector2 = target - global_position
	var distance: float = to_target.length()
	if distance <= stop_range:
		velocity = Vector2.ZERO
		return true

	# 最後一步限制速度，剛好停在停止距離上而不會衝過頭
	var remaining: float = distance - stop_range
	var step_speed: float = minf(speed, remaining / delta)
	velocity = to_target / distance * step_speed
	move_and_slide()
	# 走完最後一步就算抵達，不等下一幀再比距離：浮點誤差可能讓距離永遠略大於 stop_range
	return remaining <= speed * delta


# 玩家不存在或已死亡時回傳 INF
func _get_player_distance() -> float:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or _player.is_dead():
		return INF
	return global_position.distance_to(_player.global_position)


func _pick_patrol_point() -> Vector2:
	# 半徑取平方根，讓選到的點在圓內均勻分布
	var offset: Vector2 = Vector2.from_angle(randf() * TAU) * sqrt(randf()) * patrol_radius
	return _spawn_position + offset


func _debug_log(message: String) -> void:
	if debug_ai:
		print("%s %s" % [name, message])


# 數字加到主場景而不是自己底下，被擊殺移除時最後一擊的數字才不會跟著消失
func _on_damage_taken(amount: int) -> void:
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	number.setup(amount, DAMAGE_NUMBER_COLOR)
	number.position = global_position + DAMAGE_NUMBER_OFFSET
	get_tree().current_scene.add_child(number)


func _on_died() -> void:
	died.emit()
	queue_free()
