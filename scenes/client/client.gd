## Client — клиент у прилавка (GDD §5–6): приходит, показывает заказ в пузыре, принимает баночку, реагирует, уходит.
## Пузырь — только иконки (GDD §5.2): каждое нужное свойство столько раз, сколько звёзд силы требуется (цвет свойства —
## modulate белой иконки), ниже кристаллы чистоты по числу её звёзд. Фраза клиента — строкой под пузырём, гаснет сама.
## Баночку оценивает OrderJudge в момент приёма. Верный эффект: радость, served(verdict) — оплату и монеты делает
## владелец (OrderDesk), клиент сам уходит через react_sec. Неверный: качает головой, «уф», зелье пропадает,
## refused(verdict), клиент ждёт дальше — можно переделать (GDD §5.3).
## StateMachine: Away → Arriving → Waiting → Reacting → Waiting (неверный эффект) / Leaving → Away.
## Методы: arrive(client, order), leave(), is_present(), is_waiting(), refusal_for(vessel), coin_point().
## Сигналы: arrived; served(verdict); refused(verdict); left; drop_refused(reason) — баночку не взял:
##   &"busy" — сейчас не ждёт заказ, &"kind" — пустой сосуд, &"grind" — FTUE 1–3, помол не дошёл до «идеально».
## Зависимости: OrderJudge, DropTarget (kind &"potion"), CarryVessel (смесь, помол), StateMachine, JuicePunch,
##   SfxComponent ×3, DataCatalog (свойства), EconomyConfig через OrderJudge (зона «идеально»), order_icon.tscn,
##   EventBus (поворот экрана: пузырь слева или справа от клиента).
class_name Client
extends Node2D

signal arrived
signal served(verdict: Dictionary)
signal refused(verdict: Dictionary)
signal left
signal drop_refused(reason: StringName)

const STATE_AWAY: StringName = &"Away"
const STATE_ARRIVING: StringName = &"Arriving"
const STATE_WAITING: StringName = &"Waiting"
const STATE_REACTING: StringName = &"Reacting"
const STATE_LEAVING: StringName = &"Leaving"
const REASON_BUSY: StringName = &"busy"
const REASON_KIND: StringName = &"kind"
const REASON_GRIND: StringName = &"grind"
## Помол сравнивается с началом зоны «идеально» с этим допуском.
const EPSILON: float = 0.0001

@export var catalog: DataCatalog
## Иконка в пузыре (TextureRect): свойство или кристалл чистоты.
@export var icon_scene: PackedScene
@export var purity_icon: Texture2D
@export_group("Движение и реакция")
## Откуда приходит и куда уходит (смещение тела от места у прилавка).
@export var walk_offset: Vector2 = Vector2(360.0, 0.0)
@export var walk_sec: float = 0.55
## Пауза между приёмом баночки и реакцией: баночка успевает долететь.
@export var react_delay_sec: float = 0.25
## Сколько длится реакция до ухода (верный эффект) или до нового ожидания (неверный).
@export var react_sec: float = 1.2
@export var happy_punch: float = 0.8
@export var bubble_pop_sec: float = 0.2
## Фраза под пузырём видна столько секунд, потом гаснет.
@export var line_sec: float = 4.5
@export var line_fade_sec: float = 0.4
@export_group("Пузырь")
@export var icon_size_max: float = 64.0
@export var icon_size_min: float = 36.0
## Ширина строки иконок в пузыре (локально): иконки ужимаются, чтобы влезть.
@export var row_width: float = 330.0
## Где пузырь в ландшафте и в портрете (в портрете клиент слева — пузырь справа, хвостик отражён).
@export var bubble_landscape: Vector2 = Vector2(-400.0, -540.0)
@export var bubble_portrait: Vector2 = Vector2(400.0, -540.0)
@export_group("Узлы")
@export var state_machine: StateMachine
@export var judge: OrderJudge
@export var drop_target: DropTarget
## Двигается при приходе и уходе (портрет, пузырь, цель броска — внутри).
@export var body: Node2D
@export var portrait: Sprite2D
@export var bubble: Node2D
@export var bubble_sprite: Sprite2D
@export var property_row: HBoxContainer
@export var purity_row: HBoxContainer
@export var line_label: Label
@export var punch: JuicePunch
@export var sfx_receive: SfxComponent
@export var sfx_happy: SfxComponent
@export var sfx_upset: SfxComponent
## Отсюда вылетают монеты оплаты (рука клиента).
@export var coin_from: Node2D

