## LiquidCheck — жидкость S4.1 в Godot (F6 на этой сцене): проверки в Output и колбы для сравнения с
## docs/art/refs/ref_liquid_*.jpg. Те же случаи, что python tools/alchemy/liquid_model.py --self-test (эталон):
## LiquidLayers.view и LiquidSlosh, плюс то, чего Python не видит: узел Liquid ставит параметры шейдера, муть
## отстаивается, поверхность держит горизонт при повороте, разгон вбок наклоняет её к нужной стенке, толчок затухает.
## Слив (S4.2): LiquidPourTilt.angle сверяется с числами эталона, узел — pour_angle, top_color, surface_point,
## texture_to_global, stir(сек), settle_now.
## На экране: верхний ряд — шесть свойств по одному (узоры), нижний — 4 слоя, 6 слоёв, слив, муть раз в
## STIR_EVERY с, качание колбы, рывки вбок и колба проверок. Итог — строкой «LIQUID CHECK: x/y».
## Сигналы: нет. Зависимости: DataCatalog, EconomyConfig, LiquidSlosh, колбы Liquid (@export), LiquidLayers,
##   LiquidPourTilt (у колбы проверок).
extends Node2D

## Порядок колб верхнего ряда = порядок детей singles_row: тяжёлое слева.
const SINGLE_ORDER: Array[StringName] = [&"acid", &"heat", &"life", &"cold", &"sleep", &"light"]
const SINGLE_AMOUNT: float = 3.0
const LAYERED: Dictionary = {&"acid": 1.0, &"life": 1.1, &"cold": 1.0, &"light": 1.0}
const SIX: Dictionary = {&"acid": 0.8, &"heat": 0.8, &"life": 0.8, &"cold": 0.8, &"sleep": 0.8, &"light": 0.8}
const POUR_SHARE: float = 0.4
const STIR_EVERY: float = 3.0
const SWING_ANGLE: float = 0.5
const SWING_SEC: float = 1.6
const SHAKE_PX: float = 60.0
const SHAKE_SEC: float = 0.35
const SHAKE_PAUSE: float = 1.5
## Проверки view: Холод 2 при ёмкости 4 — уровень 0,5; Холод 9 — перелив.
const PROBE_CAPACITY: float = 4.0
const COLD_PATTERN: int = 3
## Проверки узла.
const TURN: float = 0.4
const RESTING: float = 0.01
const SETTLE_WAIT: float = 3.0
const SPEED_UP_FRAMES: int = 6
const SPEED_UP_PX: float = 6.0
const BUMP_PX: float = 10.0
const BUMP_WAIT: float = 1.0
const BUMP_TOLERANCE: float = 0.15
const NEAR: float = 0.000001
## Смеси колб «качание» и «рывки вбок».
const SWING_MIX: Dictionary = {&"heat": 1.2, &"light": 1.4}
const SHAKER_MIX: Dictionary = {&"life": 1.5, &"cold": 1.5}
## level: Холод 1 + Жизнь 2 при ёмкости 4 — 0,75; Холод 9 — перелив.
const LEVEL_MIX: Dictionary = {&"cold": 1.0, &"life": 2.0}
const LEVEL_EXPECTED: float = 0.75
const OVERFLOW: float = 9.0
## LiquidSlosh — те же случаи, что check_slosh в liquid_model.py.
const PUSH: float = 1000.0
const JOLT: float = 1e9
const SMALL_TURN: float = 0.05
const FPS: int = 60
const SLOW_FPS: int = 12
const FPS_SET: Array[int] = [30, 60, 144]
const TILTED: float = 0.3
const OVERSHOOT: float = -0.02
const QUIET_SEC: float = 3.0
const HELD_ACCEL: float = 800.0
const HELD_SEC: float = 4.0
const HELD_TOLERANCE: float = 0.001
const HARD_TURN: float = 3.0
const HARD_TURN_SEC: float = 0.05
const STICK_SEC: float = 0.5
const UNSTUCK_SHARE: float = 0.8
const FPS_TURN: float = 0.3
const FPS_TURN_SEC: float = 0.1
const FPS_SEC: float = 0.6
const FPS_TOLERANCE: float = 0.04
## Узел: «мутная» — выше этого; запас к settle_sec на последний кадр твина.
const TURBID: float = 0.9
## Слив (S4.2, D22): смесь макета Отстойника при ёмкости колбы 5 и наклон по эталону
## (python tools/alchemy/liquid_model.py, LiquidPourTilt.angle) для слива 0 / 0,12 / 0,3 / 0,5; пустая колба.
const POUR_MIX: Dictionary = {&"sleep": 1.0, &"life": 1.1, &"light": 1.0}
const POUR_CAPACITY: float = 5.0
const POUR_SHARES: Array[float] = [0.0, 0.12, 0.3, 0.5]
const POUR_ANGLES: Array[float] = [1.515164683083612, 1.5685348379924946, 1.6049847656662126, 1.7340810508014253]
const POUR_ANGLE_EMPTY: float = 1.9293679119476301
## tops приходят во float32: расхождение с эталоном на double — около 1e-6 рад.
const ANGLE_NEAR: float = 0.0001
const POUR_STEPS: int = 40
## 70° и 120° в радианах: колба не переворачивается.
const POUR_MIN_ANGLE: float = 1.2217304763960306
const POUR_MAX_ANGLE: float = 2.0943951023931953
const QUARTER_TURN: float = PI / 2.0
const QUICK_STIR: float = 0.5
const PIXEL_NEAR: float = 0.01
const SETTLE_SLACK: float = 0.2

