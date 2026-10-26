## DataCheck — проверка данных игры в Godot (F6 на этой сцене), пока у агента нет движка.
## Проверяет: что все .tres каталога грузятся (типизированные массивы и словари), что ссылки
## между данными целы, и толкование чисел EconomyConfig (звёзды, извлечение, оплата).
## Итог — в Output строкой «DATA: x/y». Та же согласованность проверяется без Godot:
## python tools/data/bootstrap_gdd_v1.py --check (решаемость заказов — там же).
## Сигналы: нет. Зависимости: DataCatalog (@export), GameState (тот же каталог).
extends Node

const EXPECTED_PROPERTIES: int = 6
const EXPECTED_INGREDIENTS: int = 12
const EXPECTED_RECIPES: int = 20
const EXPECTED_CLIENTS: int = 7
const EXPECTED_TOOLS: int = 6
const EXPECTED_RANKS: int = 5
const EXPECTED_FTUE: int = 5
const EPSILON: float = 0.001
## Пробные значения — из GDD §4, §5.1, §7.
const PROBE_INGREDIENT: StringName = &"ing_fire_bloom"
const PROBE_HEAT: float = 2.0
const PROBE_TOTAL: float = 3.0
const PROBE_PAIR: Array[StringName] = [&"heat", &"life"]
const PROBE_PAIR_RECIPE: StringName = &"warming_balm"
const PROBE_STRANGE: Array[StringName] = [&"acid", &"cold", &"sleep"]
const FIRST_STATION: StringName = &"settler"
const PROBE_CLIENT: StringName = &"baker"
const PROBE_RANK: int = 2
const PROBE_UNLOCKS: Array[StringName] = [&"ing_moon_moss", &"indicator_paper", &"guard"]
const PROBE_PAY_BASE: int = 100
const PROBE_STREAK: int = 2
## Ровно столько звёзд дали первые три заказа FTUE (GDD §9).
const FTUE_STARS: Array[int] = [3, 2, 2]
## Новая игра начинается с бесплатных ингредиентов первого ранга (GDD §4).
const STARTING_INGREDIENTS: Array[StringName] = [&"ing_sage_bundle", &"ing_fire_bloom"]

@export var catalog: DataCatalog

var _passed: int = 0
var _total: int = 0


func _ready() -> void:
	_check("каталог загружен", catalog != null and catalog.economy != null and catalog.daily_rewards != null)
	if catalog == null:
		_finish()
		return
	_check_properties()
	_check_ingredients()
	_check_recipes()
	_check_orders()
	_check_progression()
	_check_economy()
	_finish()


func _check_properties() -> void:
	var ranks: Array[int] = []
	for item: PropertyData in catalog.properties:
		if item != null and not ranks.has(item.density_rank):
			ranks.append(item.density_rank)
	_check("свойства: %d, плотность без повторов" % EXPECTED_PROPERTIES,
		catalog.properties.size() == EXPECTED_PROPERTIES and ranks.size() == EXPECTED_PROPERTIES)


func _check_ingredients() -> void:
	var ids_ok: bool = _unique_ids(catalog.ingredients)
	var keys_ok: bool = true
	for item: IngredientData in catalog.ingredients:
		for key: StringName in item.properties:
			keys_ok = keys_ok and catalog.property(key) != null and item.properties[key] > 0.0
	_check("ингредиенты: %d, id без повторов" % EXPECTED_INGREDIENTS,
		catalog.ingredients.size() == EXPECTED_INGREDIENTS and ids_ok)
	_check("свойства ингредиентов существуют", keys_ok)
	var probe: IngredientData = catalog.ingredient(PROBE_INGREDIENT)
	_check("типизированный словарь читается", probe != null
		and is_equal_approx(probe.amount(&"heat"), PROBE_HEAT) and is_equal_approx(probe.total(), PROBE_TOTAL))


func _check_recipes() -> void:
	var sets_ok: bool = true
	var steps_ok: bool = true
	for i: int in catalog.recipes.size():
		var recipe: RecipeData = catalog.recipes[i]
		for j: int in range(i + 1, catalog.recipes.size()):
			sets_ok = sets_ok and not catalog.recipes[j].matches(recipe.property_set)
		for key: StringName in recipe.property_set:
			sets_ok = sets_ok and catalog.property(key) != null
		for step: StringName in recipe.hint_steps:
			var ing: IngredientData = catalog.ingredient(step)
			if ing != null:
				steps_ok = steps_ok and ing.unlock_rank <= recipe.tier
			else:
				steps_ok = steps_ok and RecipeData.STATION_STEPS.has(step)
	_check("рецепты: %d, наборы без повторов" % EXPECTED_RECIPES,
		catalog.recipes.size() == EXPECTED_RECIPES and _unique_ids(catalog.recipes) and sets_ok)
	_check("шаги подсказок известны и открыты к рангу рецепта", steps_ok)
	var pair: RecipeData = catalog.recipe_for(PROBE_PAIR)
	_check("recipe_for: порядок не важен, лишнее — «Странная смесь»",
		pair != null and pair.id == PROBE_PAIR_RECIPE and catalog.recipe_for(PROBE_STRANGE) == null)


