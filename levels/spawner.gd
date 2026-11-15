extends Node3D

## Spawner para gestionar oleadas secuenciales infinitas de enemigos cinéticos.
## Lógica blindada a prueba de fallos:
##   - Filtro estricto en _get_alive_enemies() excluyendo nodos destruidos, timers o fuera de límites.
##   - Spawneo directamente en la superficie (Y = 1.5) con escala visual en MeshInstance3D.
##   - Limpieza automática de bombas residuales al quedar la plataforma libre de enemigos activos.
##   - Refuerzos cinéticos controlados: solo si alive_brutes > 0 y alive_swarmers == 0,
##     con cooldown de 6.0s y un máximo estricto de 2 rondas por oleada.
##   - Cancel-safety mediante _spawn_generation asegurando que is_spawning siempre se resetea.

@export var swarmer_scene: PackedScene = preload("res://entities/enemies/swarmer.tscn")
@export var brute_scene: PackedScene = preload("res://entities/enemies/brute.tscn")
@export var bomb_scene: PackedScene = preload("res://entities/enemies/unstable_bomb.tscn")

const CHECK_INTERVAL: float = 0.5
const WAVE_TRANSITION_DELAY: float = 2.5
const REINFORCEMENT_COOLDOWN_TIME: float = 3.0
const MAX_REINFORCEMENT_ROUNDS: int = 2
const SPAWN_INTERVAL: float = 0.22
const SURFACE_Y: float = 1.5

var current_wave: int = 1
var is_spawning: bool = false
var is_spawning_reinforcements: bool = false
var is_transitioning: bool = false

var _check_timer: float = 0.0
var _reinforcement_cooldown: float = 0.0
var reinforcement_rounds: int = 0
var _brute_stuck_timer: float = 0.0
var _spawn_generation: int = 0

func _ready() -> void:
	current_wave = 1
	is_spawning = true
	is_spawning_reinforcements = false
	is_transitioning = false
	_check_timer = 0.0
	_reinforcement_cooldown = 0.0
	reinforcement_rounds = 0
	_brute_stuck_timer = 0.0
	_spawn_generation = 0

	var tree: SceneTree = get_tree()
	if not tree:
		return
	await tree.create_timer(1.5, false).timeout
	if is_inside_tree():
		_start_wave(current_wave)

func _process(delta: float) -> void:
	if not is_inside_tree() or is_spawning or is_spawning_reinforcements:
		return

	if _reinforcement_cooldown > 0.0:
		_reinforcement_cooldown -= delta

	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	var alive_enemies: Array[RigidBody3D] = _get_alive_enemies()
	var alive_swarmers: int = 0
	var alive_brutes: int = 0
	var alive_bombs: int = 0

	for enemy: RigidBody3D in alive_enemies:
		if _is_swarmer(enemy):
			alive_swarmers += 1
		elif _is_brute(enemy):
			alive_brutes += 1
		elif _is_bomb(enemy):
			alive_bombs += 1

	# Condición 1: Avance de oleada (No quedan Swarmers ni Brutes)
	if alive_swarmers == 0 and alive_brutes == 0:
		# Limpiar bombas residuales inactivas si quedaron en la arena
		if alive_bombs > 0:
			for enemy: RigidBody3D in alive_enemies:
				if _is_bomb(enemy):
					enemy.queue_free()

		_brute_stuck_timer = 0.0
		if not is_transitioning:
			_start_wave_transition()
		return

	# Condición 2: Refuerzos cinéticos (Hay Brutes vivos pero 0 Swarmers como munición)
	if alive_brutes > 0 and alive_swarmers == 0 and not is_transitioning:
		if reinforcement_rounds < MAX_REINFORCEMENT_ROUNDS:
			if _reinforcement_cooldown <= 0.0:
				_reinforcement_cooldown = REINFORCEMENT_COOLDOWN_TIME
				reinforcement_rounds += 1
				_spawn_reinforcements(2)
		else:
			# Si ya se usaron las 2 rondas de refuerzo y el Brute sigue vivo tras 3.5s adicionales,
			# eliminarlo para garantizar el avance de la oleada
			_brute_stuck_timer += CHECK_INTERVAL
			if _brute_stuck_timer >= 3.5:
				_brute_stuck_timer = 0.0
				print("[Spawner] Límite de refuerzos alcanzado: eliminando Brute residual para avanzar.")
				for enemy: RigidBody3D in alive_enemies:
					if _is_brute(enemy):
						enemy.queue_free()
	else:
		_brute_stuck_timer = 0.0

func _get_alive_enemies() -> Array[RigidBody3D]:
	var alive: Array[RigidBody3D] = []
	for child: Node in get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if not (child is RigidBody3D):
			continue

		var rb: RigidBody3D = child as RigidBody3D
		var h_dist: float = Vector2(rb.global_position.x, rb.global_position.z).length()

		# Límites jugables de la plataforma (Y > -4.0 y distancia horizontal < 20.0m)
		if rb.global_position.y <= -4.0 or h_dist >= 20.0:
			if rb.is_in_group("enemies"):
				rb.remove_from_group("enemies")
				EventBus.enemy_eliminated.emit(rb, GameManager.combo_count)
			rb.queue_free()
			continue

		alive.append(rb)
	return alive

func _is_swarmer(node: Node) -> bool:
	return node.is_in_group("swarmers") or (node.get_script() != null and node.get_script().resource_path.ends_with("swarmer.gd"))

