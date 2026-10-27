## PlaytestRecorder — замеры плейтеста M2 (S2.5, docs/playtest/PLAYTEST_M2.md): что игрок делает со ступкой и заказами.
## Каждая запись — строка JSON в user://playtest/session_<дата>.jsonl (пишется сразу: вкладку могут закрыть в любой момент)
## и та же строка в Output с префиксом «PLAYTEST » (summarize.py берёт записи и из файла, и из скопированного лога).
## Записи (поле "type"): session — шапка сессии (версия, платформа, настройки помола); batch — партия в ступке от первого
## ингредиента до пустой чаши: время и круги до «идеально», перетёр, итоговый помол, тапы и жесты, чем кончилась;
## order — заказ от прихода клиента до оплаты или ухода: время, попытки, отказы, звёзды, оплата; event — пауза, поворот.
## Формат полей — docs/playtest/PLAYTEST_M2.md, «Формат записей». Время — по Time.get_ticks_msec() без пауз: пока игра
## на паузе (свёрнутая вкладка, реклама), часы записи стоят.
## Включён, только если enabled и сборка отладочная (редактор, debug-экспорт); с debug_only = false — и в релизе.
## Стоит в main.tscn, а не в лавке: проверочные сцены с лавкой (order_check и др.) файлов не пишут.
## Сигналы: recorded(record) — запись готова (её же добавили в records).
## Зависимости: OrderDesk, Client, Mortar (@export; у ступки — StateMachine, GrindGesture, EconomyConfig),
##   GameState (каталог, шаг обучения, ранг, монеты, серия), EventBus (pause_changed, layout_changed), LayoutSwitcher.portrait.
class_name PlaytestRecorder
extends Node

signal recorded(record: Dictionary)

## Версия формата записей: поднимать, если поля меняют смысл (summarize.py её читает).
const SCHEMA: int = 1
const TYPE_SESSION: String = "session"
const TYPE_BATCH: String = "batch"
const TYPE_ORDER: String = "order"
const TYPE_EVENT: String = "event"
const EVENT_PAUSE: String = "pause"
const EVENT_LAYOUT: String = "layout"
## Чем кончилась партия: отдана клиенту, выброшена в мусор, ингредиенты вернулись на полку без помола.
const OUTCOME_HANDED: String = "handed"
const OUTCOME_DISCARDED: String = "discarded"
const OUTCOME_RETURNED: String = "returned"
## Чем кончился заказ: оплачен; клиент ушёл без оплаты (новая игра, смена заказа).
const RESULT_PAID: String = "paid"
const RESULT_LEFT: String = "left"
## Префикс строк в Output.
const LOG_PREFIX: String = "PLAYTEST "
const MSEC_PER_SEC: float = 1000.0
## Точность чисел в записях: секунды и помол.
const SEC_STEP: float = 0.01
const GRIND_STEP: float = 0.001
## Допуск сравнения помола с границами зоны.
const EPSILON: float = 0.0001
## «Нет данных» в сводке (медиана пустого списка).
const NO_DATA: float = -1.0
const VERSION_SETTING: String = "application/config/version"
const FILE_PREFIX: String = "session_"
const FILE_EXT: String = ".jsonl"

@export var desk: OrderDesk
@export var client: Client
@export var mortar: Mortar
## Выключенный ни к чему не подключается и ничего не пишет.
@export var enabled: bool = true
## Только в отладочной сборке: в релизном экспорте выключен.
@export var debug_only: bool = true
## Папка файлов сессий (один запуск игры — один файл).
@export var folder: String = "user://playtest"
## Писать файл; false — только Output и records.
@export var write_file: bool = true
## Печатать записи и короткий итог после каждого заказа в Output.
@export var print_records: bool = true

## Все записи сессии по порядку; первая — шапка session.
var records: Array[Dictionary] = []
## Файл сессии; пусто — ещё не создан (создаётся на первой записи).
var file_path: String = ""

var _active: bool = false
var _start_msec: int = 0
var _paused_msec: int = 0
var _paused_since: int = -1

