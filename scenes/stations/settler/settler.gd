## Settler — станция Отстойника (S4.2, GDD §3.3, STATIONS §1.2): колба отстаивает смесь в слои по плотности, игрок
## зажимает колбу — она поднимается, наклоняется по уровню и льёт верхние слои струёй в Приёмник; отпустил — струя
## стихает за EconomyConfig.pour_stop_time (хвост). Срез точно по границе слоёв — «чистый»: искорка и «дзынь».
## Состояния: Empty → Settling → Layered ⇄ Pouring; Layered и Pouring → Empty (колбу вылили корзиной или слили всю).
## Слитая высота (доля столба сверху) = слито раньше + AlchemyRules.pour_height удержания + pour_tail_after хвоста:
## точные формулы, поэтому итог не зависит от частоты кадров. Приёмник = что было в нём до этой колбы (или пусто
## после «вылить») + AlchemyRules.pour_between с той высоты, на которой его опустошили.
## Ввод: колба — нажал и держишь = слив; тап во время отстаивания — отстоять сразу; удержание там — только «буль».
## Смесь станция получает методом receive (перенос из ступки — S4.4); тот же путь у обучения и стенда.
## Сигналы: received(mixture), receive_refused, poured_changed(poured), cut_made(poured, admixture, clean),
##   flask_emptied(reason) — REASON_DRAINED (слили всё) или REASON_TRASH (вылили корзиной).
## Зависимости: EconomyConfig, DataCatalog, SettlerConfig, AlchemyRules, EventBus (pause_changed); узлы (@export):
##   StateMachine, State Settling, Liquid колбы, HitArea, PourStream, Receiver, BandGauge, StationTrash, JuicePunch,
##   BurstParticles (искорка), SfxComponent.
class_name Settler
extends Node2D

signal received(mixture: Dictionary[StringName, float])
signal receive_refused
signal poured_changed(poured: float)
signal cut_made(poured: float, admixture: float, clean: bool)
signal flask_emptied(reason: StringName)

const STATE_EMPTY: StringName = &"Empty"
const STATE_SETTLING: StringName = &"Settling"
const STATE_LAYERED: StringName = &"Layered"
const STATE_POURING: StringName = &"Pouring"
const REASON_DRAINED: StringName = &"drained"
const REASON_TRASH: StringName = &"trash"

@export var economy: EconomyConfig
@export var catalog: DataCatalog
@export var config: SettlerConfig
@export_group("Узлы")
@export var state_machine: StateMachine
## Его timeout_sec берётся из EconomyConfig.settle_time.
@export var settling_state: State
## Поворотный узел колбы: начало — центр шара, вокруг него колба наклоняется.
@export var flask: Node2D
@export var liquid: Liquid
@export var flask_area: HitArea
@export var stream: PourStream
@export var receiver: Receiver
@export var gauge: BandGauge
@export var trash: StationTrash
## Импульсы колбы (пульс при приёме, «нет-нет» при отказе) — на дочернем Flask/Body, не на Flask: поворотом Flask
## владеет наклон слива, а JuicePunch возвращает цель в исходный поворот (один узел — один владелец).
@export var punch: JuicePunch
@export var sparkle: BurstParticles
@export var sfx_receive: SfxComponent
@export var sfx_reject: SfxComponent
@export var sfx_settle: SfxComponent
@export var sfx_glug: SfxComponent
@export var sfx_clean: SfxComponent

## Смесь в колбе на момент отстаивания: от неё считаются слои и слив. Пусто — колба пуста.
var mixture: Dictionary[StringName, float] = {}
## Сколько столба слито (0…1, сверху), включая текущее удержание и хвост.
var poured: float = 0.0

var _committed: float = 0.0
var _holding: bool = false
var _held: float = 0.0
var _tail_active: bool = false
var _tail_held: float = 0.0
var _tail_since: float = 0.0
var _receiver_base: Dictionary[StringName, float] = {}
var _receiver_from: float = 0.0
var _glug_left: float = 0.0
var _rest_position: Vector2 = Vector2.ZERO
var _pose_tween: Tween


func _ready() -> void:
	assert(economy != null and catalog != null and config != null, "Settler: нужны EconomyConfig, DataCatalog, SettlerConfig")
	assert(state_machine != null and settling_state != null and flask != null and liquid != null
			and flask_area != null and stream != null and receiver != null and gauge != null and trash != null
			and punch != null and sparkle != null, "Settler: не заданы узлы сцены")
	_rest_position = flask.position
	settling_state.timeout_sec = economy.settle_time
	settling_state.timeout_to = STATE_LAYERED
	state_machine.state_changed.connect(_on_state_changed)
	flask_area.pointer_down.connect(_on_flask_down)
	flask_area.pointer_up.connect(_on_flask_up)
	flask_area.pointer_cancelled.connect(_on_flask_cancelled)
	flask_area.tapped.connect(_on_flask_tapped)
	trash.pressed.connect(empty_flask)
	receiver.poured_out.connect(_on_receiver_poured_out)
	EventBus.pause_changed.connect(_on_pause_changed)
	liquid.show_mixture(mixture)
	trash.set_active(false)
	gauge.show_gauge(false)


