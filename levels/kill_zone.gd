extends Area3D

## Zona de eliminación en el vacío que detecta caídas de entidades.
## Genera esquirlas de XP en el borde de la arena al eliminar enemigos.

@export var xp_shard_scene: PackedScene = preload("res://entities/interactables/xp_shard.tscn")

const ARENA_EDGE_DISTANCE: float = 14.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return

	if body.is_in_group("player"):
		EventBus.player_fell_off.emit()
		GameManager.game_over()
	elif body.has_method("die_and_drop_xp"):
		body.call("die_and_drop_xp")
	elif body.is_in_group("enemies"):
		body.remove_from_group("enemies")
		var fall_pos: Vector3 = Vector3.ZERO
		if body is Node3D:
			fall_pos = (body as Node3D).global_position
		EventBus.enemy_eliminated.emit(body, GameManager.combo_count)
		GameManager.spawn_xp_shard_at_edge(fall_pos)
		body.queue_free()
	else:
		body.queue_free()

func _calculate_nearest_edge(from_pos: Vector3) -> Vector3:
	var x: float = clampf(from_pos.x, -ARENA_EDGE_DISTANCE, ARENA_EDGE_DISTANCE)
	var z: float = clampf(from_pos.z, -ARENA_EDGE_DISTANCE, ARENA_EDGE_DISTANCE)
	if absf(from_pos.x) >= absf(from_pos.z):
		x = (1.0 if from_pos.x >= 0.0 else -1.0) * ARENA_EDGE_DISTANCE
	else:
		z = (1.0 if from_pos.z >= 0.0 else -1.0) * ARENA_EDGE_DISTANCE
	return Vector3(x, 1.35, z)

func _spawn_xp_shard(spawn_pos: Vector3) -> void:
	ObjectPool.activate_shard(spawn_pos)
