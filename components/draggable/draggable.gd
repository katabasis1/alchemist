## Draggable — перенос сущности пальцем/мышью и запасной способ «тап по предмету → тап по цели» (GDD §10).
## Взял: предмет приподнимается, появляется тень, цели подсвечиваются (EventBus.drag_started).
## Отпустил над целью: DropTarget решает, принять ли; принят — встаёт на цель (или как задано on_accept),
## нет — возвращается домой (drop_rejected, затем returned; дрожь и звук вешаются на эти сигналы в сцене).
## Лента с прокруткой (pass_horizontal): нажатие, ушедшее сначала вбок, предмет не берёт — press_passed,
##   дальше жестом распоряжается владелец (слушает HitArea этого предмета).
## Сигналы: drag_started, drag_moved(world_pos), dropped(target), drop_rejected(target), landed, returned,
##   selected_changed(selected), press_passed(world_pos). target в drop_rejected == null — отпустили мимо всех целей.
## Методы для владельца: select/deselect, cancel, place_at (мгновенно), send_to (плавно, станция вернула предмет),
##   drop_on (бросить на цель без пальца: обучение, проверки), is_busy.
## Зависимости: HitArea (ввод), DropTarget (цели), EventBus (drag_started, drag_ended).
class_name Draggable
extends Node

signal drag_started
signal drag_moved(world_pos: Vector2)
signal dropped(target: DropTarget)
signal drop_rejected(target: DropTarget)
signal landed
signal returned
signal selected_changed(selected: bool)
## Нажатие ушло вбок при pass_horizontal: предмет не взят, жест отдан владельцу (прокрутка ленты).
signal press_passed(world_pos: Vector2)

## Что делать после приёма: встать на цель / вернуться домой (полка-источник) / остаться где отпустили (владелец сам решит).
enum AcceptMode { SNAP, RETURN, STAY }

@export var hit_area: HitArea
## Что двигаем — корень сущности.
@export var body: Node2D
## Что приподнимаем — визуальная часть (не тот узел, которым владеет JuicePunch/SquashStretch). Можно пусто.
@export var lift_node: Node2D
## Тень под предметом, видна только в руке. Можно пусто.
@export var shadow: CanvasItem
## Вид предмета для DropTarget.accepted_kinds: &"ingredient", &"flask", &"potion"…
@export var kind: StringName = &"item"
## Данные предмета (IngredientData и т. п.) — для логики целей.
@export var payload: Resource
@export var enabled: bool = true:
	set = set_enabled
@export var tap_to_select: bool = true
@export var on_accept: AcceptMode = AcceptMode.SNAP
## Сколько пикселей мира провести пальцем, чтобы нажатие стало переносом. Стартовое значение — GDD §12, строка «Ввод».
@export var drag_threshold: float = 12.0
## Первое движение вбок не берёт предмет, а отдаёт жест (press_passed). Включает полка-лента, когда её можно листать.
@export var pass_horizontal: bool = false
## «Вбок» — когда сдвиг по x больше сдвига по y, умноженного на это число.
@export var pass_ratio: float = 1.0
## Как плотно предмет следует за пальцем (1/с); 0 — без сглаживания.
@export var follow_sharpness: float = 28.0
@export var lift_offset: Vector2 = Vector2(0.0, -18.0)
@export var lift_scale: float = 1.08
@export var lift_sec: float = 0.1
@export var shadow_alpha: float = 0.35
@export var return_sec: float = 0.3
@export var snap_sec: float = 0.16
## Полёт к цели в режиме «тап — тап».
@export var fly_sec: float = 0.32
## z_index предмета в руке — поверх остальных.
@export var carry_z_index: int = 50

var is_dragging: bool = false
var is_selected: bool = false
## Куда предмет возвращается при отказе. Запоминается, когда предмет берут в состоянии покоя
## (поэтому раскладка и спавнер могут свободно ставить сущность), и после приёма в режиме SNAP.
var home_position: Vector2 = Vector2.ZERO

