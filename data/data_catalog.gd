## DataCatalog — все данные игры в одном ресурсе (data/catalog.tres).
## Сигналы: нет. Зависимости: все классы data/*.
## Сцены получают каталог через @export; поиск по id — линейный (данных десятки, не тысячи).
class_name DataCatalog
extends Resource

@export var properties: Array[PropertyData] = []
@export var ingredients: Array[IngredientData] = []
@export var recipes: Array[RecipeData] = []
@export var clients: Array[ClientData] = []
@export var tools: Array[ToolData] = []
@export var ranks: Array[RankData] = []
## Заказы первой сессии по порядку (GDD §9); какой клиент приходит — решает сценарий FTUE.
@export var ftue_orders: Array[OrderTemplate] = []
@export var economy: EconomyConfig
@export var daily_rewards: DailyRewardConfig


func property(id: StringName) -> PropertyData:
	for item: PropertyData in properties:
		if item.id == id:
			return item
	return null


func ingredient(id: StringName) -> IngredientData:
	for item: IngredientData in ingredients:
		if item.id == id:
			return item
	return null


func recipe(id: StringName) -> RecipeData:
	for item: RecipeData in recipes:
		if item.id == id:
			return item
	return null


## Рецепт для набора значимых свойств; null — «Странная смесь».
func recipe_for(significant: Array[StringName]) -> RecipeData:
	for item: RecipeData in recipes:
		if item.matches(significant):
			return item
	return null


func client(id: StringName) -> ClientData:
	for item: ClientData in clients:
		if item.id == id:
			return item
	return null


func tool(id: StringName) -> ToolData:
	for item: ToolData in tools:
		if item.id == id:
			return item
	return null


## Ранг для репутации: последний, чей порог достигнут.
func rank_for(reputation: int) -> RankData:
	var best: RankData = null
	for item: RankData in ranks:
		if reputation >= item.threshold and (best == null or item.threshold > best.threshold):
			best = item
	return best


## Индекс первого ранга (с него начинается новая игра).
func first_rank() -> int:
	var first: RankData = rank_for(0)
	return first.index if first != null else 0


## Ингредиенты новой игры: первого ранга, бесплатные и не редкие.
func starting_ingredients() -> Array[StringName]:
	var result: Array[StringName] = []
	var start: int = first_rank()
	for item: IngredientData in ingredients:
		if item.unlock_rank <= start and item.unlock_price == 0 and not item.is_rare:
			result.append(item.id)
	return result


## Что появляется на ранге: ингредиенты, покупки, клиенты (из их unlock_rank / min_rank).
func unlocks_for_rank(rank: int) -> Array[Resource]:
	var result: Array[Resource] = []
	for item: IngredientData in ingredients:
		if item.unlock_rank == rank:
			result.append(item)
	for item: ToolData in tools:
		if item.unlock_rank == rank:
			result.append(item)
	for item: ClientData in clients:
		if item.min_rank == rank:
			result.append(item)
	return result


## Шаблон заказа по id (у клиентов и в FTUE); null — такого нет (старое сохранение).
func order(id: StringName) -> OrderTemplate:
	for item: OrderTemplate in all_orders():
		if item.id == id:
			return item
	return null


## Все шаблоны заказов без повторов: у клиентов и в FTUE.
func all_orders() -> Array[OrderTemplate]:
	var result: Array[OrderTemplate] = []
	for item: ClientData in clients:
		for order: OrderTemplate in item.orders:
			if not result.has(order):
				result.append(order)
	for order: OrderTemplate in ftue_orders:
		if not result.has(order):
			result.append(order)
	return result
