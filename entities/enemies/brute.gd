extends RigidBody3D

## Pilar / Torreta Monolítica Brute Anclada (Fase 4.1).
## Físicas Kinematic inmóviles (freeze = true). No se desplaza por impactos.
## Ciclo de combate: Emerge (Y=-2.5 a 1.6) ➔ Ráfaga de 3 plasmas (7.0s) ➔ Se hunde y cura +25% HP ➔ Resurge.
## Al llegar a 0 HP, explota en 7 a 9 pedazos irregulares asimétricos y suelta 2 Esquirlas de XP.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto, -Z adelante).

const ENEMY_SHADER: Shader = preload("res://entities/effects/enemy_hit_fresnel.gdshader")
const PLASMA_SCENE: PackedScene = preload("res://entities/projectiles/brute_plasma_ball.tscn")

const MAX_HP: float = 145.0
const SURFACE_Y: float = 1.6
const SUBMERGED_Y: float = -2.5
const SURFACE_DURATION: float = 7.0
const BURST_SHOT_INTERVAL: float = 1.6
const TOTAL_BURST_SHOTS: int = 3
const SUBMERGED_DURATION: float = 1.5
const ARENA_RADIUS: float = 9.0

var max_hp: float = MAX_HP
var burst_interval: float = BURST_SHOT_INTERVAL
var current_hp: float = 145.0
var is_submerged: bool = false
var is_emerging: bool = false
var is_submerging: bool = false
var is_dead: bool = false

var surface_timer: float = 0.0
var burst_timer: float = 0.0
var burst_shots_fired: int = 0
var player_ref: Node3D = null

var shader_mat: ShaderMaterial = null
var eye_mat: ShaderMaterial = null
var hit_flash_tween: Tween = null
var shake_tween: Tween = null

@onready var visual_mesh: Node3D = $VisualMesh
@onready var pillar_mesh: MeshInstance3D = $VisualMesh/PillarMesh
@onready var core_eye: MeshInstance3D = $VisualMesh/CoreEye
@onready var top_crown: MeshInstance3D = $VisualMesh/TopCrown
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("brutes")
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)

	_setup_shader()
	call_deferred("_start_initial_cycle")

func _setup_shader() -> void:
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = ENEMY_SHADER
	shader_mat.set_shader_parameter("albedo_color", Color(0.35, 0.08, 0.52, 1.0))
	shader_mat.set_shader_parameter("emission_color", Color(0.85, 0.15, 0.95, 1.0))
	shader_mat.set_shader_parameter("emission_energy", 0.9)
	shader_mat.set_shader_parameter("metallic", 0.75)
	shader_mat.set_shader_parameter("roughness", 0.3)
	shader_mat.set_shader_parameter("dissolve_edge_color", Color("#FF00D4"))

	eye_mat = ShaderMaterial.new()
	eye_mat.shader = ENEMY_SHADER
	eye_mat.set_shader_parameter("albedo_color", Color(1.0, 0.1, 0.8, 1.0))
	eye_mat.set_shader_parameter("emission_color", Color(1.0, 0.2, 0.9, 1.0))
	eye_mat.set_shader_parameter("emission_energy", 2.6)
	eye_mat.set_shader_parameter("dissolve_edge_color", Color("#FF00D4"))

	if pillar_mesh:
		pillar_mesh.material_override = shader_mat
	if top_crown:
		top_crown.material_override = shader_mat
	if core_eye:
		core_eye.material_override = eye_mat

func _start_initial_cycle() -> void:
	global_position.y = SUBMERGED_Y
	is_submerged = true
	collision_shape.set_deferred("disabled", true)
	emerge()

func emerge() -> void:
	is_emerging = true
	is_submerged = false
	collision_shape.set_deferred("disabled", false)

	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position:y", SURFACE_Y, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_emerged)

func _on_emerged() -> void:
	is_emerging = false
	surface_timer = SURFACE_DURATION
	burst_shots_fired = 0
	burst_timer = 1.0

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_submerged and not is_emerging and not is_submerging:
		_track_player()
		_handle_surface_phase(delta)

func _track_player() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D

	if not player_ref:
		return

	var look_target: Vector3 = Vector3(player_ref.global_position.x, global_position.y, player_ref.global_position.z)
	if global_position.distance_squared_to(look_target) > 0.01:
		var target_basis: Basis = Basis.looking_at(look_target - global_position, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, 0.1)

