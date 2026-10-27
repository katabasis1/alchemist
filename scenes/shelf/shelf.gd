## Shelf — полка ингредиентов (GDD §10): в ландшафте сетка слева, в портрете лента внизу с прокруткой.
## Ячейки (ShelfSlot) берутся из готовой сцены по списку ингредиентов: открытых у игрока или заданных в сцене.
## Ленту листают пальцем — по пустому месту (scroll_hit) и жестом вбок по ингредиенту; после броска она катится
## по инерции. Колесо мыши тоже листает. Ячейка у края ленты тает, а скрывшись, перестаёт ловить касания.
## Сигналы: ingredient_taken(item) — ингредиент взяли с полки, и станция его приняла.
## Методы: build(ids) — выложить ингредиенты; take_back(item) — станция вернула ингредиент; set_ribbon(on).
## Зависимости: DataCatalog, GameState (открытые ингредиенты; state_reset — выложить заново), EventBus (layout_changed), LayoutSwitcher (portrait),
##   ShelfSlot (slot_scene), HitArea (scroll_hit).
class_name Shelf
extends Node2D

signal ingredient_taken(item: IngredientItem)

const MSEC_PER_SEC: float = 1000.0

@export var catalog: DataCatalog
## Какие ингредиенты выложить. Пусто — открытые у игрока (GameState.unlocked_ingredients).
@export var ingredient_ids: Array[StringName] = []
@export var slot_scene: PackedScene
@export_group("Сетка (ландшафт)")
@export var grid_columns: int = 3
## Шаг ячеек. Начало полки — левый верхний угол сетки; ячейка стоит на нижней кромке своей клетки.
@export var grid_step: Vector2 = Vector2(196.0, 168.0)
@export_group("Лента (портрет)")
@export var ribbon_step: float = 212.0
## Видимая ширина ленты. Начало полки — левый край ленты, ячейки стоят на линии y = 0.
@export var ribbon_width: float = 1080.0
@export var ribbon_padding: float = 16.0
## Высота полосы над линией, за которую ленту можно тянуть по пустому месту.
@export var ribbon_height: float = 210.0
## Затухание инерции: чем больше, тем быстрее лента останавливается.
@export var scroll_friction: float = 5.0
## Медленнее этого (пикс./с) лента после броска не катится.
@export var min_fling_speed: float = 40.0
## Сглаживание оценки скорости пальца.
@export var velocity_sharpness: float = 18.0
@export var wheel_step: float = 140.0
@export_group("Узлы")
@export var slots_root: Node2D
@export var scroll_hit: HitArea

var slots: Array[ShelfSlot] = []
var ribbon: bool = false
var scroll: float = 0.0
var _scrolling: bool = false
var _scroll_from: float = 0.0
var _press_x: float = 0.0
var _last_x: float = 0.0
var _last_msec: int = 0
var _velocity: float = 0.0


func _ready() -> void:
	set_process(false)
	if scroll_hit != null:
		scroll_hit.pointer_down.connect(_begin_scroll)
		scroll_hit.pointer_moved.connect(_move_scroll)
		scroll_hit.pointer_up.connect(_on_scroll_hit_up)
		scroll_hit.pointer_cancelled.connect(_on_scroll_cancelled)
	EventBus.layout_changed.connect(set_ribbon)
	GameState.state_reset.connect(_on_state_reset)
	ribbon = LayoutSwitcher.portrait
	build(ingredient_ids if not ingredient_ids.is_empty() else GameState.unlocked_ingredients)
	set_ribbon(ribbon)


## Загрузка сохранения или новая игра: открытые ингредиенты могли смениться (полка без своего списка).
func _on_state_reset() -> void:
	if ingredient_ids.is_empty():
		build(GameState.unlocked_ingredients)
		set_ribbon(ribbon)


## Выложить ингредиенты по id (порядок сохраняется). Старые ячейки убираются.
func build(ids: Array[StringName]) -> void:
	if catalog == null or slot_scene == null:
		push_warning("Shelf %s: не заданы catalog или slot_scene" % get_path())
		return
	for old: ShelfSlot in slots:
		old.queue_free()
	slots.clear()
	for id: StringName in ids:
		var data: IngredientData = catalog.ingredient(id)
		if data == null:
			push_warning("Shelf: нет ингредиента %s в каталоге" % id)
			continue
		var slot: ShelfSlot = slot_scene.instantiate() as ShelfSlot
		slots_root.add_child(slot)
		slot.setup(data, _properties_of(data))
		slot.item_taken.connect(_on_item_taken)
		slot.gesture_passed.connect(_begin_scroll)
		slot.gesture_moved.connect(_move_scroll)
		slot.gesture_ended.connect(_end_scroll)
		slots.append(slot)
	_arrange()


## Раскладка: true — лента (портрет), false — сетка (ландшафт).
func set_ribbon(on: bool) -> void:
	ribbon = on
	_stop_scroll()
	if scroll_hit != null:
		scroll_hit.visible = on
		scroll_hit.set_enabled(on)
		scroll_hit.position = Vector2(0.0, -ribbon_height)
		scroll_hit.size = Vector2(ribbon_width, ribbon_height)
	for slot: ShelfSlot in slots:
		slot.set_pass_horizontal(on)
	_arrange()


