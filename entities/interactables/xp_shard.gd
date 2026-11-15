extends Area3D

## Esquirla de XP con degradación temporal y atracción magnética hacia el jugador.
## Cumple estrictamente con AGENTS.md (tipado estricto).

const SHARD_COLOR: Color = Color("#00FF66")

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
var rotation_speed: float = 5.5

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var omni_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group("xp_shards")
	current_xp = base_xp
	body_entered.connect(_on_body_entered)

	if mesh_instance:
		var base_mat: Material = mesh_instance.get_active_material(0)
		var mat: StandardMaterial3D = null
		if base_mat:
			mat = base_mat.duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()

		# Aislamiento estricto de material y valores iniciales limpios
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color = SHARD_COLOR
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = SHARD_COLOR
		mat.emission_energy_multiplier = 2.8
		mesh_instance.material_override = mat
		mesh_instance.scale = Vector3.ONE

	if omni_light:
		omni_light.light_color = SHARD_COLOR
		omni_light.light_energy = 1.4
		omni_light.omni_range = 2.0
		omni_light.shadow_enabled = false

## Atrae inmediatamente la esquirla al jugador a alta velocidad (usado en transiciones de oleada)
func attract_to_player() -> void:
	is_collecting = true
	magnet_speed = 32.0

func _process(delta: float) -> void:
	life_timer += delta

	# Rotación continua (rápida al nacer, lenta al degradarse)
	rotate_y(rotation_speed * delta)

	# Rebote vertical sutil (sin) que no interfiere con la atracción magnética
	if mesh_instance:
		if not is_collecting:
			mesh_instance.position.y = sin(life_timer * 4.0) * 0.12
		else:
			mesh_instance.position.y = 0.0

	# Degradación de valor tras 4.0 segundos
	if not is_degraded and life_timer >= degrade_duration:
		_degrade_shard()

func _physics_process(delta: float) -> void:
	# Búsqueda y atracción magnética al jugador
	_check_player_magnet(delta)

func _degrade_shard() -> void:
	is_degraded = true
	current_xp = degraded_xp

	# Transición suave con Tween preservando la identidad visual (mismo Verde Esmeralda Neón)
	var tween: Tween = create_tween()
	tween.set_parallel(true)

	if mesh_instance:
		tween.tween_property(mesh_instance, "scale", Vector3(0.55, 0.55, 0.55), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if mesh_instance.material_override:
			var mat: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
			if mat:
				# Mantiene TRANSPARENCY_DISABLED y SHARD_COLOR ("#00FF66"), solo reduce energía
				mat.albedo_color = SHARD_COLOR
				mat.emission = SHARD_COLOR
				tween.tween_property(mat, "emission_energy_multiplier", 0.7, 0.4)

	tween.tween_property(self, "rotation_speed", 1.8, 0.4)

	if omni_light:
		omni_light.light_color = SHARD_COLOR
		tween.tween_property(omni_light, "light_energy", 0.5, 0.4)

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
	EventBus.xp_collected.emit(current_xp)
	GameManager.add_xp(current_xp)
	queue_free()
