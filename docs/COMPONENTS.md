# COMPONENTS — каталог компонентов и рецепты сборки

Сущность = сцена из узлов-компонентов (AGENTS.md §3, п. 1–5). Здесь собрано, какие компоненты есть, кто чем владеет
и как из них собирать предметы, станции и экраны. Живой пример всего ниже: `scenes/debug/components_demo.tscn` (F6).
Числа в таблицах — стартовые значения (Numbers Policy, GDD §12). Менять их нужно в инспекторе, а не в коде.

## 1. Главное правило: одно свойство узла — один владелец

Анимации разных компонентов не должны спорить за одно и то же свойство одного узла. Поэтому сущность делится на вложенные
узлы-«слои», и у каждого свойства каждого слоя ровно один хозяин:

| Свойство узла | Кто может владеть | Кому нельзя его отдавать одновременно |
|---|---|---|
| `position` корня сущности | Draggable (перенос, полёт домой) или LayoutSwitcher (раскладка) | Draggable берёт новую «домашнюю» точку при следующем взятии в покое, так что их можно совмещать |
| `position`, `scale` слоя Lift | Draggable (`lift_node`: подъём при взятии) | JuicePunch, SquashStretch, Hoverable |
| `scale` слоя | **один** из: SquashStretch, JuicePunch.punch, Hoverable (`hover_scale ≠ 1`), LayoutSwitcher (`copy_scale`) | все остальные из этого списка |
| `rotation` слоя | JuicePunch.wiggle | — |
| `modulate` | Hoverable, Flash (режим MODULATE), DropTarget (на узле `highlight`), Draggable (на узле `shadow`) | два из них на одном узле: Flash и Hoverable вычисляют цвет от «базы», запомненной в `_ready` |
| параметр шейдера `flash` | Flash (режим SHADER) | — |

Типичная лесенка предмета: `Корень (Draggable двигает) → Lift (подъём) → Squash (SquashStretch, опора у основания) → Sprite (Hoverable — только цвет, Flash — шейдер)`.

## 2. Каталог

