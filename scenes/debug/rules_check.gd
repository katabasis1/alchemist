## RulesCheck — стенд правил алхимии (S3.3): те же случаи, что `python tools/alchemy/rules_model.py --self-test`,
## но на настоящем AlchemyRules в Godot: числа GDD §3.2–3.4, качество §5.3, летучесть §3.4, пути всех рецептов,
## независимость от шага кадра, детерминизм. Сверку имён .gd ↔ .py делает только Python.
## Запуск: открыть сцену, F6 — мгновенно; итог одной строкой «RULES CHECK: x/y OK» в Output (не путать с «RULES:»
## Python-эталона). Упавший путь печатает значимые свойства и ход пути.
## Сигналы: нет. Зависимости: AlchemyRules, RulePaths (scenes/debug/rule_paths.gd), DataCatalog через @export.
extends Node

const RulePaths := preload("res://scenes/debug/rule_paths.gd")

const LIFE: StringName = &"life"
const HEAT: StringName = &"heat"
const COLD: StringName = &"cold"
const SLEEP: StringName = &"sleep"
const ACID: StringName = &"acid"
const LIGHT: StringName = &"light"
const ONLY_LIFE: Array[StringName] = [LIFE]
const LIFE_HEAT: Array[StringName] = [LIFE, HEAT]
const NOTHING: Array[StringName] = []
const SAGE: StringName = &"ing_sage_bundle"
const FIRE_BLOOM: StringName = &"ing_fire_bloom"
const MOON_MOSS: StringName = &"ing_moon_moss"
const DROWSE_HERB: StringName = &"ing_drowse_herb"
const GOLDEN_ROOT: StringName = &"ing_golden_root"
const RUST_LICHEN: StringName = &"ing_rust_lichen"
const GLOW_FLOWER: StringName = &"ing_glow_flower"
const EMBER_NUT: StringName = &"ing_ember_nut"
const SNOW_LOTUS: StringName = &"ing_snow_lotus"
## Сверка «то же самое»: допуск для сумм с плавающей точкой.
const TOLERANCE: float = 1e-9
## Дробление тика горелки: 1 (эталон) и мельче; плюс столько случайных дроблений.
const DT_SPLITS: Array[int] = [2, 3, 7, 16]
const RANDOM_RUNS: int = 5
const RANDOM_SEED: int = 31
## Слив по кадрам: шаги кадра и время удержания.
const POUR_FRAME_DT: Array[float] = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0, 0.07]
const POUR_HOLD_SEC: float = 1.3
## Сумма приращений слива по кадрам совпадает с формулой с таким допуском.
const FRAME_TOLERANCE: float = 1e-12
## Помол смесей для случаев горелки и слива (как в эталоне).
const DT_GRIND: float = 0.75
const SHUFFLES: int = 20

@export var catalog: DataCatalog

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_check("каталог на месте", catalog != null and catalog.economy != null)
	if catalog == null or catalog.economy == null:
		_finish()
		return
	_check_grind()
	_check_mix()
	_check_layers()
	_check_pour()
	_check_heat()
	_check_quality()
	_check_volatility()
	_check_paths()
	seed(RANDOM_SEED)
	_check_dt_burner()
	_check_dt_pour()
	_check_determinism()
	_finish()


