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
signal player_fell_off()
