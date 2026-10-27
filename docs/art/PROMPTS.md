# PROMPTS — готовые промпты для ChatGPT Image

Как пользоваться:
1. Открой **один** чат ChatGPT для всей серии, приложи референсы `docs/art/reference/style_A_mockup.jpg` и `docs/art/reference/style_A_assets_sheet.png`.
2. Копируй блок промпта целиком. Для эмоций персонажа дополнительно приложи готовый нейтральный портрет.
3. Сохрани результат под именем из колонки «Файл» (например `prop_flask_round.png`) → положи в `inbox/art/` Pod. Агент вырежет фон и впишет в холст по `ASSET_REGISTRY.md`.

Стилевой префикс (уже включён в каждый промпт ниже):

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.
```

| ID | Файл | Что это |
|---|---|---|
| P-BG-01 | `bg_workshop.png` | Фон лавки (ландшафт) |
| P-BG-02 | `bg_workshop_portrait.png` | Фон лавки (портрет, телефон) |
| P-PROP-01 | `prop_mortar_bowl.png` | Ступка (чаша без пестика) |
| P-PROP-02 | `prop_pestle.png` | Пестик (отдельно) |
| P-PROP-03 | `prop_flask_round.png` | Колба круглодонная (пустая) |
| P-ING-01 | `ing_fire_bloom.png` | Ингредиент: огнецвет |
| P-ING-02 | `ing_moon_moss.png` | Ингредиент: лунный мох |
| P-ING-03 | `ing_golden_root.png` | Ингредиент: золотой корень |
| P-ING-04 | `ing_sage_bundle.png` | Ингредиент: пучок шалфея |
| P-ING-05 | `ing_drowse_herb.png` | Ингредиент: дрёма-трава (GDD v1, ранг 2) |
| P-ING-06 | `ing_rust_lichen.png` | Ингредиент: ржавый лишайник (ранг 3) |
| P-ING-07 | `ing_frost_berry.png` | Ингредиент: морозника (ранг 3) |
| P-ING-08 | `ing_glow_flower.png` | Ингредиент: светоцвет (ранг 3) |
| P-ING-09 | `ing_ember_nut.png` | Ингредиент: жар-орех (ранг 3) |
| P-ING-10 | `ing_sun_petal.png` | Ингредиент: солнечник (ранг 4) |
| P-ING-11 | `ing_snow_lotus.png` | Ингредиент: снежный лотос (ранг 4) |
| P-ING-12 | `ing_star_crystal.png` | Ингредиент: звёздный кристалл (редкий) |
| P-CHR-01 | `client_baker_neutral.png` | Клиент «Пекарша» — нейтральная |
| P-CHR-02 | `client_baker_happy.png` | Клиент «Пекарша» — радость |
| P-CHR-03 | `client_baker_upset.png` | Клиент «Пекарша» — недовольна |
| P-UI-01 | `ui_button_wood.png` | Кнопка деревянная (9-slice) |
| P-UI-02 | `ui_panel_parchment.png` | Панель-пергамент (9-slice) |
| P-UI-03 | `icon_coin.png` | Иконка монеты |
| P-UI-04 | `icon_star.png` | Иконка звезды (оценка) |
| P-UI-05 | `ui_badge_round.png` | Рамка-медальон (пузырь заказа) |
| P-PROP-04 | `prop_shelf_slot.png` | Ячейка полки (деревянный лоток под один ингредиент) |
| P-UI-06 | `ui_trash.png` | Корзина «вылить» (деревянное ведёрко) |
| P-UI-07 | `icon_prop_sheet.png` → `icon_prop_*.png` ×6 | Иконки шести свойств одним листом (агент режет) |

## P-BG-01 — Фон лавки (ландшафт) → `bg_workshop.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

Wide game background: interior of a cozy fairytale alchemist's shop seen from the alchemist's side, straight front view. Foreground: a long, empty, clean wooden workbench spanning the full width; the back edge of the workbench top must be at about 70% of the image height and the bench surface must be completely clear for gameplay objects. Middle and back: wooden shelves with assorted jars and bottles, bundles of dried herbs hanging from ceiling beams, a large round leaded window on the left letting in warm golden afternoon light, potted plants, copper pipes, a small brass scale on a high shelf, a doorway with a little shop bell on the right where customers come in. Calm, warm, inviting atmosphere; the background is slightly softer and less contrasted than gameplay objects.

