extends Node

## Singleton para gestionar estado del juego, combo, puntuación y reinicio rápido.

signal score_changed(new_score: int)
signal combo_updated(count: int, multiplier: float)
signal combo_reset()

var score: int = 0
var combo_count: int = 0
var combo_multiplier: float = 1.0
var combo_timer: float = 0.0

const COMBO_DURATION: float = 4.0
const BASE_COMBO_STEP: float = 0.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.enemy_eliminated.connect(_on_enemy_eliminated)
	EventBus.chain_collision.connect(_on_chain_collision)
	EventBus.player_fell_off.connect(_on_player_fell_off)

func _process(delta: float) -> void:
	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			reset_combo()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_R:
			restart_game()

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

func _on_enemy_eliminated(_enemy: Node3D, _current_combo: int) -> void:
	add_combo()
	add_score(100)

func _on_chain_collision(_current_combo: int, _collision_pos: Vector3) -> void:
	add_combo()
	add_score(50)

func _on_player_fell_off() -> void:
	reset_combo()
	restart_game()

func restart_game() -> void:
	score = 0
	reset_combo()
	var tree: SceneTree = get_tree()
	if tree:
		tree.call_deferred("reload_current_scene")
