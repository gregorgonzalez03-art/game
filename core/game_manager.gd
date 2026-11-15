extends Node

## Singleton para gestionar estado del juego, combo, puntuación, XP, hit-stop y reinicio rápido.

signal score_changed(new_score: int)
signal combo_updated(count: int, multiplier: float)
signal combo_reset()
signal xp_changed(new_xp: int)
@warning_ignore("unused_signal")
signal wave_changed(current_wave: int)
@warning_ignore("unused_signal")
signal wave_completed(completed_wave: int)
signal game_over_triggered(final_score: int, final_wave: int)

var score: int = 0
var xp: int = 0
var combo_count: int = 0
var combo_multiplier: float = 1.0
var combo_timer: float = 0.0
var current_wave: int = 1
var is_game_over: bool = false

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
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game_over_triggered.emit(score, current_wave)

func restart_game() -> void:
	is_game_over = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Engine.time_scale = 1.0
	_is_hit_stopping = false
	_hit_stop_end_msec = 0
	score = 0
	xp = 0
	current_wave = 1
	reset_combo()
	xp_changed.emit(xp)
	score_changed.emit(score)
	wave_changed.emit(current_wave)
	var tree: SceneTree = get_tree()
	if tree:
		tree.call_deferred("reload_current_scene")
