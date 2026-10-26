## ComponentsDemo — проверочная сцена компонентов S1.5 (F6 на этой сцене), пока у агента нет движка.
## Автопроверки при запуске → Output, итог строкой «COMPONENTS: x/y OK». Ручная часть — памятка там же.
## Здесь же образец «станции»: ступка = DropTarget + StateMachine (Пусто → Занято → по таймеру Пусто),
## отказ через вето в drop_attempted, отклик принятия и отказа минимум двумя каналами (AGENTS.md §3, п. 9).
## Тексты на экран не выводятся: до S1.7 нет strings.csv, поэтому подсказки показывают сам ключ.
## Сигналы: нет.
## Зависимости: EventBus (camera_shake_requested), узлы сцены через @export.
extends Node2D

const STATE_EMPTY: StringName = &"Empty"
const STATE_LOADED: StringName = &"Loaded"
const CHECK_IDLE: StringName = &"Idle"
const CHECK_BUSY: StringName = &"Busy"
const CHECK_DONE: StringName = &"Done"
const CHECK_TIMED: StringName = &"Timed"
## Сила тряски камеры (0…1) для разных событий.
const SHAKE_ACCEPT: float = 0.25
const SHAKE_COIN: float = 0.5
## Сколько раз подряд тянуть вариант звука в проверке «без повторов».
const SFX_PICKS: int = 40
## Запас ко времени анимации при ожидании её конца, секунды.
const WAIT_MARGIN_SEC: float = 0.15
## Сжатие для проверки SquashStretch.hold().
const CHECK_SQUASH: float = 0.2
## Окна для проверки порогов раскладки: телефон, ПК, почти квадрат.
const WINDOW_PHONE: Vector2i = Vector2i(1080, 1920)
const WINDOW_PC: Vector2i = Vector2i(1920, 1080)
const WINDOW_SQUARE: Vector2i = Vector2i(1000, 1000)
## Смещение от центра круглой HitArea к углу её прямоугольника (вне круга), доля размера.
const CORNER_SHARE: float = 0.03

@export_group("Ступка")
@export var mortar_target: DropTarget
@export var mortar_machine: StateMachine
@export var mortar_punch: JuicePunch
@export var mortar_flash_ok: Flash
@export var mortar_flash_no: Flash
@export var mortar_sfx_ok: SfxComponent
@export var mortar_sfx_no: SfxComponent
@export_group("Клиент")
@export var client_target: DropTarget
@export var client_punch: JuicePunch
@export var client_sfx_ok: SfxComponent
@export var client_sfx_no: SfxComponent
@export_group("Монета")
@export var coin_hit: HitArea
@export var coin_punch: JuicePunch
@export var coin_flash: Flash
@export var coin_sfx: SfxComponent
@export var screen_flash: Flash
@export_group("Раскладка")
@export var layout: LayoutSwitcher
@export_group("Автопроверки")
@export var check_point: Marker2D
@export var check_ingredient: DemoItem
@export var check_potion: DemoItem
@export var check_target_plain: DropTarget
@export var check_target_potion: DropTarget
@export var check_target_best: DropTarget
@export var check_machine: StateMachine
@export var check_done_state: State
@export var check_timed_state: State
@export var check_punch: JuicePunch
@export var check_squash: SquashStretch
@export var check_sfx: SfxComponent

var _passed: int = 0
var _total: int = 0
## Предмет, который сейчас лежит в ступке, и откуда его взяли.
var _loaded: Draggable
var _loaded_from: Vector2 = Vector2.ZERO
var _pending_from: Vector2 = Vector2.ZERO
var _last_reason: StringName = &""
var _veto_on: bool = false
var _transitions: PackedStringArray = []


func _ready() -> void:
	mortar_target.drop_attempted.connect(_on_mortar_drop_attempted)
	mortar_target.received.connect(_on_mortar_received)
	mortar_target.rejected.connect(_on_mortar_rejected)
	mortar_machine.state_changed.connect(_on_mortar_state_changed)
	client_target.received.connect(_on_client_received)
	client_target.rejected.connect(_on_client_rejected)
	coin_hit.tapped.connect(_on_coin_tapped)
	layout.layout_applied.connect(_on_layout_applied)
	_print_manual()
	await _run_checks()


# ---- ступка: образец станции ------------------------------------------------

func _on_mortar_drop_attempted(draggable: Draggable) -> void:
	if not mortar_machine.is_in(STATE_EMPTY):
		mortar_target.reject(DropTarget.REASON_BUSY)
		return
	# Пока предмет не встал в ступку, его home_position — ещё место на полке.
	_pending_from = draggable.home_position


