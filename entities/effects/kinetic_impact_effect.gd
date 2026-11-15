extends GPUParticles3D

## Efecto de chispas/ondas de impacto cinético.
## Se auto-emite y se destruye al finalizar.

func _ready() -> void:
	emitting = true
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime + 0.1, true, false, true)
	timer.timeout.connect(queue_free)
