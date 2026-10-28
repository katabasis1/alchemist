# THIRD_PARTY — заимствованные материалы и лицензии

Правило: только CC0 / MIT / OFL (шрифты) / явно разрешающие лицензии. GPL и CC BY-NC(-SA) — не использовать в коде игры.

| Файл в проекте | Источник (URL) | Автор | Лицензия | Что изменено |
|---|---|---|---|---|
| tools/humanizer/ru/* (инструмент, не входит в сборку игры) | https://github.com/Vladimir-Human/humanizer-ru | Vladimir-Human | MIT | Без изменений, офлайн-копия |
| tools/humanizer/en/SKILL.md (инструмент, не входит в сборку игры) | https://github.com/blader/humanizer | blader | MIT | Без изменений, офлайн-копия |
| assets/fonts/kurale_regular.ttf (заголовки) | https://fonts.google.com/specimen/Kurale · https://github.com/google/fonts/tree/main/ofl/kurale | Eduardo Tunni (The Kurale Project Authors) | SIL OFL 1.1 — текст лицензии: `assets/fonts/ofl_kurale.txt` | Без изменений (v2.000) |
| assets/fonts/nunito_regular.ttf, assets/fonts/nunito_bold.ttf (основной текст) | https://fonts.google.com/specimen/Nunito · https://github.com/googlefonts/nunito | The Nunito Project Authors | SIL OFL 1.1 — текст лицензии: `assets/fonts/ofl_nunito.txt` | Статические начертания 400 и 700 вариативного шрифта (v3.602), как их отдаёт Google Fonts; глифы не менялись |
| scenes/stations/mortar/powder.gdshader, scenes/ingredient/ingredient.gdshader, components/liquid/liquid.gdshader (+ копия в tools/art/liquid_preview.py) — функции hash12 / hash22 | https://www.shadertoy.com/view/4djSRW («Hash without Sine») | Dave Hoskins | MIT | Перенесено на шейдерный язык Godot; весь остальной код шейдеров собственный |
| scenes/stations/mortar/powder.gdshader (мерцание искр по ячейкам, пульс свечения), scenes/ingredient/ingredient.gdshader (распад с каёмкой по краю), scenes/fx/fx_ring.gdshader (shockwave ring, glitter), scenes/fx/fx_rays.gdshader (god rays) | https://godotshaders.com/ (приёмы glitter, sun pulse glow, dissolve with burn edge, shockwave, god rays) | авторы godotshaders.com | только идеи, код не копировался | Свои реализации: поле высот в полости чаши, ячейки Вороного, каёмка цвета смеси |

Шрифты OFL можно встраивать в игру и продавать вместе с ней; продавать сами файлы шрифтов отдельно нельзя, а файл лицензии должен лежать рядом с ними.