## Станция вернула ингредиент: он летит в свою ячейку. Ячейки нет (ингредиент не на полке) — просто исчезает.
func take_back(item: IngredientItem) -> void:
	var slot: ShelfSlot = slot_for(item.data)
	if slot == null:
		item.queue_free()
		return
	slot.take_back(item)


func slot_for(data: IngredientData) -> ShelfSlot:
	for slot: ShelfSlot in slots:
		if slot.data == data or (data != null and slot.data != null and slot.data.id == data.id):
			return slot
	return null


## Пролистать ленту так, чтобы ячейка index была видна целиком (обучение, «новый ингредиент»).
func scroll_to(index: int) -> void:
	if not ribbon or index < 0 or index >= slots.size():
		return
	var left: float = ribbon_padding + index * ribbon_step
	var right: float = left + ribbon_step
	if left < scroll:
		_set_scroll(left - ribbon_padding)
	elif right > scroll + ribbon_width:
		_set_scroll(right + ribbon_padding - ribbon_width)


func max_scroll() -> float:
	return maxf(0.0, ribbon_padding * 2.0 + slots.size() * ribbon_step - ribbon_width)


func _process(delta: float) -> void:
	if _scrolling or absf(_velocity) < min_fling_speed:
		set_process(false)
		return
	var before: float = scroll
	_set_scroll(scroll + _velocity * delta)
	_velocity *= exp(-scroll_friction * delta)
	if is_equal_approx(before, scroll):
		_velocity = 0.0


func _input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not ribbon or mb == null or not mb.pressed or scroll_hit == null:
		return
	if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	var world: Vector2 = get_canvas_transform().affine_inverse() * mb.position
	if not scroll_hit.contains_world_point(world):
		return
	get_viewport().set_input_as_handled()
	var direction: float = -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
	_stop_scroll()
	_set_scroll(scroll + direction * wheel_step)


func _arrange() -> void:
	if ribbon:
		_layout_ribbon()
	else:
		for i: int in slots.size():
			var col: int = i % maxi(grid_columns, 1)
			var row: int = floori(float(i) / float(maxi(grid_columns, 1)))
			var slot: ShelfSlot = slots[i]
			slot.position = Vector2((col + 0.5) * grid_step.x, (row + 1) * grid_step.y)
			slot.modulate.a = 1.0
			slot.visible = true
	for slot: ShelfSlot in slots:
		slot.settle()


func _layout_ribbon() -> void:
	var half: float = ribbon_step * 0.5
	for i: int in slots.size():
		var slot: ShelfSlot = slots[i]
		var center_x: float = ribbon_padding + (i + 0.5) * ribbon_step - scroll
		slot.position = Vector2(center_x, 0.0)
		var edge: float = minf(center_x, ribbon_width - center_x)
		var alpha: float = clampf(edge / half, 0.0, 1.0)
		slot.modulate.a = alpha
		slot.visible = alpha > 0.0


func _set_scroll(value: float) -> void:
	scroll = clampf(value, 0.0, max_scroll())
	if ribbon:
		_layout_ribbon()


func _begin_scroll(world: Vector2) -> void:
	if not ribbon:
		return
	_scrolling = true
	_velocity = 0.0
	var x: float = to_local(world).x
	_press_x = x
	_last_x = x
	_scroll_from = scroll
	_last_msec = Time.get_ticks_msec()


func _move_scroll(world: Vector2) -> void:
	if not _scrolling:
		return
	var x: float = to_local(world).x
	var now: int = Time.get_ticks_msec()
	var dt: float = (now - _last_msec) / MSEC_PER_SEC
	if dt > 0.0:
		var instant: float = -(x - _last_x) / dt
		_velocity = lerpf(_velocity, instant, 1.0 - exp(-velocity_sharpness * dt))
	_last_x = x
	_last_msec = now
	_set_scroll(_scroll_from + _press_x - x)


func _end_scroll(world: Vector2) -> void:
	if not _scrolling:
		return
	_move_scroll(world)
	_scrolling = false
	set_process(absf(_velocity) >= min_fling_speed)


func _on_scroll_hit_up(world: Vector2, _inside: bool) -> void:
	_end_scroll(world)


func _on_scroll_cancelled() -> void:
	_scrolling = false
	_velocity = 0.0


func _stop_scroll() -> void:
	_scrolling = false
	_velocity = 0.0
	set_process(false)


func _properties_of(data: IngredientData) -> Array[PropertyData]:
	var ids: Array[StringName] = []
	ids.assign(data.properties.keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return data.properties[a] > data.properties[b])
	var result: Array[PropertyData] = []
	for id: StringName in ids:
		var property: PropertyData = catalog.property(id)
		if property != null:
			result.append(property)
	return result


func _on_item_taken(item: IngredientItem) -> void:
	ingredient_taken.emit(item)
