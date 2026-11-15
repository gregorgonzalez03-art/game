extends CanvasLayer

## HUD principal con telemetría de combate, combo, estado de sobrecarga y banners de oleada.
## Cumple estrictamente con AGENTS.md (tipado estricto, Godot 4.x).

@onready var score_label: Label = $UI/MarginContainer/VBoxContainer/ScoreLabel
@onready var xp_label: Label = $UI/MarginContainer/VBoxContainer/XPLabel
@onready var wave_label: Label = $UI/MarginContainer/VBoxContainer/WaveLabel
@onready var combo_label: Label = $UI/MarginContainer/VBoxContainer/ComboLabel
@onready var overcharge_badge: Label = $UI/MarginContainer/VBoxContainer/OverchargeBadge
@onready var wave_banner_label: Label = $UI/WaveBannerLabel

@onready var game_over_panel: ColorRect = $UI/GameOverPanel
@onready var game_over_stats: Label = $UI/GameOverPanel/CenterContainer/VBoxContainer/StatsLabel
@onready var restart_button: Button = $UI/GameOverPanel/CenterContainer/VBoxContainer/RestartButton

var player_ref: Node3D = null
var _banner_tween: Tween = null
var _banner_sequence_token: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameManager.score_changed.connect(_on_score_changed)
	GameManager.combo_updated.connect(_on_combo_updated)
	GameManager.xp_changed.connect(_on_xp_changed)
	GameManager.wave_changed.connect(_on_wave_changed)
	GameManager.wave_completed.connect(_on_wave_completed)
	GameManager.game_over_triggered.connect(_on_game_over_triggered)

	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)

	_on_score_changed(GameManager.score)
	_on_xp_changed(GameManager.xp)
	_on_combo_updated(GameManager.combo_count, GameManager.combo_multiplier)

	if wave_label:
		wave_label.text = "OLEADA ACTUAL: %d" % GameManager.current_wave

	if game_over_panel:
		game_over_panel.visible = false

	if wave_banner_label:
		wave_banner_label.visible = false

func _process(_delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D

	if player_ref and overcharge_badge:
		var is_overcharged: bool = player_ref.get("is_edge_overcharged") == true
		overcharge_badge.visible = is_overcharged

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "SCORE: %d" % new_score

func _on_xp_changed(new_xp: int) -> void:
	if xp_label:
		xp_label.text = "XP: %d" % new_xp

func _on_combo_updated(count: int, multiplier: float) -> void:
	if combo_label:
		if multiplier > 1.0 and count > 0:
			combo_label.text = "COMBO: x%.1f (%d)" % [multiplier, count]
			combo_label.visible = true
		else:
			combo_label.visible = false

func _on_wave_completed(completed_wave: int) -> void:
	if not wave_banner_label:
		return

	_banner_sequence_token += 1
	var current_token: int = _banner_sequence_token

	# Segundo 0.0 a 1.0: "¡OLEADA X COMPLETADA!"
	wave_banner_label.visible = true
	wave_banner_label.text = "¡OLEADA %d COMPLETADA!" % completed_wave
	wave_banner_label.modulate = Color(1.0, 0.88, 0.2, 1.0)
	_play_banner_pop(Vector2(1.2, 1.2), 0.22)

	var tree: SceneTree = get_tree()
	if not tree:
		return

	# Segundo 1.0 a 1.5: "PRÓXIMA OLEADA EN 3..."
	await tree.create_timer(1.0, false).timeout
	if _banner_sequence_token != current_token or not is_inside_tree():
		return
	wave_banner_label.text = "PRÓXIMA OLEADA EN 3..."
	wave_banner_label.modulate = Color(0.3, 0.9, 1.0, 1.0)
	_play_banner_pop(Vector2(1.15, 1.15), 0.15)

	# Segundo 1.5 a 2.0: "PRÓXIMA OLEADA EN 2..."
	await tree.create_timer(0.5, false).timeout
	if _banner_sequence_token != current_token or not is_inside_tree():
		return
	wave_banner_label.text = "PRÓXIMA OLEADA EN 2..."
	wave_banner_label.modulate = Color(0.3, 0.9, 1.0, 1.0)
	_play_banner_pop(Vector2(1.15, 1.15), 0.15)

	# Segundo 2.0 a 2.5: "PRÓXIMA OLEADA EN 1..."
	await tree.create_timer(0.5, false).timeout
	if _banner_sequence_token != current_token or not is_inside_tree():
		return
	wave_banner_label.text = "PRÓXIMA OLEADA EN 1..."
	wave_banner_label.modulate = Color(1.0, 0.4, 0.2, 1.0)
	_play_banner_pop(Vector2(1.2, 1.2), 0.15)

func _on_wave_changed(new_wave: int) -> void:
	if wave_label:
		wave_label.text = "OLEADA ACTUAL: %d" % new_wave

	# Al iniciar la nueva oleada: muestra "¡OLEADA Y!" durante 0.8s
	if wave_banner_label:
		_banner_sequence_token += 1
		var current_token: int = _banner_sequence_token

		wave_banner_label.visible = true
		wave_banner_label.text = "¡OLEADA %d!" % new_wave
		wave_banner_label.modulate = Color(1.0, 0.95, 0.3, 1.0)
		_play_banner_pop(Vector2(1.25, 1.25), 0.2)

		var tree: SceneTree = get_tree()
		if not tree:
			return
		await tree.create_timer(0.8, false).timeout
		if _banner_sequence_token == current_token and is_inside_tree() and is_instance_valid(wave_banner_label):
			wave_banner_label.visible = false

func _play_banner_pop(scale_peak: Vector2, duration: float) -> void:
	if not wave_banner_label:
		return
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	wave_banner_label.scale = scale_peak
	_banner_tween = create_tween()
	_banner_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(wave_banner_label, "scale", Vector2.ONE, duration)

func _on_game_over_triggered(final_score: int, final_wave: int) -> void:
	if wave_banner_label:
		wave_banner_label.visible = false
	if game_over_panel:
		game_over_panel.visible = true
	if game_over_stats:
		game_over_stats.text = "PUNTUACIÓN FINAL: %d | OLEADA ALCANZADA: %d" % [final_score, final_wave]

func _on_restart_button_pressed() -> void:
	GameManager.restart_game()
