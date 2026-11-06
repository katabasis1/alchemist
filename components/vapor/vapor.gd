## Vapor — пар и дым над горлом колбы на Горелке (S4.3, STATIONS §1.3; референсы docs/art/refs/ref_burner_heating.jpg,
## ref_burner_overheat_smoke.jpg). Пар: мягкие клубы Steam (fx_puff) цвета уходящих свойств. Каждый клуб берёт один
## из цветов (color_initial_ramp со ступенями), излучатель плавно качается, и столб пара вьётся. Раз в
## BurnerConfig.steam_icon_sec с паром улетает белая иконка уходящего свойства (пул Icons, по кругу).
## Дым горящей Жизни — слои Smoke: бурые клубы (fx_smoke), хлопья пепла, увядшие листки.
## pop(иконка, цвет): свойство ушло совсем, иконка выскакивает из горла и лопается облачком (PopBurst).
## Частицы живут в координатах мира (local_coords = false): тряска колбы и качание излучателя их не дёргают.
## Звуки (шипение, «пок») играет станция. Начало узла — середина отверстия горла; колба трясётся отдельно.
## Сигналы: нет. Зависимости: config (BurnerConfig), дочерние Steam, Smoke…, Icons, PopBurst (@export).
class_name Vapor
extends Node2D

@export var config: BurnerConfig
@export var steam: CPUParticles2D
## Слои дыма. Первый — клубы, их число в секунду задаёт BurnerConfig.smoke_per_sec; дальше пепел и листки.
@export var smoke: Array[CPUParticles2D] = []
## Пул иконок для полёта с паром и «пок» (Sprite2D, белая заливка). Иконки берутся по кругу.
@export var icons: Array[Sprite2D] = []
@export var pop_burst: BurstParticles

@export_group("Пар")
## Насколько клубы пара светлее цвета свойства: 0 — цвет свойства, 1 — белый.
@export_range(0.0, 1.0) var steam_whiten: float = 0.2
## Качание излучателя пара: размах, px, и период, с. Столб пара от этого вьётся.
@export var sway_px: float = 9.0
@export var sway_sec: float = 1.7

@export_group("Иконка")
## Первая иконка вылетает через столько секунд после начала пара, дальше — раз в BurnerConfig.steam_icon_sec.
@export var icon_first_sec: float = 0.5
## Полёт иконки с паром: высота, px, длительность, с, и размах качания, px.
@export var icon_rise_px: float = 150.0
@export var icon_rise_sec: float = 1.9
@export var icon_sway_px: float = 10.0
## Сколько качаний за полёт.
@export var icon_sway_turns: float = 0.8
## Масштаб иконки в начале и в конце полёта.
@export var icon_scale_from: float = 0.22
@export var icon_scale_to: float = 0.36
## Доли полёта на появление и на таяние иконки.
@export_range(0.0, 0.5) var icon_fade_in: float = 0.15
@export_range(0.0, 0.5) var icon_fade_out: float = 0.35

@export_group("Пок")
## Иконка выскакивает на pop_rise_px за pop_sec, раздуваясь до pop_scale, и лопается облачком цвета свойства.
@export var pop_rise_px: float = 70.0
@export var pop_sec: float = 0.35
@export var pop_scale: float = 0.45

## Счётчики для проверочных сцен: сколько иконок улетело с паром и сколько лопнуло.
var icons_sent: int = 0
var pops: int = 0

var _steam_ramp: Gradient
var _colors: Array[Color] = []
var _icon_textures: Array[Texture2D] = []
var _next_kind: int = 0
var _next_sprite: int = 0
var _icon_wait: float = 0.0
var _time: float = 0.0
var _tweens: Dictionary[Sprite2D, Tween] = {}


func _ready() -> void:
	_steam_ramp = steam.color_initial_ramp
	steam.amount = maxi(1, roundi(config.steam_per_sec * steam.lifetime))
	if not smoke.is_empty():
		smoke[0].amount = maxi(1, roundi(config.smoke_per_sec * smoke[0].lifetime))
	steam.emitting = false
	for layer: CPUParticles2D in smoke:
		layer.emitting = false
	for sprite: Sprite2D in icons:
		sprite.visible = false


func _process(delta: float) -> void:
	_time += delta
	steam.position.x = sin(_time * TAU / sway_sec) * sway_px
	if _colors.is_empty():
		return
	_icon_wait -= delta
	if _icon_wait <= 0.0:
		_icon_wait += config.steam_icon_sec
		_send_icon()


