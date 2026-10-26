## BurstParticles — короткие выбросы частиц по событию (крошки помола, облачко пыли) без создания узлов в коде.
## Держит пул заранее собранных в сцене CPUParticles2D (one_shot, explosiveness ≈ 1) и перезапускает их по кругу:
## новый выброс не обрывает частицы прошлого, пока пул не исчерпан. CPUParticles2D, а не GPUParticles2D: веб-сборка
## на рендерере Compatibility (AGENTS.md). Частицы живут в координатах мира (local_coords = false), поэтому
## тряска и «подпрыгивание» станции их не дёргают.
## Сигналы: нет.
## Зависимости: emitters — CPUParticles2D-дети, настроенные в сцене эффекта (scenes/fx/fx_crumbs.tscn, fx_dust.tscn).
class_name BurstParticles
extends Node2D

## Пул излучателей. Чем чаще выбросы и дольше живут частицы, тем больше нужно излучателей.
@export var emitters: Array[CPUParticles2D] = []
@export var enabled: bool = true

## Сколько выбросов было с запуска (для проверочных сцен).
var bursts: int = 0

var _next: int = 0


## Выброс в точке мира. color умножается на цвет частиц (у крошек — цвет смеси в ступке).
func burst(global_pos: Vector2, color: Color = Color.WHITE) -> void:
	if not enabled or emitters.is_empty():
		return
	var emitter: CPUParticles2D = emitters[_next]
	_next = (_next + 1) % emitters.size()
	emitter.global_position = global_pos
	emitter.color = color
	emitter.restart()
	bursts += 1


## Погасить всё сразу (станцию опустошили, сцена уходит).
func clear() -> void:
	for emitter: CPUParticles2D in emitters:
		emitter.emitting = false
