## SceneRouter — смена экранов с затемнением; на время перехода блокирует ввод.
## Сигналы: transition_started(scene_path), transition_finished(scene_path); глобально — EventBus.scene_changed.
## Зависимости: EventBus; fade_rect (@export) — ColorRect на весь экран поверх игры.
extends CanvasLayer

signal transition_started(scene_path: String)
signal transition_finished(scene_path: String)

@export var fade_rect: ColorRect
## Длительность затемнения и проявления, секунды.
@export var fade_sec: float = 0.25

var is_busy: bool = false


func _ready() -> void:
	_set_overlay(false)
	fade_rect.modulate.a = 0.0


## Перейти на сцену по пути res://… Возвращает false, если переход не начался.
func go_to(scene_path: String) -> bool:
	if is_busy:
		return false
	if not ResourceLoader.exists(scene_path):
		push_error("SceneRouter: сцена не найдена: %s" % scene_path)
		return false
	is_busy = true
	transition_started.emit(scene_path)
	_set_overlay(true)
	await _fade_to(1.0)
	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: не удалось сменить сцену (%s)" % error_string(err))
	# Смена сцены отложенная: новая сцена появится в дереве к следующему кадру.
	await get_tree().process_frame
	if err == OK:
		EventBus.scene_changed.emit(scene_path)
	await _fade_to(0.0)
	_set_overlay(false)
	is_busy = false
	transition_finished.emit(scene_path)
	return err == OK


func _fade_to(alpha: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", alpha, fade_sec)
	await tween.finished


func _set_overlay(active: bool) -> void:
	fade_rect.visible = active
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
