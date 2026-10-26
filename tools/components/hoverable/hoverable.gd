## Hoverable — отклик на наведение мыши: цель светлеет и чуть подрастает (на телефоне наведения нет).
## Масштаб меняет только у своей цели: не давайте ей тот же узел, что JuicePunch/SquashStretch/Draggable
## (один узел — один владелец масштаба; см. docs/COMPONENTS.md).
## Сигналы: hover_started, hover_ended.
## Зависимости: HitArea (источник наведения), цель — Node2D или Control.
class_name Hoverable
extends Node

signal hover_started
signal hover_ended

@export var hit_area: HitArea
## Что подсвечивать. У Control задайте pivot_offset в центр, иначе он растёт от угла.
@export var target: CanvasItem
## Множитель modulate при наведении (> 1 — светлее).
@export var hover_modulate: Color = Color(1.12, 1.1, 1.05, 1.0)
## Множитель масштаба при наведении; 1 — без роста, и тогда Hoverable вообще не трогает scale
## (target можно отдать JuicePunch/SquashStretch: один узел — один владелец масштаба).
@export var hover_scale: float = 1.04
@export var tween_sec: float = 0.1
@export var enabled: bool = true

var _base_modulate: Color = Color.WHITE
var _base_scale: Vector2 = Vector2.ONE
var _tween: Tween


func _ready() -> void:
	if target == null or hit_area == null:
		push_warning("Hoverable %s: не заданы hit_area или target" % get_path())
		return
	_base_modulate = target.modulate
	if hover_scale != 1.0:
		_base_scale = target.get(&"scale")
	hit_area.hover_changed.connect(_on_hover_changed)


func _on_hover_changed(hovered: bool) -> void:
	if not enabled and hovered:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var to_modulate: Color = _base_modulate * hover_modulate if hovered else _base_modulate
	var to_scale: Vector2 = _base_scale * hover_scale if hovered else _base_scale
	_tween.tween_property(target, ^"modulate", to_modulate, tween_sec)
	if hover_scale != 1.0:
		_tween.tween_property(target, ^"scale", to_scale, tween_sec)
	if hovered:
		hover_started.emit()
	else:
		hover_ended.emit()