@export var catalog: DataCatalog
@export var economy: EconomyConfig
@export var slosh: LiquidSlosh
@export var singles_row: Node2D
@export var layered: Liquid
@export var six: Liquid
@export var poured: Liquid
@export var stirred: Liquid
@export var swing: Liquid
@export var shaker: Liquid
@export var probe: Liquid

var _passed: int = 0
var _total: int = 0


func _ready() -> void:
	_check("каталог, экономика, раскачка и колбы на месте", catalog != null and economy != null and slosh != null
			and singles_row != null and probe != null)
	if catalog == null or economy == null or slosh == null or probe == null:
		_finish()
		return
	_show_flasks()
	_check_view()
	_check_slosh()
	await _check_node()
	await _check_pour()
	_finish()


func _show_flasks() -> void:
	var children: Array[Node] = singles_row.get_children()
	for i: int in mini(children.size(), SINGLE_ORDER.size()):
		(children[i] as Liquid).show_mixture({SINGLE_ORDER[i]: SINGLE_AMOUNT})
	layered.show_mixture(LAYERED)
	six.show_mixture(SIX)
	poured.show_mixture(LAYERED, POUR_SHARE)
	stirred.show_mixture(LAYERED)
	swing.show_mixture(SWING_MIX)
	shaker.show_mixture(SHAKER_MIX)
	var stir_loop: Tween = create_tween().set_loops()
	stir_loop.tween_callback(stirred.stir)
	stir_loop.tween_interval(STIR_EVERY)
	var swing_loop: Tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	swing_loop.tween_property(swing, "rotation", SWING_ANGLE, SWING_SEC)
	swing_loop.tween_property(swing, "rotation", -SWING_ANGLE, SWING_SEC)
	var x: float = shaker.position.x
	var shake_loop: Tween = create_tween().set_loops().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	shake_loop.tween_property(shaker, "position:x", x + SHAKE_PX, SHAKE_SEC)
	shake_loop.tween_interval(SHAKE_PAUSE)
	shake_loop.tween_property(shaker, "position:x", x, SHAKE_SEC)
	shake_loop.tween_interval(SHAKE_PAUSE)


