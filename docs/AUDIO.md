# AUDIO — звуки и музыка

Шины: `Master` → `Music`, `SFX`, `UI` (`audio/default_bus_layout.tres`). Громкость шин берётся из настроек (GameState),
воспроизведение идёт через автозагрузку `AudioDirector` (пул плееров SFX с разбросом высоты, отдельный плеер UI).
Сущности играют звуки компонентом `SfxComponent` (см. `docs/COMPONENTS.md`).

## Временные звуки (MVP)

Синтезируются офлайн: `python tools/audio/synth_sfx.py` (numpy + scipy → ffmpeg, OGG Vorbis, моно 44,1 кГц; без `--force` создаёт только недостающие файлы). Генерация
детерминирована (seed), поэтому повторный запуск даёт те же файлы. Это собственная работа проекта, не заимствование, так что в
`docs/THIRD_PARTY.md` их нет. Финальный звук заменяет временный **под тем же именем**, сцены не правятся.

| Файл | Длина | Событие | Где подключён | Статус |
|---|---|---|---|---|
| `audio/sfx/sfx_pickup.ogg` | 0,14 с | Взяли предмет (короткий «тык» вверх) | `Draggable.drag_started` предмета | temp |
| `audio/sfx/sfx_drop_wood_1.ogg` … `_3.ogg` | 0,22 с | Предмет встал на дерево или вернулся на полку (3 варианта, без повтора подряд) | `Draggable.landed/returned` | temp |
| `audio/sfx/sfx_accept.ogg` | 0,32 с | Станция или клиент приняли предмет, тап по монете | `DropTarget.received`, кнопки-сущности | temp |
| `audio/sfx/sfx_reject.ogg` | 0,26 с | Отказ цели (занято, не тот предмет) | `DropTarget.rejected` | temp |
| `audio/sfx/sfx_grind_crunch_1.ogg` … `_5.ogg` | 0,14–0,16 с | Хруст помола на каждую ¼ круга: сухие щелчки + глухой удар пестика (5 вариантов, без повтора подряд, разброс высоты ±12 %) | `MortarJuice` ← `GrindGesture.quarter_passed` | temp |
| `audio/sfx/sfx_grind_dull_1.ogg`, `_2.ogg` | 0,16 с | p = 1: пестик трёт пыль — глухо, без щелчков | `MortarJuice` (вместо хруста) | temp |
| `audio/sfx/sfx_perfect.ogg` | 0,7 с | Помол вошёл в «идеально»: колокольчик из двух нот | `MortarJuice` ← `ZoneGauge.zone_changed` | temp |
| `audio/sfx/sfx_overgrind.ogg` | 0,42 с | Перетёр (вышли за «идеально»): «пфф», полоса уходит вниз | `MortarJuice` ← `ZoneGauge.zone_changed` | temp |
| `audio/sfx/sfx_whoosh.ogg` | 0,36 с | «Вжух»: клиент принял сосуд, тот летит к нему | `Client` (SfxReceive) | temp |
| `audio/sfx/sfx_happy.ogg` | 0,60 с | Клиент доволен (верный эффект) | `Client` (SfxHappy) | temp |
| `audio/sfx/sfx_oof.ogg` | 0,42 с | «Уф»: неверный эффект, клиент качает головой | `Client` (SfxUpset) | temp |
| `audio/sfx/sfx_coin_1…3.ogg` | 0,32 с | Монета долетела до счётчика (случайный из трёх) | `CoinCounter` | temp |

## Требования к финальным звукам

- Формат: OGG Vorbis, 44,1 кГц, моно для SFX. Пик как у временных (от −6 dBFS у «тука» до −9 dBFS у взятия), чтобы баланс шин не сбился.
- Без резких щелчков в начале и конце: короткие фейды.
- Лицензия: только собственные, CC0 или с явным разрешением на коммерческое использование. Каждое заимствование — строка
  в `docs/THIRD_PARTY.md`.
- Музыка (S6/S9): зацикливаемая, без вокала. По требованиям Яндекса звук ставится на паузу при сворачивании вкладки и во
  время рекламы (`docs/YANDEX_CHECKLIST.md`).

> Скрипт `tools/audio/synth_sfx.py` пропал с GitHub вместе с Pod и восстановлен в S2.3 (v0.1.3) только с рецептами звуков S2.3.
> Звуки S1 (`sfx_pickup`, `sfx_drop_wood_*`, `sfx_accept`, `sfx_reject`) лежат в репозитории и не перегенерируются.
