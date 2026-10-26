## L10nCheck — проверка локализации в Godot (F6 на этой сцене), пока у агента нет движка.
## Проверяет: переводы ru/en подключены; у каждого ключа из данных (*_key в data/*.tres) и интерфейса
## есть текст на обоих языках; в шрифтах темы есть все символы этих текстов; тема проекта — main_theme;
## смена языка меняет текст. Итог — в Output строкой «L10N: x/y».
## На экране — образцы текста шрифтами темы; язык переключается сам по SwitchTimer (2 с, задаётся в сцене),
## Label переводятся без кода — так видно, что живая смена языка работает.
## Без Godot ключи проверяет python tools/validate_project.py (L007, L011).
## Сигналы: нет. Зависимости: DataCatalog, Theme, Timer (@export).
extends Control

const LOCALES: PackedStringArray = ["ru", "en"]
## Ключи интерфейса, которых нет в данных.
const UI_KEYS: Array[StringName] = [&"GAME_TITLE", &"LOADING_TEXT", &"LANGUAGE_NAME", &"PROP_FLASK_NAME"]
const FONT_ITEM: StringName = &"font"
const FONT_VARIATIONS: Array[StringName] = [&"TitleLabel", &"BoldLabel"]
const PROBE_KEY: StringName = &"GAME_TITLE"
## Сколько пропущенных ключей или символов перечислить в строке отчёта.
const LIST_LIMIT: int = 8

@export var catalog: DataCatalog
@export var ui_theme: Theme
@export var switch_timer: Timer

var _passed: int = 0
var _total: int = 0
var _locale_index: int = 0


func _ready() -> void:
	_run_checks()
	if switch_timer != null:
		switch_timer.timeout.connect(_on_switch_timeout)


func _run_checks() -> void:
	var start_locale: String = TranslationServer.get_locale()
	_check("каталог и тема заданы", catalog != null and ui_theme != null)
	if catalog == null or ui_theme == null:
		_finish()
		return
	_check("тема проекта — main_theme (Project Settings → GUI → Theme → Custom)",
			ThemeDB.get_project_theme() == ui_theme)
	var loaded: PackedStringArray = TranslationServer.get_loaded_locales()
	for loc: String in LOCALES:
		_check("перевод %s подключён (Project Settings → Localization)" % loc, loc in loaded)
	var keys: Array[StringName] = _collect_keys()
	var fonts: Array[Font] = [ui_theme.default_font]
	for variation: StringName in FONT_VARIATIONS:
		fonts.append(ui_theme.get_font(FONT_ITEM, variation))
	var probes: Array[String] = []
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		var missing: Array[String] = []
		var no_glyph: Array[String] = []
		for key: StringName in keys:
			var text: String = String(TranslationServer.translate(key))
			if text.is_empty() or text == String(key):
				missing.append(String(key))
				continue
			for i: int in text.length():
				for font: Font in fonts:
					if font != null and not font.has_char(text.unicode_at(i)) and not no_glyph.has(text[i]):
						no_glyph.append(text[i])
		_check("%s: тексты для всех %d ключей%s" % [loc, keys.size(), _list(missing)], missing.is_empty())
		_check("%s: в шрифтах темы есть все символы%s" % [loc, _list(no_glyph)], no_glyph.is_empty())
		probes.append(String(TranslationServer.translate(PROBE_KEY)))
	_check("смена языка меняет текст (%s)" % " / ".join(PackedStringArray(probes)),
			probes.size() == LOCALES.size() and probes[0] != probes[1])
	TranslationServer.set_locale(start_locale)
	_finish()


func _collect_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	keys.append_array(UI_KEYS)
	for item: PropertyData in catalog.properties:
		keys.append(item.name_key)
	for item: IngredientData in catalog.ingredients:
		keys.append(item.name_key)
	for item: RecipeData in catalog.recipes:
		keys.append(item.name_key)
		keys.append(item.desc_key)
	for item: ClientData in catalog.clients:
		keys.append(item.name_key)
	for item: ToolData in catalog.tools:
		keys.append(item.name_key)
		keys.append(item.desc_key)
	for item: RankData in catalog.ranks:
		keys.append(item.name_key)
	for order: OrderTemplate in catalog.all_orders():
		keys.append(order.line_key)
	var unique: Array[StringName] = []
	for key: StringName in keys:
		if key == &"":
			_check("пустой ключ в данных", false)
		elif not unique.has(key):
			unique.append(key)
	return unique


func _on_switch_timeout() -> void:
	_locale_index = (_locale_index + 1) % LOCALES.size()
	TranslationServer.set_locale(LOCALES[_locale_index])


func _list(items: Array[String]) -> String:
	if items.is_empty():
		return ""
	var shown: PackedStringArray = PackedStringArray(items.slice(0, LIST_LIMIT))
	return ": нет — " + ", ".join(shown) + (" …" if items.size() > LIST_LIMIT else "")


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  [OK] ", title)
	else:
		push_error("L10N: не прошло — " + title)
		print("  [!!] ", title)


func _finish() -> void:
	print("L10N: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])
