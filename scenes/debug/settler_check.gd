## SettlerCheck — стенд Отстойника S4.2 (F6 на этой сцене): автопроверки станции в Output и живая колба с готовыми
## смесями. Проверки шагают Отстойник проверок сами (process выключен, Settler.advance(dt)), поэтому слитая высота
## сверяется с точными формулами AlchemyRules и эталоном python tools/alchemy/rules_model.py: при 30, 60, 144 кадрах
## в секунду и случайном шаге — одно и то же. Ещё: приём и отказ, отстаивание (само и тапом), удержание во время
## отстаивания, шкала среза (у одного слоя её нет), чистый и грязный срез, края чистой полосы, два слива подряд и
## внахлёст, Приёмник вылит посреди слива и Приёмник с прошлой колбой, слив до дна, корзины, пауза, ввод через HitArea,
## наклон колбы и её возврат. Итог — строкой «SETTLER CHECK: x/y OK», потом памятка для ручной проверки.
## Живая колба (слева) получает смеси по кругу: слили всё или вылили — через LIVE_NEXT_SEC следующая. Каждый срез —
## строкой в Output. Проверка идёт пару секунд — колбу проверок (справа) в это время не трогайте.
## Тексты на экран не выводятся.
## Сигналы: нет.
## Зависимости: DataCatalog, EconomyConfig, AlchemyRules, EventBus (pause_changed), BandGauge (OUTSIDE),
##   Отстойники Settler (@export).
extends Node2D

## Две полосы: Жизнь внизу (2/3 столба), Свет сверху (1/3) — граница на 1/3.
const TWO: Dictionary = {&"life": 2.0, &"light": 1.0}
## Смесь макета станции: три слоя, две границы.
const THREE: Dictionary = {&"sleep": 1.0, &"life": 1.1, &"light": 1.0}
## Один слой: границ нет, шкалы нет, чистого среза не бывает.
const SINGLE: Dictionary = {&"cold": 2.0}
const SIX: Dictionary = {&"acid": 0.8, &"heat": 0.8, &"life": 0.8, &"cold": 0.8, &"sleep": 0.8, &"light": 0.8}
## Смеси живой колбы по кругу.
const LIVE_MIXES: Array[Dictionary] = [THREE, TWO, SIX, SINGLE]
const LIVE_NEXT_SEC: float = 1.0
## Шаг проверок и частоты кадров для инвариантности.
const FPS: int = 60
const FPS_SET: Array[int] = [30, 60, 144]
## Кадров на удержание: ceil(сек × fps − FRAME_SLACK) — 1,0 с при 60 к/с ровно 60 кадров, а не 61.
const FRAME_SLACK: float = 0.001
## Случайный шаг: зерно и пределы кадра, секунды.
const RANDOM_SEED: int = 4242
const RANDOM_STEP_MIN: float = 0.004
const RANDOM_STEP_MAX: float = 0.05
## Эталон rules_model.py: удержание 1 с + хвост = 0,225 + 0,015 = 0,24 столба; через 0,05 с после отпускания —
## 0,225 + 0,3 · (0,05 − 0,05² / 0,2) = 0,23625.
const HOLD_SEC: float = 1.0
const POURED_AFTER_HOLD: float = 0.24
const TAIL_PEEK_SEC: float = 0.05
const POURED_AT_TAIL_PEEK: float = 0.23625
## Два слива: 0,6 с подряд (0,12 + 0,12); внахлёст — 1 с, через 0,05 с снова 0,6 с (0,24 + 0,12 = 0,36);
## нажал снова через 0,02 с на 0,03 с — хвост первого засчитан целиком, 0,24 + 0,0045 + 0,0075 = 0,252.
const SHORT_HOLD: float = 0.6
const POURED_TWO_SHORT: float = 0.24
const OVERLAP_AFTER: float = 0.05
const POURED_OVERLAP: float = 0.36
const TINY_GAP: float = 0.02
const TINY_HOLD: float = 0.03
const POURED_TINY: float = 0.252
## Пауза посреди удержания 0,4 с (короче разгона: на границе разгона скорость прыгает) — 0,06 + 0,0075.
const PAUSE_HOLD: float = 0.4
const POURED_PAUSE: float = 0.0675
## Грязный срез: слить 0,2 смеси TWO — в Отстойнике остаётся 40 % Света, примесь 0,4 / 2,4 = 1/6.
const DIRTY_TARGET: float = 0.2
const DIRTY_ADMIXTURE: float = 0.16666666666666666
## Края чистой полосы: на столько внутрь и наружу.
const BAND_EDGE_STEP: float = 0.005
## Приёмник вылит через столько секунд удержания.
const EMPTY_RECEIVER_AT: float = 0.5
## Слив до дна: эталон 0,5 + (1 − 0,075) / 0,3 с удержания; не дольше DRAIN_LIMIT_SEC.
const DRAIN_HOLD: float = 3.5833333333333335
const DRAIN_LIMIT_SEC: float = 10.0
## Хвост не может течь дольше стольких кадров.
const TAIL_GUARD_FRAMES: int = 1000
## Допуски: высота и доли (double, формулы точные), наклон колбы, поворот и позиция у покоящейся колбы.
const NEAR: float = 0.000001
const TILT_NEAR: float = 0.05
const REST_NEAR: float = 0.001
## Доли в проценты для строки живой колбы.
const PERCENT: float = 100.0
## Запас к времени твинов при ожидании, секунды.
const WAIT_MARGIN_SEC: float = 0.15

