class_name UpgradesCatalog
extends RefCounted

## Catálogo estructurado de sinergias físicas y mejoras de progresión en partida.
## Cumple estrictamente con AGENTS.md (Godot 4.x, tipado estricto).

static var CATALOG: Dictionary = {
	"elastic_ricochet": {
		"id": "elastic_ricochet",
		"name": "Rebote Elástico",
		"description": "+35% de fuerza de rebote y multiplicador de impacto en cadena cuando un enemigo lanzado choca contra otro.",
		"color": Color("#00E5FF")
	},
	"gravity_singularity": {
		"id": "gravity_singularity",
		"name": "Singularidad de Gancho",
		"description": "Al atraer con Clic Derecho, un pulso gravitacional arrastra enemigos cercanos en 4.5m hacia el punto de suspensión.",
		"color": Color("#FF00E5")
	},
	"shockwave_pulse": {
		"id": "shockwave_pulse",
		"name": "Pulso de Onda Ancha",
		"description": "Amplía el cono del Pulso Cinético en +25% y añade empuje secundario en área alrededor del objetivo impactado.",
		"color": Color("#FFCC00")
	},
	"volatile_shrapnel": {
		"id": "volatile_shrapnel",
		"name": "Inestabilidad Volátil",
		"description": "+30% de radio de explosión en Bombas. Los Swarmers que eliminan enemigos generan una micro-onda al caer al vacío.",
		"color": Color("#FF5500")
	},
	"kinetic_overdrive": {
		"id": "kinetic_overdrive",
		"name": "Sobrecarga Cinética",
		"description": "-20% de cooldown en Pulso Cinético y Ganchazo. +2.5m de distancia de atracción magnética para Esquirlas de XP.",
		"color": Color("#00FF66")
	}
}

static func get_all_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: Variant in CATALOG.keys():
		ids.append(str(id))
	return ids

static func get_upgrade(id: String) -> Dictionary:
	return CATALOG.get(id, {})

static func get_random_draft(count: int = 3) -> Array[Dictionary]:
	var all_ids: Array[String] = get_all_ids()
	all_ids.shuffle()
	var draft: Array[Dictionary] = []
	var selected_count: int = mini(count, all_ids.size())
	for i: int in range(selected_count):
		var id: String = all_ids[i]
		var info: Dictionary = get_upgrade(id).duplicate()
		info["current_level"] = GameManager.get_upgrade_stacks(id)
		draft.append(info)
	return draft
