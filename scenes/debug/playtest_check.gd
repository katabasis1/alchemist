## PlaytestCheck — проверочная сцена S2.5 (F6 на этой сцене): запись плейтеста (PlaytestRecorder) в лавке.
## Проверка играет два обучающих заказа сигналами, как order_check: ингредиенты бросает через Draggable.drop_on, мелет
## сигналами жеста и тапами (GrindGesture.tap_turn), отдаёт баночку через drop_on. По дороге — отказы ступки и клиента,
## перетёр, мусор, неверный эффект, пауза, поворот, уход клиента без оплаты. Потом сверяет записи, файл и сводку.
## Время до «идеально» сравнивается с тем, что намерила сама проверка (Time.get_ticks_msec), с допуском TIME_TOL_SEC.
## Регистратор этой сцены пишет в user://playtest_check/ (файлы тестера в user://playtest/ не трогаются) и не печатает
## записи в Output. Итог строкой «PLAYTEST: x/y OK», потом памятка для ручной проверки. Проверка идёт секунд двадцать —
## экран не трогайте. В конце GameState возвращается к тому, что было до проверок.
## Сигналы: нет.
## Зависимости: GameState (новая игра, монеты, каталог), Platform (пауза), EventBus (layout_changed),
##   LayoutSwitcher.portrait, узлы лавки и PlaytestRecorder через @export.
extends Node2D

## Запас ко времени анимации при ожидании её конца, секунды.
const WAIT_MARGIN_SEC: float = 0.15
## Запас сверх таймингов клиента и очереди, секунды.
const WAIT_SLACK_SEC: float = 1.0
## Допуск времени записи против замера проверки: округление до 0,01 с и кадр.
const TIME_TOL_SEC: float = 0.05
## Пауза перед первым броском («игрок читает заказ»), секунды.
const READ_SEC: float = 0.3
## Помол жестом: круги за шаг и шаг, секунды (медленно — в первом заказе, быстро — дальше).
const CIRCLES_PER_TURN: float = 1.0
const TURN_SEC: float = 0.2
const FAST_TURN_SEC: float = 0.05
## Тапы чуть реже лимита GrindGesture.max_taps_per_sec (12/с).
const TAP_SEC: float = 0.1
## Перетёр: столько кругов поверх «идеально» — помол упирается в 1 (пыль).
const OVERSHOOT_TURNS: int = 3
## Крупный помол огнецвета: столько кругов (ниже зоны).
const COARSE_TURNS: int = 2
## Пауза посреди заказа, секунды.
const PAUSE_SEC: float = 0.5
const PAUSE_REASON: StringName = &"playtest_check"
const LIFE_HERB: StringName = &"ing_sage_bundle"
const HEAT_FLOWER: StringName = &"ing_fire_bloom"
const ORDER_FTUE_1: String = "ftue_1"
const ORDER_FTUE_2: String = "ftue_2"
const MSEC_PER_SEC: float = 1000.0
const EPSILON: float = 0.0001
## Папка файлов регистратора этой сцены (задана в playtest_check.tscn).
const CHECK_FOLDER: String = "user://playtest_check"
## Что сыграно: партий в заказе 2 (мусор, огнецвет, шалфей); за всю проверку — оплачено, партий с помолом,
## отдано клиенту (все в зоне).
const ORDER_2_BATCHES: int = 3
const PAID_ORDERS: int = 2
const GROUND_BATCHES: int = 4
const HANDED_BATCHES: int = 3
## Медиана: наборы и ответы (нечётный, чётный).
const MEDIAN_ODD: Array[float] = [3.0, 1.0, 2.0]
const MEDIAN_ODD_IS: float = 2.0
const MEDIAN_EVEN: Array[float] = [4.0, 1.0, 3.0, 2.0]
const MEDIAN_EVEN_IS: float = 2.5

@export var desk: OrderDesk
@export var client: Client
@export var mortar: Mortar
@export var shelf: Shelf
@export var recorder: PlaytestRecorder

var _passed: int = 0
var _total: int = 0
var _arrived_msec: int = -1
var _paid: Array[int] = []
## Замер проверки в партии: первый помол и первый заход в зону «идеально», мс (-1 — ещё не было).
var _grind_start_msec: int = -1
var _perfect_msec: int = -1
## Сколько на самом деле длилась пауза проверки, мс (таймер срабатывает на кадр позже PAUSE_SEC).
var _pause_msec: int = 0