@export var catalog: DataCatalog
@export var economy: EconomyConfig
## Отстойник проверок: стенд выключает ему процесс и шагает сам.
@export var probe: Settler
## Живая колба для ручной проверки.
@export var live: Settler

var _passed: int = 0
var _total: int = 0
var _received: int = 0
var _refused: int = 0
var _cuts: int = 0
var _cut_poured: float = 0.0
var _cut_admixture: float = 0.0
var _cut_clean: bool = false
var _emptied: Array[StringName] = []
var _rest_position: Vector2 = Vector2.ZERO
var _live_index: int = 0


func _ready() -> void:
	if catalog == null or economy == null or probe == null or live == null:
		_check("каталог, экономика и оба Отстойника на месте", false)
		_finish()
		return
	probe.set_process(false)
	probe.received.connect(_on_received)
	probe.receive_refused.connect(_on_refused)
	probe.cut_made.connect(_on_cut_made)
	probe.flask_emptied.connect(_on_flask_emptied)
	live.cut_made.connect(_on_live_cut)
	live.flask_emptied.connect(_on_live_emptied)
	_run_checks.call_deferred()


func _run_checks() -> void:
	# Кадр на запуск машин состояний (autostart отложенный).
	await get_tree().process_frame
	_live_next()
	print("--- S4.2: Отстойник ---")
	_check("каталог, экономика и оба Отстойника на месте", true)
	_rest_position = probe.flask.position
	_check_setup()
	await _check_receive()
	_check_tap_skip()
	await _check_single()
	_check_frame_rate()
	_check_cuts()
	_check_two_pours()
	_check_receiver()
	await _check_drain()
	_check_trash()
	_check_pause()
	await _check_input()
	_finish()
	_print_manual()


# --- Проверки -----------------------------------------------------------------------------------------------------

func _check_setup() -> void:
	_check("пустая колба: Empty", probe.state_machine.is_in(Settler.STATE_EMPTY))
	_check("пустая колба: шкалы нет, корзина погашена", not probe.gauge.visible and not probe.trash.active)
	_check("пустая колба: Приёмник пуст, слито 0", probe.receiver.is_empty() and probe.poured == 0.0)
	_check("пустая колба: в колбе пусто", probe.flask_mixture().is_empty())
	_check("эталон: удержание 1 с + хвост = 0,24 по AlchemyRules",
			absf(_expected(HOLD_SEC) - POURED_AFTER_HOLD) <= NEAR)


