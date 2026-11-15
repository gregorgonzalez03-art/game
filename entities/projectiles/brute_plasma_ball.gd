extends Area3D

## Proyectil de Presión Cinética / Bola de Plasma de la Torre Brute (Paso 4.1).
## Se desplaza lento a ras de suelo y puede ser devuelto / desviado por el Pulso Cinético del jugador.
## Cumple estrictamente con AGENTS.md (tipado estricto, Godot 4.x).

const ENEMY_SHADER: Shader = preload("res://entities/effects/enemy_hit_fresnel.gdshader")

@export var speed: float = 10.0
@export var deflected_speed: float = 32.0
@export var damage_force: float = 7.8
@export var lifetime: float = 8.0

var direction: Vector3 = Vector3.FORWARD
var is_deflected: bool = false
var life_timer: float = 0.0
var shader_mat: ShaderMaterial = null

@onready var visual_mesh: MeshInstance3D = $MeshInstance3D
@onready var omni_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group("deflectable")
	body_entered.connect(_on_body_entered)
	EventBus.pulse_fired.connect(_on_player_pulse_fired)
	_setup_shader()

func _setup_shader() -> void:
	if not visual_mesh:
		return
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = ENEMY_SHADER
	shader_mat.set_shader_parameter("albedo_color", Color(0.95, 0.1, 0.7, 1.0))
	shader_mat.set_shader_parameter("emission_color", Color(1.0, 0.15, 0.9, 1.0))
	shader_mat.set_shader_parameter("emission_energy", 3.2)
	shader_mat.set_shader_parameter("dissolve_edge_color", Color("#FF00D4"))
	visual_mesh.material_override = shader_mat

func setup_trajectory(start_pos: Vector3, target_dir: Vector3) -> void:
	global_position = start_pos
	direction = target_dir.normalized()
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	life_timer += delta
	if life_timer >= lifetime:
		_destroy()
		return

	var current_spd: float = deflected_speed if is_deflected else speed
	global_position += direction * (current_spd * delta)

	# Rotación visual constante
	rotate_object_local(Vector3(1.0, 0.5, 0.0).normalized(), delta * 8.0)

## Devuelve o desvía el proyectil con el Pulso Cinético del jugador
func deflect(new_direction: Vector3) -> void:
	if is_deflected:
		return
	is_deflected = true
	direction = new_direction.normalized()
	life_timer = 0.0

	# Cambio de identidad visual: de Magenta Hostil a Cian Neón Aliado
	if shader_mat:
		shader_mat.set_shader_parameter("albedo_color", Color(0.0, 0.9, 1.0, 1.0))
		shader_mat.set_shader_parameter("emission_color", Color(0.1, 1.0, 0.95, 1.0))
		shader_mat.set_shader_parameter("emission_energy", 4.5)
		shader_mat.set_shader_parameter("hit_flash", 1.0)
		shader_mat.set_shader_parameter("dissolve_edge_color", Color("#00FFFF"))

		var tween: Tween = create_tween()
		tween.tween_method(
			func(val: float) -> void:
				if shader_mat:
					shader_mat.set_shader_parameter("hit_flash", val),
			1.0, 0.0, 0.15
		)

	if omni_light:
		omni_light.light_color = Color(0.0, 0.9, 1.0)
		omni_light.light_energy = 2.5

	GameManager.trigger_hit_stop(0.05)
	GameManager.add_combo()
	EventBus.chain_collision.emit(GameManager.combo_count, global_position)

func apply_kinetic_impulse(impulse: Vector3, _combo_level: int = 0, _is_chain: bool = false) -> void:
	deflect(impulse.normalized())

func _on_player_pulse_fired(origin: Vector3, shot_dir: Vector3, hit_node: Node3D) -> void:
	if is_deflected:
		return
	if hit_node == self:
		deflect(shot_dir)
		return

	# Detección por proximidad al disparo del jugador (parry generoso)
	var diff: Vector3 = global_position - origin
	var dist: float = diff.length()
	if dist <= 4.5:
		var dot_prod: float = shot_dir.dot(diff.normalized())
		if dot_prod > 0.5:
			deflect(shot_dir)

func _on_body_entered(body: Node) -> void:
	if not is_deflected:
		if body.is_in_group("player"):
			if body.has_method("apply_knockback"):
				body.call("apply_knockback", direction * damage_force)
			if body.has_method("add_screen_shake"):
				body.call("add_screen_shake", 0.22)
			_destroy()
		elif body.is_in_group("enemies") and body != self:
			pass
		elif body is StaticBody3D:
			_destroy()
	else:
		if body.is_in_group("enemies"):
			var impact_force: Vector3 = (direction + Vector3(0.0, 0.25, 0.0)).normalized() * 45.0
			if body.has_method("apply_kinetic_impulse"):
				body.call("apply_kinetic_impulse", impact_force, GameManager.combo_count, true)
			elif body is RigidBody3D:
				(body as RigidBody3D).apply_central_impulse(impact_force)
			GameManager.trigger_hit_stop(0.06)
			GameManager.add_combo()
			EventBus.chain_collision.emit(GameManager.combo_count, global_position)
			_destroy()
		elif body is StaticBody3D:
			_destroy()

func _destroy() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)

	if shader_mat:
		var tween: Tween = create_tween()
		tween.tween_method(
			func(val: float) -> void:
				if shader_mat:
					shader_mat.set_shader_parameter("dissolve_amount", val),
			0.0, 1.0, 0.2
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.finished.connect(queue_free)
	else:
		queue_free()
