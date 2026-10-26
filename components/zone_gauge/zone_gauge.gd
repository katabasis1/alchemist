## ZoneGauge — вертикальная шкала 0…1 с зоной «идеально» (помол ступки; позже — градусник горелки, S4).
## Рисует её шейдер zone_gauge.gdshader на этом же ColorRect; скрипт только передаёт значения.
## Цвет заливки зависит от положения: ниже зоны, в зоне, выше зоны — цвет никогда не единственный признак:
## зона ещё и обведена, а у значения есть риска. Касания не ловит (mouse_filter = IGNORE).
## Сигналы: zone_changed(zone) — заливка перешла в другую часть шкалы (Zone.BELOW / INSIDE / ABOVE).
## Зависимости: ShaderMaterial с zone_gauge.gdshader (local to scene: у каждого экземпляра свой).
class_name ZoneGauge
extends ColorRect

signal zone_changed(zone: Zone)

enum Zone { BELOW, INSIDE, ABOVE }

@export_range(0.0, 1.0) var zone_from: float = 0.7
@export_range(0.0, 1.0) var zone_to: float = 0.85
@export var color_below: Color = Color(0.94, 0.63, 0.05, 1.0)
@export var color_inside: Color = Color(0.49, 0.85, 0.34, 1.0)
@export var color_above: Color = Color(0.61, 0.54, 0.45, 1.0)
## За сколько секунд заливка догоняет новое значение (0 — сразу).
@export var fill_sec: float = 0.12
@export var color_sec: float = 0.18
@export var fade_sec: float = 0.2

var value: float = 0.0
var zone: Zone = Zone.BELOW

var _shown_value: float = 0.0
var _fill_tween: Tween
var _color_tween: Tween
var _fade_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_on_resized()
	set_zone(zone_from, zone_to)
	_apply_value(value)
	_set_param(&"fill_color", _color_for(zone))


## Новое значение 0…1. instant — без догоняющей анимации (сброс).
func set_value(new_value: float, instant: bool = false) -> void:
	value = clampf(new_value, 0.0, 1.0)
	var new_zone: Zone = zone_of(value)
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	if instant or fill_sec <= 0.0:
		_apply_value(value)
	else:
		_fill_tween = create_tween()
		_fill_tween.tween_method(_apply_value, _shown_value, value, fill_sec)
	if new_zone != zone:
		zone = new_zone
		_tint(_color_for(zone), instant)
		zone_changed.emit(zone)


func set_zone(from: float, to: float) -> void:
	zone_from = clampf(minf(from, to), 0.0, 1.0)
	zone_to = clampf(maxf(from, to), 0.0, 1.0)
	_set_param(&"zone_from", zone_from)
	_set_param(&"zone_to", zone_to)


func zone_of(v: float) -> Zone:
	if v < zone_from:
		return Zone.BELOW
	if v <= zone_to:
		return Zone.INSIDE
	return Zone.ABOVE


## Мигание зоны (обучение: «доведи до зелёного», GDD §7.1).
func set_zone_pulse(on: bool) -> void:
	_set_param(&"zone_pulse", 1.0 if on else 0.0)


## Плавно показать или спрятать шкалу.
func show_gauge(on: bool) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if on and not visible:
		modulate.a = 0.0
		visible = true
	var to_alpha: float = 1.0 if on else 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", to_alpha, fade_sec)
	if not on:
		_fade_tween.tween_callback(hide)


func _apply_value(v: float) -> void:
	_shown_value = v
	_set_param(&"value", v)


func _tint(color: Color, instant: bool) -> void:
	if _color_tween != null and _color_tween.is_valid():
		_color_tween.kill()
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat == null:
		return
	if instant or color_sec <= 0.0:
		mat.set_shader_parameter(&"fill_color", color)
		return
	var from: Color = mat.get_shader_parameter(&"fill_color")
	_color_tween = create_tween()
	_color_tween.tween_method(_set_fill_color, from, color, color_sec)


func _set_fill_color(color: Color) -> void:
	_set_param(&"fill_color", color)


func _color_for(z: Zone) -> Color:
	match z:
		Zone.INSIDE:
			return color_inside
		Zone.ABOVE:
			return color_above
	return color_below


func _on_resized() -> void:
	_set_param(&"rect_size", size)


func _set_param(param: StringName, v: Variant) -> void:
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(param, v)
