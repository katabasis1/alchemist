## CameraShake — тряска камеры по модели «травмы»: удары копят травму 0…1, она плавно гаснет,
## смещение растёт как травма в степени trauma_power (лёгкие удары почти незаметны, сильные — ощутимы).
## Слушает EventBus.camera_shake_requested, так что трясти может кто угодно, не зная о камере.
## Настройка «тряска» (GameState.SETTING_SHAKE) выключает эффект целиком (STATIONS.md §2, Яндекс: комфорт).
## Двигает только camera.offset — позицией камеры владеет раскладка (LayoutSwitcher).
## Сигналы: нет.
## Зависимости: Camera2D (@export camera), EventBus (camera_shake_requested), GameState (настройка).
class_name CameraShake
extends Node

@export var camera: Camera2D
## Шум для плавного дрожания. Без него — случайный рывок каждый кадр (грубее, но работает).
@export var noise: FastNoiseLite
## Наибольшее смещение при травме 1, пиксели мира.
@export var max_offset: Vector2 = Vector2(18.0, 12.0)
## Скорость угасания травмы, единиц в секунду.
@export var trauma_decay: float = 1.6
## Показатель кривой: смещение = max_offset · травма^power.
@export var trauma_power: float = 2.0
## Скорость «бега» по шуму: выше — чаще дрожь.
@export var noise_speed: float = 60.0
## Смещение по оси Y берётся из шума с этим сдвигом, чтобы оси дрожали независимо.
@export var noise_axis_gap: float = 100.0
@export var enabled: bool = true

var trauma: float = 0.0

var _base_offset: Vector2 = Vector2.ZERO
var _time: float = 0.0


func _ready() -> void:
	set_process(false)
	if camera == null:
		push_warning("CameraShake %s: не задана camera" % get_path())
		return
	_base_offset = camera.offset
	EventBus.camera_shake_requested.connect(add_trauma)


## Добавить травму (0…1). Слабый удар — 0.2, приземление тяжёлого — 0.4, провал/взрыв — 0.7.
func add_trauma(amount: float) -> void:
	if not enabled or camera == null or not _shake_allowed():
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)
	set_process(trauma > 0.0)


## Остановить тряску сразу (смена экрана, пауза).
func stop() -> void:
	trauma = 0.0
	set_process(false)
	if camera != null:
		camera.offset = _base_offset


func _process(delta: float) -> void:
	trauma = maxf(trauma - trauma_decay * delta, 0.0)
	if trauma <= 0.0:
		stop()
		return
	_time += delta * noise_speed
	var amount: float = pow(trauma, trauma_power)
	camera.offset = _base_offset + Vector2(max_offset.x * amount * _sample(0.0), max_offset.y * amount * _sample(noise_axis_gap))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		stop()


## Значение -1…1 для оси: из шума или случайное.
func _sample(axis_gap: float) -> float:
	if noise == null:
		return randf_range(-1.0, 1.0)
	return noise.get_noise_2d(axis_gap, _time)


func _shake_allowed() -> bool:
	return bool(GameState.get_setting(GameState.SETTING_SHAKE))
