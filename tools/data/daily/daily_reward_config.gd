## DailyRewardConfig — цепочка ежедневных наград, 7 дней (GDD §8).
## Сигналы: нет. Зависимости: IngredientData (кристалл).
## День цепочки идёт по реальным суткам; пропуск не обнуляет цепочку, она просто ждёт.
class_name DailyRewardConfig
extends Resource

## Монеты по дням цепочки; длина = числу дней.
@export var coins: Array[int] = []
## Кристаллы по дням цепочки; та же длина, что у coins.
@export var crystals: Array[int] = []
## Что выдаётся как «кристалл».
@export var crystal_item: IngredientData
## После последнего дня цепочка начинается заново (иначе повторяется последний день).
@export var restart_after_last: bool = false


func days() -> int:
	return coins.size()


## День цепочки (с 0) для порядкового номера полученной награды (с 0).
func day_index(claim_number: int) -> int:
	var count: int = days()
	if count == 0:
		return 0
	if restart_after_last:
		return claim_number % count
	return mini(claim_number, count - 1)


func coins_for(claim_number: int) -> int:
	return coins[day_index(claim_number)] if days() > 0 else 0


func crystals_for(claim_number: int) -> int:
	var i: int = day_index(claim_number)
	return crystals[i] if i < crystals.size() else 0
