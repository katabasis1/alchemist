## DemoItem — предмет для проверочной сцены компонентов: раздаёт своим компонентам картинку, вид и ключ подсказки,
## чтобы одна сцена demo_item.tscn служила и ингредиентом, и колбой.
## Сборка (образец для будущих ингредиентов): Lift (приподнимает Draggable) → Squash (SquashStretch, опора
## у основания) → Sprite (Hoverable — только цвет, Flash — шейдер), рядом HitArea, Shadow, звуки, Tooltip.
## Сигналы: нет.
## Зависимости: Sprite2D, Draggable, Tooltip, Flash (@export).
class_name DemoItem
extends Node2D

@export var texture: Texture2D
@export var sprite_scale: float = 0.55
@export var kind: StringName = &"ingredient"
@export var on_accept: Draggable.AcceptMode = Draggable.AcceptMode.SNAP
@export var tip_key: StringName = &""
@export_group("Узлы")
@export var sprite: Sprite2D
@export var draggable: Draggable
@export var tooltip: Tooltip
## Красная вспышка предмета при отказе цели (вызывает владелец сцены).
@export var reject_flash: Flash


func _ready() -> void:
	if texture != null:
		sprite.texture = texture
	sprite.scale = Vector2.ONE * sprite_scale
	draggable.kind = kind
	draggable.on_accept = on_accept
	tooltip.set_text_key(tip_key)
