# HANDOFF — что делается прямо сейчас (читать ПЕРВЫМ)

> Этот файл переписывается после **каждого** шага, а не в конце подэтапа. Одна команда сохраняет всё:
> `python tools/pod_sync.py --quick --note "что сделано"`. Она дописывает строку в журнал ниже,
> коммитит всё незакоммиченное, обновляет bundle и кладёт этот файл в корень Pod (`/files/pod/HANDOFF.md`).
> Ответ агента может оборваться в любой момент. Чего нет в Pod, следующий агент не увидит.

## Сейчас
- **Сессия 16 (2026-10-26), Pod «новая игра» снова пуст.** Агент «па» (сессия 16a) восстановил рабочую копию из ZIP GitHub `0203552` («0.1.2» — пользователь поставил v0.1.2 и запушил `*.uid` Godot для S2.2) → коммит `sync: GitHub 0203552 (0.1.2)`, теги `gh-0203552`, `v0.1.2`; валидатор 0 ошибок. Его ответ оборвался до сохранения в Pod.
- Сессия 16c (агент «rt», 20:11 UTC): нашёл несохранённые IngredientItem.set_crumble, ZoneGauge.shake, mortar_juice.gd → сохранил; подключил MortarJuice в mortar.tscn; PIL-макет порошка/кольца — ок; grind_check 44 проверки; документы; **S2.3 закрыт — v0.1.3**, полная выдача `outbox/alchemist_update_gh-0203552_to_v0.1.3.zip`. Следующий агент: ждать проверки пользователем (PROGRESS «Ждём»), затем S2.4.
- Сессия 16b: продолжала с той же `/tmp/work/repo`. Output проверочных сцен (`grind_check`, `shelf_check`) пользователь не присылал, замечаний по скорости помола нет → начинаем **S2.3 Juice v1**.

