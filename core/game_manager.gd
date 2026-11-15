extends Node

## Singleton para gestionar estado del juego, combo, puntuación, XP, progresión y mejoras.
## Cumple estrictamente con AGENTS.md (tipado estricto, Godot 4.x).

signal score_changed(new_score: int)
signal combo_updated(count: int, multiplier: float)
signal combo_reset()
signal xp_changed(new_xp: int)
@warning_ignore("unused_signal")
signal wave_changed(current_wave: int)
@warning_ignore("unused_signal")
signal wave_completed(completed_wave: int)
signal game_over_triggered(final_score: int, final_wave: int)
signal level_up_triggered(new_level: int, draft_options: Array[Dictionary])
signal upgrade_applied(upgrade_id: String, current_stacks: int)
signal level_progress_updated(current_level: int, current_xp: int, needed_xp: int)

var score: int = 0
var xp: int = 0
var combo_count: int = 0
var combo_multiplier: float = 1.0
var combo_timer: float = 0.0
var current_wave: int = 1
var is_game_over: bool = false

# Sistema de Progresión y Subida de Nivel
var current_level: int = 1
var xp_to_next_level: int = 80
var active_upgrades: Dictionary = {}
var pending_level_ups: int = 0
var is_drafting: bool = false

@export var xp_shard_scene: PackedScene = preload("res://entities/interactables/xp_shard.tscn")

# Control centralizado de Hit-Stop
var _hit_stop_end_msec: int = 0
var _is_hit_stopping: bool = false

const COMBO_DURATION: float = 4.0
const BASE_COMBO_STEP: float = 0.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.enemy_eliminated.connect(_on_enemy_eliminated)
	EventBus.chain_collision.connect(_on_chain_collision)
	EventBus.player_fell_off.connect(_on_player_fell_off)
	call_deferred("_emit_initial_progress")

func _emit_initial_progress() -> void:
	level_progress_updated.emit(current_level, xp, xp_to_next_level)

func _process(delta: float) -> void:
	if _is_hit_stopping and Time.get_ticks_msec() >= _hit_stop_end_msec:
		Engine.time_scale = 1.0
		_is_hit_stopping = false

	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			reset_combo()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
			if is_game_over:
				restart_game()

## Centraliza el hit-stop visceral asegurando restauración a 1.0 incluso en llamadas sucesivas
func trigger_hit_stop(duration: float = 0.05) -> void:
	Engine.time_scale = 0.05
	var target_time: int = Time.get_ticks_msec() + int(duration * 1000.0)
	if target_time > _hit_stop_end_msec:
		_hit_stop_end_msec = target_time
	_is_hit_stopping = true

	var timer: SceneTreeTimer = get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(_on_hit_stop_timer_timeout)

func _on_hit_stop_timer_timeout() -> void:
	if Time.get_ticks_msec() >= _hit_stop_end_msec:
		Engine.time_scale = 1.0
		_is_hit_stopping = false

func add_combo() -> void:
	combo_count += 1
	combo_multiplier = 1.0 + float(combo_count) * BASE_COMBO_STEP
	combo_timer = COMBO_DURATION
	combo_updated.emit(combo_count, combo_multiplier)

func reset_combo() -> void:
	combo_count = 0
	combo_multiplier = 1.0
	combo_timer = 0.0
	combo_reset.emit()
	combo_updated.emit(combo_count, combo_multiplier)

func add_score(base_points: int) -> void:
	var points: int = int(float(base_points) * combo_multiplier)
	score += points
	score_changed.emit(score)

func add_xp(amount: int) -> void:
	xp += amount
	xp_changed.emit(xp)
	_check_level_up()

func _check_level_up() -> void:
	var leveled_up: bool = false
	while xp >= xp_to_next_level:
		xp -= xp_to_next_level
		current_level += 1
		xp_to_next_level = int(float(xp_to_next_level) * 1.4)
		pending_level_ups += 1
		leveled_up = true

	level_progress_updated.emit(current_level, xp, xp_to_next_level)

	if leveled_up and not is_drafting and not is_game_over:
		trigger_upgrade_draft()

func trigger_upgrade_draft() -> void:
	if is_game_over:
		return
	is_drafting = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var draft: Array[Dictionary] = UpgradesCatalog.get_random_draft(3)
	level_up_triggered.emit(current_level, draft)

func apply_upgrade(upgrade_id: String) -> void:
	var current_stacks: int = get_upgrade_stacks(upgrade_id)
	active_upgrades[upgrade_id] = current_stacks + 1
	upgrade_applied.emit(upgrade_id, active_upgrades[upgrade_id])

	if pending_level_ups > 0:
		pending_level_ups -= 1

	if pending_level_ups > 0 and not is_game_over:
		call_deferred("trigger_upgrade_draft")
	else:
		is_drafting = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func get_upgrade_stacks(upgrade_id: String) -> int:
	return int(active_upgrades.get(upgrade_id, 0))

## Activa una esquirla de XP desde el ObjectPool en el borde seguro de la plataforma
func spawn_xp_shard_at_edge(death_pos: Vector3) -> void:
	var spawn_pos: Vector3 = Vector3(
		clampf(death_pos.x, -13.5, 13.5),
		1.35,
		clampf(death_pos.z, -13.5, 13.5)
	)
	call_deferred("_deferred_activate_shard", spawn_pos)

func _deferred_activate_shard(spawn_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	ObjectPool.activate_shard(spawn_pos)

func notify_wave_completed(wave_num: int) -> void:
	wave_completed.emit(wave_num)

func notify_wave_changed(wave_num: int) -> void:
	current_wave = wave_num
	wave_changed.emit(wave_num)

func _on_enemy_eliminated(_enemy: Node3D, _current_combo: int) -> void:
	add_combo()
	add_score(100)

func _on_chain_collision(_current_combo: int, _collision_pos: Vector3) -> void:
	add_combo()
	add_score(50)

func _on_player_fell_off() -> void:
	game_over()

func game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	is_drafting = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_over_triggered.emit(score, current_wave)

func restart_game() -> void:
	is_game_over = false
	is_drafting = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Engine.time_scale = 1.0
	_is_hit_stopping = false
	_hit_stop_end_msec = 0
	score = 0
	xp = 0
	current_level = 1
	xp_to_next_level = 80
	pending_level_ups = 0
	active_upgrades.clear()
	current_wave = 1
	reset_combo()
	ObjectPool.deactivate_all()
	SaveManager.reset_session_flags()
	xp_changed.emit(xp)
	score_changed.emit(score)
	wave_changed.emit(current_wave)
	level_progress_updated.emit(current_level, xp, xp_to_next_level)
	var tree: SceneTree = get_tree()
	if tree:
		tree.call_deferred("reload_current_scene")