func _check_receive() -> void:
	var refused: int = _refused
	_check("пустая смесь: отказ", not probe.receive({}) and _refused == refused + 1
			and probe.state_machine.is_in(Settler.STATE_EMPTY))
	var received: int = _received
	_check("смесь принята: Settling", probe.receive(TWO) and _received == received + 1
			and probe.state_machine.is_in(Settler.STATE_SETTLING))
	_check("в колбе — принятая смесь", _same_mix(probe.mixture, TWO) and _same_mix(probe.flask_mixture(), TWO))
	_check("отстаивание: корзина погашена", not probe.trash.active)
	refused = _refused
	_check("вторая смесь во время отстаивания: отказ, смесь та же",
			not probe.receive(THREE) and _refused == refused + 1 and _same_mix(probe.mixture, TWO))
	probe.flask_area.pointer_down.emit(Vector2.ZERO)
	probe.advance(1.0 / FPS)
	_check("удержание во время отстаивания: не льёт", probe.state_machine.is_in(Settler.STATE_SETTLING)
			and not probe.is_pouring() and probe.poured == 0.0 and probe.receiver.is_empty())
	probe.flask_area.pointer_up.emit(Vector2.ZERO, true)
	_check("отпустили во время отстаивания: всё ещё Settling", probe.state_machine.is_in(Settler.STATE_SETTLING))
	await _wait(economy.settle_time)
	_check("отстоялась сама за settle_time: Layered", probe.state_machine.is_in(Settler.STATE_LAYERED))
	_check("шкала среза видна, полос — по границам слоёв", probe.gauge.visible
			and probe.gauge.band_count() == AlchemyRules.cut_marks(TWO, catalog, economy).size())
	_check("отстоялась: корзина горит", probe.trash.active)
	refused = _refused
	_check("смесь в отстоянную колбу: отказ", not probe.receive(TWO) and _refused == refused + 1)


func _check_tap_skip() -> void:
	_reset_probe()
	probe.receive(THREE)
	probe.flask_area.tapped.emit(Vector2.ZERO)
	_check("тап во время отстаивания: сразу Layered", probe.state_machine.is_in(Settler.STATE_LAYERED))
	_check("три слоя: две полосы на шкале", probe.gauge.visible
			and probe.gauge.band_count() == AlchemyRules.cut_marks(THREE, catalog, economy).size())
	probe.flask_area.tapped.emit(Vector2.ZERO)
	_check("тап по отстоянной колбе: ничего", probe.state_machine.is_in(Settler.STATE_LAYERED)
			and probe.poured == 0.0)


func _check_single() -> void:
	_fresh(SINGLE)
	await _wait(probe.gauge.fade_sec)
	_check("один слой: шкала спрятана", not probe.gauge.visible and probe.gauge.band_count() == 0)
	var bursts: int = probe.sparkle.bursts
	var cuts: int = _cuts
	_pour(SHORT_HOLD)
	_check("один слой: срез не чистый, примесь 1", _cuts == cuts + 1 and not _cut_clean
			and is_equal_approx(_cut_admixture, 1.0) and probe.sparkle.bursts == bursts)


func _check_frame_rate() -> void:
	for fps: int in FPS_SET:
		_fresh(TWO)
		var cuts: int = _cuts
		_pour(HOLD_SEC, fps)
		_check("%d к/с: слито %.6f = 0,24" % [fps, probe.poured], _near(probe.poured, POURED_AFTER_HOLD)
				and _cuts == cuts + 1 and _near(_cut_poured, POURED_AFTER_HOLD))
	_fresh(TWO)
	seed(RANDOM_SEED)
	probe.begin_pour()
	_step_random(HOLD_SEC)
	probe.end_pour()
	var guard: int = 0
	while probe.is_tailing() and guard < TAIL_GUARD_FRAMES:
		probe.advance(randf_range(RANDOM_STEP_MIN, RANDOM_STEP_MAX))
		guard += 1
	_check("случайный шаг: слито %.6f = 0,24" % probe.poured, _near(probe.poured, POURED_AFTER_HOLD))
	_fresh(TWO)
	probe.begin_pour()
	_step_for(HOLD_SEC)
	probe.end_pour()
	_step_for(TAIL_PEEK_SEC)
	_check("хвост через 0,05 с: %.6f = 0,23625, ещё течёт" % probe.poured,
			_near(probe.poured, POURED_AT_TAIL_PEEK) and probe.is_tailing())
	_finish_tail()
	var split: Dictionary = AlchemyRules.pour_top(TWO, probe.poured, catalog, economy)
	_check("Приёмник = слитый верх (pour_top)", _same_mix(probe.receiver.mixture, split[AlchemyRules.KEY_TOP]))
	_check("в колбе = остаток, вместе с Приёмником — вся смесь",
			_same_mix(probe.flask_mixture(), split[AlchemyRules.KEY_BOTTOM])
			and _same_mix(AlchemyRules.combine(probe.flask_mixture(), probe.receiver.mixture), TWO))
	_check("бегунок шкалы = слитая высота", _near(probe.gauge.value, probe.poured))


