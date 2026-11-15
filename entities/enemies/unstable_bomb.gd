extends RigidBody3D

## Enemigo / Objeto Cinético Arquetipo: Unstable Bomb.
## Masa 3.0 kg. Al ser lanzado o chocar a alta velocidad, detona una
## onda expansiva radial que lanza a todos los cuerpos cercanos.

const ENEMY_SHADER: Shader = preload("res://entities/effects/enemy_hit_fresnel.gdshader")

@export var mass_weight: float = 3.0
@export var blast_radius: float = 7.0
@export var blast_force: float = 38.0
@export var fuse_duration: float = 1.5
@export var high_speed_threshold: float = 4.5

var is_launched: bool = false
var fuse_timer: float = 0.0
var is_exploding: bool = false
var pulse_time: float = 0.0

# Estado de atracción magnética (Ganchazo)
var is_being_pulled: bool = false
var pull_target_pos: Vector3 = Vector3.ZERO
var pull_timer: float = 0.0
var pull_player_ref: Node3D = null
var is_dead: bool = false

var shader_mat: ShaderMaterial = null
var hit_flash_tween: Tween = null
var dissolve_tween: Tween = null

@onready var visual_mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("bombs")
	mass = mass_weight
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp = 1.0
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
	shader_mat.set_shader_parameter("albedo_color", Color(1.0, 0.45, 0.05, 1.0))
	shader_mat.set_shader_parameter("emission_color", Color(1.0, 0.4, 0.0, 1.0))
	shader_mat.set_shader_parameter("emission_energy", 1.6)
	shader_mat.set_shader_parameter("dissolve_edge_color", Color("#FFAA00"))
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

func play_dissolve(duration: float = 0.25, on_complete: Callable = Callable()) -> void:
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
	EventBus.enemy_eliminated.emit(self, GameManager.combo_count)
	GameManager.spawn_xp_shard_at_edge(global_position)
	if global_position.y >= -3.0:
		freeze = true
		$CollisionShape3D.set_deferred("disabled", true)
		play_dissolve(0.25, queue_free)
	else:
		queue_free()

func _physics_process(delta: float) -> void:
	var h_dist: float = Vector2(global_position.x, global_position.z).length()
	if global_position.y < -5.0 or h_dist > 22.0:
		die_and_drop_xp()
		return

	# Pulso visual constante neón naranja/dorado
	pulse_time += delta * (14.0 if is_launched else 4.0)
	if shader_mat:
		var base_energy: float = 2.4 if is_launched else 1.2
		var amp: float = 1.4 if is_launched else 0.5
		shader_mat.set_shader_parameter("emission_energy", base_energy + sin(pulse_time) * amp)

	if is_being_pulled:
		_process_pull(delta)
		return

	if is_launched and not is_exploding:
		fuse_timer -= delta
		if fuse_timer <= 0.0:
			explode()

func apply_kinetic_impulse(impulse: Vector3, _combo_level: int, _is_chain: bool = false) -> void:
	play_hit_flash()
	is_being_pulled = false
	gravity_scale = 1.0
	is_launched = true
	fuse_timer = fuse_duration
	linear_damp = 0.05
	apply_central_impulse(impulse)
	EventBus.enemy_launched.emit(self, impulse.length())

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

func _on_body_entered(_body: Node) -> void:
	if is_launched:
		explode()

func explode() -> void:
	if is_exploding:
		return
	is_exploding = true
	remove_from_group("enemies")

	var bomb_pos: Vector3 = global_position
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()

	var shrapnel_stacks: int = GameManager.get_upgrade_stacks("volatile_shrapnel")
	var effective_blast_radius: float = blast_radius * (1.0 + float(shrapnel_stacks) * 0.30)
	shape.radius = effective_blast_radius

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), bomb_pos)
	query.collision_mask = 0xFFFFFFFF

	var results: Array[Dictionary] = space_state.intersect_shape(query, 32)
	for item: Dictionary in results:
		var collider: Object = item.get("collider")
		if collider is Node3D and collider != self:
			var target_node: Node3D = collider as Node3D
			var diff: Vector3 = target_node.global_position - bomb_pos
			var dist: float = diff.length()
			if dist < 0.001:
				diff = Vector3(0.0, 1.0, 0.0)
				dist = 1.0

			var factor: float = clampf(1.0 - (dist / effective_blast_radius), 0.2, 1.0)
			var blast_dir: Vector3 = (diff.normalized() + Vector3(0.0, 0.35, 0.0)).normalized()
			var blast_impulse: Vector3 = blast_dir * (blast_force * factor)

			if target_node.has_method("take_damage") and target_node.is_in_group("brutes"):
				target_node.call("take_damage", 55.0, bomb_pos)
			elif target_node.has_method("apply_kinetic_impulse"):
				target_node.call("apply_kinetic_impulse", blast_impulse, GameManager.combo_count)
			elif target_node is RigidBody3D:
				var rb: RigidBody3D = target_node as RigidBody3D
				rb.apply_central_impulse(blast_impulse)
			elif target_node.is_in_group("player"):
				if target_node.has_method("add_screen_shake"):
					target_node.call("add_screen_shake", 0.6)

	# Hit-stop centralizado exclusivamente en GameManager
	GameManager.trigger_hit_stop(0.05)

	GameManager.add_combo()
	EventBus.chain_collision.emit(GameManager.combo_count, bomb_pos)
	EventBus.enemy_eliminated.emit(self, GameManager.combo_count)
	GameManager.spawn_xp_shard_at_edge(bomb_pos)
	freeze = true
	$CollisionShape3D.set_deferred("disabled", true)
	play_dissolve(0.24, queue_free)
