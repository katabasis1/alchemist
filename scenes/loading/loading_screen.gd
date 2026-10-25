## LoadingScreen — экран загрузки при старте игры: название, качающаяся колба, полоса прогресса, «Загрузка…».
## Main вызывает advance() после каждого шага запуска, затем await finish(): полоса доходит до конца,
## экран тает, ввод в игру открывается. Пока экран виден, корневой Control перехватывает нажатия.
## Тексты — ключи локализации: Label переводит их сам, язык Main выбирает сразу после Platform.initialize.
## process_mode ALWAYS: потеря фокуса ставит дерево на паузу, а экран должен доиграть анимацию.
## Сигналы: finished — экран скрыт.
## Зависимости: узлы сцены через @export (root, bar, flask). Цвета и шрифты — тема ui/theme/main_theme.tres.
class_name LoadingScreen
extends CanvasLayer

signal finished

@export var root: Control
@export var bar: ProgressBar
@export var flask: Control
## Сколько шагов запуска отметит Main: платформа, сохранение, настройки.
@export var steps: int = 3
## Время, за которое полоса доезжает до нового значения, секунды. Стартовое значение.
@export var bar_tween_sec: float = 0.2
## Колба качается, пока идёт загрузка (знак «игра не зависла»): угол, градусы. Стартовое значение.
@export var sway_deg: float = 6.0
## Время качания от края до края, секунды. Стартовое значение.
@export var sway_half_period_sec: float = 0.6
## Исчезновение экрана, секунды. Стартовое значение.
@export var fade_sec: float = 0.35

var _done: int = 0
var _sway: Tween
var _bar_tween: Tween


func _ready() -> void:
	visible = true
	root.modulate.a = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.max_value = float(steps)
	bar.value = 0.0
	_start_sway()


## Шаг запуска завершён: полоса плавно продвигается.
func advance() -> void:
	_done = mini(_done + 1, steps)
	if _bar_tween != null:
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(bar, "value", float(_done), bar_tween_sec)


## Полоса до конца, затем экран тает. Возвращается, когда экран скрыт.
func finish() -> void:
	if _bar_tween != null:
		_bar_tween.kill()
	var tween: Tween = create_tween()
	tween.tween_property(bar, "value", bar.max_value, bar_tween_sec)
	tween.tween_property(root, "modulate:a", 0.0, fade_sec)
	await tween.finished
	if _sway != null:
		_sway.kill()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	finished.emit()


func _start_sway() -> void:
	var angle: float = deg_to_rad(sway_deg)
	flask.rotation = -angle
	_sway = create_tween().set_loops()
	_sway.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway.tween_property(flask, "rotation", angle, sway_half_period_sec)
	_sway.tween_property(flask, "rotation", -angle, sway_half_period_sec)