## GDD §3.3: помол и извлечение.
func _check_grind() -> void:
	var e: EconomyConfig = catalog.economy
	_check("извлечение: p=0 → 0,4", _near(AlchemyRules.extraction(0.0, e), 0.4))  # noqa: magic
	_check("извлечение: p=0,35 → 0,7", _near(AlchemyRules.extraction(0.35, e), 0.7))  # noqa: magic
	_check("извлечение: 0,70…0,85 → 1", AlchemyRules.extraction(0.7, e) == 1.0  # noqa: magic
			and AlchemyRules.extraction(0.85, e) == 1.0)
	_check("извлечение: p=1 → 0,7 (пылит)", _near(AlchemyRules.extraction(1.0, e), 0.7))  # noqa: magic
	_check("помол: мягкий +0,12, средний +0,09, твёрдый +0,07 за круг",  # noqa: magic
			AlchemyRules.grind_per_circle(_ings([SAGE]), e) == 0.12
			and AlchemyRules.grind_per_circle(_ings([RUST_LICHEN]), e) == 0.09
			and AlchemyRules.grind_per_circle(_ings([GOLDEN_ROOT]), e) == 0.07)
	_check("помол: в смеси считается самый твёрдый",
			AlchemyRules.hardest(_ings([SAGE, SNOW_LOTUS, EMBER_NUT])) == IngredientData.Hardness.HARD)
	_check("помол: пустая ступка не мелется", AlchemyRules.grind_after(0.3, 5.0, _ings([]), e) == 0.3)  # noqa: magic
	_check("помол: шкала стоит на 1", AlchemyRules.grind_after(0.95, 3.0, _ings([SAGE]), e) == 1.0)  # noqa: magic
	_check("смесь из ступки = доли × извлечение (порядок ключей — по ингредиентам)",  # noqa: magic
			_same_mix(AlchemyRules.ground(_ings([FIRE_BLOOM, SAGE]), 0.35, e),
			{HEAT: 2.0 * 0.7, ACID: 1.0 * 0.7, LIFE: 2.0 * 0.7}))


## GDD §3.2: значимость, сила, чистота, смешивание.
func _check_mix() -> void:
	var e: EconomyConfig = catalog.economy
	var with_trace: Dictionary = {LIFE: 1.0, ACID: 0.29}  # noqa: magic
	_check("порог значимости: 0,3 есть, 0,29 — след", AlchemyRules.is_present(0.3, e)  # noqa: magic
			and not AlchemyRules.is_present(0.29, e) and AlchemyRules.significant(with_trace, e) == [LIFE]
			and AlchemyRules.traces(with_trace, e) == [ACID])
	var stars: Array[int] = []
	for value: float in [0.99, 1.0, 2.0, 3.0]:  # noqa: magic
		stars.append(AlchemyRules.strength_stars(value, e))
	_check("сила: 0,99 → 0, 1,0 → ★, 2,0 → ★★, 3,0 → ★★★", stars == [0, 1, 2, 3])  # noqa: magic
	_check("сила: 0,7 × 3 доли (2,0999…) → ★★", AlchemyRules.strength_stars(3.0 * 0.7, e) == 2)  # noqa: magic
	var almost: Dictionary = {LIFE: 2.4, ACID: 0.6}  # noqa: magic
	_check("чистота: 2,4 / 3,0 = 0,7999… → ★★ (допуск EPSILON)",  # noqa: magic
			AlchemyRules.purity(almost, ONLY_LIFE) < 0.8
			and AlchemyRules.purity_stars(AlchemyRules.purity(almost, ONLY_LIFE), e) == 2)
	_check("чистота: пустая смесь — 0", AlchemyRules.purity({}, ONLY_LIFE) == 0.0)
	_check("сложение смесей: ключи a, потом новые из b", _same_mix(  # noqa: magic
			AlchemyRules.combine({HEAT: 1.0, ACID: 0.5}, {LIFE: 2.0, HEAT: 1.0}), {HEAT: 2.0, ACID: 0.5, LIFE: 2.0}, 0.0))
	_check("масштаб и чистка нулей", _same_mix(  # noqa: magic
			AlchemyRules.scaled({HEAT: 2.0, ACID: 0.00005}, 0.5), {HEAT: 1.0}, 0.0))


