extends RigidBody3D

## Enemigo Cinético Arquetipo: Swarmer.
## RigidBody3D con persecución suave, modo proyectil (disco de hockey),
## asistencia magnética de hasta 15 grados y frenado magnético al ser atraído.

@export var mass_weight: float = 1.5
@export var pursue_speed: float = 4.5
@export var pursue_force: float = 14.0
@export var high_speed_threshold: float = 6.0
@export var chain_multiplier: float = 1.4

const NORMAL_LINEAR_DAMP: float = 1.2
const PROJECTILE_LINEAR_DAMP: float = 0.05
const PROJECTILE_DURATION: float = 1.2
const MAX_MAGNETIC_ANGLE_DEG: float = 15.0
const MAGNETIC_SEARCH_RADIUS: float = 25.0
const PUSH_FORCE: float = 5.0
const PUSH_COOLDOWN: float = 0.35

var is_launched: bool = false
var projectile_timer: float = 0.0
var player_ref: Node3D = null
var push_cooldown_timer: float = 0.0

# Estado de atracción magnética (Ganchazo)
var is_being_pulled: bool = false
var pull_target_pos: Vector3 = Vector3.ZERO
var pull_timer: float = 0.0
var pull_player_ref: Node3D = null

@onready var visual_mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("swarmers")
	mass = mass_weight
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp = NORMAL_LINEAR_DAMP
	angular_damp = 2.0
	body_entered.connect(_on_body_entered)
	freeze = false

	# Asegurar desfreeze tras 0.4s
	var tree: SceneTree = get_tree()
	if tree:
		tree.create_timer(0.4, false).timeout.connect(func() -> void:
			if is_instance_valid(self):
				freeze = false
		)

func _physics_process(delta: float) -> void:
	var h_dist: float = Vector2(global_position.x, global_position.z).length()
	if global_position.y < -5.0 or h_dist > 22.0:
		if is_in_group("enemies"):
			remove_from_group("enemies")
			EventBus.enemy_eliminated.emit(self, GameManager.combo_count)
		queue_free()
		return

	if push_cooldown_timer > 0.0:
		push_cooldown_timer -= delta

	if is_being_pulled:
		_process_pull(delta)
		return

	if projectile_timer > 0.0:
		projectile_timer -= delta
		if projectile_timer <= 0.0:
			linear_damp = NORMAL_LINEAR_DAMP
		else:
			_apply_in_flight_magnetic_guidance(delta)

	var current_speed: float = linear_velocity.length()
	if is_launched and projectile_timer <= 0.0 and current_speed < 2.5:
		is_launched = false

	if not is_launched:
		_check_player_contact()
		_pursue_player()

func apply_pull(target_pos: Vector3, player_node: Node3D = null) -> void:
	is_being_pulled = true
	pull_target_pos = target_pos
	pull_player_ref = player_node
	pull_timer = 0.6
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 0.05

func _process_pull(delta: float) -> void:
	pull_timer -= delta
	if pull_player_ref and is_instance_valid(pull_player_ref) and pull_player_ref.has_method("get_pull_target_position"):
		pull_target_pos = pull_player_ref.call("get_pull_target_position")

	var diff: Vector3 = pull_target_pos - global_position
	var dist: float = diff.length()

	if dist < 0.8 or pull_timer <= 0.0:
		is_being_pulled = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		gravity_scale = 0.05
		var hover_timer: SceneTreeTimer = get_tree().create_timer(0.6, true, false, true)
		hover_timer.timeout.connect(_on_pull_release)
	else:
		var pull_speed: float = clampf(dist * 9.0, 12.0, 26.0)
		linear_velocity = diff.normalized() * pull_speed

func _on_pull_release() -> void:
	if not is_being_pulled and not is_launched:
		gravity_scale = 1.0

func _pursue_player() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D

	if not player_ref:
		return

	var diff: Vector3 = player_ref.global_position - global_position
	diff.y = 0.0
	var distance: float = diff.length()

	if distance > 1.2:
		var dir: Vector3 = diff.normalized()
		var horizontal_vel: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if horizontal_vel.length() < pursue_speed:
			apply_central_force(dir * pursue_force)

## Impacto cinético recibido: activa el Modo Proyectil con asistencia magnética
func apply_kinetic_impulse(impulse: Vector3, combo_level: int, _is_chain: bool = false) -> void:
	is_being_pulled = false
	gravity_scale = 1.0
	is_launched = true
	projectile_timer = PROJECTILE_DURATION
	linear_damp = PROJECTILE_LINEAR_DAMP

	var assisted_impulse: Vector3 = _calculate_magnetic_assistance(impulse)
	apply_central_impulse(assisted_impulse)
	EventBus.enemy_launched.emit(self, assisted_impulse.length())

	if visual_mesh and visual_mesh.material_override:
		var mat: StandardMaterial3D = visual_mesh.material_override as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 2.5 + float(combo_level) * 0.5

