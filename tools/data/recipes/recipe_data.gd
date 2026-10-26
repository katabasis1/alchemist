## RecipeData — рецепт: набор значимых свойств готового зелья (GDD §3.5, §5.1).
## Сигналы: нет. Зависимости: property_set — PropertyData.id; hint_steps — IngredientData.id и STEP_*.
class_name RecipeData
extends Resource

## Шаги подсказки, кроме ингредиентов. Подсказка рисуется иконками, без текста (GDD §8).
const STEP_MORTAR: StringName = &"mortar"
const STEP_SETTLER_TOP: StringName = &"settler_top"
const STEP_SETTLER_BOTTOM: StringName = &"settler_bottom"
const STEP_BURNER_35_54: StringName = &"burner_35_54"
const STEP_BURNER_55_74: StringName = &"burner_55_74"
const STEP_BURNER_75_89: StringName = &"burner_75_89"
const STATION_STEPS: Array[StringName] = [
	STEP_MORTAR, STEP_SETTLER_TOP, STEP_SETTLER_BOTTOM,
	STEP_BURNER_35_54, STEP_BURNER_55_74, STEP_BURNER_75_89,
]

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var desc_key: StringName = &""
@export var property_set: Array[StringName] = []
## Ранг, с которого рецепт можно сварить открытыми ингредиентами («Ранг» в GDD §5.1).
@export var tier: int = 1
## Один из путей: ингредиенты, затем шаги станций, например
## [&"ing_fire_bloom", &"mortar", &"settler_top"] — «Огнецвет → Ступка → Отстойник: неси верх».
@export var hint_steps: Array[StringName] = []


## Рецепт совпадает, если набор значимых свойств зелья в точности равен property_set.
func matches(significant: Array[StringName]) -> bool:
	if significant.size() != property_set.size():
		return false
	for property_id: StringName in property_set:
		if not significant.has(property_id):
			return false
	return true
