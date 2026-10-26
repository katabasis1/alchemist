## Main — корневая сцена: запуск сервисов по порядку и сигнал платформе, что игра готова.
## Порядок: экран загрузки виден → Platform.initialize → язык платформы → SaveService.load_game →
## язык и звук из настроек → экран загрузки убран → Platform.loading_ready.
## Язык: настройка игрока (если выбрана) → язык платформы → русскоязычные регионы — ru, прочие — en.
## Смена настройки языка применяется сразу (EventBus.settings_changed): Label переводятся сами.
## Сигналы: нет (глобально — EventBus.game_ready).
## Зависимости: Platform, SaveService, GameState, AudioDirector, EventBus; loading_screen (@export).
extends Node

## Языки игры (ru/en). Остальные: русскоязычные регионы — ru, прочие — en.
const LOCALES: PackedStringArray = ["ru", "en"]
const RU_REGION_LANGS: PackedStringArray = ["ru", "uk", "be", "kk", "uz"]
const LOCALE_RU: String = "ru"
const LOCALE_FALLBACK: String = "en"

@export var loading_screen: LoadingScreen


func _ready() -> void:
	await Platform.initialize()
	_apply_locale()
	await SaveService.load_game()
	_apply_locale()
	AudioDirector.apply_settings()
	EventBus.settings_changed.connect(_apply_locale)
	if loading_screen != null:
		await loading_screen.hide_screen()
	Platform.loading_ready()
	Platform.gameplay_start()
	EventBus.game_ready.emit()
	print_verbose("Main: готово (бэкенд %s, язык %s)" % [Platform.backend_name(), TranslationServer.get_locale()])


func _apply_locale() -> void:
	var locale: String = _resolve_locale()
	if TranslationServer.get_locale() != locale:
		TranslationServer.set_locale(locale)


func _resolve_locale() -> String:
	var chosen: String = str(GameState.get_setting(GameState.SETTING_LOCALE))
	if chosen in LOCALES:
		return chosen
	var lang: String = Platform.get_language().to_lower().left(LOCALE_RU.length())
	if lang in LOCALES:
		return lang
	if lang in RU_REGION_LANGS:
		return LOCALE_RU
	return LOCALE_FALLBACK
