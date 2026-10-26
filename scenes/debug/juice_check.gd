## JuiceCheck — проверочная сцена S2.3 (F6 на этой сцене): мастерская, полка, ступка с откликом (MortarJuice).
## Автопроверки при запуске → Output, итог строкой «JUICE: x/y OK», потом памятка для ручной проверки
## (на глаз и на слух: крошки, порошок, звуки, вибрация на телефоне).
## Четверти круга проверки подают сигналом жеста (GrindGesture.quarter_passed), помол — Mortar.set_grind;
## между событиями — паузы длиннее защиты от частых звуков и вибрации. Проверка идёт пару секунд — экран не трогайте.
## Монеты и настройку вибрации проверки меняют и в конце возвращают. Тексты на экран не выводятся.
## Сигналы: нет.
## Зависимости: GameState (монеты, настройка вибрации), узлы сцены через @export.
extends Node2D

## Монет на время проверок: хватает на любые два ингредиента полки.
const CHECK_COINS: int = 100
## Запас ко времени анимации при ожидании её конца, секунды.
const WAIT_MARGIN_SEC: float = 0.15
const SOFT: StringName = &"ing_sage_bundle"
const HARD: StringName = &"ing_star_crystal"
## Помол для проверок распада, порошка и тона хруста.
const GRIND_LOW: float = 0.3
const GRIND_MID: float = 0.5
const GRIND_OVER: float = 0.95
const EPSILON: float = 0.001
## Допуск сравнения цветов (8 бит на канал).
const COLOR_EPSILON: float = 0.01
## Насколько дальше start_distance сдвигаем палец, чтобы начать жест.
const START_EXTRA_PX: float = 8.0
const MSEC_PER_SEC: float = 1000.0

@export var shelf: Shelf
@export var mortar: Mortar
@export var juice: MortarJuice

var _passed: int = 0
var _total: int = 0
var _crumbs: Array[Vector2] = []
var _dust: Array[Vector2] = []
var _sounds: Dictionary[StringName, int] = {}
var _pulses: int = 0
var _wiggles: int = 0


func _ready() -> void:
	juice.crumbs.fired.connect(func(world: Vector2) -> void: _crumbs.append(world))
	juice.dust.fired.connect(func(world: Vector2) -> void: _dust.append(world))
	juice.haptic.pulsed.connect(func(_ms: int) -> void: _pulses += 1)
	juice.gauge_punch.finished.connect(func() -> void: _wiggles += 1)
	_count_sound(&"accept", mortar.sfx_accept)
	_count_sound(&"crunch", juice.sfx_crunch)
	_count_sound(&"dull", juice.sfx_crunch_dull)
	_count_sound(&"chime", juice.sfx_chime)
	_count_sound(&"poof", juice.sfx_poof)
	_run_checks.call_deferred()


func _run_checks() -> void:
	# Кадр на запуск машины состояний и раскладку.
	await get_tree().process_frame
	var saved_coins: int = GameState.coins
	var saved_shake: Variant = GameState.get_setting(GameState.SETTING_SHAKE)
	GameState.coins = CHECK_COINS
	# Напрямую, без set_setting: проверке не нужна запись сохранения.
	GameState.settings[GameState.SETTING_SHAKE] = true
	print("--- S2.3: отклик ступки ---")
	_check("пустая ступка: порошка и кольца не видно", not juice.powder.visible and not juice.ring.visible)
	await _check_drop()
	await _check_quarter()
	await _check_haptic_setting()
	await _check_decay_and_powder()
	await _check_zones()
	await _check_quiet_outside_grinding()
	await _check_trash_and_return()
	_check_bursts_overlap()
	GameState.settings[GameState.SETTING_SHAKE] = saved_shake
	GameState.coins = saved_coins
	print("JUICE: %d/%d OK" % [_passed, _total])
	_print_manual()


func _check_drop() -> void:
	_reset_counts()
	var item: IngredientItem = _slot(SOFT).item
	item.draggable.drop_on(mortar.drop_target)
	_check("бросок: «тук» сразу", _sounds[&"accept"] == 1)
	_check("бросок: облачко ждёт, пока ингредиент долетит", _dust.is_empty())
	await _wait(item.draggable.fly_sec)
	_check("бросок: облачко в центре чаши после приземления", _dust.size() == 1
			and _dust[0].is_equal_approx(_center()))
	var expected: Color = item.data.crumb_color
	expected.a = juice.drop_puff_alpha
	_check("облачко цвета брошенного ингредиента", _emitter_has_color(juice.dust, expected))
	var hard: IngredientItem = _slot(HARD).item
	hard.draggable.drop_on(mortar.drop_target)
	await _wait(hard.draggable.fly_sec)
	var whole: bool = true
	for loaded: IngredientItem in mortar.items:
		whole = whole and is_zero_approx(loaded.grind())
	_check("Loaded: ингредиенты целые, порошка нет", mortar.items.size() == 2 and whole
			and not juice.powder.visible)