func _check_view() -> void:
	var empty: Dictionary = LiquidLayers.view({}, 0.0, PROBE_CAPACITY, catalog, economy)
	_check("view пусто: слоёв нет, муть прозрачная", _tops(empty).is_empty()
			and (empty[LiquidLayers.KEY_MIXED] as Color).a == 0.0)
	var one: Dictionary = LiquidLayers.view({&"cold": 2.0}, 0.0, PROBE_CAPACITY, catalog, economy)
	var cold: Color = catalog.property(&"cold").color
	_check("view одно свойство: цвет и узор свойства, уровень 0,5", _tops(one).size() == 1
			and (one[LiquidLayers.KEY_COLORS] as PackedColorArray)[0] == cold
			and (one[LiquidLayers.KEY_PATTERNS] as PackedInt32Array)[0] == COLD_PATTERN
			and absf(_tops(one)[0] - 0.5) < NEAR and (one[LiquidLayers.KEY_MIXED] as Color).is_equal_approx(cold))
	_check("level: доли / ёмкость, не выше 1, ёмкость 0 — пусто",
			absf(LiquidLayers.level(LEVEL_MIX, PROBE_CAPACITY) - LEVEL_EXPECTED) < NEAR
			and LiquidLayers.level({&"cold": OVERFLOW}, PROBE_CAPACITY) == 1.0
			and LiquidLayers.level({&"cold": 1.0}, 0.0) == 0.0)
	var full: Dictionary = LiquidLayers.view({&"cold": OVERFLOW}, 0.0, PROBE_CAPACITY, catalog, economy)
	_check("view перелив: поверхность = 1", absf(_tops(full)[-1] - 1.0) < NEAR)
	var six_view: Dictionary = LiquidLayers.view(SIX, 0.0, probe.capacity, catalog, economy)
	var patterns: PackedInt32Array = six_view[LiquidLayers.KEY_PATTERNS]
	_check("view шесть свойств: шесть слоёв, тяжёлое внизу (Едкость → Свет)", patterns.size() == LiquidLayers.MAX_LAYERS
			and patterns[0] == catalog.property(&"acid").pattern and patterns[-1] == catalog.property(&"light").pattern
			and _ascending(_tops(six_view)))
	var cut: Dictionary = LiquidLayers.view(LAYERED, POUR_SHARE, probe.capacity, catalog, economy)
	var whole: Dictionary = LiquidLayers.view(LAYERED, 0.0, probe.capacity, catalog, economy)
	_check("view слив: верх срезан, низ на месте", _tops(cut).size() < _tops(whole).size()
			and absf(_tops(cut)[0] - _tops(whole)[0]) < NEAR
			and absf(_tops(cut)[-1] - (1.0 - POUR_SHARE) * LiquidLayers.level(LAYERED, probe.capacity)) < NEAR)
	_check("view слив всего столба — пусто",
			_tops(LiquidLayers.view(LAYERED, 1.0, probe.capacity, catalog, economy)).is_empty())


func _check_slosh() -> void:
	_check("разгон вправо: жидкость набегает на левую стенку (угол > 0)", slosh.target(PUSH) > 0.0)
	_check("торможение: набегает на правую (угол < 0)", slosh.target(-PUSH) < 0.0)
	_check("рывок не наклоняет сильнее предела", slosh.target(JOLT) == slosh.max_angle)
	_check("поворот по часовой: стенки тянут поверхность за собой",
			slosh.step(Vector2.ZERO, 0.0, SMALL_TURN, 1.0 / FPS).x > 0.0)
	var free: Vector3 = _run_slosh(FPS, QUIET_SEC, Vector2(TILTED, 0.0), 0.0, 0.0, 0.0)
	_check("качается и за 3 с успокаивается", free.y < OVERSHOOT and absf(free.x) < RESTING)
	_check("на 12 кадрах/с тоже успокаивается", absf(_run_slosh(SLOW_FPS, QUIET_SEC, Vector2(TILTED, 0.0), 0.0, 0.0, 0.0).x) < RESTING)
	var held: float = _run_slosh(FPS, HELD_SEC, Vector2.ZERO, HELD_ACCEL, 0.0, 0.0).x
	_check("постоянное ускорение: держит наклон target", absf(held - slosh.target(HELD_ACCEL)) < HELD_TOLERANCE)
	_check("резкий поворот не пробивает предел", _run_slosh(FPS, 1.0, Vector2.ZERO, 0.0, HARD_TURN, HARD_TURN_SEC).z <= slosh.max_angle)
	_check("после удара в предел не залипает",
			absf(_run_slosh(FPS, STICK_SEC, Vector2.ZERO, 0.0, HARD_TURN, HARD_TURN_SEC).x)
			< UNSTUCK_SHARE * slosh.max_angle)
	var ends: Array[float] = []
	for fps: int in FPS_SET:
		ends.append(_run_slosh(fps, FPS_SEC, Vector2.ZERO, 0.0, FPS_TURN, FPS_TURN_SEC).x)
	_check("не зависит от частоты кадров (30/60/144)", ends.max() - ends.min() < FPS_TOLERANCE)
	var px: float = BUMP_PX
	for i: int in FPS:
		px = slosh.fade(px, 1.0 / FPS)
	_check("волна толчка затухает по экспоненте, кадры роли не играют",
			absf(px - BUMP_PX * exp(-slosh.bump_decay)) < NEAR)


