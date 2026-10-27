## OrderCheck — проверочная сцена S2.4 (F6 на этой сцене): вся лавка (Workshop) — клиент с заказом, баночка из ступки,
## оценка, оплата, полёт монет в счётчик, очередь заказов.
## Автопроверки при запуске → Output, итог строкой «ORDER: x/y OK», потом памятка для ручной проверки.
## Перед проверками — новая игра (GameState.new_game): первым придёт обучающий заказ пекарши. Ингредиенты проверки
## бросают в ступку через Draggable.drop_on, помол ставят сигналами жеста и Mortar.set_grind, баночку берут тапом
## (Draggable.select) и отдают клиенту через drop_on. Клиент ходит и реагирует по своим таймингам, поэтому проверка идёт
## секунд пятнадцать — экран не трогайте.
## OrderDesk сам не стартует: игру здесь не загружали, EventBus.game_ready никто не шлёт. Первого клиента зовёт проверка.
## В конце GameState возвращается к тому, что было до проверок (from_dict): клиент уходит, приходит первый обучающий
## заказ — его можно сыграть руками. Сохранение не загружено, поэтому SaveService пишет в Output «запись до загрузки
## пропущена» — так и должно быть. Тексты на экран не выводятся.
## Сигналы: нет.
## Зависимости: GameState (новая игра, монеты, репутация, заказ, шаг обучения, серия), DataCatalog (через
##   GameState.catalog), узлы лавки через @export.
extends Node2D

## Запас ко времени анимации при ожидании её конца, секунды.
const WAIT_MARGIN_SEC: float = 0.15
## Запас сверх таймингов клиента и очереди, когда ждём «клиент снова у прилавка», секунды.
const WAIT_SLACK_SEC: float = 1.0
## Помол ниже зоны «идеально» — обучающий заказ такой баночки не берёт.
const GRIND_COARSE: float = 0.4
## Сколько раз тянуть случайный заказ после обучения.
const PICK_TRIES: int = 30
## Ингредиенты стартовой полки: жизнь 2; жар 2 + кислота 1.
const LIFE_HERB: StringName = &"ing_sage_bundle"
const HEAT_FLOWER: StringName = &"ing_fire_bloom"
## Заказы каталога: обучающие 1 (жизнь), 2 (жизнь, сила 2), 4 (жар, чистота 3), 5 (жизнь + жар, чистота 3), обычный.
const ORDER_FTUE_1: StringName = &"ftue_1"
const ORDER_FTUE_2: StringName = &"ftue_2"
const ORDER_FTUE_4: StringName = &"ftue_4"
const ORDER_FTUE_5: StringName = &"ftue_5"
const ORDER_FREE: StringName = &"healing_balm_s1_p2"
const LIFE: StringName = &"life"
const ACID: StringName = &"acid"
## Миллисекунд в секунде (Time.get_ticks_msec).
const MSEC_PER_SEC: float = 1000.0
## Причина конца жеста, которую подаёт проверка.
const GESTURE_END: StringName = &"check"
## Клиента с таким id в каталоге нет.
const MISSING_ID: String = "nobody"

@export var desk: OrderDesk
@export var client: Client
@export var mortar: Mortar
@export var shelf: Shelf
@export var hud: Hud

var _passed: int = 0
var _total: int = 0
var _arrivals: int = 0
var _left_count: int = 0
var _started: Array[StringName] = []
var _served: Array[Dictionary] = []
var _refused: Array[Dictionary] = []
var _paid: Array[int] = []
var _handed: Array[Dictionary] = []
var _client_refusals: Array[StringName] = []
## Место баночки в ступке (локально): раскладка двигает ступку, а не баночку внутри неё.
var _vessel_home: Vector2 = Vector2.ZERO


func _ready() -> void:
	client.arrived.connect(_on_arrived)
	client.left.connect(_on_left)
	client.served.connect(_on_served)
	client.refused.connect(_on_refused)
	client.drop_refused.connect(_on_client_drop_refused)
	desk.order_started.connect(_on_order_started)
	desk.order_paid.connect(_on_order_paid)
	mortar.handed_off.connect(_on_handed_off)
	_run_checks.call_deferred()


