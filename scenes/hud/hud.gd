## Hud — интерфейс поверх лавки (GDD §10). Пока здесь только счётчик монет и полёт монет к нему; репутация, ранг,
## Гримуар, магазин и настройки появятся на S6–S8. Слой CanvasLayer: камера и её тряска HUD не двигают, якоря сами
## подстраиваются под ландшафт и портрет (в LayoutSwitcher HUD не добавляют).
## Сигналы: нет.
## Методы: fly_coins(from_world, amount) — монеты из точки мира в счётчик (вызывать после зачисления монет в GameState);
##   deny_coins() — «монет не хватает» (STATIONS §1.1).
## Зависимости: CoinCounter, CoinFlight (связаны здесь: coin_landed → CoinCounter.release).
class_name Hud
extends CanvasLayer

@export var counter: CoinCounter
@export var flight: CoinFlight


func _ready() -> void:
	flight.coin_landed.connect(counter.release)


## Монеты вылетают из точки мира (например, руки клиента) и летят в счётчик. Число растёт по мере прилёта.
func fly_coins(from_world: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var held: int = counter.hold(amount)
	if held <= 0:
		return
	flight.fly(world_to_hud(from_world), counter.coin_point(), held)


## Монет не хватает: счётчик вздрагивает.
func deny_coins() -> void:
	counter.deny()


## Точка мира → координаты слоя HUD (через камеру текущего вьюпорта).
func world_to_hud(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world