func _ready() -> void:
	client.arrived.connect(_on_arrived)
	desk.order_paid.connect(_on_order_paid)
	_run_checks.call_deferred()


func _run_checks() -> void:
	await get_tree().process_frame
	_clear_folder()
	var saved: Dictionary = GameState.to_dict()
	GameState.new_game()
	print("--- S2.5: запись плейтеста (PlaytestRecorder) ---")
	_check("регистратор включён (отладочная сборка), пишет в %s" % CHECK_FOLDER, recorder.is_active()
			and recorder.folder == CHECK_FOLDER and recorder.write_file)
	await _check_first_order()
	await _check_second_order()
	await _check_left_order()
	_check_file()
	_check_summary()
	GameState.from_dict(saved)
	print("PLAYTEST: %d/%d OK" % [_passed, _total])
	_print_manual()


# --- заказ 1: помол жестом, оплата -------------------------------------------------------------------------------

func _check_first_order() -> void:
	desk.start()
	var arrived: bool = await _wait_until(client.is_waiting, client.walk_sec + WAIT_SLACK_SEC)
	_check("клиент пришёл; записи заказа и партии пока нет", arrived and _of_type(PlaytestRecorder.TYPE_ORDER).is_empty()
			and _of_type(PlaytestRecorder.TYPE_BATCH).is_empty())
	await _wait(READ_SEC)
	await _drop_from_shelf(LIFE_HERB)
	_check("шалфей в ступке — партия идёт, записи партии ещё нет", mortar.items.size() == 1
			and _of_type(PlaytestRecorder.TYPE_BATCH).is_empty())
	_reset_timing()
	var turns: int = _turns_to_perfect()
	await _gesture(turns, TURN_SEC)
	var grind: float = mortar.grind
	_hand_to_client()
	var hand_msec: int = Time.get_ticks_msec()
	await get_tree().process_frame
	var batch: Dictionary = _last(PlaytestRecorder.TYPE_BATCH)
	_check("партия записана сразу после передачи: отдана, заказ %s" % ORDER_FTUE_1, not batch.is_empty()
			and batch["outcome"] == PlaytestRecorder.OUTCOME_HANDED and batch["order"] == ORDER_FTUE_1)
	_check("партия: шалфей, мягкий, 1 жест, 0 тапов, %d кругов" % turns, _strings_are(batch.get("ingredients"), [str(LIFE_HERB)])
			and batch.get("hardness") == "soft" and int(batch.get("gestures", -1)) == 1
			and int(batch.get("taps", -1)) == 0 and _near(batch.get("circles"), turns * CIRCLES_PER_TURN, EPSILON)
			and _ends_are(batch, {"released": 1}))
	_check("партия: помол %.2f в зоне, без перетёра" % grind, _near(batch.get("grind"), grind, PlaytestRecorder.GRIND_STEP)
			and bool(batch.get("in_zone")) and not bool(batch.get("overshoot")) and not bool(batch.get("dust")))
	var perfect_sec: float = _measured_perfect_sec()
	_check("до «идеально» %.2f с (замер проверки), жестом столько же" % perfect_sec,
			_near(batch.get("perfect_sec"), perfect_sec, TIME_TOL_SEC)
			and _near(batch.get("perfect_active_sec"), perfect_sec, TIME_TOL_SEC))
	await _wait(client.react_delay_sec)
	var order: Dictionary = _last(PlaytestRecorder.TYPE_ORDER)
	var economy: EconomyConfig = mortar.economy
	var one_right: Array[bool] = [true]
	_check("заказ записан после оплаты: %s, обучающий, оплачен" % ORDER_FTUE_1, not order.is_empty()
			and order["order"] == ORDER_FTUE_1 and bool(order["ftue"]) and order["result"] == PlaytestRecorder.RESULT_PAID)
	_check("заказ: 1 попытка — верно, в зоне, %d ★; 1 партия, без отказов" % economy.max_stars(),
			_attempts_are(order, one_right) and int(order["stars"]) == economy.max_stars()
			and int(order["batches"]) == 1 and int(order["discarded"]) == 0 and int(order["wrong"]) == 0
			and (order["client_refusals"] as Dictionary).is_empty() and (order["mortar_refusals"] as Dictionary).is_empty())
	_check("заказ: оплата и монеты как в игре, серия 1", _paid.size() == 1 and int(order["pay"]) == _paid[0]
			and int(order["coins"]) == GameState.coins and int(order["streak"]) == 1)
	var order_sec: float = (hand_msec - _arrived_msec) / MSEC_PER_SEC
	_check("время заказа %.2f с — от прихода до передачи; первый бросок не раньше %.1f с" % [order_sec, READ_SEC],
			_near(order.get("order_sec"), order_sec, TIME_TOL_SEC) and _num(order.get("first_drop_sec"), -1.0) >= READ_SEC
			and _num(order.get("first_drop_sec"), INF) <= _num(order.get("first_attempt_sec"), -INF)
			and _near(order.get("first_attempt_sec"), order_sec, TIME_TOL_SEC))


