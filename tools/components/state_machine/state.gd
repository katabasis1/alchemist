## State — одно состояние для StateMachine. Своей логики нет: владелец (станция) слушает сигналы
## entered/exited/updated, а правила переходов и автопереход по таймеру задаются в инспекторе.
## Имя состояния = имя узла (Empty, Loaded, Grinding… — как в docs/gdd/STATIONS.md).
## Сигналы: entered(from), exited(to), updated(delta).
## Зависимости: родитель — StateMachine.
class_name State
extends Node

signal entered(from: StringName)
signal exited(to: StringName)
signal updated(delta: float)

## Куда можно перейти из этого состояния (имена узлов). Пусто — куда угодно.
@export var next_states: Array[StringName] = []
## > 0 — через столько секунд в состоянии машина сама перейдёт в timeout_to (Settling 1,2 с → Ready).
@export var timeout_sec: float = 0.0
@export var timeout_to: StringName = &""


func can_go_to(state_name: StringName) -> bool:
	return next_states.is_empty() or next_states.has(state_name)
