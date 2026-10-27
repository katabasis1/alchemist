## MortarJuice — отклик ступки (S2.3, docs/gdd/STATIONS.md §2, «Ступка»). Только картинка, звук и вибрация:
## на помол и экономику не влияет, ступка работает и без этого узла.
##   ¼ круга      — крошки цвета смеси от кончика пестика, хруст (5 вариантов, своя высота тона), squash пестика,
##                  короткая вибрация. При p = 1 вместо хруста — облачко пыли, глухой звук, шкала вздрагивает.
##   помол p      — ингредиенты крошатся (шейдер ingredient.gdshader) и к началу «идеально» рассыпаются целиком,
##                  горка порошка (powder.gdshader) растёт в полости, кусочки трав в ней тают, стенки покрывает
##                  налёт; зерно горки закручивается вслед за пестиком. За «идеально» порошок сереет в пыль и гаснет.
##   «идеально»   — волна света по горлышку с веером лучей (FxRing + спутник FxRays), всплеск звёздочек, звон
##                  (шкала зеленеет сама, ZoneGauge); горка светится изнутри, над ней кружат золотые искры.
##   порошок есть — над чашей поднимаются редкие светлячки цвета смеси (гаснут в «идеально» и в пыли).
##   перетёр      — облако пыли, «пфф» ниже тоном, шкала трясётся, вибрация подлиннее.
##   бросили      — ингредиент долетел до места в чаше: полупрозрачное облачко пыли (толчок чаши и «тук» — Mortar).
## Цвет смеси — среднее цветов свойств ингредиентов (по количеству), подмешанное к цвету «сухого порошка».
## Сигналы: нет.
## Зависимости: Mortar (grind_changed, contents_changed, items, economy), DropTarget ступки (received),
##   GrindGesture (quarter_passed), ZoneGauge (zone_changed, shake), Pestle (кончик = начало узла),
##   SquashStretch пестика, BurstParticles крошек, пыли и всплеска «идеально», FxRing, светлячки (CPUParticles2D
##   Idle/Perfect из fx_motes.tscn), ColorRect порошка с powder_material.tres,
##   SfxComponent ×4, DataCatalog (цвета свойств) — всё через @export; Platform.vibrate.
class_name MortarJuice
extends Node

const PARAM_AMOUNT: StringName = &"amount"
const PARAM_POWDER_COLOR: StringName = &"powder_color"
const PARAM_FLECK_COLOR: StringName = &"fleck_color"
const PARAM_FLECKS: StringName = &"flecks"
const PARAM_COAT: StringName = &"coat"
const PARAM_GLOW: StringName = &"glow"
const PARAM_GLOW_COLOR: StringName = &"glow_color"
const PARAM_SPARKLE: StringName = &"sparkle"
const PARAM_SPIN: StringName = &"spin"
## Нижняя граница знаменателя: зона «идеально» с нуля не делит на ноль.
const MIN_SPAN: float = 0.01

@export var catalog: DataCatalog
@export_group("Отклик")
## Цвет сухого порошка: к нему подмешиваются цвета свойств (чистые цвета свойств слишком яркие для порошка).
@export var powder_base: Color = Color(0.86, 0.78, 0.6, 1.0)
## Доля цвета свойств в порошке и крошках: 0 — всегда powder_base, 1 — чистая смесь цветов свойств.
@export_range(0.0, 1.0) var property_tint: float = 0.55
## Цвет пыли при перетёре (облака и порошок за «идеально»).
@export var dust_color: Color = Color(0.9, 0.87, 0.82, 1.0)
@export var perfect_ring_color: Color = Color(0.62, 1.0, 0.45, 1.0)
## Внутренний свет горки в «идеально» и время, за которое он разгорается и гаснет.
@export var perfect_glow_color: Color = Color(1.0, 0.86, 0.45, 1.0)
@export var glow_sec: float = 0.35
## Кусочки трав в порошке: доля в самом начале помола (дальше тают до нуля к «идеально»).
@export_range(0.0, 1.0) var flecks_start: float = 1.0
## Налёт на стенках при полной горке.
@export_range(0.0, 1.0) var coat_full: float = 0.8
## Искры в порошке: обычно, в «идеально» и в пыли (перетёр).
@export_range(0.0, 1.0) var sparkle_normal: float = 0.55
@export_range(0.0, 1.0) var sparkle_perfect: float = 1.0
@export_range(0.0, 1.0) var sparkle_dust: float = 0.0
## Насколько закручивается зерно горки за один круг пестика, радианы.
@export var spin_per_circle: float = 1.6
## Крошки темнее смеси: кусочки трав в порошке (доля затемнения).
@export_range(0.0, 1.0) var fleck_darken: float = 0.45
## Светлячки над порошком появляются, когда горка выросла хотя бы до этой доли.
@export_range(0.0, 1.0) var motes_from: float = 0.25
## Насколько светлячки светлее смеси.
@export_range(0.0, 1.0) var motes_lighten: float = 0.55
## Прозрачность облачка, когда ингредиент ложится в чашу (облако пыли той же сцены, только бледнее).
@export_range(0.0, 1.0) var land_dust_alpha: float = 0.45
## Сила squash пестика на ¼ круга и на ¼ круга по пыли (доля SquashStretch.amount).
@export var quarter_squash: float = 0.6
@export var dull_squash: float = 0.3
## Шкала вздрагивает на ¼ круга по пыли (p = 1) и трясётся при перетёре (доля ZoneGauge.shake_px).
@export var dull_shake: float = 0.5
@export var overgrind_shake: float = 1.0
## Вибрация, миллисекунды (Platform.vibrate; выключается настройкой «тряска»).
@export var quarter_vibrate_ms: int = 12
@export var overgrind_vibrate_ms: int = 40
@export_group("Узлы")
@export var mortar: Mortar
@export var drop_target: DropTarget
@export var gesture: GrindGesture
@export var gauge: ZoneGauge
@export var pestle: Pestle
@export var pestle_squash: SquashStretch
@export var crumbs: BurstParticles
@export var dust: BurstParticles
@export var ring: FxRing
@export var sparkle_burst: BurstParticles
@export var motes_idle: CPUParticles2D
@export var motes_perfect: CPUParticles2D
## Середина чаши: отсюда пыль при перетёре и при броске.
@export var bowl_center: Node2D
@export var powder: CanvasItem
@export var sfx_crunch: SfxComponent
@export var sfx_dull: SfxComponent
@export var sfx_perfect: SfxComponent
@export var sfx_overgrind: SfxComponent

