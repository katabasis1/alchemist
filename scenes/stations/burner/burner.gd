## Burner — станция Горелки (S4.3, GDD §3.3, STATIONS §1.3): колба стоит в кольце над спиртовкой, игрок зажимает
## горелку — огонь разгорается, T растёт на EconomyConfig.heat_rate до max_temp; отпустил — огонь гаснет, T остывает
## на cool_rate до room_temp. Пока T не ниже точки свойства, оно уходит паром своего цвета (иконка улетает с паром),
## с burn_temp — сгорает (Жизнь с 90°: бурый дым, шипение, колба дрожит, лёгкая тряска камеры). Свойство ушло
## совсем — «пок»; ушло всё, что уходит при этой T, — пар стих, сигнал «готово». Кипение (пузыри, «буль») — от T.
## На пределе огонь не растёт, термометр трясётся, раз в whistle_sec — свист и облачко из колпачка.
## Состояния: Empty → Idle ⇄ Heating ⇄ Cooling; Idle и Cooling → Empty (вылили корзиной), Heating и Cooling → Empty
## (выкипело всё). Пауза: огонь отпущен (Heating → Cooling), T заморожена вместе с деревом.
## Смесь и T меняет только advance: AlchemyRules.heat и temp_after — точные формулы, итог не зависит от частоты кадров.
## Ввод: горелка/колба — нажал и держишь = огонь. Смесь станция получает методом receive (перенос из ступки — S4.4).
## Сигналы: received(mixture), receive_refused, temperature_changed(temp), property_gone(property_id, burned),
##   steam_done, flask_emptied(reason) — REASON_TRASH (вылили корзиной) или REASON_DRY (выкипело всё).
## Зависимости: EconomyConfig, DataCatalog, BurnerConfig, AlchemyRules, EventBus (pause_changed,
##   camera_shake_requested); узлы (@export): StateMachine, колба (Flask — дрожь), Liquid, Flame, Vapor, Thermometer,
##   HitArea, StationTrash, JuicePunch, BurstParticles (облачко свистка), SfxComponent.
class_name Burner
extends Node2D

signal received(mixture: Dictionary[StringName, float])
signal receive_refused
signal temperature_changed(temp: float)
signal property_gone(property_id: StringName, burned: bool)
signal steam_done
signal flask_emptied(reason: StringName)

const STATE_EMPTY: StringName = &"Empty"
const STATE_IDLE: StringName = &"Idle"
const STATE_HEATING: StringName = &"Heating"
const STATE_COOLING: StringName = &"Cooling"
const REASON_TRASH: StringName = &"trash"
const REASON_DRY: StringName = &"dry"
## Дрожь колбы по Y идёт с другой частотой, чем по X (доля от smoke_jitter_hz), — не ровный круг.
const JITTER_Y_RATIO: float = 1.37

@export var economy: EconomyConfig
@export var catalog: DataCatalog
@export var config: BurnerConfig
@export_group("Узлы")
@export var state_machine: StateMachine
## Узел колбы: начало — центр шара. Пока горит Жизнь, станция мелко трясёт его (пар и дым идут вместе с горлом).
@export var flask: Node2D
@export var liquid: Liquid
@export var flame: Flame
## Пар и дым; станция ставит его в горло колбы по BurnerConfig.mouth_px.
@export var vapor: Vapor
@export var thermometer: Thermometer
## Зажатие = огонь. Накрывает горелку и колбу.
@export var heat_area: HitArea
@export var trash: StationTrash
## Импульсы колбы (пульс при приёме, «нет-нет» при отказе) — на дочернем Flask/Body: позицией Flask владеет дрожь.
@export var punch: JuicePunch
## Белое облачко из колпачка термометра на свисте.
@export var whistle_puff: BurstParticles
@export var sfx_receive: SfxComponent
@export var sfx_reject: SfxComponent
@export var sfx_ignite: SfxComponent
@export var sfx_crackle: SfxComponent
@export var sfx_boil: SfxComponent
@export var sfx_whistle: SfxComponent
@export var sfx_hiss: SfxComponent
@export var sfx_pop: SfxComponent
@export var sfx_done: SfxComponent

## Смесь в колбе. Пусто — колбы нет (Empty).
var mixture: Dictionary[StringName, float] = {}
## Температура смеси, °.
var temp: float = 0.0

