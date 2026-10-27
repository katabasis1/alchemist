## OrderDesk — очередь заказов лавки, первая версия (S2.4): кто приходит и с чем, оплата и монеты.
## Кто следующий:
##   1) незакрытый заказ из сохранения — тот же клиент с тем же заказом (GDD §5.4, §11);
##   2) обучающие заказы по GameState.ftue_step — первые ftue_limit из DataCatalog.ftue_orders (S2.4: два, у пекарши;
##      третий — кузнец, ему нужны магазин и Отстойник), клиент — ftue_clients[шаг], иначе free_client;
##   3) дальше — заказы free_client: случайный по весу из orders_for_rank(ранг), только если все нужные свойства есть
##      у открытых ингредиентов; один и тот же шаблон два раза подряд не выпадает, если есть другой.
##   Полный генератор с проверкой решаемости — S5.2, подсказки обучения — S9.
## Клиент принял верное зелье → OrderJudge: оплата (серия 3★, множитель клиента) и репутация → GameState.finish_order
## одной записью → монеты летят из руки клиента в счётчик (Hud.fly_coins). Клиент ушёл → через next_delay_sec следующий.
## Сигналы: order_started(client, order); order_paid(order, verdict, pay).
## Методы: start() — первый клиент; started, served_count — для проверочной сцены; pick() — кто придёт следующим
##   (без побочных эффектов, кроме случайности).
## Зависимости: Client, OrderJudge, Hud, GameState (current_order, ftue_step, rank, streak_3star, unlocked_ingredients),
##   DataCatalog (через GameState.catalog), EventBus.game_ready, SaveService.is_loaded (сцену открыли после загрузки).
class_name OrderDesk
extends Node

signal order_started(client: ClientData, order: OrderTemplate)
signal order_paid(order: OrderTemplate, verdict: Dictionary, pay: int)

## Ключи словаря, который возвращает pick().
const PICK_CLIENT: StringName = &"client"
const PICK_ORDER: StringName = &"order"
const PICK_FTUE: StringName = &"ftue"

@export var client: Client
@export var judge: OrderJudge
@export var hud: Hud
## Сколько обучающих заказов в этой версии (DataCatalog.ftue_orders[0 … ftue_limit−1]).
@export var ftue_limit: int = 2
## Клиент обучающего заказа по шагу FTUE (GDD §9); пусто или null — free_client.
@export var ftue_clients: Array[ClientData] = []
## Кто приходит после обучения (S2.4 — только пекарша).
@export var free_client: ClientData
## Пауза между уходом клиента и приходом следующего.
@export var next_delay_sec: float = 1.0
## Начать по EventBus.game_ready (в лавке) или сразу, если сохранение уже загружено. Проверочные сцены (F6) сохранение
## не грузят и game_ready не шлют — там start() вызывают сами.
@export var start_on_game_ready: bool = true

var started: bool = false
var served_count: int = 0
var _order_is_ftue: bool = false
var _last_order_id: StringName = &""


func _ready() -> void:
	client.served.connect(_on_served)
	client.left.connect(_on_left)
	GameState.state_reset.connect(_on_state_reset)
	if start_on_game_ready:
		EventBus.game_ready.connect(start)
		if SaveService.is_loaded:
			start.call_deferred()


## Позвать первого клиента. Повторный вызов ничего не делает.
func start() -> void:
	if started:
		return
	started = true
	_call_next()


## Кто придёт следующим: {PICK_CLIENT, PICK_ORDER, PICK_FTUE}; пустой словарь — заказать нечего.
func pick() -> Dictionary:
	var catalog: DataCatalog = GameState.catalog
	var saved: Dictionary = _saved_order(catalog)
	if not saved.is_empty():
		return saved
	var step: int = GameState.ftue_step
	if step < mini(ftue_limit, catalog.ftue_orders.size()):
		return _pick_entry(_ftue_client(step), catalog.ftue_orders[step], true)
	if free_client == null:
		return {}
	var order: OrderTemplate = _weighted(_solvable(free_client.orders_for_rank(GameState.rank)))
	if order == null:
		return {}
	return _pick_entry(free_client, order, false)


