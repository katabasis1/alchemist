## Receiver — Приёмник Отстойника (S4.2, STATIONS §1.2): стакан под струёй, Empty ⇄ Filled.
## Содержимое задаёт станция целиком (set_contents: что было + что слилось с последнего «вылить»), Приёмник его
## показывает, под струёй мутнеет и качается (splash) и выливается своей корзиной. Унести его — S4.4.
## Удержание на Приёмнике ничего не делает: своей области касания у него нет, только корзина.
## Сигналы: poured_out — игрок вылил содержимое (станция начинает счёт Приёмника заново).
## Зависимости: Liquid, StateMachine, StationTrash, JuicePunch (@export), AlchemyRules.
class_name Receiver
extends Node2D

signal poured_out

const STATE_EMPTY: StringName = &"Empty"
const STATE_FILLED: StringName = &"Filled"

@export var liquid: Liquid
@export var state_machine: StateMachine
@export var trash: StationTrash
@export var punch: JuicePunch

## Что в Приёмнике: id свойства → доли (GDD §3.2). Пусто — Приёмник пуст.
var mixture: Dictionary[StringName, float] = {}


func _ready() -> void:
	assert(liquid != null and state_machine != null and trash != null and punch != null,
			"Receiver: не заданы узлы сцены")
	trash.pressed.connect(pour_out)
	liquid.show_mixture(mixture)
	trash.set_active(false)


## Содержимое целиком; пустой словарь — Приёмник пуст.
func set_contents(new_mixture: Dictionary) -> void:
	mixture = AlchemyRules.cleaned(new_mixture)
	liquid.show_mixture(mixture)
	trash.set_active(not mixture.is_empty())
	var target: StringName = STATE_EMPTY if mixture.is_empty() else STATE_FILLED
	if not state_machine.is_in(target):
		state_machine.transition_to(target)


## Струя ударила в поверхность: смесь мутнеет (и отстоится сама, когда струя стихнет) и качается.
func splash(bump_px: float) -> void:
	liquid.stir()
	liquid.bump(bump_px)


## Точка поверхности в мире, куда бьёт струя; у пустого Приёмника — дно.
func surface_point() -> Vector2:
	return liquid.surface_point()


func is_empty() -> bool:
	return mixture.is_empty()


## Вылить всё (корзина Приёмника, проверки).
func pour_out() -> void:
	if mixture.is_empty():
		return
	set_contents({})
	punch.punch()
	poured_out.emit()