func _handle_surface_phase(delta: float) -> void:
	surface_timer -= delta

	if burst_shots_fired < TOTAL_BURST_SHOTS:
		burst_timer -= delta

		# Pre-carga de disparo en el núcleo ocular
		if burst_timer <= 0.3 and burst_timer > 0.0 and eye_mat:
			var pulse: float = 3.5 + sin(burst_timer * 35.0) * 3.0
			eye_mat.set_shader_parameter("emission_energy", pulse)

		if burst_timer <= 0.0:
			_fire_plasma_shot()
			burst_shots_fired += 1
			burst_timer = burst_interval

	if surface_timer <= 0.0:
		submerge_and_heal()

func _fire_plasma_shot() -> void:
	if not PLASMA_SCENE or not is_inside_tree():
		return

	if eye_mat:
		eye_mat.set_shader_parameter("emission_energy", 2.6)

	var spawn_pos: Vector3 = core_eye.global_position if core_eye else (global_position + Vector3(0, 0.7, 0))
	var target_pos: Vector3 = spawn_pos - global_transform.basis.z * 10.0
	if player_ref and is_instance_valid(player_ref):
		target_pos = player_ref.global_position + Vector3(0.0, 0.8, 0.0)

	var fire_dir: Vector3 = (target_pos - spawn_pos).normalized()
	fire_dir.y = clampf(fire_dir.y, -0.15, 0.15)
	fire_dir = fire_dir.normalized()

	var plasma: Node = PLASMA_SCENE.instantiate()
	var plasma_node: Node3D = plasma as Node3D
	if plasma_node:
		var root: Node = get_tree().current_scene
		if root:
			root.add_child(plasma_node)
		if plasma_node.has_method("setup_trajectory"):
			plasma_node.call("setup_trajectory", spawn_pos, fire_dir)

func submerge_and_heal() -> void:
	if is_submerging or is_dead:
		return
	is_submerging = true
	is_submerged = true
	collision_shape.set_deferred("disabled", true)

	# Recupera un 25% de su vida máxima y actualiza grietas
	current_hp = minf(max_hp, current_hp + (max_hp * 0.25))
	_update_cracks()

	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position:y", SUBMERGED_Y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(_on_submerged_complete)

func _on_submerged_complete() -> void:
	is_submerging = false
	var tree: SceneTree = get_tree()
	if not tree:
		return

	await tree.create_timer(SUBMERGED_DURATION, false).timeout
	if is_dead or not is_inside_tree():
		return

	# Relocalización en posición aleatoria válida dentro de la plataforma
	var rand_angle: float = randf_range(0.0, TAU)
	var rand_dist: float = randf_range(3.0, ARENA_RADIUS)
	global_position = Vector3(cos(rand_angle) * rand_dist, SUBMERGED_Y, sin(rand_angle) * rand_dist)

	emerge()

## Recibe daño directo con valores diferenciados según la fuente
func take_damage(amount: float, _hit_source_pos: Vector3 = Vector3.ZERO) -> void:
	if is_dead or is_submerged:
		return

	current_hp = maxf(0.0, current_hp - amount)
	play_hit_flash()
	_play_damage_shake()
	_update_cracks()
	GameManager.trigger_hit_stop(0.05)

	if current_hp <= 0.0:
		_destroy_pillar()

## Representación visual progresiva de grietas incandescentes según pérdida de HP
func _update_cracks() -> void:
	if not shader_mat:
		return
	var crack_ratio: float = (1.0 - (current_hp / max_hp)) * 0.35
	shader_mat.set_shader_parameter("dissolve_amount", clampf(crack_ratio, 0.0, 0.35))
	shader_mat.set_shader_parameter("emission_energy", 0.9 + (crack_ratio * 3.5))

## Escalado Progresivo por Oleada (Paso 4.2)
func apply_wave_scaling(wave_num: int) -> void:
	if wave_num >= 4:
		var hp_scaling: float = 1.0 + float(wave_num - 3) * 0.08
		max_hp = MAX_HP * hp_scaling
		current_hp = max_hp
		_update_cracks()

	var interval_reduction: float = 1.0 - float(wave_num - 1) * 0.05
	burst_interval = maxf(0.9, BURST_SHOT_INTERVAL * interval_reduction)

func _play_damage_shake() -> void:
	if not visual_mesh:
		return
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()

	shake_tween = create_tween()
	var shake_offset: Vector3 = Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12))
	shake_tween.tween_property(visual_mesh, "position", shake_offset, 0.04)
	shake_tween.tween_property(visual_mesh, "position", -shake_offset * 0.6, 0.04)
	shake_tween.tween_property(visual_mesh, "position", Vector3.ZERO, 0.05)

