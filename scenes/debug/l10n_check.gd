## L10nCheck — проверка локализации в Godot (F6 на этой сцене), пока у агента нет движка.
## Проверяет: переводы ru и en подключены; каждый ключ из данных (name_key, desc_key, line_key)
## и интерфейса переводится на оба языка; смена языка на лету меняет текст; тема проекта задана,
## в ней есть варианты, на которые ссылаются сцены; в шрифтах темы есть все символы переводов.
## Итог — в Output строкой «L10N: x/y». Без Godot ключи проверяет tools/validate_project.py,
## символы — python tools/fonts/build_fonts.py --check.
## Сигналы: нет. Зависимости: DataCatalog (@export), Theme (@export ui_theme), TranslationServer.
extends Node

const LOCALES: PackedStringArray = ["ru", "en"]
const THEME_SETTING: String = "gui/theme/custom"
## Ключи интерфейса, которых нет в данных: экран загрузки, названия языков, демо-колба.
const UI_KEYS: Array[StringName] = [&"GAME_TITLE", &"LOADING", &"LANG_RU", &"LANG_EN", &"PROP_FLASK_NAME"]
## Варианты темы, на которые ссылаются сцены (theme_type_variation).
const THEME_VARIATIONS: Array[StringName] = [&"TitleLabel", &"HeaderLabel", &"LightLabel", &"TooltipLabel", &"TooltipPanel"]
## Первый печатный символ: перевод строки и прочие управляющие в шрифте не нужны.
const FIRST_PRINTABLE: int = 32
## Варианты темы со своими шрифтами (кроме шрифта по умолчанию).
const FONT_OWNERS: Array[StringName] = [&"TitleLabel", &"Button"]
const FONT_NAME: StringName = &"font"

@export var catalog: DataCatalog
@export var ui_theme: Theme

var _passed: int = 0
var _total: int = 0


func _ready() -> void:
	var start_locale: String = TranslationServer.get_locale()
	var loaded: PackedStringArray = TranslationServer.get_loaded_locales()
	_check("переводы подключены: %s" % ", ".join(LOCALES), _has_all(loaded, LOCALES))
	var keys: Array[StringName] = _collect_keys()
	_check("ключей к проверке: %d" % keys.size(), keys.size() > UI_KEYS.size())
	var texts: Array[String] = []
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		var missing: Array[StringName] = []
		for key: StringName in keys:
			var text: String = tr(key)
			if text == String(key) or text.is_empty():
				missing.append(key)
			else:
				texts.append(text)
		_check("%s: переводятся все ключи%s" % [loc, _list(missing)], missing.is_empty())
	TranslationServer.set_locale(LOCALES[0])
	var first: String = tr(&"GAME_TITLE")
	TranslationServer.set_locale(LOCALES[1])
	_check("смена языка на лету меняет текст", tr(&"GAME_TITLE") != first)
	TranslationServer.set_locale(start_locale)
	_check_theme()
	_check_glyphs(texts)
	_finish()


func _collect_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	keys.append_array(UI_KEYS)
	if catalog == null:
		return keys
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
	for item: OrderTemplate in catalog.all_orders():
		keys.append(item.line_key)
	return keys


func _check_theme() -> void:
	_check("тема загружена, шрифт по умолчанию задан", ui_theme != null and ui_theme.default_font != null)
	if ui_theme == null:
		return
	_check("тема проекта (%s) — ui/theme/main_theme.tres" % THEME_SETTING,
		str(ProjectSettings.get_setting(THEME_SETTING, "")) == ui_theme.resource_path)
	var absent: Array[StringName] = []
	for variation: StringName in THEME_VARIATIONS:
		if ui_theme.get_type_variation_base(variation) == &"":
			absent.append(variation)
	_check("варианты темы на месте%s" % _list(absent), absent.is_empty())


func _check_glyphs(texts: Array[String]) -> void:
	if ui_theme == null or ui_theme.default_font == null:
		return
	var fonts: Array[Font] = [ui_theme.default_font]
	for type_name: StringName in FONT_OWNERS:
		if ui_theme.has_font(FONT_NAME, type_name):
			fonts.append(ui_theme.get_font(FONT_NAME, type_name))
	var lacking: PackedStringArray = []
	for font: Font in fonts:
		for text: String in texts:
			for i: int in text.length():
				var code: int = text.unicode_at(i)
				var symbol: String = text[i]
				if code >= FIRST_PRINTABLE and not font.has_char(code) and not lacking.has(symbol):
					lacking.append(symbol)
	_check("в шрифтах темы (%d) есть все символы переводов%s" % [fonts.size(), " — нет: " + "".join(lacking) if not lacking.is_empty() else ""],
		lacking.is_empty())


func _has_all(have: PackedStringArray, need: PackedStringArray) -> bool:
	for item: String in need:
		if not have.has(item):
			return false
	return true


func _list(keys: Array[StringName]) -> String:
	if keys.is_empty():
		return ""
	var names: PackedStringArray = []
	for key: StringName in keys:
		names.append(String(key))
	return " — нет: " + ", ".join(names)


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
