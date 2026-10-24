## HitArea — область касания сущности: нажатие, перемещение, отпускание, тап, долгое нажатие, наведение.
## Это Control внутри Node2D-сущности: GUI Godot сам выбирает верхнюю область под пальцем и держит
## указатель за ней, пока кнопка нажата (палец может уйти за край — события всё равно придут сюда).
## Позиции в сигналах — в координатах мира (канваса), их понимают Draggable и DropTarget.
## Размер — прямоугольник Control (в редакторе) не меньше 96×96 (GDD §10); radius > 0 — круглая зона.
## Сигналы: pointer_down(world_pos), pointer_moved(world_pos), pointer_up(world_pos, inside), pointer_cancelled,
##   tapped(world_pos), long_pressed(world_pos), hover_changed(hovered).
## Зависимости: нет. Слушают: Draggable, Hoverable, Tooltip, логика станций.
class_name HitArea
extends Control

signal pointer_down(world_pos: Vector2)
signal pointer_moved(world_pos: Vector2)
signal pointer_up(world_pos: Vector2, inside: bool)
## Нажатие прервано (пауза, отключение, cancel()): отпускания не было — бросок не засчитывать.
signal pointer_cancelled
signal tapped(world_pos: Vector2)
signal long_pressed(world_pos: Vector2)
signal hover_changed(hovered: bool)

const MSEC_PER_SEC: float = 1000.0

## Выключенная область не реагирует и пропускает касания к тому, что под ней.
@export var enabled: bool = true:
	set = set_enabled
## > 0 — круглая зона этого радиуса вокруг центра прямоугольника; 0 — весь прямоугольник.
@export var radius: float = 0.0
## Тап: палец сдвинулся не дальше этого (px мира). Стартовое значение, проверка — GDD §12 «Ввод».
@export var tap_max_distance: float = 24.0
## Тап: от нажатия до отпускания не дольше этого (с).
@export var tap_max_sec: float = 0.35
## Долгое нажатие на месте (подсказка на телефоне), с.
@export var long_press_sec: float = 0.45

## Последний ввод был с сенсорного экрана: наведение мышью тогда не показываем.
static var touch_mode: bool = false

var is_pressed: bool = false
var is_hovered: bool = false

var _down_world: Vector2 = Vector2.ZERO
var _down_msec: int = 0
var _moved_far: bool = false
var _long_fired: bool = false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_process(false)
	set_enabled(enabled)


func set_enabled(value: bool) -> void:
	enabled = value
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled:
		cancel()


## Сбросить нажатие без сигналов tapped/long_pressed (пауза, выключение, станция занята).
func cancel() -> void:
	if is_pressed:
		is_pressed = false
		set_process(false)
		pointer_cancelled.emit()
	_set_hovered(false)


## Точка мира внутри зоны (для режима «тап по предмету → тап по цели»).
func contains_world_point(world_pos: Vector2) -> bool:
	if not enabled or not is_visible_in_tree():
		return false
	return _has_point(get_global_transform().affine_inverse() * world_pos)


func _has_point(point: Vector2) -> bool:
	if radius <= 0.0:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return point.distance_to(size * 0.5) <= radius


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		touch_mode = true
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		touch_mode = false


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press(get_global_transform() * mb.position)
		elif is_pressed:
			_release(get_global_transform() * mb.position, _has_point(mb.position))
		accept_event()
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and is_pressed:
		var world: Vector2 = get_global_transform() * mm.position
		if world.distance_to(_down_world) > tap_max_distance:
			_moved_far = true
		pointer_moved.emit(world)
		accept_event()


func _process(_delta: float) -> void:
	if not is_pressed or _moved_far or _long_fired:
		set_process(false)
		return
	if _elapsed_sec() >= long_press_sec:
		_long_fired = true
		set_process(false)
		long_pressed.emit(_down_world)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		cancel()


func _press(world: Vector2) -> void:
	is_pressed = true
	_down_world = world
	_down_msec = Time.get_ticks_msec()
	_moved_far = false
	_long_fired = false
	set_process(true)
	pointer_down.emit(world)


func _release(world: Vector2, inside: bool) -> void:
	is_pressed = false
	set_process(false)
	var is_tap: bool = inside and not _moved_far and not _long_fired and _elapsed_sec() <= tap_max_sec
	pointer_up.emit(world, inside)
	if is_tap:
		tapped.emit(world)
	if touch_mode:
		_set_hovered(false)


func _elapsed_sec() -> float:
	return float(Time.get_ticks_msec() - _down_msec) / MSEC_PER_SEC


func _on_mouse_entered() -> void:
	if not touch_mode:
		_set_hovered(true)


func _on_mouse_exited() -> void:
	_set_hovered(false)


func _set_hovered(value: bool) -> void:
	if is_hovered == value:
		return
	is_hovered = value
	hover_changed.emit(value)
