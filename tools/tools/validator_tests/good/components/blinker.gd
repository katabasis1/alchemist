## Blinker — мигает целевым узлом.
## Сигналы: blinked. Зависимости: target (@export).
extends Node

signal blinked

const BLINK_TIME: float = 0.25

@export var target: CanvasItem
@export var config: ItemData
@export_range(0.1, 3.0)
var speed: float = 1.5


func blink() -> void:
	if target == null:
		return
	var tween := create_tween()
	tween.tween_property(target, "modulate:a", 0.0, BLINK_TIME)
	tween.tween_property(target, "modulate:a", 1.0, BLINK_TIME)
	blinked.emit()
