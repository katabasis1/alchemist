## GrindCheck — проверочная сцена S2.2 (F6 на этой сцене): мастерская, полка, ступка с шкалой и пестиком.
## Автопроверки помола при запуске → Output, итог строкой «GRIND: x/y OK», потом памятка для ручной проверки.
## Касания проверки подают прямо сигналами зоны помола (HitArea), с настоящими паузами между событиями:
## жест считает скорость по времени. Проверка идёт пару секунд — экран в это время не трогайте.
## Монеты и покупки GameState проверки меняют и в конце возвращают. SaveService пишет в Output
## «запись до загрузки пропущена» — так и должно быть. Тексты на экран не выводятся.
## Сигналы: нет.
## Зависимости: GameState (монеты), EventBus (pause_changed), EconomyConfig ступки, узлы сцены через @export.
extends Node2D

## Монет на время проверок: хватает на любые два ингредиента полки.
const CHECK_COINS: int = 100
## Запас ко времени анимации при ожидании её конца, секунды.
const WAIT_MARGIN_SEC: float = 0.15
## Мягкий бесплатный и твёрдый платный: помол считается по твёрдому.
const SOFT: StringName = &"ing_sage_bundle"
const HARD: StringName = &"ing_star_crystal"
## Ещё один ингредиент для броска в молотую ступку.
const EXTRA: StringName = &"ing_moon_moss"
## Круг пальцем: радиус (мир), шагов на круг, пауза между шагами (жест меряет скорость по времени).
const CIRCLE_RADIUS: float = 80.0
const CIRCLE_STEPS: int = 60
const STEP_SEC: float = 0.02
## Допуск помола за круг: часть пути до начала жеста не считается, кадры неровные.
const CIRCLE_TOLERANCE: float = 0.2
## Быстрые свайпы: размах (мир) и число взмахов — должны упереться в потолок кругов в секунду.
const SWIPE_HALF: float = 70.0
const SWIPES: int = 12
## Шквал: столько тапов подряд в один кадр (засчитаться должен один).
const TAP_BURST: int = 5
## Тап мимо ингредиентов: сдвиг от центра чаши вверх (мир).
const TAP_OFFSET: Vector2 = Vector2(0.0, -110.0)
## Значения помола для проверки шкалы и извлечения.
const GRIND_BELOW: float = 0.35
const EPSILON: float = 0.001
const MSEC_PER_SEC: float = 1000.0
## Насколько дальше границы ухода (в радиусах чаши) уводим палец.
const LEAVE_MARGIN: float = 0.1

@export var shelf: Shelf
@export var mortar: Mortar

var _passed: int = 0
var _total: int = 0
var _refusals: Array[StringName] = []
var _turned: float = 0.0
var _ended: Array[StringName] = []


func _ready() -> void:
	mortar.drop_refused.connect(_on_drop_refused)
	mortar.gesture.turned.connect(_on_turned)
	mortar.gesture.ended.connect(_on_ended)
	_run_checks.call_deferred()


func _run_checks() -> void:
	# Кадр на запуск машины состояний и раскладку.
	await get_tree().process_frame
	var saved_coins: int = GameState.coins
	GameState.coins = CHECK_COINS
	print("--- S2.2: помол в ступке ---")
	_check_empty()
	await _check_loaded()
	await _check_jump()
	await _check_circle()
	await _check_ground_drop()
	await _check_taps()
	await _check_speed_cap()
	await _check_leave()
	await _check_pause()
	_check_gauge_and_extraction()
	await _check_trash()
	GameState.coins = saved_coins
	print("GRIND: %d/%d OK" % [_passed, _total])
	_print_manual()


func _check_empty() -> void:
	_check("пустая ступка: шкалы нет", not mortar.gauge.visible)
	_check("пустая ступка: зона помола выключена", not mortar.grind_area.enabled)