func _call_next() -> void:
	var next: Dictionary = pick()
	if next.is_empty():
		push_warning("OrderDesk: заказать нечего — проверьте free_client и открытые ингредиенты")
		return
	var who: ClientData = next[PICK_CLIENT] as ClientData
	var order: OrderTemplate = next[PICK_ORDER] as OrderTemplate
	_order_is_ftue = bool(next[PICK_FTUE])
	_last_order_id = order.id
	GameState.start_order(who.id, order.id)
	client.arrive(who, order)
	order_started.emit(who, order)


func _on_served(verdict: Dictionary) -> void:
	var order: OrderTemplate = client.order
	var stars: int = int(verdict[OrderJudge.KEY_STARS])
	var three_stars: bool = stars >= GameState.catalog.economy.pay_by_stars.size()
	var streak: int = GameState.streak_3star + 1 if three_stars else 0
	var multiplier: float = client.data.pay_multiplier if client.data != null else 1.0
	var pay: int = judge.pay_for(order, verdict, streak, multiplier)
	GameState.finish_order(pay, judge.reputation_for(verdict), three_stars, _order_is_ftue)
	_order_is_ftue = false
	served_count += 1
	if hud != null:
		hud.fly_coins(client.coin_point(), pay)
	order_paid.emit(order, verdict, pay)


func _on_left() -> void:
	if started:
		get_tree().create_timer(next_delay_sec).timeout.connect(_call_next_if_free)


## Таймер мог пережить сброс игры: зовём, только если у прилавка никого.
func _call_next_if_free() -> void:
	if started and not client.is_present():
		_call_next()


## Новая игра или загрузка: клиент уходит, следующий придёт по новым данным.
func _on_state_reset() -> void:
	if not started:
		return
	_order_is_ftue = false
	if client.is_present():
		client.leave()
	else:
		_call_next()


func _saved_order(catalog: DataCatalog) -> Dictionary:
	if GameState.current_order.is_empty():
		return {}
	var who: ClientData = catalog.client(StringName(str(GameState.current_order.get(GameState.ORDER_CLIENT, ""))))
	var order: OrderTemplate = catalog.order(StringName(str(GameState.current_order.get(GameState.ORDER_TEMPLATE, ""))))
	if who == null or order == null:
		return {}
	var step: int = GameState.ftue_step
	var is_ftue: bool = step < catalog.ftue_orders.size() and catalog.ftue_orders[step] == order
	return _pick_entry(who, order, is_ftue)


func _pick_entry(who: ClientData, order: OrderTemplate, is_ftue: bool) -> Dictionary:
	if who == null or order == null:
		return {}
	return {PICK_CLIENT: who, PICK_ORDER: order, PICK_FTUE: is_ftue}


func _ftue_client(step: int) -> ClientData:
	if step < ftue_clients.size() and ftue_clients[step] != null:
		return ftue_clients[step]
	return free_client


## Заказы, у которых каждое нужное свойство есть хотя бы у одного открытого ингредиента.
func _solvable(orders: Array[OrderTemplate]) -> Array[OrderTemplate]:
	var offered: Dictionary[StringName, bool] = {}
	for id: StringName in GameState.unlocked_ingredients:
		var item: IngredientData = GameState.catalog.ingredient(id)
		if item == null:
			continue
		for property: StringName in item.properties:
			offered[property] = true
	var result: Array[OrderTemplate] = []
	for order: OrderTemplate in orders:
		var ok: bool = true
		for property: StringName in order.required:
			if not offered.has(property):
				ok = false
				break
		if ok:
			result.append(order)
	return result


## Случайный по весу; прошлый заказ — только если других нет.
func _weighted(orders: Array[OrderTemplate]) -> OrderTemplate:
	var pool: Array[OrderTemplate] = []
	for order: OrderTemplate in orders:
		if order.id != _last_order_id:
			pool.append(order)
	if pool.is_empty():
		pool = orders
	var total: float = 0.0
	for order: OrderTemplate in pool:
		total += order.weight
	if pool.is_empty() or total <= 0.0:
		return null
	var roll: float = randf() * total
	for order: OrderTemplate in pool:
		roll -= order.weight
		if roll <= 0.0:
			return order
	return pool.back()