func _on_mortar_received(draggable: Draggable) -> void:
	_loaded = draggable
	_loaded_from = _pending_from
	draggable.enabled = false
	mortar_machine.transition_to(STATE_LOADED)
	mortar_punch.punch()
	mortar_flash_ok.flash()
	mortar_sfx_ok.play()
	EventBus.camera_shake_requested.emit(SHAKE_ACCEPT)


func _on_mortar_rejected(draggable: Draggable, reason: StringName) -> void:
	mortar_punch.wiggle()
	mortar_flash_no.flash()
	mortar_sfx_no.play()
	_flash_item(draggable)
	print("  ступка отказала: ", reason)


func _on_mortar_state_changed(_from: StringName, to: StringName) -> void:
	if to != STATE_EMPTY or _loaded == null:
		return
	_loaded.enabled = true
	_loaded.send_to(_loaded_from)
	_loaded = null


# ---- клиент: принимает только зелья (колба уходит обратно — режим RETURN) ------

func _on_client_received(_draggable: Draggable) -> void:
	client_punch.punch()
	client_sfx_ok.play()
	coin_punch.punch()
	EventBus.camera_shake_requested.emit(SHAKE_ACCEPT)


func _on_client_rejected(draggable: Draggable, reason: StringName) -> void:
	client_punch.wiggle()
	client_sfx_no.play()
	_flash_item(draggable)
	print("  клиент отказал: ", reason)


# ---- монета: тап → пульс, вспышка, вспышка экрана, тряска, звук ---------------

func _on_coin_tapped(_world: Vector2) -> void:
	coin_punch.punch()
	coin_flash.flash()
	screen_flash.flash()
	coin_sfx.play()
	EventBus.camera_shake_requested.emit(SHAKE_COIN)


# ---- раскладка ---------------------------------------------------------------

func _on_layout_applied(portrait: bool) -> void:
	# Раскладка сама переставила предметы на полку; ступку просто освобождаем.
	if _loaded != null:
		_loaded.enabled = true
		_loaded = null
	if not mortar_machine.is_in(STATE_EMPTY):
		mortar_machine.transition_to(STATE_EMPTY, true)
	print("  раскладка: ", "портрет" if portrait else "ландшафт")


func _flash_item(draggable: Draggable) -> void:
	var item: DemoItem = draggable.body as DemoItem
	if item != null:
		item.reject_flash.flash()


# ---- автопроверки ------------------------------------------------------------