func _process(delta: float) -> void:
	advance(delta)


# --- Методы для владельца, обучения и стенда ----------------------------------------------------------------------

## Принять смесь в пустую колбу: она мутнеет и отстаивается economy.settle_time. Колба не пуста — отказ.
func receive(new_mixture: Dictionary) -> bool:
	var clean: Dictionary[StringName, float] = AlchemyRules.cleaned(new_mixture)
	if not state_machine.is_in(STATE_EMPTY) or clean.is_empty():
		punch.wiggle()
		_play(sfx_reject)
		receive_refused.emit()
		return false
	mixture = clean
	_reset_pour()
	_receiver_base = receiver.mixture.duplicate()
	_receiver_from = 0.0
	liquid.show_mixture(mixture)
	liquid.stir(economy.settle_time)
	liquid.bump(config.receive_bump_px)
	punch.punch()
	_play(sfx_receive)
	_play(sfx_settle)
	state_machine.transition_to(STATE_SETTLING)
	received.emit(mixture)
	return true


## Начать слив, как будто колбу зажали. Только в Layered.
func begin_pour() -> bool:
	return state_machine.is_in(STATE_LAYERED) and state_machine.transition_to(STATE_POURING)


## Отпустить колбу: струя стихает за pour_stop_time.
func end_pour() -> void:
	if state_machine.is_in(STATE_POURING):
		state_machine.transition_to(STATE_LAYERED)


## Отстоять сразу (тап по колбе во время отстаивания).
func skip_settling() -> void:
	if state_machine.is_in(STATE_SETTLING):
		state_machine.transition_to(STATE_LAYERED)


## Вылить колбу (корзина): слитое остаётся в Приёмнике.
func empty_flask() -> void:
	if not state_machine.is_in(STATE_LAYERED):
		return
	_reset_pour()
	stream.clear()
	state_machine.transition_to(STATE_EMPTY)
	flask_emptied.emit(REASON_TRASH)


## Шаг времени: удержание и хвост. Зовётся из _process; стенд выключает процесс и шагает сам.
func advance(delta: float) -> void:
	if not _holding and not _tail_active:
		return
	var tail_done: bool = false
	if _holding:
		_held += delta
	if _tail_active:
		_tail_since += delta
		if _tail_since >= economy.pour_stop_time:
			_finish_tail()
			tail_done = true
	_update_poured()
	if poured >= 1.0:
		_drain()
		return
	if _holding:
		_follow_tilt(delta)
		_glug(delta)
		stream.pour(liquid.top_color(), _flow())
		_aim_stream()
	elif _tail_active:
		_follow_tilt(delta)
	elif tail_done:
		_judge_cut()
		_return_flask()


## Что осталось в колбе: смесь минус слитый верх.
func flask_mixture() -> Dictionary:
	return AlchemyRules.pour_top(mixture, poured, catalog, economy)[AlchemyRules.KEY_BOTTOM]


func is_pouring() -> bool:
	return _holding


## Хвост струи ещё течёт (колбу отпустили меньше pour_stop_time назад).
func is_tailing() -> bool:
	return _tail_active


# --- Состояния ----------------------------------------------------------------------------------------------------

func _on_state_changed(from: StringName, to: StringName) -> void:
	if from == STATE_POURING:
		_release(to == STATE_LAYERED)
	match to:
		STATE_EMPTY:
			_enter_empty()
		STATE_SETTLING:
			trash.set_active(false)
			gauge.show_gauge(false)
		STATE_LAYERED:
			_enter_layered(from)
		STATE_POURING:
			_enter_pouring()


func _enter_empty() -> void:
	mixture = {}
	_reset_pour()
	liquid.show_mixture(mixture)
	trash.set_active(false)
	gauge.show_gauge(false)
	_return_flask()


func _enter_layered(from: StringName) -> void:
	trash.set_active(true)
	if from != STATE_SETTLING:
		return
	liquid.settle_now()
	var marks: Array[float] = AlchemyRules.cut_marks(mixture, catalog, economy)
	gauge.set_bands(AlchemyRules.clean_bands(mixture, catalog, economy), marks)
	gauge.set_value(poured, true)
	# Один слой — границ нет, срезать нечего: шкалу не показываем (STATIONS §1.2).
	gauge.show_gauge(not marks.is_empty())


func _enter_pouring() -> void:
	trash.set_active(false)
	_holding = true
	_held = 0.0
	_glug_left = stream.grow_sec
	_kill_pose_tween()
	_pose_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(flask, ^"position", _rest_position + Vector2.UP * config.pour_lift, config.lift_sec)
	_aim_stream()
	stream.pour(liquid.top_color(), _flow())


