## OrderJudge — оценка зелья по заказу (GDD §5.3): ★ эффект — все нужные свойства есть; ★ сила — каждое нужное
## не слабее требования; ★ чистота — не ниже требования. Сила и чистота засчитываются только при верном эффекте.
## «Безупречно» — сила ★★★ по всем нужным свойствам и чистота ★★★ (≥ 95 %). Чистота — доли нужных / доли всех (§3.2).
## Первая версия (S2.4): зелье несут прямо из ступки. S5.3 добавит репутацию в разбор, Гримуар и экран итога.
## Сигналы: нет. Методы: judge(order, mixture) → словарь-вердикт (ключи KEY_*); pay_for(order, verdict, streak, multiplier);
##   reputation_for(verdict) — звёзды + бонус за «безупречно» (GDD §5.3, репутацию не отнимаем).
## Зависимости: EconomyConfig (порог значимости, звёзды силы и чистоты, оплата), OrderTemplate.
class_name OrderJudge
extends Node

const KEY_EFFECT: StringName = &"effect"
const KEY_STRENGTH_OK: StringName = &"strength_ok"
const KEY_PURITY_OK: StringName = &"purity_ok"
## Звёзды силы самого слабого из нужных свойств (0…3).
const KEY_STRENGTH_STARS: StringName = &"strength_stars"
const KEY_PURITY: StringName = &"purity"
const KEY_PURITY_STARS: StringName = &"purity_stars"
## Итог: 0 — неверный эффект, 1…3 — звёзды оценки.
const KEY_STARS: StringName = &"stars"
const KEY_FLAWLESS: StringName = &"flawless"
## Нужные свойства, которых в зелье нет (только следы или совсем нет).
const KEY_MISSING: StringName = &"missing"
## Сравнение с порогами: 4 доли из 5 — ровно 80 %, а не 79,999…
const EPSILON: float = 0.0001

@export var economy: EconomyConfig


func judge(order: OrderTemplate, mixture: Dictionary) -> Dictionary:
	var missing: Array[StringName] = []
	var weakest: int = economy.max_stars()
	var wanted: float = 0.0
	var total: float = 0.0
	for property_id: StringName in mixture:
		total += float(mixture[property_id])
	for property_id: StringName in order.required:
		var amount: float = float(mixture.get(property_id, 0.0))
		wanted += amount
		if not economy.is_significant(amount + EPSILON):
			missing.append(property_id)
		weakest = mini(weakest, economy.strength_stars(amount + EPSILON))
	var purity: float = wanted / total if total > 0.0 else 0.0
	var purity_stars: int = economy.purity_stars(purity + EPSILON)
	var effect: bool = missing.is_empty() and not order.required.is_empty()
	var strength_ok: bool = effect and weakest >= order.strength_req
	var purity_ok: bool = effect and purity_stars >= order.purity_req
	var stars: int = 0
	if effect:
		stars = 1 + int(strength_ok) + int(purity_ok)
	var top: int = economy.max_stars()
	return {
		KEY_EFFECT: effect,
		KEY_STRENGTH_OK: strength_ok,
		KEY_PURITY_OK: purity_ok,
		KEY_STRENGTH_STARS: weakest if effect else 0,
		KEY_PURITY: purity,
		KEY_PURITY_STARS: purity_stars,
		KEY_STARS: stars,
		KEY_FLAWLESS: effect and weakest >= top and purity_stars >= top,
		KEY_MISSING: missing,
	}


## Оплата по вердикту. streak — заказов подряд с 3★, включая этот (EconomyConfig.tip).
func pay_for(order: OrderTemplate, verdict: Dictionary, streak: int, multiplier: float) -> int:
	return economy.payment(order.base_pay, int(verdict[KEY_STARS]), bool(verdict[KEY_FLAWLESS]), streak, multiplier)


## Репутация за заказ: число звёзд + бонус за «безупречно». Неверный эффект — 0.
func reputation_for(verdict: Dictionary) -> int:
	var gain: int = int(verdict[KEY_STARS])
	if bool(verdict[KEY_FLAWLESS]):
		gain += economy.flawless_reputation_bonus
	return gain