func _check_cuts() -> void:
	var mark: float = AlchemyRules.cut_marks(TWO, catalog, economy)[0]
	_fresh(TWO)
	var bursts: int = probe.sparkle.bursts
	var cuts: int = _cuts
	_pour(_hold_for(mark))
	_check("срез по риске 1/3: чистый, искорка", _cuts == cuts + 1 and _cut_clean
			and _cut_admixture <= economy.clean_cut_admixture and probe.sparkle.bursts == bursts + 1
			and _near(_cut_poured, mark))
	_check("чистый срез: бегунок в зелёной полосе", probe.gauge.band_at(probe.poured) != BandGauge.OUTSIDE)
	_fresh(TWO)
	bursts = probe.sparkle.bursts
	_pour(_hold_for(DIRTY_TARGET))
	_check("слито 0,2 при границе 1/3: грязный, примесь 1/6, без искорки", not _cut_clean
			and _near(_cut_admixture, DIRTY_ADMIXTURE) and probe.sparkle.bursts == bursts)
	_check("грязный срез: бегунок вне полос", probe.gauge.band_at(probe.poured) == BandGauge.OUTSIDE)
	var band: Vector2 = AlchemyRules.clean_bands(TWO, catalog, economy)[0]
	_check_edge("нижний край полосы изнутри: чистый", band.x + BAND_EDGE_STEP, true)
	_check_edge("нижний край полосы снаружи: грязный", band.x - BAND_EDGE_STEP, false)
	_check_edge("верхний край полосы изнутри: чистый", band.y - BAND_EDGE_STEP, true)
	_check_edge("верхний край полосы снаружи: грязный", band.y + BAND_EDGE_STEP, false)


func _check_two_pours() -> void:
	_fresh(TWO)
	var cuts: int = _cuts
	_pour(SHORT_HOLD)
	_pour(SHORT_HOLD)
	_check("два слива подряд: 0,12 + 0,12, два среза", _near(probe.poured, POURED_TWO_SHORT) and _cuts == cuts + 2)
	_check("два слива подряд: Приёмник = pour_top", _receiver_is_top(TWO))
	_fresh(TWO)
	cuts = _cuts
	probe.begin_pour()
	_step_for(HOLD_SEC)
	probe.end_pour()
	_step_for(OVERLAP_AFTER)
	_check("внахлёст: снова зажали, пока течёт хвост", probe.is_tailing() and probe.begin_pour())
	_step_for(SHORT_HOLD)
	probe.end_pour()
	_finish_tail()
	_check("внахлёст: 0,24 + 0,12 = 0,36, срез один", _near(probe.poured, POURED_OVERLAP) and _cuts == cuts + 1)
	_check("внахлёст: Приёмник = pour_top", _receiver_is_top(TWO))
	_fresh(TWO)
	cuts = _cuts
	probe.begin_pour()
	_step_for(HOLD_SEC)
	probe.end_pour()
	_step_for(TINY_GAP)
	probe.begin_pour()
	_step_for(TINY_HOLD)
	probe.end_pour()
	_finish_tail()
	_check("короткое нажатие в хвосте: хвост засчитан целиком, 0,252", _near(probe.poured, POURED_TINY)
			and _cuts == cuts + 1)


