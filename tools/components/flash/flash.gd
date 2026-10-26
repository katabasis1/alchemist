## Flash — короткая вспышка цветом: «принято», попадание, «нельзя», вспышка экрана при открытии рецепта.
## Режим SHADER: у target материал components/flash/flash_material.tres (свой у каждой копии сцены —
## resource_local_to_scene), вспышка красит силуэт ровно в flash_color.
## Режим MODULATE: без материала — modulate уходит к flash_color и возвращается. Подходит для
## оверлея-ColorRect (базовая альфа 0 → вспышка на весь экран) и для лёгкого «подсвечивания» спрайта.
## Сигналы: finished.
## Зависимости: target (CanvasItem; в режиме SHADER — с flash_material.tres).
class_name Flash
extends Node

signal finished

enum Mode { SHADER, MODULATE }

const PARAM_AMOUNT: StringName = &"flash_amount"
const PARAM_COLOR: StringName = &"flash_color"

@export var target: CanvasItem
@export var mode: Mode = Mode.SHADER
## SHADER: цвет подмеса (альфа — сила). MODULATE: цвет, к которому уходит modulate на пике.
@export var flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Сила пика 0…1 при strength = 1.
@export var peak: float = 0.8
@export var hold_sec: float = 0.03
@export var fade_sec: float = 0.18
@export var enabled: bool = true

var _base_modulate: Color = Color.WHITE
var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	if target == null:
		push_warning("Flash %s: не задан target" % get_path())
		return
	_base_modulate = target.modulate
	if mode == Mode.SHADER:
		_material = target.material as ShaderMaterial
		if _material == null:
			push_warning("Flash %s: у target нет ShaderMaterial (flash_material.tres) — переключаюсь на MODULATE" % get_path())
			mode = Mode.MODULATE


## Вспыхнуть. strength 0…1 — доля пика (слабое попадание — 0.5).
func flash(strength: float = 1.0) -> void:
	if not enabled or target == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var top: float = clampf(peak * strength, 0.0, 1.0)
	if mode == Mode.SHADER:
		_material.set_shader_parameter(PARAM_COLOR, flash_color)
	_set_amount(top)
	_tween = create_tween()
	_tween.tween_interval(hold_sec)
	_tween.tween_method(_set_amount, top, 0.0, fade_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(finished.emit)


func _set_amount(value: float) -> void:
	if mode == Mode.SHADER:
		_material.set_shader_parameter(PARAM_AMOUNT, value)
	else:
		target.modulate = _base_modulate.lerp(flash_color, value)
