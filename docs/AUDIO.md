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
| `audio/sfx/sfx_glug_1.ogg` … `_3.ogg` | 0,22 с | «Буль» струи Отстойника: ритм — `SettlerConfig.glug_sec_full` на полной скорости, реже при слабой струе; при удержании во время отстаивания — одиночный «буль» без слива (3 варианта, без повтора подряд) | `Settler` (SfxGlug) | temp |
| `audio/sfx/sfx_settle_bubble.ogg` | 1,1 с | Смесь отстаивается: бульканье, затихающее к концу (под `settle_time` 1,2 с) | `Settler` (SfxSettle) | temp |
| `audio/sfx/sfx_clean_cut.ogg` | 0,6 с | «Дзынь» чистого среза: примесь ≤ 5 %, вместе с искоркой на поверхности | `Settler` (SfxClean) ← `cut_made(…, clean = true)` | temp |
| `audio/sfx/sfx_flame_ignite.ogg` | 0,45 с | «Фух» розжига: нажали на горелку, огонь вспыхнул | `Burner` (SfxIgnite) | temp |
| `audio/sfx/sfx_flame_crackle_1.ogg` … `_3.ogg` | 0,18 с | Тихий треск огня, пока держат: раз в `BurnerConfig.crackle_sec` (0,55 с), 3 варианта, разброс высоты ±12 % | `Burner` (SfxCrackle) | temp |
| `audio/sfx/sfx_boil_1.ogg` … `_3.ogg` | 0,28 с | «Буль» кипения: 2–3 пузыря ниже «буль» струи, последний лопается; ритм `boil_glug_sec / кипение` — чем горячее, тем чаще | `Burner` (SfxBoil) | temp |
| `audio/sfx/sfx_whistle.ogg` | 0,85 с | Свист на пределе (100°): тон чайника ~2,1 кГц с дрожью, раз в `whistle_sec` (1,2 с), вместе с облачком из колпачка термометра | `Burner` (SfxWhistle) | temp |
| `audio/sfx/sfx_hiss.ogg` | 0,6 с | «Пш-ш» — горит Жизнь (≥ 90°): шипение с потрескиванием, раз в `smoke_shake_sec` (0,9 с), вместе с толчком камеры | `Burner` (SfxHiss) | temp |
| `audio/sfx/sfx_steam_pop.ogg` | 0,16 с | «Пок» — свойство ушло с паром целиком: иконка выскакивает из горла и лопается | `Burner` (SfxPop) ← `Vapor.pop` | temp |
| `audio/sfx/sfx_steam_done.ogg` | 0,7 с | «Готово» — всё летучее при этой температуре ушло, пар стих: две тёплые ноты вниз (соль — до) | `Burner` (SfxDone) | temp |

## Требования к финальным звукам

- Формат: OGG Vorbis, 44,1 кГц, моно для SFX. Пик как у временных (от −6 dBFS у «тука» до −9 dBFS у взятия), чтобы баланс шин не сбился.
- Без резких щелчков в начале и конце: короткие фейды.
- Лицензия: только собственные, CC0 или с явным разрешением на коммерческое использование. Каждое заимствование — строка
  в `docs/THIRD_PARTY.md`.
- Музыка (S6/S9): зацикливаемая, без вокала. По требованиям Яндекса звук ставится на паузу при сворачивании вкладки и во
  время рекламы (`docs/YANDEX_CHECKLIST.md`).

> Скрипт `tools/audio/synth_sfx.py` пропал с GitHub вместе с Pod и восстановлен в S2.3 (v0.1.3) только с рецептами звуков S2.3.
> Звуки S1 (`sfx_pickup`, `sfx_drop_wood_*`, `sfx_accept`, `sfx_reject`) лежат в репозитории и не перегенерируются.