func _check_loaded() -> void:
	await _drop(_slot(SOFT).item)
	await _drop(_slot(HARD).item)
	_check("два ингредиента: Loaded", mortar.items.size() == 2 and mortar.state_machine.is_in(Mortar.STATE_LOADED))
	_check("шкала появилась, помол 0", mortar.gauge.visible and is_zero_approx(mortar.grind))
	_check("зона помола включена", mortar.grind_area.enabled)
	_check("помол считается по самому твёрдому", mortar.hardest() == IngredientData.Hardness.HARD)


func _check_jump() -> void:
	var center: Vector2 = _center()
	_turned = 0.0
	_ended.clear()
	mortar.grind_area.pointer_down.emit(center + Vector2(CIRCLE_RADIUS, 0.0))
	await _wait_step()
	# Скачок длиннее max_step_px: жест начат, но путь не засчитан.
	var jump: float = mortar.gesture.max_step_px + mortar.gesture.start_distance
	mortar.grind_area.pointer_moved.emit(center + Vector2(CIRCLE_RADIUS - jump, 0.0))
	_check("сдвиг дальше порога — жест начат, Grinding", mortar.gesture.is_grinding
			and mortar.state_machine.is_in(Mortar.STATE_GRINDING))
	_check("скачок указателя не засчитан", is_zero_approx(_turned))
	mortar.grind_area.pointer_up.emit(center, true)
	await _wait_step()
	_check("отпустили без помола — обратно Loaded", mortar.state_machine.is_in(Mortar.STATE_LOADED)
			and _ended == [GrindGesture.REASON_RELEASED])


func _check_circle() -> void:
	var center: Vector2 = _center()
	var per_circle: float = mortar.economy.grind_per_circle(mortar.hardest())
	_turned = 0.0
	var path: float = 0.0
	var previous: Vector2 = center + Vector2(CIRCLE_RADIUS, 0.0)
	var followed: bool = false
	mortar.grind_area.pointer_down.emit(previous)
	for i: int in range(1, CIRCLE_STEPS + 1):
		await _wait_step()
		var angle: float = TAU * i / CIRCLE_STEPS
		var point: Vector2 = center + Vector2.from_angle(angle) * CIRCLE_RADIUS
		path += point.distance_to(previous)
		previous = point
		mortar.grind_area.pointer_moved.emit(point)
		followed = followed or mortar.pestle.is_following
	var expected: float = path / mortar.gesture.circle_length_px * per_circle
	_check("круг пальцем: Grinding, пестик идёт за пальцем", followed
			and mortar.state_machine.is_in(Mortar.STATE_GRINDING))
	_check("круг дал помол ≈ путь / circle_length_px × grind_hard (%.3f при ожидании %.3f)" % [mortar.grind, expected],
			absf(mortar.grind - expected) <= expected * CIRCLE_TOLERANCE)
	_check("шкала показывает помол", is_equal_approx(mortar.gauge.value, mortar.grind))
	mortar.grind_area.pointer_up.emit(previous, true)
	await _wait_step()
	_check("отпустили — Ground, пестик лёг", mortar.state_machine.is_in(Mortar.STATE_GROUND)
			and not mortar.pestle.is_following)


func _check_ground_drop() -> void:
	_refusals.clear()
	var extra: IngredientItem = _slot(EXTRA).item
	var coins_before: int = GameState.coins
	await _drop(extra, extra.draggable.return_sec)
	_check("бросок в молотую ступку — отказ «ground»", _refusals == [Mortar.REASON_GROUND]
			and mortar.items.size() == 2)
	_check("за отказ монеты не списаны", GameState.coins == coins_before)


