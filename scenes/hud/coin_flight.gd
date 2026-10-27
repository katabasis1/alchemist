## CoinFlight — монеты вылетают пачкой из точки и по дуге со шлейфом летят в счётчик (STATIONS §3 «Монеты»).
## Сумма делится на монетки: coins_per_sprite монет на штуку, от min_sprites до max_sprites штук; у каждой своя часть,
## их сумма равна оплате. Вылет: монетки «выскакивают» веером вокруг точки, затем по очереди (stagger_sec) летят
## к цели по квадратичной кривой Безье с ускорением и уменьшаются к концу.
## Пул монеток создаётся в _ready из coin_scene (instantiate); если все заняты, часть суммы засчитывается сразу.
## Координаты from/to — в слое HUD (CanvasLayer), сам узел стоит в начале координат слоя без поворота и масштаба.
## Сигналы: coin_landed(value) — монетка долетела (счётчик добавляет value); flight_finished — в пути никого не осталось.
## Методы: fly(from, to, amount) → сколько монеток вылетело; flying_count, launched — для проверочной сцены.
## Зависимости: coin_scene (FlyingCoin).
class_name CoinFlight
extends Node2D

signal coin_landed(value: int)
signal flight_finished

@export var coin_scene: PackedScene
@export var pool_size: int = 12
@export_group("Сколько монеток")
## Монет на одну летящую монетку.
@export var coins_per_sprite: int = 5
@export var min_sprites: int = 3
@export var max_sprites: int = 10
@export_group("Вылет")
@export var burst_radius_min: float = 50.0
@export var burst_radius_max: float = 110.0
## Веер раскрывается вверх: монетки поднимаются над точкой вылета на столько.
@export var burst_up: float = 50.0
@export var pop_sec: float = 0.26
@export var pop_from_scale: float = 0.3
@export_group("Полёт")
@export var stagger_sec: float = 0.07
@export var fly_sec: float = 0.55
@export var fly_sec_jitter: float = 0.08
## Изгиб дуги: контрольная точка уходит вбок от прямой на эту долю её длины (сторона случайная).
@export var arc_bend: float = 0.3
@export var land_scale: float = 0.6

## Монеток в пути сейчас.
var flying_count: int = 0
## Монеток выпущено за всё время (для проверок).
var launched: int = 0
var _pool: Array[FlyingCoin] = []


func _ready() -> void:
	for i: int in pool_size:
		var coin: FlyingCoin = coin_scene.instantiate() as FlyingCoin
		add_child(coin)
		_pool.append(coin)


## Выпустить amount монет из from в to. Возвращает, сколько монеток полетело (остаток засчитан сразу).
func fly(from: Vector2, to: Vector2, amount: int) -> int:
	if amount <= 0:
		return 0
	var count: int = sprites_for(amount)
	var base: int = floori(float(amount) / float(count))
	var extra: int = amount - base * count
	var sent: int = 0
	for i: int in count:
		var value: int = base + (1 if i < extra else 0)
		var coin: FlyingCoin = _free_coin()
		if coin == null:
			coin_landed.emit(value)
			continue
		_launch(coin, from, to, value, sent)
		sent += 1
	if sent == 0 and flying_count == 0:
		flight_finished.emit()
	return sent


## Сколько монеток понадобится на сумму (не больше самой суммы: на 2 монеты — 2 монетки).
func sprites_for(amount: int) -> int:
	if amount <= 0:
		return 0
	var wanted: int = ceili(float(amount) / float(maxi(coins_per_sprite, 1)))
	return mini(clampi(wanted, min_sprites, max_sprites), amount)


func _free_coin() -> FlyingCoin:
	for coin: FlyingCoin in _pool:
		if not coin.is_busy():
			return coin
	return null


func _launch(coin: FlyingCoin, from: Vector2, to: Vector2, value: int, index: int) -> void:
	flying_count += 1
	launched += 1
	var angle: float = randf_range(-PI, 0.0)
	var burst: Vector2 = from + Vector2.from_angle(angle) * randf_range(burst_radius_min, burst_radius_max)
	burst.y -= burst_up
	var chord: Vector2 = to - burst
	var side: float = 1.0 if randf() < 0.5 else -1.0
	var control: Vector2 = burst + chord * 0.5 + chord.orthogonal() * arc_bend * side
	var sec: float = maxf(fly_sec + randf_range(-fly_sec_jitter, fly_sec_jitter), pop_sec)
	coin.launch(from, value)
	coin.scale = Vector2.ONE * pop_from_scale
	var tween: Tween = coin.create_tween()
	tween.tween_property(coin, ^"global_position", burst, pop_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(coin, ^"scale", Vector2.ONE, pop_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(stagger_sec * float(index))
	tween.tween_method(_fly_step.bind(coin, burst, control, to), 0.0, 1.0, sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(coin, ^"scale", Vector2.ONE * land_scale, sec)
	tween.tween_callback(_land.bind(coin))


func _fly_step(t: float, coin: FlyingCoin, start: Vector2, control: Vector2, end: Vector2) -> void:
	coin.global_position = start.lerp(control, t).lerp(control.lerp(end, t), t)
	coin.spin(t)


func _land(coin: FlyingCoin) -> void:
	var value: int = coin.value
	coin.park()
	flying_count = maxi(flying_count - 1, 0)
	coin_landed.emit(value)
	if flying_count == 0:
		flight_finished.emit()
