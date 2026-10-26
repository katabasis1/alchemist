## Mortar — станция «ступка» (GDD §3.3, docs/gdd/STATIONS.md §1.1). На S2.1 — приём ингредиентов, вместимость,
## цена при броске, возврат на полку (тап по ингредиенту, корзина). Жест помола и шкала появятся на S2.2.
## Ингредиенты лежат в чаше: слой contents стоит между чашей и её передним краем (BowlFront).
## Полная ступка не подсвечивается как цель; бросок в неё — отскок, и огоньки слотов мигают.
## Монет не хватает — отскок и drop_refused(&"coins"): HUD вздрогнет счётчиком (S2.4).
## Сигналы: item_released(item) — ингредиент отдан обратно (полка ловит его в take_back);
##   contents_changed(ids) — что лежит в чаше; drop_refused(reason) — бросок отклонён (&"full", &"coins", &"kind").
## Зависимости: DropTarget, StateMachine (Empty / Loaded), StationTrash, JuicePunch, SfxComponent, IngredientItem,
##   EconomyConfig (вместимость), ToolData (улучшение «третий слот»), GameState (монеты, покупки).
class_name Mortar
extends Node2D

signal item_released(item: IngredientItem)
signal contents_changed(ids: Array[StringName])
signal drop_refused(reason: StringName)

const STATE_EMPTY: StringName = &"Empty"
const STATE_LOADED: StringName = &"Loaded"
const REASON_FULL: StringName = &"full"
const REASON_COINS: StringName = &"coins"
const REASON_KIND: StringName = &"kind"

@export var economy: EconomyConfig
## Купленное улучшение даёт economy.mortar_slots_upgraded мест вместо economy.mortar_slots.
@export var third_slot_upgrade: ToolData
## Сила «подпрыгивания» чаши при приёме ингредиента.
@export var receive_punch: float = 0.6
@export_group("Огоньки слотов")
@export var pip_empty: Color = Color(0.25, 0.16, 0.1, 0.55)
@export var pip_full: Color = Color(1.0, 0.82, 0.35, 1.0)
@export var pip_alert: Color = Color(1.0, 0.3, 0.2, 1.0)
@export var pip_spacing: float = 30.0
@export var pip_blink_sec: float = 0.1
@export var pip_blinks: int = 3
@export_group("Узлы")
@export var drop_target: DropTarget
@export var state_machine: StateMachine
## Слой ингредиентов в чаше (между Bowl и BowlFront).
@export var contents: Node2D
## Места ингредиентов при вместимости 2 и 3.
@export var slots_two: Array[Marker2D] = []
@export var slots_three: Array[Marker2D] = []
## Огоньки под чашей: сколько мест и сколько занято. pip_fills[i] — заливка огонька pips[i].
@export var pips: Array[Node2D] = []
@export var pip_fills: Array[Polygon2D] = []
@export var trash: StationTrash
@export var punch: JuicePunch
@export var sfx_accept: SfxComponent
@export var sfx_reject: SfxComponent

var items: Array[IngredientItem] = []
var capacity: int = 2
var _blink: Tween


func _ready() -> void:
	drop_target.drop_attempted.connect(_on_drop_attempted)
	drop_target.received.connect(_on_received)
	drop_target.rejected.connect(_on_rejected)
	trash.pressed.connect(empty_to_shelf)
	refresh_capacity()


## Пересчитать вместимость (после покупки улучшения).
func refresh_capacity() -> void:
	capacity = slots_two.size()
	if economy != null:
		var upgraded: bool = third_slot_upgrade != null and GameState.purchases.has(third_slot_upgrade.id)
		capacity = economy.mortar_slots_upgraded if upgraded else economy.mortar_slots
	capacity = clampi(capacity, 1, _marks_for(capacity).size())
	_repack()
	_update_view()


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for item: IngredientItem in items:
		result.append(item.data.id)
	return result


func is_full() -> bool:
	return items.size() >= capacity