## GDD §3.4: слои Отстойника.
func _check_layers() -> void:
	var e: EconomyConfig = catalog.economy
	_check("слои по плотности: Едкость на дне, Свет сверху",
			AlchemyRules.layers({LIGHT: 1.0, COLD: 1.0, ACID: 1.0, LIFE: 1.0}, catalog) == [ACID, LIFE, COLD, LIGHT])
	_check("толщины ∝ долям: Едкость 1 + Жар 2 → 1/3, 2/3", _near_list(  # noqa: magic
			AlchemyRules.layer_heights({HEAT: 2.0, ACID: 1.0}, catalog, e), [1.0 / 3.0, 2.0 / 3.0]))
	var thin: Array[float] = AlchemyRules.layer_heights({HEAT: 3.0, LIFE: 0.1}, catalog, e)  # noqa: magic
	_check("тонкий слой не меньше 10 %%: Жар 3 + Жизнь 0,1 → 0,9 / 0,1 %s" % [thin],  # noqa: magic
			_near_list(thin, [0.9, 0.1]))
	var many: Dictionary = {}
	for property: PropertyData in catalog.properties:
		many[property.id] = 1.0
	var thick: EconomyConfig = e.duplicate() as EconomyConfig
	thick.min_layer_height = 0.2  # noqa: magic
	var crowded: Array[float] = AlchemyRules.layer_heights(many, catalog, thick)
	_check("минимум не влезает (6 × 0,2 > 1) — все слои поровну",  # noqa: magic
			_near_list(crowded, _repeat(1.0 / 6.0, 6)))
	many[LIGHT] = 0.01  # noqa: magic
	many[ACID] = 0.02  # noqa: magic
	var two: Array[float] = AlchemyRules.layer_heights(many, catalog, e)
	_check("два тонких слоя: оба по 10 %%, сумма 1 %s" % [two], _near(_sum(two), 1.0)  # noqa: magic
			and _near(two[0], 0.1) and _near(two[two.size() - 1], 0.1))


## GDD §3.4: слив из Отстойника.
func _check_pour() -> void:
	var e: EconomyConfig = catalog.economy
	var mix: Dictionary = {HEAT: 2.0, ACID: 1.0}
	var split: Dictionary = AlchemyRules.pour_top(mix, 2.0 / 3.0, catalog, e)  # noqa: magic
	_check("слив 2/3: Жар целиком сверху, Едкость внизу %s" % [split],  # noqa: magic
			_same_mix(split[AlchemyRules.KEY_TOP], {HEAT: 2.0}, 1e-6)
			and _same_mix(split[AlchemyRules.KEY_BOTTOM], {ACID: 1.0}, 1e-6))
	split = AlchemyRules.pour_top(mix, 0.5, catalog, e)  # noqa: magic
	_check("слив 0,5: из слоя уходит накрытая доля (Жар 1,5 / 0,5) %s" % [split],  # noqa: magic
			_same_mix(split[AlchemyRules.KEY_TOP], {HEAT: 1.5})
			and _same_mix(split[AlchemyRules.KEY_BOTTOM], {HEAT: 0.5, ACID: 1.0}))
	split = AlchemyRules.pour_top(mix, 1.5, catalog, e)  # noqa: magic
	_check("слив больше столба — всё наверху", Dictionary(split[AlchemyRules.KEY_BOTTOM]).is_empty()
			and _same_mix(split[AlchemyRules.KEY_TOP], {HEAT: 2.0, ACID: 1.0}))
	_check("высота над слоем: снять Жар — 2/3, снять всё — 1",  # noqa: magic
			_near(AlchemyRules.height_above_layer(mix, 1, catalog, e), 2.0 / 3.0)
			and _near(AlchemyRules.height_above_layer(mix, 0, catalog, e), 1.0))
	_check("струя: 0,5 с по 15 %, дальше 30 %", _near(AlchemyRules.pour_height(0.5, e), 0.075)  # noqa: magic
			and _near(AlchemyRules.pour_height(1.5, e), 0.375) and AlchemyRules.pour_rate(0.49, e) == 0.15
			and AlchemyRules.pour_rate(0.5, e) == 0.3)
	_check("хвост струи после отпускания за 0,1 с", _near(AlchemyRules.pour_tail(1.0, e), 0.015)  # noqa: magic
			and _near(AlchemyRules.pour_tail(0.2, e), 0.0075))


