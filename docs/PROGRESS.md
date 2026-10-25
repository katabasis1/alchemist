# PROGRESS — где мы сейчас

**Обновлено:** 2026-10-25 (сессия 9)
**Версия:** 0.1.0 (тег `v0.1.0` в истории агента) — **M1**: каркас готов (S1 закрыт)
**Текущий этап:** M1 — контрольная точка с пользователем; дальше S2 — вертикальный срез «ступка»
**Текущий подэтап:** S1.7 завершён; ждём проверку M1, затем S2.1
**Репозиторий:** https://github.com/katabasis1/alchemist (`main` = `355ab53` «0.0.4», пользователь запушил v0.0.4 2026-10-24; в истории агента это `6912f09` + тег `v0.0.4`)

## Статус S0–S1
- [x] S0.1–S0.6 Фундамент (стиль A утверждён: ART_STYLE v1.0; GDD v1)
- [x] S1.1 Валидатор v1: `tools/validate_project.py`, 70 правил, `--self-test` на фикстурах
- [x] S1.2 Минимальный проект v0.0.1
- [x] S1.3 Обмен через GitHub: агент читает GitHub веб-инструментом, выдаёт `alchemist_update_v*.zip` + патчи (D16, AGENTS.md §2.2–2.3)
- [x] S1.4 Автозагрузки v0.0.2: `EventBus`, `Platform` (+ `PlatformMock`), `GameState`, `SaveService`, `AudioDirector`, `SceneRouter`, `scenes/debug/services_smoke.tscn`
- [x] S1.5 Компоненты v1 (v0.0.3): 12 компонентов (`docs/COMPONENTS.md`), портретный фон и смена раскладки, временные звуки, `scenes/debug/components_demo.tscn`
- [x] S1.6 Классы данных (v0.0.4): `PropertyData`, `IngredientData`, `RecipeData`, `OrderTemplate`, `ClientData`, `ToolData`, `RankData`, `DailyRewardConfig`, `EconomyConfig`, `DataCatalog` + 102 `.tres` по GDD v1 (6 свойств, 12 ингредиентов, 20 рецептов, 38 шаблонов заказов + 5 FTUE, 7 клиентов, 6 покупок, 5 рангов); `GameState.catalog`, новая игра — из данных; `scenes/debug/data_check.tscn`; `tools/data/bootstrap_gdd_v1.py --check` — решаемость заказов
- [x] S1.7 Локализация (v0.0.5 + v0.1.0): шрифты Kurale и Nunito 600/800 (OFL, урезаны до латиницы и кириллицы, `tools/fonts/build_fonts.py`); `localization/strings.csv` — 112 ключей ru/en через humanizer; тема `ui/theme/main_theme.tres` в настройках проекта (варианты `TitleLabel`, `HeaderLabel`, `LightLabel`, `TooltipLabel`, `TooltipPanel`; размеры — ART_STYLE §6); `Tooltip` на теме; экран загрузки `scenes/loading/loading_screen.tscn` (колба качается, полоса по шагам запуска, затем тает; `Platform.loading_ready()` — после него); язык ставится сразу после `Platform.initialize` и ещё раз после загрузки сохранения; `scenes/debug/l10n_check.tscn`
- [ ] **M1 = v0.1.0** — проверка пользователем (ниже)

## Ждём от пользователя (M1)
1. Обновить проект одним архивом: если на GitHub ещё v0.0.4 — `outbox/alchemist_update_v0.0.4_to_v0.1.0.zip`; если v0.0.5 уже запушен — `outbox/alchemist_update_v0.1.0.zip`. Распаковать поверх проекта. Полная копия с картинками — `archive/alchemist_latest.zip`.
2. Открыть в Godot 4.7. Godot создаст `*.import` для шрифтов и `strings.csv`, `strings.en.translation`, `strings.ru.translation`, `*.uid` для новых скриптов (`loading_screen.gd`, `l10n_check.gd`) — закоммитить всё и запушить.
3. **F5:** тёмно-коричневый экран загрузки — качается колба, золотое «Лавка алхимика», полоса заполняется, «Загрузка…»; экран тает, открывается лавка. Сузить окно до «телефона» — экран и лавка перестраиваются в портрет.
4. **F6** по очереди в `scenes/debug/`: `services_smoke` → `SMOKE: 8/8 OK`; `components_demo` → `COMPONENTS: 20/20 OK` (подсказки теперь шрифтом Nunito и крупнее); `data_check` → `DATA: 23/23 OK`; `l10n_check` → `L10N: 9/9 OK`. Ошибки — прислать текст Output.
5. Английский: `autoload/platform/platform.tscn` → узел `PlatformMock` → `language_override` = `en`, F5 — «The Alchemist's Shop». Вернуть поле пустым.
6. Ответ по M1: всё ли запускается; нравятся ли шрифты и экран загрузки; читается ли текст подсказок на узком окне.

## Следующий шаг
- Сверить GitHub (AGENTS.md §2.2): подтянуть `*.import`, `*.translation`, `*.uid` из пуша пользователя; если Output проверочных сцен с ошибками — сначала исправить.
- Затем **S2.1**: полка ингредиентов + перетаскивание, подсветка цели; ассеты S2 (GDD §14): `prop_mortar_bowl`, `prop_pestle`, `prop_shelf`, `ui_trash`, `icon_prop_*` ×6 — временные + промпты (AGENTS.md §3.7).

## Блокеры
- нет. Computer без сети — принято; GitHub читается веб-инструментом агента.

## Известный долг
- GDScript автозагрузок, компонентов, данных, экрана загрузки ни разу не запускался (у агента нет Godot): проверка — четырьмя сценами из п. 4 и F5.
- Размеры шрифтов — стартовые значения, проверка на телефоне — ART_STYLE §6.
- Экран загрузки использует временную колбу `prop_flask_round`; стиль кнопок в теме появится с финальной `ui_button_wood` (9-slice).
- Баланс (к S3.3 / S6.4): упрощённый перебор показал, что заказы на Едкость решаются Огнецветом через низ Отстойника (Ржавый лишайник не обязателен), а «Масло ледяного фонаря» ★★/★★ — без Снежного лотоса (Лунный мох + Золотой корень, верх). Ошибкой это не считается, но стоит учесть при проверке ценности покупок.
- Временные звуки (`audio/sfx/*.ogg`) синтезированы — заменить на S8 (см. `docs/AUDIO.md`).
- Пауза при потере фокуса включена и в редакторе (`Platform.pause_on_focus_loss`) — если мешает, выключить в `autoload/platform/platform.tscn`.
- Лёгкий зелёный ореол на кудрях клиентки; ландшафтный фон 1536×864 апскейлен (temp).
- История агента с сессии 9 собрана из ZIP ветки `main` вместе с PNG (AGENTS.md §2.3): `archive/alchemist_latest.zip` — полный проект с картинками.

## Архив
`outbox/alchemist_update_v0.0.4_to_v0.1.0.zip` (сводный от GitHub v0.0.4), `outbox/alchemist_update_v0.1.0.zip` (после v0.0.5), `outbox/patches/v0.1.0/`, `archive/alchemist_latest.zip` (полный проект), `archive/alchemist_repo.bundle`, `archive/history/`, `archive/LAST_SYNC.txt`.
