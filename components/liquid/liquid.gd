## Liquid — жидкость в круглой колбе (S4.1): Sprite2D с текстурой колбы и шейдером liquid.gdshader.
## Стекло рисует тот же шейдер поверх жидкости, поэтому отдельный спрайт колбы не нужен.
## show_mixture(смесь, слив) — слои по плотности (LiquidLayers.view); stir() — смесь мутнеет и за settle_sec
## отстаивается обратно в слои; bump(px) — волна от толчка.
## Поверхность держит горизонт: при наклоне колбы шейдер получает −global_rotation. Сверху — раскачка
## (LiquidSlosh): дёрнули колбу вбок или повернули рывком — жидкость качнётся и успокоится.
## Сигналы: нет. Зависимости: DataCatalog, EconomyConfig, LiquidSlosh (@export), LiquidLayers, ShaderMaterial
##   с liquid.gdshader (liquid_material.tres, local to scene: у каждой колбы свои слои).
class_name Liquid
extends Sprite2D

@export var catalog: DataCatalog
@export var economy: EconomyConfig
@export var slosh: LiquidSlosh
## Сколько долей смеси наполняют колбу до верха (уровень 1). Три ингредиента — почти полная колба.
@export var capacity: float = 5.0
## За сколько секунд муть после stir() отстаивается в слои.
@export var settle_sec: float = 1.2

var _material: ShaderMaterial
var _settle_tween: Tween
## (угол поверхности в мире, скорость угла) — состояние для LiquidSlosh.step.
var _tilt: Vector2 = Vector2.ZERO
var _last_rotation: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _last_velocity: Vector2 = Vector2.ZERO
var _bump_px: float = 0.0
var _bump_phase: float = 0.0


func _ready() -> void:
	_material = material as ShaderMaterial
	assert(_material != null, "Liquid: нужен ShaderMaterial с liquid.gdshader")
	assert(slosh != null, "Liquid: нужен LiquidSlosh (data/liquid/liquid_slosh.tres)")
	assert(capacity > 0.0, "Liquid: capacity должна быть больше нуля")
	_last_rotation = global_rotation
	_last_position = global_position


## Слои смеси после слива poured (доля столба сверху, как в AlchemyRules.pour_top).
func show_mixture(mixture: Dictionary, poured: float = 0.0) -> void:
	var view: Dictionary = LiquidLayers.view(mixture, poured, capacity, catalog, economy)
	var colors: PackedColorArray = view[LiquidLayers.KEY_COLORS]
	var patterns: PackedInt32Array = view[LiquidLayers.KEY_PATTERNS]
	var tops: PackedFloat32Array = view[LiquidLayers.KEY_TOPS]
	var count: int = tops.size()
	var color_slots: PackedVector4Array = PackedVector4Array()
	var pattern_slots: PackedInt32Array = PackedInt32Array()
	var top_slots: PackedFloat32Array = PackedFloat32Array()
	for i: int in LiquidLayers.MAX_LAYERS:
		var color: Color = colors[i] if i < count else Color(0.0, 0.0, 0.0, 0.0)
		color_slots.append(Vector4(color.r, color.g, color.b, color.a))
		pattern_slots.append(patterns[i] if i < count else 0)
		top_slots.append(tops[i] if i < count else 0.0)
	_material.set_shader_parameter(&"layer_count", count)
	_material.set_shader_parameter(&"layer_colors", color_slots)
	_material.set_shader_parameter(&"layer_patterns", pattern_slots)
	_material.set_shader_parameter(&"layer_tops", top_slots)
	_material.set_shader_parameter(&"mixed_color", view[LiquidLayers.KEY_MIXED])


## Взболтать: смесь мутнеет и за settle_sec отстаивается в слои (отстаивание, Приёмник со струёй).
func stir() -> void:
	if _settle_tween:
		_settle_tween.kill()
	_settle_tween = create_tween()
	_settle_tween.tween_method(_set_turbidity, 1.0, 0.0, settle_sec).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)


## Волна от толчка: размах в пикселях текстуры, складывается с ещё не затухшей.
func bump(strength_px: float) -> void:
	_bump_px += strength_px


## Наклон поверхности в мире сейчас, радианы (0 — горизонт). Для стенда и звука плеска.
func surface_tilt() -> float:
	return _tilt.x


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var velocity: Vector2 = (global_position - _last_position) / delta
	var accel: Vector2 = (velocity - _last_velocity) / delta
	var turn: float = angle_difference(_last_rotation, global_rotation)
	_tilt = slosh.step(_tilt, slosh.target(accel.x), turn, delta)
	_bump_px = slosh.fade(_bump_px, delta)
	_bump_phase = fmod(_bump_phase + slosh.bump_frequency * delta, TAU)
	_last_position = global_position
	_last_velocity = velocity
	_last_rotation = global_rotation
	_material.set_shader_parameter(&"surface_angle", -global_rotation + _tilt.x)
	_material.set_shader_parameter(&"slosh_px", _bump_px)
	_material.set_shader_parameter(&"slosh_phase", _bump_phase)


func _set_turbidity(value: float) -> void:
	_material.set_shader_parameter(&"turbidity", value)
