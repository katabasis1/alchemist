## FxRing — волна света по краю чаши (scenes/fx/fx_ring.tscn): «идеально» у ступки, позже — звёзды и открытия.
## Волну рисует шейдер fx_ring.gdshader во весь прямоугольник, поэтому её пропорции задаёт размер узла.
## Спутники (extras) — другие узлы с шейдером, у которых есть те же progress и ring_color (лучи fx_rays.tscn):
## показываются, идут и гаснут вместе с волной, каждый — со своим цветом из своего материала, если follow_color = false.
## Сигналы: нет.
## Зависимости: свой материал fx_ring_material.tres (resource_local_to_scene); extras — CanvasItem с ShaderMaterial (@export).
class_name FxRing
extends ColorRect

const PARAM_PROGRESS: StringName = &"progress"
const PARAM_COLOR: StringName = &"ring_color"

## Сколько секунд волна расходится и гаснет (лучи живут столько же: их огибающая — в шейдере).
@export var ring_sec: float = 0.9
## Спутники волны: лучи и другие эффекты с параметром progress.
@export var extras: Array[CanvasItem] = []
## Красить ли спутники цветом волны (иначе у них свой цвет из материала).
@export var follow_color: bool = false

## Сколько раз волну показывали (для проверочных сцен).
var plays: int = 0

var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	_material = material as ShaderMaterial
	if _material == null:
		push_warning("FxRing %s: нет ShaderMaterial (fx_ring_material.tres)" % get_path())
	visible = false
	for extra: CanvasItem in extras:
		if extra != null:
			extra.visible = false


func play(color: Color) -> void:
	if _material == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_material.set_shader_parameter(PARAM_COLOR, color)
	for extra: CanvasItem in extras:
		var mat: ShaderMaterial = _extra_material(extra)
		if mat != null and follow_color:
			mat.set_shader_parameter(PARAM_COLOR, color)
		if extra != null:
			extra.visible = true
	_set_progress(0.0)
	visible = true
	plays += 1
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, ring_sec)
	_tween.tween_callback(_finish)


func _finish() -> void:
	hide()
	for extra: CanvasItem in extras:
		if extra != null:
			extra.visible = false


func _set_progress(value: float) -> void:
	_material.set_shader_parameter(PARAM_PROGRESS, value)
	for extra: CanvasItem in extras:
		var mat: ShaderMaterial = _extra_material(extra)
		if mat != null:
			mat.set_shader_parameter(PARAM_PROGRESS, value)


func _extra_material(extra: CanvasItem) -> ShaderMaterial:
	return extra.material as ShaderMaterial if extra != null else null