func _run_checks() -> void:
	# Кадр на запуск машин состояний и раскладку.
	await get_tree().process_frame
	_vessel_home = mortar.vessel.position
	var saved: Dictionary = GameState.to_dict()
	GameState.new_game()
	print("--- S2.4: клиент, заказ, оценка, оплата ---")
	_check_judge()
	_check_pick()
	await _check_arrival()
	await _check_empty_vessel()
	await _check_coarse_refused()
	await _check_serve_first()
	await _check_wrong_effect()
	await _check_serve_flawless()
	_check_deny_coins()
	await _check_reset()
	GameState.from_dict(saved)
	print("ORDER: %d/%d OK" % [_passed, _total])
	_print_manual()


# --- оценка (OrderJudge) -----------------------------------------------------------------------------------------

func _check_judge() -> void:
	var judge: OrderJudge = client.judge
	var economy: EconomyConfig = judge.economy
	var top: int = economy.max_stars()
	var first: OrderTemplate = _order(ORDER_FTUE_1)
	var herb: Dictionary = judge.judge(first, _mix([LIFE_HERB]))
	_check("оценка: шалфей на бальзам — эффект, 3 ★, сила 2 ★, чистота 100 %, не безупречно",
			_effect(herb) and _stars(herb) == top and int(herb[OrderJudge.KEY_STRENGTH_STARS]) == 2
			and is_equal_approx(float(herb[OrderJudge.KEY_PURITY]), 1.0) and not bool(herb[OrderJudge.KEY_FLAWLESS]))
	var double: Dictionary = judge.judge(first, _mix([LIFE_HERB, LIFE_HERB]))
	_check("два шалфея — безупречно (сила и чистота на максимуме)", _stars(double) == top
			and bool(double[OrderJudge.KEY_FLAWLESS]))
	_check("репутация: звёзды, за «безупречно» — бонус", judge.reputation_for(herb) == top
			and judge.reputation_for(double) == top + economy.flawless_reputation_bonus)
	var wrong: Dictionary = judge.judge(first, _mix([HEAT_FLOWER]))
	_check("огнецвет на бальзам — неверный эффект: 0 ★, не хватает жизни, 0 монет, 0 репутации",
			not _effect(wrong) and _stars(wrong) == 0 and wrong[OrderJudge.KEY_MISSING] == [LIFE]
			and judge.pay_for(first, wrong, 1, 1.0) == 0 and judge.reputation_for(wrong) == 0)
	var trace: Dictionary[StringName, float] = {LIFE: economy.significance_threshold * 0.5}
	_check("след жизни ниже порога значимости — эффекта нет", not _effect(judge.judge(first, trace)))
	var empty: Dictionary = judge.judge(first, {})
	_check("пустая смесь — эффекта нет, чистота 0", not _effect(empty) and is_zero_approx(float(empty[OrderJudge.KEY_PURITY])))
	var weak: Dictionary[StringName, float] = {LIFE: economy.strength_thresholds[0]}
	var weak_verdict: Dictionary = judge.judge(_order(ORDER_FTUE_2), weak)
	_check("сила 1 ★ на заказ «сила 2» — 2 ★, промах по силе", _effect(weak_verdict) and _stars(weak_verdict) == 2
			and not bool(weak_verdict[OrderJudge.KEY_STRENGTH_OK]) and bool(weak_verdict[OrderJudge.KEY_PURITY_OK]))
	var heat: Dictionary = judge.judge(_order(ORDER_FTUE_4), _mix([HEAT_FLOWER]))
	_check("огнецвет на «чистый жар» (чистота 3) — 2/3 жара, чистота 1 ★, итог 2 ★",
			_stars(heat) == 2 and int(heat[OrderJudge.KEY_PURITY_STARS]) == 1 and not bool(heat[OrderJudge.KEY_PURITY_OK]))
	var partial: float = economy.extraction(GRIND_COARSE)
	var edge: Dictionary = judge.judge(_order(ORDER_FTUE_5), _mix([LIFE_HERB, HEAT_FLOWER], partial))
	_check("ровно 4 доли из 5 при неполном извлечении — чистота 2 ★, не 1", int(edge[OrderJudge.KEY_PURITY_STARS]) == 2
			and _stars(edge) == 2)
	# Жизнь значима, но слабее 1 ★ силы, и кислоты больше, чем жизни: ни сила, ни чистота — 1 ★.
	var faint: float = (economy.significance_threshold + economy.strength_thresholds[0]) * 0.5
	var one_star: Dictionary = judge.judge(first, {LIFE: faint, ACID: economy.strength_thresholds[0]})
	var pay_one: int = judge.pay_for(first, one_star, 1, 1.0)
	var pay_three: int = judge.pay_for(first, herb, 1, 1.0)
	var pay_flawless: int = judge.pay_for(first, double, 1, 1.0)
	_check("оплата растёт: 1 ★ < 3 ★ < «безупречно» (%d < %d < %d)" % [pay_one, pay_three, pay_flawless],
			_stars(one_star) == 1 and 0 < pay_one and pay_one < pay_three and pay_three < pay_flawless
			and pay_three >= first.base_pay)