## Что уходит паром и что горит при текущей T (порядок — как в смеси).
var _steaming: Array[StringName] = []
var _burning: Array[StringName] = []
## Ритмы (треск, свист, шипение): сколько секунд до следующего удара. 0 — режим только начался: удар в этом
## же кадре, следующий ровно через период (кадр входа не вычитается — иначе интервал короче на кадр).
var _crackle_left: float = 0.0
## Фаза «буль» 0…1 (темп меняется с кипением — см. _update_boil); 1 — закипело только что, удар сразу.
var _glug_phase: float = 1.0
var _whistle_left: float = 0.0
var _shake_left: float = 0.0
var _jitter_time: float = 0.0
var _flask_rest: Vector2 = Vector2.ZERO


func _ready() -> void:
	assert(economy != null and catalog != null and config != null, "Burner: нужны EconomyConfig, DataCatalog, BurnerConfig")
	assert(state_machine != null and flask != null and liquid != null and flame != null and vapor != null
			and thermometer != null and heat_area != null and trash != null and punch != null
			and whistle_puff != null, "Burner: не заданы узлы сцены")
	temp = economy.room_temp
	_flask_rest = flask.position
	vapor.global_position = liquid.texture_to_global(config.mouth_px)
	_setup_thermometer()
	state_machine.state_changed.connect(_on_state_changed)
	heat_area.pointer_down.connect(_on_heat_down)
	heat_area.pointer_up.connect(_on_heat_up)
	heat_area.pointer_cancelled.connect(end_heat)
	trash.pressed.connect(empty_flask)
	EventBus.pause_changed.connect(_on_pause_changed)
	liquid.show_mixture(mixture)
	liquid.set_boil(0.0)
	flame.set_strength(0.0)
	trash.set_active(false)


func _process(delta: float) -> void:
	advance(delta)


# --- Методы для владельца, обучения и стенда ----------------------------------------------------------------------

## Поставить колбу со смесью на горелку (T = room_temp). Горелка занята или смесь пуста — отказ.
func receive(new_mixture: Dictionary) -> bool:
	var clean: Dictionary[StringName, float] = AlchemyRules.cleaned(new_mixture)
	if not state_machine.is_in(STATE_EMPTY) or clean.is_empty():
		punch.wiggle()
		_play(sfx_reject)
		receive_refused.emit()
		return false
	mixture = clean
	_set_temp(economy.room_temp)
	liquid.show_mixture(mixture)
	liquid.settle_now()
	liquid.bump(config.receive_bump_px)
	punch.punch()
	_play(sfx_receive)
	state_machine.transition_to(STATE_IDLE)
	received.emit(mixture)
	return true


## Зажечь огонь, как будто горелку зажали. Только в Idle и Cooling.
func begin_heat() -> bool:
	return (state_machine.is_in(STATE_IDLE) or state_machine.is_in(STATE_COOLING)) \
			and state_machine.transition_to(STATE_HEATING)


## Отпустить горелку: огонь гаснет, колба остывает.
func end_heat() -> void:
	if state_machine.is_in(STATE_HEATING):
		state_machine.transition_to(STATE_COOLING)


## Вылить колбу (корзина). Во время нагрева нельзя: сначала отпустить. Пар, дым и иконки гаснут сразу.
func empty_flask() -> void:
	if not (state_machine.is_in(STATE_IDLE) or state_machine.is_in(STATE_COOLING)):
		return
	vapor.stop()
	state_machine.transition_to(STATE_EMPTY)
	flask_emptied.emit(REASON_TRASH)


## Шаг времени: T и смесь (Heating, Cooling), затем отклик — огонь, кипение, пар, дым, предел.
## Зовётся из _process; стенд выключает процесс и шагает сам.
func advance(delta: float) -> void:
	if delta <= 0.0 or mixture.is_empty():
		return
	var heating: bool = state_machine.is_in(STATE_HEATING)
	if heating or state_machine.is_in(STATE_COOLING):
		_step_heat(heating, delta)
		if mixture.is_empty():
			return
	_update_flame(heating, delta)
	_update_boil(delta)
	_update_limit(heating, delta)
	_update_smoke(delta)


## Огонь горит (Heating).
func is_heating() -> bool:
	return state_machine.is_in(STATE_HEATING)


## Что сейчас уходит паром / горит (id свойств).
func steaming() -> Array[StringName]:
	return _steaming.duplicate()


func burning() -> Array[StringName]:
	return _burning.duplicate()


