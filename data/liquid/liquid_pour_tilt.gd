## LiquidPourTilt — наклон колбы при сливе (S4.2, решение D22): от уровня жидкости, а не постоянный угол.
## Колба наклоняется ровно так, чтобы видимая внутренняя кромка горла (lip) ушла под поверхность на dip:
## тогда у горла всегда цвет того слоя, что льётся, а по мере слива колба клонится дальше, как в жизни.
## liquid.gdshader держит высоты слоёв над центром шара по мировой вертикали (up = (sin a, −cos a),
## a = −θ), поэтому высота кромки над центром = −lx·sinθ − ly·cosθ и угол считается формулой:
##   θ = acos((поверхность − bulb_radius − dip) / |lip − bulb_center|) − atan2(lx, −ly),
##   dip = clamp(dip_layer_share · толщина верхнего слоя, dip_min_px, dip_px).
## Метод не меняет ресурс: один .tres на форму колбы. Состояние (слои) хранит Liquid.
## Эталон на Python — tools/alchemy/liquid_model.py (класс LiquidPourTilt): правило меняется в обоих местах сразу.
## Сигналы: нет. Зависимости: нет.
class_name LiquidPourTilt
extends Resource

## Видимая внутренняя кромка горла со стороны слива, px холста текстуры колбы. Полость шейдера может быть шире
## (neck_half_width), но жидкость под непрозрачным стеклом не видна — считаем от чистого стекла.
@export var lip: Vector2 = Vector2(213.0, 60.0)
## На сколько кромка уходит под поверхность, px холста: столько жидкости видно у горла из-под венчика…
@export var dip_px: float = 15.0
## …но не глубже этой доли верхнего слоя: у кромки не показывается следующий слой.
@export var dip_layer_share: float = 0.7
## Меньше этого не опускаем: даже у тонкого остатка струя должна откуда-то браться.
@export var dip_min_px: float = 2.0


## Наклон колбы, радианы (по часовой, > 0 — горло вправо). tops — верх слоёв в долях полной колбы снизу вверх
## (LiquidLayers.view), остальное — форма колбы из материала жидкости (px холста).
func angle(tops: PackedFloat32Array, column_height: float, bulb_center: Vector2, bulb_radius: float) -> float:
	var count: int = tops.size()
	var surface: float = tops[count - 1] * column_height if count > 0 else 0.0
	var below: float = tops[count - 2] * column_height if count > 1 else 0.0
	var dip: float = minf(dip_px, maxf(dip_min_px, (surface - below) * dip_layer_share))
	var arm: Vector2 = lip - bulb_center
	var height: float = surface - bulb_radius - dip
	return acos(clampf(height / arm.length(), -1.0, 1.0)) - atan2(arm.x, -arm.y)
