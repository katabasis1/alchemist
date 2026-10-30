## AlchemyRules — правила алхимии (GDD §3): смесь, раскрытие помолом, отстаивание по плотности, нагрев и летучесть.
## Только расчёт: статические чистые функции, без узлов и без состояния — экземпляр не нужен (AlchemyRules.total(…)).
## Детерминированно: одинаковый вход даёт одинаковый выход, включая порядок ключей. Нагрев и слив считаются точными
## формулами, поэтому итог не зависит от частоты кадров: шаг dt можно дробить как угодно (с точностью до округления).
## Смесь — словарь «id свойства → доли» (GDD §3.2). Функции принимают любой Dictionary (и нетипизированный: {} из
## проверок), а возвращают Dictionary[StringName, float] без нулевых долей — пустой словарь значит «пусто».
## Отстоянная колба (GDD §3.4): слои снизу вверх по PropertyData.density_rank; толщина слоя пропорциональна долям, но
## не меньше EconomyConfig.min_layer_height; все слои вместе — столб высотой 1. Слив сверху на высоту h (доля столба)
## забирает из каждого слоя ту часть, которую h накрыла. Слив считается от смеси на момент отстаивания и всей слитой
## высоты: сколькими удержаниями её слили — неважно.
## Срез (S4.2): риски на границах слоёв, примесь среза (доля чужих слоёв в испорченном сосуде) и чистые полосы
## шкалы среза, где примесь не больше EconomyConfig.clean_cut_admixture. Хвост струи по времени (pour_tail_after) и
## что ушло между двумя высотами слива (pour_between) — для колбы, которая сливает по кадрам.
## Горелка: температура растёт на heat_rate, пока огонь держат, и падает на cool_rate до room_temp, когда отпустили;
## пока T не ниже точки свойства, оно уходит паром (evaporate_rate доли/с) или сгорает (burn_rate доли/с).
## Кто пользуется: ступка (помол и смесь), OrderJudge (значимость, сила, чистота, «безупречно»), отстойник и горелка (S4),
## распознавание рецептов (S3.2), стенд проверок (S3.3). Эталон на Python — tools/alchemy/rules_model.py:
## правило меняется в обоих местах сразу.
## Сигналы: нет. Зависимости: EconomyConfig (порог значимости, звёзды, помол, извлечение, слив, чистый срез, горелка),
##   PropertyData (плотность, точки испарения и сгорания), IngredientData (доли, твёрдость), DataCatalog (свойство по id).
class_name AlchemyRules
extends RefCounted

## Допуск сравнений с порогами (4 доли из 5 — ровно 80 %, а не 79,999…) и доля, которую считаем нулём.
const EPSILON: float = 0.0001
## Ключи результата pour_top: что ушло в Приёмник (верх) и что осталось в Отстойнике (низ).
const KEY_TOP: StringName = &"top"
const KEY_BOTTOM: StringName = &"bottom"


# --- Смесь (GDD §3.2) ---------------------------------------------------------------------------------------------

## Сумма долей всех свойств.
static func total(mixture: Dictionary) -> float:
	var sum: float = 0.0
	for property_id: StringName in mixture:
		sum += float(mixture[property_id])
	return sum


## Доли свойства; 0 — свойства в смеси нет.
static func amount(mixture: Dictionary, property_id: StringName) -> float:
	return float(mixture.get(property_id, 0.0))


## Копия без нулевых и отрицательных долей (не больше EPSILON), порядок ключей тот же.
static func cleaned(mixture: Dictionary) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for property_id: StringName in mixture:
		var value: float = float(mixture[property_id])
		if value > EPSILON:
			result[property_id] = value
	return result


## Слить две смеси (струя в непустой Приёмник, содержимое двух сосудов). Сначала ключи a, потом новые из b.
static func combine(a: Dictionary, b: Dictionary) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for property_id: StringName in a:
		result[property_id] = float(a[property_id])
	for property_id: StringName in b:
		result[property_id] = result.get(property_id, 0.0) + float(b[property_id])
	return cleaned(result)


## Все доли × factor.
static func scaled(mixture: Dictionary, factor: float) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for property_id: StringName in mixture:
		result[property_id] = float(mixture[property_id]) * factor
	return cleaned(result)


## Свойство «есть», если доли не меньше порога значимости; иначе это след (GDD §3.2).
static func is_present(value: float, economy: EconomyConfig) -> bool:
	return economy.is_significant(value + EPSILON)