## Отдать ингредиент обратно на полку. refund — вернуть его цену (из Loaded — да, молотый — нет).
func release(item: IngredientItem, refund: bool) -> void:
	var index: int = items.find(item)
	if index < 0:
		return
	items.remove_at(index)
	var tap: Callable = _on_item_tapped.bind(item)
	if item.hit_area.tapped.is_connected(tap):
		item.hit_area.tapped.disconnect(tap)
	if refund and item.data.cost_per_use > 0:
		GameState.add_coins(item.data.cost_per_use)
	if item_released.get_connections().is_empty():
		item.queue_free()
	else:
		item_released.emit(item)
	_repack()
	if items.is_empty() and not state_machine.is_in(STATE_EMPTY):
		state_machine.transition_to(STATE_EMPTY)
	_update_view()
	contents_changed.emit(ids())


## Корзина: всё из чаши — обратно на полку. Из Loaded цена возвращается (STATIONS §1.1).
func empty_to_shelf() -> void:
	var refund: bool = state_machine.is_in(STATE_LOADED)
	for item: IngredientItem in items.duplicate():
		release(item, refund)


func _on_drop_attempted(draggable: Draggable) -> void:
	var item: IngredientItem = draggable.body as IngredientItem
	if item == null or item.data == null:
		drop_target.reject(REASON_KIND)
		return
	if is_full():
		drop_target.reject(REASON_FULL)
		return
	if item.data.cost_per_use > GameState.coins:
		drop_target.reject(REASON_COINS)
		return
	drop_target.snap_point = _marks_for(capacity)[items.size()]


func _on_received(draggable: Draggable) -> void:
	var item: IngredientItem = draggable.body as IngredientItem
	if item.data.cost_per_use > 0:
		GameState.try_spend_coins(item.data.cost_per_use)
	# Переносим в чашу кадром позже: сейчас идёт обработка касания самого предмета.
	_settle_in_bowl.call_deferred(item)
	item.set_in_station(true)
	item.hit_area.tapped.connect(_on_item_tapped.bind(item))
	items.append(item)
	punch.punch(receive_punch)
	sfx_accept.play()
	if not state_machine.is_in(STATE_LOADED):
		state_machine.transition_to(STATE_LOADED)
	_update_view()
	contents_changed.emit(ids())


func _on_rejected(_draggable: Draggable, reason: StringName) -> void:
	var why: StringName = reason
	if reason == DropTarget.REASON_DISABLED and is_full():
		why = REASON_FULL
	if why == REASON_FULL:
		_blink_pips()
	punch.wiggle()
	sfx_reject.play()
	drop_refused.emit(why)


func _on_item_tapped(_world: Vector2, item: IngredientItem) -> void:
	if state_machine.is_in(STATE_LOADED):
		# Кадром позже: полка переносит предмет к себе, а касание по нему ещё обрабатывается.
		release.call_deferred(item, true)


## Ингредиент уже в ступке: кладём его между чашей и её передним краем, чтобы он лежал «внутри».
func _settle_in_bowl(item: IngredientItem) -> void:
	if not is_instance_valid(item) or not items.has(item) or item.get_parent() == contents:
		return
	item.reparent(contents)
	item.scale = Vector2.ONE


## Оставшиеся ингредиенты съезжают на первые места.
func _repack() -> void:
	var marks: Array[Marker2D] = _marks_for(capacity)
	for i: int in mini(items.size(), marks.size()):
		items[i].draggable.send_to(marks[i].global_position)


func _marks_for(count: int) -> Array[Marker2D]:
	return slots_three if count > slots_two.size() else slots_two


func _update_view() -> void:
	if drop_target == null:
		return
	drop_target.enabled = not is_full()
	trash.set_active(not items.is_empty())
	var first_x: float = -(capacity - 1) * pip_spacing * 0.5
	for i: int in pips.size():
		pips[i].visible = i < capacity
		pips[i].position.x = first_x + i * pip_spacing
		pip_fills[i].color = pip_full if i < items.size() else pip_empty


func _blink_pips() -> void:
	if _blink != null and _blink.is_valid():
		_blink.kill()
	_blink = create_tween().set_loops(maxi(pip_blinks, 1))
	_blink.tween_callback(_paint_pips.bind(pip_alert))
	_blink.tween_interval(pip_blink_sec)
	_blink.tween_callback(_update_view)
	_blink.tween_interval(pip_blink_sec)


func _paint_pips(color: Color) -> void:
	for i: int in mini(items.size(), pip_fills.size()):
		pip_fills[i].color = color
