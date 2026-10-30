## BandGauge — вертикальная шкала среза (колба-отстойник S4.2, STATIONS §1.2): риски на границах слоёв, вокруг
## каждой — зелёная полоса «чистый срез», бегунок — где сейчас срез. 0 — верх шкалы, 1 — низ: значение — сколько
## столба уже слито (как poured в AlchemyRules.pour_top), поэтому заливка идёт сверху вниз.
## Полосы и риски задаёт владелец (AlchemyRules.clean_bands / cut_marks); шкала их только рисует и знает, в какой
## полосе бегунок, чтобы перекрасить заливку. Цвет не единственный признак: полоса обведена, риска — светлая черта,
## бегунок — яркая черта потолще. Рисует шейдер band_gauge.gdshader на этом же ColorRect; касания не ловит.
## Без цифр и звёзд: точные доли — Индикатору (S6).
## Сигналы: band_changed(band) — бегунок вошёл в полосу band или вышел из всех (OUTSIDE).
## Зависимости: ShaderMaterial с band_gauge.gdshader (band_gauge_material.tres, local to scene).
class_name BandGauge
extends ColorRect

signal band_changed(band: int)

## Полос не больше, чем границ между шестью слоями (LiquidLayers.MAX_LAYERS − 1): под этот размер — массивы шейдера.
const MAX_BANDS: int = 5
## Бегунок вне полос.
const OUTSIDE: int = -1

@export var color_outside: Color = Color(0.94, 0.63, 0.05, 1.0)
@export var color_inside: Color = Color(0.49, 0.85, 0.34, 1.0)
## За сколько секунд заливка догоняет новое значение (0 — сразу). Короче, чем у шкалы помола: струя быстрая.
@export var fill_sec: float = 0.06
@export var color_sec: float = 0.12
@export var fade_sec: float = 0.2

var value: float = 0.0
var band: int = OUTSIDE

var _bands: Array[Vector2] = []
var _shown_value: float = 0.0
var _fill_tween: Tween
var _color_tween: Tween
var _fade_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_on_resized()
	var no_bands: Array[Vector2] = []
	var no_marks: Array[float] = []
	set_bands(no_bands, no_marks)
	_apply_value(value)
	_set_param(&"fill_color", _color_for(band))


## Полосы (x — от, y — до) и риски, доли столба сверху; лишние сверх MAX_BANDS отбрасываются.
func set_bands(bands: Array[Vector2], marks: Array[float]) -> void:
	_bands.clear()
	for i: int in mini(bands.size(), MAX_BANDS):
		_bands.append(bands[i])
	var band_slots: PackedVector2Array = PackedVector2Array()
	var mark_slots: PackedFloat32Array = PackedFloat32Array()
	for i: int in MAX_BANDS:
		band_slots.append(_bands[i] if i < _bands.size() else Vector2(-1.0, -1.0))
		mark_slots.append(marks[i] if i < marks.size() else -1.0)
	_set_param(&"band_count", _bands.size())
	_set_param(&"bands", band_slots)
	_set_param(&"marks", mark_slots)
	_update_band(true)


## Где срез: 0…1 сверху. instant — без догоняющей анимации (сброс).
func set_value(new_value: float, instant: bool = false) -> void:
	value = clampf(new_value, 0.0, 1.0)
	if _fill_tween != null and _fill_tween.is_valid():
		_fill_tween.kill()
	if instant or fill_sec <= 0.0:
		_apply_value(value)
	else:
		_fill_tween = create_tween()
		_fill_tween.tween_method(_apply_value, _shown_value, value, fill_sec)
	_update_band(instant)


## В какой полосе точка v (OUTSIDE — ни в одной). Края включены.
func band_at(v: float) -> int:
	for i: int in _bands.size():
		if _bands[i].x <= v and v <= _bands[i].y:
			return i
	return OUTSIDE


func band_count() -> int:
	return _bands.size()


## Мигание полос (обучение: «останови струю на зелёном», GDD §7.1).
func set_band_pulse(on: bool) -> void:
	_set_param(&"band_pulse", 1.0 if on else 0.0)


## Плавно показать или спрятать шкалу.
func show_gauge(on: bool) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if on and not visible:
		modulate.a = 0.0
		visible = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 1.0 if on else 0.0, fade_sec)
	if not on:
		_fade_tween.tween_callback(hide)


func _update_band(instant: bool) -> void:
	var new_band: int = band_at(value)
	if new_band == band:
		return
	band = new_band
	_tint(_color_for(band), instant)
	band_changed.emit(band)


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


func _color_for(b: int) -> Color:
	return color_outside if b == OUTSIDE else color_inside


func _on_resized() -> void:
	_set_param(&"rect_size", size)


func _set_param(param: StringName, v: Variant) -> void:
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(param, v)