## Текущий цвет смеси (порошок, крошки, каёмка распада).
var mixture_color: Color = Color.WHITE

var _powder_material: ShaderMaterial
var _spin: float = 0.0
var _glow: float = 0.0
var _glow_tween: Tween


func _ready() -> void:
	mixture_color = powder_base
	if powder != null:
		_powder_material = powder.material as ShaderMaterial
	if mortar == null:
		push_warning("MortarJuice %s: не задан mortar" % get_path())
		return
	mortar.grind_changed.connect(_on_grind_changed)
	mortar.contents_changed.connect(_on_contents_changed)
	if gesture != null:
		gesture.quarter_passed.connect(_on_quarter_passed)
		gesture.turned.connect(_on_turned)
	if gauge != null:
		gauge.zone_changed.connect(_on_zone_changed)
	if drop_target != null:
		drop_target.received.connect(_on_received)
	_refresh_color()
	_apply_grind(mortar.grind)


## Распад ингредиентов 0…1 при помоле p: целиком рассыпаются к началу зоны «идеально».
func crumble_for(p: float) -> float:
	var full_at: float = mortar.economy.perfect_from if mortar.economy != null else 1.0
	return clampf(p / maxf(full_at, MIN_SPAN), 0.0, 1.0)


## Насколько порошок ушёл в пыль: 0 до конца «идеально», 1 при p = 1.
func dust_for(p: float) -> float:
	var from: float = mortar.economy.perfect_to if mortar.economy != null else 1.0
	if from >= 1.0:
		return 0.0
	return clampf((p - from) / (1.0 - from), 0.0, 1.0)


## Средний цвет свойств ингредиентов в ступке (по количеству), подмешанный к цвету сухого порошка.
func mix_color() -> Color:
	var total: float = 0.0
	var r: float = 0.0
	var g: float = 0.0
	var b: float = 0.0
	for item: IngredientItem in mortar.items:
		if item.data == null:
			continue
		for property_id: StringName in item.data.properties:
			var weight: float = item.data.properties[property_id]
			var property: PropertyData = catalog.property(property_id) if catalog != null else null
			if property == null or weight <= 0.0:
				continue
			total += weight
			r += property.color.r * weight
			g += property.color.g * weight
			b += property.color.b * weight
	if total <= 0.0:
		return powder_base
	return powder_base.lerp(Color(r / total, g / total, b / total, 1.0), property_tint)


func _refresh_color() -> void:
	mixture_color = mix_color()
	if _powder_material != null:
		_powder_material.set_shader_parameter(PARAM_FLECK_COLOR, mixture_color.darkened(fleck_darken))
		_powder_material.set_shader_parameter(PARAM_GLOW_COLOR, perfect_glow_color)


## Сколько порошка в чаше (0…1): растёт вместе с распадом; пустая ступка — 0.
func powder_amount() -> float:
	return crumble_for(mortar.grind) if not mortar.items.is_empty() else 0.0


