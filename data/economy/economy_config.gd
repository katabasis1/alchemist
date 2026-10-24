## EconomyConfig — все пороги, скорости и множители игры (GDD §3, §5, §8, §12).
## Сигналы: нет. Зависимости: IngredientData.Hardness.
## Значения — стартовые (Numbers Policy): план проверки каждого — в GDD §12.
## Функции здесь только толкуют числа конфига; логики станций и заказов тут нет.
class_name EconomyConfig
extends Resource

@export_group("Смесь (GDD §3.2)")
## Свойство «есть», если его доли не меньше порога; иначе это след.
@export var significance_threshold: float = 0.0
## Доли для ★, ★★, ★★★ силы.
@export var strength_thresholds: Array[float] = []
## Чистота для ★, ★★, ★★★ (0…1).
@export var purity_thresholds: Array[float] = []

@export_group("Ступка (GDD §3.3)")
@export var mortar_slots: int = 0
@export var mortar_slots_upgraded: int = 0
## Прирост помола за полный круг по твёрдости.
@export var grind_soft: float = 0.0
@export var grind_medium: float = 0.0
@export var grind_hard: float = 0.0
## Альтернатива жесту для доступности: столько тапов = один круг.
@export var taps_per_circle: int = 0
## Зона «идеально»: извлечение 1,0.
@export var perfect_from: float = 0.0
@export var perfect_to: float = 0.0
## Извлечение при нулевом помоле.
@export var extraction_floor: float = 0.0
## Насколько быстро падает извлечение после зоны «идеально» (порошок пылит).
@export var overgrind_slope: float = 0.0

@export_group("Отстойник (GDD §3.3)")
@export var settle_time: float = 0.0
## Минимальная толщина слоя, доля высоты колбы.
@export var min_layer_height: float = 0.0
## Скорость слива, доля высоты в секунду: сначала медленно, после разгона — быстрее.
@export var pour_speed_start: float = 0.0
@export var pour_speed_full: float = 0.0
@export var pour_ramp_time: float = 0.0
## За сколько секунд струя прекращается после отпускания.
@export var pour_stop_time: float = 0.0

@export_group("Горелка (GDD §3.3)")
## Градусы в секунду.
@export var heat_rate: float = 0.0
@export var cool_rate: float = 0.0
@export var room_temp: float = 0.0
@export var max_temp: float = 0.0
## Доли в секунду: испарение летучих и сгорание Жизни.
@export var evaporate_rate: float = 0.0
@export var burn_rate: float = 0.0

@export_group("Оплата и репутация (GDD §5.3)")
## Множитель базы за 1★, 2★, 3★.
@export var pay_by_stars: Array[float] = []
@export var flawless_tip: float = 0.0
## Серия 3★: прибавка за каждый заказ серии и её потолок.
@export var streak_tip_step: float = 0.0
@export var streak_tip_max: float = 0.0
@export var flawless_reputation_bonus: int = 0
## База = flat + per_strength · n · S + per_purity · P (n — число свойств).
@export var base_pay_flat: int = 0
@export var base_pay_per_strength: int = 0
@export var base_pay_per_purity: int = 0

@export_group("День и награды (GDD §3.5, §8)")
@export var orders_per_day: int = 0
## Полноэкранная реклама — только начиная с этого игрового дня.
@export var interstitial_first_day: int = 0
@export var free_hints_per_day: int = 0
@export var merchant_gift_min_rank: int = 0
@export var merchant_gift_crystals: int = 0
## Столько «безупречных» варок делают страницу Гримуара золотой.
@export var golden_page_flawless: int = 0
@export var start_coins: int = 0


func is_significant(amount: float) -> bool:
	return amount >= significance_threshold


## 0…3 звезды силы для доли свойства.
func strength_stars(amount: float) -> int:
	return _stars(amount, strength_thresholds)


## 0…3 звезды чистоты (purity — 0…1).
func purity_stars(purity: float) -> int:
	return _stars(purity, purity_thresholds)


func max_stars() -> int:
	return strength_thresholds.size()


## Доля извлечения при помоле grind (0…1).
func extraction(grind: float) -> float:
	if grind < perfect_from:
		return extraction_floor + (1.0 - extraction_floor) * grind / perfect_from
	if grind <= perfect_to:
		return 1.0
	return 1.0 - overgrind_slope * (grind - perfect_to)


func grind_per_circle(hardness: IngredientData.Hardness) -> float:
	match hardness:
		IngredientData.Hardness.MEDIUM:
			return grind_medium
		IngredientData.Hardness.HARD:
			return grind_hard
	return grind_soft


func base_pay_for(property_count: int, strength_req: int, purity_req: int) -> int:
	return base_pay_flat + base_pay_per_strength * property_count * strength_req + base_pay_per_purity * purity_req


## Множитель базы за число звёзд оценки (0 — неверный эффект, оплаты нет).
func pay_factor(stars: int) -> float:
	if stars <= 0 or pay_by_stars.is_empty():
		return 0.0
	return pay_by_stars[mini(stars, pay_by_stars.size()) - 1]


## Чаевые: streak — сколько заказов подряд, включая этот, получили 3★.
func tip(flawless: bool, streak: int) -> float:
	var value: float = minf(streak_tip_step * streak, streak_tip_max)
	if flawless:
		value += flawless_tip
	return value


func payment(base_pay: int, stars: int, flawless: bool, streak: int, client_multiplier: float) -> int:
	return roundi(base_pay * pay_factor(stars) * (1.0 + tip(flawless, streak)) * client_multiplier)


func _stars(value: float, thresholds: Array[float]) -> int:
	var stars: int = 0
	for threshold: float in thresholds:
		if value >= threshold:
			stars += 1
	return stars
