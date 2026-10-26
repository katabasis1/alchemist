## ShelfCheck — проверочная сцена S2.1 (F6 на этой сцене): мастерская, полка ингредиентов, ступка с корзиной.
## Автопроверки при запуске → Output, итог строкой «SHELF: x/y OK». Потом всё возвращается в исходный вид
## для ручной проверки, памятка — там же. Сузьте окно (ширина меньше 0,9 высоты) — полка станет лентой внизу.
## Монеты и покупки GameState проверки меняют и в конце возвращают. Сохранение в этой сцене не загружено,
## поэтому SaveService пишет в Output «запись до загрузки пропущена» — так и должно быть.
## Тексты на экран не выводятся.
## Сигналы: нет.
## Зависимости: GameState (монеты, покупки), EventBus (drag_started, drag_ended), узлы сцены через @export.
extends Node2D

## Монет на время проверок: хватает на любые два ингредиента полки.
const CHECK_COINS: int = 100
## Запас ко времени анимации при ожидании её конца, секунды.
const WAIT_MARGIN_SEC: float = 0.15
## Насколько близко (пикс.) предмет должен вернуться к своей точке.
const NEAR_PX: float = 1.0
## Ингредиенты с одним и с тремя свойствами — для проверки иконок.
const ONE_PROPERTY: StringName = &"ing_sage_bundle"
const THREE_PROPERTIES: StringName = &"ing_sun_petal"
## Платный и слишком дорогой для пустого кошелька.
const PAID: StringName = &"ing_moon_moss"
const PRICEY: StringName = &"ing_star_crystal"
## Сколько иконок у ингредиента с тремя свойствами и сколько мест у ступки с улучшением.
const THREE: int = 3

@export var shelf: Shelf
@export var mortar: Mortar

var _passed: int = 0
var _total: int = 0
var _refusals: Array[StringName] = []


func _ready() -> void:
	mortar.drop_refused.connect(_on_drop_refused)
	_run_checks.call_deferred()


func _run_checks() -> void:
	# Кадр на запуск машины состояний и раскладку.
	await get_tree().process_frame
	var saved_coins: int = GameState.coins
	var saved_purchases: Array[StringName] = GameState.purchases.duplicate()
	GameState.coins = CHECK_COINS
	print("--- S2.1: полка и ступка ---")
	_check_shelf()
	await _check_drops()
	await _check_return_and_trash()
	_check_upgrade(saved_purchases)
	_check_ribbon()
	GameState.coins = saved_coins
	GameState.purchases = saved_purchases
	mortar.refresh_capacity()
	print("SHELF: %d/%d OK" % [_passed, _total])
	_print_manual()


func _check_shelf() -> void:
	_check("полка: по ячейке на ингредиент", shelf.slots.size() == shelf.ingredient_ids.size())
	var filled: bool = true
	for slot: ShelfSlot in shelf.slots:
		filled = filled and slot.item != null and slot.item.data == slot.data
	_check("в каждой ячейке лежит свой ингредиент", filled)
	_check("иконки: одно свойство — одна иконка", _visible_icons(_slot(ONE_PROPERTY)) == 1)
	_check("иконки: три свойства — три иконки", _visible_icons(_slot(THREE_PROPERTIES)) == THREE)
	var draggable: Draggable = shelf.slots[0].item.draggable
	EventBus.drag_started.emit(draggable)
	_check("ингредиент в руке — ступка подсвечена", mortar.drop_target.state == DropTarget.Highlight.AVAILABLE)
	EventBus.drag_ended.emit(draggable)
	_check("отпустили — подсветка погасла", mortar.drop_target.state == DropTarget.Highlight.NONE)


func _check_drops() -> void:
	var first_slot: ShelfSlot = _slot(ONE_PROPERTY)
	var first: IngredientItem = first_slot.item
	await _drop(first)
	_check("ступка приняла ингредиент", mortar.items.size() == 1 and mortar.items[0] == first)
	_check("он лежит в чаше и не переносится", first.get_parent() == mortar.contents and first.in_station)
	_check("на полке на его месте новый", first_slot.item != null and first_slot.item != first)
	_check("ступка: Empty → Loaded", mortar.state_machine.is_in(Mortar.STATE_LOADED))
	_check("корзина ожила", mortar.trash.active)

	var paid_data: IngredientData = _slot(PAID).data
	var coins_before: int = GameState.coins
	await _drop(_slot(PAID).item)
	_check("цена списана при броске", GameState.coins == coins_before - paid_data.cost_per_use)
	_check("2 из 2: ступка полна, цель выключена", mortar.is_full() and not mortar.drop_target.enabled)
	var draggable: Draggable = first_slot.item.draggable
	EventBus.drag_started.emit(draggable)
	_check("полная ступка не подсвечивается", mortar.drop_target.state == DropTarget.Highlight.NONE)
	EventBus.drag_ended.emit(draggable)

	var extra_slot: ShelfSlot = shelf.slots[1]
	var extra: IngredientItem = extra_slot.item
	_refusals.clear()
	await _drop(extra, extra.draggable.return_sec)
	_check("третий — отказ «полно»", _refusals == [Mortar.REASON_FULL] and mortar.items.size() == 2)
	_check("отказанный вернулся в свою ячейку", extra_slot.item == extra
			and extra.global_position.distance_to(extra_slot.item_anchor.global_position) < NEAR_PX)


