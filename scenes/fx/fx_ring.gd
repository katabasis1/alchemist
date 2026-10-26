## FxRing — расходящееся кольцо света (scenes/fx/fx_ring.tscn): «идеально» у ступки, позже — звёзды и открытия.
## Кольцо рисует шейдер fx_ring.gdshader во весь прямоугольник, поэтому его пропорции задаёт размер узла.
## Сигналы: нет.
## Зависимости: свой материал fx_ring_material.tres (resource_local_to_scene).
class_name FxRing
extends ColorRect

const PARAM_PROGRESS: StringName = &"progress"
const PARAM_COLOR: StringName = &"ring_color"

## Сколько секунд кольцо расходится и гаснет.
@export var ring_sec: float = 0.45

## Сколько раз кольцо показывали (для проверочных сцен).
var plays: int = 0

var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_material = material as ShaderMaterial
	if _material == null:
		push_warning("FxRing %s: нет ShaderMaterial (fx_ring_material.tres)" % get_path())
	visible = false


func play(color: Color) -> void:
	if _material == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_material.set_shader_parameter(PARAM_COLOR, color)
	_set_progress(0.0)
	visible = true
	plays += 1
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, ring_sec)
	_tween.tween_callback(hide)


func _set_progress(value: float) -> void:
	_material.set_shader_parameter(PARAM_PROGRESS, value)
