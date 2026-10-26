## IngredientData — ингредиент на полке (GDD §4).
## Сигналы: нет. Зависимости: ключи properties — PropertyData.id.
class_name IngredientData
extends Resource

## Твёрдость задаёт прирост помола за круг (EconomyConfig.grind_per_circle).
enum Hardness { SOFT, MEDIUM, HARD }

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var texture: Texture2D
## Свойства в долях, например {&"life": 2.0}.
@export var properties: Dictionary[StringName, float] = {}
## Цвет крошек и порошка в ступке (S2.3). Подобран по картинке: медиана непрозрачных пикселей.
@export var crumb_color: Color = Color(0.6, 0.5, 0.35, 1.0)
@export var hardness: Hardness = Hardness.SOFT
## Цена за штуку: списывается, когда ингредиент брошен в ступку. 0 — бесплатно.
@export var cost_per_use: int = 0
## С какого ранга ингредиент появляется в магазине (или сразу на полке, если unlock_price = 0).
@export var unlock_rank: int = 1
## Цена открытия; 0 — открывается сам с рангом.
@export var unlock_price: int = 0
## Редкий: вместо монет можно взять за рекламу или кристаллом из наград (GDD §4, §8).
@export var is_rare: bool = false


func amount(property_id: StringName) -> float:
	return properties.get(property_id, 0.0)


func total() -> float:
	var sum: float = 0.0
	for value: float in properties.values():
		sum += value
	return sum