var data: ClientData
var order: OrderTemplate
var _walk: Tween
var _line: Tween
var _bubble_tween: Tween


func _ready() -> void:
	drop_target.drop_attempted.connect(_on_drop_attempted)
	drop_target.received.connect(_on_received)
	EventBus.layout_changed.connect(_on_layout_changed)
	body.visible = false
	drop_target.enabled = false
	bubble.visible = false
	line_label.visible = false


## Клиент подходит к прилавку с заказом.
func arrive(client: ClientData, new_order: OrderTemplate) -> void:
	data = client
	order = new_order
	_set_portrait(data.portrait_neutral if data != null else null)
	_fill_bubble()
	state_machine.transition_to(STATE_ARRIVING, true)
	body.visible = true
	body.position = walk_offset
	body.modulate.a = 0.0
	_walk = _restart(_walk)
	_walk.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_walk.tween_property(body, ^"position", Vector2.ZERO, walk_sec)
	_walk.parallel().tween_property(body, ^"modulate:a", 1.0, walk_sec)
	_walk.tween_callback(_on_arrived)


## Клиент уходит (сам — после верного зелья; владелец — при смене дня, сбросе).
func leave() -> void:
	if state_machine.is_in(STATE_AWAY) or state_machine.is_in(STATE_LEAVING):
		return
	state_machine.transition_to(STATE_LEAVING, true)
	drop_target.enabled = false
	_show_bubble(false)
	_hide_line()
	_walk = _restart(_walk)
	_walk.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_walk.tween_property(body, ^"position", walk_offset, walk_sec)
	_walk.parallel().tween_property(body, ^"modulate:a", 0.0, walk_sec)
	_walk.tween_callback(_on_left)


## Точка мира, откуда летят монеты оплаты.
func coin_point() -> Vector2:
	return coin_from.global_position


## У прилавка кто-то есть (идёт, ждёт, реагирует или уходит).
func is_present() -> bool:
	return not state_machine.is_in(STATE_AWAY)


func is_waiting() -> bool:
	return state_machine.is_in(STATE_WAITING)


## Можно ли отдать этот сосуд: ждёт заказ, сосуд не пуст, в FTUE 1–3 помол дошёл до «идеально».
func refusal_for(vessel: CarryVessel) -> StringName:
	if not is_waiting() or order == null:
		return REASON_BUSY
	if vessel == null or not vessel.is_filled():
		return REASON_KIND
	if order.needs_perfect_grind and vessel.grind + EPSILON < judge.economy.perfect_from:
		return REASON_GRIND
	return &""


func _on_arrived() -> void:
	state_machine.transition_to(STATE_WAITING)
	drop_target.enabled = true
	_show_bubble(true)
	_show_line()
	arrived.emit()


func _on_left() -> void:
	body.visible = false
	state_machine.transition_to(STATE_AWAY)
	data = null
	order = null
	left.emit()


func _on_drop_attempted(draggable: Draggable) -> void:
	var reason: StringName = refusal_for(draggable.body as CarryVessel)
	if reason != &"":
		drop_target.reject(reason)
		punch.wiggle(0.5)
		drop_refused.emit(reason)


func _on_received(draggable: Draggable) -> void:
	# Смесь читаем сейчас: станция опустошит сосуд, как только узнает, что его приняли.
	var vessel: CarryVessel = draggable.body as CarryVessel
	var verdict: Dictionary = judge.judge(order, vessel.mixture)
	state_machine.transition_to(STATE_REACTING)
	drop_target.enabled = false
	sfx_receive.play()
	get_tree().create_timer(react_delay_sec).timeout.connect(_react.bind(verdict))