## Что сейчас уходит паром: цвета и иконки свойств, по одному на свойство, в одном порядке.
## Пусто — пар стихает (уже вылетевшие клубы дотают).
func set_steam(colors: Array[Color], icon_textures: Array[Texture2D]) -> void:
	var was_steaming: bool = is_steaming()
	_colors = colors.duplicate()
	_icon_textures = icon_textures.duplicate()
	if _colors.is_empty():
		steam.emitting = false
		return
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var ramp: PackedColorArray = PackedColorArray()
	for i: int in _colors.size():
		offsets.append(float(i) / _colors.size())
		ramp.append(_colors[i].lerp(Color.WHITE, steam_whiten))
	_steam_ramp.offsets = offsets
	_steam_ramp.colors = ramp
	if not was_steaming:
		_icon_wait = icon_first_sec
		_next_kind = 0
	steam.emitting = true


func is_steaming() -> bool:
	return not _colors.is_empty()


## Горит Жизнь: бурые клубы, пепел и листки. false — дым стихает.
func set_smoke(on: bool) -> void:
	for layer: CPUParticles2D in smoke:
		layer.emitting = on


func is_smoking() -> bool:
	return not smoke.is_empty() and smoke[0].emitting


## Свойство ушло совсем: иконка выскакивает из горла и лопается облачком цвета свойства («пок»).
func pop(icon: Texture2D, color: Color) -> void:
	var sprite: Sprite2D = _take_sprite(icon)
	sprite.scale = Vector2.ONE * icon_scale_to
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(sprite, "position:y", -pop_rise_px, pop_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", Vector2.ONE * pop_scale, pop_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_burst.bind(sprite, color))
	_tweens[sprite] = tween
	pops += 1


## Погасить всё сразу: колбу вылили или унесли. Уже вылетевшие частицы дотают сами.
func stop() -> void:
	_colors.clear()
	_icon_textures.clear()
	steam.emitting = false
	set_smoke(false)
	for sprite: Sprite2D in icons:
		_kill_tween(sprite)
		sprite.visible = false


func _send_icon() -> void:
	if _icon_textures.is_empty():
		return
	var texture: Texture2D = _icon_textures[_next_kind % _icon_textures.size()]
	_next_kind += 1
	var sprite: Sprite2D = _take_sprite(texture)
	var phase: float = TAU * float(icons_sent % icons.size()) / icons.size()
	_fly(0.0, sprite, phase)
	var tween: Tween = create_tween()
	tween.tween_method(_fly.bind(sprite, phase), 0.0, 1.0, icon_rise_sec)
	tween.tween_callback(sprite.hide)
	_tweens[sprite] = tween
	icons_sent += 1


## Иконка на доле полёта t: вверх с замедлением, качается, растёт; появляется и тает по краям полёта.
func _fly(t: float, sprite: Sprite2D, phase: float) -> void:
	var rise: float = 1.0 - (1.0 - t) * (1.0 - t)
	sprite.position = Vector2(sin(t * TAU * icon_sway_turns + phase) * icon_sway_px, -icon_rise_px * rise)
	sprite.scale = Vector2.ONE * lerpf(icon_scale_from, icon_scale_to, t)
	var fade_in: float = clampf(t / icon_fade_in, 0.0, 1.0) if icon_fade_in > 0.0 else 1.0
	var fade_out: float = clampf((1.0 - t) / icon_fade_out, 0.0, 1.0) if icon_fade_out > 0.0 else 1.0
	sprite.modulate.a = minf(fade_in, fade_out)


func _burst(sprite: Sprite2D, color: Color) -> void:
	pop_burst.burst(sprite.global_position, color.lerp(Color.WHITE, steam_whiten))
	sprite.visible = false


func _take_sprite(texture: Texture2D) -> Sprite2D:
	var sprite: Sprite2D = icons[_next_sprite]
	_next_sprite = (_next_sprite + 1) % icons.size()
	_kill_tween(sprite)
	sprite.texture = texture
	sprite.position = Vector2.ZERO
	sprite.modulate = Color.WHITE
	sprite.visible = true
	return sprite


func _kill_tween(sprite: Sprite2D) -> void:
	var tween: Tween = _tweens.get(sprite)
	if tween != null:
		tween.kill()
	_tweens.erase(sprite)