# Партия в ступке (часы записи, мс; -1 — ещё не было).
var _batch_open: bool = false
var _batch_start: int = 0
var _batch_first: int = -1
var _grind_since: int = -1
var _batch_active: int = 0
var _perfect_wall: int = -1
var _perfect_active: int = -1
var _batch_ids: Array[StringName] = []
var _batch_hardness: int = 0
var _batch_grind: float = 0.0
var _batch_max: float = 0.0
var _batch_circles: float = 0.0
var _batch_taps: int = 0
var _batch_gestures: int = 0
var _batch_ends: Dictionary = {}
## Запись партии, которая только что опустела: отдана ли она клиенту, станет ясно в том же кадре (handed_off).
var _closing: Dictionary = {}

# Заказ.
var _order_open: bool = false
var _order: Dictionary = {}
var _order_from: int = 0
var _first_drop: int = -1
var _first_attempt: int = -1
var _last_attempt: int = -1
var _attempts: Array[Dictionary] = []


func _ready() -> void:
	_active = (enabled and (OS.is_debug_build() or not debug_only)
			and desk != null and client != null and mortar != null)
	if not _active:
		return
	_start_msec = Time.get_ticks_msec()
	desk.order_started.connect(_on_order_started)
	desk.order_paid.connect(_on_order_paid)
	client.arrived.connect(_on_client_arrived)
	client.refused.connect(_on_client_refused)
	client.drop_refused.connect(_on_client_drop_refused)
	client.left.connect(_on_client_left)
	mortar.state_machine.state_changed.connect(_on_mortar_state_changed)
	mortar.grind_changed.connect(_on_grind_changed)
	mortar.contents_changed.connect(_on_contents_changed)
	mortar.drop_refused.connect(_on_mortar_drop_refused)
	mortar.handed_off.connect(_on_handed_off)
	mortar.gesture.turned.connect(_on_turned)
	mortar.gesture.ended.connect(_on_gesture_ended)
	EventBus.pause_changed.connect(_on_pause_changed)
	EventBus.layout_changed.connect(_on_layout_changed)


func is_active() -> bool:
	return _active


## Сводка сессии: orders — оплачено заказов; order_sec — медиана времени заказа; perfect_sec — медиана времени
## до «идеально»; ground — партий с помолом; overshoot — из них перетёрто; handed / in_zone — отдано клиенту и из них
## с помолом в зоне. Медиана без данных — NO_DATA.
func summary() -> Dictionary:
	var order_secs: Array[float] = []
	var perfect_secs: Array[float] = []
	var ground: int = 0
	var overshoot: int = 0
	var handed: int = 0
	var in_zone: int = 0
	for record: Dictionary in records:
		var type: String = str(record.get("type", ""))
		if type == TYPE_ORDER and record.get("result") == RESULT_PAID:
			order_secs.append(float(record["order_sec"]))
		elif type == TYPE_BATCH and float(record["max_grind"]) > 0.0:
			ground += 1
			if bool(record["overshoot"]):
				overshoot += 1
			if record["perfect_sec"] != null:
				perfect_secs.append(float(record["perfect_sec"]))
			if record["outcome"] == OUTCOME_HANDED:
				handed += 1
				if bool(record["in_zone"]):
					in_zone += 1
	return {"orders": order_secs.size(), "order_sec": median(order_secs), "perfect_sec": median(perfect_secs),
			"ground": ground, "overshoot": overshoot, "handed": handed, "in_zone": in_zone}


static func median(values: Array[float]) -> float:
	if values.is_empty():
		return NO_DATA
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var mid: int = floori(sorted.size() * 0.5)
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) * 0.5


# --- ступка: партия ------------------------------------------------------------------------------------------------

func _on_mortar_state_changed(from: StringName, to: StringName) -> void:
	var now: int = _clock()
	if from == Mortar.STATE_GRINDING and _grind_since >= 0:
		_batch_active += now - _grind_since
		_grind_since = -1
	if to == Mortar.STATE_EMPTY:
		if _batch_open:
			_close_batch(now)
		return
	if not _batch_open:
		_open_batch(now)
	if to == Mortar.STATE_GRINDING:
		_grind_since = now
		if _batch_first < 0:
			_batch_first = now


