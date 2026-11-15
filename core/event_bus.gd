extends Node

## Singleton global para eventos y desacoplamiento de sistemas.
## Siguiendo el principio de arquitectura: Call down, signal up.

@warning_ignore("unused_signal")
signal enemy_launched(enemy: Node3D, force: float)
@warning_ignore("unused_signal")
signal chain_collision(combo_count: int, position: Vector3)
@warning_ignore("unused_signal")
signal enemy_eliminated(enemy: Node3D, combo_count: int)
@warning_ignore("unused_signal")
signal wave_completed(completed_wave: int)
@warning_ignore("unused_signal")
signal player_fell_off()
@warning_ignore("unused_signal")
signal pulse_fired(origin: Vector3, direction: Vector3, hit_collider: Node3D)
@warning_ignore("unused_signal")
signal pull_fired(target: Node3D)
@warning_ignore("unused_signal")
signal xp_collected(amount: int)
@warning_ignore("unused_signal")
signal edge_overcharge_changed(active: bool)