# --- кто придёт (OrderDesk.pick) -----------------------------------------------------------------------------

func _check_pick() -> void:
	var first: Dictionary = desk.pick()
	_check("новая игра: первым — обучающий заказ 1 у пекарши", _is_pick(first, ORDER_FTUE_1, true)
			and first[OrderDesk.PICK_CLIENT] == desk.ftue_clients[0])
	GameState.ftue_step = 1
	_check("шаг обучения 1 — обучающий заказ 2", _is_pick(desk.pick(), ORDER_FTUE_2, true))
	GameState.ftue_step = desk.ftue_limit
	var all_free: bool = true
	for i: int in PICK_TRIES:
		var entry: Dictionary = desk.pick()
		if entry.is_empty() or bool(entry[OrderDesk.PICK_FTUE]) \
				or not _is_free_order(entry[OrderDesk.PICK_ORDER] as OrderTemplate):
			all_free = false
	_check("после обучения — обычные заказы пекарши своего ранга, решаемые стартовой полкой", all_free)
	GameState.current_order = {GameState.ORDER_CLIENT: String(desk.free_client.id),
			GameState.ORDER_TEMPLATE: String(ORDER_FREE)}
	_check("незакрытый заказ из сохранения — тот же заказ, не обучающий", _is_pick(desk.pick(), ORDER_FREE, false))
	GameState.ftue_step = 0
	GameState.current_order = {GameState.ORDER_CLIENT: String(desk.free_client.id),
			GameState.ORDER_TEMPLATE: String(ORDER_FTUE_1)}
	_check("сохранённый обучающий заказ остаётся обучающим", _is_pick(desk.pick(), ORDER_FTUE_1, true))
	GameState.current_order = {GameState.ORDER_CLIENT: MISSING_ID, GameState.ORDER_TEMPLATE: MISSING_ID}
	_check("в сохранении неизвестный заказ — приходит новый", _is_pick(desk.pick(), ORDER_FTUE_1, true))
	GameState.current_order = {}


# --- живой заказ -------------------------------------------------------------------------------------------------

