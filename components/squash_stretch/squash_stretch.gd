## SquashStretch — сплющивание и вытягивание физического предмета (пестик, колба, ингредиент).
## squash() — удар, приземление: шире и ниже, затем упругий возврат; stretch() — рывок, подъём: уже и выше;
## hold(amount) — держать сжатие, пока палец давит (пестик), release() — отпустить с пружиной.
## Объём сохраняется (x·y ≈ const). Опора — origin цели: ставьте origin спрайта у основания предмета.
## Один узел — один владелец масштаба (см. JuicePunch).
## Сигналы: нет.
## Зависимости: цель — Node2D.
class_name SquashStretch
extends Node

## Пружина возврата: сколько полуволн до покоя.
const SPRING_HALF_WAVES: float = 3.0

@export var target: Node2D
## Сила по умолчанию: 0,2 = на 20 % шире (squash) или выше (stretch).
@export var amount: float = 0.2
@export var recover_sec: float = 0.35
## Предел для hold(): дальше не сжимаем, даже если палец давит сильнее.
@export var max_hold: float = 0.35

var _base_scale: Vector2 = Vector2.ONE
var _tween: Tween
var _from: float = 0.0
var _current: float = 0.0


func _ready() -> void:
	if target == null:
		push_warning("SquashStretch %s: не задан target" % get_path())
		return
	_base_scale = target.scale


func squash(strength: float = 1.0) -> void:
	_spring_from(amount * strength)


func stretch(strength: float = 1.0) -> void:
	_spring_from(-amount * strength)


## Держать деформацию: amount > 0 — сжатие, < 0 — вытягивание. Без пружины.
func hold(value: float) -> void:
	_kill()
	_set_deform(clampf(value, -max_hold, max_hold))


## Отпустить hold() с пружинящим возвратом.
func release() -> void:
	_spring_from(_current)


func _spring_from(value: float) -> void:
	if target == null:
		return
	_kill()
	_from = value
	_tween = create_tween()
	_tween.tween_method(_apply_spring, 0.0, 1.0, recover_sec)


func _apply_spring(t: float) -> void:
	_set_deform(_from * cos(t * PI * SPRING_HALF_WAVES) * pow(1.0 - t, 2.0))


func _set_deform(value: float) -> void:
	_current = value
	if target == null:
		return
	var wide: float = 1.0 + value
	target.scale = Vector2(_base_scale.x * wide, _base_scale.y / wide)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
