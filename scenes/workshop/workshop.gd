## Workshop — экран лавки (GDD §10): комната (фон, прилавок, место клиента), полка, ступка, клиент, очередь заказов, HUD.
## Здесь связи между соседями: ступка вернула ингредиент → полка; «монет не хватает» у ступки → счётчик HUD вздрагивает.
## Раскладка: полку и ступку двигает свой LayoutSwitcher, клиента — LayoutSwitcher комнаты (клиент стоит за прилавком:
## он дочерний узел Room/ClientSpot, прилавок рисуется поверх), HUD подстраивается якорями. Окно переключает Main.
## Сигналы: нет. Методы: нет.
## Зависимости: Shelf, Mortar, Hud (OrderDesk и Client связаны в сцене через @export).
class_name Workshop
extends Node2D

@export var shelf: Shelf
@export var mortar: Mortar
@export var hud: Hud


func _ready() -> void:
	mortar.item_released.connect(shelf.take_back)
	mortar.drop_refused.connect(_on_mortar_drop_refused)


func _on_mortar_drop_refused(reason: StringName) -> void:
	if reason == Mortar.REASON_COINS:
		hud.deny_coins()