func _check_quarter() -> void:
	_reset_counts()
	var sprite: Node2D = juice.pestle_squash.target
	var rest_scale: Vector2 = sprite.scale
	mortar.gesture.quarter_passed.emit()
	_check("¼ круга: крошки из-под пестика", _crumbs.size() == 1
			and _crumbs[0].is_equal_approx(juice.pestle.global_position))
	var colors: Array[Color] = []
	for item: IngredientItem in mortar.items:
		colors.append(item.data.crumb_color)
	var any_color: bool = false
	for color: Color in colors:
		any_color = any_color or _emitter_has_color(juice.crumbs, color)
	_check("крошки цвета одного из ингредиентов в чаше", any_color)
	_check("¼ круга: хруст, при помоле 0 — обычный тон", _sounds[&"crunch"] == 1
			and is_equal_approx(juice.sfx_crunch.pitch, 1.0))
	_check("¼ круга: вибрация", _pulses == 1)
	# Пружина колеблется: смотрим каждый кадр, был ли пестик шире и ниже покоя (один долгий кадр
	# мог попасть на переход через ноль).
	var squashed: bool = false
	var until_msec: int = Time.get_ticks_msec() + roundi((juice.pestle_squash.recover_sec + WAIT_MARGIN_SEC) * MSEC_PER_SEC)
	while Time.get_ticks_msec() < until_msec:
		await get_tree().process_frame
		squashed = squashed or (sprite.scale.x > rest_scale.x and sprite.scale.y < rest_scale.y)
	_check("¼ круга: пестик сплющился (шире, ниже)", squashed)
	_check("пестик вернулся к своему размеру", sprite.scale.is_equal_approx(rest_scale))


func _check_haptic_setting() -> void:
	_reset_counts()
	GameState.settings[GameState.SETTING_SHAKE] = false
	await _wait(juice.haptic.min_interval_sec)
	mortar.gesture.quarter_passed.emit()
	_check("вибрация выключена в настройках — импульса нет, хруст есть", _pulses == 0 and _sounds[&"crunch"] == 1)
	GameState.settings[GameState.SETTING_SHAKE] = true


func _check_decay_and_powder() -> void:
	mortar.set_grind(GRIND_LOW, true)
	var decayed: bool = true
	for item: IngredientItem in mortar.items:
		decayed = decayed and is_equal_approx(item.grind(), GRIND_LOW)
	_check("помол %.1f: ингредиенты распадаются вместе с ним" % GRIND_LOW, decayed)
	var low_scale: Vector2 = juice.powder.scale
	var low_alpha: float = juice.powder.modulate.a
	_check("порошок появился", juice.powder.visible and low_alpha > 0.0)
	var mix: Color = juice.mix_color()
	var tint: Color = juice.powder.modulate
	_check("порошок цвета смеси", absf(tint.r - mix.r) < COLOR_EPSILON and absf(tint.g - mix.g) < COLOR_EPSILON
			and absf(tint.b - mix.b) < COLOR_EPSILON)
	mortar.set_grind(juice.powder_full_at, true)
	_check("порошок растёт и густеет к помолу %.1f" % juice.powder_full_at, juice.powder.scale.x > low_scale.x
			and juice.powder.modulate.a > low_alpha and is_equal_approx(juice.powder.modulate.a, juice.powder_alpha))
	mortar.set_grind(GRIND_MID, true)
	_reset_counts()
	await _wait(juice.sfx_crunch.min_interval_sec)
	mortar.gesture.quarter_passed.emit()
	_check("хруст выше по мере помола (тон %.3f)" % juice.sfx_crunch.pitch,
			is_equal_approx(juice.sfx_crunch.pitch, 1.0 + juice.crunch_pitch_gain * GRIND_MID))


func _check_zones() -> void:
	var economy: EconomyConfig = mortar.economy
	mortar.set_grind(0.0, true)
	await _start_gesture()
	_check("палец повёл — Grinding", mortar.state_machine.is_in(Mortar.STATE_GRINDING))
	_reset_counts()
	mortar.set_grind((economy.perfect_from + economy.perfect_to) * 0.5)
	_check("в зону «идеально»: звон и кольцо из чаши", _sounds[&"chime"] == 1 and juice.ring.visible)
	_check("в зоне: зона шкалы пульсирует", is_equal_approx(_gauge_param(&"zone_pulse"), 1.0))
	await _wait(juice.ring_sec)
	_check("кольцо погасло и спряталось", not juice.ring.visible)
	_reset_counts()
	mortar.set_grind(GRIND_OVER)
	_check("перетёр: облако пыли над чашей и «пфф»", _dust.size() == 1 and _dust[0].is_equal_approx(_center())
			and _sounds[&"poof"] == 1)
	_check("вышли из зоны — пульс выключен", is_zero_approx(_gauge_param(&"zone_pulse")))
	await _wait(juice.gauge_punch.wiggle_sec)
	_check("перетёр: шкала тряхнулась", _wiggles == 1)
	mortar.set_grind(1.0)
	_reset_counts()
	await _wait(juice.sfx_crunch_dull.min_interval_sec)
	mortar.gesture.quarter_passed.emit()
	_check("помол 1: вместо крошек пыль у пестика, хруст глухой", _crumbs.is_empty() and _dust.size() == 1
			and _dust[0].is_equal_approx(juice.pestle.global_position)
			and _sounds[&"dull"] == 1 and _sounds[&"crunch"] == 0)
	mortar.grind_area.pointer_up.emit(_center(), true)
	await _wait(mortar.pestle.rest_sec)


