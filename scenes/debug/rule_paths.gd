## RulePaths — симулятор путей игрока для стенда правил (S3.3): ингредиенты в ступку, помол тапами до «идеально»,
## горелка по тикам решений игрока, слив целых слоёв Отстойника; итог — какой рецепт получился.
## Копия run_path и соседей из tools/alchemy/rules_model.py: меняется вместе с ними. Рецепт смеси узнаёт
## GrimoireRules.recognize — то же место, что у Гримуара.
## Только расчёт: статические функции без узлов и состояния; подключается через preload (без class_name), экземпляр
## не нужен. Случайное дробление тика берёт глобальный ГСЧ — зерно задаёт вызывающий (seed()).
## Сигналы: нет. Зависимости: AlchemyRules, GrimoireRules, DataCatalog, EconomyConfig, RecipeData (STEP_*, hint_steps).
extends RefCounted

## 1 тап = ¼ круга (GDD §3.3).
const TAP_CIRCLES: float = 0.25
## Игрок решает «держать / отпустить» горелку раз в четверть секунды.
const PLAYER_TICK: float = 0.25
## Дольше горелку не держат: путь не сработал.
const BURNER_LIMIT_SEC: float = 60.0
## Случайное дробление тика: от 1 до стольких разрезов.
const MAX_RANDOM_CUTS: int = 9
## Шаг-ингредиент — id ингредиента; шаг горелки — «burner_<низ>_<верх>» (RecipeData.STEP_BURNER_*).
const INGREDIENT_PREFIX: String = "ing_"
const BURNER_PREFIX: String = "burner_"
const BURNER_PARTS: int = 2
## Запасные пути из GDD §5.1 («или …») сверх RecipeData.hint_steps.
const EXTRA_PATHS: Dictionary = {
	&"warming_balm": [[&"ing_sage_bundle", &"ing_fire_bloom", RecipeData.STEP_MORTAR, RecipeData.STEP_BURNER_75_89]],
}
## Ключи отчётов.
const KEY_RECIPE: StringName = &"recipe"
const KEY_PATH: StringName = &"path"
const KEY_NOTES: StringName = &"notes"
const KEY_NOTE: StringName = &"note"
const KEY_ERROR: StringName = &"error"
const KEY_MIXTURE: StringName = &"mixture"
const KEY_SIGNIFICANT: StringName = &"significant"
const KEY_RESULT: StringName = &"result"
const KEY_OK: StringName = &"ok"
const KEY_TEMP: StringName = &"temp"
const KEY_LAYERS: StringName = &"layers"


## Пути всех рецептов каталога: подсказка рецепта и запасные пути. Отчёты — как у run_path.
static func all_paths(catalog: DataCatalog) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for recipe: RecipeData in catalog.recipes:
		reports.append(run_path(recipe, recipe.hint_steps, catalog))
		for steps: Array in EXTRA_PATHS.get(recipe.id, []):
			reports.append(run_path(recipe, steps, catalog))
	return reports


## Пройти путь игрока. Отчёт: KEY_RECIPE, KEY_PATH, KEY_NOTES (как шёл), KEY_MIXTURE, KEY_SIGNIFICANT,
## KEY_RESULT (id рецепта или &"" — «Странная смесь»), KEY_OK; при ошибке пути — KEY_ERROR и KEY_OK = false.
static func run_path(recipe: RecipeData, steps: Array, catalog: DataCatalog) -> Dictionary:
	var notes: PackedStringArray = []
	var report: Dictionary = {KEY_RECIPE: recipe.id, KEY_PATH: steps, KEY_NOTES: notes, KEY_OK: false}
	var ingredients: Array[IngredientData] = []
	for step: StringName in steps:
		if not String(step).begins_with(INGREDIENT_PREFIX):
			continue
		var item: IngredientData = catalog.ingredient(step)
		if item == null:
			report[KEY_ERROR] = "нет ингредиента %s" % step
			return report
		ingredients.append(item)
	if ingredients.size() > catalog.economy.mortar_slots:
		notes.append("ступка с третьим слотом")
	var mixture: Dictionary = {}
	for step: StringName in steps:
		if String(step).begins_with(INGREDIENT_PREFIX):
			continue
		var done: Dictionary = _step(step, mixture, ingredients, recipe.id, catalog)
		if done.has(KEY_ERROR):
			report[KEY_ERROR] = done[KEY_ERROR]
			return report
		mixture = done[KEY_MIXTURE]
		notes.append(String(done[KEY_NOTE]))
	report[KEY_NOTES] = notes
	return _finish_report(report, mixture, catalog)