func _check_arrival() -> void:
	var first: OrderTemplate = _order(ORDER_FTUE_1)
	_check("до start() у прилавка никого", not client.is_present() and not client.drop_target.enabled)
	desk.start()
	_check("start(): клиент идёт, заказ сразу записан в GameState", client.state_machine.is_in(Client.STATE_ARRIVING)
			and _saved_order_id() == first.id and _started == [first.id])
	_check("пока идёт — баночку не принять (цель выключена)", not client.drop_target.enabled)
	desk.start()
	_check("повторный start() второго клиента не зовёт", _started.size() == 1)
	await _wait(client.walk_sec)
	_check("пришёл: ждёт, цель включена, пузырь показан", client.is_waiting() and client.drop_target.enabled
			and client.bubble.visible and _arrivals == 1)
	_check("пузырь: иконок свойства = нужные × сила, звёзд чистоты = сколько просит", _bubble_matches(first))
	_check("реплика заказа видна", client.line_label.visible and client.line_label.text == tr(first.line_key)
			and not client.line_label.text.is_empty())
	_check("фраза — внутри пузыря, над иконками", _line_inside_bubble())
	_check("фон пузыря — по содержимому, кончик хвостика в начале узла Bubble", _bubble_fits())
	_check("пузырь не наезжает на ступку: кончик хвостика выше пестика", client.bubble.global_position.y < _pestle_top())
	_check("портрет дышит: шейдер Breathe на Portrait", _breathes())


func _check_empty_vessel() -> void:
	_client_refusals.clear()
	mortar.vessel_drag.drop_on(client.drop_target)
	_check("пустую баночку не берут — отказ «kind», клиент ждёт", _client_refusals == [Client.REASON_KIND]
			and client.is_waiting() and _handed.is_empty())
	await _wait(mortar.vessel_drag.return_sec)
	_check("баночка вернулась в чашу спрятанной", not mortar.vessel.visible
			and _vessel_at_home())


func _check_coarse_refused() -> void:
	await _drop_from_shelf(LIFE_HERB)
	_grind_to(GRIND_COARSE)
	_check("шалфей в ступке, помол крупный — Ground", mortar.items.size() == 1
			and mortar.state_machine.is_in(Mortar.STATE_GROUND))
	mortar.vessel_drag.select()
	_check("тап по чаше: в руке баночка со смесью и помолом ступки", mortar.vessel.visible
			and mortar.vessel.mixture == mortar.mixture() and is_equal_approx(mortar.vessel.grind, GRIND_COARSE))
	_check("баночка в руке — клиент подсвечен", client.drop_target.state == DropTarget.Highlight.AVAILABLE)
	_client_refusals.clear()
	var coins_before: int = GameState.coins
	mortar.vessel_drag.drop_on(client.drop_target)
	_check("обучение: помол не дошёл до «идеально» — отказ «grind»", _client_refusals == [Client.REASON_GRIND]
			and client.is_waiting())
	_check("после отказа смесь в ступке, монеты те же", mortar.items.size() == 1 and _handed.is_empty()
			and mortar.state_machine.is_in(Mortar.STATE_GROUND) and GameState.coins == coins_before)
	await _wait(mortar.vessel_drag.return_sec)
	_check("баночка вернулась, спряталась и опустела", not mortar.vessel.visible and not mortar.vessel.is_filled())


