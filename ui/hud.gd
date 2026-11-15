extends CanvasLayer

@onready var score_label: Label = $UI/MarginContainer/VBoxContainer/ScoreLabel
@onready var combo_label: Label = $UI/MarginContainer/VBoxContainer/ComboLabel

func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.combo_updated.connect(_on_combo_updated)
	_on_score_changed(GameManager.score)
	_on_combo_updated(GameManager.combo_count, GameManager.combo_multiplier)

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "SCORE: %d" % new_score

func _on_combo_updated(count: int, multiplier: float) -> void:
	if combo_label:
		if count > 0:
			combo_label.text = "COMBO x%.1f (%d)" % [multiplier, count]
			combo_label.visible = true
		else:
			combo_label.visible = false
