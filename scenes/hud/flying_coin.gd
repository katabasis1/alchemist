## FlyingCoin — монетка, которая летит в счётчик (её ведёт CoinFlight): картинка монеты, мягкое свечение и шлейф искр.
## Шлейф — CPUParticles2D с local_coords = false: искры остаются там, где монетка пролетела, и гаснут сами.
## Поэтому park() прячет только картинку и выключает шлейф, а сам узел остаётся видимым, пока искры догорают.
## Монетка вертится в полёте: ширина картинки «дышит», будто монета поворачивается ребром.
## Владельцы свойств: position и scale корня — CoinFlight; scale узла Spin — сама монетка.
## Сигналы: нет. Методы: launch(at, coin_value), park(), spin(t), is_busy(); value — сколько монет несёт.
## Зависимости: нет. Узлы сцены: Trail (CPUParticles2D), Spin (Node2D) → Glow, Sprite.
class_name FlyingCoin
extends Node2D

@export var spin_node: Node2D
@export var trail: CPUParticles2D
## Сколько полных оборотов за полёт.
@export var spin_turns: float = 1.5
## Самая узкая ширина при повороте (доля полной).
@export var spin_min_width: float = 0.3

## Сколько монет несёт эта монетка.
var value: int = 0
var _busy: bool = false


func _ready() -> void:
	spin_node.visible = false
	trail.emitting = false


## Показаться в точке at (координаты слоя HUD) со своей частью суммы.
func launch(at: Vector2, coin_value: int) -> void:
	value = coin_value
	_busy = true
	global_position = at
	spin_node.scale = Vector2.ONE
	spin_node.visible = true
	trail.emitting = true


## Долетела: спрятать монету, шлейф догорает сам.
func park() -> void:
	_busy = false
	value = 0
	spin_node.visible = false
	trail.emitting = false


## Поворот ребром: t — доля полёта 0…1.
func spin(t: float) -> void:
	var width: float = lerpf(spin_min_width, 1.0, absf(cos(t * PI * spin_turns)))
	spin_node.scale = Vector2(width, 1.0)


func is_busy() -> bool:
	return _busy