## T на пределе и огонь горит: термометр трясётся, свист.
func is_at_limit() -> bool:
	return is_heating() and temp >= economy.max_temp - AlchemyRules.EPSILON


# --- Состояния ----------------------------------------------------------------------------------------------------

func _on_state_changed(from: StringName, to: StringName) -> void:
	if from == STATE_HEATING:
		flame.fade_to(0.0, config.flame_fade_sec)
		thermometer.set_tremble(0.0)
	match to:
		STATE_EMPTY:
			_enter_empty()
		STATE_IDLE:
			trash.set_active(true)
		STATE_HEATING:
			_enter_heating()
		STATE_COOLING:
			trash.set_active(true)


func _enter_empty() -> void:
	heat_area.cancel()
	mixture = {}
	_steaming = []
	_burning = []
	# Выкипело — последний «пок» долетает; вылили корзиной — empty_flask уже погасил всё.
	var no_colors: Array[Color] = []
	var no_icons: Array[Texture2D] = []
	vapor.set_steam(no_colors, no_icons)
	vapor.set_smoke(false)
	liquid.show_mixture(mixture)
	liquid.set_boil(0.0)
	thermometer.set_tremble(0.0)
	flask.position = _flask_rest
	trash.set_active(false)
	_set_temp(economy.room_temp)


func _enter_heating() -> void:
	trash.set_active(false)
	flame.fade_to(_flame_target(), config.flame_grow_sec)
	_play(sfx_ignite)
	_crackle_left = config.crackle_sec
	_whistle_left = 0.0


# --- Нагрев -------------------------------------------------------------------------------------------------------

## Шаг T и смеси: свойства уходят паром и сгорают; ушедшие совсем — «пок»; выкипело всё — колба пуста.
## Ушло ли свойство паром или сгорело — по самой высокой T шага (в начале или в конце).
func _step_heat(heating: bool, delta: float) -> void:
	var before: Dictionary[StringName, float] = mixture
	var hottest: float = temp
	mixture = AlchemyRules.heat(mixture, temp, heating, delta, catalog, economy)
	_set_temp(AlchemyRules.temp_after(temp, heating, delta, economy))
	hottest = maxf(hottest, temp)
	if mixture != before:
		liquid.show_mixture(mixture)
	var gone_steam: bool = false
	for property_id: StringName in before:
		if mixture.has(property_id):
			continue
		var data: PropertyData = catalog.property(property_id)
		var steamed: bool = data != null and data.evaporates_at(hottest)
		gone_steam = gone_steam or steamed
		_pop(property_id, not steamed)
	if mixture.is_empty():
		state_machine.transition_to(STATE_EMPTY)
		flask_emptied.emit(REASON_DRY)
		return
	_refresh_vapor(gone_steam)
	if not heating and temp <= economy.room_temp:
		state_machine.transition_to(STATE_IDLE)


## Пар и дым по текущей T. Пар стих, потому что ушло последнее летучее (а не потому, что остыло), — «готово».
func _refresh_vapor(gone_steam: bool) -> void:
	var now_steaming: Array[StringName] = AlchemyRules.steaming(mixture, temp, catalog)
	if now_steaming != _steaming:
		var was_steaming: bool = not _steaming.is_empty()
		_steaming = now_steaming
		var colors: Array[Color] = []
		var icons: Array[Texture2D] = []
		for property_id: StringName in _steaming:
			var data: PropertyData = catalog.property(property_id)
			colors.append(data.color)
			icons.append(data.icon)
		vapor.set_steam(colors, icons)
		if was_steaming and _steaming.is_empty() and gone_steam:
			_play(sfx_done)
			steam_done.emit()
	var now_burning: Array[StringName] = AlchemyRules.burning(mixture, temp, catalog)
	if now_burning != _burning:
		var was_burning: bool = not _burning.is_empty()
		_burning = now_burning
		vapor.set_smoke(not _burning.is_empty())
		if not was_burning:
			_shake_left = 0.0
	if _burning.is_empty():
		flask.position = _flask_rest


## Свойство ушло совсем: иконка выскакивает и лопается облачком его цвета (сгоревшее — цвета опасной зоны).
func _pop(property_id: StringName, burned: bool) -> void:
	var data: PropertyData = catalog.property(property_id)
	if data != null:
		vapor.pop(data.icon, config.danger_color if burned else data.color)
	_play(sfx_pop)
	property_gone.emit(property_id, burned)


