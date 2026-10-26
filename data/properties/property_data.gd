## PropertyData — одно из шести свойств смеси (GDD §3.1).
## Сигналы: нет. Зависимости: нет.
## id совпадает с ключами IngredientData.properties, RecipeData.property_set и OrderTemplate.required.
class_name PropertyData
extends Resource

## Узор слоя в колбе (рисует шейдер, S3): цвет никогда не работает в одиночку.
enum Pattern { BUBBLES, WAVES, LEAVES, SNOWFLAKES, MOONS, SPARKS }

## Значение evaporate_temp / burn_temp «никогда».
const NEVER: float = -1.0

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var color: Color = Color.WHITE
## Иконка свойства (белая заливка, цвет даёт color через modulate): ячейка полки, слой в колбе, пузырь заказа.
@export var icon: Texture2D
@export var pattern: Pattern = Pattern.BUBBLES
## Порядок плотности: 1 — самое тяжёлое (лежит на дне).
@export_range(1, 6) var density_rank: int = 1
## С этой температуры свойство уходит паром; NEVER — стойкое.
@export var evaporate_temp: float = NEVER
## С этой температуры свойство сгорает; NEVER — не горит.
@export var burn_temp: float = NEVER


func evaporates_at(temp: float) -> bool:
	return evaporate_temp >= 0.0 and temp >= evaporate_temp


func burns_at(temp: float) -> bool:
	return burn_temp >= 0.0 and temp >= burn_temp


## Стойкое: не уходит паром и не горит (Жар, Свет).
func is_stable() -> bool:
	return evaporate_temp < 0.0 and burn_temp < 0.0
