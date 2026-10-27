## Mortar — станция «ступка» (GDD §3.3, docs/gdd/STATIONS.md §1.1): приём ингредиентов, вместимость, цена при броске,
## возврат на полку (S2.1); жест помола, шкала с зоной «идеально», пестик (S2.2).
## Ингредиенты лежат в чаше: слой contents стоит между чашей и её передним краем (BowlFront), пестик — там же.
## Касания над чашей ловит одна зона grind_area (поверх ингредиентов): жест — помол; тап по ингредиенту в Loaded —
## вернуть его на полку; тап мимо ингредиентов — ¼ круга (доступность).
## Перенос (S2.4): тело чаши — своя зона body_area. Потянул за неё или тапнул — из чаши появляется баночка (CarryVessel)
## со смесью, её несут клиенту (или тапом выбирают цель). Принята — hand_off: ступка пустеет. Не принята — баночка
## возвращается и прячется. Пока мелется (Grinding) или пусто, тело чаши не берётся.
## Помол p (0…1) растёт на grind_per_circle самого твёрдого ингредиента за круг; извлечение — EconomyConfig.extraction.
## Полная или молотая ступка не подсвечивается как цель; бросок в неё — отскок (&"full" — мигают огоньки, &"ground").
## Монет не хватает — отскок и drop_refused(&"coins"): HUD вздрогнет счётчиком (S2.4).
## Сигналы: item_released(item) — ингредиент отдан обратно (полка ловит его в take_back);
##   contents_changed(ids) — что лежит в чаше; drop_refused(reason) — бросок отклонён (&"full", &"coins", &"kind",
##   &"ground"); grind_changed(grind) — помол изменился (0…1); handed_off(mixture) — содержимое отдано (клиенту).
## Зависимости: DropTarget, StateMachine (Empty / Loaded / Grinding / Ground), GrindGesture, HitArea (зона помола),
##   ZoneGauge (шкала), Pestle, StationTrash, CarryVessel + Draggable (перенос) + HitArea body_area, JuicePunch, SfxComponent, IngredientItem, EconomyConfig (вместимость,
##   помол, извлечение), ToolData (улучшение «третий слот»), GameState (монеты, покупки), EventBus (пауза, поворот).
class_name Mortar
extends Node2D

signal item_released(item: IngredientItem)
signal contents_changed(ids: Array[StringName])
signal drop_refused(reason: StringName)
signal grind_changed(grind: float)
signal handed_off(mixture: Dictionary[StringName, float])

const STATE_EMPTY: StringName = &"Empty"
const STATE_LOADED: StringName = &"Loaded"
const STATE_GRINDING: StringName = &"Grinding"
const STATE_GROUND: StringName = &"Ground"
const REASON_FULL: StringName = &"full"
const REASON_COINS: StringName = &"coins"
const REASON_KIND: StringName = &"kind"
const REASON_GROUND: StringName = &"ground"

@export var economy: EconomyConfig
## Купленное улучшение даёт economy.mortar_slots_upgraded мест вместо economy.mortar_slots.
@export var third_slot_upgrade: ToolData
## Сила «подпрыгивания» чаши при приёме ингредиента.
@export var receive_punch: float = 0.6
## Тап ближе этого (мир) к ингредиенту в чаше — тап по нему (вернуть на полку), а не по чаше.
@export var item_pick_radius: float = 56.0
## Выброшенный помол исчезает за столько секунд.
@export var discard_sec: float = 0.2
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
## Зона касаний над чашей и пестиком (помол, тапы по ингредиентам).
@export var grind_area: HitArea
@export var gesture: GrindGesture
@export var gauge: ZoneGauge
@export var pestle: Pestle
@export var trash: StationTrash
@export var punch: JuicePunch
@export var sfx_accept: SfxComponent
@export var sfx_reject: SfxComponent
@export_group("Перенос")
## Баночка со смесью: прячется в чаше, появляется, когда содержимое берут.
@export var vessel: CarryVessel
## Draggable баночки (body = vessel, hit_area = body_area, kind = &"potion").
@export var vessel_drag: Draggable
## Тело чаши под зоной помола: за него берут содержимое.
@export var body_area: HitArea

var items: Array[IngredientItem] = []
var capacity: int = 2
## Степень помола p: 0 — целые, perfect_from…perfect_to — идеально, 1 — пыль.
var grind: float = 0.0
var _blink: Tween
## Где баночка ждёт в чаше (локально в ступке).
var _vessel_home: Vector2 = Vector2.ZERO


