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

const ENEMY_SHADER: Shader = preload("res://entities/effects/enemy_hit_fresnel.gdshader")

var is_launched: bool = false
var projectile_timer: float = 0.0
var player_ref: Node3D = null
var push_cooldown_timer: float = 0.0

# Estado de atracción magnética (Ganchazo)
var is_being_pulled: bool = false
var pull_target_pos: Vector3 = Vector3.ZERO
var pull_timer: float = 0.0
var pull_player_ref: Node3D = null
var is_dead: bool = false
var has_hit_other_enemy: bool = false

var shader_mat: ShaderMaterial = null
var hit_flash_tween: Tween = null
var dissolve_tween: Tween = null

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

	_setup_shader()

	# Asegurar desfreeze tras 0.4s
	var tree: SceneTree = get_tree()
	if tree:
		tree.create_timer(0.4, false).timeout.connect(func() -> void:
			if is_instance_valid(self):
				freeze = false
		)

func _setup_shader() -> void:
	if not visual_mesh:
		return
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = ENEMY_SHADER
	shader_mat.set_shader_parameter("albedo_color", Color(0.95, 0.08, 0.12, 1.0))
	shader_mat.set_shader_parameter("emission_color", Color(0.95, 0.08, 0.12, 1.0))
	shader_mat.set_shader_parameter("emission_energy", 0.5)
	shader_mat.set_shader_parameter("dissolve_edge_color", Color("#00E5FF"))
	visual_mesh.material_override = shader_mat

func play_hit_flash() -> void:
	if not shader_mat:
		return
	if hit_flash_tween and hit_flash_tween.is_valid():
		hit_flash_tween.kill()
	hit_flash_tween = create_tween()
	shader_mat.set_shader_parameter("hit_flash", 1.0)
	hit_flash_tween.tween_method(
		func(val: float) -> void:
			if shader_mat:
				shader_mat.set_shader_parameter("hit_flash", val),
		1.0, 0.0, 0.12
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func play_dissolve(duration: float = 0.28, on_complete: Callable = Callable()) -> void:
	if not shader_mat:
		if on_complete.is_valid():
			on_complete.call()
		return
	if dissolve_tween and dissolve_tween.is_valid():
		dissolve_tween.kill()
	dissolve_tween = create_tween()
	dissolve_tween.tween_method(
		func(val: float) -> void:
			if shader_mat:
				shader_mat.set_shader_parameter("dissolve_amount", val),
		0.0, 1.0, duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if on_complete.is_valid():
		dissolve_tween.finished.connect(on_complete)

func die_and_drop_xp() -> void:
	if is_dead:
		return
	is_dead = true
	if is_in_group("enemies"):
		remove_from_group("enemies")

	# Sinergia volatile_shrapnel: micro-onda expansiva si eliminó/chocó con un enemigo
	var shrapnel_stacks: int = GameManager.get_upgrade_stacks("volatile_shrapnel")
	if has_hit_other_enemy and shrapnel_stacks > 0:
		_trigger_micro_shockwave()

	EventBus.enemy_eliminated.emit(self, GameManager.combo_count)
	GameManager.spawn_xp_shard_at_edge(global_position)

	if global_position.y >= -3.0:
		freeze = true
		$CollisionShape3D.set_deferred("disabled", true)
		play_dissolve(0.25, queue_free)
	else:
		queue_free()
	GameManager.spawn_xp_shard_at_edge(global_position)
	queue_free()

func _trigger_micro_shockwave() -> void:
	var death_pos: Vector3 = global_position
	var shrapnel_stacks: int = GameManager.get_upgrade_stacks("volatile_shrapnel")
	var shockwave_radius: float = 4.5 * (1.0 + float(shrapnel_stacks - 1) * 0.25)
	var shockwave_force: float = 18.0 * (1.0 + float(shrapnel_stacks - 1) * 0.25)
	for enemy_node: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy_node != self and enemy_node is Node3D and is_instance_valid(enemy_node):
			var other: Node3D = enemy_node as Node3D
			var diff: Vector3 = other.global_position - death_pos
			var dist: float = diff.length()
			if dist <= shockwave_radius and dist > 0.001:
				var blast_dir: Vector3 = (diff.normalized() + Vector3(0.0, 0.35, 0.0)).normalized()
				var factor: float = clampf(1.0 - (dist / shockwave_radius), 0.25, 1.0)
				if other.has_method("apply_kinetic_impulse"):
					other.call("apply_kinetic_impulse", blast_dir * shockwave_force * factor, GameManager.combo_count)
				elif other is RigidBody3D:
					(other as RigidBody3D).apply_central_impulse(blast_dir * shockwave_force * factor)

func _physics_process(delta: float) -> void:
	var h_dist: float = Vector2(global_position.x, global_position.z).length()
	if global_position.y < -5.0 or h_dist > 22.0:
		die_and_drop_xp()
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
			if shader_mat:
				shader_mat.set_shader_parameter("emission_energy", 0.5)
		else:
			_apply_in_flight_magnetic_guidance(delta)

	var current_speed: float = linear_velocity.length()
	if is_launched and projectile_timer <= 0.0 and current_speed < 2.5:
		is_launched = false

	if not is_launched:
		_check_player_contact()
		_pursue_player()

func apply_pull(target_pos: Vector3, player_node: Node3D = null) -> void:
	play_hit_flash()
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
	play_hit_flash()
	is_being_pulled = false
	gravity_scale = 1.0
	is_launched = true
	projectile_timer = PROJECTILE_DURATION
	linear_damp = PROJECTILE_LINEAR_DAMP

	var assisted_impulse: Vector3 = _calculate_magnetic_assistance(impulse)
	apply_central_impulse(assisted_impulse)
	EventBus.enemy_launched.emit(self, assisted_impulse.length())

	if shader_mat:
		shader_mat.set_shader_parameter("emission_energy", 2.5 + float(combo_level) * 0.5)

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
			has_hit_other_enemy = true
			var transfer_dir: Vector3 = (other_enemy.global_position - global_position).normalized()
			if transfer_dir == Vector3.ZERO:
				transfer_dir = -global_transform.basis.z

			var ricochet_stacks: int = GameManager.get_upgrade_stacks("elastic_ricochet")
			var ricochet_mult: float = 1.0 + float(ricochet_stacks) * 0.35
			var effective_chain_mult: float = chain_multiplier * ricochet_mult
			var transfer_impulse: Vector3 = (transfer_dir + Vector3(0.0, 0.2, 0.0)).normalized() * (speed * effective_chain_mult)

			GameManager.trigger_hit_stop(0.05)
			GameManager.add_combo()
			play_hit_flash()
			if other_enemy.has_method("play_hit_flash"):
				other_enemy.call("play_hit_flash")
			EventBus.chain_collision.emit(GameManager.combo_count, global_position)
			other_enemy.call("apply_kinetic_impulse", transfer_impulse, GameManager.combo_count)

			if ricochet_stacks > 0:
				var rebound_dir: Vector3 = (-transfer_dir + Vector3(0.0, 0.25, 0.0)).normalized()
				apply_central_impulse(rebound_dir * (speed * 0.45 * ricochet_mult))
