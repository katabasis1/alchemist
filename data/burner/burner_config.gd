## BurnerConfig — вид и отклик станции Горелки (S4.3, STATIONS §1.3): откуда растёт пламя и идёт пар, как быстро
## огонь разгорается и гаснет, когда колба закипает, сколько пара и дыма, тряска и свист на пределе.
## Правила нагрева (скорость нагрева и остывания, комнатная и предельная T, испарение, сгорание) — в EconomyConfig,
## точки свойств — в PropertyData; здесь только то, что игрок видит и слышит.
## Один .tres на пару «горелка + форма колбы» (data/burner/burner_round.tres — prop_burner и круглая колба).
## Сигналы: нет. Зависимости: нет.
class_name BurnerConfig
extends Resource

@export_group("Геометрия")
## Середина отверстия горла колбы, px холста текстуры колбы: отсюда идут пар и дым.
@export var mouth_px: Vector2 = Vector2(191.0, 16.0)
## Верх фитиля, px холста prop_burner: здесь основание пламени.
@export var wick_px: Vector2 = Vector2(193.0, 202.0)

@export_group("Огонь")
## За сколько секунд пламя разгорается, когда игрок зажал горелку, и за сколько гаснет, когда отпустил.
@export_range(0.01, 2.0) var flame_grow_sec: float = 0.25
@export_range(0.01, 2.0) var flame_fade_sec: float = 0.4
## Сила пламени (0…1) в начале нагрева. К EconomyConfig.max_temp она дорастает до 1: языки выше и шире.
## На пределе огонь больше не растёт (STATIONS §1.3).
@export_range(0.0, 1.0) var flame_start: float = 0.55
## Пока огонь горит, раз в столько секунд — треск (SfxComponent сам перебирает варианты и тон).
@export var crackle_sec: float = 0.55

@export_group("Кипение")
## С какой T в колбе появляются пузыри и при какой кипение в полную силу (кипение 0…1 в шейдере жидкости).
@export var boil_from_temp: float = 30.0
@export var boil_full_temp: float = 95.0
## Пауза между «буль» на полном кипении, с; на слабом — длиннее, в такт кипению.
@export var boil_glug_sec: float = 0.45
## Волна поверхности на каждый «буль» кипения, px холста.
@export var boil_bump_px: float = 2.0

@export_group("Пар")
## Сколько клубов пара в секунду, пока хоть одно свойство уходит паром. Клубы по очереди красятся в цвета
## уходящих свойств.
@export var steam_per_sec: float = 5.0
## Раз в столько секунд с паром улетает иконка уходящего свойства.
@export var steam_icon_sec: float = 1.4

@export_group("Дым")
## Сколько клубов бурого дыма в секунду, пока горит Жизнь.
@export var smoke_per_sec: float = 4.0
## Колба мелко дрожит, пока горит Жизнь: размах, px станции.
@export var smoke_jitter_px: float = 1.5
## Частота дрожи колбы, Гц.
@export var smoke_jitter_hz: float = 12.0
## Лёгкая тряска камеры, пока горит Жизнь: сила для CameraShake (0…1) и пауза между толчками, с.
@export_range(0.0, 1.0) var smoke_camera_shake: float = 0.12
@export var smoke_shake_sec: float = 0.9

@export_group("Термометр")
## Цвет опасной зоны (свойство там не уходит паром, а сгорает): красно-бурый, как на ref_burner_overheat_smoke.
## Остальные зоны — цветом свойства, которое в них начинает уходить.
@export var danger_color: Color = Color(0.62, 0.22, 0.13)

@export_group("Предел")
## На EconomyConfig.max_temp термометр трясётся с такой силой (1 — как у шкалы помола при «перетёр»),
## раз в whistle_sec — свист и белое облачко из колпачка термометра.
@export_range(0.0, 2.0) var max_shake: float = 0.6
@export var whistle_sec: float = 1.2

@export_group("Отклик")
## Волна при приёме смеси, px холста.
@export var receive_bump_px: float = 9.0