func _check_serve_first() -> void:
	var order: OrderTemplate = client.order
	var economy: EconomyConfig = client.judge.economy
	_grind_to(_perfect())
	var mixture: Dictionary[StringName, float] = mortar.mixture()
	var verdict: Dictionary = client.judge.judge(order, mixture)
	var pay: int = client.judge.pay_for(order, verdict, GameState.streak_3star + 1, client.data.pay_multiplier)
	var reputation: int = client.judge.reputation_for(verdict)
	var coins_before: int = GameState.coins
	var reputation_before: int = GameState.reputation
	var lands_before: int = hud.counter.lands
	var launched_before: int = hud.flight.launched
	mortar.vessel_drag.select()
	mortar.vessel_drag.drop_on(client.drop_target)
	_check("помол идеальный — клиент взял баночку с той же смесью", _handed.size() == 1 and _handed[0] == mixture
			and client.state_machine.is_in(Client.STATE_REACTING))
	_check("ступка опустела (Empty), монеты пока те же", mortar.items.is_empty()
			and mortar.state_machine.is_in(Mortar.STATE_EMPTY) and GameState.coins == coins_before)
	_check("пока реагирует — второй баночки не берёт (busy)", not client.drop_target.enabled
			and client.refusal_for(mortar.vessel) == Client.REASON_BUSY)
	await _wait(client.react_delay_sec)
	_check("клиент доволен: верный эффект, 3 ★", _served.size() == 1 and _stars(_served[0]) == economy.max_stars())
	_check("оплата по формуле: %d монет" % pay, _paid == [pay] and GameState.coins == coins_before + pay)
	_check("репутация +%d" % reputation, GameState.reputation == reputation_before + reputation)
	_check("обучение: шаг 1, заказ закрыт, серия 3 ★ = 1", GameState.ftue_step == 1
			and GameState.current_order.is_empty() and GameState.streak_3star == 1 and desk.served_count == 1)
	var sprites: int = hud.flight.sprites_for(pay)
	_check("из руки клиента летят %d монеток, число их ждёт" % sprites, hud.flight.launched - launched_before == sprites
			and hud.flight.flying_count > 0 and hud.counter.target_shown() < GameState.coins)
	var next_arrived: bool = await _wait_until(client.is_waiting, _next_client_sec())
	_check("монеты долетели: в счётчике столько же, сколько у игрока", hud.counter.lands - lands_before == sprites
			and hud.counter.shown == GameState.coins)
	_check("баночка долетела до клиента, спряталась и вернулась в чашу", not mortar.vessel.visible
			and _vessel_at_home())
	var second: OrderTemplate = _order(ORDER_FTUE_2)
	_check("клиент ушёл, через паузу пришёл с обучающим заказом 2", next_arrived and _left_count == 1
			and _arrivals == 2 and client.order == second and _saved_order_id() == second.id)
	_check("пузырь заказа 2: иконок по силе", _bubble_matches(second))


func _check_wrong_effect() -> void:
	await _drop_from_shelf(HEAT_FLOWER)
	_grind_to(_perfect())
	var coins_before: int = GameState.coins
	var step_before: int = GameState.ftue_step
	mortar.vessel_drag.select()
	mortar.vessel_drag.drop_on(client.drop_target)
	_check("огнецвет вместо бальзама: баночку взяли (помол идеальный), ступка пуста", _handed.size() == 2
			and mortar.items.is_empty())
	await _wait(client.react_delay_sec)
	_check("неверный эффект: клиент расстроен, монет нет", _refused.size() == 1 and not _effect(_refused[0])
			and _paid.size() == 1 and GameState.coins == coins_before)
	_check("заказ не закрыт: шаг обучения и заказ те же", GameState.ftue_step == step_before
			and _saved_order_id() == ORDER_FTUE_2)
	var waiting: bool = await _wait_until(client.is_waiting, client.react_sec + WAIT_SLACK_SEC)
	_check("клиент не ушёл и снова ждёт тот же заказ", waiting and _left_count == 1 and client.order.id == ORDER_FTUE_2
			and client.drop_target.enabled)


func _check_serve_flawless() -> void:
	var order: OrderTemplate = client.order
	await _drop_from_shelf(LIFE_HERB)
	await _drop_from_shelf(LIFE_HERB)
	_check("ячейка полки не пустеет: в ступке два шалфея", mortar.items.size() == 2)
	_grind_to(_perfect())
	var verdict: Dictionary = client.judge.judge(order, mortar.mixture())
	var pay: int = client.judge.pay_for(order, verdict, GameState.streak_3star + 1, client.data.pay_multiplier)
	var reputation: int = client.judge.reputation_for(verdict)
	var coins_before: int = GameState.coins
	var reputation_before: int = GameState.reputation
	_check("смесь двух шалфеев — безупречно", bool(verdict[OrderJudge.KEY_FLAWLESS]))
	mortar.vessel_drag.select()
	mortar.vessel_drag.drop_on(client.drop_target)
	await _wait(client.react_delay_sec)
	_check("безупречно: %d монет — больше базы %d (чаевые)" % [pay, order.base_pay], _paid.size() == 2
			and _paid[1] == pay and pay > order.base_pay and GameState.coins == coins_before + pay)
	_check("репутация +%d (звёзды и бонус)" % reputation, GameState.reputation == reputation_before + reputation)
	_check("обучение пройдено, серия 3 ★ = 2", GameState.ftue_step == desk.ftue_limit and GameState.streak_3star == 2)
	var next_arrived: bool = await _wait_until(client.is_waiting, _next_client_sec())
	_check("дальше — обычный заказ пекарши", next_arrived and client.data == desk.free_client
			and _is_free_order(client.order) and _saved_order_id() == client.order.id)


