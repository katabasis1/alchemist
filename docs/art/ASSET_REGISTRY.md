# ASSET_REGISTRY — контракт ассетов

Статусы: `probe` — только пробник стиля · `planned (S…)` — промпт готов, временная версия появится на указанном подэтапе · `temp` — временная графика агента · `final` — финальная (ChatGPT Image) · `proc` — процедурная: файл пишет скрипт (`tools/art/fx_textures.py`), промпт не нужен, правится код.
Правило: финальная картинка заменяет временную **под тем же именем и с тем же холстом**. Пути — от корня проекта Godot (`res://`).
Исходники пробников: `art_probes/style_A/source/`, вырезка: `art_probes/style_A/cutouts/` (в проект переносятся на S1.2).

| ID | Путь в проекте | Холст | Опора | Фон для вырезки | Статус | Промпт | Примечание |
|---|---|---|---|---|---|---|---|
| bg_workshop | assets/backgrounds/bg_workshop.png | 1920×1080 | top-left | — | temp | P-BG-01 | Край прилавка y≈760: из этого же файла вырезается слой `bg_workshop_bench` (y ≥ 760) поверх клиента |
| bg_workshop_bench | assets/backgrounds/bg_workshop_bench.png | 1920×324 | top-left, узел в (0, 756) | — | temp | P-BG-01 | Производный слой прилавка: `python tools/art/derive.py bench --top 756` из `bg_workshop`. Отдельно не генерировать; после финального фона проверить линию края |
| bg_workshop_portrait | assets/backgrounds/bg_workshop_portrait.png | 1080×1920 | top-left | — | temp | P-BG-02 | Портрет (телефон, GDD §10). Край прилавка y≈781: верх — клиент и заказ, прилавок — станции, ящики внизу — полка-лента |
| bg_workshop_portrait_bench | assets/backgrounds/bg_workshop_portrait_bench.png | 1080×1139 | top-left, узел в (0, 781) | — | temp | P-BG-02 | Производный слой: `python tools/art/derive.py bench --bg assets/backgrounds/bg_workshop_portrait.png --top 781 --out assets/backgrounds/bg_workshop_portrait_bench.png`. Отдельно не генерировать |
| prop_mortar_full | art_probes/style_A/cutouts/prop_mortar_full.png | 512×512 | bottom | #FF00FF | probe | — | Только пробник; в игре — две части ниже |
| prop_mortar_bowl | assets/props/prop_mortar_bowl.png | 512×512 | bottom | — | final | P-PROP-01 | Чаша; порошок — шейдер. Финальная от пользователя (S2.3a): `python tools/art/fit_final.py <png> assets/props/prop_mortar_bowl.png --canvas 512x512 --pivot bottom`. Горлышко на холсте: центр 252.5,114.5, полуоси 174.6×80.5 (в сцене — MOUTH_C/MOUTH_R, масштаб 0.7) |
| prop_pestle | assets/props/prop_pestle.png | 256×512 | center | — | final | P-PROP-02 | Пестик, головка внизу. Финальный от пользователя (S2.3a): `fit_final.py <png> assets/props/prop_pestle.png --canvas 256x512 --pivot center --upright`; кончик в сцене — offset (0,-248) |
| prop_mortar_bowl_front | assets/props/prop_mortar_bowl_front.png | 512×512 | bottom | — | final | P-PROP-01 | Производный слой финальной чаши: передний край по **нижней дуге горлышка** — всё, что ниже дуги, рисуется поверх содержимого (ингредиенты, порошок, головка пестика). `python tools/art/derive.py front assets/props/prop_mortar_bowl.png assets/props/prop_mortar_bowl_front.png --ellipse 252.5,114.5,174.6,80.5`. Отдельно не генерировать |
| fx_spark | assets/fx/fx_spark.png | 64×64 | center | — | proc | — | Искра-звёздочка: ядро + 4 луча. Белая, цвет — частица; смешивание «сложение» |
| fx_glow | assets/fx/fx_glow.png | 64×64 | center | — | proc | — | Мягкий ореол: светлячки над порошком, отсветы |
| fx_puff | assets/fx/fx_puff.png | 64×64 | center | — | proc | — | Облачко пыли (перетёр, бросок в чашу, «пфф» на ¼ круга по пыли) |
| fx_flakes | assets/fx/fx_flakes.png | 128×32 | center | — | proc | — | Обломки трав, 4 кадра 32×32 (`particles_anim_h_frames = 4`); заливка белая, цвет — смесь в ступке |
| prop_shelf_slot | assets/props/prop_shelf_slot.png | 256×192 | bottom | #FF00FF | temp | P-PROP-04 | Ячейка полки под один ингредиент; в сетке и в ленте одна и та же. В GDD §14 — «prop_shelf» |
| prop_flask_round | assets/props/prop_flask_round.png | 384×512 | bottom | #FF00FF (global) | temp | P-PROP-03 | Стекло прозрачное, жидкость — шейдер |
| prop_receiver_beaker | assets/props/prop_receiver_beaker.png | 320×384 | bottom | #FF00FF (global) | temp | P-PROP-06 | Приёмник Отстойника (S4.2). Стекло прозрачное, жидкость — шейдер liquid.gdshader со своей полостью (`receiver_liquid_material.tres`): после замены картинки сверить полость на макете. В GDD §14 — «prop_receiver_beaker»; колба-отстойник = `prop_flask_round` (отдельный `prop_settling_flask` не нужен) |
| prop_jar_ointment | assets/props/prop_jar_ointment.png | 256×256 | center | #FF00FF | temp | P-PROP-05 | Баночка мази: так выглядит зелье, отданное прямо из ступки (GDD §3.3). Летит к клиенту, на оценку не влияет |
| ing_fire_bloom | assets/ingredients/ing_fire_bloom.png | 256×256 | center | #FF00FF | temp | P-ING-01 |  |
| ing_moon_moss | assets/ingredients/ing_moon_moss.png | 256×256 | center | #FF00FF | temp | P-ING-02 |  |
| ing_golden_root | assets/ingredients/ing_golden_root.png | 256×256 | center | #FF00FF | temp | P-ING-03 |  |
| ing_sage_bundle | assets/ingredients/ing_sage_bundle.png | 256×256 | center | #FF00FF | temp | P-ING-04 |  |
| ing_drowse_herb | assets/ingredients/ing_drowse_herb.png | 256×256 | center | #FF00FF | planned (S4.2) | P-ING-05 | Цветы синие (не фиолетовые) — чтобы резать по #FF00FF при зелёных стеблях |
| ing_rust_lichen | assets/ingredients/ing_rust_lichen.png | 256×256 | center | #00FF00 | planned (S4.3) | P-ING-06 | Фиолетовые края — фон для вырезки зелёный |
| ing_frost_berry | assets/ingredients/ing_frost_berry.png | 256×256 | center | #FF00FF | planned (S4.3) | P-ING-07 |  |
| ing_glow_flower | assets/ingredients/ing_glow_flower.png | 256×256 | center | #FF00FF | planned (S4.3) | P-ING-08 | Свечение — шейдер |
| ing_ember_nut | assets/ingredients/ing_ember_nut.png | 256×256 | center | #FF00FF | planned (S4.3) | P-ING-09 | Тепловое мерцание трещин — шейдер |
| ing_sun_petal | assets/ingredients/ing_sun_petal.png | 256×256 | center | #FF00FF | planned (S6.1) | P-ING-10 |  |
| ing_snow_lotus | assets/ingredients/ing_snow_lotus.png | 256×256 | center | #FF00FF | planned (S6.1) | P-ING-11 |  |
| ing_star_crystal | assets/ingredients/ing_star_crystal.png | 256×256 | center | #FF00FF | planned (S6.1) | P-ING-12 | Свечение и искры — шейдер/частицы |
| client_baker_neutral | assets/characters/client_baker_neutral.png | 768×768 | bottom | #00FF00 | temp | P-CHR-01 | Фигура обрезана снизу. В `client.tscn` портрет опущен (`Portrait.offset.y = -344` при высоте 768): низ фигуры уходит за прилавок ≈26 px экрана — запас на скруглённые углы контура и дыхание. Новый портрет — проверить, что по бокам у прилавка не видно фона |
| client_baker_happy | assets/characters/client_baker_happy.png | 768×768 | bottom | #00FF00 | planned (S5.1) | P-CHR-02 | Приложить нейтральный портрет |
| client_baker_upset | assets/characters/client_baker_upset.png | 768×768 | bottom | #00FF00 | planned (S5.1) | P-CHR-03 | Приложить нейтральный портрет |
| ui_button_wood | assets/ui/ui_button_wood.png | по содержимому | — | #FF00FF | temp | P-UI-01 | Поля 9-slice задаются на S1.5 |
| ui_panel_parchment | assets/ui/ui_panel_parchment.png | по содержимому | — | #FF00FF | temp | P-UI-02 | Поля 9-slice задаются на S1.5 |
| icon_coin | assets/ui/icon_coin.png | 256×256 | center | #FF00FF | temp | P-UI-03 |  |
| icon_star | assets/ui/icon_star.png | 256×256 | center | #FF00FF | temp | P-UI-04 |  |
| ui_badge_round | assets/ui/ui_badge_round.png | 256×256 | center | #FF00FF | temp | P-UI-05 |  |
| ui_trash | assets/ui/ui_trash.png | 256×256 | center | #FF00FF | temp | P-UI-06 | Корзина «вылить» у станции (кнопка) |
| icon_prop_acid | assets/ui/icon_prop_acid.png | 128×128 | center | #FF00FF | temp | P-UI-07 | Пузырьки; заливка белая, цвет — `PropertyData.color` через modulate |
| icon_prop_heat | assets/ui/icon_prop_heat.png | 128×128 | center | #FF00FF | temp | P-UI-07 | Пламя; заливка белая, цвет — `PropertyData.color` через modulate |
| icon_prop_life | assets/ui/icon_prop_life.png | 128×128 | center | #FF00FF | temp | P-UI-07 | Лист; заливка белая, цвет — `PropertyData.color` через modulate |
| icon_prop_cold | assets/ui/icon_prop_cold.png | 128×128 | center | #FF00FF | temp | P-UI-07 | Снежинка; заливка белая, цвет — `PropertyData.color` через modulate |
| icon_prop_sleep | assets/ui/icon_prop_sleep.png | 128×128 | center | #FF00FF | temp | P-UI-07 | Полумесяц; заливка белая, цвет — `PropertyData.color` через modulate |
| icon_prop_light | assets/ui/icon_prop_light.png | 128×128 | center | #FF00FF | temp | P-UI-07 | Искра; заливка белая, цвет — `PropertyData.color` через modulate |
| ui_order_bubble | assets/ui/ui_order_bubble.png | 512×320 | center | #FF00FF | temp | P-UI-08 | Пузырь заказа, хвостик справа внизу (к клиенту). Внутри — фраза клиента и иконки (GDD §5.2). **Тянется как nine-patch** (NinePatchRect, масштаб 1): поля L75 T105 R112 B140 px — в углах только скругления, хвостик целиком в правом нижнем поле; середина и стороны — ровные, без рисунка, который заметно тянется. Временный: тело x 8–503, y 39–243, радиус углов ≈ 58, хвостик x 413–469, кончик (459, 280) → `Client.tail_tip` = (52, 40) от правого нижнего угла. Новый рисунок с другой формой — поправить поля в `client.tscn` и `tail_tip` |
| icon_purity | assets/ui/icon_purity.png | 128×128 | center | #FF00FF | temp | P-UI-09 | Кристалл чистоты: в пузыре заказа столько кристаллов, сколько звёзд чистоты требуется |
