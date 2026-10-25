# PROGRESS — где мы сейчас

**Обновлено:** 2026-10-25 (сессия 9)
**Версия:** 0.0.5 (тег `v0.0.5` в истории агента) — S1.7, часть 1: шрифты и тексты
**Текущий этап:** S1 — Каркас и GitHub
**Текущий подэтап:** S1.7 — локализация (в работе: шрифты, `strings.csv`, подключение перевода готовы; тема, экран загрузки и проверочная сцена — дальше)
**Репозиторий:** https://github.com/katabasis1/alchemist (`main` = `355ab53` «0.0.4», пользователь запушил v0.0.4 2026-10-24; в истории агента это `6912f09` + тег `v0.0.4`)

## Статус S0–S1
- [x] S0.1–S0.6 Фундамент (стиль A утверждён: ART_STYLE v1.0; GDD v1)
- [x] S1.1 Валидатор v1: `tools/validate_project.py`, 70 правил, `--self-test` на фикстурах
- [x] S1.2 Минимальный проект v0.0.1
- [x] S1.3 Обмен через GitHub: агент читает GitHub веб-инструментом, выдаёт `alchemist_update_v*.zip` + патчи (D16, AGENTS.md §2.2–2.3)
- [x] S1.4 Автозагрузки v0.0.2: `EventBus`, `Platform` (+ `PlatformMock`), `GameState`, `SaveService`, `AudioDirector`, `SceneRouter`, `scenes/debug/services_smoke.tscn`
- [x] S1.5 Компоненты v1 (v0.0.3): 12 компонентов (`docs/COMPONENTS.md`), портретный фон и смена раскладки, временные звуки, `scenes/debug/components_demo.tscn`
- [x] S1.6 Классы данных (v0.0.4): `PropertyData`, `IngredientData`, `RecipeData`, `OrderTemplate`, `ClientData`, `ToolData`, `RankData`, `DailyRewardConfig`, `EconomyConfig`, `DataCatalog` + 102 `.tres` по GDD v1 (6 свойств, 12 ингредиентов, 20 рецептов, 38 шаблонов заказов + 5 FTUE, 7 клиентов, 6 покупок, 5 рангов); `GameState.catalog`, новая игра — из данных; `scenes/debug/data_check.tscn`; `tools/data/bootstrap_gdd_v1.py --check` — решаемость заказов
- [~] S1.7 Локализация → M1 = v0.1.0. Готово (v0.0.5): шрифты Kurale (заголовки) и Nunito 600/800 (текст, кнопки) под OFL, урезаны до латиницы и кириллицы (`tools/fonts/build_fonts.py`, `--check` — все символы строк есть в шрифтах); `localization/strings.csv` — 110 ключей ru/en (свойства, ингредиенты, рецепты и описания, клиенты, ранги, покупки, фразы заказов и FTUE, названия языков), все прошли humanizer (`humanized.txt`); перевод подключён в `project.godot`. Осталось: тема с шрифтами, экран загрузки, проверочная сцена `l10n_check`

## Ждём от пользователя
1. Распаковать `outbox/alchemist_update_v0.0.5.zip` поверх проекта (GitHub на v0.0.4 — одного архива хватает). Запасной путь — патчи `outbox/patches/v0.0.5/` (`git am`). Полная копия проекта с картинками — `archive/alchemist_latest.zip`.
2. Открыть в Godot 4.7. Godot импортирует `localization/strings.csv` и создаст рядом `strings.csv.import`, `strings.en.translation`, `strings.ru.translation`, а также `*.import` для трёх шрифтов в `assets/fonts/`. Всё это закоммитить вместе с обновлением и запушить.
3. `scenes/debug/components_demo.tscn` → F6: подсказки над предметами показывают текст («Огнецвет», «Лунный мох», «Круглая колба» или английский вариант, если ОС на английском), а не ключи `ING_…_NAME`.
4. Если ещё не присылали: Output проверочных сцен `services_smoke` (`SMOKE: 8/8 OK`), `components_demo` (`COMPONENTS: 20/20 OK`), `data_check` (`DATA: 23/23 OK`).

## Следующий шаг
- Сверить GitHub (AGENTS.md §2.2): подтянуть `*.import`/`*.translation`, если пользователь запушил v0.0.5.
- Закончить **S1.7**: тема `ui/theme` (Nunito по умолчанию, Kurale для заголовков, размеры из ART_STYLE §5), подсказка `Tooltip` — на теме; экран загрузки (Platform.initialize → загрузка сохранения → `Platform.loading_ready()` → лавка); ключи интерфейса экрана загрузки через humanizer; `scenes/debug/l10n_check.tscn` (все ключи есть в ru и en, `name_key`/`desc_key` из данных переводятся, смена языка на лету). Затем M1 = v0.1.0.

## Блокеры
- нет. Computer без сети — принято; GitHub читается веб-инструментом агента.

## Известный долг
- GDScript автозагрузок, компонентов и данных ни разу не запускался (у агента нет Godot): проверка — тремя сценами из п. 3.
- Шрифты ещё не подключены к интерфейсу (тема — следующий шаг S1.7): пока текст рисуется шрифтом Godot по умолчанию.
- Баланс (к S3.3 / S6.4): упрощённый перебор показал, что заказы на Едкость решаются Огнецветом через низ Отстойника (Ржавый лишайник не обязателен), а «Масло ледяного фонаря» ★★/★★ — без Снежного лотоса (Лунный мох + Золотой корень, верх). Ошибкой это не считается, но стоит учесть при проверке ценности покупок.
- Временные звуки (`audio/sfx/*.ogg`) синтезированы — заменить на S8 (см. `docs/AUDIO.md`).
- Пауза при потере фокуса включена и в редакторе (`Platform.pause_on_focus_loss`) — если мешает, выключить в `autoload/platform/platform.tscn`.
- Лёгкий зелёный ореол на кудрях клиентки; ландшафтный фон 1536×864 апскейлен (temp).
- История агента с сессии 9 собрана из ZIP ветки `main` вместе с PNG (AGENTS.md §2.3): `archive/alchemist_latest.zip` — полный проект с картинками.

## Архив
`outbox/alchemist_update_v0.0.5.zip` (изменения после v0.0.4 на GitHub), `outbox/patches/v0.0.5/`, `archive/alchemist_latest.zip` (полный проект), `archive/alchemist_repo.bundle` (история агента), `archive/history/`, `archive/LAST_SYNC.txt`.
