## LoadingScreen — экран загрузки поверх игры: название и «Открываем лавку…», пока Main запускает
## сервисы (платформа, сохранение, язык). Фон того же цвета, что boot splash, — переход незаметен.
## Тексты — ключи локализации: Label переводит их сам и меняет язык без кода, когда Main его выберет.
## Пока экран виден, он перехватывает ввод. hide_screen() плавно убирает его и возвращает управление.
## Сигналы: closed — экран убран.
## Зависимости: content (@export) — корневой Control, его прозрачность анимируется;
## status (@export) — «дышащая» надпись о загрузке.
class_name LoadingScreen
extends CanvasLayer

signal closed

@export var content: Control
@export var status: Label
## Длительность исчезновения, секунды.
@export var fade_sec: float = 0.35
## «Дыхание» надписи: полный цикл, секунды, и самая бледная прозрачность.
@export var breath_sec: float = 1.2
@export var breath_min_alpha: float = 0.45

var _breath: Tween


func _ready() -> void:
	if content == null or status == null:
		push_warning("LoadingScreen %s: не заданы content или status" % get_path())
		return
	visible = true
	content.visible = true
	_start_breath()


## Плавно убрать экран. Повторный вызов ничего не делает.
func hide_screen() -> void:
	if not visible or content == null:
		return
	if _breath != null:
		_breath.kill()
	var fade: Tween = create_tween()
	fade.tween_property(content, "modulate:a", 0.0, fade_sec)
	await fade.finished
	content.visible = false
	visible = false
	closed.emit()


func _start_breath() -> void:
	var half: float = breath_sec / 2.0
	_breath = create_tween().set_loops()
	_breath.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath.tween_property(status, "modulate:a", breath_min_alpha, half)
	_breath.tween_property(status, "modulate:a", 1.0, half)
