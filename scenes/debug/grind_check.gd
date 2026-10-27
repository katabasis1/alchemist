## GrindCheck — проверочная сцена S2.2–S2.3 (F6 на этой сцене): мастерская, полка, ступка с шкалой и пестиком.
## S2.3: отклик ступки (MortarJuice) — крошки, пыль, сплющивание пестика, распад ингредиентов, порошок, кольцо, вибрация.
## Автопроверки помола при запуске → Output, итог строкой «GRIND: x/y OK», потом памятка для ручной проверки.
## Касания проверки подают прямо сигналами зоны помола (HitArea), с настоящими паузами между событиями:
## жест считает скорость по времени. Проверка идёт пару секунд — экран в это время не трогайте.
## Монеты и покупки GameState проверки меняют и в конце возвращают. SaveService пишет в Output
## «запись до загрузки пропущена» — так и должно быть. Настройку вибрации проверка тоже меняет и возвращает.
## Тексты на экран не выводятся.
## Сигналы: нет.
## Зависимости: GameState (монеты, настройка вибрации), Platform (vibrated), EventBus (pause_changed), EconomyConfig
##   ступки, узлы сцены через @export (MortarJuice — внутри сцены ступки).
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
@export var juice: MortarJuice

var _passed: int = 0
var _total: int = 0
var _refusals: Array[StringName] = []
var _turned: float = 0.0
var _ended: Array[StringName] = []
var _quarters: int = 0
var _vibrations: int = 0
var _squashed: bool = false


func _ready() -> void:
	mortar.drop_refused.connect(_on_drop_refused)
	mortar.gesture.turned.connect(_on_turned)
	mortar.gesture.ended.connect(_on_ended)
	mortar.gesture.quarter_passed.connect(_on_quarter_passed)
	Platform.vibrated.connect(_on_vibrated)
	_run_checks.call_deferred()


func _run_checks() -> void:
	# Кадр на запуск машины состояний и раскладку.
	await get_tree().process_frame
	var saved_coins: int = GameState.coins
	var saved_shake: Variant = GameState.get_setting(GameState.SETTING_SHAKE)
	GameState.coins = CHECK_COINS
	GameState.set_setting(GameState.SETTING_SHAKE, true)
	print("--- S2.2: помол в ступке; S2.3: отклик ---")
	_check_empty()
	var dust_before: int = juice.dust.bursts
	await _check_loaded()
	_check_juice_loaded(dust_before)
	await _check_jump()
	await _check_circle()
	await _check_ground_drop()
	await _check_taps()
	await _check_speed_cap()
	await _check_leave()
	await _check_pause()
	_check_gauge_and_extraction()
	await _check_dull_and_vibration()
	await _check_trash()
	_check_crumble_reset()
	GameState.coins = saved_coins
	GameState.set_setting(GameState.SETTING_SHAKE, saved_shake)
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
	_quarters = 0
	_vibrations = 0
	_squashed = false
	var crumbs_before: int = juice.crumbs.bursts
	var sprite: Node2D = juice.pestle_squash.target
	var sprite_scale: Vector2 = sprite.scale
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
		_squashed = _squashed or not sprite.scale.is_equal_approx(sprite_scale)
	var expected: float = path / mortar.gesture.circle_length_px * per_circle
	_check("круг пальцем: Grinding, пестик идёт за пальцем", followed
			and mortar.state_machine.is_in(Mortar.STATE_GRINDING))
	_check("круг дал помол ≈ путь / circle_length_px × grind_hard (%.3f при ожидании %.3f)" % [mortar.grind, expected],
			absf(mortar.grind - expected) <= expected * CIRCLE_TOLERANCE)
	_check("шкала показывает помол", is_equal_approx(mortar.gauge.value, mortar.grind))
	_check("каждая ¼ круга — выброс крошек (четвертей %d, выбросов %d)" % [_quarters, juice.crumbs.bursts - crumbs_before],
			_quarters > 0 and juice.crumbs.bursts - crumbs_before == _quarters)
	_check("пестик сплющивается на ¼ круга", _squashed)
	_check("на ¼ круга запрошена вибрация (%d раз, не чаще ограничителя)" % _vibrations,
			_vibrations > 0 and _vibrations <= _quarters)
	var crumble: float = juice.crumble_for(mortar.grind)
	_check("ингредиенты крошатся по помолу (%.2f), горка порошка растёт" % crumble, crumble > 0.0
			and _items_crumble(crumble) and is_equal_approx(_powder(MortarJuice.PARAM_AMOUNT), crumble))
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
	var ring_before: int = juice.ring.plays
	var sparkle_before: int = juice.sparkle_burst.bursts
	mortar.set_grind(perfect, true)
	_check("идеально: шкала в зоне, извлечение 1", mortar.gauge.zone == ZoneGauge.Zone.INSIDE
			and is_equal_approx(mortar.extraction(), 1.0))
	_check("идеально: кольцо света, ингредиенты рассыпались целиком, порошок — полная горка",
			juice.ring.plays == ring_before + 1 and _items_crumble(1.0)
			and is_equal_approx(_powder(MortarJuice.PARAM_AMOUNT), 1.0)
			and _powder_color().is_equal_approx(juice.mixture_color)
			and is_equal_approx(_powder(MortarJuice.PARAM_SPARKLE), juice.sparkle_perfect))
	_check("идеально: всплеск звёздочек, золотые искры над горкой, светлячки смеси погасли",
			juice.sparkle_burst.bursts == sparkle_before + 1 and juice.motes_perfect.emitting
			and not juice.motes_idle.emitting)
	_check("идеально: лучи из чаши показаны вместе с волной (спутники FxRing)", _ring_extras_visible())
	var mixture: Dictionary[StringName, float] = mortar.mixture()
	var expected: Dictionary[StringName, float] = {}
	for item: IngredientItem in mortar.items:
		for property_id: StringName in item.data.properties:
			expected[property_id] = expected.get(property_id, 0.0) + item.data.properties[property_id]
	_check("смесь = сумма свойств × извлечение", mixture == expected)
	var dust_before: int = juice.dust.bursts
	mortar.set_grind(1.0, true)
	_check("перетёр: облако пыли, шкала трясётся, порошок ушёл в пыль", juice.dust.bursts == dust_before + 1
			and mortar.gauge.is_shaking() and _powder_color().is_equal_approx(juice.dust_color)
			and is_equal_approx(_powder(MortarJuice.PARAM_SPARKLE), juice.sparkle_dust))
	_check("перетёр: светлячков нет", not juice.motes_idle.emitting and not juice.motes_perfect.emitting)
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
	_check("корзина: порошка в чаше нет", is_zero_approx(_powder(MortarJuice.PARAM_AMOUNT)))
	await _wait(maxf(mortar.discard_sec, mortar.gauge.fade_sec))
	var freed: bool = true
	for item: IngredientItem in gone:
		freed = freed and not is_instance_valid(item)
	_check("ингредиенты исчезли, шкала спряталась", freed and not mortar.gauge.visible)
	_check("зона помола выключена, ступка снова принимает", not mortar.grind_area.enabled
			and mortar.drop_target.enabled)


