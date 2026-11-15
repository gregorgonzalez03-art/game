extends RigidBody3D

## Enemigo Cinético Arquetipo: Brute (Tanque Pesado).
## Masa 25.0 kg. Inmune inicialmente a pulsos directos leves, pero vulnerable:
##   - Choques en cadena de otros enemigos lanzados le rompen la resistencia (2 impactos).
##   - 3 disparos directos del jugador rompen su resistencia y lo lanzan por los aires.
##   - Respaldo a prueba de fallos: cae o sale de los límites y se elimina con queue_free().

@export var mass_weight: float = 25.0
@export var pursue_speed: float = 2.2
@export var pursue_force: float = 50.0

var chain_hits: int = 0
var direct_hits: int = 0
var is_resistant: bool = true
var is_launched: bool = false
var player_ref: Node3D = null

@onready var visual_mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("brutes")
	mass = mass_weight
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp = 1.5
	angular_damp = 3.0
	body_entered.connect(_on_body_entered)
	freeze = false

	# Asegurar desfreeze tras 0.4s
	var tree: SceneTree = get_tree()
	if tree:
		tree.create_timer(0.4, false).timeout.connect(func() -> void:
			if is_instance_valid(self):
				freeze = false
		)

	if visual_mesh and visual_mesh.material_override:
		visual_mesh.material_override = visual_mesh.material_override.duplicate()

func _physics_process(_delta: float) -> void:
	# Respaldo absoluto para eliminación si cae o sale de los límites de la arena
	var h_dist: float = Vector2(global_position.x, global_position.z).length()
	if global_position.y < -5.0 or h_dist > 22.0:
		if is_in_group("enemies"):
			remove_from_group("enemies")
			EventBus.enemy_eliminated.emit(self, GameManager.combo_count)
		queue_free()
		return

	if not is_launched:
		_pursue_player()
	else:
		if linear_velocity.length() < 2.0:
			is_launched = false

func _pursue_player() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D

	if not player_ref:
		return

	var diff: Vector3 = player_ref.global_position - global_position
	diff.y = 0.0
	var dist: float = diff.length()
	if dist > 1.8:
		var dir: Vector3 = diff.normalized()
		var h_vel: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		if h_vel.length() < pursue_speed:
			apply_central_force(dir * pursue_force)

func apply_pull(target_pos: Vector3, _player_node: Node3D = null) -> void:
	if is_resistant:
		var pull_dir: Vector3 = target_pos - global_position
		apply_central_impulse(pull_dir.normalized() * 30.0)
		_flash_armor(false)
	else:
		linear_velocity = Vector3.ZERO
		var pull_dir: Vector3 = target_pos - global_position
		apply_central_impulse(pull_dir.normalized() * 100.0)
		gravity_scale = 0.05
		var timer: SceneTreeTimer = get_tree().create_timer(0.6, true, false, true)
		timer.timeout.connect(_on_pull_release)

func _on_pull_release() -> void:
	gravity_scale = 1.0

func _are_swarmers_alive() -> bool:
	var tree: SceneTree = get_tree()
	if not tree:
		return false
	var swarmers: Array[Node] = tree.get_nodes_in_group("swarmers")
	for node: Node in swarmers:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			return true
	return false

func apply_kinetic_impulse(impulse: Vector3, combo_level: int, is_chain: bool = false) -> void:
	if is_chain:
		_register_chain_impact(impulse, combo_level)
		return

	if is_resistant:
		direct_hits += 1
		_flash_armor(true)

		var swarmers_alive: bool = _are_swarmers_alive()

		# Rompe postura inmediatamente si no quedan Swarmers vivos O tras 2 impactos directos en cualquier momento
		if not swarmers_alive or direct_hits >= 2 or chain_hits >= 2:
			is_resistant = false
			is_launched = true
			apply_central_impulse(impulse * 1.8)
			EventBus.enemy_launched.emit(self, impulse.length() * 1.8)
			GameManager.trigger_hit_stop(0.05)
			GameManager.add_combo()
			EventBus.chain_collision.emit(GameManager.combo_count, global_position)
			return

		# Empuje progresivo con cada impacto directo (base 30% + 15% por golpe)
		var push_factor: float = 0.30 + float(direct_hits) * 0.15
		apply_central_impulse(impulse * push_factor)
	else:
		# Resistencia rota: sale disparado con fuerza completa
		is_launched = true
		apply_central_impulse(impulse * 1.8)
		EventBus.enemy_launched.emit(self, impulse.length() * 1.8)

func _register_chain_impact(impulse: Vector3, _combo_level: int) -> void:
	chain_hits += 1
	_flash_armor(true)
	if chain_hits >= 2 or direct_hits >= 3:
		is_resistant = false
		is_launched = true
		apply_central_impulse(impulse * 1.8)
		EventBus.enemy_launched.emit(self, impulse.length() * 1.8)
		GameManager.trigger_hit_stop(0.05)
		GameManager.add_combo()
		EventBus.chain_collision.emit(GameManager.combo_count, global_position)
	else:
		apply_central_impulse(impulse * 0.5)

func _flash_armor(was_chain: bool) -> void:
	if visual_mesh and visual_mesh.material_override:
		var mat: StandardMaterial3D = visual_mesh.material_override as StandardMaterial3D
		if mat:
			if was_chain:
				mat.albedo_color = Color(0.8, 0.2, 0.9, 1.0)
				mat.emission = Color(0.9, 0.2, 1.0, 1.0)
				mat.emission_energy_multiplier = 3.0
			else:
				mat.emission_energy_multiplier = 1.5

func _on_body_entered(body: Node) -> void:
	if body is Node3D and body.is_in_group("enemies") and body != self:
		var other: Node3D = body as Node3D
		var other_speed: float = 0.0
		if other is RigidBody3D:
			var other_rb: RigidBody3D = other as RigidBody3D
			other_speed = other_rb.linear_velocity.length()

		if other_speed > 5.0 and other.get("is_launched") == true:
			var transfer_impulse: Vector3 = (global_position - other.global_position).normalized() * (other_speed * 1.4)
			_register_chain_impact(transfer_impulse, GameManager.combo_count)
