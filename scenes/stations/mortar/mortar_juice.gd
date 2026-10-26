## MortarJuice — отклик ступки (S2.3, docs/gdd/STATIONS.md §2, «Ступка»). Только картинка, звук и вибрация:
## на помол и экономику не влияет, ступка работает и без этого узла.
##   ¼ круга      — крошки цвета смеси от кончика пестика, хруст (5 вариантов, своя высота тона), squash пестика,
##                  короткая вибрация. При p = 1 вместо хруста — облачко пыли, глухой звук, шкала вздрагивает.
##   помол p      — ингредиенты крошатся (шейдер ingredient.gdshader) и к началу «идеально» рассыпаются целиком,
##                  горка порошка (powder.gdshader) растёт; за «идеально» порошок сереет в пыль.
##   «идеально»   — кольцо света по краю чаши и звон (шкала зеленеет сама, ZoneGauge).
##   перетёр      — облако пыли, «пфф» ниже тоном, шкала трясётся, вибрация подлиннее.
##   бросили      — ингредиент долетел до места в чаше: полупрозрачное облачко пыли (толчок чаши и «тук» — Mortar).
## Цвет смеси — среднее цветов свойств ингредиентов (по количеству), подмешанное к цвету «сухого порошка».
## Сигналы: нет.
## Зависимости: Mortar (grind_changed, contents_changed, items, economy), DropTarget ступки (received),
##   GrindGesture (quarter_passed), ZoneGauge (zone_changed, shake), Pestle (кончик = начало узла),
##   SquashStretch пестика, BurstParticles крошек и пыли, FxRing, ColorRect порошка с powder_material.tres,
##   SfxComponent ×4, DataCatalog (цвета свойств) — всё через @export; Platform.vibrate.
class_name MortarJuice
extends Node

const PARAM_FILL: StringName = &"fill"
const PARAM_POWDER_COLOR: StringName = &"powder_color"
const PARAM_DUST: StringName = &"dust"
const PARAM_DUST_COLOR: StringName = &"dust_color"
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
		_powder_material.set_shader_parameter(PARAM_POWDER_COLOR, mixture_color)
		_powder_material.set_shader_parameter(PARAM_DUST_COLOR, dust_color)


func _apply_grind(p: float) -> void:
	var crumble: float = crumble_for(p)
	for item: IngredientItem in mortar.items:
		item.set_crumble(crumble, mixture_color)
	if _powder_material != null:
		_powder_material.set_shader_parameter(PARAM_FILL, crumble if not mortar.items.is_empty() else 0.0)
		_powder_material.set_shader_parameter(PARAM_DUST, dust_for(p))


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
			if sfx_perfect != null:
				sfx_perfect.play()
		ZoneGauge.Zone.ABOVE:
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
