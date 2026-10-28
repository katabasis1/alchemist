## LiquidLayers — что рисует шейдер жидкости (S4.1): смесь → слои колбы снизу вверх.
## Только расчёт: статические чистые функции, без узлов и без состояния (LiquidLayers.view(…)).
## Слой — одно свойство; порядок и толщины — AlchemyRules.layers / layer_heights (GDD §3.4), поэтому слоёв не больше,
## чем свойств: MAX_LAYERS, под этот размер сделаны массивы шейдера liquid.gdshader.
## Уровень полной колбы — сумма долей / capacity, не выше 1. Слив сверху на poured (доля столба, как в
## AlchemyRules.pour_top) срезает верх: нижние слои стоят на месте, целиком слитые слои пропадают.
## Результат view — словарь с ключами KEY_*:
##   KEY_COLORS   PackedColorArray   — цвет слоя (PropertyData.color);
##   KEY_PATTERNS PackedInt32Array   — узор слоя (PropertyData.Pattern);
##   KEY_TOPS     PackedFloat32Array — верх слоя в долях полной колбы, по возрастанию; последний — поверхность;
##   KEY_MIXED    Color              — цвет взболтанной смеси (муть при отстаивании): среднее по видимой толщине
##                                     слоёв, чтобы при расслаивании цвет не прыгал; пусто — прозрачный.
## Эталон на Python — tools/alchemy/liquid_model.py: правило меняется в обоих местах сразу.
## Сигналы: нет. Зависимости: AlchemyRules (слои и толщины), DataCatalog (свойство по id), EconomyConfig.
class_name LiquidLayers
extends RefCounted

## Один слой на свойство, свойств шесть (GDD §3.1). Размер массивов в liquid.gdshader — столько же.
const MAX_LAYERS: int = 6
const KEY_COLORS: StringName = &"colors"
const KEY_PATTERNS: StringName = &"patterns"
const KEY_TOPS: StringName = &"tops"
const KEY_MIXED: StringName = &"mixed"


## Уровень полной колбы: сумма долей / ёмкость, 0…1. Ёмкость не больше нуля — пусто.
static func level(mixture: Dictionary, capacity: float) -> float:
	if capacity <= 0.0:
		return 0.0
	return clampf(AlchemyRules.total(mixture) / capacity, 0.0, 1.0)


## Слои для шейдера после слива poured (доля столба) сверху: меньше 0 — как 0, от 1 — пусто.
## Слой тоньше AlchemyRules.EPSILON не рисуется.
static func view(mixture: Dictionary, poured: float, capacity: float, catalog: DataCatalog,
		economy: EconomyConfig) -> Dictionary:
	var ids: Array[StringName] = AlchemyRules.layers(mixture, catalog)
	var heights: Array[float] = AlchemyRules.layer_heights(mixture, catalog, economy)
	var full: float = level(mixture, capacity)
	var cut: float = 1.0 - poured
	var colors: PackedColorArray = PackedColorArray()
	var patterns: PackedInt32Array = PackedInt32Array()
	var tops: PackedFloat32Array = PackedFloat32Array()
	var mixed: Color = Color(0.0, 0.0, 0.0, 0.0)
	var bottom: float = 0.0
	for i: int in ids.size():
		var top: float = minf(bottom + heights[i], cut)
		if (top - bottom) * full <= AlchemyRules.EPSILON:
			break
		var data: PropertyData = catalog.property(ids[i])
		colors.append(data.color)
		patterns.append(data.pattern)
		tops.append(top * full)
		mixed += data.color * (top - bottom)
		bottom = top
	if bottom > 0.0:
		mixed /= bottom
	return {KEY_COLORS: colors, KEY_PATTERNS: patterns, KEY_TOPS: tops, KEY_MIXED: mixed}