# --- заказ 2: отказы, тапы, перетёр, мусор, неверный эффект, пауза, поворот ---------------------------------------

func _check_second_order() -> void:
	var arrived: bool = await _wait_until(client.is_waiting, _next_client_sec())
	_check("пришёл обучающий заказ 2", arrived and str(client.order.id) == ORDER_FTUE_2)
	var arrived_msec: int = _arrived_msec
	await _drop_from_shelf(LIFE_HERB)
	await _drop_from_shelf(LIFE_HERB)
	await _drop_from_shelf(LIFE_HERB)
	await _wait(shelf.slot_for(GameState.catalog.ingredient(LIFE_HERB)).item.draggable.return_sec)
	_check("третий шалфей в полную ступку — отказ (в заказе: full 1)", mortar.items.size() == 2)
	_reset_timing()
	var taps: int = _taps_to_perfect()
	var accepted: int = 0
	for i: int in taps:
		if i > 0:
			await get_tree().create_timer(TAP_SEC).timeout
		if mortar.gesture.tap_turn():
			accepted += 1
		_note_grind()
	_check("тапами до «идеально»: %d тапов приняты" % taps, accepted == taps and _in_zone(mortar.grind))
	await _gesture(OVERSHOOT_TURNS, FAST_TURN_SEC)
	_check("перетёрли до пыли", is_equal_approx(mortar.grind, 1.0))
	mortar.empty_to_shelf()
	await get_tree().process_frame
	var batch: Dictionary = _last(PlaytestRecorder.TYPE_BATCH)
	var circles: float = taps / float(mortar.gesture.taps_per_circle) + OVERSHOOT_TURNS * CIRCLES_PER_TURN
	_check("партия в мусор: выброшена, перетёр и пыль, не в зоне", batch.get("outcome") == PlaytestRecorder.OUTCOME_DISCARDED
			and bool(batch.get("overshoot")) and bool(batch.get("dust")) and not bool(batch.get("in_zone"))
			and _strings_are(batch.get("ingredients"), [str(LIFE_HERB), str(LIFE_HERB)]) and batch.get("order") == ORDER_FTUE_2)
	_check("партия: %d тапов + 1 жест, %.2f круга" % [taps, circles], int(batch.get("taps", -1)) == taps
			and int(batch.get("gestures", -1)) == 1 and _near(batch.get("circles"), circles, EPSILON)
			and _ends_are(batch, {"tap": taps, "released": 1}))
	var perfect_sec: float = _measured_perfect_sec()
	_check("тапы: до «идеально» %.2f с, а «жестом» почти 0 (тап — мгновенный круг)" % perfect_sec,
			_near(batch.get("perfect_sec"), perfect_sec, TIME_TOL_SEC) and _num(batch.get("perfect_active_sec"), INF) < TIME_TOL_SEC)
	mortar.vessel_drag.drop_on(client.drop_target)
	await _wait(mortar.vessel_drag.return_sec)
	await _drop_from_shelf(HEAT_FLOWER)
	_reset_timing()
	await _gesture(COARSE_TURNS, FAST_TURN_SEC)
	_hand_to_client()
	await _wait(mortar.vessel_drag.return_sec)
	_check("пустая баночка и крупный помол — клиент не взял, смесь в ступке", mortar.items.size() == 1
			and client.is_waiting())
	await _gesture(_turns_to_perfect() - COARSE_TURNS, FAST_TURN_SEC)
	_hand_to_client()
	await get_tree().process_frame
	batch = _last(PlaytestRecorder.TYPE_BATCH)
	_check("огнецвет: 2 жеста; «жестом» до зоны меньше, чем по часам (между жестами — отказ клиента)",
			int(batch.get("gestures", -1)) == 2 and batch.get("outcome") == PlaytestRecorder.OUTCOME_HANDED
			and _num(batch.get("perfect_active_sec"), INF) + mortar.vessel_drag.return_sec < _num(batch.get("perfect_sec"), 0.0)
			and _near(batch.get("perfect_sec"), _measured_perfect_sec(), TIME_TOL_SEC))
	await _wait(client.react_delay_sec)
	_check("неверный эффект — заказ ещё не записан", str(_last(PlaytestRecorder.TYPE_ORDER).get("order")) == ORDER_FTUE_1)
	await _wait_until(client.is_waiting, client.react_sec + WAIT_SLACK_SEC)
	await _check_pause()
	_check_layout()
	await _drop_from_shelf(LIFE_HERB)
	await _drop_from_shelf(LIFE_HERB)
	await _gesture(_turns_to_perfect(), FAST_TURN_SEC)
	_hand_to_client()
	var hand_msec: int = Time.get_ticks_msec()
	await _wait(client.react_delay_sec)
	var order: Dictionary = _last(PlaytestRecorder.TYPE_ORDER)
	var wrong_then_right: Array[bool] = [false, true]
	_check("заказ 2 оплачен: 2 попытки (неверно, верно), wrong 1", order.get("order") == ORDER_FTUE_2
			and order.get("result") == PlaytestRecorder.RESULT_PAID and _attempts_are(order, wrong_then_right)
			and int(order.get("wrong", -1)) == 1)
	_check("заказ 2: отказы клиента kind 1 + grind 1, ступки full 1", order.get("client_refusals") == {"kind": 1, "grind": 1}
			and order.get("mortar_refusals") == {"full": 1})
	_check("заказ 2: %d партии, 1 в мусор" % ORDER_2_BATCHES, int(order.get("batches", -1)) == ORDER_2_BATCHES
			and int(order.get("discarded", -1)) == 1)
	var order_sec: float = (hand_msec - arrived_msec - _pause_msec) / MSEC_PER_SEC
	_check("время заказа без паузы (%.2f с): %.2f с" % [_pause_msec / MSEC_PER_SEC, order_sec], _near(order.get("order_sec"), order_sec, TIME_TOL_SEC))


