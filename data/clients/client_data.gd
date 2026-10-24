## ClientData — посетитель лавки (GDD §6).
## Сигналы: нет. Зависимости: OrderTemplate.
class_name ClientData
extends Resource

enum Mood { NEUTRAL, HAPPY, UPSET }

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var portrait_neutral: Texture2D
## Пока портрета нет (planned в ASSET_REGISTRY) — показывается нейтральный.
@export var portrait_happy: Texture2D
@export var portrait_upset: Texture2D
@export var min_rank: int = 1
## Что клиент заказывает. Генератор берёт отсюда с учётом ранга, веса и решаемости.
@export var orders: Array[OrderTemplate] = []
## Множитель оплаты (королевский гонец ×2).
@export var pay_multiplier: float = 1.0
## Сколько раз за игровой день приходит; 0 — без ограничения.
@export var visits_per_day: int = 0


func portrait(mood: Mood) -> Texture2D:
	var texture: Texture2D = portrait_neutral
	match mood:
		Mood.HAPPY:
			texture = portrait_happy
		Mood.UPSET:
			texture = portrait_upset
	return texture if texture != null else portrait_neutral


func orders_for_rank(rank: int) -> Array[OrderTemplate]:
	var result: Array[OrderTemplate] = []
	for order: OrderTemplate in orders:
		if order.min_rank <= rank and order.weight > 0.0:
			result.append(order)
	return result