func _check_receiver() -> void:
	_fresh(TWO)
	probe.begin_pour()
	_step_for(EMPTY_RECEIVER_AT)
	var from: float = probe.poured
	probe.receiver.pour_out()
	_check("Приёмник вылит посреди слива: пуст, Empty", probe.receiver.is_empty()
			and probe.receiver.state_machine.is_in(Receiver.STATE_EMPTY))
	_step_for(HOLD_SEC - EMPTY_RECEIVER_AT)
	probe.end_pour()
	_finish_tail()
	_check("…в нём только слитое после: pour_between", probe.receiver.state_machine.is_in(Receiver.STATE_FILLED)
			and _same_mix(probe.receiver.mixture, AlchemyRules.pour_between(TWO, from, probe.poured, catalog, economy)))
	var before: Dictionary = probe.receiver.mixture.duplicate()
	probe.empty_flask()
	_check("колбу вылили: Приёмник не тронут", _same_mix(probe.receiver.mixture, before))
	probe.receive(THREE)
	probe.skip_settling()
	_pour(HOLD_SEC)
	var top: Dictionary = AlchemyRules.pour_top(THREE, probe.poured, catalog, economy)[AlchemyRules.KEY_TOP]
	_check("новая колба: Приёмник = прежнее + новый слитый верх",
			_same_mix(probe.receiver.mixture, AlchemyRules.combine(before, top)))
	probe.receiver.trash.pressed.emit()
	_check("корзина Приёмника: пуст", probe.receiver.is_empty())


func _check_drain() -> void:
	_fresh(TWO)
	var cuts: int = _cuts
	var emptied: int = _emptied.size()
	probe.begin_pour()
	var frames: int = 0
	while probe.state_machine.is_in(Settler.STATE_POURING) and frames < ceili(DRAIN_LIMIT_SEC * FPS):
		probe.advance(1.0 / FPS)
		frames += 1
	var held: float = float(frames) / FPS
	_check("слив до дна: Empty через %.3f с ≈ 3,583" % held, probe.state_machine.is_in(Settler.STATE_EMPTY)
			and absf(held - DRAIN_HOLD) <= 1.0 / FPS)
	_check("слив до дна: flask_emptied(drained) один раз", _emptied.size() == emptied + 1
			and _emptied.back() == Settler.REASON_DRAINED)
	_check("слив до дна: Приёмник = вся смесь", _same_mix(probe.receiver.mixture, TWO))
	_check("слив до дна: колба пуста, слито 0, ничего не течёт", probe.mixture.is_empty() and probe.poured == 0.0
			and not probe.is_pouring() and not probe.is_tailing() and not probe.stream.is_flowing())
	_check("слив до дна: среза нет, корзина погашена", _cuts == cuts and not probe.trash.active)
	probe.advance(HOLD_SEC)
	probe.end_pour()
	_check("после дна: шаги и отпускание ничего не меняют", probe.state_machine.is_in(Settler.STATE_EMPTY)
			and _same_mix(probe.receiver.mixture, TWO) and probe.poured == 0.0)
	await _wait(probe.gauge.fade_sec)
	_check("после дна: шкала спрятана", not probe.gauge.visible)


func _check_trash() -> void:
	_fresh(TWO)
	_pour(SHORT_HOLD)
	var before: Dictionary = probe.receiver.mixture.duplicate()
	var emptied: int = _emptied.size()
	probe.trash.pressed.emit()
	_check("корзина колбы: Empty, flask_emptied(trash)", probe.state_machine.is_in(Settler.STATE_EMPTY)
			and _emptied.size() == emptied + 1 and _emptied.back() == Settler.REASON_TRASH)
	_check("корзина колбы: Приёмник не тронут, колба пуста", _same_mix(probe.receiver.mixture, before)
			and probe.mixture.is_empty() and probe.poured == 0.0)
	probe.receive(TWO)
	probe.empty_flask()
	_check("вылить во время отстаивания: нельзя", probe.state_machine.is_in(Settler.STATE_SETTLING))
	probe.skip_settling()
	probe.begin_pour()
	probe.advance(1.0 / FPS)
	_check("слив: корзина погашена", not probe.trash.active)
	probe.empty_flask()
	_check("вылить во время слива: нельзя", probe.state_machine.is_in(Settler.STATE_POURING))
	probe.end_pour()
	probe.empty_flask()
	_check("вылить, пока течёт хвост: Empty, струи нет", probe.state_machine.is_in(Settler.STATE_EMPTY)
			and not probe.is_tailing() and not probe.stream.is_flowing())


