## PlatformMock — бэкенд Platform для редактора и ПК: сохранение в user://, реклама-заглушка по таймеру.
## Запись атомарная: сначала во временный файл, потом переименование. Повреждённый файл
## откладывается рядом с суффиксом .bad, чтобы его можно было разобрать.
## Сигналы: нет. Зависимости: нет (вызывается только из Platform).
extends Node

const TMP_SUFFIX: String = ".tmp"
const BAD_SUFFIX: String = ".bad"

@export var save_path: String = "user://save.json"
## Язык вместо языка ОС, например "en" для проверки перевода. Пусто — язык ОС.
@export var language_override: String = ""
## Длительность рекламы-заглушки, секунды.
@export var ad_seconds: float = 1.0
## Чем заканчивается реклама за награду: true — досмотрели.
@export var rewarded_result: bool = true
## false — полноэкранная реклама «не показалась» (как при ограничении частоты на платформе).
@export var fullscreen_available: bool = true
## Отступы JSON в файле сохранения (удобно читать глазами). Пусто — одна строка.
@export var json_indent: String = "\t"


func initialize() -> void:
	await get_tree().process_frame
	print_verbose("PlatformMock: initialize")


func loading_ready() -> void:
	print_verbose("PlatformMock: loading_ready")


func gameplay_start() -> void:
	print_verbose("PlatformMock: gameplay_start")


func gameplay_stop() -> void:
	print_verbose("PlatformMock: gameplay_stop")


func get_language() -> String:
	if not language_override.is_empty():
		return language_override
	return OS.get_locale_language()


func get_server_time_unix() -> int:
	return int(Time.get_unix_time_from_system())


func save_data(data: Dictionary) -> bool:
	var tmp_path: String = save_path + TMP_SUFFIX
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("PlatformMock: не открыть %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, json_indent))
	file.close()
	var err: Error = DirAccess.rename_absolute(tmp_path, save_path)
	if err != OK:
		push_warning("PlatformMock: переименование не удалось (%s), пишем напрямую" % error_string(err))
		file = FileAccess.open(save_path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(JSON.stringify(data, json_indent))
		file.close()
	return true


func load_data() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var text: String = FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("PlatformMock: сохранение не читается, отложено в %s" % (save_path + BAD_SUFFIX))
	DirAccess.rename_absolute(save_path, save_path + BAD_SUFFIX)
	return {}


func show_fullscreen_ad() -> bool:
	if not fullscreen_available:
		return false
	await get_tree().create_timer(ad_seconds).timeout
	return true


func show_rewarded_ad(placement: StringName) -> bool:
	print_verbose("PlatformMock: rewarded %s" % placement)
	await get_tree().create_timer(ad_seconds).timeout
	return rewarded_result