func _check_pause() -> void:
	var before: int = _of_type(PlaytestRecorder.TYPE_EVENT).size()
	var paused_at: int = Time.get_ticks_msec()
	Platform.set_paused(PAUSE_REASON, true)
	await get_tree().create_timer(PAUSE_SEC).timeout
	Platform.set_paused(PAUSE_REASON, false)
	_pause_msec = Time.get_ticks_msec() - paused_at
	var events: Array[Dictionary] = _of_type(PlaytestRecorder.TYPE_EVENT)
	var ok: bool = events.size() == before + 2
	if ok:
		var on: Dictionary = events[before]
		var off: Dictionary = events[before + 1]
		ok = (on["event"] == PlaytestRecorder.EVENT_PAUSE and bool(on["on"]) and off["event"] == PlaytestRecorder.EVENT_PAUSE
				and not bool(off["on"]) and _near(off["t"], float(on["t"]), PlaytestRecorder.SEC_STEP))
	_check("пауза: два события, часы записи на паузе стоят", ok)


func _check_layout() -> void:
	var portrait: bool = LayoutSwitcher.portrait
	EventBus.layout_changed.emit(portrait)
	var event: Dictionary = _last(PlaytestRecorder.TYPE_EVENT)
	_check("поворот: событие layout", event.get("event") == PlaytestRecorder.EVENT_LAYOUT
			and bool(event.get("portrait")) == portrait)


# --- заказ 3: уход без оплаты ----------------------------------------------------------------------------------------

func _check_left_order() -> void:
	var arrived: bool = await _wait_until(client.is_waiting, _next_client_sec())
	var order_id: String = str(client.order.id) if arrived else ""
	var orders: int = _of_type(PlaytestRecorder.TYPE_ORDER).size()
	GameState.new_game()
	var order_recorded: Callable = func() -> bool: return _of_type(PlaytestRecorder.TYPE_ORDER).size() > orders
	await _wait_until(order_recorded, client.walk_sec + WAIT_SLACK_SEC)
	var order: Dictionary = _last(PlaytestRecorder.TYPE_ORDER)
	_check("новая игра посреди заказа: заказ %s записан как ушедший, без оплаты" % order_id, arrived
			and order.get("order") == order_id and order.get("result") == PlaytestRecorder.RESULT_LEFT
			and int(order.get("pay", -1)) == 0 and (order.get("attempts", []) as Array).is_empty())


