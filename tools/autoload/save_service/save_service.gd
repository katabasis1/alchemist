## SaveService — загрузка и запись GameState через Platform (сейчас mock → user://, на S10 — облако Яндекса).
## Пишет одной записью сразу после действия игрока (GDD §11, Яндекс 1.9). Несколько запросов за кадр
## сливаются в одну запись; запрос во время записи ставится в очередь. До загрузки ничего не пишет,
## чтобы не затереть облачное сохранение значениями по умолчанию.
## Сигналы: loaded(ok), saved(ok).
## Зависимости: EventBus (save_requested), GameState, Platform.
extends Node

signal loaded(ok: bool)
signal saved(ok: bool)

var is_loaded: bool = false
var is_writing: bool = false

var _flush_scheduled: bool = false
var _dirty_while_writing: bool = false
var _last_reason: StringName = &""


func _ready() -> void:
	EventBus.save_requested.connect(_on_save_requested)


## Прочитать сохранение и применить к GameState. Пустое сохранение — новая игра.
func load_game() -> bool:
	var data: Dictionary = await Platform.load_data()
	var ok: bool = true
	if data.is_empty():
		GameState.new_game()
	else:
		ok = GameState.from_dict(data)
	is_loaded = true
	loaded.emit(ok)
	return ok


## Стереть прогресс (для отладки и кнопки «Начать заново» в настройках).
func reset_progress() -> void:
	GameState.new_game(true)


func _on_save_requested(reason: StringName) -> void:
	_last_reason = reason
	if is_writing:
		_dirty_while_writing = true
		return
	if _flush_scheduled:
		return
	_flush_scheduled = true
	_flush.call_deferred()


func _flush() -> void:
	_flush_scheduled = false
	if not is_loaded:
		push_warning("SaveService: запись до загрузки пропущена (%s)" % _last_reason)
		return
	is_writing = true
	var ok: bool = await Platform.save_data(GameState.to_dict())
	is_writing = false
	if not ok:
		push_warning("SaveService: запись не удалась (%s)" % _last_reason)
	saved.emit(ok)
	if _dirty_while_writing:
		_dirty_while_writing = false
		_on_save_requested(_last_reason)
