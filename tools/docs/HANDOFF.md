# HANDOFF — что делается прямо сейчас (читать ПЕРВЫМ)

> Этот файл переписывается после **каждого** шага, а не в конце подэтапа. Одна команда сохраняет всё:
> `python tools/pod_sync.py --quick --note "что сделано"`. Она дописывает строку в журнал ниже,
> коммитит всё незакоммиченное, обновляет bundle и кладёт этот файл в корень Pod (`/files/pod/HANDOFF.md`).
> Ответ агента может оборваться в любой момент. Чего нет в Pod, следующий агент не увидит.

## Сейчас
- **S1.7 закончен, v0.1.0 = M1 выдан** (коммит `S1.7: …`, тег `v0.1.0`, полный `pod_sync`). Пользователю: `outbox/alchemist_update_v0.1.0.zip`.
- Ждём от пользователя проверку M1 — список в `docs/PROGRESS.md`, «Ждём от пользователя».
- Следующий агент: сверить GitHub (AGENTS.md §2.2) → если пользователь прислал Output с ошибками, сначала исправить → затем S2.1 (вписать его чек-лист сюда вместо чек-листа S1.7).
- Рабочая копия: `/tmp/work/repo`. Если песочница перезапускалась: `git clone /files/pod/archive/alchemist_repo.bundle /tmp/work/repo && cd /tmp/work/repo && python tools/placeholder_pngs.py`
- GitHub: `355ab53` = v0.0.4 (проверено 2026-10-26 09:10 UTC)

## Чек-лист S1.7
- [x] `localization/strings.csv`: 111 ключей ru/en — все `*_key` из `data/**/*.tres` + `GAME_TITLE`, `LOADING_TEXT`, `LANGUAGE_NAME`, `PROP_FLASK_NAME`
- [x] humanizer ru/en, все ключи отмечены в `localization/humanized.txt`
- [x] шрифты: Kurale (заголовки), Nunito 400/700 (текст) + OFL-лицензии; строки в `docs/THIRD_PARTY.md`; кириллица и все символы CSV есть (проверено fontTools)
- [x] `project.godot`: `locale/translations`, `gui/theme/custom`, `config/name_localized`, версия 0.1.0
- [x] `assets/ui/main_theme.tres`: шрифт по умолчанию 32, вариации `TitleLabel` (Kurale 72) и `BoldLabel`
- [x] экран загрузки `scenes/loading/loading_screen.tscn` + подключение в `scenes/main/main.tscn` / `main.gd`
- [x] смена языка по настройке: `EventBus.settings_changed` → `TranslationServer.set_locale`
- [x] проверочная сцена `scenes/debug/l10n_check.tscn` → `L10N: x/y OK`
- [x] валидатор: правило L011 — ключ из `*_key` в `.tres/.tscn` есть в `strings.csv` (+ фикстура, самотест)
- [x] документы: PROGRESS, DEVLOG (сессия 9), PLAN [x], ART_STYLE §5, README «Проверка в Godot», GDD §13
- [x] коммит `S1.7: ...`, тег `v0.1.0`, `python tools/pod_sync.py --id S1.7 --slug localization`
- [ ] ответ пользователю: какой архив распаковать, что проверить на M1

## Журнал (новое — внизу; пишется через --note)
- 2026-10-26 07:50–08:02 UTC — агент 1 (сессия 9a): сверка с GitHub `355ab53` = v0.0.4 → коммит `835f1ff` (тег v0.0.4); правка `tools/placeholder_pngs.py` (`54a7f3c`); bundle. Начал S1.7 (сбор ключей из данных). Ответ оборвался; PROGRESS не обновлён.
- 2026-10-26 08:44–08:59 UTC — агент 2 (сессия 9b): шрифты Kurale/Nunito (через `pptx_fonts` → Google Fonts), `strings.csv`, humanizer ru/en, `humanized.txt`. Ничего не закоммитил и не записал: работа лежала только в `/tmp` и пропала бы при перезапуске песочницы. Ответ оборвался.
- 2026-10-26 09:07 UTC — агент 3 (сессия 9c): нашёл работу агента 2 в `/tmp`, закоммитил (`460c08d`); THIRD_PARTY, project.godot, тема (`S1.7 wip` следующим коммитом). Введены этот файл и автосохранение `pod_sync.py --quick --note`.
- 2026-10-26 09:14 UTC — агент 3: введены HANDOFF.md, правило §0 в AGENTS.md (D19) и сохранение одной командой pod_sync.py --quick --note. Дальше: экран загрузки
- 2026-10-26 09:15 UTC — экран загрузки scenes/loading/loading_screen.tscn/.gd (GAME_TITLE + LOADING_TEXT, «дыхание» надписи, hide_screen()). Дальше: подключить в main.tscn/main.gd + смена языка по настройке
- 2026-10-26 09:15 UTC — Main: экран загрузки подключён (main.tscn, @export loading_screen), язык применяется после Platform.initialize и после загрузки сохранения, смена настройки языка — сразу через EventBus.settings_changed. Дальше: scenes/debug/l10n_check
- 2026-10-26 09:16 UTC — проверочная сцена scenes/debug/l10n_check.tscn/.gd: переводы подключены, тексты всех ключей ru/en, глифы шрифтов темы, тема проекта, смена языка; образцы на экране, язык переключается таймером. Дальше: правило валидатора L011
- 2026-10-26 09:16 UTC — валидатор: правило L011 (ключ из *_key в .tres/.tscn есть в strings.csv), фикстура bad/data/missing_key.tres, самотест 71/71; проверено на порче rank_1.tres. Дальше: документы S1.7
- 2026-10-26 09:17 UTC — документы: ART_STYLE §5 (шрифты решены), GDD §13, PLAN S1.7 [x], README (l10n_check, язык для проверки). Дальше: PROGRESS + DEVLOG, затем коммит S1.7 и тег v0.1.0
- 2026-10-26 09:17 UTC — PROGRESS переписан под M1 (что проверить пользователю, следующий шаг S2.1). Дальше: DEVLOG сессии 9, коммит S1.7, тег v0.1.0, полный pod_sync
- 2026-10-26 09:18 UTC — DEVLOG: запись сессии 9. Дальше: финальный коммит S1.7, тег v0.1.0, pod_sync --id S1.7 --slug localization
