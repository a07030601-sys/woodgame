extends Node2D

@export var respawn_delay: float = 3.0

@onready var _player: Player = $Player
@onready var _player_spawn_point: Marker2D = $PlayerSpawnPoint
@onready var _death_label: Label = $UI/DeathLabel


func _ready() -> void:
	_death_label.hide()
	_player.died.connect(_on_player_died)


func _on_player_died() -> void:
	_death_label.show()
	await get_tree().create_timer(respawn_delay).timeout
	_death_label.hide()
	_player.revive(_player_spawn_point.global_position)