## Чек-лист S2.3 (v0.1.3) — Juice v1 ступки
- [x] сохранить базу в Pod (bundle + HANDOFF)
- [x] прочитать код ступки/пестика/жеста/шкалы, SfxComponent, AudioDirector, Platform, настройки
- [x] звуки: хруст ×4+ (`sfx_grind_crunch_*`), звон «идеально» (`sfx_perfect`), «пфф» перетёр (`sfx_overgrind`) — synth_sfx.py, AUDIO.md
- [x] крошки-частицы на каждую ¼ круга (CPUParticles2D, цвет смеси), облако пыли при p = 1
- [x] squash пестика на ¼ круга (SquashStretch)
- [x] шейдер распада ингредиентов по помолу + горка порошка (шейдер, цвет смеси)
- [x] вибрация на ¼ круга через Platform (настройка «вибрация»), шкала трясётся при p = 1, кольцо/звон при входе в «идеально»
- [x] проверочная сцена: дополнить `grind_check` (juice-проверки)
- [x] документы: PROGRESS, DEVLOG, PLAN, COMPONENTS, AUDIO, README; версия 0.1.3; коммит/тег; полная выдача `--base gh-0203552`

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
- 2026-10-26 11:34 UTC — сессия 10: восстановлено с GitHub df4d87b, уборка S2.0 (копия в tools/, файлы «Турбовендетты», дубли шрифтов/темы). Дальше: ассеты S2.1
- 2026-10-26 11:49 UTC — сессия 11: пользователь подтвердил удаление всех трёх групп лишних файлов и что проверка M1 в Godot 4.7 прошла. GitHub HEAD всё ещё df4d87b (nocache). Начинаю S2.1: ассеты
- 2026-10-26 11:54 UTC — S2.1 ассеты: временные prop_mortar_bowl, prop_pestle, prop_shelf_slot (в GDD было prop_shelf), ui_trash, icon_prop_* ×6 (белые, тон — PropertyData.color); промпты P-PROP-04, P-UI-06, P-UI-07; иконки в data/properties/*.tres. Дальше: сцены ячейки полки и полки
- 2026-10-26 11:59 UTC — S2.1: Draggable — pass_horizontal/press_passed (жест вбок отдаётся ленте), drop_on, is_busy. Дальше: ingredient_item.tscn
- 2026-10-26 14:02 UTC — сессия 12: найдена несохранённая работа — scenes/ingredient/ingredient_item.tscn/.gd (ингредиент полки: Draggable, Tooltip, Flash отказа, масштаб в станции). Дальше: shelf_slot + shelf
- 2026-10-26 14:08 UTC — S2.1: шейдер подсветки цели components/drop_target/drop_glow.gdshader + drop_glow.tscn (мягкий пульсирующий овал, яркость — modulate от DropTarget). Дальше: shelf_slot
- 2026-10-26 14:12 UTC — S2.1: scenes/shelf/shelf_slot.tscn/.gd — ячейка полки (ящичек, ингредиент, до 3 иконок свойств; всегда полна: новый pop_in после приёма станцией; take_back — вернувшийся летит и сливается; жест вбок отдаётся ленте). Дальше: shelf.tscn/.gd
- 2026-10-26 14:13 UTC — S2.1: scenes/shelf/shelf.tscn/.gd — полка: сетка (ландшафт) / лента с прокрутткой, инерцией и колесом (портрет), таяние ячеек у края, take_back, scroll_to; слушает EventBus.layout_changed. Дальше: ступка (mortar) + корзина
- 2026-10-26 14:15 UTC — S2.1: корзина scenes/stations/station_trash.tscn/.gd (кнопка «вылить», приглушена у пустой станции); derive.py front + assets/props/prop_mortar_bowl_front.png (передний край чаши — ингредиенты лежат внутри), строка в ASSET_REGISTRY. Дальше: mortar.tscn/.gd
- 2026-10-26 15:57 UTC — сессия 13: найден несохранённый scenes/stations/mortar/mortar.gd (приём ≤2/3, цена при броске, возврат тапом и корзиной, огоньки слотов). Дальше: проверка API компонентов, mortar.tscn
- 2026-10-26 16:01 UTC — S2.1: scenes/stations/mortar/mortar.tscn — чаша/содержимое/передний край, пестик, места на 2 и 3, огоньки, DropTarget с подсветкой, корзина, StateMachine Empty⇄Loaded; в mortar.gd переходы без повторного входа. Дальше: проверка раскладки картинкой, shelf_check
- 2026-10-26 16:03 UTC — S2.1: mortar.gd — перенос в чашу и возврат по тапу кадром позже (не трогаем узел посреди его же обработки касания). Дальше: scenes/debug/shelf_check
- 2026-10-26 16:05 UTC — S2.1: scenes/debug/shelf_check.tscn/.gd — мастерская + полка (6 ингредиентов) + ступка; 27 автопроверок (полка, иконки, подсветка, приём/цена/полно/монеты, возврат тапом и корзиной, улучшение, лента) → «SHELF: x/y OK» + памятка. Дальше: промпты/реестр, humanizer, документы, выдача v0.1.1
- 2026-10-26 16:06 UTC — S2.1: mortar — вместимость по умолчанию = число мест slots_two, перекладка при смене вместимости; чек-лист: данные/сцены/перенос/тексты/проверочная сцена [x]. Дальше: документы (PROGRESS, DEVLOG, PLAN, COMPONENTS), версия 0.1.1, выдача
- 2026-10-26 16:07 UTC — S2.1: версия 0.1.1, PLAN [x], README (shelf_check), COMPONENTS §2.1 (сущности S2). Дальше: PROGRESS, DEVLOG, коммит/тег, полная выдача
- 2026-10-26 17:36 UTC — сессия 14: Pod пуст; восстановлено с GitHub 9888a1e целиком (ZIP main, с PNG/TTF); возвращён tools/.gdignore (валидатор 0 ошибок). Дальше: S2.2 — чтение STATIONS §1.1
- 2026-10-26 17:41 UTC — S2.2: решения по жесту/шкале/пестику записаны в HANDOFF; дальше — код grind_gesture
- 2026-10-26 17:43 UTC — S2.2: компоненты GrindGesture (жест→круги, тапы ≤12/с) и ZoneGauge (шейдерная шкала с зоной) написаны, валидатор OK; дальше — пестик и ступка
- 2026-10-26 17:46 UTC — S2.2: mortar.gd/tscn — состояния Grinding/Ground, GrindArea, GrindGesture, Gauge, Pestle в чаше; валидатор OK. Дальше: макет картинкой, затем grind_check.tscn
- 2026-10-26 18:03 UTC — сессия 15: найдена несохранённая правка позы пестика (mortar.tscn: Pestle 72,-256, rot 0.58). Дальше: PIL-макет позы пестика и места шкалы
- 2026-10-26 18:08 UTC — S2.2: PIL-макет позы пестика (покой + 5 поз помола) и места шкалы — ок, правок не нужно. Дальше: тексты S2.2, затем grind_check.tscn
- 2026-10-26 18:10 UTC — S2.2: scenes/debug/grind_check.tscn/.gd — автопроверки помола (скачок, круг, Ground-отказ, тапы и шквал, потолок скорости, уход пальца, пауза, шкала/извлечение/смесь, корзина). Дальше: документы S2.2
- 2026-10-26 18:12 UTC — S2.2: документы (PROGRESS, DEVLOG, PLAN, COMPONENTS, README), версия 0.1.2. Дальше: коммит S2.2, тег v0.1.2, полная выдача
- 2026-10-26 20:00 UTC — сессия 16b: база gh-0203552 (v0.1.2 у пользователя), начат S2.3 Juice v1 — чек-лист в HANDOFF
- 2026-10-26 20:04 UTC — S2.3: звуки помола (хруст ×5, глухой ×2, звон «идеально», «пфф») + восстановлен tools/audio/synth_sfx.py, AUDIO.md. Дальше: шейдеры распада и порошка
- 2026-10-26 20:05 UTC — S2.3: Platform.vibrate (настройка shake, пауза, троттлинг, сигнал vibrated), SfxComponent.pitch_jitter + AudioDirector.play_sfx(jitter). Дальше: шейдеры распада и порошка
- 2026-10-26 20:07 UTC — S2.3: шейдеры — ingredient.gdshader (вспышка + распад crumble), powder.gdshader (горка порошка), fx_ring.gdshader (кольцо «идеально») + материалы. Дальше: FxRing, BurstParticles, fx_crumbs/fx_dust
- 2026-10-26 20:08 UTC — S2.3: компонент BurstParticles (пул CPUParticles2D), сцены scenes/fx/fx_crumbs.tscn, fx_dust.tscn, FxRing (fx_ring.tscn/gd). Дальше: IngredientItem.set_crumble, ZoneGauge.shake, MortarJuice
- 2026-10-26 20:11 UTC — сессия 16c: найдена несохранённая работа — IngredientItem.set_crumble (+ingredient_material), ZoneGauge.shake, mortar_juice.gd. Дальше: проверка API, подключение MortarJuice в mortar.tscn
- 2026-10-26 20:15 UTC — S2.3: MortarJuice подключён в mortar.tscn (Powder, Crumbs, Dust, Ring, PestleSquash, Sfx×4, Juice); облачко пыли — по приземлению ингредиента; G009 в mortar_juice; починен битый символ в комментарии grind_gesture.gd. Дальше: PIL-макет порошка/кольца
- 2026-10-26 20:16 UTC — S2.3: PIL-макет (порошок по горлышку, распад, кольцо по краю чаши) — правок не нужно; чек-лист HANDOFF обновлён. Дальше: juice-проверки в grind_check
- 2026-10-26 20:18 UTC — S2.3: grind_check — 12 juice-проверок (облачко при приземлении, крошки на каждую ¼, squash, вибрация и её выключение, распад/порошок, кольцо, перетёр, глухой помол на p=1, сброс распада) + памятка 9–12. Дальше: документы, версия 0.1.3, выдача
- 2026-10-26 20:20 UTC — S2.3: документы — COMPONENTS (BurstParticles, ZoneGauge.shake, Flash/ingredient.gdshader, SfxComponent.pitch_jitter, MortarJuice, FxRing), PLAN S2.3 [x], README GRIND 44/44, версия 0.1.3. Дальше: PROGRESS, DEVLOG, коммит/тег, полная выдача
- 2026-10-26 20:21 UTC — S2.3: PROGRESS (v0.1.3, ждём GRIND 44/44, следующий шаг S2.4), DEVLOG сессия 16. Дальше: коммит S2.3, тег v0.1.3, полная выдача --base gh-0203552