Landscape 1536x1024. Keep all important content inside the central 16:9 band (top and bottom ~8% may be cropped). No characters.
```

## P-BG-02 — Фон лавки (портрет, телефон) → `bg_workshop_portrait.png`

Приложи к чату и готовый `bg_workshop.png` (ландшафт): это та же лавка, нужна та же мебель и та же палитра.

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

Tall portrait game background for a phone screen: the same cozy fairytale alchemist's shop as in the attached landscape background (same furniture, materials and light), recomposed vertically, straight front view from the alchemist's side. Upper part (top 40% of the image): back wall with wooden shelves of assorted jars and bottles, bundles of dried herbs hanging from a ceiling beam, a round leaded window on the left with warm golden afternoon light, potted plants, copper pipes, a small brass scale on a high shelf, a wooden door with a little shop bell on the right. The empty space in front of the left-middle shelves is where a customer will stand, so keep it calm and uncluttered. Lower part: a large empty wooden workbench seen from slightly above; the back edge of the workbench top must be at about 40% of the image height, the bench surface must be completely clear for gameplay objects and take up roughly the next 35% of the height; below it the front of the bench with simple wooden drawers down to the bottom edge. Calm, warm, inviting atmosphere; the background is slightly softer and less contrasted than gameplay objects.

Portrait 1024x1536. Keep all important content inside the central 9:16 band (left and right ~8% may be cropped). No characters.
```

После замены: проверить линию края прилавка (сейчас y = 781 на холсте 1080×1920), при необходимости поправить `--top` в реестре и позицию узла `BenchPortrait` в `scenes/workshop/workshop.tscn`, затем пересобрать слой прилавка командой из реестра.

## P-PROP-01 — Ступка (чаша без пестика) → `prop_mortar_bowl.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A sturdy grey-stone alchemist's mortar bowl, empty (no powder, no pestle), thick rounded rim with small carved details, the inner hollow clearly visible from slightly above.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-PROP-02 — Пестик (отдельно) → `prop_pestle.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A single wooden pestle with a rounded grey-stone grinding head, lying diagonally, nothing else.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-PROP-03 — Колба круглодонная (пустая) → `prop_flask_round.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

An empty, perfectly clear glass round-bottom alchemy flask with a long neck and a rolled rim, drawn with a clean outline, bright white highlights and soft light-blue reflections along the edges.

