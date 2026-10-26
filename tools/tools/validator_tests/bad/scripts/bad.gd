## Bad — набор нарушений.
## Сигналы: нет. Зависимости: нет.
extends Node2D

var untyped = 5
var y: float = 3.7


func f(a) -> void:
	var s := Sprite2D.new()
	add_child(s)
	var n := $Sprite
	var t: Texture2D = load("res://missing.png")
	var k := tr("NOPE_KEY")
	yield(get_tree(), "idle_frame")
	if a:
	print_debug(n, t, k)


func g(b: int):
	pass
