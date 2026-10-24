## Main — корневая сцена: запуск сервисов по порядку и сигнал платформе, что игра готова.
## Порядок: Platform.initialize → SaveService.load_game → язык и звук из настроек → Platform.loading_ready.
## Сигналы: нет (глобально — EventBus.game_ready).
## Зависимости: Platform, SaveService, GameState, AudioDirector, EventBus.
extends Node

## Языки игры (ru/en). Остальные: русскоязычные регионы — ru, прочие — en.
const LOCALES: PackedStringArray = ["ru", "en"]
const RU_REGION_LANGS: PackedStringArray = ["ru", "uk", "be", "kk", "uz"]
const LOCALE_RU: String = "ru"
const LOCALE_FALLBACK: String = "en"


func _ready() -> void:
	await Platform.initialize()
	await SaveService.load_game()
	TranslationServer.set_locale(_resolve_locale())
	AudioDirector.apply_settings()
	Platform.loading_ready()
	Platform.gameplay_start()
	EventBus.game_ready.emit()
	print_verbose("Main: готово (бэкенд %s, язык %s)" % [Platform.backend_name(), TranslationServer.get_locale()])


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
