## GrindGesture — жест помола над чашей: путь пальца превращается в «круги» (GDD §3.3, docs/gdd/STATIONS.md §1.1).
## Считается длина пути, а не угол: засчитываются и круги, и свайпы. Один круг = circle_length_px пути.
## Жест начинается, когда палец сдвинулся дальше start_distance от точки нажатия (короткий тап — ещё не жест).
## Конец жеста: палец отпущен; ушёл дальше leave_factor · zone_radius от центра; нажатие прервано (пауза, реклама,
## поворот экрана — владелец зовёт cancel()). Защита: не больше max_circles_per_sec, скачок дальше max_step_px
## (телепорт указателя) не засчитывается. Альтернатива для доступности — tap_turn(): тап = 1/taps_per_circle круга,
## не чаще max_taps_per_sec (защита от автокликера и дрожи пальца).
## Сигналы: started — жест начат; turned(circles) — засчитана часть круга; quarter_passed — пройдена очередная
##   четверть круга (для хруста и крошек, S2.3); ended(reason) — &"released", &"left", &"cancelled", &"tap".
## Зависимости: HitArea (источник касаний, @export), center — Node2D в центре чаши (@export).
class_name GrindGesture
extends Node

signal started
signal turned(circles: float)
signal quarter_passed
signal ended(reason: StringName)

const REASON_RELEASED: StringName = &"released"
const REASON_LEFT: StringName = &"left"
const REASON_CANCELLED: StringName = &"cancelled"
const REASON_TAP: StringName = &"tap"
const QUARTERS_PER_CIRCLE: float = 4.0
const MSEC_PER_SEC: float = 1000.0

@export var hit_area: HitArea
## Центр чаши (мир): от него меряется уход пальца.
@export var center: Node2D
## Выключенный жест не начинается; идущий — обрывается.
@export var enabled: bool = true:
	set = set_enabled
## Столько пикселей пути пальца (мир, 1920×1080) — один полный круг.
@export var circle_length_px: float = 520.0
## Палец сдвинулся дальше этого от точки нажатия — это уже жест, а не тап (как HitArea.tap_max_distance).
@export var start_distance: float = 24.0
## Радиус чаши (мир) и множитель: дальше leave_factor · zone_radius от центра — жест окончен (STATIONS §1.1).
@export var zone_radius: float = 185.0
@export var leave_factor: float = 1.5
## Потолок скорости помола жестом, кругов в секунду.
@export var max_circles_per_sec: float = 3.0
## Отрезок пути длиннее этого за одно событие — скачок указателя, не засчитывается.
@export var max_step_px: float = 160.0
## Тап = 1 / taps_per_circle круга. Владелец берёт число из EconomyConfig.taps_per_circle.
@export var taps_per_circle: int = 4
## Лимит засчитанных тапов в секунду (STATIONS §1.1, «шквал тапов»).
@export var max_taps_per_sec: float = 12.0

## Жест идёт: палец давит и уже сдвинулся дальше start_distance.
var is_grinding: bool = false

var _pressed: bool = false
var _down_world: Vector2 = Vector2.ZERO
var _last_world: Vector2 = Vector2.ZERO
var _last_msec: int = 0
var _last_tap_msec: int = -1
## Путь с прошлой засчитанной четверти круга, в кругах.
var _quarter_progress: float = 0.0


func _ready() -> void:
	hit_area.pointer_down.connect(_on_pointer_down)
	hit_area.pointer_moved.connect(_on_pointer_moved)
	hit_area.pointer_up.connect(_on_pointer_up)
	hit_area.pointer_cancelled.connect(_on_pointer_cancelled)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		cancel()


## Оборвать жест (пауза, реклама, поворот экрана, станцию разгрузили). Засчитанное остаётся.
func cancel() -> void:
	_pressed = false
	if is_grinding:
		_finish(REASON_CANCELLED)


## Тап как ¼ круга (доступность). false — тап не засчитан: жест уже идёт, выключено или слишком часто.
func tap_turn() -> bool:
	if not enabled or is_grinding or taps_per_circle <= 0:
		return false
	var now: int = Time.get_ticks_msec()
	if _last_tap_msec >= 0 and float(now - _last_tap_msec) < MSEC_PER_SEC / max_taps_per_sec:
		return false
	_last_tap_msec = now
	started.emit()
	_count(1.0 / taps_per_circle)
	ended.emit(REASON_TAP)
	return true


## Насколько далеко точка мира от центра чаши, в радиусах чаши.
func distance_in_radii(world_pos: Vector2) -> float:
	if center == null or zone_radius <= 0.0:
		return 0.0
	return world_pos.distance_to(center.global_position) / zone_radius


func _on_pointer_down(world: Vector2) -> void:
	if not enabled:
		return
	_pressed = true
	_down_world = world
	_last_world = world
	_last_msec = Time.get_ticks_msec()


func _on_pointer_moved(world: Vector2) -> void:
	if not _pressed:
		return
	if distance_in_radii(world) > leave_factor:
		_pressed = false
		if is_grinding:
			_finish(REASON_LEFT)
		return
	if not is_grinding:
		if world.distance_to(_down_world) <= start_distance:
			return
		is_grinding = true
		_quarter_progress = 0.0
		started.emit()
	var now: int = Time.get_ticks_msec()
	var step: float = world.distance_to(_last_world)
	var dt: float = float(now - _last_msec) / MSEC_PER_SEC
	_last_world = world
	_last_msec = now
	if step > max_step_px or circle_length_px <= 0.0:
		return
	var circles: float = minf(step / circle_length_px, max_circles_per_sec * dt)
	if circles > 0.0:
		_count(circles)


func _on_pointer_up(_world: Vector2, _inside: bool) -> void:
	_pressed = false
	if is_grinding:
		_finish(REASON_RELEASED)


func _on_pointer_cancelled() -> void:
	_pressed = false
	if is_grinding:
		_finish(REASON_CANCELLED)


func _count(circles: float) -> void:
	turned.emit(circles)
	_quarter_progress += circles
	var quarter: float = 1.0 / QUARTERS_PER_CIRCLE
	while _quarter_progress >= quarter:
		_quarter_progress -= quarter
		quarter_passed.emit()


func _finish(reason: StringName) -> void:
	is_grinding = false
	ended.emit(reason)