| Компонент | Сцена | Узел | Назначение | Сигналы | Методы для владельца |
|---|---|---|---|---|---|
| HitArea | `components/hit_area/hit_area.tscn` | Control | Зона касания: нажатие, тап, долгое нажатие, наведение. Прямоугольник или круг (`radius`). Не меньше 96 px (GDD §12) | `pointer_down/moved/up`, `pointer_cancelled`, `tapped`, `long_pressed`, `hover_changed` | `cancel()`, `contains_world_point()` |
| Hoverable | `components/hoverable/hoverable.tscn` | Node | Подсветка при наведении мышью (на телефоне молчит) | `hover_started`, `hover_ended` | — |
| Draggable | `components/draggable/draggable.tscn` | Node | Перенос и запасной режим «тап по предмету → тап по цели». Подъём, тень, полёт домой | `drag_started`, `drag_moved`, `dropped`, `drop_rejected`, `landed`, `returned`, `selected_changed` | `select()`, `deselect()`, `cancel()`, `place_at()` — мгновенно, `send_to()` — плавно |
| DropTarget | `components/drop_target/drop_target.tscn` | Control | Цель для переноса: фильтр по `kind`, приоритет, подсветка, точка установки, вето станции | `drop_attempted`, `received`, `rejected(reason)`, `highlight_changed` | `reject(reason)` (только внутри `drop_attempted`), `find_at()` (static) |
| StateMachine + State | `components/state_machine/*.tscn` | Node | Состояния станции/клиента: разрешённые переходы, таймер выхода, очередь перехода из обработчика | `state_changed`, `transition_refused`; у State: `entered`, `exited`, `updated` | `start()`, `transition_to(name, force)`, `is_in()` |
| JuicePunch | `components/juice_punch/juice_punch.tscn` | Node | Пульс масштабом («да!») и покачивание («нет») | `finished` | `punch(strength)`, `wiggle(strength)` |
| SquashStretch | `components/squash_stretch/squash_stretch.tscn` | Node | Сжатие и вытягивание с пружиной, площадь сохраняется | — | `squash()`, `stretch()`, `hold(value)`, `release()` |
| CameraShake | `components/camera_shake/camera_shake.tscn` | Node | Тряска камеры по «травме» (шум, затухание). Выключается настройкой | — | `add_trauma()`, `stop()`; глобально — `EventBus.camera_shake_requested` |
| Flash | `components/flash/flash.tscn` | Node | Вспышка цветом: шейдер `flash_material.tres` (сохраняет силуэт) или `modulate`. Подходит любой шейдер с `flash_color`/`flash_amount` (у ингредиента — `ingredient.gdshader`: вспышка + распад) | — | `flash(strength)` |
| SfxComponent | `components/sfx_component/sfx_component.tscn` | Node | Звук события: варианты без повтора подряд, разброс высоты (`pitch_jitter` узла, иначе общий AudioDirector), защита от «пулемёта» | — | `play()`, `play_index()` |
| BurstParticles | `components/burst_particles/burst_particles.tscn` | Node2D | Выброс частиц в точке мира по кругу из нескольких CPUParticles2D (`local_coords = false`): частые выбросы не обрывают друг друга. Готовые: `scenes/fx/fx_crumbs.tscn` (крошки), `fx_dust.tscn` (облако пыли) | — | `burst(global_pos, color)`, `bursts` (счётчик для проверок) |
| Tooltip | `components/tooltip/tooltip.tscn` | PanelContainer | Подсказка: наведение 0,4 с на ПК, долгое нажатие на телефоне. Текст — ключ локализации | — | `set_text_key()`, `show_tip()`, `hide_tip()` |
| GrindGesture | `components/grind_gesture/grind_gesture.tscn` | Node | Жест помола над HitArea: длина пути пальца → круги (`circle_length_px` = круг), и круги, и свайпы. Конец — отпустили, ушёл дальше `leave_factor`·`zone_radius`, `cancel()`. Потолок `max_circles_per_sec`, скачок дальше `max_step_px` не считается. Тап = 1/`taps_per_circle` круга, не чаще `max_taps_per_sec` | `started`, `turned(circles)`, `quarter_passed`, `ended(reason)` | `tap_turn()`, `cancel()`, `distance_in_radii()` |
| ZoneGauge | `components/zone_gauge/zone_gauge.tscn` | ColorRect | Вертикальная шкала 0…1 с зоной «идеально» (шейдер, без картинок). Цвет ниже/в/выше зоны + обводка зоны и риска значения. Тряска вбок — `shake()` (во время тряски позицией шкалы владеет она сама) | `zone_changed(zone)` | `set_value(v, instant)`, `set_zone()`, `zone_of()`, `show_gauge(on)`, `set_zone_pulse()`, `shake(strength)`, `is_shaking()` |
| LayoutSwitcher | `components/layout_switcher/layout_switcher.tscn` | Node | Портрет/ландшафт (GDD §10): ведущий меняет базовое разрешение окна, остальные переставляют узлы по меткам | `layout_applied(portrait)`; глобально — `EventBus.layout_changed` | `apply()`, `wants_portrait()` |

### 2.1 Сущности игры на этих компонентах (S2)