## GDD §3.4: горелка, пар и дым.
func _check_heat() -> void:
	var e: EconomyConfig = catalog.economy
	_check("температура: +20°/с до 100°, остывание −12°/с до 20°",  # noqa: magic
			AlchemyRules.temp_after(20.0, true, 3.0, e) == 80.0 and AlchemyRules.temp_after(90.0, true, 1.0, e) == 100.0
			and AlchemyRules.temp_after(80.0, false, 2.0, e) == 56.0
			and AlchemyRules.temp_after(30.0, false, 5.0, e) == 20.0)
	_check("время выше точки: рост 20→60 за 2 с, выше 35° — 1,25 с",  # noqa: magic
			_near(AlchemyRules.time_at_or_above(35.0, 20.0, true, 2.0, e), 1.25))
	_check("время выше точки: остывание с 50° за 5 с, выше 35° — 1,25 с",  # noqa: magic
			_near(AlchemyRules.time_at_or_above(35.0, 50.0, false, 5.0, e), 1.25))
	_check("время выше точки: на потолке 100° всё время; «никогда» — 0",  # noqa: magic
			AlchemyRules.time_at_or_above(90.0, 100.0, true, 3.0, e) == 3.0
			and AlchemyRules.time_at_or_above(-1.0, 100.0, true, 3.0, e) == 0.0)
	_check("пар: Холод 2 за 2 с нагрева с 20° теряет 1,2 × 1,25", _same_mix(  # noqa: magic
			AlchemyRules.heat({COLD: 2.0, HEAT: 1.0}, 20.0, true, 2.0, catalog, e), {COLD: 2.0 - 1.5, HEAT: 1.0}))
	_check("дым: Жизнь с 90° сгорает 0,8 доли/с, Жар и Свет стойкие", _same_mix(  # noqa: magic
			AlchemyRules.heat({LIFE: 2.0, HEAT: 1.0, LIGHT: 1.0}, 90.0, true, 1.0, catalog, e),
			{LIFE: 1.2, HEAT: 1.0, LIGHT: 1.0}))
	_check("пар и дым: кто уходит при 60° и 95°",  # noqa: magic
			AlchemyRules.steaming({HEAT: 1.0, COLD: 1.0, SLEEP: 1.0, ACID: 1.0}, 60.0, catalog) == [COLD, SLEEP]
			and AlchemyRules.burning({LIFE: 1.0, HEAT: 1.0}, 95.0, catalog) == [LIFE]
			and AlchemyRules.burning({LIFE: 1.0}, 89.9, catalog).is_empty())


## GDD §5.3: сила — по самому слабому нужному свойству; «безупречно» — ★★★ силы и ★★★ чистоты.
func _check_quality() -> void:
	var e: EconomyConfig = catalog.economy
	_check("слабейшее: {Жизнь 3, Жар 2} → ★★",  # noqa: magic
			AlchemyRules.weakest_stars({LIFE: 3.0, HEAT: 2.0}, LIFE_HEAT, e) == 2)
	_check("слабейшее: нужного свойства нет → 0", AlchemyRules.weakest_stars({LIFE: 3.0}, LIFE_HEAT, e) == 0)  # noqa: magic
	_check("слабейшее: ничего не нужно → 0", AlchemyRules.weakest_stars({LIFE: 3.0}, NOTHING, e) == 0)  # noqa: magic
	_check("слабейшее: 2,99995 → ★★★ (допуск EPSILON)",  # noqa: magic
			AlchemyRules.weakest_stars({LIFE: 2.99995}, ONLY_LIFE, e) == 3)
	_check("безупречно: ★★★ и ★★★", AlchemyRules.is_flawless(3, 3, e))  # noqa: magic
	_check("не безупречно: ★★★ силы, ★★ чистоты", not AlchemyRules.is_flawless(3, 2, e))  # noqa: magic
	_check("не безупречно: ★★ силы, ★★★ чистоты", not AlchemyRules.is_flawless(2, 3, e))  # noqa: magic
	_check("Жизнь 3 + Жар 0,15: чистота 95,2 % → безупречно", _flawless({LIFE: 3.0, HEAT: 0.15}))  # noqa: magic
	_check("Жизнь 3 + Жар 0,2: чистота 93,75 % → нет", not _flawless({LIFE: 3.0, HEAT: 0.2}))  # noqa: magic


