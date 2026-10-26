## IngredientItem — ингредиент, который берут с полки и кладут в станцию (GDD §2, §4, §10).
## Сборка как у demo_item: Lift (приподнимает Draggable) → Squash (SquashStretch, опора у основания) →
## Sprite (Hoverable — только цвет, Flash — шейдер); рядом HitArea, Shadow, звуки, Tooltip с названием.
## Материал спрайта — ingredient_material.tres: вспышка Flash + распад при помоле (set_crumble, S2.3).
## Жизнь предмета: полка ставит его в ячейку и кладёт на это место новый, как только этот приняла станция;
## станция держит его у себя (set_in_station) и отдаёт обратно на полку тапом по нему или корзиной.
## Сигналы: нет — владельцы слушают draggable и hit_area.
## Зависимости: IngredientData; Draggable, HitArea, Tooltip, Flash, SquashStretch (@export).
class_name IngredientItem
extends Node2D

const PARAM_CRUMBLE: StringName = &"crumble"
const PARAM_CRUMB_COLOR: StringName = &"crumb_color"

@export var data: IngredientData
## Размер картинки на полке и в руке.
@export var sprite_scale: float = 0.55
## Размер в станции: в чаше ступки должны поместиться двое-трое.
@export var station_scale: float = 0.42
@export var scale_sec: float = 0.16
@export_group("Узлы")
@export var sprite: Sprite2D
@export var draggable: Draggable
@export var hit_area: HitArea
@export var tooltip: Tooltip
## Красная вспышка, когда цель отказала.
@export var reject_flash: Flash
@export var squash: SquashStretch

## Предмет лежит в станции: не переносится, тап по нему возвращает его на полку (решает станция).
var in_station: bool = false
var _scale_tween: Tween


func _ready() -> void:
	sprite.scale = Vector2.ONE * sprite_scale
	if data != null:
		setup(data)
	draggable.drop_rejected.connect(_on_drop_rejected)


func setup(value: IngredientData) -> void:
	data = value
	if value == null:
		return
	sprite.texture = value.texture
	draggable.payload = value
	tooltip.set_text_key(value.name_key)


## Станция приняла предмет (true) или отдала (false). В станции предмет меньше и не переносится.
func set_in_station(value: bool) -> void:
	in_station = value
	draggable.set_enabled(not value)
	if not value:
		_reset_crumble()
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	var to_scale: float = station_scale if value else sprite_scale
	_scale_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(sprite, ^"scale", Vector2.ONE * to_scale, scale_sec)


## Распад при помоле: 0 — целый, 1 — рассыпался в порошок (шейдер ingredient.gdshader). color — цвет крошки.
func set_crumble(amount: float, color: Color) -> void:
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(PARAM_CRUMBLE, clampf(amount, 0.0, 1.0))
	mat.set_shader_parameter(PARAM_CRUMB_COLOR, color)


func get_crumble() -> float:
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null:
		return 0.0
	return float(mat.get_shader_parameter(PARAM_CRUMBLE))


func _reset_crumble() -> void:
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(PARAM_CRUMBLE, 0.0)


## Появление в ячейке полки: короткий «плюх».
func pop_in() -> void:
	squash.squash()


func _on_drop_rejected(target: DropTarget) -> void:
	if target != null:
		reject_flash.flash()
