# GODOT 4.x GDScript rules — READ THIS BEFORE WRITING ANY .gd CODE

You are writing **Godot 4.x** GDScript (GDScript 2.0). Your training data is dominated by **Godot 3**,
whose API was renamed/broken in Godot 4. Emitting Godot-3 syntax is the #1 cause of failure here.
**Never** emit Godot-3 API. Prefer statically-typed GDScript. Match the surrounding file's style.

## Godot 3 → Godot 4 — the breakages you MUST get right

| ❌ Godot 3 (WRONG — will fail the gate) | ✅ Godot 4 (REQUIRED) |
|---|---|
| `export var hp = 10` | `@export var hp: int = 10` |
| `onready var s = $Sprite` | `@onready var s: Sprite2D = $Sprite2D` |
| `extends KinematicBody2D` / `KinematicBody` | `extends CharacterBody2D` / `CharacterBody3D` |
| `extends Spatial` | `extends Node3D` |
| `move_and_slide(velocity, Vector2.UP)` | set `velocity` property, then `move_and_slide()` (no args) |
| `yield(get_tree().create_timer(1), "timeout")` | `await get_tree().create_timer(1).timeout` |
| `sig.connect("name", self, "_on_x")` | `sig.connect(_on_x)`  (pass a Callable, not strings) |
| `emit_signal("died")` (ok but prefer) | `died.emit()` |
| `.instance()` | `.instantiate()` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `Quat` / `Transform` (3D) | `Quaternion` / `Transform3D` |
| `PoolStringArray` / `PoolIntArray` etc. | `PackedStringArray` / `PackedInt32Array` |
| `rand_range(a, b)` | `randf_range(a, b)` |
| `File.new()` / `Directory.new()` | `FileAccess.open(...)` / `DirAccess.open(...)` |
| `setget getter, setter` | `var x: int : get = _get_x, set = _set_x` |
| `class_name Foo, "res://icon.png"` | `class_name Foo` (icon via `@icon("res://icon.png")` annotation) |

## Signals belong to specific node types
A signal must exist on the type you `extends`. `body_entered` is on `Area2D`/`RigidBody2D`, NOT
`CharacterBody2D`. If you connect a signal, confirm the node/type actually declares it. Declare custom
signals with `signal my_signal(arg: int)` and emit with `my_signal.emit(value)`.

## Typed GDScript conventions (this codebase uses them)
- Annotate function params and returns: `func take_damage(amount: int) -> void:`
- Type vars: `var speed: float = 0.0`; infer with `:=` when the RHS type is obvious.
- Constants `UPPER_SNAKE`, funcs/vars `snake_case`, classes/nodes `PascalCase`.
- Prefer `@export` for inspector-tunable values; group with `@export_group` if the file already does.

## Correct Godot 4 example (imitate this shape)
```gdscript
extends CharacterBody2D
class_name Enemy

signal died(by: Node)

@export var max_hp: int = 30
@export var speed: float = 120.0
@onready var sprite: Sprite2D = $Sprite2D

var hp: int = max_hp

func _ready() -> void:
    died.connect(_on_died)

func take_damage(amount: int) -> void:
    hp -= amount
    if hp <= 0:
        died.emit(self)

func _on_died(_by: Node) -> void:
    queue_free()

func _physics_process(_delta: float) -> void:
    move_and_slide()
```

## Before you finish
- Every `.gd` file must PARSE as Godot 4 (no `export var`, no `yield(`, no `KinematicBody`).
- Only reference methods/signals that exist on the node type you extend.
- If you add a function the item asked for, make sure it is actually called or is `@export`/public as specified.