## GDD §3.1, §3.4: какие свойства летучие, какие стойкие; горелка по окнам снимает летучие по очереди.
func _check_volatility() -> void:
	var e: EconomyConfig = catalog.economy
	var volatile: Array[PropertyData] = []
	var stable: Array[StringName] = []
	var everything: Dictionary = {}
	for property: PropertyData in catalog.properties:
		if property.evaporate_temp >= 0.0:
			volatile.append(property)
		if property.is_stable():
			stable.append(property.id)
		everything[property.id] = 2.0  # noqa: magic
	volatile.sort_custom(_by_evaporate_temp)
	var volatile_ids: Array[StringName] = []
	for property: PropertyData in volatile:
		volatile_ids.append(property.id)
	_check("GDD §3.4: летучие по возрастанию точки — Холод, Сон, Едкость", volatile_ids == [COLD, SLEEP, ACID])
	_check("GDD §3.1: стойкие — Жар и Свет", stable.size() == 2 and stable.has(HEAT) and stable.has(LIGHT))
	var left: Array[String] = []
	for window: Array in [[35, 54], [55, 74], [75, 89]]:  # noqa: magic
		var schedule: Array[bool] = RulePaths.burner_schedule(everything, window[0], window[1], catalog, e)
		var mixture: Dictionary = RulePaths.run_burner(everything, schedule, catalog, e)[RulePaths.KEY_MIXTURE]
		var gone: PackedStringArray = []
		for property_id: StringName in everything:
			if not mixture.has(property_id):
				gone.append(String(property_id))
		gone.sort()
		left.append(",".join(gone))
	_check("горелка снимает {Холод} → {Холод, Сон} → {Холод, Сон, Едкость}, Жизнь цела ниже 90° %s" % [left],
			left == ["cold", "cold,sleep", "acid,cold,sleep"])


## Подсказки рецептов (GDD §5.1) проходятся честно: помол тапами, горелка по тикам, слив целых слоёв.
func _check_paths() -> void:
	var covered: Dictionary[StringName, bool] = {}
	for report: Dictionary in RulePaths.all_paths(catalog):
		covered[report[RulePaths.KEY_RECIPE]] = true
		var steps: PackedStringArray = []
		for step: StringName in report[RulePaths.KEY_PATH]:
			steps.append(String(step))
		var ok: bool = bool(report[RulePaths.KEY_OK])
		if not ok:
			print("    %s; значимые %s; ход: %s" % [report.get(RulePaths.KEY_ERROR, "—"),
					report.get(RulePaths.KEY_SIGNIFICANT, []), report.get(RulePaths.KEY_NOTES, [])])
		_check("путь %s: %s → %s" % [report[RulePaths.KEY_RECIPE], " → ".join(steps),
				report.get(RulePaths.KEY_RESULT, &"?")], ok)
	var all_covered: bool = covered.size() == catalog.recipes.size()
	for recipe: RecipeData in catalog.recipes:
		all_covered = all_covered and covered.has(recipe.id)
	_check("у каждого из %d рецептов есть путь" % catalog.recipes.size(), all_covered)


## Горелка: итог не зависит от того, как кадры режут тик игрока (равные и случайные куски).
func _check_dt_burner() -> void:
	var e: EconomyConfig = catalog.economy
	var short_heat: Array[bool] = _held(5, 12)  # noqa: magic
	_check_burner_dt("короткий нагрев до 45° (Холод уходит частично)",
			AlchemyRules.ground(_ings([MOON_MOSS]), DT_GRIND, e), short_heat, true)
	var overheat: Array[bool] = _held(19, 34)  # noqa: magic
	_check_burner_dt("перегрев до 100° и остывание (Жизнь подгорает)",
			AlchemyRules.ground(_ings([SAGE, FIRE_BLOOM]), DT_GRIND, e), overheat, true)
	var jerks: Array[bool] = _held(8, 1)  # noqa: magic
	jerks.append_array(_held(1, 30))  # noqa: magic
	_check_burner_dt("рывки огня у точки Сна",
			AlchemyRules.ground(_ings([DROWSE_HERB, SNOW_LOTUS]), DT_GRIND, e), jerks, true)
	var sparks: Dictionary = AlchemyRules.ground(_ings([FIRE_BLOOM, GLOW_FLOWER]), DT_GRIND, e)
	var window: Array[bool] = RulePaths.burner_schedule(sparks, 75, 89, catalog, e)  # noqa: magic
	_check_burner_dt("окно 75–89° по пути «Праздничных искр»", sparks, window, false)