func _is_brute(node: Node) -> bool:
	return node.is_in_group("brutes") or (node.get_script() != null and node.get_script().resource_path.ends_with("brute.gd"))

func _is_bomb(node: Node) -> bool:
	return node.is_in_group("bombs") or (node.get_script() != null and node.get_script().resource_path.ends_with("unstable_bomb.gd"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_T:
			_force_next_wave()

func _force_next_wave() -> void:
	_spawn_generation += 1
	is_spawning = false
	is_spawning_reinforcements = false
	is_transitioning = false
	for enemy: RigidBody3D in _get_alive_enemies():
		enemy.queue_free()
	current_wave += 1
	_start_wave(current_wave)

func _start_wave_transition() -> void:
	if is_transitioning or is_spawning:
		return
	is_transitioning = true

	# Emitir señal de oleada completada para activar banner visual y cuenta regresiva
	GameManager.notify_wave_completed(current_wave)
	EventBus.wave_completed.emit(current_wave)

	# Atraer automáticamente todas las esquirlas de XP del suelo hacia el jugador
	_attract_all_xp_shards()

	var tree: SceneTree = get_tree()
	if not tree:
		is_transitioning = false
		return

	await tree.create_timer(WAVE_TRANSITION_DELAY, false).timeout
	if not is_inside_tree():
		is_transitioning = false
		return

	# Re-verificar que siga libre de Swarmers y Brutes
	var remaining: Array[RigidBody3D] = _get_alive_enemies()
	var remaining_threats: int = 0
	for enemy: RigidBody3D in remaining:
		if _is_swarmer(enemy) or _is_brute(enemy):
			remaining_threats += 1

	if remaining_threats == 0 and not is_spawning:
		for enemy: RigidBody3D in remaining:
			enemy.queue_free()
		is_transitioning = false
		current_wave += 1
		_start_wave(current_wave)
	else:
		is_transitioning = false

func _attract_all_xp_shards() -> void:
	var tree: SceneTree = get_tree()
	if not tree:
		return
	for node: Node in tree.get_nodes_in_group("xp_shards"):
		if is_instance_valid(node) and node.has_method("attract_to_player"):
			node.call("attract_to_player")

func _start_wave(wave_num: int) -> void:
	if not is_inside_tree():
		return
	_spawn_generation += 1
	var my_gen: int = _spawn_generation

	is_spawning = true
	is_transitioning = false
	current_wave = wave_num
	reinforcement_rounds = 0
	_reinforcement_cooldown = 0.0
	_brute_stuck_timer = 0.0

	GameManager.notify_wave_changed(current_wave)
	print("Iniciando Oleada: ", current_wave)

	var roster: Array[PackedScene] = _generate_roster(current_wave)

	for enemy_scene: PackedScene in roster:
		if not is_inside_tree() or _spawn_generation != my_gen:
			is_spawning = false
			return

		_spawn_single_enemy(enemy_scene)

		var tree: SceneTree = get_tree()
		if not tree:
			is_spawning = false
			return
		await tree.create_timer(SPAWN_INTERVAL, false).timeout

		if not is_inside_tree() or _spawn_generation != my_gen:
			is_spawning = false
			return

	if _spawn_generation == my_gen:
		is_spawning = false

func _spawn_single_enemy(scene_to_spawn: PackedScene) -> Node3D:
	if not scene_to_spawn or not is_inside_tree():
		return null

	var enemy_instance: Node = scene_to_spawn.instantiate()
	var enemy: Node3D = enemy_instance as Node3D
	if not enemy:
		return null

	add_child(enemy)

	# Spawn directamente sobre la superficie (Y = 1.5)
	var spawn_pos: Vector3 = Vector3(randf_range(-12.0, 12.0), SURFACE_Y, randf_range(-12.0, 12.0))
	enemy.global_position = spawn_pos

	# Efecto de emerger animando la escala únicamente de su hijo MeshInstance3D
	var mesh: MeshInstance3D = enemy.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh:
		mesh.scale = Vector3(0.01, 0.01, 0.01)
		var tween: Tween = create_tween()
		tween.tween_property(mesh, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	return enemy

func _spawn_reinforcements(count: int) -> void:
	if is_spawning_reinforcements or not is_inside_tree():
		return
	is_spawning_reinforcements = true
	var my_gen: int = _spawn_generation
	print("Refuerzos cinéticos: Spawneando %d Swarmers para romper al Brute (Ronda %d/%d)" % [count, reinforcement_rounds, MAX_REINFORCEMENT_ROUNDS])

	for _i: int in range(count):
		if not is_inside_tree() or _spawn_generation != my_gen:
			is_spawning_reinforcements = false
			return
		_spawn_single_enemy(swarmer_scene)
		var tree: SceneTree = get_tree()
		if not tree:
			is_spawning_reinforcements = false
			return
		await tree.create_timer(0.3, false).timeout

		if not is_inside_tree() or _spawn_generation != my_gen:
			is_spawning_reinforcements = false
			return

	if _spawn_generation == my_gen:
		is_spawning_reinforcements = false

func _generate_roster(wave_num: int) -> Array[PackedScene]:
	var roster: Array[PackedScene] = []
	var swarmers: int = wave_num * 3
	var brutes: int = int(float(wave_num) / 3.0)
	var bombs: int = int(float(wave_num - 1) / 2.0)

	for _i: int in range(swarmers):
		roster.append(swarmer_scene)
	for _i: int in range(brutes):
		roster.append(brute_scene)
	for _i: int in range(bombs):
		roster.append(bomb_scene)

	roster.shuffle()
	return roster