func _on_contents_changed(ids: Array[StringName]) -> void:
	if ids.is_empty():
		return
	_batch_ids = ids.duplicate()
	_batch_hardness = mortar.hardest()
	if _order_open and _first_drop < 0:
		_first_drop = _clock()


func _on_grind_changed(value: float) -> void:
	# Сброс помола у опустевшей ступки — не помол.
	if not _batch_open or mortar.state_machine.is_in(Mortar.STATE_EMPTY):
		return
	var now: int = _clock()
	if _batch_first < 0:
		_batch_first = now
	_batch_grind = value
	_batch_max = maxf(_batch_max, value)
	if _perfect_wall < 0 and mortar.economy != null and value + EPSILON >= mortar.economy.perfect_from:
		_perfect_wall = now - _batch_first
		_perfect_active = _batch_active + (now - _grind_since if _grind_since >= 0 else 0)


func _on_turned(circles: float) -> void:
	if _batch_open:
		_batch_circles += circles


func _on_gesture_ended(reason: StringName) -> void:
	if not _batch_open:
		return
	if reason == GrindGesture.REASON_TAP:
		_batch_taps += 1
	else:
		_batch_gestures += 1
	var key: String = str(reason)
	_batch_ends[key] = int(_batch_ends.get(key, 0)) + 1


func _on_handed_off(_mixture: Dictionary[StringName, float]) -> void:
	var grind: float = mortar.vessel.grind
	if not _closing.is_empty():
		_closing["outcome"] = OUTCOME_HANDED
		grind = float(_closing["grind"])
	if not _order_open:
		return
	var now: int = _clock()
	_last_attempt = now
	if _first_attempt < 0:
		_first_attempt = now
	_attempts.append({"t": _sec(now - _order_from), "grind": snappedf(grind, GRIND_STEP), "in_zone": _in_zone(grind),
			"effect": null, "stars": 0})


func _on_mortar_drop_refused(reason: StringName) -> void:
	_count_in_order("mortar_refusals", reason)


func _open_batch(now: int) -> void:
	_batch_open = true
	_batch_start = now
	_batch_first = -1
	_grind_since = -1
	_batch_active = 0
	_perfect_wall = -1
	_perfect_active = -1
	_batch_ids = mortar.ids()
	_batch_hardness = mortar.hardest()
	_batch_grind = 0.0
	_batch_max = 0.0
	_batch_circles = 0.0
	_batch_taps = 0
	_batch_gestures = 0
	_batch_ends = {}


## Ступка опустела: запись партии готова, но отдана ли она клиенту, скажет handed_off в этом же кадре.
func _close_batch(now: int) -> void:
	_batch_open = false
	var economy: EconomyConfig = mortar.economy
	var names: Array = IngredientData.Hardness.keys()
	_closing = {
		"type": TYPE_BATCH,
		"t": _sec(_batch_start),
		"order": str(_order.get("order", "")) if _order_open else "",
		"ingredients": _strings(_batch_ids),
		"hardness": str(names[_batch_hardness]).to_lower() if _batch_hardness < names.size() else "",
		"gestures": _batch_gestures,
		"taps": _batch_taps,
		"ends": _batch_ends.duplicate(),
		"circles": snappedf(_batch_circles, GRIND_STEP),
		"grind": snappedf(_batch_grind, GRIND_STEP),
		"max_grind": snappedf(_batch_max, GRIND_STEP),
		"in_zone": _in_zone(_batch_grind),
		"overshoot": economy != null and _batch_max > economy.perfect_to + EPSILON,
		"dust": _batch_max + EPSILON >= 1.0,
		"perfect_sec": _sec(_perfect_wall) if _perfect_wall >= 0 else null,
		"perfect_active_sec": _sec(_perfect_active) if _perfect_active >= 0 else null,
		"active_sec": _sec(_batch_active),
		"batch_sec": _sec(now - _batch_start),
		"outcome": OUTCOME_DISCARDED if _batch_max > 0.0 else OUTCOME_RETURNED,
	}
	_finish_batch.call_deferred()