func _check_quiet_outside_grinding() -> void:
	var economy: EconomyConfig = mortar.economy
	_check("отпустили — Ground", mortar.state_machine.is_in(Mortar.STATE_GROUND))
	_reset_counts()
	mortar.set_grind((economy.perfect_from + economy.perfect_to) * 0.5, true)
	mortar.set_grind(GRIND_OVER, true)
	_check("помол меняют не пальцем (сброс, проверки) — ни звона, ни кольца, ни пыли", _sounds[&"chime"] == 0
			and _sounds[&"poof"] == 0 and _dust.is_empty() and not juice.ring.visible)


func _check_trash_and_return() -> void:
	mortar.trash.hit_area.tapped.emit(mortar.trash.global_position)
	_check("корзина: порошок исчез", not juice.powder.visible)
	await _wait(mortar.discard_sec)
	var item: IngredientItem = _slot(SOFT).item
	item.draggable.drop_on(mortar.drop_target)
	await _wait(item.draggable.fly_sec)
	item.set_grind(GRIND_LOW)
	item.hit_area.tapped.emit(item.global_position)
	# Ступка отдаёт предмет кадром позже (release.call_deferred).
	await get_tree().process_frame
	_check("ингредиент вернулся на полку целым", not mortar.items.has(item) and is_instance_valid(item)
			and is_zero_approx(item.grind()))
	await _wait(item.draggable.fly_sec)


func _check_bursts_overlap() -> void:
	juice.crumbs.burst(_center())
	juice.crumbs.burst(_center())
	_check("два всплеска подряд — оба видны (разные излучатели)", _emitting(juice.crumbs) >= 2)


func _start_gesture() -> void:
	var center: Vector2 = _center()
	var start: Vector2 = center + Vector2(mortar.gesture.start_distance, 0.0)
	mortar.grind_area.pointer_down.emit(start)
	await get_tree().process_frame
	mortar.grind_area.pointer_moved.emit(start - Vector2(mortar.gesture.start_distance + START_EXTRA_PX, 0.0))
	await get_tree().process_frame


func _count_sound(key: StringName, sfx: SfxComponent) -> void:
	_sounds[key] = 0
	sfx.played.connect(func(_index: int) -> void: _sounds[key] += 1)


func _reset_counts() -> void:
	_crumbs.clear()
	_dust.clear()
	_pulses = 0
	_wiggles = 0
	for key: StringName in _sounds:
		_sounds[key] = 0


func _emitter_has_color(burst: ParticleBurst, color: Color) -> bool:
	for emitter: CPUParticles2D in burst.emitters:
		if emitter.emitting and emitter.color.is_equal_approx(color):
			return true
	return false


func _emitting(burst: ParticleBurst) -> int:
	var count: int = 0
	for emitter: CPUParticles2D in burst.emitters:
		if emitter.emitting:
			count += 1
	return count


func _gauge_param(param: StringName) -> float:
	var shader: ShaderMaterial = mortar.gauge.material as ShaderMaterial
	return float(shader.get_shader_parameter(param)) if shader != null else -1.0


func _center() -> Vector2:
	return mortar.gesture.center.global_position


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec + WAIT_MARGIN_SEC).timeout


func _slot(id: StringName) -> ShelfSlot:
	return shelf.slot_for(shelf.catalog.ingredient(id))


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		print("  FAIL ", title)
		push_error("JuiceCheck: не прошло — %s" % title)


func _print_manual() -> void:
	print("--- Ручная проверка (глазами и на слух) ---")
	print("1. Бросьте ингредиент в ступку: «тук» сразу, облачко его цвета — когда он лёг в чашу.")
	print("2. Мелите кругами: каждую четверть круга из-под пестика летят крошки, пестик чуть сплющивается, хрустит.")
	print("   Хруст не повторяется подряд и к концу помола становится выше. Не слишком ли часто и громко?")
	print("3. Ингредиенты истираются постепенно: сначала края, к зелёной зоне от них остаётся около половины.")
	print("   Под ними растёт мягкое пятно порошка цвета смеси.")
	print("4. Вход в зелёную зону: звон, золотое кольцо из чаши, зона шкалы пульсирует.")
	print("5. Перетёрли: облако пыли, «пфф», шкала трясётся. Дальше вместо крошек — пыль и глухой хруст.")
	print("6. На телефоне (Android): лёгкая вибрация на каждую четверть круга.")
	print("7. Крошки хорошо видны над чашей? Если теряются за передним краем — скажите, поднимем выше.")
