## DropTarget — зона, куда можно положить предмет (Draggable): станция, клиент, корзина.
## Прямоугольник Control задаётся в редакторе; касания он не перехватывает (mouse_filter = IGNORE).
## Пока предмет в руке, допустимые цели подсвечиваются, цель под пальцем — ярче.
## Приём в два шага: drop_attempted(draggable) — владелец может отказать, вызвав reject(reason)
## прямо в обработчике (ступка в состоянии Ground, монет не хватает); затем received или rejected.
## Сигналы: drop_attempted(draggable), received(draggable), rejected(draggable, reason),
##   highlight_changed(level) — DropTarget.Highlight: NONE / AVAILABLE / HOVERED.
## Зависимости: EventBus (drag_started, drag_ended), Draggable (kind).
class_name DropTarget
extends Control

signal drop_attempted(draggable: Draggable)
signal received(draggable: Draggable)
signal rejected(draggable: Draggable, reason: StringName)
signal highlight_changed(level: int)

enum Highlight { NONE, AVAILABLE, HOVERED }

const GROUP: StringName = &"drop_targets"
const REASON_KIND: StringName = &"kind"
const REASON_DISABLED: StringName = &"disabled"
const REASON_BUSY: StringName = &"busy"

## Какие предметы принимает (Draggable.kind). Пусто — любые.
@export var accepted_kinds: Array[StringName] = []
## Выключенная цель не подсвечивается и отказывает с причиной &"disabled".
@export var enabled: bool = true
## При перекрытии побеждает больший приоритет, при равном — узел ниже в дереве (он рисуется сверху).
@export var priority: int = 0
## Куда встаёт принятый предмет. Пусто — центр прямоугольника.
@export var snap_point: Node2D
## Подсветка (спрайт, полигон). Скрыта, пока предмет не взят.
@export var highlight: CanvasItem
## Прозрачность подсветки: цель доступна / предмет над ней.
@export var available_alpha: float = 0.45
@export var hovered_alpha: float = 1.0

var state: Highlight = Highlight.NONE

var _veto: StringName = &""
var _carried: Draggable


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	EventBus.drag_started.connect(_on_drag_started)
	EventBus.drag_ended.connect(_on_drag_ended)
	_apply_highlight(Highlight.NONE)


## Лучшая цель под точкой мира: сначала те, что принимают этот вид предмета, затем приоритет, затем порядок в дереве.
## Возвращает и отказывающую цель — чтобы она могла объяснить отказ (отскок, мигание).
static func find_at(tree: SceneTree, world_pos: Vector2, draggable: Draggable) -> DropTarget:
	var best: DropTarget = null
	for node: Node in tree.get_nodes_in_group(GROUP):
		var t: DropTarget = node as DropTarget
		if t == null or not t.contains_world_point(world_pos):
			continue
		if best == null or t._beats(best, draggable):
			best = t
	return best


func accepts_kind(draggable: Draggable) -> bool:
	return accepted_kinds.is_empty() or accepted_kinds.has(draggable.kind)


func can_accept(draggable: Draggable) -> bool:
	return enabled and is_visible_in_tree() and accepts_kind(draggable)


func contains_world_point(world_pos: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	var local: Vector2 = get_global_transform().affine_inverse() * world_pos
	return Rect2(Vector2.ZERO, size).has_point(local)


## Попробовать принять предмет. true — принят (received), false — отказ (rejected с причиной).
func try_receive(draggable: Draggable) -> bool:
	if not enabled:
		rejected.emit(draggable, REASON_DISABLED)
		return false
	if not accepts_kind(draggable):
		rejected.emit(draggable, REASON_KIND)
		return false
	_veto = &""
	drop_attempted.emit(draggable)
	var reason: StringName = _veto
	_veto = &""
	if reason != &"":
		rejected.emit(draggable, reason)
		return false
	received.emit(draggable)
	return true


## Отказать в приёме. Вызывать только внутри обработчика drop_attempted.
func reject(reason: StringName = REASON_BUSY) -> void:
	_veto = reason


## Куда поставить принятый предмет (мир).
func snap_position() -> Vector2:
	if snap_point != null:
		return snap_point.global_position
	return get_global_transform() * (size * 0.5)


## Предмет над целью или ушёл с неё (вызывает Draggable во время переноса).
func set_hovered(hovered: bool) -> void:
	if _carried == null:
		return
	if hovered and can_accept(_carried):
		_apply_highlight(Highlight.HOVERED)
	elif can_accept(_carried):
		_apply_highlight(Highlight.AVAILABLE)


func _beats(other: DropTarget, draggable: Draggable) -> bool:
	var mine: bool = can_accept(draggable)
	var theirs: bool = other.can_accept(draggable)
	if mine != theirs:
		return mine
	if priority != other.priority:
		return priority > other.priority
	return is_greater_than(other)


func _on_drag_started(draggable: Node) -> void:
	_carried = draggable as Draggable
	if _carried != null and can_accept(_carried):
		_apply_highlight(Highlight.AVAILABLE)
	else:
		_apply_highlight(Highlight.NONE)


func _on_drag_ended(draggable: Node) -> void:
	# Снять выбор с одного предмета может новый выбор другого: тогда шина сначала объявит новый предмет,
	# а уже потом «отпустит» старый — подсветку для нового гасить нельзя.
	if _carried != null and draggable != _carried:
		return
	_carried = null
	_apply_highlight(Highlight.NONE)


func _apply_highlight(value: Highlight) -> void:
	if highlight != null:
		highlight.visible = value != Highlight.NONE
		highlight.modulate.a = hovered_alpha if value == Highlight.HOVERED else available_alpha
	if state != value:
		state = value
		highlight_changed.emit(value)
