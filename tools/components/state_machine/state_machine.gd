## StateMachine — машина состояний станции или клиента (docs/gdd/STATIONS.md). Дети-узлы State — состояния.
## Переход разрешён, если он есть в State.next_states (или список пуст); иначе transition_refused.
## Переход, запрошенный из обработчика entered/exited, выполняется сразу после текущего (без вложенности).
## Пауза дерева (реклама) замораживает таймеры состояний: process_mode наследуется.
## Сигналы: state_changed(from, to), transition_refused(from, to).
## Зависимости: дочерние State.
class_name StateMachine
extends Node

signal state_changed(from: StringName, to: StringName)
signal transition_refused(from: StringName, to: StringName)

## Стартовое состояние. Пусто — первый дочерний State.
@export var initial_state: State
## Запустить машину сама (отложенно, после _ready владельца — он успеет подписаться на entered).
@export var autostart: bool = true
## Печатать переходы в Output (отладка).
@export var log_transitions: bool = false

var current: State
var previous_name: StringName = &""
## Сколько секунд машина в текущем состоянии.
var time_in_state: float = 0.0

var _states: Dictionary = {}
var _busy: bool = false
var _queued: StringName = &""


func _ready() -> void:
	for child: Node in get_children():
		var s: State = child as State
		if s != null:
			_states[StringName(s.name)] = s
	if _states.is_empty():
		push_warning("StateMachine %s: нет дочерних State" % get_path())
	set_process(false)
	if autostart:
		start.call_deferred()


## Войти в стартовое состояние (повторный вызов — перезапуск машины).
func start(state_name: StringName = &"") -> void:
	var first: State = _states.get(state_name) as State if state_name != &"" else initial_state
	if first == null and not _states.is_empty():
		first = _states.values()[0] as State
	if first == null:
		return
	if current != null:
		current.exited.emit(first.name)
	var from: StringName = current_name()
	_enter(first, from)


## Перейти в состояние. force — в обход next_states (сброс, загрузка сохранения).
func transition_to(state_name: StringName, force: bool = false) -> bool:
	var next: State = _states.get(state_name) as State
	if next == null:
		push_warning("StateMachine %s: нет состояния %s" % [get_path(), state_name])
		return false
	if current != null and not force and not current.can_go_to(state_name):
		transition_refused.emit(current_name(), state_name)
		if log_transitions:
			print("[SM] %s: %s → %s запрещён" % [name, current_name(), state_name])
		return false
	if _busy:
		_queued = state_name
		return true
	_busy = true
	var from: StringName = current_name()
	if current != null:
		current.exited.emit(state_name)
	_enter(next, from)
	_busy = false
	if _queued != &"":
		var queued: StringName = _queued
		_queued = &""
		transition_to(queued, true)
	return true


func current_name() -> StringName:
	return StringName(current.name) if current != null else &""


func is_in(state_name: StringName) -> bool:
	return current_name() == state_name


func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)


func _enter(next: State, from: StringName) -> void:
	previous_name = from
	current = next
	time_in_state = 0.0
	set_process(true)
	if log_transitions:
		print("[SM] %s: %s → %s" % [name, from, next.name])
	next.entered.emit(from)
	state_changed.emit(from, StringName(next.name))


func _process(delta: float) -> void:
	if current == null:
		set_process(false)
		return
	time_in_state += delta
	current.updated.emit(delta)
	if current.timeout_sec > 0.0 and time_in_state >= current.timeout_sec and current.timeout_to != &"":
		var target: StringName = current.timeout_to
		time_in_state = 0.0
		transition_to(target, true)
