## Tooltip — подсказка-пергамент над сущностью: название ингредиента, свойство, что делает станция.
## ПК: появляется после задержки наведения. Телефон: по долгому нажатию, исчезает при отпускании.
## Прячется при нажатии и в начале любого переноса (EventBus.drag_started) — бросок важнее подсказки.
## Текст — ключ локализации: Label переводит его сам и обновляет при смене языка.
## top_level: не наследует масштаб «приподнятого» предмета; ставится над HitArea (или над anchor)
## и прижимается к видимой области камеры, а если сверху места нет — встаёт под предмет.
## Узлы Tooltip и Label — mouse_filter IGNORE: подсказка не перехватывает наведение (иначе мигала бы).
## Сигналы: нет (видимость — встроенные visibility_changed).
## Зависимости: HitArea (наведение, долгое нажатие), EventBus (drag_started), Label (@export label).
class_name Tooltip
extends PanelContainer

@export var hit_area: HitArea
@export var label: Label
## Точка, над которой встаёт подсказка. Пусто — середина верхнего края HitArea.
@export var anchor: Node2D
## Ключ строки в localization/strings.csv.
@export var text_key: StringName = &""
## Задержка наведения мышью, секунды. Стартовое значение — GDD §12, строка «Подсказка».
@export var show_delay_sec: float = 0.4
## Зазор между предметом и подсказкой, пиксели мира.
@export var gap: float = 14.0
## Минимальный отступ от края экрана, пиксели мира.
@export var screen_margin: float = 12.0
@export var fade_sec: float = 0.12
@export var enabled: bool = true

var _wait_left: float = 0.0
var _tween: Tween


func _ready() -> void:
	visible = false
	set_process(false)
	if hit_area == null or label == null:
		push_warning("Tooltip %s: не заданы hit_area или label" % get_path())
		return
	hit_area.hover_changed.connect(_on_hover_changed)
	hit_area.long_pressed.connect(_on_long_pressed)
	hit_area.pointer_down.connect(_on_pointer_down)
	hit_area.pointer_up.connect(_on_pointer_up)
	hit_area.pointer_cancelled.connect(hide_tip)
	EventBus.drag_started.connect(_on_any_drag_started)
	# Размер контейнера пересчитывается отложенно — после смены текста встаём на место ещё раз.
	minimum_size_changed.connect(_on_minimum_size_changed)


## Сменить текст (например, после того как игрок узнал свойство ингредиента).
func set_text_key(key: StringName) -> void:
	text_key = key
	if visible:
		_apply_text()
		_place()


func show_tip() -> void:
	set_process(false)
	if not enabled or text_key == &"":
		return
	_apply_text()
	if not visible:
		modulate.a = 0.0
	visible = true
	_place()
	_fade_to(1.0)


func hide_tip() -> void:
	set_process(false)
	if visible:
		_fade_to(0.0)


func _process(delta: float) -> void:
	_wait_left -= delta
	if _wait_left <= 0.0:
		show_tip()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		set_process(false)
		visible = false


func _on_hover_changed(hovered: bool) -> void:
	if hovered and enabled:
		_wait_left = show_delay_sec
		set_process(true)
	else:
		hide_tip()


func _on_long_pressed(_world: Vector2) -> void:
	if HitArea.touch_mode:
		show_tip()


func _on_pointer_down(_world: Vector2) -> void:
	hide_tip()


func _on_pointer_up(_world: Vector2, _inside: bool) -> void:
	if HitArea.touch_mode:
		hide_tip()


func _on_any_drag_started(_draggable: Node) -> void:
	hide_tip()


func _on_minimum_size_changed() -> void:
	if visible:
		reset_size()
		_place()


func _apply_text() -> void:
	label.text = String(text_key)
	reset_size()


## Над предметом по центру; не вылезать за видимую область камеры.
func _place() -> void:
	var top_center: Vector2
	var bottom_y: float
	if anchor != null:
		top_center = anchor.global_position
		bottom_y = top_center.y
	else:
		var xf: Transform2D = hit_area.get_global_transform()
		top_center = xf * Vector2(hit_area.size.x * 0.5, 0.0)
		bottom_y = (xf * Vector2(0.0, hit_area.size.y)).y
	var view: Rect2 = get_canvas_transform().affine_inverse() * get_viewport_rect()
	var pos: Vector2 = Vector2(top_center.x - size.x * 0.5, top_center.y - gap - size.y)
	if pos.y < view.position.y + screen_margin:
		pos.y = bottom_y + gap
	pos.x = clampf(pos.x, view.position.x + screen_margin, maxf(view.position.x + screen_margin, view.end.x - screen_margin - size.x))
	global_position = pos


func _fade_to(alpha: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", alpha, fade_sec)
	if alpha <= 0.0:
		_tween.tween_callback(hide)
