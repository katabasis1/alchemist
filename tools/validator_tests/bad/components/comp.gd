## Comp — компонент с сигналом.
## Сигналы: done. Зависимости: нет.
class_name MyComp
extends Node

signal done

@export var exported_one: Node


func run() -> void:
	done.emit()
