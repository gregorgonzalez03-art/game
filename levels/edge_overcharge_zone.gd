extends Node3D

## Visualizador perimetral de la zona de Sobrecarga de Borde (Edge Overcharge).
## Superficie tenue por defecto que se ilumina intensamente cuando el jugador pisa el borde (11m a 15m).
## Configurado con render_priority = -1 y DEPTH_DRAW_DISABLED para no interferir con las esquirlas.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

@export var edge_material: StandardMaterial3D

var _tween: Tween

func _ready() -> void:
	EventBus.edge_overcharge_changed.connect(_on_overcharge_changed)
	if edge_material:
		edge_material.render_priority = -1
		edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		edge_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		edge_material.albedo_color = Color(0.0, 0.85, 1.0, 0.22)
		edge_material.emission_enabled = true
		edge_material.emission = Color(0.0, 0.85, 1.0, 1.0)
		edge_material.emission_energy_multiplier = 0.4

func _on_overcharge_changed(active: bool) -> void:
	if not edge_material:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var target_energy: float = 1.8 if active else 0.4
	var target_alpha: float = 0.50 if active else 0.22
	_tween.tween_property(edge_material, "emission_energy_multiplier", target_energy, 0.15)
	_tween.parallel().tween_property(edge_material, "albedo_color:a", target_alpha, 0.15)