var _pressing: bool = false
## В этом нажатии уже был перенос: короткий бросок не должен засчитаться ещё и как тап (выбор).
var _dragged_this_press: bool = false
var _press_world: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO
var _goal: Vector2 = Vector2.ZERO
var _hover_target: DropTarget
var _base_z: int = 0
var _lift_base_position: Vector2 = Vector2.ZERO
var _lift_base_scale: Vector2 = Vector2.ONE
var _move_tween: Tween
var _lift_tween: Tween


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	if hit_area == null or body == null:
		push_warning("Draggable %s: не заданы hit_area или body" % get_path())
		return
	home_position = body.global_position
	_base_z = body.z_index
	if lift_node != null:
		_lift_base_position = lift_node.position
		_lift_base_scale = lift_node.scale
	if shadow != null:
		shadow.visible = false
		shadow.modulate.a = 0.0
	hit_area.pointer_down.connect(_on_pointer_down)
	hit_area.pointer_moved.connect(_on_pointer_moved)
	hit_area.pointer_up.connect(_on_pointer_up)
	hit_area.pointer_cancelled.connect(cancel)
	hit_area.tapped.connect(_on_tapped)
	EventBus.drag_started.connect(_on_any_drag_started)


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and is_node_ready():
		cancel()


## Бросить перенос или выбор: предмет возвращается домой без сигнала отказа.
func cancel() -> void:
	_pressing = false
	if is_dragging:
		is_dragging = false
		set_process(false)
		_set_hover_target(null)
		EventBus.drag_ended.emit(self)
		_move_to(home_position, return_sec, false)
	elif is_selected:
		deselect()


func select() -> void:
	if enabled and not is_selected and not is_dragging:
		_capture_home()
		_set_selected(true)


func deselect() -> void:
	if is_selected:
		_set_selected(false)
		_set_lift(false)
		body.z_index = _base_z


## Поставить предмет в новую «домашнюю» точку мгновенно (раскладка, появление на полке).
func place_at(world_pos: Vector2) -> void:
	_kill(_move_tween)
	home_position = world_pos
	body.global_position = world_pos


## Бросить предмет на цель без пальца (сценарий обучения, проверочные сцены) — как будто его отпустили над целью.
func drop_on(target: DropTarget) -> void:
	_pressing = false
	if is_dragging:
		is_dragging = false
		set_process(false)
		_set_hover_target(null)
	elif is_selected:
		_set_selected(false, false)
	else:
		_capture_home()
	body.z_index = carry_z_index
	_resolve_drop(target, fly_sec)


## Предмет занят: в руке, выбран или летит. Раскладка (прокрутка ленты) двигает только свободные предметы.
func is_busy() -> bool:
	return is_dragging or is_selected or _is_moving()


## Плавно отправить предмет в новую «домашнюю» точку: станция вернула предмет на полку, полка перестроилась.
## Перенос или выбор, если были, отменяются. По прибытии — landed.
func send_to(world_pos: Vector2) -> void:
	if is_dragging or is_selected:
		cancel()
	home_position = world_pos
	_move_to(world_pos, fly_sec, true)


func _process(delta: float) -> void:
	if not is_dragging:
		set_process(false)
		return
	var k: float = 1.0 if follow_sharpness <= 0.0 else 1.0 - exp(-follow_sharpness * delta)
	body.global_position = body.global_position.lerp(_goal, k)


func _input(event: InputEvent) -> void:
	# Слушаем только в режиме «выбран тапом»: следующий тап по цели отправляет предмет туда.
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var world: Vector2 = body.get_canvas_transform().affine_inverse() * mb.position
	if hit_area.contains_world_point(world):
		return  # тап по самому предмету снимет выбор через tapped
	var target: DropTarget = DropTarget.find_at(get_tree(), world, self)
	if target == null:
		deselect()  # тап мимо: выбор снят, касание идёт дальше — можно сразу взять другой предмет
		return
	get_viewport().set_input_as_handled()
	_set_selected(false, false)
	_resolve_drop(target, fly_sec)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		cancel()


func _on_pointer_down(world: Vector2) -> void:
	if not enabled:
		return
	_capture_home()
	_pressing = true
	_dragged_this_press = false
	_press_world = world
	_grab_offset = body.global_position - world