func _react(verdict: Dictionary) -> void:
	if not state_machine.is_in(STATE_REACTING):
		return
	_hide_line()
	if bool(verdict[OrderJudge.KEY_EFFECT]):
		_set_portrait(data.portrait_happy if data != null and data.portrait_happy != null else null)
		_show_bubble(false)
		punch.punch(happy_punch)
		sfx_happy.play()
		served.emit(verdict)
		get_tree().create_timer(react_sec).timeout.connect(_leave_after_react)
	else:
		_set_portrait(data.portrait_upset if data != null and data.portrait_upset != null else null)
		punch.wiggle()
		sfx_upset.play()
		refused.emit(verdict)
		get_tree().create_timer(react_sec).timeout.connect(_wait_again)


## Радость показана — уходим. Если за это время клиента уже увели (сброс игры), таймер ничего не делает.
func _leave_after_react() -> void:
	if state_machine.is_in(STATE_REACTING):
		leave()


## Неверный эффект пережит: клиент снова ждёт тот же заказ.
func _wait_again() -> void:
	if not state_machine.is_in(STATE_REACTING):
		return
	_set_portrait(data.portrait_neutral if data != null else null)
	state_machine.transition_to(STATE_WAITING)
	drop_target.enabled = true


## Пустая текстура — оставить текущую (у клиента пока только нейтральный портрет).
func _set_portrait(texture: Texture2D) -> void:
	if texture != null:
		portrait.texture = texture


func _fill_bubble() -> void:
	_clear(property_row)
	_clear(purity_row)
	if order == null:
		return
	var count: int = order.required.size() * order.strength_req
	var side: float = clampf(row_width / maxf(count, 1.0), icon_size_min, icon_size_max)
	for property_id: StringName in order.required:
		var property: PropertyData = catalog.property(property_id) if catalog != null else null
		for i: int in order.strength_req:
			_add_icon(property_row, property.icon if property != null else null,
					property.color if property != null else Color.WHITE, side)
	for i: int in order.purity_req:
		_add_icon(purity_row, purity_icon, Color.WHITE, icon_size_max)


func _add_icon(row: HBoxContainer, texture: Texture2D, tint: Color, side: float) -> void:
	var icon: TextureRect = icon_scene.instantiate() as TextureRect
	icon.texture = texture
	icon.self_modulate = tint
	icon.custom_minimum_size = Vector2(side, side)
	row.add_child(icon)


func _clear(row: Node) -> void:
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()


func _show_bubble(on: bool) -> void:
	_bubble_tween = _restart(_bubble_tween)
	if on:
		bubble.visible = true
		bubble.scale = Vector2.ZERO
		_bubble_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_bubble_tween.tween_property(bubble, ^"scale", Vector2.ONE, bubble_pop_sec)
	elif bubble.visible:
		_bubble_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		_bubble_tween.tween_property(bubble, ^"scale", Vector2.ZERO, bubble_pop_sec)
		_bubble_tween.tween_callback(bubble.hide)


func _show_line() -> void:
	if order == null or order.line_key == &"":
		return
	line_label.text = tr(order.line_key)
	line_label.visible = true
	line_label.modulate.a = 1.0
	_line = _restart(_line)
	_line.tween_interval(line_sec)
	_line.tween_property(line_label, ^"modulate:a", 0.0, line_fade_sec)
	_line.tween_callback(line_label.hide)


func _hide_line() -> void:
	if _line != null and _line.is_valid():
		_line.kill()
	line_label.visible = false


func _on_layout_changed(is_portrait: bool) -> void:
	bubble.position = bubble_portrait if is_portrait else bubble_landscape
	bubble_sprite.flip_h = is_portrait


func _restart(tween: Tween) -> Tween:
	if tween != null and tween.is_valid():
		tween.kill()
	return create_tween()
