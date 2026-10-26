## ParticleBurst — всплеск частиц в точке мира: крошки под пестиком, облачко пыли.
## Излучатели — готовые CPUParticles2D в сцене (one_shot, local_coords = false); всплески берут их по кругу,
## поэтому новый всплеск не обрывает частицы прошлого. Внешний вид (текстура, скорость, гравитация, затухание)
## задаётся в сцене эффекта (scenes/fx/*), цвет — при вызове: заменяет color излучателя, затухание color_ramp множится на него.
## CPUParticles2D, а не GPU: рендерер Compatibility и слабые телефоны.
## Сигналы: fired(world) — всплеск запущен (для проверочных сцен).
## Зависимости: нет.
class_name ParticleBurst
extends Node2D

signal fired(world: Vector2)

@export var emitters: Array[CPUParticles2D] = []
@export var enabled: bool = true

var _next: int = 0


## Всплеск в точке мира цветом color (белый — цвет из сцены как есть).
func burst(world: Vector2, color: Color = Color.WHITE) -> void:
	if not enabled or emitters.is_empty():
		return
	var emitter: CPUParticles2D = emitters[_next]
	_next = (_next + 1) % emitters.size()
	emitter.global_position = world
	emitter.color = color
	emitter.restart()
	emitter.emitting = true
	fired.emit(world)
