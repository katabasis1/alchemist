# PROGRESS — где мы сейчас

**Обновлено:** 2026-10-24 (сессия 8)
**Версия:** 0.0.4 (тег `v0.0.4` в истории агента) — классы данных
**Текущий этап:** S1 — Каркас и GitHub
**Текущий подэтап:** S1.7 — локализация (не начат)
**Репозиторий:** https://github.com/katabasis1/alchemist (`main`, коммит пользователя `83deb07` = v0.0.1 + `*.import`; v0.0.2–v0.0.4 ещё не запушены)

## Статус S0–S1
- [x] S0.1–S0.6 Фундамент (стиль A утверждён: ART_STYLE v1.0; GDD v1)
- [x] S1.1 Валидатор v1: `tools/validate_project.py`, 70 правил, `--self-test` на фикстурах
- [x] S1.2 Минимальный проект v0.0.1
- [x] S1.3 Обмен через GitHub: агент читает GitHub веб-инструментом, выдаёт `alchemist_update_v*.zip` + патчи (D16, AGENTS.md §2.2–2.3)
- [x] S1.4 Автозагрузки v0.0.2: `EventBus`, `Platform` (+ `PlatformMock`), `GameState`, `SaveService`, `AudioDirector`, `SceneRouter`, `scenes/debug/services_smoke.tscn`
- [x] S1.5 Компоненты v1 (v0.0.3): 12 компонентов (`docs/COMPONENTS.md`), портретный фон и смена раскладки, временные звуки, `scenes/debug/components_demo.tscn`
- [x] S1.6 Классы данных (v0.0.4): `PropertyData`, `IngredientData`, `RecipeData`, `OrderTemplate`, `ClientData`, `ToolData`, `RankData`, `DailyRewardConfig`, `EconomyConfig`, `DataCatalog` + 102 `.tres` по GDD v1 (6 свойств, 12 ингредиентов, 20 рецептов, 38 шаблонов заказов + 5 FTUE, 7 клиентов, 6 покупок, 5 рангов); `GameState.catalog`, новая игра — из данных; `scenes/debug/data_check.tscn`; `tools/data/bootstrap_gdd_v1.py --check` — решаемость заказов
- [ ] S1.7 Локализация → M1 = v0.1.0

## Ждём от пользователя
1. На GitHub всё ещё v0.0.1. Проще всего распаковать **один** архив `outbox/alchemist_update_v0.0.1_to_v0.0.4.zip` поверх проекта (там S1.4 + S1.5 + S1.6). Или по шагам: `alchemist_update_v0.0.2.zip`, `…v0.0.3.zip`, `…v0.0.4.zip`; или патчи `outbox/patches/v0.0.2/`, `v0.0.3/`, `v0.0.4/` (`git am`).
2. Открыть в Godot 4.7: Output без ошибок; F5 — лавка. Сузь окно до «телефона» — фон и клиентка перестраиваются в портрет. Godot создаст `*.uid` для новых скриптов — закоммитить вместе с обновлением и запушить.
3. В `scenes/debug/` открыть сцену и нажать **F6**: `services_smoke.tscn` → `SMOKE: 8/8 OK`; `components_demo.tscn` → `COMPONENTS: 20/20 OK` + шесть ручных проверок (они напечатаны в Output); `data_check.tscn` → `DATA: 23/23 OK`. Если есть ошибки — прислать текст Output.
4. (к S1.7) Шрифты OFL с кириллицей в `inbox/fonts/` — кандидаты в ART_STYLE.md §5. Если не пришлют — агент подберёт сам.
5. По желанию: финальный портретный фон по промпту P-BG-02 → `inbox/art/bg_workshop_portrait.png` (1080×1920).

## Следующий шаг
- Сверить GitHub с рабочей копией (AGENTS.md §2.2): если пользователь запушил обновление с `*.uid` — подтянуть; если прислал Output с ошибками проверочных сцен — сначала исправить.
- Затем **S1.7 Локализация**: `localization/strings.csv` (ru/en) для всех ключей из `.tres` (GDD §13, «Ключи текстов») и интерфейса; каждый текст — через humanizer (AGENTS.md §3.6) и в `localization/humanized.txt`; шрифты; переключение языка по `Platform`. После S1.7 — M1 = v0.1.0 (контрольная точка с пользователем).

## Блокеры
- нет. Computer без сети — принято; GitHub читается веб-инструментом агента.

## Известный долг
- GDScript автозагрузок, компонентов и данных ни разу не запускался (у агента нет Godot): проверка — тремя сценами из п. 3.
- Подсказки в `components_demo` и все `name_key` в данных показывают ключи до S1.7.
- Баланс (к S3.3 / S6.4): упрощённый перебор показал, что заказы на Едкость решаются Огнецветом через низ Отстойника (Ржавый лишайник не обязателен), а «Масло ледяного фонаря» ★★/★★ — без Снежного лотоса (Лунный мох + Золотой корень, верх). Ошибкой это не считается, но стоит учесть при проверке ценности покупок.
- Временные звуки (`audio/sfx/*.ogg`) синтезированы — заменить на S8 (см. `docs/AUDIO.md`).
- Пауза при потере фокуса включена и в редакторе (`Platform.pause_on_focus_loss`) — если мешает, выключить в `autoload/platform/platform.tscn`.
- Лёгкий зелёный ореол на кудрях клиентки; ландшафтный фон 1536×864 апскейлен (temp).
- В истории агента нет PNG/JPG пользователя (AGENTS.md §2.3); исключение — графика, которую добавил сам агент (портретный фон).

## Архив
`outbox/alchemist_update_v0.0.4.zip`, сводный `outbox/alchemist_update_v0.0.1_to_v0.0.4.zip`, `outbox/patches/v0.0.4/`, `archive/alchemist_repo.bundle` (история агента), `archive/alchemist_latest.zip` (без картинок пользователя), `archive/history/`, `archive/LAST_SYNC.txt`.