# --- файл и сводка ---------------------------------------------------------------------------------------------------

func _check_file() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(CHECK_FOLDER)
	_check("в папке проверки один файл сессии", files.size() == 1
			and recorder.file_path == CHECK_FOLDER.path_join(files[0]))
	var text: String = FileAccess.get_file_as_string(recorder.file_path)
	var lines: PackedStringArray = text.split("\n", false)
	var parsed: Array[Dictionary] = []
	for line: String in lines:
		var value: Variant = JSON.parse_string(line)
		if value is Dictionary:
			parsed.append(value)
	_check("файл: строк столько же, сколько записей (%d), все — JSON" % recorder.records.size(),
			lines.size() == recorder.records.size() and parsed.size() == lines.size())
	var header: Dictionary = parsed[0] if not parsed.is_empty() else {}
	_check("первая строка — шапка: схема, версия игры, зона «идеально»", header.get("type") == PlaytestRecorder.TYPE_SESSION
			and int(header.get("schema", 0)) == PlaytestRecorder.SCHEMA
			and header.get("version") == ProjectSettings.get_setting(PlaytestRecorder.VERSION_SETTING)
			and _near(header.get("perfect_from"), mortar.economy.perfect_from, EPSILON))
	var same: bool = parsed.size() == recorder.records.size()
	if same:
		for i: int in parsed.size():
			same = (same and parsed[i].get("type") == recorder.records[i].get("type")
					and _near(parsed[i].get("t"), _num(recorder.records[i].get("t"), -1.0), EPSILON))
	_check("строки файла совпадают с записями (тип, время)", same)


func _check_summary() -> void:
	var s: Dictionary = recorder.summary()
	_check("сводка: оплачено %d, партий с помолом %d (перетёрта 1), отдано %d — все в зоне" % [PAID_ORDERS,
			GROUND_BATCHES, HANDED_BATCHES], int(s["orders"]) == PAID_ORDERS and int(s["ground"]) == GROUND_BATCHES
			and int(s["overshoot"]) == 1 and int(s["handed"]) == HANDED_BATCHES and int(s["in_zone"]) == HANDED_BATCHES
			and float(s["order_sec"]) > 0.0 and float(s["perfect_sec"]) > 0.0)
	var none: Array[float] = []
	_check("медиана: нечётное, чётное, пусто", is_equal_approx(PlaytestRecorder.median(MEDIAN_ODD), MEDIAN_ODD_IS)
			and is_equal_approx(PlaytestRecorder.median(MEDIAN_EVEN), MEDIAN_EVEN_IS)
			and PlaytestRecorder.median(none) == PlaytestRecorder.NO_DATA)


# --- помощники -------------------------------------------------------------------------------------------------------

func _drop_from_shelf(id: StringName) -> void:
	var item: IngredientItem = shelf.slot_for(GameState.catalog.ingredient(id)).item
	var sec: float = item.draggable.fly_sec
	item.draggable.drop_on(mortar.drop_target)
	await _wait(sec)


## Помол «как пальцем»: жест начался → turns шагов по CIRCLES_PER_TURN через sec → жест кончился.
func _gesture(turns: int, sec: float) -> void:
	mortar.gesture.started.emit()
	_note_grind()
	for i: int in turns:
		await get_tree().create_timer(sec).timeout
		mortar.gesture.turned.emit(CIRCLES_PER_TURN)
		_note_grind()
	mortar.gesture.ended.emit(GrindGesture.REASON_RELEASED)


## Замер проверки: начало помола в партии и первый заход в зону.
func _note_grind() -> void:
	var now: int = Time.get_ticks_msec()
	if _grind_start_msec < 0:
		_grind_start_msec = now
	if _perfect_msec < 0 and mortar.grind + EPSILON >= mortar.economy.perfect_from:
		_perfect_msec = now


func _reset_timing() -> void:
	_grind_start_msec = -1
	_perfect_msec = -1