## Значимые свойства в порядке ключей смеси. По этому набору узнают рецепт (DataCatalog.recipe_for, S3.2).
static func significant(mixture: Dictionary, economy: EconomyConfig) -> Array[StringName]:
	var result: Array[StringName] = []
	for property_id: StringName in mixture:
		if is_present(float(mixture[property_id]), economy):
			result.append(property_id)
	return result


## Следы: есть в смеси, но ниже порога значимости. На эффект не влияют, чистоту снижают.
static func traces(mixture: Dictionary, economy: EconomyConfig) -> Array[StringName]:
	var result: Array[StringName] = []
	for property_id: StringName in mixture:
		var value: float = float(mixture[property_id])
		if value > EPSILON and not is_present(value, economy):
			result.append(property_id)
	return result


## Звёзды силы для доли свойства (0…3).
static func strength_stars(value: float, economy: EconomyConfig) -> int:
	return economy.strength_stars(value + EPSILON)


## Чистота: доли нужных свойств / доли всех (0…1). Пустая смесь — 0.
static func purity(mixture: Dictionary, wanted: Array[StringName]) -> float:
	var sum: float = total(mixture)
	if sum <= 0.0:
		return 0.0
	var good: float = 0.0
	for property_id: StringName in wanted:
		good += amount(mixture, property_id)
	return good / sum


## Звёзды чистоты (0…3).
static func purity_stars(value: float, economy: EconomyConfig) -> int:
	return economy.purity_stars(value + EPSILON)


## Звёзды силы самого слабого из нужных свойств (0…3): по нему судят «Силу» (GDD §5.3). Нужного нет — 0; пустой
## список — 0 (нечего оценивать).
static func weakest_stars(mixture: Dictionary, wanted: Array[StringName], economy: EconomyConfig) -> int:
	if wanted.is_empty():
		return 0
	var weakest: int = economy.max_stars()
	for property_id: StringName in wanted:
		weakest = mini(weakest, strength_stars(amount(mixture, property_id), economy))
	return weakest


## «Безупречно» (GDD §5.3): сила ★★★ у всех нужных свойств и чистота ★★★ (≥ 95 %). Одно определение на всю игру:
## им пользуются и оценка заказа (OrderJudge), и Гримуар (GrimoireRules, золотая страница).
static func is_flawless(weakest: int, purity_stars_value: int, economy: EconomyConfig) -> bool:
	var top: int = economy.max_stars()
	return weakest >= top and purity_stars_value >= top


# --- Помол (GDD §3.3, Ступка) -------------------------------------------------------------------------------------

## Самый твёрдый ингредиент: по нему растёт помол.
static func hardest(ingredients: Array[IngredientData]) -> IngredientData.Hardness:
	var result: IngredientData.Hardness = IngredientData.Hardness.SOFT
	for item: IngredientData in ingredients:
		if item != null and item.hardness > result:
			result = item.hardness
	return result


## Прирост помола за полный круг; пустая ступка не мелется.
static func grind_per_circle(ingredients: Array[IngredientData], economy: EconomyConfig) -> float:
	if ingredients.is_empty():
		return 0.0
	return economy.grind_per_circle(hardest(ingredients))


## Помол после circles кругов (0…1: на 1 шкала стоит).
static func grind_after(grind: float, circles: float, ingredients: Array[IngredientData],
		economy: EconomyConfig) -> float:
	return clampf(grind + maxf(circles, 0.0) * grind_per_circle(ingredients, economy), 0.0, 1.0)


## Доля извлечения при помоле (0…1): крупно — меньше, «идеально» — всё, перетёр — снова меньше.
static func extraction(grind: float, economy: EconomyConfig) -> float:
	return economy.extraction(clampf(grind, 0.0, 1.0))


## Смесь из ингредиентов при доле извлечения k: свойства всех ингредиентов × k. Ключи — в порядке ингредиентов.
static func extract(ingredients: Array[IngredientData], k: float) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for item: IngredientData in ingredients:
		if item == null:
			continue
		for property_id: StringName in item.properties:
			result[property_id] = result.get(property_id, 0.0) + item.properties[property_id] * k
	return cleaned(result)


## Смесь, которую отдаёт ступка при помоле grind (GDD §3.3).
static func ground(ingredients: Array[IngredientData], grind: float,
		economy: EconomyConfig) -> Dictionary[StringName, float]:
	return extract(ingredients, extraction(grind, economy))