Single isolated game asset, centered, three-quarter front view, the whole object fully visible with generous empty margin. The glass must be see-through: the background must be visible through the glass. Transparent background (PNG with alpha); if transparency is not possible: perfectly flat solid pure magenta #FF00FF background that also shows through the glass. No liquid, no cast shadow, no other objects. Square 1024x1024.
```

## P-ING-01 — Ингредиент: огнецвет → `ing_fire_bloom.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A fiery orange-red magical flower with curled flame-like petals and a short green stem with two leaves (alchemy ingredient).

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-02 — Ингредиент: лунный мох → `ing_moon_moss.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A soft rounded clump of pale blue moon moss with tiny lighter tips (alchemy ingredient).

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-03 — Ингредиент: золотой корень → `ing_golden_root.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A knobby golden-yellow root with small rootlets, slightly glossy (alchemy ingredient).

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-04 — Ингредиент: пучок шалфея → `ing_sage_bundle.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small bundle of sage-green leaves tied with a brown string (alchemy ingredient).

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-05 — Ингредиент: дрёма-трава → `ing_drowse_herb.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small tied bundle of a sleepy magical herb: slender gently drooping stems with tiny bell-shaped soft indigo-blue flowers (#6C7BD9, clearly blue rather than purple) and fresh green leaves, tied with a twine bow. Calm, soft, cozy look.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-06 — Ингредиент: ржавый лишайник → `ing_rust_lichen.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small flat rounded river stone covered with frilly crusty lichen in rusty copper-brown tones with violet edges (#9B5DE5) and a few tiny golden specks. Friendly, not dirty or gross.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure green #00FF00 background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-07 — Ингредиент: морозника → `ing_frost_berry.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small sprig of magical frost berries: a cluster of round icy-blue berries (#5BC8F5) with a thin white frost rim and tiny highlights, on a short green twig with two leaves.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-08 — Ингредиент: светоцвет → `ing_glow_flower.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A magical cup-shaped flower with bright warm golden-yellow petals (#FFE066), a pale indigo center, a short green stem and two leaves. Flat painted object: no glow, no light rays, no sparkles (glow is added in-game).

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-09 — Ингредиент: жар-орех → `ing_ember_nut.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A chunky round magical nut with a hard walnut-brown shell, cracked open on one side to show a warm orange-red kernel (#FF6B2C). No fire, no smoke.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-10 — Ингредиент: солнечник → `ing_sun_petal.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A magical sunflower-like flower head with layered petals going from golden yellow at the tips to warm orange at the base, a green seed center and one green leaf.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-11 — Ингредиент: снежный лотос → `ing_snow_lotus.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small magical lotus flower with pointed icy white-blue petals and a pale gold heart, resting on a round green lily pad.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-ING-12 — Ингредиент: звёздный кристалл (редкий) → `ing_star_crystal.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A rare magical crystal cluster: three pale-gold translucent crystal points of different heights growing from a small grey rock, clean faceted shapes with soft highlights. Not star-shaped, no symbols. Flat painted object: no glow, no sparkles (glow is added in-game).

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-CHR-01 — Клиент «Пекарша» — нейтральная → `client_baker_neutral.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A friendly plump village baker woman in her forties: rosy cheeks, a little flour on her cream apron, brown hair in a bun under a cream kerchief, mustard-yellow dress. Warm curious expression with a slight smile.

Character bust portrait: head, shoulders and upper chest; the bottom edge of the image cuts the character at mid-chest (they stand behind a shop counter). Turned three-quarters toward the viewer, big expressive eyes. Transparent background (PNG with alpha); if transparency is not possible: perfectly flat solid pure green #00FF00 background and no green anywhere on the character. No shadow. Square 1024x1024.
```

## P-CHR-02 — Клиент «Пекарша» — радость → `client_baker_happy.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

The SAME baker woman as in the attached neutral portrait (identical design, clothes, colors and framing), now delighted: big open smile, eyes squinting with joy, hands clasped near her chest.

Character bust portrait: head, shoulders and upper chest; the bottom edge of the image cuts the character at mid-chest (they stand behind a shop counter). Turned three-quarters toward the viewer, big expressive eyes. Transparent background (PNG with alpha); if transparency is not possible: perfectly flat solid pure green #00FF00 background and no green anywhere on the character. No shadow. Square 1024x1024.
```

## P-CHR-03 — Клиент «Пекарша» — недовольна → `client_baker_upset.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

The SAME baker woman as in the attached neutral portrait (identical design, clothes, colors and framing), now mildly disappointed in a cartoony, non-aggressive way: pouting lips, raised eyebrows, one hand on her cheek.

Character bust portrait: head, shoulders and upper chest; the bottom edge of the image cuts the character at mid-chest (they stand behind a shop counter). Turned three-quarters toward the viewer, big expressive eyes. Transparent background (PNG with alpha); if transparency is not possible: perfectly flat solid pure green #00FF00 background and no green anywhere on the character. No shadow. Square 1024x1024.
```

## P-UI-01 — Кнопка деревянная (9-slice) → `ui_button_wood.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A wide rounded wooden button plate with small brass corner caps; even plain center area so it can be stretched as a 9-slice.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons unless described). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```

## P-UI-02 — Панель-пергамент (9-slice) → `ui_panel_parchment.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A rectangular parchment panel with slightly curled edges and a thin wooden frame; even plain center area so it can be stretched as a 9-slice.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons unless described). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```

## P-UI-03 — Иконка монеты → `icon_coin.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A shiny gold coin with a simple leaf emblem, slight three-quarter tilt.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons unless described). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```

## P-UI-04 — Иконка звезды (оценка) → `icon_star.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A plump, rounded golden star with a soft highlight.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons unless described). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```

## P-UI-05 — Рамка-медальон (пузырь заказа) → `ui_badge_round.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small round copper badge frame with an empty light parchment center for an icon.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons unless described). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```

## P-PROP-04 — Ячейка полки → `prop_shelf_slot.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small square open wooden crate-tray (one shelf compartment) made of honey-coloured wood planks with brass corner caps and tiny rivets, a low front wall, empty inside, seen from the front and slightly above so the empty floor of the tray is visible. Wider than tall, sturdy and cosy, nothing inside.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-UI-06 — Корзина «вылить» → `ui_trash.png`

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small empty wooden slop bucket with two brass hoops and a little rope handle, slightly tilted toward the viewer so the empty inside is visible, for pouring out a failed mix. Friendly and clean, no liquid, no dirt.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons unless described). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```

## P-UI-07 — Иконки свойств (лист из шести) → `icon_prop_sheet.png`

Агент режет лист на `icon_prop_acid`, `icon_prop_heat`, `icon_prop_life`, `icon_prop_cold`, `icon_prop_sleep`, `icon_prop_light` (порядок — как в промпте). Заливка **белая**: цвет свойства игра накладывает сама из `PropertyData.color`, иначе цвета разъедутся с GDD §3.1.

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A game UI icon sheet: six simple bold symbol icons arranged in a 3 by 2 grid with wide empty gaps between them, none touching. Each icon is a chunky, rounded silhouette filled with flat pure white (#FFFFFF) and very light grey soft shading only, with a clean confident dark warm-brown outline (#431D0D) of thick consistent weight, readable at 48 pixels.
Top row, left to right: 1) a cluster of three round bubbles of different sizes; 2) a plump flame; 3) a single leaf with a curled stem.
Bottom row, left to right: 4) a six-armed snowflake with rounded tips; 5) a crescent moon; 6) a four-pointed sparkle star.
No colour fills other than white and light grey, no frames, no badges.

Flat front view, all six icons fully visible with generous empty margin. Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Landscape 1536x1024.
```

