extends Node3D

## Onda de Aire Cinética Sutil (Fase 4.2).
## Expansión breve y tenue de aire comprimido / distorsión transparente (sin emisión ni líneas).
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

var wave_mesh: MeshInstance3D = null
var wave_material: StandardMaterial3D = null

func _ready() -> void:
	_setup_air_wave()

func _setup_air_wave() -> void:
	wave_mesh = MeshInstance3D.new()
	wave_mesh.name = "AirWave"

	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	torus.rings = 32
	torus.ring_segments = 16
	wave_mesh.mesh = torus
	wave_mesh.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	wave_material = StandardMaterial3D.new()
	wave_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	wave_material.albedo_color = Color(1.0, 1.0, 1.0, 0.18)
	wave_material.emission_enabled = false
	wave_mesh.material_override = wave_material

	add_child(wave_mesh)
	scale = Vector3(0.3, 0.3, 0.3)

func play(origin_pos: Vector3, forward_dir: Vector3) -> void:
	global_position = origin_pos + forward_dir * 0.4
	var target_look: Vector3 = global_position + forward_dir * 10.0
	var up_vec: Vector3 = Vector3.UP if abs(forward_dir.y) < 0.95 else Vector3.RIGHT
	look_at(target_look, up_vec)

	scale = Vector3(0.3, 0.3, 0.3)

	if wave_material:
		wave_material.albedo_color.a = 0.18
		var target_pos: Vector3 = global_position + forward_dir * 1.6
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "global_position", target_pos, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector3(1.3, 1.3, 0.8), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(wave_material, "albedo_color:a", 0.0, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var timer: SceneTreeTimer = get_tree().create_timer(0.12, true, false, true)
	timer.timeout.connect(queue_free)

## Destello circular en el punto de impacto para representar el radio de empuje de shockwave_pulse
static func spawn_shockwave_splash(parent: Node, hit_pos: Vector3, radius: float) -> void:
	if not parent or not parent.is_inside_tree():
		return

	var splash_root: Node3D = Node3D.new()
	parent.add_child(splash_root)
	splash_root.global_position = hit_pos + Vector3(0.0, 0.1, 0.0)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 16
	mesh_inst.mesh = torus
	splash_root.add_child(mesh_inst)

	var splash_mat: StandardMaterial3D = StandardMaterial3D.new()
	splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_mat.albedo_color = Color(0.0, 0.95, 1.0, 0.9)
	splash_mat.emission_enabled = true
	splash_mat.emission = Color(0.0, 1.0, 0.85, 1.0)
	splash_mat.emission_energy_multiplier = 3.5
	mesh_inst.material_override = splash_mat

	splash_root.scale = Vector3(0.1, 1.0, 0.1)

	var tween: Tween = splash_root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(splash_root, "scale", Vector3(radius, 1.0, radius), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(splash_mat, "albedo_color:a", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(splash_mat, "emission_energy_multiplier", 0.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(splash_root.queue_free)
