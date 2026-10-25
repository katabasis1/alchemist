## Main — корневая сцена: запуск сервисов по порядку под экраном загрузки и сигнал платформе, что игра готова.
## Порядок: Platform.initialize → язык платформы → SaveService.load_game → язык из настроек (если игрок выбрал)
## → звук → экран загрузки тает → Platform.loading_ready. Язык ставится дважды, чтобы экран загрузки
## сразу говорил на языке игрока, а выбор из сохранения всё равно побеждал.
## Сигналы: нет (глобально — EventBus.game_ready).
## Зависимости: Platform, SaveService, GameState, AudioDirector, EventBus; LoadingScreen (@export loading_screen).
extends Node

## Языки игры (ru/en). Остальные: русскоязычные регионы — ru, прочие — en.
const LOCALES: PackedStringArray = ["ru", "en"]
const RU_REGION_LANGS: PackedStringArray = ["ru", "uk", "be", "kk", "uz"]
const LOCALE_RU: String = "ru"
const LOCALE_FALLBACK: String = "en"

@export var loading_screen: LoadingScreen


func _ready() -> void:
	await Platform.initialize()
	TranslationServer.set_locale(_resolve_locale())
	loading_screen.advance()
	await SaveService.load_game()
	TranslationServer.set_locale(_resolve_locale())
	loading_screen.advance()
	AudioDirector.apply_settings()
	loading_screen.advance()
	await loading_screen.finish()
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
