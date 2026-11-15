extends CharacterBody3D

## Controlador cinético en tercera persona estilo Risk of Rain 2.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto, -Z adelante).

signal pulse_fired(origin: Vector3, direction: Vector3, hit_collider: Node3D)

@export var move_speed: float = 8.0
@export var acceleration: float = 45.0
@export var friction: float = 35.0
@export var air_acceleration: float = 15.0

# Mecánicas de Deslizamiento (Slide con inercia)
@export var slide_speed: float = 15.0
@export var slide_friction: float = 5.0
@export var slide_duration: float = 1.0
var is_sliding: bool = false
var slide_timer: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO

# Mecánicas de Dash (Espacio con cooldown)
@export var dash_speed: float = 24.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

# Ganchazo de Atracción (Pull - Clic Derecho)
@export var pull_cooldown: float = 1.5
var pull_cooldown_timer: float = 0.0

# Disparo de Pulso Cinético (Clic Izquierdo)
@export var pulse_cooldown: float = 0.35
@export var pulse_force: float = 35.0
@export var pulse_range: float = 75.0
var pulse_cooldown_timer: float = 0.0

# Mecánica Anti-Kiting: Sobrecarga de Borde (Edge Overcharge)
var is_edge_overcharged: bool = false

# Retroceso e impacto cinético externo (empuje de Swarmers)
var external_knockback: Vector3 = Vector3.ZERO

# Sistema de Screen Shake
var shake_trauma: float = 0.0
const SHAKE_DECAY: float = 3.5

# Cámara y Sensibilidad
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch: float = -75.0
@export var max_pitch: float = 65.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var kinetic_cast: RayCast3D = $CameraPivot/SpringArm3D/Camera3D/KineticCast
@onready var visual_mesh: MeshInstance3D = $VisualMesh
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	if visual_mesh and visual_mesh.mesh:
		visual_mesh.mesh = visual_mesh.mesh.duplicate()

	floor_snap_length = 0.4
	floor_constant_speed = true
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(45.0)

	kinetic_cast.collision_mask = 5 # Capas 1 (World) y 3 (Enemies), ignora capa 2 (Player)
	kinetic_cast.collide_with_areas = false
	kinetic_cast.collide_with_bodies = true
	kinetic_cast.add_exception(self)

