## EventBus — только глобальные события, которые слушают несвязанные системы (AGENTS.md §3, п. 4).
## Локальные связи — сигналами компонентов и ссылками через @export, не через шину.
## Сигналы: save_requested, coins_changed, settings_changed, pause_changed, scene_changed, game_ready,
## drag_started, drag_ended, camera_shake_requested, layout_changed.
## Зависимости: нет. Сам ничего не испускает — только объявляет сигналы.
extends Node

## Состояние игрока изменилось, его нужно записать (GDD §11). reason — для журнала: &"purchase", &"order", &"settings"…
@warning_ignore("unused_signal")
signal save_requested(reason: StringName)

## Монеты изменились: новое значение и разница.
@warning_ignore("unused_signal")
signal coins_changed(total: int, delta: int)

## Изменились настройки (громкость, язык, звук вкл/выкл).
@warning_ignore("unused_signal")
signal settings_changed

## Игра встала на паузу (реклама, потеря фокуса) или снова идёт.
@warning_ignore("unused_signal")
signal pause_changed(paused: bool)

## Сменился экран (после SceneRouter.go_to).
@warning_ignore("unused_signal")
signal scene_changed(scene_path: String)

## Загрузка завершена, сохранение применено, можно играть.
@warning_ignore("unused_signal")
signal game_ready

## Игрок взял предмет (перетаскивание или выбор тапом): цели подсвечиваются (компонент DropTarget).
@warning_ignore("unused_signal")
signal drag_started(draggable: Node)

## Предмет отпущен, принят или вернулся на место: подсветку целей снять.
@warning_ignore("unused_signal")
signal drag_ended(draggable: Node)

## Встряхнуть камеру. strength — 0…1 (компонент CameraShake; учитывает настройку «тряска»).
@warning_ignore("unused_signal")
signal camera_shake_requested(strength: float)

## Сменилась раскладка экрана: портрет (телефон) или ландшафт (компонент LayoutSwitcher).
@warning_ignore("unused_signal")
signal layout_changed(portrait: bool)
