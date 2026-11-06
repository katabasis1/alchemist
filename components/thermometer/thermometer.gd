## Thermometer — термометр Горелки (S4.3): красный столбик температуры и цветные зоны с иконками за стеклом.
## Зоны задаёт владелец (станция берёт их из AlchemyRules.heat_zones): с какой T зона начинается, её цвет и иконка;
## до первой зоны — кремовый фон. Столбик рисует шейдер thermometer.gdshader на текстуре prop_thermometer.png,
## иконки — готовые узлы-слоты Icons/* на планке справа от трубки (лишние скрыты). На пределе и пока горит Жизнь
## термометр дрожит: set_tremble(сила 0…1+), 0 — замер. Цифр нет (ART_STYLE: читается цветом и иконкой).
## Начало узла — низ подставки; геометрия шкалы — в материале (px холста текстуры).
## Сигналы: нет. Зависимости: дочерние Body/Tube/Icons/Cap (@export).
class_name Thermometer
extends Node2D

## Качается вместе со всем термометром (точка поворота — низ подставки).
@export var body: Node2D
## Спрайт с текстурой термометра и материалом thermometer_material.tres (resource_local_to_scene).
@export var tube: Sprite2D
## Слоты иконок зон снизу вверх; зон больше, чем слотов, — лишние без иконки.
@export var icons: Array[Sprite2D] = []
## Верхний колпачок: отсюда свистит облачко на пределе (станция берёт точку через cap_point()).
@export var cap: Marker2D
## Шкала: температура у шарика и у верха трубки. Станция ставит EconomyConfig.room_temp и max_temp.
@export var temp_min: float = 20.0
@export var temp_max: float = 100.0
## Где на планке иконки зон (x, px холста текстуры) и их размер, px холста.
@export var icon_x_px: float = 89.0
@export var icon_size_px: float = 24.0
## Иконка красится цветом зоны, осветлённым к белому на эту долю (чтобы читалась на тёмной планке).
@export_range(0.0, 1.0) var icon_lighten: float = 0.3
## Дрожь: наклон, градусы при силе 1; частота, Гц; сдвиг вбок, px.
@export var tremble_deg: float = 2.5
@export var tremble_hz: float = 11.0
@export var tremble_px: float = 1.2
## Сдвиг вбок идёт с другой частотой (доля от tremble_hz), чтобы дрожь не была ровным маятником.
@export var tremble_side_ratio: float = 1.7

const MAX_ZONES: int = 8

var _material: ShaderMaterial
var _temp: float = 0.0
var _tremble: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_material = tube.material as ShaderMaterial
	_temp = temp_min
	set_zones(PackedFloat32Array(), PackedColorArray(), [])
	set_temperature(temp_min)
	set_process(false)


## Зоны снизу вверх: температуры начала (по возрастанию), цвета, иконки (null — без иконки).
func set_zones(starts: PackedFloat32Array, colors: PackedColorArray, zone_icons: Array[Texture2D]) -> void:
	var count: int = mini(starts.size(), MAX_ZONES)
	var from_slots: PackedFloat32Array = PackedFloat32Array()
	var color_slots: PackedVector4Array = PackedVector4Array()
	from_slots.resize(MAX_ZONES)
	color_slots.resize(MAX_ZONES)
	for i: int in count:
		from_slots[i] = fraction_of(starts[i])
		color_slots[i] = Vector4(colors[i].r, colors[i].g, colors[i].b, colors[i].a)
	_material.set_shader_parameter(&"zone_count", count)
	_material.set_shader_parameter(&"zone_from", from_slots)
	_material.set_shader_parameter(&"zone_colors", color_slots)
	for i: int in icons.size():
		var icon: Sprite2D = icons[i]
		icon.visible = i < count and i < zone_icons.size() and zone_icons[i] != null
		if not icon.visible:
			continue
		var top: float = from_slots[i + 1] if i + 1 < count else 1.0
		icon.texture = zone_icons[i]
		icon.position = _canvas_to_body(Vector2(icon_x_px, _scale_y((from_slots[i] + top) * 0.5)))
		icon.scale = Vector2.ONE * icon_size_px / float(icon.texture.get_width())
		icon.modulate = colors[i].lerp(Color.WHITE, icon_lighten)


## Температура столбика (за пределами шкалы — упирается в край).
func set_temperature(temp: float) -> void:
	_temp = temp
	_material.set_shader_parameter(&"value", fraction_of(temp))


func temperature() -> float:
	return _temp


## Дрожь: 0 — спокоен, 1 — как на пределе (сила задаёт размах).
func set_tremble(strength: float) -> void:
	_tremble = maxf(strength, 0.0)
	set_process(_tremble > 0.0)
	if _tremble == 0.0:
		body.rotation = 0.0
		body.position = Vector2.ZERO


func trembling() -> float:
	return _tremble


## Точка верхнего колпачка в глобальных координатах.
func cap_point() -> Vector2:
	return cap.global_position


## Доля шкалы 0…1 для температуры.
func fraction_of(temp: float) -> float:
	if is_equal_approx(temp_max, temp_min):
		return 0.0
	return clampf((temp - temp_min) / (temp_max - temp_min), 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var wave: float = sin(_time * TAU * tremble_hz)
	body.rotation = deg_to_rad(tremble_deg) * _tremble * wave
	body.position = Vector2(tremble_px * _tremble * sin(_time * TAU * tremble_hz * tremble_side_ratio), 0.0)


func _scale_y(fraction: float) -> float:
	var bottom: float = _material.get_shader_parameter(&"scale_bottom")
	var top: float = _material.get_shader_parameter(&"scale_top")
	return lerpf(bottom, top, fraction)


## px холста текстуры → координаты Body (текстура по центру спрайта Tube).
func _canvas_to_body(px: Vector2) -> Vector2:
	var size: Vector2 = tube.texture.get_size()
	return tube.position + (px - size * 0.5) * tube.scale