func _check_burner_dt(title: String, mixture: Dictionary, schedule: Array[bool], partial_expected: bool) -> void:
	var e: EconomyConfig = catalog.economy
	var base: Dictionary = RulePaths.run_burner(mixture, schedule, catalog, e)
	var base_mix: Dictionary = base[RulePaths.KEY_MIXTURE]
	var same: bool = true
	var worst: float = 0.0
	var runs: Array[Dictionary] = []
	for splits: int in DT_SPLITS:
		runs.append(RulePaths.run_burner(mixture, schedule, catalog, e, splits))
	for _i: int in RANDOM_RUNS:
		runs.append(RulePaths.run_burner(mixture, schedule, catalog, e, 1, true))
	for run: Dictionary in runs:
		var run_mix: Dictionary = run[RulePaths.KEY_MIXTURE]
		same = same and _same_mix(base_mix, run_mix) and _near(float(run[RulePaths.KEY_TEMP]), float(base[RulePaths.KEY_TEMP]))
		for property_id: StringName in mixture:
			worst = maxf(worst, absf(float(base_mix.get(property_id, 0.0)) - float(run_mix.get(property_id, 0.0))))
	_check("горелка, %s: шаг dt не меняет итог (макс. расхождение %s)" % [title, worst], same)
	if partial_expected:
		var partial: bool = false
		for property_id: StringName in mixture:
			var now: float = float(base_mix.get(property_id, 0.0))
			partial = partial or (now > 0.0 and now < float(mixture[property_id]) - AlchemyRules.EPSILON)
		_check("горелка, %s: испарение оборвано на полпути (проверка не пустая)" % title, partial)
	else:
		_check("горелка, %s: Сон и Едкость ушли, Жар и Свет целы" % title, base_mix.keys() == [HEAT, LIGHT]
				and float(base[RulePaths.KEY_TEMP]) == e.room_temp)


## Слив и помол: итог не зависит от шага кадра и от того, как разбито удержание.
func _check_dt_pour() -> void:
	var e: EconomyConfig = catalog.economy
	for dt: float in POUR_FRAME_DT:
		var held: float = 0.0
		var poured: float = 0.0
		while held + dt <= POUR_HOLD_SEC + FRAME_TOLERANCE:
			poured += AlchemyRules.pour_height(held + dt, e) - AlchemyRules.pour_height(held, e)
			held += dt
		_check("слив по кадрам dt=%.4f = pour_height" % dt,
				absf(poured - AlchemyRules.pour_height(held, e)) < FRAME_TOLERANCE)
	var mixture: Dictionary = AlchemyRules.ground(_ings([SAGE, FIRE_BLOOM]), DT_GRIND, e)
	var first: float = AlchemyRules.pour_height(0.4, e) + AlchemyRules.pour_tail(0.4, e)  # noqa: magic
	var second: float = AlchemyRules.pour_height(0.6, e) + AlchemyRules.pour_tail(0.6, e)  # noqa: magic
	var once: Dictionary = AlchemyRules.pour_top(mixture, first + second, catalog, e)
	var swapped: Dictionary = AlchemyRules.pour_top(mixture, second + first, catalog, e)
	_check("слив двумя удержаниями = одним на ту же высоту (считается от отстоянной смеси)",
			_same_mix(once[AlchemyRules.KEY_TOP], swapped[AlchemyRules.KEY_TOP]))
	var herbs: Array[IngredientData] = _ings([GOLDEN_ROOT, SAGE])
	var by_taps: float = 0.0
	for _i: int in 36:  # noqa: magic
		by_taps = AlchemyRules.grind_after(by_taps, RulePaths.TAP_CIRCLES, herbs, e)
	_check("помол: 36 тапов = 9 кругов", _near(by_taps,  # noqa: magic
			AlchemyRules.grind_after(0.0, 9.0, herbs, e)))