func _process(delta: float) -> void:
	_handle_screen_shake(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var current_pitch: float = camera_pivot.rotation.x - motion.relative.y * mouse_sensitivity
		camera_pivot.rotation.x = clampf(
			current_pitch,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	_check_edge_overcharge()
	_handle_timers(delta)
	_apply_gravity(delta)
	_handle_actions()
	_handle_movement(delta)

	# Sumar el retroceso externo acumulado a la velocidad horizontal y decaer rápidamente
	velocity.x += external_knockback.x
	velocity.z += external_knockback.z
	external_knockback = external_knockback.lerp(Vector3.ZERO, 15.0 * delta)
	if external_knockback.length_squared() < 0.001:
		external_knockback = Vector3.ZERO

	var was_grounded: bool = is_on_floor()
	move_and_slide()
	_prevent_rigidbody_lift(was_grounded)
	_push_enemies()

## Recibe empuje o retroceso cinético externo (ej. colisión de Swarmers)
func apply_knockback(force_vector: Vector3) -> void:
	# Asegurar que el empuje sea exclusivamente horizontal para empujar hacia el borde
	var h_force: Vector3 = Vector3(force_vector.x, 0.0, force_vector.z)
	external_knockback = h_force

## Evita que los rebotes físicos y colisiones con RigidBodies levanten al jugador del suelo
func _prevent_rigidbody_lift(was_grounded: bool) -> void:
	var collided_with_rigidbody: bool = false
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is RigidBody3D:
			collided_with_rigidbody = true
			break

	# Si estaba en el suelo o colisionó con un RigidBody, anular cualquier velocidad vertical ascendente
	if (was_grounded or collided_with_rigidbody) and velocity.y > 0.0:
		velocity.y = 0.0

	# Mantener anclaje al suelo firme si estaba apoyado
	if was_grounded and is_on_floor():
		velocity.y = minf(velocity.y, -0.1)

## Empuje sutil a enemigos RigidBody3D para que no se sientan como muros estáticos al caminar contra ellos
func _push_enemies() -> void:
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is RigidBody3D and (collider as Node3D).is_in_group("enemies"):
			var rb: RigidBody3D = collider as RigidBody3D
			var push_dir: Vector3 = -collision.get_normal()
			push_dir.y = 0.0
			if push_dir.length_squared() > 0.0001:
				push_dir = push_dir.normalized()
				var h_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
				if h_speed > 0.1:
					var push_impulse: float = h_speed * 0.12
					rb.apply_central_impulse(push_dir * push_impulse)

func _check_edge_overcharge() -> void:
	var was_overcharged: bool = is_edge_overcharged
	var max_dist_to_center: float = maxf(absf(global_position.x), absf(global_position.z))
	is_edge_overcharged = max_dist_to_center > 11.0 and is_on_floor()
	if is_edge_overcharged != was_overcharged:
		EventBus.edge_overcharge_changed.emit(is_edge_overcharged)

func _handle_timers(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	if pull_cooldown_timer > 0.0:
		pull_cooldown_timer -= delta

	if pulse_cooldown_timer > 0.0:
		var recharge_rate: float = 1.30 if is_edge_overcharged else 1.0
		pulse_cooldown_timer -= delta * recharge_rate

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false

	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0.0 or not is_on_floor():
			_stop_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1

func _handle_actions() -> void:
	if Input.is_action_just_pressed("fire") and pulse_cooldown_timer <= 0.0:
		_fire_kinetic_pulse()

	if Input.is_action_just_pressed("pull") and pull_cooldown_timer <= 0.0:
		_fire_pull()

	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		_start_dash()

	if Input.is_action_pressed("slide") and is_on_floor() and not is_sliding:
		_start_slide()
	elif not Input.is_action_pressed("slide") and is_sliding:
		_stop_slide()

func _get_input_direction() -> Vector3:
	var input_dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_back"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0

	input_dir = input_dir.normalized()
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	return direction

func _handle_movement(delta: float) -> void:
	if is_dashing:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		return

	if is_sliding:
		velocity.x = move_toward(velocity.x, 0.0, slide_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, slide_friction * delta)
		return

	var direction: Vector3 = _get_input_direction()
	var current_accel: float = acceleration if is_on_floor() else air_acceleration

	if direction != Vector3.ZERO:
		var target_vel_x: float = direction.x * move_speed
		var target_vel_z: float = direction.z * move_speed
		velocity.x = move_toward(velocity.x, target_vel_x, current_accel * delta)
		velocity.z = move_toward(velocity.z, target_vel_z, current_accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

func _start_dash() -> void:
	var move_dir: Vector3 = _get_input_direction()
	if move_dir == Vector3.ZERO:
		dash_direction = -transform.basis.z.normalized()
	else:
		dash_direction = move_dir

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	if is_sliding:
		_stop_slide()

func _start_slide() -> void:
	var move_dir: Vector3 = _get_input_direction()
	if move_dir == Vector3.ZERO:
		move_dir = -transform.basis.z.normalized()

	is_sliding = true
	slide_timer = slide_duration
	slide_direction = move_dir
	velocity.x = slide_direction.x * slide_speed
	velocity.z = slide_direction.z * slide_speed

	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
		capsule_shape.height = 1.0
		collision_shape.position.y = 0.5
		collision_shape.scale = Vector3.ONE

	if visual_mesh and visual_mesh.mesh is CapsuleMesh:
		var capsule_mesh: CapsuleMesh = visual_mesh.mesh as CapsuleMesh
		capsule_mesh.height = 1.0
		visual_mesh.position.y = 0.5
		visual_mesh.scale = Vector3.ONE

func _stop_slide() -> void:
	is_sliding = false
	slide_timer = 0.0
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
		capsule_shape.height = 1.8
		collision_shape.position.y = 0.9
		collision_shape.scale = Vector3.ONE

	if visual_mesh and visual_mesh.mesh is CapsuleMesh:
		var capsule_mesh: CapsuleMesh = visual_mesh.mesh as CapsuleMesh
		capsule_mesh.height = 1.8
		visual_mesh.position.y = 0.9
		visual_mesh.scale = Vector3.ONE

func _fire_kinetic_pulse() -> void:
	var overdrive_stacks: int = GameManager.get_upgrade_stacks("kinetic_overdrive")
	var cd_multiplier: float = pow(0.8, float(overdrive_stacks))
	pulse_cooldown_timer = pulse_cooldown * cd_multiplier

	var shot_origin: Vector3 = camera.global_position
	var shot_direction: Vector3 = -camera.global_transform.basis.z.normalized()

	kinetic_cast.target_position = Vector3(0.0, 0.0, -pulse_range)
	kinetic_cast.force_raycast_update()

	add_screen_shake(0.12)

	var hit_node: Node3D = null
	if kinetic_cast.is_colliding():
		var collider: Object = kinetic_cast.get_collider()
		if collider is Node3D and collider != self and (collider as Node3D).is_in_group("enemies"):
			hit_node = collider as Node3D
			_apply_kinetic_impulse(hit_node, shot_direction)

			# Sinergia shockwave_pulse: empuje radial secundario a enemigos cercanos
			var shockwave_stacks: int = GameManager.get_upgrade_stacks("shockwave_pulse")
			if shockwave_stacks > 0:
				var aoe_radius: float = 4.0 * (1.0 + float(shockwave_stacks - 1) * 0.25)
				var aoe_force: float = pulse_force * 0.6 * (1.0 + float(shockwave_stacks - 1) * 0.25)
				var hit_pos: Vector3 = hit_node.global_position
				for enemy_node: Node in get_tree().get_nodes_in_group("enemies"):
					if enemy_node != hit_node and enemy_node is Node3D and is_instance_valid(enemy_node):
						var other_enemy: Node3D = enemy_node as Node3D
						var diff: Vector3 = other_enemy.global_position - hit_pos
						var dist: float = diff.length()
						if dist <= aoe_radius and dist > 0.001:
							var aoe_dir: Vector3 = (diff.normalized() + shot_direction * 0.4 + Vector3(0.0, 0.25, 0.0)).normalized()
							var aoe_factor: float = clampf(1.0 - (dist / aoe_radius), 0.3, 1.0)
							if other_enemy.has_method("apply_kinetic_impulse"):
								other_enemy.call("apply_kinetic_impulse", aoe_dir * (aoe_force * aoe_factor), GameManager.combo_count)
							elif other_enemy is RigidBody3D:
								(other_enemy as RigidBody3D).apply_central_impulse(aoe_dir * (aoe_force * aoe_factor))

	# Garantizar que no se aplique ningún retroceso vertical en el eje Y
	if is_on_floor():
		velocity.y = -0.1
	elif velocity.y > 0.0:
		velocity.y = 0.0

	pulse_fired.emit(shot_origin, shot_direction, hit_node)
	EventBus.pulse_fired.emit(shot_origin, shot_direction, hit_node)

func get_pull_target_position() -> Vector3:
	var cam_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	return camera.global_position + (cam_forward * 2.5) + (Vector3.UP * 1.0)

func _fire_pull() -> void:
	var enemy: Node3D = _find_pull_target()
	if not enemy:
		return

	var overdrive_stacks: int = GameManager.get_upgrade_stacks("kinetic_overdrive")
	var cd_multiplier: float = pow(0.8, float(overdrive_stacks))
	pull_cooldown_timer = pull_cooldown * cd_multiplier
	add_screen_shake(0.22)
	EventBus.pull_fired.emit(enemy)

	# Punto situado 2.5m frente a la cámara del jugador (+ Vector3.UP * 1.0)
	var suspend_target: Vector3 = get_pull_target_position()

	if enemy.has_method("apply_pull"):
		enemy.call("apply_pull", suspend_target, self)
	elif enemy is RigidBody3D:
		var rb: RigidBody3D = enemy as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.gravity_scale = 0.05
		var pull_dir: Vector3 = suspend_target - rb.global_position
		rb.apply_central_impulse(pull_dir.normalized() * 12.0)
		var timer: SceneTreeTimer = get_tree().create_timer(0.6, true, false, true)
		timer.timeout.connect(_restore_enemy_gravity.bind(rb))

	# Sinergia gravity_singularity: pulso gravitacional que arrastra enemigos cercanos en 4.5m
	var singularity_stacks: int = GameManager.get_upgrade_stacks("gravity_singularity")
	if singularity_stacks > 0:
		var singularity_radius: float = 4.5 * (1.0 + float(singularity_stacks - 1) * 0.20)
		var origin_pos: Vector3 = enemy.global_position
		for enemy_node: Node in get_tree().get_nodes_in_group("enemies"):
			if enemy_node != enemy and enemy_node is Node3D and is_instance_valid(enemy_node):
				var sec_enemy: Node3D = enemy_node as Node3D
				var diff_from_target: Vector3 = sec_enemy.global_position - origin_pos
				if diff_from_target.length() <= singularity_radius:
					if sec_enemy.has_method("apply_pull"):
						sec_enemy.call("apply_pull", suspend_target, self)
					elif sec_enemy is RigidBody3D:
						var sec_rb: RigidBody3D = sec_enemy as RigidBody3D
						sec_rb.linear_velocity = Vector3.ZERO
						sec_rb.angular_velocity = Vector3.ZERO
						sec_rb.gravity_scale = 0.05
						var sec_pull_dir: Vector3 = suspend_target - sec_rb.global_position
						sec_rb.apply_central_impulse(sec_pull_dir.normalized() * 12.0)
						var sec_timer: SceneTreeTimer = get_tree().create_timer(0.6, true, false, true)
						sec_timer.timeout.connect(_restore_enemy_gravity.bind(sec_rb))

func _restore_enemy_gravity(target_rb: RigidBody3D) -> void:
	if is_instance_valid(target_rb):
		target_rb.gravity_scale = 1.0

func _find_pull_target() -> Node3D:
	kinetic_cast.target_position = Vector3(0.0, 0.0, -pulse_range)
	kinetic_cast.force_raycast_update()

	if kinetic_cast.is_colliding():
		var col: Object = kinetic_cast.get_collider()
		if col is Node3D and col != self and (col as Node3D).is_in_group("enemies"):
			return col as Node3D

	# Cono de asistencia y barrido esférico de radio 0.8m desde la cámara
	var cam_pos: Vector3 = camera.global_position
	var cam_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")

	var best_enemy: Node3D = null
	var best_score: float = 9999.0

	for node: Node in enemies:
		if node == self or not (node is Node3D) or not is_instance_valid(node):
			continue
		var enemy: Node3D = node as Node3D
		var to_enemy: Vector3 = enemy.global_position - cam_pos
		var dist: float = to_enemy.length()
		if dist < 0.5 or dist > pulse_range:
			continue

		var forward_proj: float = to_enemy.dot(cam_dir)
		if forward_proj <= 0.0:
			continue

		var perp_dist: float = (to_enemy - cam_dir * forward_proj).length()
		var shockwave_stacks: int = GameManager.get_upgrade_stacks("shockwave_pulse")
		var cone_mult: float = 1.0 + float(shockwave_stacks) * 0.25
		var max_allowed_perp: float = maxf(1.4, forward_proj * 0.18) * cone_mult
		if perp_dist <= max_allowed_perp:
			var score: float = perp_dist * 2.5 + (dist * 0.1)
			if score < best_score:
				best_score = score
				best_enemy = enemy

	return best_enemy

func _apply_kinetic_impulse(target: Node3D, direction: Vector3) -> void:
	if not target or target == self or not target.is_in_group("enemies"):
		return
	var launch_vector: Vector3 = (direction + Vector3(0.0, 0.25, 0.0)).normalized() * pulse_force
	if target.has_method("apply_kinetic_impulse"):
		target.call("apply_kinetic_impulse", launch_vector, GameManager.combo_count)
	elif target.has_method("launch"):
		target.call("launch", launch_vector)
		EventBus.enemy_launched.emit(target, pulse_force)
	elif target is RigidBody3D:
		var rigid: RigidBody3D = target as RigidBody3D
		rigid.apply_central_impulse(launch_vector)
		EventBus.enemy_launched.emit(rigid, pulse_force)
	elif target.has_method("apply_impulse"):
		target.call("apply_impulse", launch_vector)
		EventBus.enemy_launched.emit(target, pulse_force)

func add_screen_shake(amount: float) -> void:
	shake_trauma = clampf(shake_trauma + amount, 0.0, 1.0)

func _handle_screen_shake(delta: float) -> void:
	if shake_trauma > 0.0:
		shake_trauma = maxf(0.0, shake_trauma - SHAKE_DECAY * delta)
		var shake_amount: float = shake_trauma * shake_trauma
		camera.h_offset = randf_range(-0.15, 0.15) * shake_amount
		camera.v_offset = randf_range(-0.15, 0.15) * shake_amount
		camera.rotation.z = deg_to_rad(randf_range(-1.2, 1.2)) * shake_amount
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		camera.rotation.z = 0.0