func _on_pointer_moved(world: Vector2) -> void:
	if not _pressing:
		return
	if not is_dragging:
		var shift: Vector2 = world - _press_world
		if shift.length() < drag_threshold:
			return
		if pass_horizontal and absf(shift.x) > absf(shift.y) * pass_ratio:
			_pressing = false
			press_passed.emit(world)
			return
		_begin_drag()
	_goal = world + _grab_offset
	_update_hover(world)
	drag_moved.emit(world)


func _on_pointer_up(world: Vector2, _inside: bool) -> void:
	_pressing = false
	if not is_dragging:
		return
	is_dragging = false
	set_process(false)
	_set_hover_target(null)
	_resolve_drop(DropTarget.find_at(get_tree(), world, self), snap_sec)


func _on_tapped(_world: Vector2) -> void:
	if not enabled or not tap_to_select or is_dragging or _dragged_this_press:
		return
	if is_selected:
		deselect()
	else:
		select()


func _on_any_drag_started(draggable: Node) -> void:
	if draggable != self and is_selected:
		deselect()


func _begin_drag() -> void:
	if is_selected:
		_set_selected(false, false)
	_kill(_move_tween)
	is_dragging = true
	_dragged_this_press = true
	body.z_index = carry_z_index
	_set_lift(true)
	_goal = body.global_position
	set_process(true)
	EventBus.drag_started.emit(self)
	drag_started.emit()


func _resolve_drop(target: DropTarget, travel_sec: float) -> void:
	var accepted: bool = target != null and target.try_receive(self)
	EventBus.drag_ended.emit(self)
	if not accepted:
		drop_rejected.emit(target)
		_move_to(home_position, return_sec, false)
		return
	dropped.emit(target)
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return  # цель «съела» предмет
	match on_accept:
		AcceptMode.SNAP:
			home_position = target.snap_position()
			_move_to(home_position, travel_sec, true)
		AcceptMode.RETURN:
			_move_to(home_position, return_sec, true)
		AcceptMode.STAY:
			_finish_carry()
			landed.emit()


func _move_to(world_pos: Vector2, sec: float, accepted: bool) -> void:
	_kill(_move_tween)
	_move_tween = create_tween()
	if accepted:
		_move_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_move_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(body, ^"global_position", world_pos, sec)
	_move_tween.tween_callback(_on_arrived.bind(accepted))


func _on_arrived(accepted: bool) -> void:
	_finish_carry()
	if accepted:
		landed.emit()
	else:
		returned.emit()


func _finish_carry() -> void:
	_set_lift(false)
	body.z_index = _base_z


func _set_selected(value: bool, emit_bus: bool = true) -> void:
	is_selected = value
	set_process_input(value)
	if value:
		body.z_index = carry_z_index
		_set_lift(true)
		EventBus.drag_started.emit(self)
	elif emit_bus:
		EventBus.drag_ended.emit(self)
	selected_changed.emit(value)


func _set_lift(on: bool) -> void:
	_kill(_lift_tween)
	_lift_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if lift_node != null:
		var to_pos: Vector2 = _lift_base_position + lift_offset if on else _lift_base_position
		var to_scale: Vector2 = _lift_base_scale * lift_scale if on else _lift_base_scale
		_lift_tween.tween_property(lift_node, ^"position", to_pos, lift_sec)
		_lift_tween.tween_property(lift_node, ^"scale", to_scale, lift_sec)
	if shadow != null:
		if on:
			shadow.visible = true
		_lift_tween.tween_property(shadow, ^"modulate:a", shadow_alpha if on else 0.0, lift_sec)
	if lift_node == null and shadow == null:
		_lift_tween.kill()


func _update_hover(world: Vector2) -> void:
	_set_hover_target(DropTarget.find_at(get_tree(), world, self))


func _set_hover_target(target: DropTarget) -> void:
	if target == _hover_target:
		return
	if _hover_target != null and is_instance_valid(_hover_target):
		_hover_target.set_hovered(false)
	_hover_target = target
	if target != null:
		target.set_hovered(true)


## Предмет в покое (не в руке, не выбран, не летит) — его текущая точка и есть «дом».
func _capture_home() -> void:
	if not is_dragging and not is_selected and not _is_moving():
		home_position = body.global_position


func _is_moving() -> bool:
	return _move_tween != null and _move_tween.is_valid() and _move_tween.is_running()


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
