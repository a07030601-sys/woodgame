class_name MonsterSpawner
extends Node2D

@export var monster_scene: PackedScene
@export var max_alive: int = 3
@export var spawn_radius: float = 150.0
@export var respawn_delay: float = 5.0
# 選到的生成位置離玩家小於此距離就重選
@export var min_player_distance: float = 300.0

# 單次生成最多重選幾次位置，都不合格就延後再試，避免無窮迴圈
const MAX_POSITION_ATTEMPTS: int = 20
const RETRY_DELAY: float = 1.0

var _alive_count: int = 0


func _ready() -> void:
	if monster_scene == null:
		push_warning("%s 沒有設定 monster_scene" % name)
		return

	for i: int in max_alive:
		_spawn_monster()


func _spawn_monster() -> void:
	if _alive_count >= max_alive:
		return

	var player: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	var spawn_point: Vector2 = Vector2.ZERO
	var found: bool = false
	for attempt: int in MAX_POSITION_ATTEMPTS:
		spawn_point = _pick_spawn_point()
		if player == null or spawn_point.distance_to(player.global_position) >= min_player_distance:
			found = true
			break
	if not found:
		# 玩家站在生成範圍裡，晚點再試
		_schedule_spawn(RETRY_DELAY)
		return

	var monster: Monster = monster_scene.instantiate() as Monster
	# 先設定位置再加入場景樹，怪物在 _ready 才會記錄到正確的出生位置
	monster.position = to_local(spawn_point)
	monster.died.connect(_on_monster_died)
	_alive_count += 1
	add_child(monster, true)


func _pick_spawn_point() -> Vector2:
	# 半徑取平方根，讓選到的點在圓內均勻分布
	var offset: Vector2 = Vector2.from_angle(randf() * TAU) * sqrt(randf()) * spawn_radius
	return global_position + offset


func _schedule_spawn(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(_spawn_monster)


func _on_monster_died() -> void:
	_alive_count -= 1
	_schedule_spawn(respawn_delay)