func _check_pause() -> void:
	_fresh(TWO)
	var cuts: int = _cuts
	probe.begin_pour()
	_step_for(PAUSE_HOLD)
	EventBus.pause_changed.emit(true)
	_check("пауза: слив остановлен, течёт хвост", probe.state_machine.is_in(Settler.STATE_LAYERED)
			and not probe.is_pouring() and probe.is_tailing())
	EventBus.pause_changed.emit(false)
	_finish_tail()
	_check("пауза: слито 0,06 + хвост 0,0075, срез один", _near(probe.poured, POURED_PAUSE) and _cuts == cuts + 1)


func _check_input() -> void:
	_fresh(TWO)
	probe.flask_area.pointer_down.emit(Vector2.ZERO)
	_check("зажали колбу: Pouring", probe.state_machine.is_in(Settler.STATE_POURING) and probe.is_pouring())
	_step_for(SHORT_HOLD)
	_check("льёт: струя течёт, Приёмник Filled", probe.stream.is_flowing()
			and probe.receiver.state_machine.is_in(Receiver.STATE_FILLED))
	_check("колба наклонена по уровню: %.3f ≈ %.3f рад" % [probe.flask.rotation, probe.liquid.pour_angle()],
			absf(probe.flask.rotation - probe.liquid.pour_angle()) <= TILT_NEAR)
	probe.flask_area.pointer_up.emit(Vector2.ZERO, true)
	_check("отпустили: Layered, хвост, струя стихает", probe.state_machine.is_in(Settler.STATE_LAYERED)
			and probe.is_tailing() and not probe.stream.is_flowing())
	_finish_tail()
	probe.flask_area.pointer_down.emit(Vector2.ZERO)
	probe.advance(1.0 / FPS)
	probe.flask_area.pointer_cancelled.emit()
	_check("касание сорвалось: как отпускание", probe.state_machine.is_in(Settler.STATE_LAYERED)
			and probe.is_tailing())
	_finish_tail()
	await _wait(probe.config.return_sec)
	_check("колба вернулась на место", absf(probe.flask.rotation) <= REST_NEAR
			and probe.flask.position.distance_to(_rest_position) <= REST_NEAR)


func _check_edge(title: String, target: float, clean: bool) -> void:
	_fresh(TWO)
	_pour(_hold_for(target))
	_check("%s (слито %.4f, примесь %.4f)" % [title, probe.poured, _cut_admixture],
			_near(probe.poured, target) and _cut_clean == clean)


# --- Шаги ---------------------------------------------------------------------------------------------------------

## Колба и Приёмник пусты, смесь принята и отстоена (тапом).
func _fresh(new_mixture: Dictionary) -> void:
	_reset_probe()
	probe.receive(new_mixture)
	probe.skip_settling()


## Довести колбу проверок до Empty и вылить Приёмник — из любого состояния.
func _reset_probe() -> void:
	probe.skip_settling()
	if probe.is_pouring():
		probe.end_pour()
	probe.empty_flask()
	probe.receiver.pour_out()


## Удержание sec секунд кадрами fps (последний подогнан, сумма ровно sec), отпускание и хвост до конца.
func _pour(sec: float, fps: int = FPS) -> void:
	probe.begin_pour()
	_step_for(sec, fps)
	probe.end_pour()
	_finish_tail(fps)


func _step_for(sec: float, fps: int = FPS) -> void:
	var frames: int = maxi(1, ceili(sec * fps - FRAME_SLACK))
	var dt: float = sec / frames
	for _frame: int in frames:
		probe.advance(dt)


func _step_random(sec: float) -> void:
	var left: float = sec
	while left > 0.0:
		var dt: float = minf(left, randf_range(RANDOM_STEP_MIN, RANDOM_STEP_MAX))
		probe.advance(dt)
		left -= dt


func _finish_tail(fps: int = FPS) -> void:
	var guard: int = 0
	while probe.is_tailing() and guard < TAIL_GUARD_FRAMES:
		probe.advance(1.0 / fps)
		guard += 1


## Сколько держать, чтобы вместе с хвостом слилось target: обратная к pour_height + pour_tail. Цели между
## разгоном и полной скоростью (хвост там прыгает) не бывает — стенд их не просит.
func _hold_for(target: float) -> float:
	var slow_tail: float = AlchemyRules.pour_tail(0.0, economy)
	var ramp_height: float = AlchemyRules.pour_height(economy.pour_ramp_time, economy)
	if target < ramp_height + slow_tail:
		return (target - slow_tail) / economy.pour_speed_start
	var full_tail: float = AlchemyRules.pour_tail(economy.pour_ramp_time, economy)
	return economy.pour_ramp_time + (target - ramp_height - full_tail) / economy.pour_speed_full


