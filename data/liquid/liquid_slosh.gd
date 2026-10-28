## LiquidSlosh — раскачка поверхности жидкости (S4.1): настройки и чистые шаги, состояние хранит Liquid.
## Угол — наклон поверхности в мире, радианы, по часовой (> 0 — у левой стенки выше). Пружина запаздывания:
## разгон колбы вбок и поворот колбы отклоняют поверхность, она качается и успокаивается к горизонту.
## Методы не меняют ресурс: один .tres на все колбы.
## Эталон на Python — tools/alchemy/liquid_model.py (класс LiquidSlosh): правило меняется в обоих местах сразу.
## Сигналы: нет. Зависимости: нет.
class_name LiquidSlosh
extends Resource

## Жёсткость (1/с²) и затухание (1/с) пружины запаздывания.
@export var stiffness: float = 70.0
@export var damping: float = 5.0
## Наклон на каждый пиксель/с² ускорения колбы вбок.
@export var per_accel: float = 0.00012
## Насколько стенки тянут поверхность за собой при повороте колбы.
@export var rotation_drag: float = 0.35
## Предел наклона, радианы.
@export var max_angle: float = 0.5
## Волна от толчка: затухание (1/с) и частота (рад/с).
@export var bump_decay: float = 2.6
@export var bump_frequency: float = 9.0


## Наклон, к которому тянется поверхность при ускорении колбы вбок: разгон вправо — жидкость набегает на левую
## стенку (угол > 0), торможение — на правую. Не больше max_angle.
func target(accel_x: float) -> float:
	return clampf(accel_x * per_accel, -max_angle, max_angle)


## Шаг пружины за delta секунд: state = (угол, скорость угла), turn — поворот колбы за этот кадр, радианы.
## Стенки тянут жидкость за собой: поворот по часовой сначала наклоняет поверхность туда же. Толчок от поворота
## зависит от угла, а не от длины кадра, поэтому частота кадров на раскачку почти не влияет.
## В пределе скорость гасится: поверхность отскакивает, а не залипает у стенки.
func step(state: Vector2, target_angle: float, turn: float, delta: float) -> Vector2:
	var speed: float = state.y + turn * rotation_drag * stiffness
	speed += (-stiffness * (state.x - target_angle) - damping * speed) * delta
	var angle: float = state.x + speed * delta
	if absf(angle) >= max_angle:
		return Vector2(signf(angle) * max_angle, 0.0)
	return Vector2(angle, speed)


## Сколько пикселей останется от волны толчка px через delta секунд (экспонента: кадры роли не играют).
func fade(px: float, delta: float) -> float:
	return px * exp(-bump_decay * delta)