func _finish_batch() -> void:
	if _closing.is_empty():
		return
	var record: Dictionary = _closing
	_closing = {}
	if _order_open:
		_order["batches"] = int(_order["batches"]) + 1
		if record["outcome"] == OUTCOME_DISCARDED:
			_order["discarded"] = int(_order["discarded"]) + 1
	_emit(record)


# --- заказ -----------------------------------------------------------------------------------------------------------

func _on_order_started(who: ClientData, order: OrderTemplate) -> void:
	if _order_open:
		_close_order(RESULT_LEFT)
	var catalog: DataCatalog = GameState.catalog
	_order_open = true
	_order_from = _clock()
	_first_drop = -1
	_first_attempt = -1
	_last_attempt = -1
	_attempts = []
	_order = {
		"type": TYPE_ORDER,
		"order": str(order.id),
		"client": str(who.id) if who != null else "",
		"ftue": catalog != null and catalog.ftue_orders.has(order),
		"ftue_step": GameState.ftue_step,
		"wrong": 0,
		"client_refusals": {},
		"mortar_refusals": {},
		"batches": 0,
		"discarded": 0,
	}


func _on_client_arrived() -> void:
	# Часы заказа идут с прихода: пока клиент идёт, заказать ещё нельзя.
	if _order_open and _attempts.is_empty() and _first_drop < 0:
		_order_from = _clock()


func _on_client_drop_refused(reason: StringName) -> void:
	_count_in_order("client_refusals", reason)


func _on_client_refused(verdict: Dictionary) -> void:
	if not _order_open:
		return
	_order["wrong"] = int(_order["wrong"]) + 1
	_mark_last_attempt(false, verdict)


func _on_order_paid(_order_data: OrderTemplate, verdict: Dictionary, pay: int) -> void:
	if not _order_open:
		return
	_mark_last_attempt(true, verdict)
	_order["stars"] = int(verdict.get(OrderJudge.KEY_STARS, 0))
	_order["strength_stars"] = int(verdict.get(OrderJudge.KEY_STRENGTH_STARS, 0))
	_order["purity_stars"] = int(verdict.get(OrderJudge.KEY_PURITY_STARS, 0))
	_order["purity"] = snappedf(float(verdict.get(OrderJudge.KEY_PURITY, 0.0)), GRIND_STEP)
	_order["flawless"] = bool(verdict.get(OrderJudge.KEY_FLAWLESS, false))
	_order["pay"] = pay
	_close_order(RESULT_PAID)


func _on_client_left() -> void:
	if _order_open:
		_close_order(RESULT_LEFT)


func _mark_last_attempt(effect: bool, verdict: Dictionary) -> void:
	if _attempts.is_empty():
		return
	var attempt: Dictionary = _attempts.back()
	attempt["effect"] = effect
	attempt["stars"] = int(verdict.get(OrderJudge.KEY_STARS, 0))


func _close_order(result: String) -> void:
	_order_open = false
	var record: Dictionary = _order
	_order = {}
	var end: int = _last_attempt if result == RESULT_PAID and _last_attempt >= 0 else _clock()
	record["t"] = _sec(_order_from)
	record["result"] = result
	record["order_sec"] = _sec(end - _order_from)
	record["first_drop_sec"] = _sec(_first_drop - _order_from) if _first_drop >= 0 else null
	record["first_attempt_sec"] = _sec(_first_attempt - _order_from) if _first_attempt >= 0 else null
	record["attempts"] = _attempts.duplicate(true)
	if result != RESULT_PAID:
		record["stars"] = 0
		record["pay"] = 0
	record["streak"] = GameState.streak_3star
	record["coins"] = GameState.coins
	_emit(record)
	if print_records:
		_print_summary()


func _count_in_order(field: String, reason: StringName) -> void:
	if not _order_open:
		return
	var counts: Dictionary = _order[field]
	var key: String = str(reason)
	counts[key] = int(counts.get(key, 0)) + 1


# --- пауза и поворот -----------------------------------------------------------------------------------------------