## Помол тапами по ¼ круга, пока извлечение не станет полным (зона «идеально»): [помол, круги].
static func grind_to_perfect(ingredients: Array[IngredientData], economy: EconomyConfig) -> Array[float]:
	var grind: float = 0.0
	var circles: float = 0.0
	while AlchemyRules.extraction(grind, economy) < 1.0 and grind < 1.0:
		circles += TAP_CIRCLES
		grind = AlchemyRules.grind_after(grind, TAP_CIRCLES, ingredients, economy)
	var result: Array[float] = [grind, circles]
	return result


## Решения игрока у горелки по тикам: держать, пока T не выйдет за верх окна; как только T в окне и всё летучее
## с точкой не выше низа окна ушло — отпустить и ждать остывания. true — огонь держат весь тик.
static func burner_schedule(start: Dictionary, low: int, high: int, catalog: DataCatalog,
		economy: EconomyConfig) -> Array[bool]:
	var wanted_gone: Array[StringName] = []
	for property: PropertyData in catalog.properties:
		if property.evaporate_temp >= 0.0 and property.evaporate_temp <= low:
			wanted_gone.append(property.id)
	var schedule: Array[bool] = []
	var mixture: Dictionary = start
	var temp: float = economy.room_temp
	var elapsed: float = 0.0
	while elapsed < BURNER_LIMIT_SEC and not (temp >= low and not _has_any(mixture, wanted_gone)):
		var heating: bool = temp + economy.heat_rate * PLAYER_TICK <= high
		schedule.append(heating)
		mixture = AlchemyRules.heat(mixture, temp, heating, PLAYER_TICK, catalog, economy)
		temp = AlchemyRules.temp_after(temp, heating, PLAYER_TICK, economy)
		elapsed += PLAYER_TICK
	while temp > economy.room_temp:
		schedule.append(false)
		temp = AlchemyRules.temp_after(temp, false, PLAYER_TICK, economy)
	return schedule


## Прогнать расписание горелки. Каждый тик дробится на splits равных шагов, а при randomly — на 1…MAX_RANDOM_CUTS + 1
## случайных кусков. Итог: {KEY_MIXTURE, KEY_TEMP}.
static func run_burner(start: Dictionary, schedule: Array[bool], catalog: DataCatalog, economy: EconomyConfig,
		splits: int = 1, randomly: bool = false) -> Dictionary:
	var mixture: Dictionary = start
	var temp: float = economy.room_temp
	for heating: bool in schedule:
		for dt: float in (_random_steps() if randomly else _equal_steps(splits)):
			mixture = AlchemyRules.heat(mixture, temp, heating, dt, catalog, economy)
			temp = AlchemyRules.temp_after(temp, heating, dt, economy)
	return {KEY_MIXTURE: mixture, KEY_TEMP: temp}


## Отстоять и слить верхние k целых слоёв (k = 1…n−1), взять верх или низ: первый k, при котором смесь — нужный
## рецепт. Ни один не дал — первый срез (k = 1), а если слой один — смесь как есть. Итог: {KEY_MIXTURE, KEY_LAYERS}
## (KEY_LAYERS = 0 — рецепта не вышло).
static func settle_and_pick(mixture: Dictionary, keep_top: bool, recipe_id: StringName,
		catalog: DataCatalog) -> Dictionary:
	var count: int = AlchemyRules.layers(mixture, catalog).size()
	var fallback: Dictionary = mixture
	for k: int in range(1, count):
		var poured: float = AlchemyRules.height_above_layer(mixture, count - k, catalog, catalog.economy)
		var split: Dictionary = AlchemyRules.pour_top(mixture, poured, catalog, catalog.economy)
		var vessel: Dictionary = split[AlchemyRules.KEY_TOP if keep_top else AlchemyRules.KEY_BOTTOM]
		if k == 1:
			fallback = vessel
		if _recipe_id(vessel, catalog) == recipe_id:
			return {KEY_MIXTURE: vessel, KEY_LAYERS: k}
	return {KEY_MIXTURE: fallback, KEY_LAYERS: 0}


