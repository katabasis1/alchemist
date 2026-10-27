## Pestle — пестик ступки: лежит в чаше, во время помола ходит за пальцем (docs/gdd/STATIONS.md §1.1).
## Начало узла — кончик пестика (картинка сдвинута в сцене), поэтому поворот — наклон вокруг кончика.
## Поза покоя — та, в которой узел стоит в сцене: головка в полости (низ прячет передний край BowlFront),
## ручка выходит через задний край горлышка. Во время помола кончик гуляет по маленькому эллипсу у дна
## (tip_center), а ручка наклоняется в сторону пальца; движение сглажено (follow_rate).
## Позицией и поворотом этого узла владеет только он сам (JuicePunch ступки качает слой Visual выше).
## Сигналы: нет.
## Зависимости: center — Marker2D в центре чаши (от него меряется палец), tip_center — Marker2D у дна полости
## (вокруг него ходит кончик; пусто — тот же center). Оба у того же родителя (@export).
class_name Pestle
extends Node2D

const FRAME_SEC: float = 1.0 / 60.0

@export var center: Node2D
## Дно полости: вокруг этой точки ходит кончик. Пусто — center.
@export var tip_center: Node2D
## Полуоси эллипса, по которому ходит кончик (локальные пиксели родителя).
@export var tip_reach: Vector2 = Vector2(60.0, 14.0)
## На этом расстоянии пальца от центра (мир) кончик доходит до края эллипса и наклон максимален.
@export var reach_px: float = 150.0
## Наибольший наклон от вертикали, радианы.
@export var max_lean: float = 0.55
## Скорость догоняния: доля пути за 1/60 с (чем больше, тем плотнее за пальцем).
@export var follow_rate: float = 0.35
## Возврат в покой после помола, секунды.
@export var rest_sec: float = 0.25
## Тычок пестиком на тап (¼ круга): туда и обратно, секунды.
@export var poke_sec: float = 0.16

var is_following: bool = false

var _rest_position: Vector2 = Vector2.ZERO
var _rest_rotation: float = 0.0
var _target_position: Vector2 = Vector2.ZERO
var _target_rotation: float = 0.0
var _rest_tween: Tween



func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	_target_position = position
	_target_rotation = rotation
	set_process(false)


## Палец над чашей (мир): пестик тянется за ним.
func follow(world_pos: Vector2) -> void:
	if not _aim(world_pos):
		return
	if _rest_tween != null and _rest_tween.is_valid():
		_rest_tween.kill()
	if not is_following:
		is_following = true
		set_process(true)


## Тап по чаше: пестик коротко толкает в сторону касания и возвращается.
func poke(world_pos: Vector2) -> void:
	if is_following:
		return
	_aim(world_pos)
	if _rest_tween != null and _rest_tween.is_valid():
		_rest_tween.kill()
	var half: float = poke_sec * 0.5
	_rest_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rest_tween.tween_property(self, ^"position", _target_position, half)
	_rest_tween.parallel().tween_property(self, ^"rotation", _target_rotation, half)
	_rest_tween.tween_property(self, ^"position", _rest_position, half)
	_rest_tween.parallel().tween_property(self, ^"rotation", _rest_rotation, half)


## Помол кончился: пестик плавно ложится как был.
func rest() -> void:
	is_following = false
	set_process(false)
	if _rest_tween != null and _rest_tween.is_valid():
		_rest_tween.kill()
	_rest_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rest_tween.tween_property(self, ^"position", _rest_position, rest_sec)
	_rest_tween.tween_property(self, ^"rotation", _rest_rotation, rest_sec)


## Цель для кончика и наклона по точке пальца. false — не к чему привязаться (нет центра или родителя).
func _aim(world_pos: Vector2) -> bool:
	var parent: Node2D = get_parent() as Node2D
	if center == null or parent == null:
		return false
	var offset: Vector2 = (world_pos - center.global_position) / maxf(reach_px, 1.0)
	offset = offset.limit_length(1.0)
	var anchor: Node2D = tip_center if tip_center != null else center
	var center_local: Vector2 = parent.to_local(anchor.global_position)
	_target_position = center_local + Vector2(offset.x * tip_reach.x, offset.y * tip_reach.y)
	_target_rotation = offset.x * max_lean
	return true


func _process(delta: float) -> void:
	# Сглаживание, не зависящее от частоты кадров.
	var k: float = 1.0 - pow(1.0 - clampf(follow_rate, 0.0, 1.0), delta / FRAME_SEC)
	position = position.lerp(_target_position, k)
	rotation = lerp_angle(rotation, _target_rotation, k)
