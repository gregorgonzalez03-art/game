extends CanvasLayer

## HUD principal con telemetría de combate, combo, estado de sobrecarga, banners de oleada y Draft de Sinergias.
## Cumple estrictamente con AGENTS.md (tipado estricto, Godot 4.x).

@onready var score_label: Label = $UI/MarginContainer/VBoxContainer/ScoreLabel
@onready var xp_label: Label = $UI/MarginContainer/VBoxContainer/XPLabel
@onready var xp_progress_bar: ProgressBar = $UI/MarginContainer/VBoxContainer/XPProgressBar
@onready var wave_label: Label = $UI/MarginContainer/VBoxContainer/WaveLabel
@onready var combo_label: Label = $UI/MarginContainer/VBoxContainer/ComboLabel
@onready var overcharge_badge: Label = $UI/MarginContainer/VBoxContainer/OverchargeBadge
@onready var wave_banner_label: Label = $UI/WaveBannerLabel

@onready var game_over_panel: ColorRect = $UI/GameOverPanel
@onready var game_over_stats: Label = $UI/GameOverPanel/CenterContainer/VBoxContainer/StatsLabel
@onready var restart_button: Button = $UI/GameOverPanel/CenterContainer/VBoxContainer/RestartButton

# Interfaz de Draft de Sinergias
@onready var upgrade_draft_panel: ColorRect = $UI/UpgradeDraftPanel
@onready var draft_title: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/DraftTitle

@onready var card_button_1: Button = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton1
@onready var card_name_1: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton1/Margin/Content/Name1
@onready var card_level_1: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton1/Margin/Content/Level1
@onready var card_desc_1: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton1/Margin/Content/Desc1

@onready var card_button_2: Button = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton2
@onready var card_name_2: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton2/Margin/Content/Name2
@onready var card_level_2: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton2/Margin/Content/Level2
@onready var card_desc_2: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton2/Margin/Content/Desc2

@onready var card_button_3: Button = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton3
@onready var card_name_3: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton3/Margin/Content/Name3
@onready var card_level_3: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton3/Margin/Content/Level3
@onready var card_desc_3: Label = $UI/UpgradeDraftPanel/CenterContainer/VBoxContainer/CardsContainer/CardButton3/Margin/Content/Desc3

var player_ref: Node3D = null
var _banner_tween: Tween = null
var _banner_sequence_token: int = 0
var _current_draft: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameManager.score_changed.connect(_on_score_changed)
	GameManager.combo_updated.connect(_on_combo_updated)
	GameManager.xp_changed.connect(_on_xp_changed)
	GameManager.wave_changed.connect(_on_wave_changed)
	GameManager.wave_completed.connect(_on_wave_completed)
	GameManager.game_over_triggered.connect(_on_game_over_triggered)
	GameManager.level_up_triggered.connect(_on_level_up_triggered)
	GameManager.level_progress_updated.connect(_on_level_progress_updated)

	if restart_button:
		restart_button.pressed.connect(_on_restart_button_pressed)

	if card_button_1:
		card_button_1.pressed.connect(_on_card_pressed.bind(0))
	if card_button_2:
		card_button_2.pressed.connect(_on_card_pressed.bind(1))
	if card_button_3:
		card_button_3.pressed.connect(_on_card_pressed.bind(2))

	_on_score_changed(GameManager.score)
	_on_level_progress_updated(GameManager.current_level, GameManager.xp, GameManager.xp_to_next_level)
	_on_combo_updated(GameManager.combo_count, GameManager.combo_multiplier)

	if wave_label:
		wave_label.text = "OLEADA ACTUAL: %d" % GameManager.current_wave

	if game_over_panel:
		game_over_panel.visible = false

	if wave_banner_label:
		wave_banner_label.visible = false

	if upgrade_draft_panel:
		upgrade_draft_panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if upgrade_draft_panel and upgrade_draft_panel.visible:
		if event is InputEventKey:
			var key_event: InputEventKey = event as InputEventKey
			if key_event.pressed and not key_event.echo:
				if key_event.keycode == KEY_1:
					_on_card_pressed(0)
					get_viewport().set_input_as_handled()
				elif key_event.keycode == KEY_2:
					_on_card_pressed(1)
					get_viewport().set_input_as_handled()
				elif key_event.keycode == KEY_3:
					_on_card_pressed(2)
					get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D

	if player_ref and overcharge_badge:
		var is_overcharged: bool = player_ref.get("is_edge_overcharged") == true
		overcharge_badge.visible = is_overcharged

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "SCORE: %d" % new_score

func _on_xp_changed(_new_xp: int) -> void:
	# La actualización detallada se gestiona mediante _on_level_progress_updated
	pass

func _on_level_progress_updated(level: int, cur_xp: int, next_xp: int) -> void:
	if xp_label:
		xp_label.text = "LVL %d (%d / %d XP)" % [level, cur_xp, next_xp]
	if xp_progress_bar:
		xp_progress_bar.max_value = float(next_xp)
		xp_progress_bar.value = float(cur_xp)

func _on_level_up_triggered(new_level: int, draft_options: Array[Dictionary]) -> void:
	_current_draft = draft_options

	if draft_title:
		draft_title.text = "¡NIVEL %d ALCANZADO! ELIGE UNA SINERGIA CINÉTICA" % new_level

	_populate_card(0, card_name_1, card_level_1, card_desc_1)
	_populate_card(1, card_name_2, card_level_2, card_desc_2)
	_populate_card(2, card_name_3, card_level_3, card_desc_3)

	if upgrade_draft_panel:
		upgrade_draft_panel.visible = true

func _populate_card(index: int, name_lbl: Label, lvl_lbl: Label, desc_lbl: Label) -> void:
	if index >= _current_draft.size():
		return
	var info: Dictionary = _current_draft[index]
	var current_lvl: int = int(info.get("current_level", 0))

	if name_lbl:
		name_lbl.text = str(info.get("name", "Sinergia"))
		var accent: Color = info.get("color", Color.WHITE) as Color
		name_lbl.modulate = accent

	if lvl_lbl:
		lvl_lbl.text = "Nivel actual: %d ➔ %d" % [current_lvl, current_lvl + 1]

	if desc_lbl:
		desc_lbl.text = str(info.get("description", ""))

func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= _current_draft.size():
		return
	var chosen: Dictionary = _current_draft[index]
	var chosen_id: String = str(chosen.get("id", ""))

	if upgrade_draft_panel:
		upgrade_draft_panel.visible = false

	GameManager.apply_upgrade(chosen_id)

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
	if upgrade_draft_panel:
		upgrade_draft_panel.visible = false
	if game_over_panel:
		game_over_panel.visible = true
	if game_over_stats:
		game_over_stats.text = "PUNTUACIÓN FINAL: %d | OLEADA ALCANZADA: %d" % [final_score, final_wave]

func _on_restart_button_pressed() -> void:
	GameManager.restart_game()
