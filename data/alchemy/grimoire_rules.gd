## GrimoireRules — распознавание рецептов и страницы Гримуара (GDD §3.5).
## Только расчёт: статические чистые функции без узлов и без состояния, как AlchemyRules (GrimoireRules.recognize(…)).
## Рецепт узнаётся по набору значимых свойств зелья (не меньше порога значимости), следы не мешают; такого набора нет
## в каталоге — «Странная смесь» (null), страницы у неё нет. Зелье оценивается по своему рецепту, а не по заказу: одна
## оценка годится и для клиента (даже если он отказался), и для Ростка-проверяльщика. Сила — самое слабое свойство
## рецепта, чистота — доли свойств рецепта / все доли, «безупречно» — AlchemyRules.is_flawless.
## Страница — словарь из четырёх целых KEY_*: варок, лучшая сила, лучшая чистота (звёзды, у каждой свой рекорд),
## «безупречных». Открыта — страница есть в GameState.grimoire. Золотая — «безупречных» не меньше
## EconomyConfig.golden_page_flawless; не хранится, чтобы правило жило в одном месте.
## Сохранение читается через parse_grimoire: снаружи что угодно (JSON даёт float, старый формат, мусор), внутри —
## только нормальные страницы. Повторный разбор ничего не меняет.
## Эталон на Python — tools/alchemy/grimoire_model.py: правило меняется в обоих местах сразу.
## Кто пользуется: GameState.record_brew (зелье отдали клиенту), стенд S3.3, Гримуар и Росток (S5+).
## Сигналы: нет. Зависимости: AlchemyRules (значимость, сила, чистота, «безупречно»), DataCatalog (рецепт по набору
##   свойств), RecipeData, EconomyConfig (порог значимости, звёзды, порог золотой страницы).
class_name GrimoireRules
extends RefCounted

## Ключи страницы. Строки, а не StringName: страница целиком уходит в JSON сохранения.
const KEY_BREWS: String = "brews"
const KEY_BEST_STRENGTH: String = "best_strength"
const KEY_BEST_PURITY: String = "best_purity"
const KEY_FLAWLESS: String = "flawless"
## Ключи итога варки brew().
const BREW_STRENGTH: StringName = &"strength"
const BREW_PURITY: StringName = &"purity"
const BREW_FLAWLESS: StringName = &"flawless"


## Рецепт зелья по его значимым свойствам; null — «Странная смесь».
static func recognize(mixture: Dictionary, catalog: DataCatalog) -> RecipeData:
	return catalog.recipe_for(AlchemyRules.significant(mixture, catalog.economy))


## Оценка зелья как рецепта recipe: {BREW_STRENGTH: 0…3, BREW_PURITY: 0…3, BREW_FLAWLESS: bool}.
static func brew(mixture: Dictionary, recipe: RecipeData, economy: EconomyConfig) -> Dictionary:
	var strength: int = AlchemyRules.weakest_stars(mixture, recipe.property_set, economy)
	var purity: int = AlchemyRules.purity_stars(AlchemyRules.purity(mixture, recipe.property_set), economy)
	return {
		BREW_STRENGTH: strength,
		BREW_PURITY: purity,
		BREW_FLAWLESS: AlchemyRules.is_flawless(strength, purity, economy),
	}


## Страница из чего угодно: не словарь или нет ключа — 0, float из JSON — целое, отрицательное и не число — 0,
## лишние ключи отброшены.
static func parse_page(value: Variant) -> Dictionary:
	var source: Dictionary = {}
	if value is Dictionary:
		source = value
	return {
		KEY_BREWS: _count(source.get(KEY_BREWS)),
		KEY_BEST_STRENGTH: _count(source.get(KEY_BEST_STRENGTH)),
		KEY_BEST_PURITY: _count(source.get(KEY_BEST_PURITY)),
		KEY_FLAWLESS: _count(source.get(KEY_FLAWLESS)),
	}


## Гримуар из сохранения: id рецепта (строка) → страница. Не словарь — пустой Гримуар; пустой ключ отброшен;
## страница-мусор — открыта, но с нулями (ключ и есть открытие). Рецепты, которых нет в каталоге, не трогаем.
static func parse_grimoire(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	var source: Dictionary = value
	for key: Variant in source:
		var recipe_id: String = str(key)
		if recipe_id.is_empty():
			continue
		result[recipe_id] = parse_page(source[key])
	return result


## Страница после ещё одной варки result (из brew): варок +1, рекорды силы и чистоты — каждый по максимуму,
## «безупречных» +1, если варка безупречная. page может быть null (рецепт открыт этой варкой). Вход не меняется.
static func after_brew(page: Variant, result: Dictionary) -> Dictionary:
	var page_after: Dictionary = parse_page(page)
	page_after[KEY_BREWS] = int(page_after[KEY_BREWS]) + 1
	page_after[KEY_BEST_STRENGTH] = maxi(int(page_after[KEY_BEST_STRENGTH]), int(result[BREW_STRENGTH]))
	page_after[KEY_BEST_PURITY] = maxi(int(page_after[KEY_BEST_PURITY]), int(result[BREW_PURITY]))
	if bool(result[BREW_FLAWLESS]):
		page_after[KEY_FLAWLESS] = int(page_after[KEY_FLAWLESS]) + 1
	return page_after


## Золотая страница (GDD §3.5): «безупречных» варок не меньше EconomyConfig.golden_page_flawless.
static func is_golden(page: Dictionary, economy: EconomyConfig) -> bool:
	return _count(page.get(KEY_FLAWLESS)) >= economy.golden_page_flawless


## Счётчик из сохранения: целое не меньше 0. bool и строка — не число (true не станет единицей).
static func _count(value: Variant) -> int:
	if value is int or value is float:
		return maxi(int(value), 0)
	return 0
