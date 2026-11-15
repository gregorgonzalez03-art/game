extends Area3D

## Zona de eliminación en el vacío que detecta caídas de entidades.
## Notifica al EventBus siguiendo la arquitectura del estudio.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		EventBus.player_fell_off.emit()
	elif body.is_in_group("enemies"):
		EventBus.enemy_eliminated.emit(body, GameManager.combo_count)
		body.queue_free()
	else:
		body.queue_free()
