## StationTrash — корзина «вылить» у станции (GDD §2: у каждой станции своя корзина). Кнопка: тап — сигнал pressed.
## Пока станция пуста, корзина приглушена и не нажимается (set_active(false)).
## Сигналы: pressed — игрок нажал корзину.
## Зависимости: HitArea, JuicePunch, SfxComponent (@export).
class_name StationTrash
extends Node2D

signal pressed

## Прозрачность приглушённой корзины.
@export var inactive_alpha: float = 0.4
@export var fade_sec: float = 0.15
@export_group("Узлы")
@export var hit_area: HitArea
@export var punch: JuicePunch
@export var sfx: SfxComponent

var active: bool = true
var _fade: Tween


func _ready() -> void:
	hit_area.tapped.connect(_on_tapped)


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	hit_area.set_enabled(value)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, ^"modulate:a", 1.0 if value else inactive_alpha, fade_sec)


func _on_tapped(_world: Vector2) -> void:
	if not active:
		return
	punch.punch()
	sfx.play()
	pressed.emit()