func _expected(hold: float) -> float:
	return AlchemyRules.pour_height(hold, economy) + AlchemyRules.pour_tail(hold, economy)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec + WAIT_MARGIN_SEC).timeout


# --- Сравнения ----------------------------------------------------------------------------------------------------

func _near(a: float, b: float) -> bool:
	return absf(a - b) <= NEAR


func _same_mix(a: Dictionary, b: Dictionary) -> bool:
	var left: Dictionary[StringName, float] = AlchemyRules.cleaned(a)
	var right: Dictionary[StringName, float] = AlchemyRules.cleaned(b)
	if left.size() != right.size():
		return false
	for property_id: StringName in left:
		if not right.has(property_id) or not _near(left[property_id], right[property_id]):
			return false
	return true


## Приёмник был пуст до этой колбы: в нём ровно слитый верх.
func _receiver_is_top(source: Dictionary) -> bool:
	var top: Dictionary = AlchemyRules.pour_top(source, probe.poured, catalog, economy)[AlchemyRules.KEY_TOP]
	return _same_mix(probe.receiver.mixture, top)


# --- Сигналы ------------------------------------------------------------------------------------------------------

func _on_received(_mixture: Dictionary) -> void:
	_received += 1


func _on_refused() -> void:
	_refused += 1


func _on_cut_made(poured: float, admixture: float, clean: bool) -> void:
	_cuts += 1
	_cut_poured = poured
	_cut_admixture = admixture
	_cut_clean = clean


func _on_flask_emptied(reason: StringName) -> void:
	_emptied.append(reason)


# --- Живая колба --------------------------------------------------------------------------------------------------

func _live_next() -> void:
	if not live.state_machine.is_in(Settler.STATE_EMPTY):
		return
	live.receive(LIVE_MIXES[_live_index])
	_live_index = (_live_index + 1) % LIVE_MIXES.size()


func _on_live_cut(poured: float, admixture: float, clean: bool) -> void:
	print("Живая колба: слито %.3f, примесь %.1f %% — %s" % [poured, admixture * PERCENT,
			"чистый срез" if clean else "срез с примесью"])


func _on_live_emptied(_reason: StringName) -> void:
	get_tree().create_timer(LIVE_NEXT_SEC).timeout.connect(_live_next)


# --- Итог ---------------------------------------------------------------------------------------------------------

func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  OK   ", title)
	else:
		print("  FAIL ", title)
		push_error("SettlerCheck: не прошло — %s" % title)


func _finish() -> void:
	print("SETTLER CHECK: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])


func _print_manual() -> void:
	print("--- Ручная проверка (живая колба слева) ---")
	print("1. Смесь пришла: колба пульсирует, мутнеет и за ~1 с расслаивается; булькает. Тап — расслоится сразу.")
	print("   Удержание во время отстаивания — только «буль» и волна, не льёт.")
	print("2. Слева шкала среза: риски на границах слоёв, вокруг — зелёные полосы. У одного слоя шкалы нет.")
	print("3. Зажмите колбу: она поднимается и наклоняется так, что у горла верхний слой; струя его цвета")
	print("   бежит в Приёмник, «буль» в такт; Приёмник мутнеет и качается. Через 0,5 с струя толще и быстрее.")
	print("4. Отпустите: струя стихает за 0,1 с и отрывается, колба возвращается. Бегунок шкалы — где срез.")
	print("5. Остановите бегунок в зелёной полосе: искорка на поверхности и «дзынь». Мимо — без искорки.")
	print("6. Корзина колбы — вылить остаток (Приёмник не трогается). Корзина Приёмника — вылить его.")
	print("7. Держите до конца: колба пустеет, Приёмник полный; через 1 с — следующая смесь.")
	print("8. Смотрите: струя начинает течь сразу при нажатии, пока колба поднимается (0,14 с) — не режет ли глаз?")
