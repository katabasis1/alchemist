## Flame — пламя горелки (S4.3, STATIONS §1.3): языки огня (шейдер flame.gdshader на ColorRect Fire), мягкий
## оранжевый ореол (Glow, fx_glow, сложение) на дне колбы и редкие искры вверх (Sparks). Сила 0…1: 0 — погасло,
## 1 — языки во всю высоту; ореол растёт и светлеет вместе с ней, искры летят с sparks_from.
## Владелец (станция) зажигает и гасит плавно: fade_to(сила, секунды) — время берёт из BurnerConfig
## (flame_grow_sec / flame_fade_sec); set_strength(сила) — сразу, без твина. Начало узла — верх фитиля.
## Сигналы: нет. Зависимости: дочерние Fire/Glow/Sparks (@export).
class_name Flame
extends Node2D

## Прямоугольник с материалом flame_material.tres (resource_local_to_scene): у каждой горелки своя сила.
@export var fire: ColorRect
## Ореол: цвет и непрозрачность при силе 1 — modulate узла в сцене.
@export var glow: Sprite2D
@export var sparks: CPUParticles2D
## Масштаб ореола при силе 1 и его доля при силе → 0.
@export var glow_scale: Vector2 = Vector2(5, 3.6)
@export_range(0.0, 1.0) var glow_min_scale: float = 0.5
## С какой силы летят искры.
@export_range(0.0, 1.0) var sparks_from: float = 0.3

var _material: ShaderMaterial
var _glow_alpha: float = 1.0
var _strength: float = 0.0
var _tween: Tween


func _ready() -> void:
	_material = fire.material as ShaderMaterial
	_glow_alpha = glow.modulate.a
	_apply(0.0)


## Сила сразу, без твина (останавливает начатый fade_to).
func set_strength(value: float) -> void:
	_stop_tween()
	_apply(value)


## Плавно к силе value за sec секунд (0 — погасить).
func fade_to(value: float, sec: float) -> void:
	_stop_tween()
	_tween = create_tween()
	_tween.tween_method(_apply, _strength, clampf(value, 0.0, 1.0), sec)


func strength() -> float:
	return _strength


func is_lit() -> bool:
	return _strength > 0.0


## Твин ещё идёт (огонь разгорается или гаснет).
func is_fading() -> bool:
	return _tween != null and _tween.is_running()


func _apply(value: float) -> void:
	_strength = clampf(value, 0.0, 1.0)
	var lit: bool = _strength > 0.0
	_material.set_shader_parameter(&"strength", _strength)
	fire.visible = lit
	glow.visible = lit
	glow.scale = glow_scale * lerpf(glow_min_scale, 1.0, _strength)
	glow.modulate.a = _glow_alpha * _strength
	sparks.emitting = lit and _strength >= sparks_from


func _stop_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
