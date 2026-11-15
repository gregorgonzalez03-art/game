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

# Mecánicas de Dash (Impulso horizontal con cooldown)
@export var dash_speed: float = 24.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

# Disparo de Pulso Cinético
@export var pulse_cooldown: float = 0.35
@export var pulse_force: float = 32.0
@export var pulse_range: float = 75.0
var pulse_cooldown_timer: float = 0.0

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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		# Rotación horizontal del jugador (Yaw)
		rotate_y(-motion.relative.x * mouse_sensitivity)
		# Rotación vertical del pivote de cámara (Pitch)
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
	_handle_timers(delta)
	_apply_gravity(delta)
	_handle_actions()
	_handle_movement(delta)
	move_and_slide()

func _handle_timers(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta

	if pulse_cooldown_timer > 0.0:
		pulse_cooldown_timer -= delta

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
		if velocity.y < 0.0:
			velocity.y = -0.1

func _handle_actions() -> void:
	# Disparo de pulso cinético (Clic izquierdo)
	if Input.is_action_just_pressed("fire") and pulse_cooldown_timer <= 0.0:
		_fire_kinetic_pulse()

	# Dash / Impulso horizontal (Espacio o Clic derecho)
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0:
		_start_dash()

	# Deslizamiento (Shift o Ctrl)
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
	# Dirección relativa al forward (-Z) y right (+X) del jugador
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	return direction

func _handle_movement(delta: float) -> void:
	if is_dashing:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		return

	if is_sliding:
		# En slide conservamos inercia con baja fricción
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
		# Si no hay input WASD, dashea hacia el frente del jugador (-Z)
		dash_direction = -transform.basis.z.normalized()
	else:
		dash_direction = move_dir

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	# Si estábamos deslizando, cancelamos para dar paso al dash
	if is_sliding:
		_stop_slide()

func _start_slide() -> void:
	var move_dir: Vector3 = _get_input_direction()
	if move_dir == Vector3.ZERO:
		move_dir = -transform.basis.z.normalized()

	is_sliding = true
	slide_timer = slide_duration
	slide_direction = move_dir
	# Impulso inicial de slide
	velocity.x = slide_direction.x * slide_speed
	velocity.z = slide_direction.z * slide_speed

	# Postura agachada: modificar height del CapsuleShape3D y CapsuleMesh directamente
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
	pulse_cooldown_timer = pulse_cooldown
	var shot_origin: Vector3 = camera.global_position
	# La cámara mira hacia -Z en su espacio local
	var shot_direction: Vector3 = -camera.global_transform.basis.z.normalized()

	kinetic_cast.target_position = Vector3(0.0, 0.0, -pulse_range)
	kinetic_cast.force_raycast_update()

	var hit_node: Node3D = null
	if kinetic_cast.is_colliding():
		var collider: Object = kinetic_cast.get_collider()
		if collider is Node3D:
			hit_node = collider as Node3D
			_apply_kinetic_impulse(hit_node, shot_direction)

	pulse_fired.emit(shot_origin, shot_direction, hit_node)

func _apply_kinetic_impulse(target: Node3D, direction: Vector3) -> void:
	# Lanzamiento con vector ligeramente elevado para parábola cinemática
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
