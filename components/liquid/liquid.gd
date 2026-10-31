## Liquid — жидкость в круглой колбе (S4.1): Sprite2D с текстурой колбы и шейдером liquid.gdshader.
## Стекло рисует тот же шейдер поверх жидкости, поэтому отдельный спрайт колбы не нужен.
## show_mixture(смесь, слив) — слои по плотности (LiquidLayers.view); stir() — смесь мутнеет и за settle_sec
## отстаивается обратно в слои; bump(px) — волна от толчка.
## Поверхность держит горизонт: при наклоне колбы шейдер получает −global_rotation. Сверху — раскачка
## (LiquidSlosh): дёрнули колбу вбок или повернули рывком — жидкость качнётся и успокоится.
## Для слива (S4.2): pour_angle() — наклон по уровню (LiquidPourTilt, D22), top_color() — цвет струи,
## surface_point() — середина поверхности в мире (искорка среза), texture_to_global() — точка холста колбы в мире
## (носик для струи), stir(сек) / settle_now() — муть на заданное время и мгновенное отстаивание (тап).
## Сигналы: нет. Зависимости: DataCatalog, EconomyConfig, LiquidSlosh, LiquidPourTilt (@export), LiquidLayers,
##   ShaderMaterial с liquid.gdshader (liquid_material.tres, local to scene: у каждой колбы свои слои).
class_name Liquid
extends Sprite2D

@export var catalog: DataCatalog
@export var economy: EconomyConfig
@export var slosh: LiquidSlosh
## Наклон при сливе для этой формы колбы (data/liquid/pour_tilt_round.tres).
@export var pour_tilt: LiquidPourTilt
## Сколько долей смеси наполняют колбу до верха (уровень 1). Три ингредиента — почти полная колба.
@export var capacity: float = 5.0
## За сколько секунд муть после stir() отстаивается в слои.
@export var settle_sec: float = 1.2

var _material: ShaderMaterial
var _settle_tween: Tween
## Слои, показанные последним show_mixture: верх каждого в долях полной колбы и цвет.
var _tops: PackedFloat32Array = PackedFloat32Array()
var _colors: PackedColorArray = PackedColorArray()
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
	assert(pour_tilt != null, "Liquid: нужен LiquidPourTilt (data/liquid/pour_tilt_round.tres)")
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
	_tops = tops
	_colors = colors.slice(0, count)
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


## Взболтать: смесь мутнеет и за seconds (0 — settle_sec) отстаивается в слои. Отстойник передаёт
## EconomyConfig.settle_time, Приёмник со струёй — значение по умолчанию.
func stir(seconds: float = 0.0) -> void:
	if _settle_tween:
		_settle_tween.kill()
	_settle_tween = create_tween()
	_settle_tween.tween_method(_set_turbidity, 1.0, 0.0, seconds if seconds > 0.0 else settle_sec) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Отстоять сразу: муть пропадает, слои видны (тап по колбе во время отстаивания).
func settle_now() -> void:
	if _settle_tween:
		_settle_tween.kill()
	_set_turbidity(0.0)


## Наклон колбы для слива по показанным слоям, радианы (D22): кромка горла чуть под поверхностью верхнего слоя.
func pour_angle() -> float:
	return pour_tilt.angle(_tops, _shape_float(&"column_height"), _shape_point(&"bulb_center"),
			_shape_float(&"bulb_radius"))


## Цвет верхнего слоя — им окрашена струя. Пустая колба — прозрачный.
func top_color() -> Color:
	return _colors[_colors.size() - 1] if not _colors.is_empty() else Color(0.0, 0.0, 0.0, 0.0)


## Середина поверхности жидкости в мире (горизонт без раскачки) — туда искорка чистого среза.
func surface_point() -> Vector2:
	var surface: float = _tops[_tops.size() - 1] * _shape_float(&"column_height") if not _tops.is_empty() else 0.0
	var up: Vector2 = Vector2.UP.rotated(-global_rotation)
	return texture_to_global(_shape_point(&"bulb_center") + up * (surface - _shape_float(&"bulb_radius")))


## Точка холста текстуры колбы (px) в мировых координатах: носик для струи, кромка, центр шара.
func texture_to_global(point: Vector2) -> Vector2:
	var local: Vector2 = point + offset
	if centered:
		local -= texture.get_size() * 0.5
	return to_global(local)


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


## Форма колбы из материала (px холста): bulb_radius, column_height…
func _shape_float(parameter: StringName) -> float:
	return float(_material.get_shader_parameter(parameter))


func _shape_point(parameter: StringName) -> Vector2:
	return _material.get_shader_parameter(parameter) as Vector2


func _set_turbidity(value: float) -> void:
	_material.set_shader_parameter(&"turbidity", value)
