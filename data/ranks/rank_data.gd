## RankData — ранг лавки по репутации (GDD §7).
## Сигналы: нет. Зависимости: нет.
## Что открывает ранг, не хранится здесь, а выводится из unlock_rank / min_rank
## (DataCatalog.unlocks_for_rank): один источник правды, без расхождений.
class_name RankData
extends Resource

@export var index: int = 1
@export var name_key: StringName = &""
## Репутация, с которой ранг достигнут.
@export var threshold: int = 0