func _check_deny_coins() -> void:
	var denies_before: int = hud.counter.denies
	mortar.drop_refused.emit(Mortar.REASON_FULL)
	_check("ступка полна — счётчик монет молчит", hud.counter.denies == denies_before)
	mortar.drop_refused.emit(Mortar.REASON_COINS)
	_check("монет не хватает — счётчик вздрагивает (Workshop → Hud)", hud.counter.denies == denies_before + 1)


func _check_reset() -> void:
	var left_before: int = _left_count
	GameState.new_game()
	_check("новая игра: клиент уходит, счётчик сразу 0", client.state_machine.is_in(Client.STATE_LEAVING)
			and hud.counter.shown == GameState.coins)
	var back: bool = await _wait_until(func() -> bool: return _left_count > left_before and client.is_waiting(),
			client.walk_sec * 2.0 + desk.next_delay_sec + WAIT_SLACK_SEC)
	_check("…и приходит снова с обучающим заказом 1", back and client.order.id == ORDER_FTUE_1
			and _saved_order_id() == ORDER_FTUE_1)


# --- помощники -----------------------------------------------------------------------------------------------------

func _drop_from_shelf(id: StringName) -> void:
	var item: IngredientItem = shelf.slot_for(GameState.catalog.ingredient(id)).item
	var sec: float = item.draggable.fly_sec
	item.draggable.drop_on(mortar.drop_target)
	await _wait(sec)


## Помол «как пальцем»: жест начался → помол → жест кончился (ступка уходит в Ground).
func _grind_to(value: float) -> void:
	mortar.gesture.started.emit()
	mortar.set_grind(value, true)
	mortar.gesture.ended.emit(GESTURE_END)


func _vessel_at_home() -> bool:
	return mortar.vessel.global_position.is_equal_approx(mortar.to_global(_vessel_home))


func _perfect() -> float:
	var economy: EconomyConfig = mortar.economy
	return (economy.perfect_from + economy.perfect_to) * 0.5


## Свойства ингредиентов, сложенные с извлечением k.
func _mix(ids: Array[StringName], k: float = 1.0) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for id: StringName in ids:
		var item: IngredientData = GameState.catalog.ingredient(id)
		for property_id: StringName in item.properties:
			result[property_id] = result.get(property_id, 0.0) + item.properties[property_id] * k
	return result


func _order(id: StringName) -> OrderTemplate:
	return GameState.catalog.order(id)


func _saved_order_id() -> StringName:
	return StringName(str(GameState.current_order.get(GameState.ORDER_TEMPLATE, "")))


func _effect(verdict: Dictionary) -> bool:
	return bool(verdict[OrderJudge.KEY_EFFECT])


func _stars(verdict: Dictionary) -> int:
	return int(verdict[OrderJudge.KEY_STARS])


func _is_pick(entry: Dictionary, order_id: StringName, is_ftue: bool) -> bool:
	if entry.is_empty():
		return false
	var order: OrderTemplate = entry[OrderDesk.PICK_ORDER] as OrderTemplate
	return order != null and order.id == order_id and bool(entry[OrderDesk.PICK_FTUE]) == is_ftue


## Заказ свободного клиента: его ранга, с весом, все нужные свойства есть у открытых ингредиентов.
func _is_free_order(order: OrderTemplate) -> bool:
	if order == null or not desk.free_client.orders_for_rank(GameState.rank).has(order):
		return false
	var offered: Dictionary[StringName, bool] = {}
	for id: StringName in GameState.unlocked_ingredients:
		for property_id: StringName in GameState.catalog.ingredient(id).properties:
			offered[property_id] = true
	for property_id: StringName in order.required:
		if not offered.has(property_id):
			return false
	return true


