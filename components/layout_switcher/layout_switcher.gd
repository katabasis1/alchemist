## LayoutSwitcher — ландшафт (ПК) или портрет (телефон): выбирает раскладку по пропорциям окна
## и применяет её к своей сцене (GDD §10: портрет — сверху клиент, в середине станции, внизу полка).
## Ведущий (drive_window = true, один на игру — в Main): следит за размером окна, ставит базовое
## разрешение окна (1920×1080 или 1080×1920) и объявляет смену через EventBus.layout_changed.
## Остальные (в экранах) слушают шину, а при появлении берут текущую раскладку из LayoutSwitcher.portrait.
## Применение: показать узлы своей раскладки, спрятать чужие; поставить movers[i] в точку маркера
## landscape_marks[i] / portrait_marks[i] (позиция и, если copy_scale, масштаб маркера).
## HUD на якорях Control подстраивается сам — сюда его не добавлять.
## Порог с гистерезисом: окно почти квадратное — раскладка не «дребезжит» при ресайзе.
## Сигналы: layout_applied(portrait) — после применения (логика может пересчитать своё).
## Зависимости: EventBus (layout_changed), окно (Window.size_changed, content_scale_size).
class_name LayoutSwitcher
extends Node

signal layout_applied(portrait: bool)

## Текущая раскладка игры (её выставляет ведущий; сцены, загруженные позже, читают её в _ready).
static var portrait: bool = false

## Этот узел управляет окном. Ровно один на игру (Main); в экранах — false.
@export var drive_window: bool = false
@export var landscape_size: Vector2i = Vector2i(1920, 1080)
@export var portrait_size: Vector2i = Vector2i(1080, 1920)
## Ширина/высота окна ниже этого — портрет. Стартовое значение — GDD §12, строка «Смена раскладки».
@export var portrait_below: float = 0.9
## Ширина/высота выше этого — ландшафт. Между порогами раскладка не меняется.
@export var landscape_above: float = 1.1
@export var landscape_only: Array[CanvasItem] = []
@export var portrait_only: Array[CanvasItem] = []
## Что переставлять. Индексы совпадают с landscape_marks и portrait_marks.
@export var movers: Array[Node2D] = []
@export var landscape_marks: Array[Node2D] = []
@export var portrait_marks: Array[Node2D] = []
## Брать у маркера и масштаб (уменьшить клиента в портрете). Масштабом mover тогда владеет раскладка.
@export var copy_scale: bool = true

var _applied: int = -1  # -1 — ещё не применяли, 0 — ландшафт, 1 — портрет


func _ready() -> void:
	if movers.size() != landscape_marks.size() or movers.size() != portrait_marks.size():
		push_warning("LayoutSwitcher %s: movers и маркеры разной длины — лишние пропущу" % get_path())
	if drive_window:
		get_window().size_changed.connect(_on_window_resized)
		_on_window_resized()
	else:
		EventBus.layout_changed.connect(apply)
		apply(portrait)


## Применить раскладку к своей сцене. Повторный вызов с той же раскладкой ничего не делает.
func apply(to_portrait: bool) -> void:
	var code: int = 1 if to_portrait else 0
	if code == _applied:
		return
	_applied = code
	for item: CanvasItem in landscape_only:
		if item != null:
			item.visible = not to_portrait
	for item: CanvasItem in portrait_only:
		if item != null:
			item.visible = to_portrait
	var marks: Array[Node2D] = portrait_marks if to_portrait else landscape_marks
	var count: int = mini(movers.size(), marks.size())
	for i: int in count:
		var mover: Node2D = movers[i]
		var mark: Node2D = marks[i]
		if mover == null or mark == null:
			continue
		mover.global_position = mark.global_position
		if copy_scale:
			mover.global_scale = mark.global_scale
	layout_applied.emit(to_portrait)


## Какая раскладка нужна окну такого размера, если сейчас current. Чистая функция — её проверяет демо-сцена.
func wants_portrait(window_size: Vector2i, current: bool) -> bool:
	if window_size.y <= 0:
		return current
	var aspect: float = float(window_size.x) / float(window_size.y)
	if aspect < portrait_below:
		return true
	if aspect > landscape_above:
		return false
	return current


func _on_window_resized() -> void:
	var window: Window = get_window()
	var first: bool = _applied < 0
	# Первый расчёт: почти квадратное окно на старте считаем ландшафтом.
	var next: bool = wants_portrait(window.size, false if first else portrait)
	if not first and next == portrait:
		return
	portrait = next
	window.content_scale_size = portrait_size if next else landscape_size
	apply(next)
	EventBus.layout_changed.emit(next)