func play_hit_flash() -> void:
	if not shader_mat:
		return
	if hit_flash_tween and hit_flash_tween.is_valid():
		hit_flash_tween.kill()
	hit_flash_tween = create_tween()
	hit_flash_tween.set_parallel(true)
	shader_mat.set_shader_parameter("hit_flash", 1.0)
	if eye_mat:
		eye_mat.set_shader_parameter("hit_flash", 1.0)

	hit_flash_tween.tween_method(
		func(val: float) -> void:
			if shader_mat:
				shader_mat.set_shader_parameter("hit_flash", val),
		1.0, 0.0, 0.12
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if eye_mat:
		hit_flash_tween.tween_method(
			func(val: float) -> void:
				if eye_mat:
					eye_mat.set_shader_parameter("hit_flash", val),
			1.0, 0.0, 0.12
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Compatible con el sistema cinético: Pulso directo = 15 HP, Choque en cadena = 35 HP
func apply_kinetic_impulse(_impulse: Vector3, _combo_level: int = 0, is_chain: bool = false) -> void:
	if is_chain:
		take_damage(35.0)
	else:
		take_damage(15.0)

func apply_pull(_target_pos: Vector3, _player_node: Node3D = null) -> void:
	# El Pilar monolítico es inmóvil ante el gancho, pero recibe daño de tensión
	take_damage(15.0)

func _on_body_entered(body: Node) -> void:
	if is_dead or is_submerged:
		return

	if body is Node3D and body.is_in_group("enemies") and body != self:
		var other: Node3D = body as Node3D
		if other.get("is_launched") == true:
			take_damage(35.0, other.global_position)
			GameManager.add_combo()
			EventBus.chain_collision.emit(GameManager.combo_count, global_position)

## Destrucción total: explosión en 7 a 9 fragmentos asimétricos y liberación de 2 Esquirlas de XP
func _destroy_pillar() -> void:
	if is_dead:
		return
	is_dead = true

	remove_from_group("enemies")
	remove_from_group("brutes")
	EventBus.enemy_eliminated.emit(self, GameManager.combo_count)

	var death_pos: Vector3 = global_position

	# Liberar inmediatamente 2 Esquirlas de XP en su posición
	GameManager.spawn_xp_shard_at_edge(death_pos + Vector3(0.6, 0.0, 0.0))
	GameManager.spawn_xp_shard_at_edge(death_pos + Vector3(-0.6, 0.0, 0.0))

	call_deferred("_spawn_destruction_debris", death_pos)

	visible = false
	collision_shape.set_deferred("disabled", true)
	queue_free()

func _spawn_destruction_debris(origin_pos: Vector3) -> void:
	var root: Node = get_tree().current_scene
	if not root:
		return

	var debris_count: int = randi_range(7, 9)

	for i: int in range(debris_count):
		var debris: RigidBody3D = RigidBody3D.new()
		debris.top_level = true
		debris.collision_layer = 0 # No colisiona contra el jugador
		debris.collision_mask = 1  # Rebota en el suelo
		debris.mass = randf_range(2.0, 5.0)

		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var mesh_size: Vector3 = Vector3(
			randf_range(0.35, 0.95),
			randf_range(0.4, 1.3),
			randf_range(0.35, 0.85)
		)

		if i % 2 == 0:
			var box: BoxMesh = BoxMesh.new()
			box.size = mesh_size
			mesh_inst.mesh = box
		else:
			var prism: PrismMesh = PrismMesh.new()
			prism.size = mesh_size
			mesh_inst.mesh = prism

		var mat: ShaderMaterial = shader_mat.duplicate() as ShaderMaterial
		mat.set_shader_parameter("dissolve_amount", 0.1)
		mesh_inst.material_override = mat
		debris.add_child(mesh_inst)

		var col: CollisionShape3D = CollisionShape3D.new()
		var col_box: BoxShape3D = BoxShape3D.new()
		col_box.size = mesh_size
		col.shape = col_box
		debris.add_child(col)

		root.add_child(debris)
		debris.global_position = origin_pos + Vector3(
			randf_range(-0.6, 0.6),
			randf_range(0.3, 1.8),
			randf_range(-0.6, 0.6)
		)

		var blast_dir: Vector3 = Vector3(
			randf_range(-6.0, 6.0),
			randf_range(7.0, 13.0),
			randf_range(-6.0, 6.0)
		)
		debris.apply_central_impulse(blast_dir)
		debris.apply_torque_impulse(Vector3(
			randf_range(-25.0, 25.0),
			randf_range(-25.0, 25.0),
			randf_range(-25.0, 25.0)
		))

		var tween: Tween = debris.create_tween()
		tween.tween_method(
			func(val: float) -> void:
				if mat:
					mat.set_shader_parameter("dissolve_amount", val),
			0.1, 1.0, 1.2
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.finished.connect(debris.queue_free)
