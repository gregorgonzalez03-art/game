extends Node3D

## Spawner para generar enemigos cinéticos en la arena.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

@export var swarmer_scene: PackedScene = preload("res://entities/enemies/swarmer.tscn")
@export var spawn_count: int = 5
@export var spawn_radius: float = 8.5
@export var spawn_height: float = 1.0

func _ready() -> void:
	call_deferred("_spawn_initial_swarmers")

func _spawn_initial_swarmers() -> void:
	if not swarmer_scene:
		return

	for i: int in range(spawn_count):
		var angle: float = (float(i) / float(spawn_count)) * TAU
		var offset_pos: Vector3 = Vector3(
			cos(angle) * spawn_radius,
			spawn_height,
			sin(angle) * spawn_radius
		)
		var swarmer_instance: Node = swarmer_scene.instantiate()
		var swarmer_node: Node3D = swarmer_instance as Node3D
		if swarmer_node:
			swarmer_node.position = offset_pos
			get_parent().add_child(swarmer_node)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_T:
			_spawn_initial_swarmers()