# --- Отстаивание (GDD §3.3 Отстойник, §3.4 плотность) -------------------------------------------------------------

## Слои колбы снизу вверх: свойства смеси по density_rank (1 — дно). Равные ранги — по имени id.
## Свойство, которого нет в каталоге, слоя не даёт и остаётся внизу (так быть не должно — предупреждение в Output).
static func layers(mixture: Dictionary, catalog: DataCatalog) -> Array[StringName]:
	var result: Array[StringName] = []
	for property_id: StringName in cleaned(mixture):
		var data: PropertyData = catalog.property(property_id)
		if data == null:
			push_warning("AlchemyRules: свойства %s нет в каталоге" % property_id)
			continue
		var at: int = result.size()
		while at > 0 and _lies_below(data, catalog.property(result[at - 1])):
			at -= 1
		result.insert(at, property_id)
	return result


## Толщины слоёв (доли столба, в сумме 1) в порядке layers(): пропорционально долям, но не тоньше min_layer_height.
## Тонкие слои поднимаются до минимума, остальные делят остаток по долям. Не влезает — все слои поровну.
static func layer_heights(mixture: Dictionary, catalog: DataCatalog, economy: EconomyConfig) -> Array[float]:
	var ids: Array[StringName] = layers(mixture, catalog)
	var heights: Array[float] = []
	var count: int = ids.size()
	if count == 0:
		return heights
	heights.resize(count)
	var floor_height: float = economy.min_layer_height
	if floor_height * count >= 1.0:
		heights.fill(1.0 / count)
		return heights
	var pinned: Array[bool] = []
	pinned.resize(count)
	pinned.fill(false)
	var changed: bool = true
	while changed:
		changed = false
		var free_height: float = 1.0
		var free_amount: float = 0.0
		for i: int in count:
			if pinned[i]:
				free_height -= floor_height
			else:
				free_amount += amount(mixture, ids[i])
		for i: int in count:
			if pinned[i]:
				heights[i] = floor_height
				continue
			heights[i] = free_height * amount(mixture, ids[i]) / free_amount
			if heights[i] < floor_height:
				pinned[i] = true
				changed = true
	return heights


## Слить сверху высоту poured (доля столба, 0…1). Результат: KEY_TOP — ушло в Приёмник, KEY_BOTTOM — осталось.
## Из слоя уходит доля, которую накрыла слитая высота (GDD §3.3). Порядок ключей — как в смеси.
static func pour_top(mixture: Dictionary, poured: float, catalog: DataCatalog, economy: EconomyConfig) -> Dictionary:
	var ids: Array[StringName] = layers(mixture, catalog)
	var heights: Array[float] = layer_heights(mixture, catalog, economy)
	var share: Dictionary[StringName, float] = {}
	var surface: float = 1.0
	var cut: float = 1.0 - clampf(poured, 0.0, 1.0)
	for i: int in range(ids.size() - 1, -1, -1):
		var bottom_edge: float = surface - heights[i]
		share[ids[i]] = clampf((surface - maxf(cut, bottom_edge)) / heights[i], 0.0, 1.0)
		surface = bottom_edge
	var top: Dictionary[StringName, float] = {}
	var bottom: Dictionary[StringName, float] = {}
	for property_id: StringName in mixture:
		var value: float = float(mixture[property_id])
		var part: float = share.get(property_id, 0.0)
		top[property_id] = value * part
		bottom[property_id] = value - value * part
	return {KEY_TOP: cleaned(top), KEY_BOTTOM: cleaned(bottom)}


## Сколько столба слить, чтобы ушли целиком слой index (0 — дно) и все слои над ним.
static func height_above_layer(mixture: Dictionary, index: int, catalog: DataCatalog,
		economy: EconomyConfig) -> float:
	var heights: Array[float] = layer_heights(mixture, catalog, economy)
	var result: float = 0.0
	for i: int in range(heights.size() - 1, -1, -1):
		if i < index:
			break
		result += heights[i]
	return result


## Скорость струи через held секунд удержания: сначала pour_speed_start, после разгона — pour_speed_full.
static func pour_rate(held: float, economy: EconomyConfig) -> float:
	return economy.pour_speed_start if held < economy.pour_ramp_time else economy.pour_speed_full


## Сколько столба сливается за held секунд одного удержания (без хвоста после отпускания).
static func pour_height(held: float, economy: EconomyConfig) -> float:
	var time: float = maxf(held, 0.0)
	var slow: float = minf(time, economy.pour_ramp_time)
	return economy.pour_speed_start * slow + economy.pour_speed_full * (time - slow)


