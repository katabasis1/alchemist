## Platform — адаптер платформы: готовность, язык, время сервера, сохранения, реклама, пауза.
## Игра обращается только к Platform. Бэкенд — дочерний узел с тем же набором методов:
## PlatformMock (редактор и ПК) сейчас, PlatformYandex (плагин YandexGamesSDK4Godot) — на S10.
## На время рекламы и при потере фокуса ставит дерево на паузу и сообщает EventBus.pause_changed,
## AudioDirector глушит звук (Яндекс 1.3, 4.7).
## Сигналы: fullscreen_closed(shown), rewarded_finished(placement, rewarded).
## Зависимости: EventBus; бэкенды задаются через @export.
extends Node

signal fullscreen_closed(shown: bool)
signal rewarded_finished(placement: StringName, rewarded: bool)

const PAUSE_AD: StringName = &"ad"
const PAUSE_FOCUS: StringName = &"focus"

## Бэкенд для редактора и ПК.
@export var mock_backend: Node
## Бэкенд Яндекс Игр (S10). Пока не задан — везде работает mock.
@export var yandex_backend: Node
## Пауза при потере фокуса окна/вкладки. В редакторе можно выключить, чтобы игра не замирала.
@export var pause_on_focus_loss: bool = true

var is_initialized: bool = false
var is_ad_showing: bool = false

var _backend: Node
var _pause_reasons: Dictionary = {}


func _ready() -> void:
	if yandex_backend != null and OS.has_feature("web"):
		_backend = yandex_backend
	else:
		_backend = mock_backend
	if _backend == null:
		push_error("Platform: бэкенд не задан")


func backend_name() -> String:
	return String(_backend.name) if _backend != null else "none"


## Подключение к SDK. Вызывать один раз при старте, до загрузки сохранения.
func initialize() -> void:
	if is_initialized:
		return
	await _backend.initialize()
	is_initialized = true


## Игра загрузилась и готова к игре (Яндекс: LoadingAPI.ready).
func loading_ready() -> void:
	_backend.loading_ready()


## Начало и конец активного геймплея (Яндекс: GameplayAPI.start / stop).
func gameplay_start() -> void:
	_backend.gameplay_start()


func gameplay_stop() -> void:
	_backend.gameplay_stop()


## Код языка платформы, например "ru" или "en".
func get_language() -> String:
	return _backend.get_language()


## Время сервера в секундах Unix (ежедневная награда считается по нему, GDD §8).
func get_server_time_unix() -> int:
	return _backend.get_server_time_unix()


func save_data(data: Dictionary) -> bool:
	return await _backend.save_data(data)


## Пустой словарь — сохранения нет или оно не читается.
func load_data() -> Dictionary:
	return await _backend.load_data()


## Полноэкранная реклама: только между днями, не во время активной игры (GDD §8).
func show_fullscreen_ad() -> bool:
	if is_ad_showing:
		return false
	_begin_ad()
	var shown: bool = await _backend.show_fullscreen_ad()
	_end_ad()
	fullscreen_closed.emit(shown)
	return shown


## Реклама за награду. true — награду можно выдать.
func show_rewarded_ad(placement: StringName) -> bool:
	if is_ad_showing:
		return false
	_begin_ad()
	var rewarded: bool = await _backend.show_rewarded_ad(placement)
	_end_ad()
	rewarded_finished.emit(placement, rewarded)
	return rewarded


func is_paused() -> bool:
	return not _pause_reasons.is_empty()


## Пауза складывается из причин: игра идёт, только когда причин не осталось.
func set_paused(reason: StringName, paused: bool) -> void:
	var was_paused: bool = is_paused()
	if paused:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)
	var now_paused: bool = is_paused()
	if now_paused == was_paused:
		return
	get_tree().paused = now_paused
	if now_paused:
		_backend.gameplay_stop()
	else:
		_backend.gameplay_start()
	EventBus.pause_changed.emit(now_paused)


func _begin_ad() -> void:
	is_ad_showing = true
	set_paused(PAUSE_AD, true)


func _end_ad() -> void:
	is_ad_showing = false
	set_paused(PAUSE_AD, false)


func _notification(what: int) -> void:
	if not pause_on_focus_loss or _backend == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_paused(PAUSE_FOCUS, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_paused(PAUSE_FOCUS, false)
