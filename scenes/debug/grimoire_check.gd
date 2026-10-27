## GrimoireCheck — распознавание рецептов и Гримуар в Godot (F6 на этой сцене), пока у агента нет движка.
## Те же случаи, что python tools/alchemy/grimoire_model.py --self-test (эталон на Python), плюс то, чего Python не видит:
## сам GDScript GrimoireRules и AlchemyRules, согласие с OrderJudge о «безупречно» и силе, путь через
## GameState.record_brew (сигналы EventBus, запрос записи) и сохранение → JSON → загрузка.
## Перед проверкой GameState — новая игра, после — прежнее состояние (в F6 SaveService не загружен и на диск не пишет).
## Итог — в Output строкой «GRIMOIRE CHECK: x/y».
## Сигналы: нет. Зависимости: DataCatalog (@export), OrderJudge (@export, с тем же EconomyConfig), GrimoireRules,
##   AlchemyRules, GameState, EventBus.
extends Node

## Доля следа: чуть ниже порога значимости 0,3 (GDD §3.2).
const TRACE: float = 0.29
const AT_THRESHOLD: float = 0.3
const BELOW_THRESHOLD: float = 0.299
## В пределах допуска AlchemyRules.EPSILON от порога — свойство есть.
const WITHIN_EPSILON: float = 0.2999
const LIFE: StringName = &"life"
const HEAT: StringName = &"heat"
const COLD: StringName = &"cold"
const BALM: StringName = &"healing_balm"
const PAIR: StringName = &"warming_balm"
const STRANGE_THREE: Array[StringName] = [&"acid", &"cold", &"sleep"]
const STRANGE_FOUR: Array[StringName] = [&"life", &"heat", &"light", &"cold"]
## GDD §5.3: Жизнь 3 — ★★★ силы; + Жар 0,15 — чистота 95,2 % (безупречно); + Жар 0,2 — 93,75 % (★★, нет).
const STRONG: float = 3.0
## ★★★ — верх шкалы силы и чистоты; золотая страница — на третьей безупречной (GDD §3.5).
const TOP: int = 3
const GOLDEN_AFTER: int = 3
## Пара: Жар 1,2 — ★ силы при Жизни 3.
const PAIR_WEAK_HEAT: float = 1.2
const FLAWLESS_HEAT: float = 0.15
const DIRTY_HEAT: float = 0.2
## Пробные доли для сверки с OrderJudge: от «нет свойства» до ★★★.
const PROBE_AMOUNTS: Array[float] = [0.2, 1.0, 2.0, 3.0]
const PROBE_EXTRA: Array[float] = [0.0, 0.15, 0.29, 0.5]
## Сколько расхождений показать в строке итога.
const SHOW_DIFFERENCES: int = 3

@export var catalog: DataCatalog
@export var judge: OrderJudge

var _passed: int = 0
var _total: int = 0
var _discovered: Array[StringName] = []
var _golden: Array[StringName] = []
var _saves: Array[StringName] = []


func _ready() -> void:
	_check("каталог и оценщик на месте", catalog != null and catalog.economy != null and judge != null
			and judge.economy != null)
	if catalog == null or judge == null:
		_finish()
		return
	_check_recognition()
	_check_brew()
	_check_judge_agrees()
	_check_pages()
	_check_parse()
	_check_game_state()
	_finish()


# --- распознавание ---------------------------------------------------------------------------------------------------

func _check_recognition() -> void:
	var wrong: Array[StringName] = []
	var sets: Dictionary[String, bool] = {}
	for recipe: RecipeData in catalog.recipes:
		var pure: Dictionary[StringName, float] = _pure(recipe, 1.0)
		var dirty: Dictionary[StringName, float] = _pure(recipe, 1.0)
		for property: PropertyData in catalog.properties:
			if not dirty.has(property.id):
				dirty[property.id] = TRACE
		if _id(pure) != recipe.id or _id(dirty) != recipe.id or _id(_reversed(dirty)) != recipe.id:
			wrong.append(recipe.id)
		sets[_set_key(recipe)] = true
	_check("все %d рецептов узнаются по своим свойствам; следы 0,29 и порядок ключей не мешают %s"
			% [catalog.recipes.size(), wrong], wrong.is_empty())
	_check("наборы свойств рецептов не повторяются (иначе узнаётся первый)", sets.size() == catalog.recipes.size())
	_check("ровно 0,3 Жара — свойство есть: Согревающий бальзам", _id({LIFE: 1.0, HEAT: AT_THRESHOLD}) == PAIR)
	_check("0,2999 Жара (в допуске EPSILON) — тоже есть", _id({LIFE: 1.0, HEAT: WITHIN_EPSILON}) == PAIR)
	_check("0,299 Жара — след: Целебный бальзам", _id({LIFE: 1.0, HEAT: BELOW_THRESHOLD}) == BALM)
	_check("«Странная смесь»: пусто, одни следы, Едкость + Холод + Сон, четыре свойства",
			_id({}) == &"" and _id({LIFE: TRACE, HEAT: TRACE}) == &"" and _id(_mix(STRANGE_THREE)) == &""
			and _id(_mix(STRANGE_FOUR)) == &"")