## P-PROP-05 — Баночка мази → `prop_jar_ointment.png`

Так выглядит зелье, отданное клиенту прямо из ступки. Холст 256×256, опора по центру: агент уменьшает и вырезает фон (`tools/art/cutout.py`).

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A small round glazed ceramic ointment jar, cream-white with a wide sage-green painted band and a simple light leaf pattern on it, a short neck covered with a cream cloth cap tied with a twisted jute rope bow, a small blank parchment tag hanging from the rope. Plump, cosy and handmade, slightly wider than tall, a little copper-brown foot ring at the bottom.

Single isolated game asset, centered, three-quarter front view seen slightly from above, the whole object fully visible with generous empty margin. Transparent background (PNG with alpha). If transparency is not possible: perfectly flat solid pure magenta #FF00FF background, no gradient. No cast shadow, no floor, no other objects. Square 1024x1024.
```

## P-UI-08 — Пузырь заказа → `ui_order_bubble.png`

Пустой пузырь: фразу и иконки заказа игра кладёт поверх. Хвостик — справа внизу, к клиенту. Холст 512×320. Игра тянет пузырь как nine-patch (ASSET_REGISTRY): стороны должны быть ровными, а хвостик — маленьким и у самого угла. После cutout сверить поля и кончик хвостика с реестром.

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

An empty speech bubble for a game order panel: a wide rounded rectangle of warm parchment cream with a soft painted paper texture, slightly darker toasted edges, a clean thick dark warm-brown outline, and a small rounded tail at the bottom right edge, close to the corner, pointing down and to the right. Straight even sides and evenly rounded corners, so the panel can be stretched (nine-slice) without distortion. The inside is completely empty and evenly lit, with no pattern, so text and icons placed on it stay readable.

Flat front view game UI element, centered, fully visible with generous empty margin, blank (no text, no icons). Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Landscape 1536x1024.
```

## P-UI-09 — Кристалл чистоты → `icon_purity.png`

В пузыре заказа столько кристаллов, сколько звёзд чистоты требуется (GDD §5.2). Холст 128×128, должен читаться в 48 px.

```
Use the attached reference images strictly as the style guide. Cozy fairytale cartoon style 2D game art for a casual mobile game. Hand-painted look with clean, confident dark warm-brown outlines (#431D0D) of consistent medium-thick weight, soft cel shading with a subtle painterly texture, chunky friendly proportions, warm palette: honey and walnut wood, copper and brass, parchment cream, sage green, with small accents of teal and soft gold. Soft warm key light from the upper left, gentle rim light. Clean readable silhouettes. No text, no letters, no watermark, no skulls, no occult or religious symbols.

A single bright clear crystal gem icon for purity: an upright faceted crystal shard, pale teal and aqua with white highlights on the upper left facets and a small sparkle, chunky rounded silhouette, thick clean dark warm-brown outline, readable at 48 pixels.

Flat front view game UI icon, centered, fully visible with generous empty margin, no frame, no badge, no text. Transparent background (PNG with alpha); if not possible: perfectly flat solid pure magenta #FF00FF background. No shadow. Square 1024x1024.
```