## Один шаг пути после ингредиентов: ступка, Отстойник или горелка. Итог: {KEY_MIXTURE, KEY_NOTE} или {KEY_ERROR}.
static func _step(step: StringName, mixture: Dictionary, ingredients: Array[IngredientData], recipe_id: StringName,
		catalog: DataCatalog) -> Dictionary:
	var economy: EconomyConfig = catalog.economy
	if step == RecipeData.STEP_MORTAR:
		var grind: Array[float] = grind_to_perfect(ingredients, economy)
		return {KEY_MIXTURE: AlchemyRules.ground(ingredients, grind[0], economy),
				KEY_NOTE: "помол %.2f за %.2f круга" % [grind[0], grind[1]]}
	if step == RecipeData.STEP_SETTLER_TOP or step == RecipeData.STEP_SETTLER_BOTTOM:
		var picked: Dictionary = settle_and_pick(mixture, step == RecipeData.STEP_SETTLER_TOP, recipe_id, catalog)
		var layers: int = int(picked[KEY_LAYERS])
		return {KEY_MIXTURE: picked[KEY_MIXTURE],
				KEY_NOTE: "слить %d верхн. слоя" % layers if layers > 0 else "ни один срез не дал рецепт"}
	var window: Array[int] = _burner_window(step)
	if window.is_empty():
		return {KEY_ERROR: "неизвестный шаг %s" % step}
	var schedule: Array[bool] = burner_schedule(mixture, window[0], window[1], catalog, economy)
	var heated: Dictionary = run_burner(mixture, schedule, catalog, economy)
	return {KEY_MIXTURE: heated[KEY_MIXTURE], KEY_NOTE: "горелка %.2f с" % (schedule.size() * PLAYER_TICK)}


## Окно горелки из шага «burner_<низ>_<верх>»: [низ, верх]; не шаг горелки — пусто.
static func _burner_window(step: StringName) -> Array[int]:
	var result: Array[int] = []
	var text: String = String(step)
	if not text.begins_with(BURNER_PREFIX):
		return result
	var parts: PackedStringArray = text.trim_prefix(BURNER_PREFIX).split("_")
	if parts.size() != BURNER_PARTS or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return result
	result.append(parts[0].to_int())
	result.append(parts[1].to_int())
	return result


static func _finish_report(report: Dictionary, mixture: Dictionary, catalog: DataCatalog) -> Dictionary:
	var found: StringName = _recipe_id(mixture, catalog)
	report[KEY_MIXTURE] = mixture
	report[KEY_SIGNIFICANT] = AlchemyRules.significant(mixture, catalog.economy)
	report[KEY_RESULT] = found
	report[KEY_OK] = found == report[KEY_RECIPE]
	return report


## id рецепта смеси; «Странная смесь» — &"".
static func _recipe_id(mixture: Dictionary, catalog: DataCatalog) -> StringName:
	var recipe: RecipeData = GrimoireRules.recognize(mixture, catalog)
	return recipe.id if recipe != null else &""


static func _has_any(mixture: Dictionary, ids: Array[StringName]) -> bool:
	for property_id: StringName in ids:
		if mixture.has(property_id):
			return true
	return false


static func _equal_steps(splits: int) -> Array[float]:
	var result: Array[float] = []
	for _i: int in splits:
		result.append(PLAYER_TICK / splits)
	return result


## Тик, разрезанный в случайных точках: куски по возрастанию разрезов, в сумме PLAYER_TICK.
static func _random_steps() -> Array[float]:
	var cuts: Array[float] = []
	for _i: int in randi_range(1, MAX_RANDOM_CUTS):
		cuts.append(randf() * PLAYER_TICK)
	cuts.sort()
	var result: Array[float] = []
	var previous: float = 0.0
	for cut: float in cuts:
		result.append(cut - previous)
		previous = cut
	result.append(PLAYER_TICK - previous)
	return result
