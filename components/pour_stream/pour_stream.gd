## PourStream — струя из колбы в Приёмник (колба-отстойник S4.2): Line2D с шейдером pour_stream.gdshader.
## Форма — квадратичная кривая от носика до поверхности в Приёмнике: сначала вбок, потом почти отвесно
## (референсы docs/art/refs/ref_settler_*.jpg). Ширина — width_full × поток (0…1) и сужение книзу (width_curve).
## pour(цвет, поток) — струя вырастает из носика и течёт; stop(сек) — за stop_sec истончается до нуля (хвост струи,
## AlchemyRules.pour_tail_after) и отрывается от носика, остаток падает за fall_sec. aim(от, до) — концы в мире,
## звать каждый кадр, пока колба наклоняется. Касания не ловит; только вид, расчёт слива — у станции.
## Сигналы: нет. Зависимости: ShaderMaterial с pour_stream.gdshader (pour_stream_material.tres, local to scene).
class_name PourStream
extends Line2D

## Ширина струи при полном потоке, пиксели (у носика; книзу — по width_curve).
@export var width_full: float = 26.0
## Точек на кривой: больше — глаже дуга.
@export var segments: int = 18
## Изгиб: где контрольная точка кривой между концами (x — доля пути вбок, y — доля пути вниз).
@export var bend: Vector2 = Vector2(0.85, 0.12)
## За сколько секунд струя дорастает от носика до Приёмника.
@export var grow_sec: float = 0.12
## За сколько секунд оторвавшийся остаток долетает до Приёмника.
@export var fall_sec: float = 0.22
## За сколько секунд ширина догоняет новый поток.
@export var flow_sec: float = 0.08
## Откуда свет (ART_STYLE: ключевой — сверху слева): блик рисуется на стороне струи к свету.
@export var light_dir: Vector2 = Vector2(-1.0, -1.0)

var _material: ShaderMaterial
var _flow: float = 0.0
var _flowing: bool = false
var _flow_tween: Tween
var _ends_tween: Tween


func _ready() -> void:
	_material = material as ShaderMaterial
	assert(_material != null, "PourStream: нужен ShaderMaterial с pour_stream.gdshader")
	visible = false
	width = 0.0


## Точки кривой от from до to (count ≥ 2): квадратичная кривая Безье с контрольной точкой по bend_at.
static func arc_points(from: Vector2, to: Vector2, bend_at: Vector2, count: int) -> PackedVector2Array:
	var control: Vector2 = Vector2(lerpf(from.x, to.x, bend_at.x), lerpf(from.y, to.y, bend_at.y))
	var result: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(count, 2) - 1
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		result.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return result


## Концы струи в мировых координатах: носик колбы и точка на поверхности в Приёмнике.
func aim(from_global: Vector2, to_global: Vector2) -> void:
	var local_points: PackedVector2Array = arc_points(to_local(from_global), to_local(to_global), bend, segments)
	points = local_points
	var total: float = 0.0
	for i: int in range(1, local_points.size()):
		total += local_points[i].distance_to(local_points[i - 1])
	_material.set_shader_parameter(&"length_px", maxf(total, 1.0))
	var mid: int = local_points.size() / 2
	var along: Vector2 = (local_points[mid] - local_points[mid - 1]).normalized()
	# Line2D кладёт край UV.y = 0 на сторону along.orthogonal() (Vector2(y, −x)).
	_material.set_shader_parameter(&"light_side", 0.0 if along.orthogonal().dot(light_dir) >= 0.0 else 1.0)


## Течь цветом color с потоком flow (0…1 от полной скорости). Повторный вызов только меняет цвет и поток.
func pour(color: Color, flow: float) -> void:
	_material.set_shader_parameter(&"stream_color", color)
	if not _flowing:
		_flowing = true
		visible = true
		_tween_ends(0.0, 0.0, 1.0, grow_sec)
	_tween_flow(clampf(flow, 0.0, 1.0), flow_sec)


## Перестать течь: за stop_sec поток спадает до нуля, остаток отрывается от носика и падает.
func stop(stop_sec: float) -> void:
	if not _flowing:
		return
	_flowing = false
	_tween_flow(0.0, maxf(stop_sec, 0.0))
	_tween_ends(0.0, 1.0, 1.0, maxf(stop_sec, 0.0) + fall_sec, true)


## Убрать струю сразу (пауза, сброс станции).
func clear() -> void:
	_flowing = false
	if _flow_tween != null and _flow_tween.is_valid():
		_flow_tween.kill()
	if _ends_tween != null and _ends_tween.is_valid():
		_ends_tween.kill()
	_set_flow(0.0)
	visible = false


func is_flowing() -> bool:
	return _flowing


## Текущий поток 0…1 (ширина струи без сужения).
func flow() -> float:
	return _flow


func _tween_flow(target: float, sec: float) -> void:
	if _flow_tween != null and _flow_tween.is_valid():
		_flow_tween.kill()
	if sec <= 0.0:
		_set_flow(target)
		return
	_flow_tween = create_tween()
	_flow_tween.tween_method(_set_flow, _flow, target, sec)


## head: from_head → to_head, reach: 0 → to_reach (при отрыве reach уже 1 и не меняется).
func _tween_ends(from_head: float, to_head: float, to_reach: float, sec: float, hide_after: bool = false) -> void:
	if _ends_tween != null and _ends_tween.is_valid():
		_ends_tween.kill()
	_material.set_shader_parameter(&"head", from_head)
	_ends_tween = create_tween()
	if hide_after:
		_ends_tween.tween_method(_set_head, from_head, to_head, sec).set_ease(Tween.EASE_IN) \
				.set_trans(Tween.TRANS_QUAD)
		_ends_tween.tween_callback(hide)
	else:
		_ends_tween.tween_method(_set_reach, 0.0, to_reach, sec).set_ease(Tween.EASE_IN) \
				.set_trans(Tween.TRANS_QUAD)


func _set_flow(value: float) -> void:
	_flow = value
	width = width_full * value


func _set_head(value: float) -> void:
	_material.set_shader_parameter(&"head", value)


func _set_reach(value: float) -> void:
	_material.set_shader_parameter(&"reach", value)