func _check_juice_loaded(dust_before: int) -> void:
	_check("ингредиент лёг в чашу — облачко пыли (бросков 2, облачков %d)" % (juice.dust.bursts - dust_before),
			juice.dust.bursts - dust_before == 2)
	_check("до помола ингредиенты целые, порошка нет", _items_crumble(0.0)
			and is_zero_approx(_powder(MortarJuice.PARAM_AMOUNT)))
	_check("цвет порошка подмешан из свойств смеси", not juice.mixture_color.is_equal_approx(juice.powder_base))


func _check_dull_and_vibration() -> void:
	var dust_before: int = juice.dust.bursts
	var crumbs_before: int = juice.crumbs.bursts
	await _wait(1.0 / mortar.gesture.max_taps_per_sec)
	mortar.grind_area.tapped.emit(_center() + TAP_OFFSET)
	_check("p = 1: на ¼ круга облачко пыли вместо крошек", juice.dust.bursts == dust_before + 1
			and juice.crumbs.bursts == crumbs_before)
	GameState.set_setting(GameState.SETTING_SHAKE, false)
	_vibrations = 0
	await _wait(1.0 / mortar.gesture.max_taps_per_sec)
	mortar.grind_area.tapped.emit(_center() + TAP_OFFSET)
	_check("вибрация выключена в настройках — не вибрирует", _vibrations == 0)
	GameState.set_setting(GameState.SETTING_SHAKE, true)


## Ингредиент вернулся на полку — снова целый.
func _check_crumble_reset() -> void:
	var item: IngredientItem = _slot(EXTRA).item
	item.set_crumble(0.5, juice.mixture_color)
	item.set_in_station(false)
	_check("ингредиент вне станции — распад сброшен", is_zero_approx(item.get_crumble()))


func _ring_extras_visible() -> bool:
	if juice.ring.extras.is_empty():
		return false
	for extra: CanvasItem in juice.ring.extras:
		if extra == null or not extra.visible:
			return false
	return true


func _items_crumble(expected: float) -> bool:
	if mortar.items.is_empty():
		return false
	for item: IngredientItem in mortar.items:
		if absf(item.get_crumble() - expected) > EPSILON:
			return false
	return true


func _powder(param: StringName) -> float:
	var mat: ShaderMaterial = juice.powder.material as ShaderMaterial
	return float(mat.get_shader_parameter(param)) if mat != null else -1.0


func _powder_color() -> Color:
	var mat: ShaderMaterial = juice.powder.material as ShaderMaterial
	return mat.get_shader_parameter(MortarJuice.PARAM_POWDER_COLOR) if mat != null else Color.BLACK


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


func _on_quarter_passed() -> void:
	_quarters += 1


func _on_vibrated(_duration_ms: int) -> void:
	_vibrations += 1


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
	print("--- Отклик (S2.3) ---")
	print("9. Ингредиент ложится в чашу — бледное облачко. На каждую четверть круга: хруст (каждый раз чуть другой),")
	print("   крошки цвета смеси из-под пестика, пестик сплющивается. На телефоне с Android — лёгкая вибрация.")
	print("10. По мере помола ингредиенты крошатся, на дне растёт горка порошка; к зелёной зоне — одна горка.")
	print("11. Вход в зелёную зону: зелёное кольцо по краю чаши и звон. Перетёр: «пфф», облако пыли, шкала трясётся.")
	print("12. На самом верху шкалы пестик трёт пыль: глухой звук, без крошек. Вибрация выключается в настройках.")