func _bubble_matches(order: OrderTemplate) -> bool:
	return client.property_row.get_child_count() == order.required.size() * order.strength_req \
			and client.purity_row.get_child_count() == order.purity_req


## Сколько ждать следующего клиента после верного зелья: реакция, уход, пауза очереди, приход.
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


func _on_arrived() -> void:
	_arrivals += 1


func _on_left() -> void:
	_left_count += 1


func _on_served(verdict: Dictionary) -> void:
	_served.append(verdict)


func _on_refused(verdict: Dictionary) -> void:
	_refused.append(verdict)


func _on_client_drop_refused(reason: StringName) -> void:
	_client_refusals.append(reason)


func _on_order_started(_who: ClientData, order: OrderTemplate) -> void:
	_started.append(order.id)


func _on_order_paid(_order: OrderTemplate, _verdict: Dictionary, pay: int) -> void:
	_paid.append(pay)


func _on_handed_off(mixture: Dictionary[StringName, float]) -> void:
	_handed.append(mixture)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		print("  FAIL ", title)
		push_error("OrderCheck: не прошло — %s" % title)


## Фраза целиком в фоне пузыря и выше ряда свойств.
func _line_inside_bubble() -> bool:
	var back: Rect2 = client.bubble_back.get_global_rect()
	var line: Rect2 = client.line_label.get_global_rect()
	return back.encloses(line) and line.end.y <= client.property_row.get_global_rect().position.y


## Фон повторяет поля с содержимым, кончик хвостика — ровно в начале узла Bubble (ландшафт: хвостик справа внизу).
func _bubble_fits() -> bool:
	var content: Control = client.bubble_content
	return (client.bubble_back.size.is_equal_approx(content.size)
			and content.size.is_equal_approx(content.get_combined_minimum_size())
			and (content.position + content.size).is_equal_approx(client.tail_tip))


## Верх пестика в покое — по рамке его спрайта с учётом поворота.
func _pestle_top() -> float:
	for child: Node in mortar.pestle.get_children():
		var sprite: Sprite2D = child as Sprite2D
		if sprite != null:
			return (sprite.get_global_transform() * sprite.get_rect()).position.y
	return -INF


func _breathes() -> bool:
	var breath: ShaderMaterial = client.portrait.material as ShaderMaterial
	return (breath != null and breath.shader != null and breath.shader.resource_path.ends_with("breathe.gdshader")
			and float(breath.get_shader_parameter(&"lift_px")) > 0.0)


func _print_manual() -> void:
	print("--- Ручная проверка ---")
	print("1. После проверок приходит пекарша: в пузыре сверху фраза, под ней иконка жизни и кристалл чистоты;")
	print("   пузырь не задевает пестик. Пекарша еле заметно дышит: плечи и голова чуть поднимаются, лицо не плывёт.")
	print("2. Бросьте шалфей в ступку, мелите до зелёной зоны. Тап по чаше (или потяните) — в руке баночка мази,")
	print("   клиентка подсвечена.")
	print("3. Баночка крупного помола: клиентка качает головой, баночка возвращается в чашу, смесь на месте.")
	print("4. Идеальный помол: клиентка радуется, монеты вылетают из её руки и летят в счётчик, число растёт")
	print("   по мере прилёта.")
	print("5. Она уходит и через секунду приходит снова: бальзам покрепче, в пузыре две иконки.")
	print("6. Отдайте огнецвет: расстроится, монет нет, заказ остаётся, она снова ждёт.")
	print("7. Сузьте окно до портрета: клиентка сверху, пузырь справа, хвостик смотрит на неё, текст не зеркальный;")
	print("   монеты летят в счётчик в углу.")
	print("8. F5 (main.tscn): после экрана загрузки клиентка приходит сама.")
