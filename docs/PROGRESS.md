# PROGRESS — где мы сейчас

**Обновлено:** 2026-10-26 (сессия 9)
**Версия:** 0.1.0 (тег `v0.1.0` в истории агента) — **M1**: каркас + локализация
**Текущий этап:** S1 — Каркас и GitHub (закрыт, ждёт проверки M1 пользователем)
**Текущий подэтап:** M1 — проверка пользователем; затем S2.1
**Репозиторий:** https://github.com/katabasis1/alchemist (`main`, коммит пользователя `355ab53` = v0.0.4; v0.1.0 ещё не запушен)
**Что делается прямо сейчас (по шагам):** `docs/HANDOFF.md`, в Pod — `HANDOFF.md` в корне. Читать первым.

## Статус S0–S1
- [x] S0.1–S0.6 Фундамент (стиль A утверждён: ART_STYLE v1.0; GDD v1)
- [x] S1.1 Валидатор v1: `tools/validate_project.py`, 71 правило (L011 — с S1.7), `--self-test` на фикстурах
- [x] S1.2 Минимальный проект v0.0.1
- [x] S1.3 Обмен через GitHub: агент читает GitHub веб-инструментом, выдаёт `alchemist_update_v*.zip` + патчи (D16, AGENTS.md §2.2–2.3)
- [x] S1.4 Автозагрузки v0.0.2: `EventBus`, `Platform` (+ `PlatformMock`), `GameState`, `SaveService`, `AudioDirector`, `SceneRouter`, `scenes/debug/services_smoke.tscn`
- [x] S1.5 Компоненты v1 (v0.0.3): 12 компонентов (`docs/COMPONENTS.md`), портретный фон и смена раскладки, временные звуки, `scenes/debug/components_demo.tscn`
- [x] S1.6 Классы данных (v0.0.4): `PropertyData`, `IngredientData`, `RecipeData`, `OrderTemplate`, `ClientData`, `ToolData`, `RankData`, `DailyRewardConfig`, `EconomyConfig`, `DataCatalog` + 102 `.tres` по GDD v1 (6 свойств, 12 ингредиентов, 20 рецептов, 38 шаблонов заказов + 5 FTUE, 7 клиентов, 6 покупок, 5 рангов); `GameState.catalog`, новая игра — из данных; `scenes/debug/data_check.tscn`; `tools/data/bootstrap_gdd_v1.py --check` — решаемость заказов
- [x] S1.7 Локализация (v0.1.0 = **M1**): `localization/strings.csv` — 111 ключей ru/en, все прошли humanizer (`humanized.txt`); шрифты Kurale + Nunito (OFL) и тема `assets/ui/main_theme.tres`; экран загрузки `scenes/loading/`; язык — настройка → платформа → ru/en, смена на лету; `scenes/debug/l10n_check.tscn`; правило валидатора L011

## Ждём от пользователя (M1)
1. Распаковать **`outbox/alchemist_update_v0.1.0.zip`** поверх проекта (всё, что изменилось после v0.0.4, которая уже на GitHub). Или патчи `outbox/patches/v0.1.0/` (`git am`).
2. Открыть в Godot 4.7. Godot сам импортирует `localization/strings.csv` (появятся `strings.ru.translation`, `strings.en.translation`) и шрифты, создаст `*.uid`/`*.import` — всё это закоммитить вместе с обновлением и запушить.
3. F5: сначала коричневый экран «Лавка алхимика / Открываем лавку…» (надпись «дышит»), он плавно гаснет — открывается лавка. Чтобы увидеть английский: `autoload/platform/platform.tscn` → узел `PlatformMock` → `language_override = "en"`.
4. В `scenes/debug/` открыть сцену и нажать **F6**: `services_smoke.tscn` → `SMOKE: 8/8 OK`; `components_demo.tscn` → `COMPONENTS: 20/20 OK` + ручные проверки из Output (подсказки теперь с текстом, а не ключами); `data_check.tscn` → `DATA: 23/23 OK`; `l10n_check.tscn` → `L10N: 9/9 OK`, на экране текст шрифтами игры, язык меняется каждые 2 с. Прислать текст Output, если есть ошибки или предупреждения.
5. Сказать, нравятся ли шрифты (заголовки Kurale, текст Nunito) — заменить сейчас дёшево.
6. По желанию: финальный портретный фон по промпту P-BG-02 → `inbox/art/bg_workshop_portrait.png` (1080×1920).

## Следующий шаг
- Сверить GitHub с рабочей копией (AGENTS.md §2.2): подтянуть `*.uid`, `*.import`, `*.translation` от Godot; если пользователь прислал Output с ошибками — сначала исправить (это и есть приёмка M1).
- Затем **S2.1** по `docs/PLAN.md` (этап S2). Перед началом — вписать чек-лист S2.1 в `docs/HANDOFF.md`.

## Блокеры
- нет. Computer без сети — принято; GitHub читается веб-инструментом агента.

## Известный долг
- GDScript автозагрузок, компонентов и данных ни разу не запускался (у агента нет Godot): проверка — тремя сценами из п. 3.
- Переводы и шрифты ни разу не открывались в Godot: CSV импортирует редактор, проверка — `l10n_check.tscn`.
- Boot splash Godot (логотип) перед экраном загрузки и HTML-заставка web-экспорта — настроить на S10 вместе с шаблоном экспорта.
- Баланс (к S3.3 / S6.4): упрощённый перебор показал, что заказы на Едкость решаются Огнецветом через низ Отстойника (Ржавый лишайник не обязателен), а «Масло ледяного фонаря» ★★/★★ — без Снежного лотоса (Лунный мох + Золотой корень, верх). Ошибкой это не считается, но стоит учесть при проверке ценности покупок.
- Временные звуки (`audio/sfx/*.ogg`) синтезированы — заменить на S8 (см. `docs/AUDIO.md`).
- Пауза при потере фокуса включена и в редакторе (`Platform.pause_on_focus_loss`) — если мешает, выключить в `autoload/platform/platform.tscn`.
- Лёгкий зелёный ореол на кудрях клиентки; ландшафтный фон 1536×864 апскейлен (temp).
- В истории агента нет PNG/JPG пользователя (AGENTS.md §2.3); исключение — графика, которую добавил сам агент (портретный фон).

## Архив
`outbox/alchemist_update_v0.1.0.zip` (изменения после v0.0.4), `outbox/patches/v0.1.0/`, `archive/alchemist_repo.bundle` (история агента), `archive/alchemist_latest.zip` (без картинок пользователя), `archive/history/`, `archive/LAST_SYNC.txt`.
