extends Node

## Object Pooling para Esquirlas de XP y Efectos Cinéticos (Fase 4.3).
## Pre-instancia 25 esquirlas al inicio para eliminar stutter por Garbage Collection e instantiate().
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

const PREALLOCATED_SHARDS: int = 25
const SHARD_SCENE: PackedScene = preload("res://entities/interactables/xp_shard.tscn")

var _shard_pool: Array[Node3D] = []
var _pool_container: Node3D = null

func _ready() -> void:
	_init_pool()

func _init_pool() -> void:
	_pool_container = Node3D.new()
	_pool_container.name = "ObjectPoolContainer"
	add_child(_pool_container)

	for i in range(PREALLOCATED_SHARDS):
		_create_pooled_shard()

func _create_pooled_shard() -> Node3D:
	if not SHARD_SCENE:
		return null
	var shard_instance: Node = SHARD_SCENE.instantiate()
	var shard_node: Node3D = shard_instance as Node3D
	if shard_node:
		_pool_container.add_child(shard_node)
		_deactivate_shard_node(shard_node)
		_shard_pool.append(shard_node)
	return shard_node

func activate_shard(spawn_pos: Vector3) -> Node3D:
	var available_shard: Node3D = null

	for shard in _shard_pool:
		if is_instance_valid(shard) and not shard.visible:
			available_shard = shard
			break

	# Si se agotan los 25 pre-instanciados, expandir el pool dinámicamente
	if not available_shard:
		available_shard = _create_pooled_shard()

	if available_shard:
		_activate_shard_node(available_shard, spawn_pos)

	return available_shard

func deactivate_shard(shard: Node3D) -> void:
	if not is_instance_valid(shard):
		return
	_deactivate_shard_node(shard)

func deactivate_all() -> void:
	for shard in _shard_pool:
		if is_instance_valid(shard):
			_deactivate_shard_node(shard)

func _activate_shard_node(shard: Node3D, spawn_pos: Vector3) -> void:
	shard.global_position = spawn_pos
	shard.visible = true
	shard.set_process(true)
	shard.set_physics_process(true)

	if shard is Area3D:
		var area: Area3D = shard as Area3D
		area.set_deferred("monitoring", true)
		area.set_deferred("monitorable", true)

	if shard.has_method("reset_shard"):
		shard.call("reset_shard")

func _deactivate_shard_node(shard: Node3D) -> void:
	shard.visible = false
	shard.set_process(false)
	shard.set_physics_process(false)
	shard.global_position = Vector3(0.0, -200.0, 0.0)

	if shard is Area3D:
		var area: Area3D = shard as Area3D
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