## Одинаковый вход — одинаковый выход; порядок ключей на входе не меняет слои и слив.
func _check_determinism() -> void:
	var e: EconomyConfig = catalog.economy
	var mixture: Dictionary = {LIGHT: 1.2, ACID: 0.4, LIFE: 2.0, COLD: 0.9, SLEEP: 0.35, HEAT: 1.1}  # noqa: magic
	var height: float = 0.45  # noqa: magic
	var base_layers: Array[StringName] = AlchemyRules.layers(mixture, catalog)
	var base_split: Dictionary = AlchemyRules.pour_top(mixture, height, catalog, e)
	var keys: Array = mixture.keys()
	var same: bool = true
	for _i: int in SHUFFLES:
		keys.shuffle()
		var shuffled: Dictionary = {}
		for key: StringName in keys:
			shuffled[key] = mixture[key]
		var split: Dictionary = AlchemyRules.pour_top(shuffled, height, catalog, e)
		same = same and AlchemyRules.layers(shuffled, catalog) == base_layers
		for side: StringName in [AlchemyRules.KEY_TOP, AlchemyRules.KEY_BOTTOM]:
			for key: StringName in mixture:
				same = same and _near(float(Dictionary(split[side]).get(key, 0.0)),
						float(Dictionary(base_split[side]).get(key, 0.0)))
	_check("порядок ключей на входе не меняет слои и слив", same)
	var again: Dictionary = AlchemyRules.pour_top(mixture, height, catalog, e)
	_check("повтор того же вызова — тот же результат (с порядком ключей)",
			_same_mix(again[AlchemyRules.KEY_TOP], base_split[AlchemyRules.KEY_TOP], 0.0)
			and _same_mix(again[AlchemyRules.KEY_BOTTOM], base_split[AlchemyRules.KEY_BOTTOM], 0.0))


func _flawless(mixture: Dictionary) -> bool:
	var e: EconomyConfig = catalog.economy
	return AlchemyRules.is_flawless(AlchemyRules.weakest_stars(mixture, ONLY_LIFE, e),
			AlchemyRules.purity_stars(AlchemyRules.purity(mixture, ONLY_LIFE), e), e)


func _ings(ids: Array) -> Array[IngredientData]:
	var result: Array[IngredientData] = []
	for ingredient_id: StringName in ids:
		result.append(catalog.ingredient(ingredient_id))
	return result


## Расписание горелки: on тиков огня, затем off тиков без огня.
func _held(on: int, off: int) -> Array[bool]:
	var result: Array[bool] = []
	for i: int in on + off:
		result.append(i < on)
	return result


func _by_evaporate_temp(a: PropertyData, b: PropertyData) -> bool:
	return a.evaporate_temp < b.evaporate_temp


## Те же ключи в том же порядке, значения совпадают с допуском.
func _same_mix(a: Dictionary, b: Dictionary, tolerance: float = TOLERANCE) -> bool:
	if a.keys() != b.keys():
		return false
	for key: Variant in a:
		if absf(float(a[key]) - float(b[key])) > tolerance:
			return false
	return true


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOLERANCE


func _near_list(values: Array[float], expected: Array) -> bool:
	if values.size() != expected.size():
		return false
	for i: int in values.size():
		if not _near(values[i], float(expected[i])):
			return false
	return true


func _repeat(value: float, count: int) -> Array[float]:
	var result: Array[float] = []
	for _i: int in count:
		result.append(value)
	return result


func _sum(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total


func _check(title: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		_failed += 1
		print("  FAIL ", title)
		push_error("RulesCheck FAIL: " + title)


func _finish() -> void:
	var total: int = _passed + _failed
	print("RULES CHECK: %d/%d %s" % [_passed, total, "OK" if _failed == 0 else "FAIL"])