func _on_pause_changed(paused: bool) -> void:
	var now: int = Time.get_ticks_msec()
	if paused and _paused_since < 0:
		_paused_since = now
	elif not paused and _paused_since >= 0:
		_paused_msec += now - _paused_since
		_paused_since = -1
	_emit({"type": TYPE_EVENT, "event": EVENT_PAUSE, "on": paused})


func _on_layout_changed(portrait: bool) -> void:
	_emit({"type": TYPE_EVENT, "event": EVENT_LAYOUT, "portrait": portrait})


# --- запись --------------------------------------------------------------------------------------------------------

func _emit(record: Dictionary) -> void:
	if records.is_empty():
		_store(_header())
	if not record.has("t"):
		record["t"] = _sec(_clock())
	_store(record)


func _store(record: Dictionary) -> void:
	records.append(record)
	var line: String = JSON.stringify(record)
	if print_records:
		print(LOG_PREFIX + line)
	if write_file:
		_append_line(line)
	recorded.emit(record)


func _append_line(line: String) -> void:
	if file_path.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		file_path = _new_file_path()
		var created: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
		if created == null:
			push_warning("PlaytestRecorder: не создать %s (%s)" % [file_path, error_string(FileAccess.get_open_error())])
			write_file = false
			return
		created.close()
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ_WRITE)
	if file == null:
		push_warning("PlaytestRecorder: не дописать %s" % file_path)
		return
	file.seek_end()
	file.store_line(line)
	file.close()


func _new_file_path() -> String:
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path: String = folder.path_join(FILE_PREFIX + stamp + FILE_EXT)
	var copy: int = 1
	while FileAccess.file_exists(path):
		copy += 1
		path = folder.path_join("%s%s_%d%s" % [FILE_PREFIX, stamp, copy, FILE_EXT])
	return path


func _header() -> Dictionary:
	var header: Dictionary = {
		"type": TYPE_SESSION,
		"schema": SCHEMA,
		"t": 0.0,
		"version": str(ProjectSettings.get_setting(VERSION_SETTING, "")),
		"date": Time.get_datetime_string_from_system(false, true),
		"os": OS.get_name(),
		"debug": OS.is_debug_build(),
		"locale": TranslationServer.get_locale(),
		"portrait": LayoutSwitcher.portrait,
		"ftue_step": GameState.ftue_step,
		"rank": GameState.rank,
		"coins": GameState.coins,
		"max_circles_per_sec": mortar.gesture.max_circles_per_sec,
		"max_taps_per_sec": mortar.gesture.max_taps_per_sec,
	}
	var economy: EconomyConfig = mortar.economy
	if economy != null:
		header["perfect_from"] = economy.perfect_from
		header["perfect_to"] = economy.perfect_to
		header["taps_per_circle"] = economy.taps_per_circle
		header["grind_per_circle"] = {"soft": economy.grind_soft, "medium": economy.grind_medium,
				"hard": economy.grind_hard}
	return header


func _print_summary() -> void:
	var s: Dictionary = summary()
	print("PLAYTEST-ИТОГ: оплачено заказов %d, медиана заказа %s с, до «идеально» %s с;" % [s["orders"],
			_shown(s["order_sec"]), _shown(s["perfect_sec"])],
			" отдано в зоне %d из %d, перетёрто партий %d из %d" % [s["in_zone"], s["handed"], s["overshoot"], s["ground"]])


# --- помощники -----------------------------------------------------------------------------------------------------

## Миллисекунды сессии без пауз.
func _clock() -> int:
	var now: int = Time.get_ticks_msec()
	var paused: int = _paused_msec
	if _paused_since >= 0:
		paused += now - _paused_since
	return now - _start_msec - paused


func _sec(msec: int) -> float:
	return snappedf(msec / MSEC_PER_SEC, SEC_STEP)


func _in_zone(grind: float) -> bool:
	var economy: EconomyConfig = mortar.economy
	return (economy != null and grind + EPSILON >= economy.perfect_from
			and grind <= economy.perfect_to + EPSILON)


func _strings(ids: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for id: StringName in ids:
		out.append(str(id))
	return out


func _shown(value: float) -> String:
	return "—" if value == NO_DATA else "%.1f" % value
