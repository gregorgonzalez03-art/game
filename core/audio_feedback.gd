extends Node

## Sistema de retroalimentación de audio y efectos procedurales ("Juice").
## Genera tonos sintetizados cuyo pitch escala (0.9 a 1.8) con las reacciones en cadena
## e instancia efectos de chispas en las colisiones.

@export var impact_effect_scene: PackedScene = preload("res://entities/effects/kinetic_impact_effect.tscn")

var audio_player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
var sample_rate: float = 22050.0

func _ready() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "SFX"
	add_child(audio_player)

	generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.1
	audio_player.stream = generator
	audio_player.play()
	playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

	EventBus.chain_collision.connect(_on_chain_collision)
	EventBus.enemy_launched.connect(_on_enemy_launched)

func _on_chain_collision(combo_count: int, collision_pos: Vector3) -> void:
	var pitch_factor: float = clampf(0.9 + float(combo_count) * 0.12, 0.9, 1.8)
	var freq: float = 330.0 * pitch_factor
	_play_procedural_chime(freq, 0.09)

	if impact_effect_scene:
		var effect: Node3D = impact_effect_scene.instantiate() as Node3D
		if effect:
			effect.position = collision_pos
			var root: Node = get_tree().current_scene
			if root:
				root.add_child(effect)

func _on_enemy_launched(_enemy: Node3D, _force: float) -> void:
	_play_procedural_chime(220.0, 0.06)

func _play_procedural_chime(frequency: float, duration: float) -> void:
	if not playback:
		return
	var frames_to_fill: int = int(sample_rate * duration)
	for i: int in range(frames_to_fill):
		var t: float = float(i) / sample_rate
		var envelope: float = 1.0 - (float(i) / float(frames_to_fill))
		var sample: float = sin(t * frequency * TAU) * envelope * 0.35
		playback.push_frame(Vector2(sample, sample))