## Хвост струи после отпускания: скорость спадает до нуля за pour_stop_time, ровно.
static func pour_tail(held: float, economy: EconomyConfig) -> float:
	return pour_rate(maxf(held, 0.0), economy) * economy.pour_stop_time * 0.5


## Сколько хвоста дотекло через since секунд после отпускания (0…pour_tail): скорость спадает ровно, поэтому
## r · (t − t² / 2T). Точная формула — колба досливает хвост по кадрам, и итог не зависит от шага.
static func pour_tail_after(held: float, since: float, economy: EconomyConfig) -> float:
	var stop: float = economy.pour_stop_time
	var rate: float = pour_rate(maxf(held, 0.0), economy)
	if stop <= 0.0:
		return 0.0
	var time: float = clampf(since, 0.0, stop)
	return rate * (time - time * time / (2.0 * stop))


## Что ушло в Приёмник, пока слитая высота росла от poured_from до poured_to (доли столба): разница pour_top.
## Так Приёмник, опустошённый посреди слива, получает только новое. Назад и за пределами столба — пусто.
static func pour_between(mixture: Dictionary, poured_from: float, poured_to: float, catalog: DataCatalog,
		economy: EconomyConfig) -> Dictionary[StringName, float]:
	var low: float = clampf(poured_from, 0.0, 1.0)
	var high: float = clampf(poured_to, 0.0, 1.0)
	if high <= low:
		var empty: Dictionary[StringName, float] = {}
		return empty
	var before: Dictionary = pour_top(mixture, low, catalog, economy)[KEY_TOP]
	var after: Dictionary = pour_top(mixture, high, catalog, economy)[KEY_TOP]
	var result: Dictionary[StringName, float] = {}
	for property_id: StringName in after:
		result[property_id] = float(after[property_id]) - amount(before, property_id)
	return cleaned(result)


# --- Срез (S4.2, STATIONS §1.2): где граница слоёв и насколько чисто её поймали ---------------------------------

## Риски шкалы среза: сколько столба слить, чтобы срез прошёл точно по границе слоёв. Сверху вниз (по возрастанию
## слитой высоты), только внутренние границы: у одного слоя рисок нет.
static func cut_marks(mixture: Dictionary, catalog: DataCatalog, economy: EconomyConfig) -> Array[float]:
	var heights: Array[float] = layer_heights(mixture, catalog, economy)
	var result: Array[float] = []
	var mark: float = 0.0
	for i: int in range(heights.size() - 1, 0, -1):
		mark += heights[i]
		result.append(mark)
	return result


## Примесь среза после слива poured (0…1): доля чужих слоёв в том сосуде, который срез испортил, по ближней границе.
## Перелил за границу — в Приёмник попал нижний слой (примесь сверху); недолил — верхний остался в Отстойнике
## (примесь снизу). 0 — срез точно по границе; 1 — границ нет (один слой или пусто), чистого среза не бывает.
static func cut_admixture(mixture: Dictionary, poured: float, catalog: DataCatalog, economy: EconomyConfig) -> float:
	var ids: Array[StringName] = layers(mixture, catalog)
	var split: Dictionary = pour_top(mixture, poured, catalog, economy)
	var marks: Array[float] = cut_marks(mixture, catalog, economy)
	var best: float = 1.0
	for k: int in marks.size():
		var boundary: int = ids.size() - 1 - k
		var stray: float = 0.0
		var vessel: Dictionary
		if poured >= marks[k]:
			vessel = split[KEY_TOP]
			for i: int in boundary:
				stray += amount(vessel, ids[i])
		else:
			vessel = split[KEY_BOTTOM]
			for i: int in range(boundary, ids.size()):
				stray += amount(vessel, ids[i])
		var whole: float = total(vessel)
		if whole > 0.0:
			best = minf(best, stray / whole)
	return best