| Сущность | Сцена | Из чего собрана | Сигналы | Методы |
|---|---|---|---|---|
| Подсветка цели | `components/drop_target/drop_glow.tscn` | ColorRect + шейдер `drop_glow.gdshader`: мягкий пульсирующий овал. Яркость задаёт DropTarget через `modulate` узла `highlight` | — | — |
| Ингредиент | `scenes/ingredient/ingredient_item.tscn` | HitArea (круг) + Draggable (`kind = ingredient`) + Tooltip (название) + SquashStretch + Flash + Sfx. На полке крупнее, в станции мельче. Шейдер спрайта `ingredient.gdshader` (local to scene): вспышка Flash + распад при помоле; вне станции распад сбрасывается | — | `data`, `set_in_station(on)`, `pop_in()`, `set_crumble(amount, color)`, `get_crumble()` |
| Ячейка полки | `scenes/shelf/shelf_slot.tscn` | Ящичек, ингредиент, до трёх иконок свойств. Взяли ингредиент — сразу появляется такой же; вернули — летит в ячейку и сливается | `item_taken`, `gesture_passed/moved/ended` (жест вбок — ленте) | `setup()`, `take_back()`, `settle()` |
| Полка | `scenes/shelf/shelf.tscn` | Ячейки по `GameState.unlocked_ingredients` (или `ingredient_ids`). Ландшафт — сетка, портрет — лента внизу: листается пальцем, жестом вбок по ингредиенту, колесом, катится по инерции | `ingredient_taken` | `set_ribbon()`, `take_back(item)`, `slot_for()`, `scroll_to()` |
| Корзина станции | `scenes/stations/station_trash.tscn` | HitArea + JuicePunch + Sfx; у пустой станции приглушена | `pressed` | `set_active()` |
| Ступка | `scenes/stations/mortar/mortar.tscn` | DropTarget + подсветка + StateMachine (Empty → Loaded → Grinding ⇄ Ground) + GrindArea (HitArea над чашей и пестиком) + GrindGesture + ZoneGauge (слева над корзиной) + пестик + корзина + огоньки мест + JuicePunch + Sfx. Ингредиенты и пестик лежат между чашей и её передним краем; тело чаши (BodyArea) — ручка баночки: VesselDrag (Draggable `kind = potion`, body — Vessel) | `item_released`, `contents_changed`, `drop_refused(reason)` (`full`, `coins`, `kind`, `ground`), `grind_changed(grind)`, `handed_off(mixture)` | `release()`, `empty_to_shelf()`, `discard()`, `refresh_capacity()`, `is_full()`, `is_ground()`, `ids()`, `ingredients()`, `hardest()`, `extraction()`, `mixture()`, `add_circles()` (помол, извлечение, смесь — через `AlchemyRules`), `set_grind()`, `hand_off()` |
| Отклик ступки (S2.3) | `scenes/stations/mortar/mortar_juice.gd` (узел `Juice` в `mortar.tscn`) | Только картинка, звук, вибрация — на помол не влияет. ¼ круга: крошки цвета смеси из-под пестика (BurstParticles), хруст ×5 с разбросом высоты, SquashStretch пестика (цель — `Visual/Pestle/Sprite`, опора — кончик), `Platform.vibrate`; при p = 1 — пыль и глухой звук. Помол: распад ингредиентов (`IngredientItem.set_crumble`, к `perfect_from` — целиком) и горка порошка (`Visual/Powder`, `powder.gdshader`), за `perfect_to` порошок сереет. Вход в «идеально» — FxRing по краю чаши + звон; перетёр — облако пыли, «пфф», `ZoneGauge.shake`, вибрация длиннее. Ингредиент лёг в чашу — бледное облачко | — | `crumble_for(p)`, `dust_for(p)`, `mix_color()`, `mixture_color` |
| Кольцо света | `scenes/fx/fx_ring.tscn` (`fx_ring.gd`, `fx_ring.gdshader`) | ColorRect: расходящийся овал во весь прямоугольник («идеально»; позже — звёзды, открытия) | — | `play(color)`, `plays` |
| Пестик | `scenes/stations/mortar/pestle.gd` (узел в ступке) | Node2D, начало — кончик. Во время помола кончик ходит по маленькому эллипсу у центра чаши, ручка наклоняется к пальцу; тап — тычок; после — ложится как был | — | `follow(world)`, `poke(world)`, `rest()` |
| Баночка мази (S2.4) | `scenes/vessel/carry_vessel.tscn` | Узел `Vessel` в ступке: спрайт + Lift (подъём) + тень. Взяли (тянуть за тело чаши или тап по чаше) — показывается со смесью и помолом ступки; долетела до клиента или вернулась — прячется пустой в чашу | — | `fill(mixture, grind)`, `is_filled()`, `show_up()`, `stow()`, `mixture`, `grind` |
| Правила алхимии (S3.1) | `data/alchemy/alchemy_rules.gd` (`class_name AlchemyRules`, не узел) | Только статические чистые функции, без состояния: смесь — словарь «свойство → доля» (`total`, `combine`, `scaled`, `cleaned`, `significant`, `traces`, сила и чистота со звёздами); помол (`hardest`, `grind_per_circle`, `grind_after`, `extraction`, `ground`); отстаивание (`layers` по плотности, `layer_heights` с минимумом 10 %, `pour_top` → `{top, bottom}` по всей слитой высоте, `height_above_layer`, `pour_height`/`pour_tail` за удержание); нагрев (`temp_after`, `time_at_or_above` — точное время не ниже точки внутри шага, `heat`, `steaming`, `burning`). Станции и OrderJudge только хранят состояние и зовут эти функции. Python-копия строка в строку — `tools/alchemy/rules_model.py` (`--self-test`): правишь правило — правь оба файла. В Godot те же случаи проверяет стенд `scenes/debug/rules_check.tscn` (S3.3; пути игрока — `scenes/debug/rule_paths.gd`, копия `run_path` эталона) | — | статические, вызов `AlchemyRules.ground(items, grind, economy)` |
| Рецепты и Гримуар (S3.2) | `data/alchemy/grimoire_rules.gd` (`class_name GrimoireRules`, не узел) | Только статические чистые функции: `recognize(mixture, catalog)` — рецепт по значимым свойствам (null — «Странная смесь»); `brew(mixture, recipe, economy)` — сила, чистота, «безупречно» по рецепту; страница — словарь из четырёх целых `KEY_*` (варок, лучшая сила, лучшая чистота, «безупречных»): `after_brew(page, result)` (вход не меняет), `is_golden(page, economy)`; сохранение — `parse_page`, `parse_grimoire` (JSON, мусор, старый формат; идемпотентно). Пишет в Гримуар только `GameState.record_brew`. Python-копия — `tools/alchemy/grimoire_model.py` (`--self-test`) | — | статические, вызов `GrimoireRules.recognize(mixture, catalog)` |
| Оценка заказа (S2.4) | `scenes/client/order_judge.gd` (узел `OrderJudge` в клиенте) | Только расчёт по `EconomyConfig` через `AlchemyRules` (S3.1): эффект — все нужные свойства значимы; сила — самое слабое нужное; чистота — доли нужных / доли всех; «безупречно» — сила и чистота ★★★. Вердикт — словарь `KEY_*` | — | `judge(order, mixture)`, `pay_for(order, verdict, streak, multiplier)`, `reputation_for(verdict)` |
| Клиент (S2.4) | `scenes/client/client.tscn` (в лавке — `Room/ClientSpot/Client`) | Портрет (дышит — шейдер Breathe) + пузырь заказа: NinePatchRect растёт под содержимое, кончик хвостика — начало узла Bubble, в портретной раскладке фон зеркальный; внутри фраза клиента, ряды иконок (свойство × звёзды силы, кристаллы чистоты; `order_icon.tscn`) + DropTarget (`potion`) + OrderJudge + StateMachine Away → Arriving → Waiting → Reacting → Leaving + JuicePunch + Sfx (принял / рад / расстроен). Обучающий заказ с `needs_perfect_grind` не берёт крупный помол | `arrived`, `potion_received(mixture)` (баночку взял — копия смеси, до вердикта), `served(verdict)`, `refused(verdict)`, `left`, `drop_refused(reason)` (`kind`, `grind`, `busy`) | `arrive(data, order)`, `leave()`, `is_present()`, `is_waiting()`, `refusal_for(vessel)`, `coin_point()` |
| Дыхание (S2.4a) | `components/breathe/breathe.gdshader` (материал на спрайте) | Только шейдер, без скрипта: на вдохе всё выше `shoulder_y` поднимается на `lift_px` целиком (лицо не искажается), торс до `base_y` плавно тянется и на `widen` шире; вдох короче выдоха, после выдоха пауза. Узел не двигает — трансформ свободен для JuicePunch и твинов. Параметры — в материале сцены (`client.tscn`), `phase` — чтобы соседи не дышали в такт | — | — |
| Очередь заказов (S2.4) | `scenes/client/order_desk.tscn` | Без картинки. Кто придёт: незакрытый заказ из сохранения → обучающие (`ftue_clients`, до `ftue_limit`) → заказы `free_client` его ранга, по весу, решаемые открытыми ингредиентами. Клиент взял баночку (верную или нет) — `GameState.record_brew` (страница Гримуара, S3.2). Верное зелье — оплата и репутация одной записью (`GameState.finish_order`), монеты летят из руки клиента (`Hud.fly_coins`). Ушёл — через `next_delay_sec` следующий. Старт — `EventBus.game_ready` или сразу, если сохранение уже загружено | `order_started(client, order)`, `order_paid(order, verdict, pay)` | `start()`, `pick()`, `started`, `served_count` |
| HUD (S2.4) | `scenes/hud/hud.tscn` (CanvasLayer 10) | CoinCounter (иконка + число, прокрутка цифр, дрожь и красный при «монет не хватает») + CoinFlight (пул FlyingCoin: веер, дуга Безье, шлейф CPUParticles2D, поворот ребром). Число в счётчике растёт по мере прилёта монет (`hold`/`release`) | CoinCounter: `rolled(shown)`; CoinFlight: `coin_landed(value)`, `flight_finished` | Hud: `fly_coins(from_world, amount)`, `deny_coins()`, `world_to_hud()`; CoinCounter: `reset()`, `hold()`, `release()`, `deny()`, `target_shown()`; CoinFlight: `fly(from, to, amount)`, `sprites_for(amount)` |
| Лавка (S2.4) | `scenes/workshop/workshop.tscn` + фон `workshop_room.tscn` | Room (фон, прилавок, ClientSpot) + Mortar + Shelf + OrderDesk + Hud + LayoutSwitcher. Связи сцены: `Mortar.item_released` → `Shelf.take_back`, отказ ступки `coins` → `Hud.deny_coins`. Фон `workshop_room.tscn` берут и проверочные сцены | — | — |