func _ready() -> void:
	drop_target.drop_attempted.connect(_on_drop_attempted)
	drop_target.received.connect(_on_received)
	drop_target.rejected.connect(_on_rejected)
	trash.pressed.connect(empty_to_shelf)
	state_machine.state_changed.connect(_on_state_changed)
	gesture.started.connect(_on_gesture_started)
	gesture.turned.connect(_on_gesture_turned)
	gesture.ended.connect(_on_gesture_ended)
	grind_area.pointer_moved.connect(_on_grind_pointer_moved)
	grind_area.tapped.connect(_on_grind_area_tapped)
	grind_area.long_pressed.connect(_on_grind_area_long_pressed)
	grind_area.pointer_up.connect(_on_grind_area_released)
	EventBus.layout_changed.connect(_on_layout_changed)
	EventBus.pause_changed.connect(_on_pause_changed)
	_vessel_home = vessel.position
	body_area.enabled = false
	vessel_drag.drag_started.connect(_on_vessel_taken)
	vessel_drag.selected_changed.connect(_on_vessel_selected)
	vessel_drag.dropped.connect(_on_vessel_dropped)
	vessel_drag.landed.connect(_on_vessel_landed)
	vessel_drag.returned.connect(_on_vessel_returned)
	if economy != null:
		gesture.taps_per_circle = economy.taps_per_circle
		gauge.set_zone(economy.perfect_from, economy.perfect_to)
	gauge.set_value(0.0, true)
	gauge.visible = false
	grind_area.enabled = false
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


## Молотое (Ground) или мелется прямо сейчас: ингредиенты уже не вернуть, новые не принять.
func is_ground() -> bool:
	return state_machine.is_in(STATE_GROUND) or state_machine.is_in(STATE_GRINDING)


## Мелется прямо сейчас: палец занят жестом, содержимое не берётся.
func is_grinding() -> bool:
	return state_machine.is_in(STATE_GRINDING)


## Самый твёрдый ингредиент в чаше — по нему считается скорость помола (GDD §3.3).
func hardest() -> IngredientData.Hardness:
	var result: IngredientData.Hardness = IngredientData.Hardness.SOFT
	for item: IngredientItem in items:
		if item.data != null and item.data.hardness > result:
			result = item.data.hardness
	return result


## Доля извлечения свойств при текущем помоле (GDD §3.3).
func extraction() -> float:
	return economy.extraction(grind) if economy != null else 1.0


## Свойства смеси в ступке: сумма свойств ингредиентов × извлечение (GDD §3.2–3.3). Её понесут клиенту (S2.4).
func mixture() -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	var k: float = extraction()
	for item: IngredientItem in items:
		if item.data == null:
			continue
		for property_id: StringName in item.data.properties:
			result[property_id] = result.get(property_id, 0.0) + item.data.properties[property_id] * k
	return result


## Добавить помол в кругах (жест, тап, проверки). Шкала стоит на 1.
func add_circles(circles: float) -> void:
	if items.is_empty() or circles <= 0.0:
		return
	var per_circle: float = economy.grind_per_circle(hardest()) if economy != null else 0.0
	set_grind(grind + circles * per_circle)


func set_grind(value: float, instant: bool = false) -> void:
	var new_grind: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(new_grind, grind) and not instant:
		return
	grind = new_grind
	gauge.set_value(grind, instant)
	grind_changed.emit(grind)


## Отдать ингредиент обратно на полку. refund — вернуть его цену (из Loaded — да, молотый — нет).
func release(item: IngredientItem, refund: bool) -> void:
	var index: int = items.find(item)
	if index < 0:
		return
	_detach(item)
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


## Корзина. Из Loaded всё возвращается на полку с ценой (STATIONS §1.1); молотое выбрасывается без возврата.
func empty_to_shelf() -> void:
	if state_machine.is_in(STATE_GRINDING):
		gesture.cancel()
	if is_ground():
		discard()
		return
	var refund: bool = state_machine.is_in(STATE_LOADED)
	for item: IngredientItem in items.duplicate():
		release(item, refund)


## Содержимое отдали (клиенту принята баночка): ингредиенты исчезают, ступка пустеет, цена не возвращается.
func hand_off() -> void:
	var given: Dictionary[StringName, float] = vessel.mixture.duplicate() if vessel.is_filled() else mixture()
	discard()
	handed_off.emit(given)


## Выбросить содержимое: ингредиенты исчезают, помол сбрасывается, цена не возвращается.
func discard() -> void:
	if state_machine.is_in(STATE_GRINDING):
		gesture.cancel()
	for item: IngredientItem in items.duplicate():
		_detach(item)
		var tween: Tween = item.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(item, ^"scale", Vector2.ZERO, discard_sec)
		tween.tween_callback(item.queue_free)
	if not state_machine.is_in(STATE_EMPTY):
		state_machine.transition_to(STATE_EMPTY)
	_update_view()
	contents_changed.emit(ids())