func _check_taps() -> void:
	var per_tap: float = mortar.economy.grind_per_circle(mortar.hardest()) / mortar.economy.taps_per_circle
	await _wait(1.0 / mortar.gesture.max_taps_per_sec)
	var item: IngredientItem = mortar.items[0]
	var before: float = mortar.grind
	mortar.grind_area.tapped.emit(item.global_position)
	_check("тап по ингредиенту в Ground — не вернулся, а ¼ круга", mortar.items.has(item)
			and absf(mortar.grind - before - per_tap) < EPSILON)
	_check("после тапа снова Ground", mortar.state_machine.is_in(Mortar.STATE_GROUND))
	await _wait(1.0 / mortar.gesture.max_taps_per_sec)
	before = mortar.grind
	for _i: int in TAP_BURST:
		mortar.grind_area.tapped.emit(_center() + TAP_OFFSET)
	_check("шквал из %d тапов — засчитан один" % TAP_BURST, absf(mortar.grind - before - per_tap) < EPSILON)


func _check_speed_cap() -> void:
	var center: Vector2 = _center()
	_turned = 0.0
	mortar.grind_area.pointer_down.emit(center + Vector2(SWIPE_HALF, 0.0))
	var start_msec: int = Time.get_ticks_msec()
	for i: int in SWIPES:
		await get_tree().process_frame
		var side: float = -1.0 if i % 2 == 0 else 1.0
		mortar.grind_area.pointer_moved.emit(center + Vector2(SWIPE_HALF * side, 0.0))
	var elapsed: float = float(Time.get_ticks_msec() - start_msec) / MSEC_PER_SEC
	mortar.grind_area.pointer_up.emit(center, true)
	await _wait_step()
	var cap: float = mortar.gesture.max_circles_per_sec * elapsed
	_check("бешеные свайпы — не быстрее %.1f круга/с (%.2f за %.2f с)" % [mortar.gesture.max_circles_per_sec,
			_turned, elapsed], _turned > 0.0 and _turned <= cap + EPSILON)


func _check_leave() -> void:
	var center: Vector2 = _center()
	_ended.clear()
	mortar.grind_area.pointer_down.emit(center + Vector2(CIRCLE_RADIUS, 0.0))
	await _wait_step()
	mortar.grind_area.pointer_moved.emit(center + Vector2(CIRCLE_RADIUS * 0.5, 0.0))
	await _wait_step()
	var far: float = mortar.gesture.zone_radius * (mortar.gesture.leave_factor + LEAVE_MARGIN)
	mortar.grind_area.pointer_moved.emit(center + Vector2(far, 0.0))
	_check("палец ушёл дальше 1,5 радиуса — жест кончен, Ground", _ended == [GrindGesture.REASON_LEFT]
			and mortar.state_machine.is_in(Mortar.STATE_GROUND))
	mortar.grind_area.pointer_up.emit(center + Vector2(far, 0.0), false)
	await _wait_step()


func _check_pause() -> void:
	var center: Vector2 = _center()
	_ended.clear()
	mortar.grind_area.pointer_down.emit(center + Vector2(CIRCLE_RADIUS, 0.0))
	await _wait_step()
	mortar.grind_area.pointer_moved.emit(center + Vector2(CIRCLE_RADIUS * 0.5, 0.0))
	var before: float = mortar.grind
	EventBus.pause_changed.emit(true)
	_check("пауза посреди помола — Ground, помол сохранён", _ended == [GrindGesture.REASON_CANCELLED]
			and mortar.state_machine.is_in(Mortar.STATE_GROUND) and is_equal_approx(mortar.grind, before))
	EventBus.pause_changed.emit(false)
	mortar.grind_area.pointer_up.emit(center, true)
	await _wait_step()


