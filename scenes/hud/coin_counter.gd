## CoinCounter — счётчик монет HUD (GDD §10, STATIONS §3 «Монеты»): число прокручивается к новому значению;
## монеты, которые ещё летят, в число не входят и добавляются по мере прилёта; «монет не хватает» (STATIONS §1.1) —
## счётчик вздрагивает, число мигает красным.
## Число = GameState.coins − монеты в полёте. hold(amount) — сколько из уже зачисленных монет ещё в пути (вызывать
## после зачисления: удержать можно только то, что ещё не показано, поэтому число никогда не «отъезжает» назад);
## release(amount) — монетка долетела: число подрастает, иконка пульсирует, звенит монета.
## Сигналы: rolled(shown) — прокрутка дошла до цели.
## Методы: hold(amount), release(amount), deny(), coin_point() — куда летят монеты (координаты слоя HUD), shown,
##   lands / denies — счётчики для проверочной сцены.
## Зависимости: GameState (coins, state_reset), EventBus.coins_changed, JuicePunch (цель — иконка), SfxComponent.
class_name CoinCounter
extends Control

signal rolled(shown: int)

@export_group("Прокрутка")
## Сколько секунд прокрутки на одну монету разницы; итог зажат между min и max.
@export var roll_sec_per_coin: float = 0.02
@export var roll_sec_min: float = 0.15
@export var roll_sec_max: float = 0.8
@export_group("Монета долетела")
@export var land_punch: float = 0.6
@export_group("Монет не хватает")
@export var deny_shake_px: float = 14.0
@export var deny_shake_sec: float = 0.42
## Сколько полных качаний вбок за deny_shake_sec.
@export var deny_shakes: float = 4.0
@export var deny_color: Color = Color(1.0, 0.36, 0.3, 1.0)
@export var deny_flash_sec: float = 0.55
@export var deny_wiggle: float = 1.0
@export_group("Узлы")
## Слой, который трясётся при отказе: его position принадлежит счётчику.
@export var shaker: Control
## Иконка монеты — сюда летят монеты; масштаб и поворот у неё — у JuicePunch.
@export var icon: Control
## Число; self_modulate у него — у счётчика (мигание красным).
@export var amount_label: Label
@export var punch: JuicePunch
@export var sfx_land: SfxComponent

## Показанное сейчас число (во время прокрутки — промежуточное).
var shown: int = 0
var lands: int = 0
var denies: int = 0
var _target: int = 0
var _held: int = 0
var _roll_value: float = 0.0
var _roll: Tween
var _shake: Tween
var _flash: Tween
var _shaker_base: Vector2 = Vector2.ZERO
var _label_base: Color = Color.WHITE


func _ready() -> void:
	_shaker_base = shaker.position
	_label_base = amount_label.self_modulate
	EventBus.coins_changed.connect(_on_coins_changed)
	GameState.state_reset.connect(reset)
	reset()


## Показать монеты игрока сразу, без прокрутки и без монет в полёте (новая игра, загрузка).
func reset() -> void:
	_target = GameState.coins
	_held = 0
	_kill(_roll)
	_set_roll_value(float(_target))


## Сколько монет в пути: они уже зачислены, но число до прилёта их не показывает. Возвращает, сколько удержано.
func hold(amount: int) -> int:
	var can_hold: int = maxi(_target - _held - shown, 0)
	var held: int = clampi(amount, 0, can_hold)
	_held += held
	_roll_to(_visible_target())
	return held


## Монетка долетела: её часть добавляется к числу.
func release(amount: int) -> void:
	_held = maxi(_held - maxi(amount, 0), 0)
	lands += 1
	punch.punch(land_punch)
	sfx_land.play()
	_roll_to(_visible_target())


## Монет не хватает: вздрогнуть вбок, мигнуть красным, качнуть иконкой.
func deny() -> void:
	denies += 1
	_kill(_shake)
	_shake = create_tween()
	_shake.tween_method(_apply_shake, 0.0, 1.0, deny_shake_sec)
	_kill(_flash)
	amount_label.self_modulate = deny_color
	_flash = create_tween()
	_flash.tween_property(amount_label, ^"self_modulate", _label_base, deny_flash_sec)
	punch.wiggle(deny_wiggle)


## Центр иконки монеты в координатах слоя HUD — туда летят монеты.
func coin_point() -> Vector2:
	return icon.get_global_rect().get_center()


## Монеты, которые число покажет, когда прокрутка закончится.
func target_shown() -> int:
	return _visible_target()


func is_rolling() -> bool:
	return _roll != null and _roll.is_valid() and _roll.is_running()


func _visible_target() -> int:
	return maxi(_target - _held, 0)


func _on_coins_changed(total: int, _delta: int) -> void:
	_target = total
	_held = mini(_held, maxi(_target - shown, 0))
	_roll_to(_visible_target())


func _roll_to(value: int) -> void:
	if value == shown and not is_rolling():
		return
	_kill(_roll)
	var from: float = _roll_value
	var sec: float = clampf(absf(float(value) - from) * roll_sec_per_coin, roll_sec_min, roll_sec_max)
	_roll = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll.tween_method(_set_roll_value, from, float(value), sec)
	_roll.tween_callback(_on_rolled)


func _set_roll_value(value: float) -> void:
	_roll_value = value
	var whole: int = roundi(value)
	if whole == shown and amount_label.text != "":
		return
	shown = whole
	amount_label.text = str(whole)


func _on_rolled() -> void:
	rolled.emit(shown)


func _apply_shake(t: float) -> void:
	var k: float = sin(t * TAU * deny_shakes) * (1.0 - t)
	shaker.position = _shaker_base + Vector2(deny_shake_px * k, 0.0)


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