func _set_temp(value: float) -> void:
	if value == temp:
		return
	temp = value
	thermometer.set_temperature(temp)
	temperature_changed.emit(temp)


# --- Отклик -------------------------------------------------------------------------------------------------------

## Сила огня от T: flame_start в начале нагрева → 1 на пределе. Пока огонь разгорается или гаснет — твин Flame.
func _update_flame(heating: bool, delta: float) -> void:
	if heating and not flame.is_fading():
		flame.set_strength(_flame_target())
	if not flame.is_lit():
		return
	_crackle_left -= delta
	if _crackle_left <= 0.0:
		_crackle_left += config.crackle_sec
		_play(sfx_crackle)


func _flame_target() -> float:
	return lerpf(config.flame_start, 1.0, inverse_lerp(economy.room_temp, economy.max_temp, temp))


## Кипение 0…1 от T: пузыри в шейдере и «буль» в такт, поверхность вздрагивает. Темп «буль» следует за кипением:
## фаза копит delta · кипение / boil_glug_sec, удар — на 1 (первый — как только закипело, на полном — раз в
## boil_glug_sec). Не больше одного «буль» за кадр.
func _update_boil(delta: float) -> void:
	var boil: float = clampf(inverse_lerp(config.boil_from_temp, config.boil_full_temp, temp), 0.0, 1.0)
	liquid.set_boil(boil)
	if boil <= 0.0:
		_glug_phase = 1.0
		return
	_glug_phase += delta * boil / config.boil_glug_sec
	if _glug_phase < 1.0:
		return
	_glug_phase = fmod(_glug_phase, 1.0)
	_play(sfx_boil)
	liquid.bump(config.boil_bump_px)


## На пределе: термометр трясётся, сразу и потом раз в whistle_sec — свист и облачко из колпачка.
func _update_limit(heating: bool, delta: float) -> void:
	var at_limit: bool = heating and temp >= economy.max_temp - AlchemyRules.EPSILON
	thermometer.set_tremble(config.max_shake if at_limit else 0.0)
	if not at_limit:
		_whistle_left = 0.0
		return
	if _whistle_left > 0.0:
		_whistle_left -= delta
		if _whistle_left > 0.0:
			return
	_whistle_left += config.whistle_sec
	_play(sfx_whistle)
	whistle_puff.burst(thermometer.cap_point())


## Пока горит: колба мелко дрожит, раз в smoke_shake_sec — шипение и лёгкий толчок камеры.
func _update_smoke(delta: float) -> void:
	if _burning.is_empty():
		return
	_jitter_time += delta
	var phase: float = _jitter_time * TAU * config.smoke_jitter_hz
	flask.position = _flask_rest + Vector2(sin(phase), sin(phase * JITTER_Y_RATIO)) * config.smoke_jitter_px
	if _shake_left > 0.0:
		_shake_left -= delta
		if _shake_left > 0.0:
			return
	_shake_left += config.smoke_shake_sec
	_play(sfx_hiss)
	EventBus.camera_shake_requested.emit(config.smoke_camera_shake)


# --- Термометр ----------------------------------------------------------------------------------------------------

## Шкала room_temp…max_temp, зоны — пороги нагрева каталога: цвет и иконка свойства, опасная зона — danger_color.
func _setup_thermometer() -> void:
	thermometer.temp_min = economy.room_temp
	thermometer.temp_max = economy.max_temp
	var starts: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	var icons: Array[Texture2D] = []
	for zone: Dictionary in AlchemyRules.heat_zones(catalog):
		var data: PropertyData = catalog.property(zone[AlchemyRules.KEY_PROPERTY])
		starts.append(float(zone[AlchemyRules.KEY_TEMP]))
		colors.append(config.danger_color if zone[AlchemyRules.KEY_BURNS] else data.color)
		icons.append(data.icon)
	thermometer.set_zones(starts, colors, icons)
	thermometer.set_temperature(temp)


# --- Ввод и события -----------------------------------------------------------------------------------------------

func _on_heat_down(_world: Vector2) -> void:
	begin_heat()


func _on_heat_up(_world: Vector2, _inside: bool) -> void:
	end_heat()


## Пауза: огонь отпущен (дерево на паузе — T заморожена, остывать начнёт после паузы).
func _on_pause_changed(paused: bool) -> void:
	if paused:
		heat_area.cancel()
		end_heat()


func _play(sfx: SfxComponent) -> void:
	if sfx != null:
		sfx.play()