# --- оценка варки ----------------------------------------------------------------------------------------------------

func _check_brew() -> void:
	var e: EconomyConfig = catalog.economy
	var balm: RecipeData = catalog.recipe(BALM)
	var pair: RecipeData = catalog.recipe(PAIR)
	_check("Жизнь 3 — Целебный бальзам ★★★/★★★, безупречно", _brew_is(GrimoireRules.brew({LIFE: STRONG}, balm, e),
			TOP, TOP, true))
	_check("Жизнь 3 + Жар 0,15 (95,2 %) — безупречно",
			_brew_is(GrimoireRules.brew({LIFE: STRONG, HEAT: FLAWLESS_HEAT}, balm, e), TOP, TOP, true))
	_check("Жизнь 3 + Жар 0,2 (93,75 %) — ★★★/★★, не безупречно",
			_brew_is(GrimoireRules.brew({LIFE: STRONG, HEAT: DIRTY_HEAT}, balm, e), TOP, 2, false))
	_check("пара: сила по слабейшему, Жизнь 3 + Жар 1,2 — ★",
			int(GrimoireRules.brew({LIFE: STRONG, HEAT: PAIR_WEAK_HEAT}, pair, e)[GrimoireRules.BREW_STRENGTH]) == 1)
	_check("пара: Холод 0,5 из 4,5 — чистота 88,9 %, ★★",
			int(GrimoireRules.brew({LIFE: 2.0, HEAT: 2.0, COLD: 0.5}, pair, e)[GrimoireRules.BREW_PURITY]) == 2)


## Заказ, чьи свойства — ровно рецепт: Гримуар и OrderJudge одинаково судят «безупречно», силу и звёзды чистоты.
func _check_judge_agrees() -> void:
	var cases: int = 0
	var differ: Array[String] = []
	for order: OrderTemplate in catalog.all_orders():
		var recipe: RecipeData = catalog.recipe_for(order.required)
		if recipe == null:
			continue
		var extra: StringName = _outsider(recipe)
		for main_amount: float in PROBE_AMOUNTS:
			for extra_amount: float in PROBE_EXTRA:
				var mixture: Dictionary[StringName, float] = _pure(recipe, main_amount)
				if extra_amount > 0.0:
					mixture[extra] = extra_amount
				var verdict: Dictionary = judge.judge(order, mixture)
				var result: Dictionary = GrimoireRules.brew(mixture, recipe, catalog.economy)
				cases += 1
				var same: bool = (bool(verdict[OrderJudge.KEY_FLAWLESS]) == bool(result[GrimoireRules.BREW_FLAWLESS])
						and int(verdict[OrderJudge.KEY_PURITY_STARS]) == int(result[GrimoireRules.BREW_PURITY]))
				if bool(verdict[OrderJudge.KEY_EFFECT]):
					same = same and int(verdict[OrderJudge.KEY_STRENGTH_STARS]) == int(result[GrimoireRules.BREW_STRENGTH])
				if not same:
					differ.append("%s %s" % [order.id, mixture])
	_check("OrderJudge и Гримуар согласны: %d случаев %s" % [cases, differ.slice(0, SHOW_DIFFERENCES)], cases > 0 and differ.is_empty())


# --- страницы --------------------------------------------------------------------------------------------------------