Станция отдаёт ингредиент сигналом `item_released`, полка ловит его в `take_back` (связь — в сцене, где они встречаются). Узел, который сейчас обрабатывает своё касание, переносить к другому родителю кадром позже (`call_deferred`).

## 3. Рецепты

### 3.1 Предмет, который носят (ингредиент, зелье)
Образец — `scenes/debug/demo_item.tscn`.
1. Корень `Node2D` → `Shadow` (эллипс, `modulate.a = 0`) → `Lift` → `Squash` (в точке опоры) → `Sprite` (материал вспышки).
2. `HitArea` 140×140 по центру. `Draggable`: `hit_area`, `body = ..`, `lift_node = Lift`, `shadow = Shadow`, `kind`.
3. `Hoverable` на `Sprite` с `hover_scale = 1`, потому что масштабом `Squash` уже владеет `SquashStretch`.
4. Отклик (не меньше двух каналов): `drag_started → SfxPickup.play + SquashStretch.stretch`,
   `landed/returned → SfxDrop.play + SquashStretch.squash`. Отказ озвучивает **цель**, а не предмет:
   `drop_rejected(null)` значит «бросили мимо всех целей», и там хватает мягкого возврата.
5. `Tooltip` с `hit_area` и ключом названия.

### 3.2 Станция-приёмник (ступка, котёл)
Образец — узел `Mortar` в `components_demo.tscn`, логика в `components_demo.gd`.
1. `DropTarget` с `accepted_kinds`, `highlight` (узел подсветки, скрыт), `snap_point`.
2. `StateMachine` с состояниями; `next_states` задают, куда можно перейти, а `timeout_sec/timeout_to` — выход по таймеру.
3. В `drop_attempted`: если станция занята, вызвать `reject(DropTarget.REASON_BUSY)`. Если о занятости известно заранее,
   лучше выключить цель (`enabled = false`): тогда она даже не подсвечивается.