func _check_orders() -> void:
	var orders_ok: bool = true
	var pay_ok: bool = true
	var economy: EconomyConfig = catalog.economy
	for order: OrderTemplate in catalog.all_orders():
		orders_ok = orders_ok and catalog.recipe_for(order.required) != null \
			and order.strength_req >= 1 and order.strength_req <= economy.max_stars() \
			and order.purity_req >= 1 and order.purity_req <= economy.max_stars()
		if order.weight > 0.0:
			pay_ok = pay_ok and order.base_pay == economy.base_pay_for(
				order.required.size(), order.strength_req, order.purity_req)
	var clients_ok: bool = _unique_ids(catalog.clients)
	for client: ClientData in catalog.clients:
		clients_ok = clients_ok and not client.orders.is_empty()
	_check("клиенты: %d, у каждого есть заказы" % EXPECTED_CLIENTS,
		catalog.clients.size() == EXPECTED_CLIENTS and clients_ok)
	_check("каждый заказ — известный рецепт, звёзды в пределах", orders_ok)
	_check("база заказов = формула GDD §5.3 (кроме FTUE)", pay_ok)
	_check("FTUE: %d заказов вне генератора" % EXPECTED_FTUE, catalog.ftue_orders.size() == EXPECTED_FTUE
		and catalog.ftue_orders.all(func(o: OrderTemplate) -> bool: return o.weight == 0.0))
	var baker: ClientData = catalog.client(PROBE_CLIENT)
	_check("портрет без эмоции — нейтральный", baker != null and baker.portrait_neutral != null
		and baker.portrait(ClientData.Mood.HAPPY) == baker.portrait_neutral)


func _check_progression() -> void:
	var rising: bool = true
	for i: int in range(1, catalog.ranks.size()):
		rising = rising and catalog.ranks[i].threshold > catalog.ranks[i - 1].threshold
	var last: RankData = catalog.ranks.back() as RankData
	_check("ранги: %d, пороги растут" % EXPECTED_RANKS, catalog.ranks.size() == EXPECTED_RANKS and rising)
	_check("rank_for: границы порогов", catalog.rank_for(0) == catalog.ranks[0]
		and catalog.rank_for(catalog.ranks[1].threshold - 1) == catalog.ranks[0]
		and catalog.rank_for(last.threshold) == last)
	var unlocked: Array[StringName] = []
	for item: Resource in catalog.unlocks_for_rank(PROBE_RANK):
		unlocked.append(item.get(&"id"))
	_check("unlocks_for_rank выводится из данных", PROBE_UNLOCKS.all(func(id: StringName) -> bool: return unlocked.has(id)))
	_check("GameState: тот же каталог, старт из данных", GameState.catalog == catalog
		and catalog.first_rank() == catalog.ranks[0].index and catalog.starting_ingredients() == STARTING_INGREDIENTS)
	_check("покупки: %d, id без повторов" % EXPECTED_TOOLS,
		catalog.tools.size() == EXPECTED_TOOLS and _unique_ids(catalog.tools))
	var daily: DailyRewardConfig = catalog.daily_rewards
	_check("награды: дни совпадают, кристалл — редкий ингредиент", daily.days() > 0
		and daily.crystals.size() == daily.days() and daily.crystal_item != null and daily.crystal_item.is_rare
		and daily.coins_for(daily.days()) == daily.coins_for(0))


func _check_economy() -> void:
	var e: EconomyConfig = catalog.economy
	var first: float = e.strength_thresholds[0]
	_check("звёзды силы и чистоты по порогам", e.strength_stars(first - EPSILON) == 0
		and e.strength_stars(first) == 1 and e.strength_stars(e.strength_thresholds.back() + first) == e.max_stars()
		and e.purity_stars(e.purity_thresholds[1] - EPSILON) == 1 and e.purity_stars(e.purity_thresholds.back()) == e.max_stars()
		and e.is_significant(e.significance_threshold) and not e.is_significant(e.significance_threshold - EPSILON))
	var middle: float = (e.perfect_from + e.perfect_to) * 0.5
	_check("извлечение: пол, «идеально», перетёр", is_equal_approx(e.extraction(0.0), e.extraction_floor)
		and is_equal_approx(e.extraction(middle), 1.0)
		and is_equal_approx(e.extraction(1.0), 1.0 - e.overgrind_slope * (1.0 - e.perfect_to))
		and e.grind_per_circle(IngredientData.Hardness.HARD) < e.grind_per_circle(IngredientData.Hardness.SOFT))
	var expected: int = roundi(PROBE_PAY_BASE * (1.0 + e.streak_tip_step * PROBE_STREAK + e.flawless_tip))
	_check("оплата: чаевые и неверный эффект", e.payment(PROBE_PAY_BASE, e.max_stars(), true, PROBE_STREAK, 1.0) == expected
		and e.payment(PROBE_PAY_BASE, 0, true, PROBE_STREAK, 1.0) == 0)
	var earned: int = 0
	for i: int in FTUE_STARS.size():
		earned += e.payment(catalog.ftue_orders[i].base_pay, FTUE_STARS[i], false, 0, 1.0)
	var station: ToolData = catalog.tool(FIRST_STATION)
	_check("FTUE: трёх заказов хватает на Отстойник (GDD §9)", station != null and earned >= station.price)


func _unique_ids(items: Array) -> bool:
	var seen: Array[StringName] = []
	for item: Resource in items:
		if item == null:
			return false
		var id: StringName = item.get(&"id")
		if id == &"" or seen.has(id):
			return false
		seen.append(id)
	return true


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  [OK] ", title)
	else:
		push_error("DATA: не прошло — " + title)
		print("  [!!] ", title)


func _finish() -> void:
	print("DATA: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])