func _check_pages() -> void:
	var e: EconomyConfig = catalog.economy
	var best: Dictionary = _result(TOP, TOP, true)
	var weak: Dictionary = _result(1, 2, false)
	_check("новая страница — нули, не золотая", _page_is(GrimoireRules.parse_page(null), 0, 0, 0, 0)
			and not GrimoireRules.is_golden(GrimoireRules.parse_page(null), e))
	var first: Dictionary = GrimoireRules.after_brew(null, weak)
	_check("первая варка: варок 1, рекорды ★/★★, безупречных 0", _page_is(first, 1, 1, 2, 0))
	var second: Dictionary = GrimoireRules.after_brew(first, best)
	_check("after_brew не меняет входную страницу", _page_is(first, 1, 1, 2, 0) and _page_is(second, 2, TOP, TOP, 1))
	var split: Dictionary = GrimoireRules.after_brew(GrimoireRules.after_brew(null, _result(1, TOP, false)),
			_result(TOP, 1, false))
	_check("рекорды независимы: ★/★★★ и ★★★/★ → ★★★/★★★, безупречных 0", _page_is(split, 2, TOP, TOP, 0))
	_check("слабая варка рекорд не снижает", _page_is(GrimoireRules.after_brew(second, weak), 3, TOP, TOP, 1))  # noqa: magic
	var golden_at: Array[bool] = []
	var page: Dictionary = GrimoireRules.parse_page(null)
	for result: Dictionary in [best, weak, best, weak, best, weak]:
		page = GrimoireRules.after_brew(page, result)
		golden_at.append(GrimoireRules.is_golden(page, e))
	_check("золотая — на %d-й безупречной, слабая варка её не отнимает %s" % [e.golden_page_flawless, golden_at],
			e.golden_page_flawless == GOLDEN_AFTER and golden_at == [false, false, false, false, true, true])


# --- сохранение ------------------------------------------------------------------------------------------------------

func _check_parse() -> void:
	_check("JSON-числа (float) → целые", _page_is(GrimoireRules.parse_page(  # noqa: magic
			{"brews": 2.0, "best_strength": 3.0, "best_purity": 1.0, "flawless": 1.0}), 2, 3, 1, 1))
	_check("мусор → 0: отрицательное, строка, bool, null", _page_is(GrimoireRules.parse_page(  # noqa: magic
			{"brews": -4, "best_strength": "3", "best_purity": true, "flawless": null}), 0, 0, 0, 0))
	var old: Dictionary = GrimoireRules.parse_page({"best_stars": 2, "flawless": 1, "x": 9})  # noqa: magic
	_check("лишние ключи отброшены, старый формат (best_stars) не мешает",
			old.size() == GrimoireRules.parse_page(null).size() and _page_is(old, 0, 0, 0, 1))
	_check("не словарь — пустой Гримуар", GrimoireRules.parse_grimoire(null).is_empty()
			and GrimoireRules.parse_grimoire([1, 2]).is_empty())
	var book: Dictionary = GrimoireRules.parse_grimoire({"healing_balm": {"brews": 3.0, "flawless": 1.0}, "": {},  # noqa: magic
			"smith_flux": 7})
	_check("пустой ключ отброшен, страница-мусор — открыта с нулями", book.keys() == ["healing_balm", "smith_flux"]  # noqa: magic
			and _page_is(book["smith_flux"], 0, 0, 0, 0) and _page_is(book["healing_balm"], 3, 0, 0, 1))
	var again: Dictionary = GrimoireRules.parse_grimoire(JSON.parse_string(JSON.stringify(book)))
	_check("запись → JSON → чтение: то же самое, повторный разбор ничего не меняет", again == book
			and GrimoireRules.parse_grimoire(again) == again)


