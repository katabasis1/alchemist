## Haptic — короткая вибрация телефона (STATIONS §2: каждая ¼ круга помола).
## Input.vibrate_handheld: в вебе это navigator.vibrate — работает в браузерах Android, iOS и компьютер молча пропускают.
## Выключается настройкой «тряска и вибрация» (GameState.SETTING_SHAKE). Не чаще min_interval_sec,
## чтобы при быстром помоле импульсы не слились в сплошной гул.
## Сигналы: pulsed(duration_ms) — импульс отправлен (для проверочных сцен).
## Зависимости: GameState (настройка).
class_name Haptic
extends Node

signal pulsed(duration_ms: int)

const MSEC_PER_SEC: float = 1000.0

## Длина импульса при strength = 1, миллисекунды.
@export var duration_ms: int = 18
## Сила 0…1 там, где браузер или телефон её поддерживает.
@export_range(0.0, 1.0) var amplitude: float = 0.5
@export var min_interval_sec: float = 0.06
@export var enabled: bool = true

var _last_msec: int = -1


## Импульс. strength — доля длины и силы (лёгкий тычок — 0.5).
func pulse(strength: float = 1.0) -> void:
	if not enabled or not _allowed():
		return
	var now: int = Time.get_ticks_msec()
	if _last_msec >= 0 and float(now - _last_msec) / MSEC_PER_SEC < min_interval_sec:
		return
	_last_msec = now
	var length_ms: int = maxi(1, roundi(duration_ms * strength))
	Input.vibrate_handheld(length_ms, clampf(amplitude * strength, 0.0, 1.0))
	pulsed.emit(length_ms)


func _allowed() -> bool:
	return bool(GameState.get_setting(GameState.SETTING_SHAKE))