func _check_return_and_trash() -> void:
	var paid: IngredientItem = mortar.items[1]
	var coins_before: int = GameState.coins
	paid.hit_area.tapped.emit(paid.global_position)
	await _wait(paid.draggable.fly_sec)
	_check("тап по ингредиенту в чаше — он ушёл на полку", mortar.items.size() == 1)
	_check("цена вернулась", GameState.coins == coins_before + _slot(PAID).data.cost_per_use)
	_check("вернувшийся растворился в ячейке", not is_instance_valid(paid))

	GameState.coins = 0
	_refusals.clear()
	var pricey: IngredientItem = _slot(PRICEY).item
	await _drop(pricey, pricey.draggable.return_sec)
	_check("монет не хватает — отказ «монеты»", _refusals == [Mortar.REASON_COINS] and mortar.items.size() == 1)
	GameState.coins = CHECK_COINS

	await _drop(_slot(PAID).item)
	coins_before = GameState.coins
	mortar.trash.hit_area.tapped.emit(mortar.trash.global_position)
	await _wait(shelf.slots[0].item.draggable.fly_sec)
	_check("корзина: ступка пуста, Loaded → Empty", mortar.items.is_empty()
			and mortar.state_machine.is_in(Mortar.STATE_EMPTY))
	_check("корзина вернула цену", GameState.coins == coins_before + _slot(PAID).data.cost_per_use)
	_check("у пустой ступки корзина приглушена", not mortar.trash.active)
	_check("пустая ступка снова принимает", mortar.drop_target.enabled)


func _check_upgrade(saved_purchases: Array[StringName]) -> void:
	GameState.purchases.append(mortar.third_slot_upgrade.id)
	mortar.refresh_capacity()
	_check("улучшение: три места и три огонька", mortar.capacity == THREE and mortar.pips[THREE - 1].visible)
	GameState.purchases = saved_purchases.duplicate()
	mortar.refresh_capacity()
	_check("без улучшения снова два", mortar.capacity == THREE - 1 and not mortar.pips[THREE - 1].visible)


func _check_ribbon() -> void:
	var was_ribbon: bool = shelf.ribbon
	shelf.set_ribbon(true)
	_check("лента: шесть ячеек не влезают, есть что листать", shelf.max_scroll() > 0.0)
	shelf.scroll_to(shelf.slots.size() - 1)
	_check("scroll_to: последняя ячейка видна", is_equal_approx(shelf.scroll, shelf.max_scroll()))
	_check("ячейка, ушедшая за край, не ловит касания", not shelf.slots[0].visible)
	shelf.scroll_to(0)
	_check("scroll_to(0): лента в начале", is_zero_approx(shelf.scroll))
	shelf.set_ribbon(was_ribbon)


func _drop(item: IngredientItem, wait_sec: float = -1.0) -> void:
	item.draggable.drop_on(mortar.drop_target)
	await _wait(wait_sec if wait_sec >= 0.0 else item.draggable.fly_sec)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec + WAIT_MARGIN_SEC).timeout


func _slot(id: StringName) -> ShelfSlot:
	return shelf.slot_for(shelf.catalog.ingredient(id))


func _visible_icons(slot: ShelfSlot) -> int:
	var count: int = 0
	for icon: TextureRect in slot.icons:
		if icon.visible and icon.texture != null:
			count += 1
	return count


func _on_drop_refused(reason: StringName) -> void:
	_refusals.append(reason)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		print("  FAIL ", title)
		push_error("ShelfCheck: не прошло — %s" % title)


func _print_manual() -> void:
	print("--- Ручная проверка ---")
	print("1. Возьмите ингредиент с полки: он приподнимается, ступка светится; над ступкой свет ярче.")
	print("2. Отпустите над ступкой: ингредиент падает в чашу, огонёк загорается, на полке появляется такой же.")
	print("3. Третий ингредиент в полную ступку: отскок, огоньки мигают красным, чаша вздрагивает.")
	print("4. Тап по ингредиенту в чаше: он летит в свою ячейку и сливается с тем, что там лежит.")
	print("5. Корзина у ступки: всё из чаши возвращается на полку, корзина бледнеет.")
	print("6. Тап по ингредиенту, потом тап по ступке: то же, что перенос пальцем.")
	print("7. Наведите мышь или подержите палец на ингредиенте: подсказка с названием.")
	print("8. Сузьте окно: полка уходит вниз лентой. Листается по пустому месту, жестом вбок по ингредиенту")
	print("   и колесом мыши; брошенная лента катится по инерции. Ингредиент берётся движением вверх.")
