# THIRD_PARTY — заимствованные материалы и лицензии

Правило: только CC0 / MIT / OFL (шрифты) / явно разрешающие лицензии. GPL и CC BY-NC(-SA) — не использовать в коде игры.

| Файл в проекте | Источник (URL) | Автор | Лицензия | Что изменено |
|---|---|---|---|---|
| tools/humanizer/ru/* (инструмент, не входит в сборку игры) | https://github.com/Vladimir-Human/humanizer-ru | Vladimir-Human | MIT | Без изменений, офлайн-копия |
| tools/humanizer/en/SKILL.md (инструмент, не входит в сборку игры) | https://github.com/blader/humanizer | blader | MIT | Без изменений, офлайн-копия |
| assets/fonts/kurale_regular.ttf (исходник: tools/fonts/src/kurale_regular.ttf) | https://github.com/google/fonts/tree/main/ofl/kurale | Eduardo Tunni, The Kurale Project Authors | SIL OFL 1.1 (`assets/fonts/kurale_ofl.txt`) | Урезан до латиницы, кириллицы и типографских знаков (`tools/fonts/build_fonts.py`). Reserved Font Name нет, имя сохранено |
| assets/fonts/nunito_semibold.ttf, assets/fonts/nunito_extrabold.ttf (исходник: tools/fonts/src/nunito_variable.ttf) | https://github.com/google/fonts/tree/main/ofl/nunito | The Nunito Project Authors (https://github.com/googlefonts/nunito) | SIL OFL 1.1 (`assets/fonts/nunito_ofl.txt`) | Из вариативного шрифта сделаны статичные начертания 600 и 800, урезка как у Kurale (`tools/fonts/build_fonts.py`). Reserved Font Name нет, имя сохранено |
