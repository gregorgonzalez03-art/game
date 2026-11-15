@tool
extends EditorScenePostImport

## Pipeline de Post-Importación 3D para Arena Cinética 3D (Paso 4.1).
## Se ejecuta automáticamente al importar modelos .glb en Godot.
## Optimiza mallas aplicando enemy_hit_fresnel.gdshader y configurando colisionadores primitivos para Jolt Physics.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

const ENEMY_SHADER: Shader = preload("res://entities/effects/enemy_hit_fresnel.gdshader")

func _post_import(scene: Node) -> Object:
	return process_imported_scene(scene)

static func process_imported_scene(scene: Node) -> Node:
	_process_node(scene)
	return scene

static func _process_node(node: Node) -> void:
	if not node:
		return

	if node is MeshInstance3D:
		_process_mesh_instance(node as MeshInstance3D)

	for child: Node in node.get_children():
		_process_node(child)

static func _process_mesh_instance(mesh_inst: MeshInstance3D) -> void:
	var node_name: String = mesh_inst.name.to_lower()
	var parent_name: String = ""
	if mesh_inst.get_parent():
		parent_name = mesh_inst.get_parent().name.to_lower()

	# 1. Asignación automática de Shader Fresnel si pertenece a entidades enemigas
	var is_enemy_asset: bool = (
		"enemy" in node_name or "swarmer" in node_name or "brute" in node_name 
		or "bomb" in node_name or "enemy" in parent_name or "enemies" in parent_name
	)

	if is_enemy_asset and ENEMY_SHADER:
		var shader_mat: ShaderMaterial = ShaderMaterial.new()
		shader_mat.shader = ENEMY_SHADER

		var existing_mat: Material = mesh_inst.get_active_material(0)
		if existing_mat is StandardMaterial3D:
			var std_mat: StandardMaterial3D = existing_mat as StandardMaterial3D
			shader_mat.set_shader_parameter("albedo_color", std_mat.albedo_color)
			shader_mat.set_shader_parameter("emission_color", std_mat.emission)
			shader_mat.set_shader_parameter("emission_energy", std_mat.emission_energy_multiplier)
			shader_mat.set_shader_parameter("metallic", std_mat.metallic)
			shader_mat.set_shader_parameter("roughness", std_mat.roughness)

		mesh_inst.material_override = shader_mat

	# 2. Configuración de colisionadores primitivos de alto rendimiento para Jolt Physics
	_generate_primitive_collider(mesh_inst, node_name)

static func _generate_primitive_collider(mesh_inst: MeshInstance3D, node_name: String) -> void:
	var mesh: Mesh = mesh_inst.mesh
	if not mesh:
		return

	var aabb: AABB = mesh.get_aabb()
	var size: Vector3 = aabb.size

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "AutoCollider_" + mesh_inst.name

	# Selección de la forma primitiva óptima (evita mallas cóncavas pesadas)
	if "sphere" in node_name or _is_approx_sphere(size):
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = (size.x + size.y + size.z) / 6.0
		collision_shape.shape = sphere
	elif "cylinder" in node_name or "capsule" in node_name or _is_approx_cylinder(size):
		var cylinder: CylinderShape3D = CylinderShape3D.new()
		cylinder.height = size.y
		cylinder.radius = maxf(size.x, size.z) * 0.5
		collision_shape.shape = cylinder
	else:
		var box: BoxShape3D = BoxShape3D.new()
		box.size = size
		collision_shape.shape = box

	collision_shape.position = aabb.get_center()
	mesh_inst.add_child(collision_shape)
	collision_shape.owner = mesh_inst.owner if mesh_inst.owner else mesh_inst

static func _is_approx_sphere(size: Vector3) -> bool:
	var avg: float = (size.x + size.y + size.z) / 3.0
	return (absf(size.x - avg) < avg * 0.15 and absf(size.y - avg) < avg * 0.15 and absf(size.z - avg) < avg * 0.15)

static func _is_approx_cylinder(size: Vector3) -> bool:
	return absf(size.x - size.z) < maxf(size.x, size.z) * 0.2 and size.y > maxf(size.x, size.z) * 1.2
