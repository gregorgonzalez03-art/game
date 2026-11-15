# AGENTS.md - Reglas de Arquitectura del Estudio

## 1. Motor y Versión
- **Motor obligatorio:** Godot Engine 4.7.1 stable (rama 4.x).
- **Prohibido:** Sintaxis obsoleta de Godot 3.x (`yield`, `KinematicBody`, `Spatial`, `export var` sin `@`, `onready var` sin `@`). Usar `await`, `CharacterBody3D`, `Node3D`, `@export`, `@onready`.

## 2. Estándares de GDScript
- **Tipado estricto obligatorio:** Toda variable, parámetro y retorno de función debe declarar su tipo explícito (ej. `var speed: float = 5.0`, `func take_damage(amount: int) -> void:`).
- **Sin advertencias silenciosas:** El código debe compilar sin warnings de tipado dinámico.

## 3. Arquitectura Modular y Comunicación
- **Principio:** "Call down, signal up". Los nodos padres invocan métodos directos en sus hijos; los hijos emiten señales hacia arriba o hacia el singleton global `EventBus`.
- **Estructura de carpetas:**
  - `res://core/`: Autoloads y sistemas globales.
  - `res://entities/`: Escenas, scripts y assets encapsulados por entidad (`player/`, `enemies/`, `interactables/`).
  - `res://levels/`: Escenas de niveles y geometría modular.
  - `res://ui/`: Menús, HUD y temas (`.tres`).
  - `res://addons/`: Plugins y puente MCP.

## 4. Convenciones Espaciales 3D
- **Escala:** 1 unidad de Godot = 1 metro real.
- **Orientación:** Eje `-Z` hacia adelante (forward).
