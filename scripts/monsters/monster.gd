class_name Monster
extends CharacterBody2D

@export var move_speed: float = 120.0
@export var detection_range: float = 250.0
# 追擊中玩家超出此距離就放棄，需大於 detection_range
@export var give_up_range: float = 400.0
# 與玩家中心點的距離，需大於雙方碰撞體相加的大小，且小於玩家的攻擊範圍
@export var stop_distance: float = 40.0

const FLASH_DURATION: float = 0.15
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/ui/damage_number.tscn")
const DAMAGE_NUMBER_OFFSET: Vector2 = Vector2(0.0, -38.0)
const DAMAGE_NUMBER_COLOR: Color = Color.WHITE

var _base_color: Color = Color.WHITE
var _flash_tween: Tween = null
var _player: Player = null
var _is_chasing: bool = false

@onready var _polygon: Polygon2D = $Polygon2D
@onready var _health: HealthComponent = $HealthComponent
@onready var _health_bar: HealthBar = $HealthBar


func _ready() -> void:
	_base_color = _polygon.color
	_health.health_changed.connect(_health_bar.update_health)
	_health.damage_taken.connect(_on_damage_taken)
	_health.died.connect(_on_died)
	_health_bar.update_health(_health.current_health, _health.max_health)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or _player.is_dead():
		_is_chasing = false
		velocity = Vector2.ZERO
		return

	var to_player: Vector2 = _player.global_position - global_position
	var distance: float = to_player.length()

	if _is_chasing:
		if distance > give_up_range:
			_is_chasing = false
	elif distance <= detection_range:
		_is_chasing = true

	if not _is_chasing or distance <= stop_distance:
		velocity = Vector2.ZERO
		return

	# 最後一步限制速度，剛好停在停止距離上而不會擠進玩家
	var step_speed: float = minf(move_speed, (distance - stop_distance) / delta)
	velocity = to_player / distance * step_speed
	move_and_slide()


func take_damage(amount: int) -> void:
	print("%s 受到 %d 點傷害" % [name, amount])

	# 閃白後漸變回原本的顏色
	if _flash_tween != null:
		_flash_tween.kill()
	_polygon.color = Color.WHITE
	_flash_tween = create_tween()
	_flash_tween.tween_property(_polygon, "color", _base_color, FLASH_DURATION)

	_health.take_damage(amount)


# 數字加到主場景而不是自己底下，被擊殺移除時最後一擊的數字才不會跟著消失
func _on_damage_taken(amount: int) -> void:
	var number: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate() as DamageNumber
	number.setup(amount, DAMAGE_NUMBER_COLOR)
	number.position = global_position + DAMAGE_NUMBER_OFFSET
	get_tree().current_scene.add_child(number)


func _on_died() -> void:
	queue_free()
