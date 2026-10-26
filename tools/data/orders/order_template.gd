## OrderTemplate — шаблон заказа (GDD §5.2, §5.4).
## Сигналы: нет. Зависимости: required — PropertyData.id.
## Шаблоны живут в ClientData.orders (генератор берёт их у клиента) и в DataCatalog.ftue_orders.
class_name OrderTemplate
extends Resource

@export var id: StringName = &""
## Нужные свойства. Лишние значимые свойства эффект не портят, но снижают чистоту.
@export var required: Array[StringName] = []
## Звёзды силы: каждое нужное свойство не слабее порога EconomyConfig.strength_thresholds.
@export_range(1, 3) var strength_req: int = 1
## Звёзды чистоты: порог EconomyConfig.purity_thresholds.
@export_range(1, 3) var purity_req: int = 1
## База оплаты. У сгенерированных заказов = EconomyConfig.base_pay_for(); у FTUE — своя (GDD §9).
@export var base_pay: int = 0
@export var min_rank: int = 1
## Вес при выборе генератором; 0 — не выпадает.
@export var weight: float = 0.0
## Фраза клиента — для атмосферы, а не инструкция.
@export var line_key: StringName = &""