func _calculate_magnetic_assistance(raw_impulse: Vector3) -> Vector3:
	var impulse_speed: float = raw_impulse.length()
	if impulse_speed < 0.001:
		return raw_impulse

	var raw_dir: Vector3 = raw_impulse.normalized()
	var best_target: Node3D = _find_best_magnetic_target(raw_dir)

	if not best_target:
		return raw_impulse

	var target_diff: Vector3 = best_target.global_position - global_position
	var target_dir: Vector3 = target_diff.normalized()
	var angle_rad: float = raw_dir.angle_to(target_dir)
	var max_angle_rad: float = deg_to_rad(MAX_MAGNETIC_ANGLE_DEG)

	if angle_rad <= 0.001:
		return raw_impulse

	var steer_weight: float = clampf(max_angle_rad / angle_rad, 0.0, 1.0)
	var assisted_dir: Vector3 = raw_dir.slerp(target_dir, steer_weight).normalized()
	return assisted_dir * impulse_speed

func _apply_in_flight_magnetic_guidance(delta: float) -> void:
	var speed: float = linear_velocity.length()
	if speed < high_speed_threshold:
		return

	var current_dir: Vector3 = linear_velocity.normalized()
	var target: Node3D = _find_best_magnetic_target(current_dir)
	if not target:
		return

	var target_dir: Vector3 = (target.global_position - global_position).normalized()
	var angle_rad: float = current_dir.angle_to(target_dir)
	if angle_rad <= deg_to_rad(MAX_MAGNETIC_ANGLE_DEG):
		var turn_rate: float = clampf(delta * 4.0, 0.0, 0.25)
		var guided_dir: Vector3 = current_dir.slerp(target_dir, turn_rate).normalized()
		linear_velocity = guided_dir * speed

func _find_best_magnetic_target(forward_dir: Vector3) -> Node3D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	var best_candidate: Node3D = null
	var min_distance: float = MAGNETIC_SEARCH_RADIUS
	var max_angle_rad: float = deg_to_rad(MAX_MAGNETIC_ANGLE_DEG)

	for node: Node in enemies:
		if node == self or not (node is Node3D):
			continue
		var enemy: Node3D = node as Node3D
		if not is_instance_valid(enemy):
			continue

		var to_enemy: Vector3 = enemy.global_position - global_position
		var dist: float = to_enemy.length()
		if dist < 0.5 or dist > MAGNETIC_SEARCH_RADIUS:
			continue

		var enemy_dir: Vector3 = to_enemy.normalized()
		var angle: float = forward_dir.angle_to(enemy_dir)
		if angle <= max_angle_rad and dist < min_distance:
			min_distance = dist
			best_candidate = enemy

	return best_candidate

func _check_player_contact() -> void:
	if push_cooldown_timer > 0.0:
		return
	for body: Node in get_colliding_bodies():
		if body is Node3D and body.is_in_group("player"):
			_try_push_player(body as Node3D)
			break

func _try_push_player(player_node: Node3D) -> void:
	if push_cooldown_timer > 0.0:
		return
	push_cooldown_timer = PUSH_COOLDOWN

	var push_dir: Vector3 = (player_node.global_position - global_position).normalized()
	push_dir.y = 0.0
	if push_dir.length_squared() < 0.0001:
		push_dir = -global_transform.basis.z
	push_dir = push_dir.normalized()

	if player_node.has_method("apply_knockback"):
		player_node.call("apply_knockback", push_dir * PUSH_FORCE)
	if player_node.has_method("add_screen_shake"):
		player_node.call("add_screen_shake", 0.06)

func _on_body_entered(body: Node) -> void:
	if body is Node3D and body.is_in_group("player"):
		_try_push_player(body as Node3D)
		return

	if not is_launched:
		return

	var speed: float = linear_velocity.length()
	if speed < high_speed_threshold:
		return

	if body is Node3D and body.is_in_group("enemies") and body != self:
		var other_enemy: Node3D = body as Node3D
		if other_enemy.has_method("apply_kinetic_impulse"):
			var transfer_dir: Vector3 = (other_enemy.global_position - global_position).normalized()
			if transfer_dir == Vector3.ZERO:
				transfer_dir = -global_transform.basis.z

			var transfer_impulse: Vector3 = (transfer_dir + Vector3(0.0, 0.2, 0.0)).normalized() * (speed * chain_multiplier)

			GameManager.trigger_hit_stop(0.05)
			GameManager.add_combo()
			EventBus.chain_collision.emit(GameManager.combo_count, global_position)
			other_enemy.call("apply_kinetic_impulse", transfer_impulse, GameManager.combo_count)
