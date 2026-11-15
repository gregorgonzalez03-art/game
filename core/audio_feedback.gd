extends Node

## Sistema de retroalimentación de audio y efectos procedurales ("Juice").
## Genera tonos sintetizados para Pulso, Pull, Colisiones en Cadena y Esquirlas de XP.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

@export var impact_effect_scene: PackedScene = preload("res://entities/effects/kinetic_impact_effect.tscn")

const SAMPLE_RATE: float = 22050.0

var pulse_playback: AudioStreamGeneratorPlayback
var pull_playback: AudioStreamGeneratorPlayback
var chain_playback: AudioStreamGeneratorPlayback
var xp_playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	pulse_playback = _create_synth_player("PulseSynth")
	pull_playback = _create_synth_player("PullSynth")
	chain_playback = _create_synth_player("ChainSynth")
	xp_playback = _create_synth_player("XPSynth")

	EventBus.pulse_fired.connect(_on_pulse_fired)
	EventBus.pull_fired.connect(_on_pull_fired)
	EventBus.chain_collision.connect(_on_chain_collision)
	EventBus.enemy_launched.connect(_on_enemy_launched)
	EventBus.xp_collected.connect(_on_xp_collected)

func _create_synth_player(player_name: String) -> AudioStreamGeneratorPlayback:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "SFX"
	add_child(player)

	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.35
	player.stream = generator
	player.play()
	return player.get_stream_playback() as AudioStreamGeneratorPlayback

func _on_pulse_fired(_origin: Vector3, _direction: Vector3, _hit_collider: Node3D) -> void:
	play_pulse_sound()

func _on_pull_fired(_target: Node3D) -> void:
	play_pull_sound()

func _on_chain_collision(combo_count: int, collision_pos: Vector3) -> void:
	play_chain_sound(combo_count)

	if impact_effect_scene:
		var effect: Node3D = impact_effect_scene.instantiate() as Node3D
		if effect:
			effect.position = collision_pos
			var root: Node = get_tree().current_scene
			if root:
				root.add_child(effect)

func _on_enemy_launched(_enemy: Node3D, _force: float) -> void:
	play_chain_sound(0)

func _on_xp_collected(_amount: int) -> void:
	play_xp_sound()

## Pulso cinético: golpe seco y grave (deep, dry thump)
func play_pulse_sound() -> void:
	if not pulse_playback:
		return
	var duration: float = 0.10
	var frames_count: int = int(SAMPLE_RATE * duration)
	var available: int = pulse_playback.get_frames_available()
	var frames_to_push: int = mini(frames_count, available)
	var phase: float = 0.0

	for i: int in range(frames_to_push):
		var t: float = float(i) / SAMPLE_RATE
		var progress: float = t / duration
		var freq: float = lerpf(120.0, 48.0, progress)
		phase += freq * (1.0 / SAMPLE_RATE) * TAU
		var envelope: float = exp(-26.0 * t)
		var sample: float = sin(phase) * envelope * 0.55
		pulse_playback.push_frame(Vector2(sample, sample))

## Gancho de atracción (Pull): barrido ascendente rápido
func play_pull_sound() -> void:
	if not pull_playback:
		return
	var duration: float = 0.12
	var frames_count: int = int(SAMPLE_RATE * duration)
	var available: int = pull_playback.get_frames_available()
	var frames_to_push: int = mini(frames_count, available)
	var phase: float = 0.0

	for i: int in range(frames_to_push):
		var t: float = float(i) / SAMPLE_RATE
		var progress: float = t / duration
		var freq: float = lerpf(180.0, 560.0, progress * progress)
		phase += freq * (1.0 / SAMPLE_RATE) * TAU
		var envelope: float = sin(progress * PI) * 0.4
		var sample: float = sin(phase) * envelope
		pull_playback.push_frame(Vector2(sample, sample))

## Colisión en cadena: tono de billar/cristal con pitch incremental (+0.15 por paso)
func play_chain_sound(combo_count: int) -> void:
	if not chain_playback:
		return
	var duration: float = 0.12
	var frames_count: int = int(SAMPLE_RATE * duration)
	var available: int = chain_playback.get_frames_available()
	var frames_to_push: int = mini(frames_count, available)

	var pitch_factor: float = clampf(1.0 + float(combo_count) * 0.15, 1.0, 2.5)
	var base_freq: float = 460.0 * pitch_factor
	var phase1: float = 0.0
	var phase2: float = 0.0

	for i: int in range(frames_to_push):
		var t: float = float(i) / SAMPLE_RATE
		phase1 += base_freq * (1.0 / SAMPLE_RATE) * TAU
		phase2 += (base_freq * 2.756) * (1.0 / SAMPLE_RATE) * TAU
		var envelope: float = exp(-20.0 * t)
		var sample: float = (sin(phase1) * 0.7 + sin(phase2) * 0.3) * envelope * 0.42
		chain_playback.push_frame(Vector2(sample, sample))

## Recogida de Esquirla de XP: tintineo agudo y limpio
func play_xp_sound() -> void:
	if not xp_playback:
		return
	var duration: float = 0.15
	var frames_count: int = int(SAMPLE_RATE * duration)
	var available: int = xp_playback.get_frames_available()
	var frames_to_push: int = mini(frames_count, available)
	var phase1: float = 0.0
	var phase2: float = 0.0

	for i: int in range(frames_to_push):
		var t: float = float(i) / SAMPLE_RATE
		phase1 += 1046.5 * (1.0 / SAMPLE_RATE) * TAU
		phase2 += 1568.0 * (1.0 / SAMPLE_RATE) * TAU
		var envelope: float = exp(-16.0 * t)
		var sample: float = (sin(phase1) * 0.6 + sin(phase2) * 0.4) * envelope * 0.32
		xp_playback.push_frame(Vector2(sample, sample))
