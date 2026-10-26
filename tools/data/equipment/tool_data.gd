## ToolData — покупка в магазине: станция, прибор знания или улучшение (GDD §7).
## Сигналы: нет. Зависимости: нет. Отдельного UpgradeData нет — улучшения тоже здесь.
class_name ToolData
extends Resource

enum Kind { STATION, KNOWLEDGE, UPGRADE }

@export var id: StringName = &""
@export var kind: Kind = Kind.STATION
@export var price: int = 0
@export var unlock_rank: int = 1
@export var name_key: StringName = &""
@export var desc_key: StringName = &""
## Иконка в магазине. Появится вместе с магазином (S6).
@export var icon: Texture2D
