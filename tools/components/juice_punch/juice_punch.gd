## JuicePunch — короткий упругий импульс цели: punch() — «пульс» масштабом (монеты, кнопка, иконка),
## wiggle() — покачивание «нет-нет» поворотом (отказ, ошибка). После импульса цель точно в исходном виде.
## Один узел — один владелец масштаба: не давайте JuicePunch тот же узел, что SquashStretch/Hoverable.
## Сигналы: finished.
## Зависимости: цель — Node2D или Control (у Control задайте pivot_offset в центр).
class_name JuicePunch
extends Node

signal finished

## Затухающая синусоида: сколько полуволн за импульс (3 — рост, лёгкий провал, возврат).
const PUNCH_HALF_WAVES: float = 3.0

@export var target: CanvasItem
## Насколько вырастает в пике: 0,18 = +18 %.
@export var punch_scale: float = 0.18
@export var punch_sec: float = 0.3
## Размах покачивания, градусы.
@export var wiggle_deg: float = 9.0
@export var wiggle_sec: float = 0.35
## Сколько полных покачиваний за wiggle_sec.
@export var wiggle_count: float = 3.0

var _base_scale: Vector2 = Vector2.ONE
var _base_rotation: float = 0.0
var _scale_tween: Tween
var _rotation_tween: Tween
var _strength: float = 1.0


func _ready() -> void:
	if target == null:
		push_warning("JuicePunch %s: не задан target" % get_path())
		return
	_base_scale = target.get(&"scale")
	_base_rotation = target.get(&"rotation")


## Пульс масштабом. strength — множитель силы (1 — как в инспекторе).
func punch(strength: float = 1.0) -> void:
	if target == null:
		return
	_strength = strength
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_method(_apply_punch, 0.0, 1.0, punch_sec)
	_scale_tween.tween_callback(finished.emit)


## Покачивание «нет-нет».
func wiggle(strength: float = 1.0) -> void:
	if target == null:
		return
	_strength = strength
	if _rotation_tween != null and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = create_tween()
	_rotation_tween.tween_method(_apply_wiggle, 0.0, 1.0, wiggle_sec)
	_rotation_tween.tween_callback(finished.emit)


func _apply_punch(t: float) -> void:
	var k: float = sin(t * PI * PUNCH_HALF_WAVES) * pow(1.0 - t, 2.0)
	target.set(&"scale", _base_scale * (1.0 + punch_scale * _strength * k))


func _apply_wiggle(t: float) -> void:
	var k: float = sin(t * TAU * wiggle_count) * (1.0 - t)
	target.set(&"rotation", _base_rotation + deg_to_rad(wiggle_deg) * _strength * k)