## Колбу отпустили: удержание засчитано, начинается хвост (если колба не опустела).
func _release(with_tail: bool) -> void:
	if not _holding:
		return
	if _tail_active:
		_finish_tail()
	_committed += AlchemyRules.pour_height(_held, economy)
	_holding = false
	if with_tail:
		_tail_active = true
		_tail_held = _held
		_tail_since = 0.0
		stream.stop(economy.pour_stop_time)
	_held = 0.0


# --- Слив ---------------------------------------------------------------------------------------------------------

func _finish_tail() -> void:
	_committed += AlchemyRules.pour_tail(_tail_held, economy)
	_tail_active = false
	_tail_since = 0.0


func _update_poured() -> void:
	var now: float = _committed
	if _holding:
		now += AlchemyRules.pour_height(_held, economy)
	if _tail_active:
		now += AlchemyRules.pour_tail_after(_tail_held, _tail_since, economy)
	# Почти до дна — до дна: остаток меньше EPSILON столба уходит в Приёмник, а не пропадает вместе с колбой.
	now = 1.0 if now >= 1.0 - AlchemyRules.EPSILON else now
	if now == poured:
		return
	poured = now
	liquid.show_mixture(mixture, poured)
	gauge.set_value(poured)
	receiver.set_contents(AlchemyRules.combine(_receiver_base,
			AlchemyRules.pour_between(mixture, _receiver_from, poured, catalog, economy)))
	poured_changed.emit(poured)


## Слили всё: струя стихает, колба пуста.
func _drain() -> void:
	_holding = false
	_tail_active = false
	stream.stop(economy.pour_stop_time)
	state_machine.transition_to(STATE_EMPTY)
	flask_emptied.emit(REASON_DRAINED)


## Хвост дотёк: насколько чисто срезали. Искорка — только у чистого среза.
func _judge_cut() -> void:
	var admixture: float = AlchemyRules.cut_admixture(mixture, poured, catalog, economy)
	var clean: bool = admixture <= economy.clean_cut_admixture + AlchemyRules.EPSILON
	if clean:
		sparkle.burst(liquid.surface_point())
		_play(sfx_clean)
	cut_made.emit(poured, admixture, clean)


func _reset_pour() -> void:
	poured = 0.0
	_committed = 0.0
	_holding = false
	_held = 0.0
	_tail_active = false
	_tail_held = 0.0
	_tail_since = 0.0


## Поток струи 0…1: скорость слива относительно полной.
func _flow() -> float:
	return AlchemyRules.pour_rate(_held, economy) / economy.pour_speed_full


## «Буль» в такт скорости: на полной — раз в glug_sec_full, на медленной — реже. Приёмник мутнеет и качается.
func _glug(delta: float) -> void:
	_glug_left -= delta
	if _glug_left > 0.0:
		return
	_glug_left += config.glug_sec_full / maxf(_flow(), AlchemyRules.EPSILON)
	_play(sfx_glug)
	receiver.splash(config.receiver_bump_px)


func _aim_stream() -> void:
	stream.aim(liquid.texture_to_global(config.mouth_px), receiver.surface_point() + Vector2.DOWN * config.stream_dip_px)


# --- Поза колбы ---------------------------------------------------------------------------------------------------

## Наклон догоняет угол от уровня (D22): уровень падает — колба клонится дальше.
func _follow_tilt(delta: float) -> void:
	var weight: float = 1.0 - exp(-config.tilt_sharpness * delta)
	flask.rotation = lerp_angle(flask.rotation, liquid.pour_angle(), weight)


func _return_flask() -> void:
	if flask.position == _rest_position and flask.rotation == 0.0:
		return
	_kill_pose_tween()
	_pose_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pose_tween.tween_property(flask, ^"position", _rest_position, config.return_sec)
	_pose_tween.tween_property(flask, ^"rotation", 0.0, config.return_sec)


func _kill_pose_tween() -> void:
	if _pose_tween != null and _pose_tween.is_valid():
		_pose_tween.kill()


# --- Ввод и события -----------------------------------------------------------------------------------------------

func _on_flask_down(_world: Vector2) -> void:
	if state_machine.is_in(STATE_LAYERED):
		state_machine.transition_to(STATE_POURING)
	elif state_machine.is_in(STATE_SETTLING):
		# Удержание во время отстаивания: колба «булькает», слива нет.
		liquid.bump(config.bubble_bump_px)
		_play(sfx_glug)


func _on_flask_up(_world: Vector2, _inside: bool) -> void:
	end_pour()


func _on_flask_cancelled() -> void:
	end_pour()


func _on_flask_tapped(_world: Vector2) -> void:
	skip_settling()


## Приёмник вылили: дальше он получает только то, что сольётся с этой высоты.
func _on_receiver_poured_out() -> void:
	_receiver_base = {}
	_receiver_from = poured


## Пауза останавливает слив: колба отпущена, хвост дотечёт после паузы.
func _on_pause_changed(paused: bool) -> void:
	if paused:
		flask_area.cancel()
		end_pour()


func _play(sfx: SfxComponent) -> void:
	if sfx != null:
		sfx.play()