func _run_checks() -> void:
	var ing: Draggable = check_ingredient.draggable
	var potion: Draggable = check_potion.draggable
	var at: Vector2 = check_point.global_position

	# DropTarget: выбор цели под точкой — сначала принимающие этот вид, затем приоритет.
	_check("find_at: ингредиент → принимающая цель с большим приоритетом",
			DropTarget.find_at(get_tree(), at, ing) == check_target_best)
	_check("find_at: зелье → единственная цель для зелий",
			DropTarget.find_at(get_tree(), at, potion) == check_target_potion)
	check_target_potion.rejected.connect(_on_check_rejected)
	_check("try_receive: чужой вид отклонён", not check_target_potion.try_receive(ing) and _last_reason == DropTarget.REASON_KIND)
	check_target_plain.rejected.connect(_on_check_rejected)
	check_target_plain.drop_attempted.connect(_on_check_drop_attempted)
	_veto_on = true
	_check("try_receive: вето станции (busy)", not check_target_plain.try_receive(ing) and _last_reason == DropTarget.REASON_BUSY)
	_veto_on = false
	_check("try_receive: без вета принято", check_target_plain.try_receive(ing))

	# StateMachine: стартовое состояние, запрет перехода, очередь из обработчика, таймер.
	check_machine.state_changed.connect(_on_check_state_changed)
	check_done_state.entered.connect(_on_check_done_entered)
	check_machine.start()
	_check("StateMachine: старт в первом состоянии", check_machine.is_in(CHECK_IDLE))
	_check("StateMachine: переход не из next_states запрещён", not check_machine.transition_to(CHECK_DONE) and check_machine.is_in(CHECK_IDLE))
	_check("StateMachine: разрешённый переход", check_machine.transition_to(CHECK_BUSY) and check_machine.is_in(CHECK_BUSY))
	_transitions.clear()
	check_machine.transition_to(CHECK_DONE)
	_check("StateMachine: переход из обработчика entered встаёт в очередь",
			check_machine.is_in(CHECK_IDLE) and ",".join(_transitions) == "Busy>Done,Done>Idle")
	check_done_state.entered.disconnect(_on_check_done_entered)
	check_machine.transition_to(CHECK_TIMED, true)
	await get_tree().create_timer(check_timed_state.timeout_sec + WAIT_MARGIN_SEC).timeout
	_check("StateMachine: выход по таймеру (timeout_to)", check_machine.is_in(CHECK_IDLE))

	# LayoutSwitcher: пороги с гистерезисом.
	_check("Layout: окно телефона → портрет", layout.wants_portrait(WINDOW_PHONE, false))
	_check("Layout: окно ПК → ландшафт", not layout.wants_portrait(WINDOW_PC, true))
	_check("Layout: квадрат не меняет портрет", layout.wants_portrait(WINDOW_SQUARE, true))
	_check("Layout: квадрат не меняет ландшафт", not layout.wants_portrait(WINDOW_SQUARE, false))

	# HitArea: круглая зона не ловит угол своего прямоугольника.
	var hit_xf: Transform2D = coin_hit.get_global_transform()
	_check("HitArea: центр круга внутри", coin_hit.contains_world_point(hit_xf * (coin_hit.size * 0.5)))
	_check("HitArea: угол прямоугольника вне круга", not coin_hit.contains_world_point(hit_xf * (coin_hit.size * CORNER_SHARE)))

	# SfxComponent: один и тот же вариант не звучит дважды подряд (звук не играет — компонент выключен).
	var repeats: int = 0
	for _i: int in SFX_PICKS:
		var index: int = check_sfx._pick_index()
		if index == check_sfx._last_index:
			repeats += 1
		check_sfx._last_index = index
	_check("SfxComponent: без повторов подряд", repeats == 0)

	# JuicePunch и SquashStretch: после анимации цель в исходном виде, сжатие сохраняет «объём».
	var punch_target: Node2D = check_punch.target as Node2D
	var base_scale: Vector2 = punch_target.scale
	var base_rotation: float = punch_target.rotation
	check_punch.punch()
	await check_punch.finished
	check_punch.wiggle()
	await check_punch.finished
	_check("JuicePunch: масштаб и поворот вернулись",
			punch_target.scale.is_equal_approx(base_scale) and is_equal_approx(punch_target.rotation, base_rotation))
	var squash_target: Node2D = check_squash.target
	var squash_base: Vector2 = squash_target.scale
	check_squash.hold(CHECK_SQUASH)
	var held: Vector2 = squash_target.scale
	_check("SquashStretch: сжатие шире и ниже, площадь та же",
			held.x > squash_base.x and held.y < squash_base.y and is_equal_approx(held.x * held.y, squash_base.x * squash_base.y))
	check_squash.release()
	await get_tree().create_timer(check_squash.recover_sec + WAIT_MARGIN_SEC).timeout
	_check("SquashStretch: после release() исходный масштаб", squash_target.scale.is_equal_approx(squash_base))

	print("COMPONENTS: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])


func _on_check_rejected(_draggable: Draggable, reason: StringName) -> void:
	_last_reason = reason


func _on_check_drop_attempted(_draggable: Draggable) -> void:
	if _veto_on:
		check_target_plain.reject(DropTarget.REASON_BUSY)


func _on_check_state_changed(from: StringName, to: StringName) -> void:
	_transitions.append("%s>%s" % [from, to])


func _on_check_done_entered(_from: StringName) -> void:
	check_machine.transition_to(CHECK_IDLE)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  [OK] ", title)
	else:
		push_error("COMPONENTS FAIL: " + title)


func _print_manual() -> void:
	print("COMPONENTS DEMO — проверь руками:")
	print("  1. Перетащи ингредиент в ступку: подсветка ступки, щелчок, пульс, тряска; через 3 с он вернётся на полку.")
	print("  2. Пока ступка занята, брось туда второй — отказ: покачивание, красная вспышка, предмет вернулся.")
	print("  3. Тап по ингредиенту, затем тап по ступке — то же без перетаскивания. Тап мимо снимает выбор.")
	print("  4. Ингредиент клиенту — клиент не подсвечивается и отказывает. Колбу клиенту — принял, колба вернулась.")
	print("  5. Тап по монете: пульс, вспышка, вспышка экрана, тряска. Наведение на предметы — подсказка через 0,4 с.")
	print("  6. Сузь окно до портрета и обратно: сцена перестраивается, раскладка не дребезжит у квадрата.")
