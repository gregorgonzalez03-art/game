extends Area3D

## Esquirla de XP con degradación temporal y atracción magnética hacia el jugador.
## Cumple estrictamente con AGENTS.md (tipado estricto).

@export var base_xp: int = 10
@export var degraded_xp: int = 5
@export var degrade_duration: float = 4.0
@export var magnet_radius: float = 3.0
@export var magnet_speed: float = 14.0

var current_xp: int = 10
var life_timer: float = 0.0
var is_degraded: bool = false
var is_collecting: bool = false
var player_ref: Node3D = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group("xp_shards")
	current_xp = base_xp
	body_entered.connect(_on_body_entered)
	if mesh_instance and mesh_instance.material_override:
		mesh_instance.material_override = mesh_instance.material_override.duplicate()

## Atrae inmediatamente la esquirla al jugador a alta velocidad (usado en transiciones de oleada)
func attract_to_player() -> void:
	is_collecting = true
	magnet_speed = 32.0

func _physics_process(delta: float) -> void:
	life_timer += delta

	# Rotación sutil
	rotate_y(2.5 * delta)

	# Degradación de valor tras 4.0 segundos
	if not is_degraded and life_timer >= degrade_duration:
		_degrade_shard()

	# Búsqueda y atracción magnética al jugador
	_check_player_magnet(delta)

func _degrade_shard() -> void:
	is_degraded = true
	current_xp = degraded_xp
	if mesh_instance and mesh_instance.material_override:
		var mat: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.85, 0.5, 0.1, 0.6)
			mat.emission = Color(0.85, 0.4, 0.05, 1.0)
			mat.emission_energy_multiplier = 0.6

func _check_player_magnet(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player") as Node3D

	if not player_ref:
		return

	var diff: Vector3 = player_ref.global_position + Vector3(0.0, 0.9, 0.0) - global_position
	var dist: float = diff.length()

	if dist <= magnet_radius or is_collecting:
		is_collecting = true
		var move_step: Vector3 = diff.normalized() * (magnet_speed * delta)
		global_position += move_step
		if dist <= 0.6:
			_collect()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect()

func _collect() -> void:
	GameManager.add_xp(current_xp)
	queue_free()
