## ShelfSlot — ячейка полки: ящичек, ингредиент в нём и иконки его свойств (GDD §4, §10).
## Ячейка никогда не пустеет: как только станция приняла ингредиент, на его месте появляется новый (pop_in).
## Ингредиент, который станция отдала обратно, летит в свою ячейку и сливается с тем, что там лежит (take_back).
## Иконки свойств видны с самого начала (D15): по одной на свойство, от главного к второстепенному, цвет — PropertyData.color.
## На ленте (pass_horizontal) жест вбок по ингредиенту предмет не берёт — ячейка отдаёт его наверх, полка листает.
## Сигналы: item_taken(item) — ингредиент ушёл в станцию; gesture_passed / gesture_moved / gesture_ended(world_pos) —
##   жест вбок по ингредиенту (для прокрутки ленты).
## Зависимости: IngredientItem (item_scene), IngredientData, PropertyData; узлы — через @export.
class_name ShelfSlot
extends Node2D

signal item_taken(item: IngredientItem)
signal gesture_passed(world_pos: Vector2)
signal gesture_moved(world_pos: Vector2)
signal gesture_ended(world_pos: Vector2)

@export var item_scene: PackedScene
## Пока ингредиент летит обратно со станции, он рисуется над станциями.
@export var return_z_index: int = 40
@export_group("Узлы")
@export var items_root: Node2D
@export var item_anchor: Marker2D
## Иконки свойств слева направо; лишние прячутся.
@export var icons: Array[TextureRect] = []

var data: IngredientData
## Ингредиент, который сейчас лежит в ячейке (его и берут).
var item: IngredientItem
var pass_horizontal: bool = false
var _passing: bool = false


## Положить в ячейку ингредиент и показать его свойства (properties — PropertyData по убыванию доли).
func setup(value: IngredientData, properties: Array[PropertyData]) -> void:
	data = value
	for i: int in icons.size():
		var icon: TextureRect = icons[i]
		var has_icon: bool = i < properties.size() and properties[i] != null
		icon.visible = has_icon
		if has_icon:
			icon.texture = properties[i].icon
			icon.self_modulate = properties[i].color
	_spawn_item(false)


## Лента: жест вбок по ингредиенту листает полку, а не берёт предмет.
func set_pass_horizontal(value: bool) -> void:
	pass_horizontal = value
	if item != null:
		item.draggable.pass_horizontal = value


## Вернуть ячейку в покой после перестройки полки: брошенный перенос отменяется, предмет встаёт в ячейку.
func settle() -> void:
	if item == null:
		return
	if item.draggable.is_busy():
		item.draggable.cancel()
	item.draggable.place_at(item_anchor.global_position)


## Станция отдала ингредиент: он летит в ячейку и растворяется в том, что там лежит.
func take_back(returned: IngredientItem) -> void:
	if returned.get_parent() != items_root:
		returned.reparent(items_root)
	returned.scale = Vector2.ONE
	returned.set_in_station(false)
	returned.draggable.set_enabled(false)
	returned.hit_area.set_enabled(false)
	returned.z_index = return_z_index
	returned.draggable.landed.connect(_on_returned_landed.bind(returned), CONNECT_ONE_SHOT)
	returned.draggable.send_to(item_anchor.global_position)


func _spawn_item(animate: bool) -> void:
	if item_scene == null or data == null:
		push_warning("ShelfSlot %s: не задан item_scene или ингредиент" % get_path())
		return
	var spawned: IngredientItem = item_scene.instantiate() as IngredientItem
	spawned.data = data
	items_root.add_child(spawned)
	spawned.draggable.place_at(item_anchor.global_position)
	spawned.draggable.pass_horizontal = pass_horizontal
	spawned.draggable.dropped.connect(_on_item_dropped)
	spawned.draggable.press_passed.connect(_on_press_passed)
	spawned.hit_area.pointer_moved.connect(_on_pointer_moved)
	spawned.hit_area.pointer_up.connect(_on_pointer_up)
	spawned.hit_area.pointer_cancelled.connect(_on_pointer_cancelled)
	item = spawned
	if animate:
		spawned.pop_in()


func _release_item(taken: IngredientItem) -> void:
	taken.draggable.dropped.disconnect(_on_item_dropped)
	taken.draggable.press_passed.disconnect(_on_press_passed)
	taken.hit_area.pointer_moved.disconnect(_on_pointer_moved)
	taken.hit_area.pointer_up.disconnect(_on_pointer_up)
	taken.hit_area.pointer_cancelled.disconnect(_on_pointer_cancelled)


func _on_item_dropped(_target: DropTarget) -> void:
	var taken: IngredientItem = item
	if taken == null:
		return
	_release_item(taken)
	item = null
	_passing = false
	_spawn_item(true)
	item_taken.emit(taken)


func _on_returned_landed(returned: IngredientItem) -> void:
	returned.queue_free()
	if item != null:
		item.pop_in()


func _on_press_passed(world: Vector2) -> void:
	_passing = true
	gesture_passed.emit(world)


func _on_pointer_moved(world: Vector2) -> void:
	if _passing:
		gesture_moved.emit(world)


func _on_pointer_up(world: Vector2, _inside: bool) -> void:
	if _passing:
		_passing = false
		gesture_ended.emit(world)


func _on_pointer_cancelled() -> void:
	if _passing:
		_passing = false
		gesture_ended.emit(item_anchor.global_position)