## Узел Liquid вживую: параметры шейдера, муть, горизонт, разгон, толчок.
func _check_node() -> void:
	var mat: ShaderMaterial = probe.material as ShaderMaterial
	_check("у колбы свой ShaderMaterial (local to scene)", mat != null and mat != layered.material)
	probe.show_mixture(SIX)
	var tops: PackedFloat32Array = mat.get_shader_parameter(&"layer_tops")
	_check("шейдер получил шесть слоёв, верх = уровень колбы", int(mat.get_shader_parameter(&"layer_count")) == LiquidLayers.MAX_LAYERS
			and tops.size() == LiquidLayers.MAX_LAYERS
			and absf(tops[-1] - LiquidLayers.level(SIX, probe.capacity)) < NEAR)
	probe.show_mixture({})
	_check("пустая колба: слоёв 0", int(mat.get_shader_parameter(&"layer_count")) == 0)
	probe.show_mixture(LAYERED)
	probe.stir()
	await _frames(2)
	_check("stir: смесь мутная", float(mat.get_shader_parameter(&"turbidity")) > TURBID)
	await get_tree().create_timer(probe.settle_sec + SETTLE_SLACK).timeout
	_check("за settle_sec отстоялась", float(mat.get_shader_parameter(&"turbidity")) < RESTING)
	probe.rotation = TURN
	await _frames(2)
	_check("поворот колбы: поверхность сначала тянется за стенками", probe.surface_tilt() > 0.0)
	await get_tree().create_timer(SETTLE_WAIT).timeout
	_check("потом встаёт в горизонт: surface_angle = −rotation", absf(probe.surface_tilt()) < RESTING
			and absf(float(mat.get_shader_parameter(&"surface_angle")) + TURN) < RESTING)
	probe.rotation = 0.0
	await get_tree().create_timer(SETTLE_WAIT).timeout
	for i: int in SPEED_UP_FRAMES:
		probe.position.x += SPEED_UP_PX * float(i + 1)
		await get_tree().process_frame
	_check("разгон вправо: поверхность выше у левой стенки", probe.surface_tilt() > 0.0)
	probe.bump(BUMP_PX)
	await get_tree().create_timer(BUMP_WAIT).timeout
	var expected: float = BUMP_PX * exp(-slosh.bump_decay * BUMP_WAIT)
	_check("толчок затухает", absf(float(mat.get_shader_parameter(&"slosh_px")) - expected) < expected * BUMP_TOLERANCE)