func _measured_perfect_sec() -> float:
	return (_perfect_msec - _grind_start_msec) / MSEC_PER_SEC


func _hand_to_client() -> void:
	mortar.vessel_drag.select()
	mortar.vessel_drag.drop_on(client.drop_target)


## Сколько шагов жеста от нуля до зоны «идеально» у мягкого ингредиента.
func _turns_to_perfect() -> int:
	var economy: EconomyConfig = mortar.economy
	return ceili((economy.perfect_from - EPSILON) / (economy.grind_soft * CIRCLES_PER_TURN))


func _taps_to_perfect() -> int:
	var economy: EconomyConfig = mortar.economy
	return ceili((economy.perfect_from - EPSILON) / (economy.grind_soft / mortar.gesture.taps_per_circle))


func _in_zone(grind: float) -> bool:
	var economy: EconomyConfig = mortar.economy
	return grind + EPSILON >= economy.perfect_from and grind <= economy.perfect_to + EPSILON


func _of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Dictionary in recorder.records:
		if record.get("type") == type:
			out.append(record)
	return out


func _last(type: String) -> Dictionary:
	var all: Array[Dictionary] = _of_type(type)
	return all.back() if not all.is_empty() else {}


func _near(value: Variant, expected: float, tolerance: float) -> bool:
	return (value is float or value is int) and absf(float(value) - expected) <= tolerance


## Число из записи; null (нет данных) или не число — fallback.
func _num(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback


## Список строк из записи (Array[String] или массив из JSON) поэлементно равен expected.
func _strings_are(value: Variant, expected: Array) -> bool:
	if not (value is Array):
		return false
	var items: Array = value
	if items.size() != expected.size():
		return false
	for i: int in expected.size():
		if str(items[i]) != str(expected[i]):
			return false
	return true


func _ends_are(batch: Dictionary, expected: Dictionary) -> bool:
	var ends: Dictionary = batch.get("ends", {})
	if ends.size() != expected.size():
		return false
	for key: String in expected:
		if int(ends.get(key, -1)) != int(expected[key]):
			return false
	return true


## Попытки заказа: эффекты по порядку; верные — в зоне и со звёздами.
func _attempts_are(order: Dictionary, effects: Array[bool]) -> bool:
	var attempts: Array = order.get("attempts", [])
	if attempts.size() != effects.size():
		return false
	for i: int in effects.size():
		var attempt: Dictionary = attempts[i]
		if attempt.get("effect") != effects[i] or not bool(attempt.get("in_zone")):
			return false
		if effects[i] != (int(attempt.get("stars", 0)) > 0):
			return false
	return true


func _next_client_sec() -> float:
	return client.react_delay_sec + client.react_sec + client.walk_sec * 2.0 + desk.next_delay_sec + WAIT_SLACK_SEC


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec + WAIT_MARGIN_SEC).timeout


## Ждать (покадрово), пока condition не вернёт true, но не дольше timeout_sec. Возвращает, дождались ли.
func _wait_until(condition: Callable, timeout_sec: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + roundi(timeout_sec * MSEC_PER_SEC)
	while not bool(condition.call()):
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	return true


## Убрать файлы прошлых прогонов (кроме файла, который регистратор, может быть, уже начал).
func _clear_folder() -> void:
	for file: String in DirAccess.get_files_at(CHECK_FOLDER):
		var path: String = CHECK_FOLDER.path_join(file)
		if path != recorder.file_path:
			DirAccess.remove_absolute(path)


func _on_arrived() -> void:
	_arrived_msec = Time.get_ticks_msec()


func _on_order_paid(_order: OrderTemplate, _verdict: Dictionary, pay: int) -> void:
	_paid.append(pay)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		print("  FAIL ", title)
		push_error("PlaytestCheck: не прошло — %s" % title)


func _print_manual() -> void:
	print("--- Ручная проверка ---")
	print("1. main.tscn (F5): сыграйте заказ. В Output после каждой записи — строка «PLAYTEST {…}»,")
	print("   после каждого заказа — «PLAYTEST-ИТОГ: …».")
	print("2. Проект → Открыть папку данных пользователя → playtest/: файл session_<дата>.jsonl с теми же строками.")
	print("3. python tools/playtest/summarize.py <папка или файлы> — сводка против целей GDD §12.")
	print("   Сценарии плейтеста и лист наблюдений — docs/playtest/PLAYTEST_M2.md.")