func _check_gauge_and_extraction() -> void:
	var economy: EconomyConfig = mortar.economy
	mortar.set_grind(GRIND_BELOW, true)
	_check("крупно: шкала ниже зоны", mortar.gauge.zone == ZoneGauge.Zone.BELOW)
	_check("крупно: извлечение по формуле", is_equal_approx(mortar.extraction(),
			economy.extraction_floor + (1.0 - economy.extraction_floor) * GRIND_BELOW / economy.perfect_from))
	var perfect: float = (economy.perfect_from + economy.perfect_to) * 0.5
	mortar.set_grind(perfect, true)
	_check("идеально: шкала в зоне, извлечение 1", mortar.gauge.zone == ZoneGauge.Zone.INSIDE
			and is_equal_approx(mortar.extraction(), 1.0))
	var mixture: Dictionary[StringName, float] = mortar.mixture()
	var expected: Dictionary[StringName, float] = {}
	for item: IngredientItem in mortar.items:
		for property_id: StringName in item.data.properties:
			expected[property_id] = expected.get(property_id, 0.0) + item.data.properties[property_id]
	_check("смесь = сумма свойств × извлечение", mixture == expected)
	mortar.set_grind(1.0, true)
	mortar.add_circles(1.0)
	_check("пыль: помол стоит на 1, шкала выше зоны", is_equal_approx(mortar.grind, 1.0)
			and mortar.gauge.zone == ZoneGauge.Zone.ABOVE)
	_check("пыль: извлечение меньше 1", mortar.extraction() < 1.0)


func _check_trash() -> void:
	var coins_before: int = GameState.coins
	var gone: Array[IngredientItem] = mortar.items.duplicate()
	mortar.trash.hit_area.tapped.emit(mortar.trash.global_position)
	_check("корзина в Ground: пусто, Empty, помол 0", mortar.items.is_empty()
			and mortar.state_machine.is_in(Mortar.STATE_EMPTY) and is_zero_approx(mortar.grind))
	_check("молотое выброшено без возврата цены", GameState.coins == coins_before)
	await _wait(maxf(mortar.discard_sec, mortar.gauge.fade_sec))
	var freed: bool = true
	for item: IngredientItem in gone:
		freed = freed and not is_instance_valid(item)
	_check("ингредиенты исчезли, шкала спряталась", freed and not mortar.gauge.visible)
	_check("зона помола выключена, ступка снова принимает", not mortar.grind_area.enabled
			and mortar.drop_target.enabled)


func _center() -> Vector2:
	return mortar.gesture.center.global_position


func _drop(item: IngredientItem, wait_sec: float = -1.0) -> void:
	item.draggable.drop_on(mortar.drop_target)
	await _wait(wait_sec if wait_sec >= 0.0 else item.draggable.fly_sec)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec + WAIT_MARGIN_SEC).timeout


func _wait_step() -> void:
	await get_tree().create_timer(STEP_SEC).timeout


func _slot(id: StringName) -> ShelfSlot:
	return shelf.slot_for(shelf.catalog.ingredient(id))


func _on_drop_refused(reason: StringName) -> void:
	_refusals.append(reason)


func _on_turned(circles: float) -> void:
	_turned += circles


func _on_ended(reason: StringName) -> void:
	_ended.append(reason)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		print("  FAIL ", title)
		push_error("GrindCheck: не прошло — %s" % title)


func _print_manual() -> void:
	print("--- Ручная проверка ---")
	print("1. Бросьте в ступку два ингредиента: под чашей горят огоньки, слева появляется шкала.")
	print("2. Водите пальцем (мышью) кругами над чашей: пестик ходит за пальцем, шкала растёт.")
	print("   Свайпы туда-обратно тоже мелют. Твёрдый ингредиент мелется медленнее мягкого.")
	print("3. Доведите до зелёной зоны: заливка зеленеет. Дальше — серая «пыль», шкала стоит на верху.")
	print("4. Уведите палец далеко от чаши — помол останавливается, пестик ложится на место.")
	print("5. Тапы по чаше: каждый — четверть круга, пестик тычет. Очень частые тапы считаются не все.")
	print("6. В молотую ступку новый ингредиент не берётся: отскок, чаша вздрагивает.")
	print("7. Корзина у молотой ступки: всё исчезает, монеты не возвращаются, шкала гаснет.")
	print("8. Сузьте окно: ступка уезжает, помол продолжается там же.")