4. `received` → перевести машину, отклик (`JuicePunch.punch`, `Flash`, звук, `EventBus.camera_shake_requested`).
   `rejected` → `JuicePunch.wiggle`, красная вспышка, звук отказа.
5. Вернуть предмет на полку — `Draggable.send_to(точка)`. Точку полки запомнить в `drop_attempted`: пока предмет
   не встал на станцию, его `home_position` — ещё место на полке.

### 3.3 Кнопка-сущность с откликом (монета, колокольчик)
`HitArea` (можно круглую, `radius`) → `tapped` → `JuicePunch.punch` + `Flash` (MODULATE) + `SfxComponent` (`ui_bus = true`).
Наведение — `Hoverable` на отдельном слое `Hover`, если пульс уже занял масштаб `Sprite`.

### 3.4 Экран с двумя раскладками
1. Один ведущий `LayoutSwitcher` (`drive_window = true`) на всю игру — сейчас в `scenes/main/main.tscn`. Он же двигает камеру.
2. В экране — свой `LayoutSwitcher` (ведомый): `landscape_only/portrait_only` (фоны), `movers` и пары меток
   `landscape_marks/portrait_marks` (`Marker2D`). Метки лежат в узле `LayoutMarks`.
3. Масштабом mover при `copy_scale = true` владеет раскладка, и JuicePunch на этот же узел вешать нельзя.

## 4. Подводные камни

- **Материал вспышки в одной сцене общий.** `flash_material.tres` помечен «local to scene», то есть копируется на каждый
  экземпляр сцены. Но два спрайта со вспышкой внутри **одной** сцены получат один материал и будут вспыхивать вместе.
  Второму дайте Flash в режиме MODULATE, свой `ShaderMaterial` как sub_resource или вынесите его в отдельную сцену.
- **Базы запоминаются в `_ready`.** JuicePunch, SquashStretch, Hoverable и Flash запоминают исходный масштаб/цвет при
  старте. Если владелец меняет их позже (раскладка, смена картинки), трогайте другой слой.
- **Пауза (реклама).** HitArea и Draggable отменяют перенос по `NOTIFICATION_PAUSED`; предмет долетает домой после паузы.
- **Ведущий LayoutSwitcher и камера живут в `Main`.** `SceneRouter.go_to()` заменяет текущую сцену целиком, поэтому
  переход на другой экран через роутер оставит игру без камеры и ведущего. Пока экран один (лавка), это не мешает.
  Решить, когда появится второй экран (S7): либо SceneRouter меняет содержимое слота внутри `Main`, либо ведущий
  переезжает в автозагрузку. Записано в `docs/PROGRESS.md`, «Известный долг».
- **`drag_started/drag_ended` в EventBus** — общие для переноса и выбора тапом. DropTarget гасит подсветку только по
  `drag_ended` того предмета, который сейчас несут.
