## SfxComponent — звук события сущности: случайный вариант из набора, без повтора подряд,
## лёгкий разброс высоты (AudioDirector.pitch_jitter), защита от «пулемёта» при частых вызовах.
## Подключается сигналом в сцене: Draggable.landed → play. У сигналов с аргументами — unbinds в connection
## (например dropped(target) → play с unbinds=1).
## Сигналы: нет.
## Зависимости: AudioDirector (шины SFX/UI, громкость из настроек).
class_name SfxComponent
extends Node

const MSEC_PER_SEC: float = 1000.0

## Варианты одного звука (3 «тука» звучат живее одного).
@export var streams: Array[AudioStream] = []
## Шина UI вместо SFX — для кнопок и интерфейса.
@export var ui_bus: bool = false
@export var volume_db: float = 0.0
## Разброс высоты тона (только для шины SFX).
@export var vary_pitch: bool = true
## Не играть чаще, чем раз в столько секунд.
@export var min_interval_sec: float = 0.05
## Не повторять один и тот же вариант два раза подряд.
@export var avoid_repeat: bool = true
@export var enabled: bool = true

var _last_index: int = -1
var _last_msec: int = -1


func play() -> void:
	if streams.is_empty():
		return
	play_index(_pick_index())


func play_index(index: int) -> void:
	if not enabled or index < 0 or index >= streams.size():
		return
	var now: int = Time.get_ticks_msec()
	if _last_msec >= 0 and float(now - _last_msec) / MSEC_PER_SEC < min_interval_sec:
		return
	_last_msec = now
	_last_index = index
	if ui_bus:
		AudioDirector.play_ui(streams[index], volume_db)
	else:
		AudioDirector.play_sfx(streams[index], vary_pitch, volume_db)


func _pick_index() -> int:
	var count: int = streams.size()
	if count == 1:
		return 0
	if not avoid_repeat or _last_index < 0:
		return randi() % count
	# Сдвиг на 1…count-1 от прошлого варианта — гарантированно другой.
	return (_last_index + 1 + randi() % (count - 1)) % count
