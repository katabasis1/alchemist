## Main — корневая сцена фикстуры.
## Сигналы: нет. Зависимости: blinker, title_label (@export).
extends Node2D

@export var blinker: Node
@export var title_label: Label
@export var spawn_scene: PackedScene


func _ready() -> void:
	title_label.text = tr("ITEM_TITLE")
	var extra: Node = spawn_scene.instantiate()
	add_child(extra)
	var icon: Texture2D = load("res://assets/icons/icon_a.png")
	if icon == null:
		push_warning("no icon")


func _on_blinker_blinked() -> void:
	print_debug("blinked")