func _check_game_state() -> void:
	var saved: Dictionary = GameState.to_dict()
	GameState.new_game()
	EventBus.recipe_discovered.connect(_on_discovered)
	EventBus.grimoire_page_golden.connect(_on_golden)
	EventBus.save_requested.connect(_on_save_requested)
	var strange: StringName = GameState.record_brew(_mix(STRANGE_THREE))
	_check("GameState: «Странная смесь» — &\"\", Гримуар пуст, записи нет", strange == &""
			and GameState.grimoire.is_empty() and _saves.is_empty())
	var id: StringName = GameState.record_brew({LIFE: STRONG})
	var key: String = String(BALM)
	_check("GameState: бальзам узнан, страница открыта, сигнал и запись — по одному", id == BALM
			and _discovered == [BALM] and _saves == [GameState.REASON_GRIMOIRE]
			and _page_is(GameState.grimoire[key], 1, TOP, TOP, 1))
	GameState.record_brew({LIFE: STRONG, HEAT: DIRTY_HEAT})
	GameState.record_brew({LIFE: STRONG})
	_check("GameState: две безупречных из трёх — ещё не золотая", _golden.is_empty()  # noqa: magic
			and _page_is(GameState.grimoire[key], 3, 3, 3, 2))
	GameState.record_brew({LIFE: STRONG, HEAT: FLAWLESS_HEAT})
	_check("GameState: третья безупречная — золотая, сигнал один раз", _golden == [BALM]  # noqa: magic
			and _page_is(GameState.grimoire[key], 4, 3, 3, 3))
	GameState.record_brew({LIFE: STRONG})
	_check("GameState: дальше сигналов открытия и золота нет", _golden.size() == 1 and _discovered.size() == 1  # noqa: magic
			and _saves.size() == 5)
	var book: Dictionary = GameState.grimoire.duplicate(true)
	var loaded: bool = GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	_check("GameState: сохранение → JSON → загрузка — Гримуар тот же", loaded and GameState.grimoire == book)
	EventBus.recipe_discovered.disconnect(_on_discovered)
	EventBus.grimoire_page_golden.disconnect(_on_golden)
	EventBus.save_requested.disconnect(_on_save_requested)
	GameState.from_dict(saved)


# --- помощники -------------------------------------------------------------------------------------------------------

func _pure(recipe: RecipeData, amount: float) -> Dictionary[StringName, float]:
	var mixture: Dictionary[StringName, float] = {}
	for property_id: StringName in recipe.property_set:
		mixture[property_id] = amount
	return mixture


func _mix(ids: Array[StringName]) -> Dictionary[StringName, float]:
	var mixture: Dictionary[StringName, float] = {}
	for property_id: StringName in ids:
		mixture[property_id] = 1.0
	return mixture


## Та же смесь с ключами в обратном порядке.
func _reversed(mixture: Dictionary[StringName, float]) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	var keys: Array = mixture.keys()
	keys.reverse()
	for property_id: StringName in keys:
		result[property_id] = mixture[property_id]
	return result


## Набор свойств рецепта строкой, без учёта порядка.
func _set_key(recipe: RecipeData) -> String:
	var names: PackedStringArray = []
	for property_id: StringName in recipe.property_set:
		names.append(String(property_id))
	names.sort()
	return ",".join(names)


## Первое свойство каталога, которого нет в рецепте (для следов и примесей).
func _outsider(recipe: RecipeData) -> StringName:
	for property: PropertyData in catalog.properties:
		if not recipe.property_set.has(property.id):
			return property.id
	return &""


func _id(mixture: Dictionary) -> StringName:
	var recipe: RecipeData = GrimoireRules.recognize(mixture, catalog)
	return recipe.id if recipe != null else &""


func _result(strength: int, purity: int, flawless: bool) -> Dictionary:
	return {GrimoireRules.BREW_STRENGTH: strength, GrimoireRules.BREW_PURITY: purity,
			GrimoireRules.BREW_FLAWLESS: flawless}


func _brew_is(result: Dictionary, strength: int, purity: int, flawless: bool) -> bool:
	return (int(result[GrimoireRules.BREW_STRENGTH]) == strength and int(result[GrimoireRules.BREW_PURITY]) == purity
			and bool(result[GrimoireRules.BREW_FLAWLESS]) == flawless)


func _page_is(page: Variant, brews: int, strength: int, purity: int, flawless: int) -> bool:
	if not (page is Dictionary):
		return false
	var d: Dictionary = page
	return (d.get(GrimoireRules.KEY_BREWS) is int and int(d[GrimoireRules.KEY_BREWS]) == brews
			and int(d.get(GrimoireRules.KEY_BEST_STRENGTH, -1)) == strength
			and int(d.get(GrimoireRules.KEY_BEST_PURITY, -1)) == purity
			and int(d.get(GrimoireRules.KEY_FLAWLESS, -1)) == flawless)


func _on_discovered(recipe_id: StringName) -> void:
	_discovered.append(recipe_id)


func _on_golden(recipe_id: StringName) -> void:
	_golden.append(recipe_id)


func _on_save_requested(reason: StringName) -> void:
	_saves.append(reason)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  [OK] ", title)
	else:
		push_error("GRIMOIRE CHECK: не прошло — " + title)
		print("  [!!] ", title)


func _finish() -> void:
	print("GRIMOIRE CHECK: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])
