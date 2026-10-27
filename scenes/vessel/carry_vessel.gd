## CarryVessel — сосуд с содержимым станции, который игрок несёт клиенту (GDD §3.3 «Перенос»): из ступки — баночка
## мази, из колбы (S3) — флакон. Вид на оценку не влияет. Пока сосуд не в руке, он спрятан на своей точке в станции.
## Станция наполняет его, когда игрок берёт содержимое (fill + show_up), и прячет, когда сосуд вернулся или отдан (stow).
## Несёт его Draggable станции (body — этот узел, kind = &"potion"). Область касания остаётся у станции:
## спрятанный узел касаний не ловит.
## Сигналы: нет. Методы: fill(mixture, grind), show_up(), stow(), is_filled().
## Зависимости: нет. Узлы сцены: Lift (его приподнимает Draggable) → Pop (появление) → Sprite; Shadow.
class_name CarryVessel
extends Node2D

## Узел, который «выскакивает» при появлении. Не тот, что приподнимает Draggable (lift_node), иначе твины подерутся.
@export var pop: Node2D
@export var appear_sec: float = 0.16
@export var appear_from_scale: float = 0.35

## Свойства смеси: id свойства → доли (GDD §3.2). Пусто — сосуд пуст.
var mixture: Dictionary[StringName, float] = {}
## Помол, с которым смесь ушла из ступки (0…1); −1 — смесь не из ступки. FTUE 1–3 сверяют его с зоной «идеально».
var grind: float = -1.0
var _tween: Tween


func _ready() -> void:
	visible = false


func fill(new_mixture: Dictionary[StringName, float], new_grind: float) -> void:
	mixture = new_mixture.duplicate()
	grind = new_grind


func is_filled() -> bool:
	return not mixture.is_empty()


## Показаться в станции с коротким «выскоком».
func show_up() -> void:
	if visible:
		return
	visible = true
	_kill_tween()
	pop.scale = Vector2.ONE * appear_from_scale
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(pop, ^"scale", Vector2.ONE, appear_sec)


## Спрятаться и опустеть: сосуд вернули в станцию или отдали клиенту.
func stow() -> void:
	_kill_tween()
	visible = false
	pop.scale = Vector2.ONE
	mixture = {}
	grind = -1.0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