## Слив (S4.2): наклон по уровню (D22) и то, что нужно станции Отстойника от колбы.
func _check_pour() -> void:
	var tilt: LiquidPourTilt = probe.pour_tilt
	_check("у колбы есть LiquidPourTilt", tilt != null)
	if tilt == null:
		return
	var mat: ShaderMaterial = probe.material as ShaderMaterial
	var column: float = float(mat.get_shader_parameter(&"column_height"))
	var center: Vector2 = mat.get_shader_parameter(&"bulb_center")
	var radius: float = float(mat.get_shader_parameter(&"bulb_radius"))
	var worst: float = 0.0
	for i: int in POUR_SHARES.size():
		var tops: PackedFloat32Array = _tops(LiquidLayers.view(POUR_MIX, POUR_SHARES[i], POUR_CAPACITY, catalog, economy))
		worst = maxf(worst, absf(tilt.angle(tops, column, center, radius) - POUR_ANGLES[i]))
	_check("LiquidPourTilt.angle = эталон (слив 0 / 0,12 / 0,3 / 0,5)", worst < ANGLE_NEAR)
	_check("пустая колба: наклон как у эталона", absf(tilt.angle(PackedFloat32Array(), column, center, radius)
			- POUR_ANGLE_EMPTY) < ANGLE_NEAR)
	var previous: float = 0.0
	var growing: bool = true
	var inside: bool = true
	for k: int in POUR_STEPS + 1:
		var tops: PackedFloat32Array = _tops(LiquidLayers.view(POUR_MIX, float(k) / POUR_STEPS, POUR_CAPACITY,
				catalog, economy))
		if tops.is_empty():
			continue
		var angle: float = tilt.angle(tops, column, center, radius)
		growing = growing and angle >= previous - NEAR
		inside = inside and angle >= POUR_MIN_ANGLE and angle <= POUR_MAX_ANGLE
		previous = angle
	_check("по ходу слива колба только клонится дальше", growing)
	_check("наклон в пределах 70…120°", inside)
	probe.rotation = 0.0
	probe.show_mixture(POUR_MIX, POUR_SHARES[1])
	var view: Dictionary = LiquidLayers.view(POUR_MIX, POUR_SHARES[1], probe.capacity, catalog, economy)
	var colors: PackedColorArray = view[LiquidLayers.KEY_COLORS]
	_check("узел: pour_angle() = angle по показанным слоям",
			absf(probe.pour_angle() - tilt.angle(_tops(view), column, center, radius)) < NEAR)
	_check("top_color() — цвет верхнего слоя", probe.top_color() == colors[colors.size() - 1])
	var half: Vector2 = probe.texture.get_size() * 0.5
	_check("texture_to_global: середина холста — позиция колбы",
			probe.texture_to_global(half).distance_to(probe.global_position) < PIXEL_NEAR)
	var scale_y: float = probe.global_scale.y
	var surface: float = _tops(view)[-1] * column
	var bulb: Vector2 = probe.texture_to_global(center)
	var point: Vector2 = probe.surface_point()
	_check("surface_point без наклона: над центром шара на (поверхность − радиус)",
			absf(point.x - bulb.x) < PIXEL_NEAR and absf((bulb.y - point.y) - (surface - radius) * scale_y) < PIXEL_NEAR)
	probe.rotation = QUARTER_TURN
	var top_mid: Vector2 = probe.texture_to_global(Vector2(half.x, 0.0))
	_check("texture_to_global после поворота на 90°: верх холста справа от центра",
			absf(top_mid.y - probe.global_position.y) < PIXEL_NEAR and top_mid.x > probe.global_position.x)
	bulb = probe.texture_to_global(center)
	point = probe.surface_point()
	_check("surface_point при наклоне: на вертикали через центр шара (горизонт)",
			absf(point.x - bulb.x) < PIXEL_NEAR and absf((bulb.y - point.y) - (surface - radius) * scale_y) < PIXEL_NEAR)
	probe.rotation = 0.0
	probe.show_mixture({})
	_check("пустая колба: top_color прозрачный", probe.top_color().a == 0.0)
	probe.show_mixture(POUR_MIX)
	probe.stir(QUICK_STIR)
	await _frames(2)
	probe.settle_now()
	_check("settle_now: муть пропала сразу", float(mat.get_shader_parameter(&"turbidity")) == 0.0)
	await _frames(2)
	_check("settle_now: твин мути остановлен, муть не вернулась", float(mat.get_shader_parameter(&"turbidity")) == 0.0)
	probe.stir(QUICK_STIR)
	await _frames(2)
	var turbid: bool = float(mat.get_shader_parameter(&"turbidity")) > TURBID
	await get_tree().create_timer(QUICK_STIR + SETTLE_SLACK).timeout
	_check("stir(сек): мутнеет и отстаивается за заданное время, а не за settle_sec",
			turbid and float(mat.get_shader_parameter(&"turbidity")) < RESTING and QUICK_STIR + SETTLE_SLACK < probe.settle_sec)


## process_frame приходит до _process и шага твинов: чтобы колба успела отработать кадр, ждём два.
func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


## Прогон LiquidSlosh кадрами 1/fps: поворот turn_total равномерно за turn_sec. → (угол, мин. угол, макс. |угол|).
func _run_slosh(fps: int, seconds: float, state: Vector2, accel_x: float, turn_total: float, turn_sec: float) -> Vector3:
	var delta: float = 1.0 / float(fps)
	var turn_frames: int = roundi(turn_sec * fps)
	var low: float = state.x
	var high: float = absf(state.x)
	for frame: int in roundi(seconds * fps):
		var turn: float = turn_total / turn_frames if frame < turn_frames else 0.0
		state = slosh.step(state, slosh.target(accel_x), turn, delta)
		low = minf(low, state.x)
		high = maxf(high, absf(state.x))
	return Vector3(state.x, low, high)


func _tops(view: Dictionary) -> PackedFloat32Array:
	return view[LiquidLayers.KEY_TOPS]


func _ascending(values: PackedFloat32Array) -> bool:
	for i: int in range(1, values.size()):
		if values[i] <= values[i - 1]:
			return false
	return true


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  [OK] ", title)
	else:
		print("  [!!] ", title)


func _finish() -> void:
	print("LIQUID CHECK: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])
