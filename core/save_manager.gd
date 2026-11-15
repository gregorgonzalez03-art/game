extends Node

## Sistema de Guardado Persistente para Arena Cinética 3D (Fase 4.2).
## Serialización segura en JSON en user://save_data.json.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

signal save_data_updated(high_score: int, best_wave: int, total_enemies_launched: int)
signal new_record_achieved(record_type: String, value: int)

const SAVE_FILE_PATH: String = "user://save_data.json"
const CURRENT_SAVE_VERSION: int = 1

var save_version: int = 1
var high_score: int = 0
var best_wave: int = 1
var total_enemies_launched: int = 0

var is_new_high_score: bool = false
var is_new_best_wave: bool = false

func _ready() -> void:
	load_data()
	_connect_signals()

func _connect_signals() -> void:
	EventBus.enemy_launched.connect(_on_enemy_launched)
	GameManager.wave_completed.connect(_on_wave_completed)
	GameManager.game_over_triggered.connect(_on_game_over_triggered)

func reset_session_flags() -> void:
	is_new_high_score = false
	is_new_best_wave = false

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		_init_default_data()
		save_data()
		return

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if not file:
		push_warning("SaveManager: No se pudo abrir el archivo de guardado para lectura.")
		_init_default_data()
		return

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(content)
	if error != OK:
		push_warning("SaveManager: Error al parsear JSON de guardado (código %d). Inicializando valores por defecto." % error)
		_init_default_data()
		return

	var data: Variant = json.data
	if not data is Dictionary:
		_init_default_data()
		return

	var dict: Dictionary = data as Dictionary
	save_version = int(dict.get("save_version", CURRENT_SAVE_VERSION))
	high_score = int(dict.get("high_score", 0))
	best_wave = int(dict.get("best_wave", 1))
	total_enemies_launched = int(dict.get("total_enemies_launched", 0))

	save_data_updated.emit(high_score, best_wave, total_enemies_launched)

func save_data() -> void:
	var dict: Dictionary = {
		"save_version": save_version,
		"high_score": high_score,
		"best_wave": best_wave,
		"total_enemies_launched": total_enemies_launched
	}

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: Error al abrir archivo de guardado para escritura.")
		return

	var json_str: String = JSON.stringify(dict, "\t")
	file.store_string(json_str)
	file.close()

	save_data_updated.emit(high_score, best_wave, total_enemies_launched)

func _init_default_data() -> void:
	save_version = CURRENT_SAVE_VERSION
	high_score = 0
	best_wave = 1
	total_enemies_launched = 0
	is_new_high_score = false
	is_new_best_wave = false

func check_and_update_records(current_score: int, current_wave: int) -> Dictionary:
	var updated: bool = false
	var new_score_record: bool = false
	var new_wave_record: bool = false

	if current_score > high_score:
		high_score = current_score
		updated = true
		new_score_record = true
		is_new_high_score = true
		new_record_achieved.emit("high_score", high_score)

	if current_wave > best_wave:
		best_wave = current_wave
		updated = true
		new_wave_record = true
		is_new_best_wave = true
		new_record_achieved.emit("best_wave", best_wave)

	if updated:
		save_data()

	return {
		"new_score_record": new_score_record,
		"new_wave_record": new_wave_record
	}

func _on_enemy_launched(_enemy: Node3D, _impulse_magnitude: float) -> void:
	total_enemies_launched += 1

func _on_wave_completed(wave_num: int) -> void:
	# Al completar una oleada, la próxima alcanzada es wave_num + 1
	check_and_update_records(GameManager.score, wave_num + 1)

func _on_game_over_triggered(final_score: int, final_wave: int) -> void:
	check_and_update_records(final_score, final_wave)
	save_data()