## Чистые полосы шкалы среза: для каждой риски (в порядке cut_marks) отрезок слитой высоты (x — от, y — до), где
## cut_admixture не больше clean_cut_admixture. Полоса не выходит за соседние слои: дальше чище соседняя граница.
## Vector2 — float32, этого хватает для рисования; судить «чисто или нет» — только по cut_admixture.
static func clean_bands(mixture: Dictionary, catalog: DataCatalog, economy: EconomyConfig) -> Array[Vector2]:
	var ids: Array[StringName] = layers(mixture, catalog)
	var heights: Array[float] = layer_heights(mixture, catalog, economy)
	var limit: float = economy.clean_cut_admixture
	var ratio: float = limit / (1.0 - limit)
	var whole: float = total(cleaned(mixture))
	var result: Array[Vector2] = []
	var mark: float = 0.0
	var above: float = 0.0
	for i: int in range(ids.size() - 1, 0, -1):
		var upper: float = amount(mixture, ids[i])
		var lower: int = i - 1
		mark += heights[i]
		above += upper
		var below: float = whole - above
		var up_reach: float = minf(heights[i], heights[i] / upper * below * ratio)
		var down_reach: float = minf(heights[lower], heights[lower] / amount(mixture, ids[lower]) * above * ratio)
		result.append(Vector2(mark - up_reach, mark + down_reach))
	return result


# --- Нагрев (GDD §3.3 Горелка, §3.4 летучесть) --------------------------------------------------------------------

## Температура через dt секунд: огонь держат — растёт до max_temp, отпустили — остывает до room_temp.
static func temp_after(temp: float, heating: bool, dt: float, economy: EconomyConfig) -> float:
	var start: float = clampf(temp, economy.room_temp, economy.max_temp)
	if dt <= 0.0:
		return start
	if heating:
		return minf(start + economy.heat_rate * dt, economy.max_temp)
	return maxf(start - economy.cool_rate * dt, economy.room_temp)


## Сколько секунд из шага dt температура не ниже threshold. Точно: участок роста или остывания + участок на пределе.
static func time_at_or_above(threshold: float, temp: float, heating: bool, dt: float,
		economy: EconomyConfig) -> float:
	if dt <= 0.0 or threshold < 0.0:
		return 0.0
	var start: float = clampf(temp, economy.room_temp, economy.max_temp)
	var rate: float = economy.heat_rate if heating else -economy.cool_rate
	var limit: float = economy.max_temp if heating else economy.room_temp
	var moving: float = dt
	if not is_zero_approx(rate):
		moving = clampf((limit - start) / rate, 0.0, dt)
	var finish: float = start + rate * moving
	var result: float = 0.0
	if start >= threshold and finish >= threshold:
		result = moving
	elif start >= threshold:
		result = (start - threshold) / -rate
	elif finish >= threshold:
		result = moving - (threshold - start) / rate
	if finish >= threshold:
		result += dt - moving
	return clampf(result, 0.0, dt)


## Смесь после шага горелки: свойства уходят паром и сгорают, пока T не ниже их точек (temp — T в начале шага).
## Новую температуру даёт temp_after с теми же аргументами.
static func heat(mixture: Dictionary, temp: float, heating: bool, dt: float, catalog: DataCatalog,
		economy: EconomyConfig) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for property_id: StringName in mixture:
		var value: float = float(mixture[property_id])
		var data: PropertyData = catalog.property(property_id)
		if data != null:
			value -= economy.evaporate_rate * time_at_or_above(data.evaporate_temp, temp, heating, dt, economy)
			value -= economy.burn_rate * time_at_or_above(data.burn_temp, temp, heating, dt, economy)
		result[property_id] = maxf(value, 0.0)
	return cleaned(result)


## Свойства, которые при температуре temp уходят паром (цветной пар). Пусто — пара нет, сигнал «готово».
static func steaming(mixture: Dictionary, temp: float, catalog: DataCatalog) -> Array[StringName]:
	var result: Array[StringName] = []
	for property_id: StringName in cleaned(mixture):
		var data: PropertyData = catalog.property(property_id)
		if data != null and data.evaporates_at(temp):
			result.append(property_id)
	return result


## Свойства, которые при температуре temp сгорают (Жизнь с 90°: бурый дым, шипение).
static func burning(mixture: Dictionary, temp: float, catalog: DataCatalog) -> Array[StringName]:
	var result: Array[StringName] = []
	for property_id: StringName in cleaned(mixture):
		var data: PropertyData = catalog.property(property_id)
		if data != null and data.burns_at(temp):
			result.append(property_id)
	return result


## Тяжелее ли a, чем b (лежит ниже). Равная плотность — по имени id, чтобы порядок не зависел от входа.
static func _lies_below(a: PropertyData, b: PropertyData) -> bool:
	if a.density_rank != b.density_rank:
		return a.density_rank < b.density_rank
	return String(a.id) < String(b.id)