func _detach(item: IngredientItem) -> void:
	items.erase(item)
	var tap: Callable = _on_item_tapped.bind(item)
	if item.hit_area.tapped.is_connected(tap):
		item.hit_area.tapped.disconnect(tap)


func _on_drop_attempted(draggable: Draggable) -> void:
	var item: IngredientItem = draggable.body as IngredientItem
	if item == null or item.data == null:
		drop_target.reject(REASON_KIND)
		return
	if is_ground():
		drop_target.reject(REASON_GROUND)
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


func _on_rejected(draggable: Draggable, reason: StringName) -> void:
	if draggable == vessel_drag:
		return  # баночку опустили обратно на ступку: она просто вернётся в чашу
	var why: StringName = reason
	if reason == DropTarget.REASON_DISABLED:
		if is_ground():
			why = REASON_GROUND
		elif is_full():
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


func _on_state_changed(_from: StringName, to: StringName) -> void:
	match to:
		STATE_EMPTY:
			set_grind(0.0, true)
			gauge.show_gauge(false)
			grind_area.enabled = false
			body_area.enabled = false
			pestle.rest()
		STATE_LOADED, STATE_GROUND:
			if not gauge.visible:
				gauge.show_gauge(true)
			grind_area.enabled = true
			body_area.enabled = true
		STATE_GRINDING:
			body_area.enabled = false
	_update_view()


func _on_gesture_started() -> void:
	if state_machine.is_in(STATE_LOADED) or state_machine.is_in(STATE_GROUND):
		_hide_item_tips()
		state_machine.transition_to(STATE_GRINDING)


func _on_gesture_turned(circles: float) -> void:
	if state_machine.is_in(STATE_GRINDING):
		add_circles(circles)


func _on_gesture_ended(_reason: StringName) -> void:
	if not state_machine.is_in(STATE_GRINDING):
		return
	pestle.rest()
	state_machine.transition_to(STATE_GROUND if grind > 0.0 else STATE_LOADED)


func _on_grind_pointer_moved(world: Vector2) -> void:
	if gesture.is_grinding:
		pestle.follow(world)


func _on_grind_area_tapped(world: Vector2) -> void:
	if state_machine.is_in(STATE_LOADED):
		var item: IngredientItem = _item_at(world)
		if item != null:
			release.call_deferred(item, true)
			return
	if (state_machine.is_in(STATE_LOADED) or state_machine.is_in(STATE_GROUND)) and gesture.tap_turn():
		pestle.poke(world)


func _on_grind_area_long_pressed(world: Vector2) -> void:
	var item: IngredientItem = _item_at(world)
	if item != null and not gesture.is_grinding:
		item.tooltip.show_tip()


func _on_grind_area_released(_world: Vector2, _inside: bool) -> void:
	_hide_item_tips()


func _on_layout_changed(_portrait: bool) -> void:
	gesture.cancel()


func _on_pause_changed(paused: bool) -> void:
	if paused:
		gesture.cancel()


## Баночку взяли (перенос или выбор тапом): наполнить смесью и показать.
func _on_vessel_taken() -> void:
	if items.is_empty() or is_grinding():
		vessel_drag.cancel()
		return
	_hide_item_tips()
	vessel.fill(mixture(), grind)
	vessel.show_up()


func _on_vessel_selected(selected: bool) -> void:
	if selected:
		_on_vessel_taken()
	else:
		# Выбор снят: если баночка сейчас не летит к цели, она остаётся в чаше и прячется.
		_stow_if_idle.call_deferred()


func _on_vessel_dropped(_target: DropTarget) -> void:
	hand_off()


## Баночка долетела до клиента: прячем её и возвращаем на место в чаше.
func _on_vessel_landed() -> void:
	vessel.stow()
	vessel_drag.place_at(to_global(_vessel_home))


func _on_vessel_returned() -> void:
	vessel.stow()


func _stow_if_idle() -> void:
	if not vessel_drag.is_busy():
		vessel.stow()


## Ингредиент в чаше под точкой мира (ближайший в пределах item_pick_radius).
func _item_at(world: Vector2) -> IngredientItem:
	var best: IngredientItem = null
	var best_distance: float = item_pick_radius
	for item: IngredientItem in items:
		var distance: float = item.global_position.distance_to(world)
		if distance <= best_distance:
			best = item
			best_distance = distance
	return best


func _hide_item_tips() -> void:
	for item: IngredientItem in items:
		item.tooltip.hide_tip()


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
	drop_target.enabled = not is_full() and not is_ground()
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