func _apply_grind(p: float) -> void:
	var crumble: float = crumble_for(p)
	for item: IngredientItem in mortar.items:
		item.set_crumble(crumble, mixture_color)
	if _powder_material == null:
		return
	var amount: float = powder_amount()
	var dusty: float = dust_for(p)
	_powder_material.set_shader_parameter(PARAM_AMOUNT, amount)
	_powder_material.set_shader_parameter(PARAM_POWDER_COLOR, mixture_color.lerp(dust_color, dusty))
	_powder_material.set_shader_parameter(PARAM_FLECKS, flecks_start * (1.0 - crumble))
	_powder_material.set_shader_parameter(PARAM_COAT, coat_full * amount)
	var sparkle: float = sparkle_perfect if _is_perfect(p) else sparkle_normal
	_powder_material.set_shader_parameter(PARAM_SPARKLE, lerpf(sparkle, sparkle_dust, dusty))
	_update_motes(p, amount)
	if amount <= 0.0:
		_spin = 0.0
		_powder_material.set_shader_parameter(PARAM_SPIN, _spin)
		if _glow > 0.0:
			_set_glow_target(0.0)


## Светлячки: редкие цвета смеси над горкой; в «идеально» — золотые искры; в пыли и в пустой чаше — ничего.
func _update_motes(p: float, amount: float) -> void:
	var perfect: bool = amount > 0.0 and _is_perfect(p)
	var idle: bool = amount >= motes_from and not perfect and dust_for(p) <= 0.0
	if motes_idle != null:
		motes_idle.color = mixture_color.lightened(motes_lighten)
		if motes_idle.emitting != idle:
			motes_idle.emitting = idle
	if motes_perfect != null and motes_perfect.emitting != perfect:
		motes_perfect.emitting = perfect


func _is_perfect(p: float) -> bool:
	if mortar.economy == null:
		return false
	return p >= mortar.economy.perfect_from and p <= mortar.economy.perfect_to


## Внутренний свет горки: плавно к target (0 — погас, 1 — «идеально»).
func _set_glow_target(target: float) -> void:
	if _powder_material == null:
		return
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_method(_set_glow, _glow, target, glow_sec)


func _set_glow(value: float) -> void:
	_glow = value
	_powder_material.set_shader_parameter(PARAM_GLOW, value)


func _on_turned(circles: float) -> void:
	if _powder_material == null or mortar.items.is_empty():
		return
	_spin += circles * spin_per_circle
	_powder_material.set_shader_parameter(PARAM_SPIN, _spin)


func _tip() -> Vector2:
	return pestle.global_position if pestle != null else mortar.global_position


func _center() -> Vector2:
	return bowl_center.global_position if bowl_center != null else mortar.global_position


func _on_grind_changed(p: float) -> void:
	_apply_grind(p)


func _on_contents_changed(_ids: Array[StringName]) -> void:
	_refresh_color()
	_apply_grind(mortar.grind)


func _on_quarter_passed() -> void:
	if mortar.items.is_empty():
		return
	if mortar.grind >= 1.0:
		if dust != null:
			dust.burst(_tip(), dust_color)
		if sfx_dull != null:
			sfx_dull.play()
		if pestle_squash != null:
			pestle_squash.squash(dull_squash)
		if gauge != null:
			gauge.shake(dull_shake)
	else:
		if crumbs != null:
			crumbs.burst(_tip(), mixture_color)
		if sfx_crunch != null:
			sfx_crunch.play()
		if pestle_squash != null:
			pestle_squash.squash(quarter_squash)
	Platform.vibrate(quarter_vibrate_ms)


func _on_zone_changed(zone: ZoneGauge.Zone) -> void:
	if mortar.items.is_empty():
		return
	match zone:
		ZoneGauge.Zone.INSIDE:
			if ring != null:
				ring.play(perfect_ring_color)
			if sparkle_burst != null:
				sparkle_burst.burst(_center())
			if sfx_perfect != null:
				sfx_perfect.play()
			_set_glow_target(1.0)
		ZoneGauge.Zone.BELOW:
			_set_glow_target(0.0)
		ZoneGauge.Zone.ABOVE:
			_set_glow_target(0.0)
			if dust != null:
				dust.burst(_center(), dust_color)
			if sfx_overgrind != null:
				sfx_overgrind.play()
			if gauge != null:
				gauge.shake(overgrind_shake)
			Platform.vibrate(overgrind_vibrate_ms)


func _on_received(draggable: Draggable) -> void:
	var item: IngredientItem = draggable.body as IngredientItem
	if item != null:
		draggable.landed.connect(_on_item_landed.bind(item), CONNECT_ONE_SHOT)


## Ингредиент долетел. Если его успели вернуть на полку, облачка нет.
func _on_item_landed(item: IngredientItem) -> void:
	if dust == null or not is_instance_valid(item) or not mortar.items.has(item):
		return
	dust.burst(item.global_position, Color(powder_base, land_dust_alpha))
