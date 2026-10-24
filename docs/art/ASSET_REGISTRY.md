# ASSET_REGISTRY — контракт ассетов

Статусы: `probe` — только пробник стиля · `planned (S…)` — промпт готов, временная версия появится на указанном подэтапе · `temp` — временная графика агента · `final` — финальная (ChatGPT Image).
Правило: финальная картинка заменяет временную **под тем же именем и с тем же холстом**. Пути — от корня проекта Godot (`res://`).
Исходники пробников: `art_probes/style_A/source/`, вырезка: `art_probes/style_A/cutouts/` (в проект переносятся на S1.2).

| ID | Путь в проекте | Холст | Опора | Фон для вырезки | Статус | Промпт | Примечание |
|---|---|---|---|---|---|---|---|
| bg_workshop | assets/backgrounds/bg_workshop.png | 1920×1080 | top-left | — | temp | P-BG-01 | Край прилавка y≈760: из этого же файла вырезается слой `bg_workshop_bench` (y ≥ 760) поверх клиента |
| bg_workshop_bench | assets/backgrounds/bg_workshop_bench.png | 1920×324 | top-left, узел в (0, 756) | — | temp | P-BG-01 | Производный слой прилавка: `python tools/art/derive.py bench --top 756` из `bg_workshop`. Отдельно не генерировать; после финального фона проверить линию края |
| bg_workshop_portrait | assets/backgrounds/bg_workshop_portrait.png | 1080×1920 | top-left | — | temp | P-BG-02 | Портрет (телефон, GDD §10). Край прилавка y≈781: верх — клиент и заказ, прилавок — станции, ящики внизу — полка-лента |
| bg_workshop_portrait_bench | assets/backgrounds/bg_workshop_portrait_bench.png | 1080×1139 | top-left, узел в (0, 781) | — | temp | P-BG-02 | Производный слой: `python tools/art/derive.py bench --bg assets/backgrounds/bg_workshop_portrait.png --top 781 --out assets/backgrounds/bg_workshop_portrait_bench.png`. Отдельно не генерировать |
| prop_mortar_full | art_probes/style_A/cutouts/prop_mortar_full.png | 512×512 | bottom | #FF00FF | probe | — | Только пробник; в игре — две части ниже |
| prop_mortar_bowl | assets/props/prop_mortar_bowl.png | 512×512 | bottom | #FF00FF | planned (S2.2) | P-PROP-01 | Чаша; порошок — шейдер |
| prop_pestle | assets/props/prop_pestle.png | 256×512 | center | #FF00FF | planned (S2.2) | P-PROP-02 | Пестик; точка вращения задаётся в сцене |
| prop_flask_round | assets/props/prop_flask_round.png | 384×512 | bottom | #FF00FF (global) | temp | P-PROP-03 | Стекло прозрачное, жидкость — шейдер |
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
| client_baker_neutral | assets/characters/client_baker_neutral.png | 768×768 | bottom | #00FF00 | temp | P-CHR-01 |  |
| client_baker_happy | assets/characters/client_baker_happy.png | 768×768 | bottom | #00FF00 | planned (S5.1) | P-CHR-02 | Приложить нейтральный портрет |
| client_baker_upset | assets/characters/client_baker_upset.png | 768×768 | bottom | #00FF00 | planned (S5.1) | P-CHR-03 | Приложить нейтральный портрет |
| ui_button_wood | assets/ui/ui_button_wood.png | по содержимому | — | #FF00FF | temp | P-UI-01 | Поля 9-slice задаются на S1.5 |
| ui_panel_parchment | assets/ui/ui_panel_parchment.png | по содержимому | — | #FF00FF | temp | P-UI-02 | Поля 9-slice задаются на S1.5 |
| icon_coin | assets/ui/icon_coin.png | 256×256 | center | #FF00FF | temp | P-UI-03 |  |
| icon_star | assets/ui/icon_star.png | 256×256 | center | #FF00FF | temp | P-UI-04 |  |
| ui_badge_round | assets/ui/ui_badge_round.png | 256×256 | center | #FF00FF | temp | P-UI-05 |  |
