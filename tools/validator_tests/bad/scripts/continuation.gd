## Перенос выражения без скобок — G016 (Godot: Expected statement, found "Indent").
extends Node


func _ready() -> void:
	var a: bool = true
	var b: bool = a
			and a
	print(b)
