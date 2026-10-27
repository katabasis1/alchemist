# HANDOFF — что делается прямо сейчас (читать ПЕРВЫМ)

> Этот файл переписывается после **каждого** шага, а не в конце подэтапа. Одна команда сохраняет всё:
> `python tools/pod_sync.py --quick --note "что сделано"`. Она дописывает строку в журнал ниже,
> коммитит всё незакоммиченное, обновляет bundle и кладёт этот файл в корень Pod (`/files/pod/HANDOFF.md`).
> Ответ агента может оборваться в любой момент. Чего нет в Pod, следующий агент не увидит.

## Сейчас
- **Сессия 18 (2026-10-27): S2.4 мини-заказ, будет v0.1.6.** S2.3b (v0.1.5) пользователь принял («Принято, делай S2.4», GitHub `776c702` = 0.1.5).
- **Новый Pod** («новая папка»): bundle, outbox, inbox/art прошлого Pod недоступны. Рабочая копия восстановлена с GitHub `776c702` по §2.3: 426 текстовых файлов через веб-инструмент, вызванный из песочницы (`dsbx tools … webbrowser`, ответы не идут в контекст), hash-object совпали все; коммит `sync: GitHub 776c702`, теги `gh-776c702`, `v0.1.5`. История агента до v0.1.5 потеряна вместе со старым Pod — не страшно, GitHub = источник истины.
- Бинарники (PNG/OGG/TTF/translation) в рабочей копии — заглушки и пересинтезированные файлы (`placeholder_pngs.py`, `fx_textures.py`, `synth_sfx.py`, пустые файлы), все в `.git/info/exclude`.
- Чек-лист S2.4 — ниже. Сессия 19 (2026-10-27, вечер): продолжение — прошлый агент только прочитал код, файлов не менял; GitHub HEAD всё ещё `776c702`.
- Сессия 20 (2026-10-27, вечер): продолжение 19 (у неё остались несохранённые PNG баночки и пузыря — сохранены). GitHub HEAD `776c702`, inbox пуст.
- Сессия 21 (2026-10-27, 16:32 UTC): продолжение 20; рабочая копия цела (HEAD f88c351 = LAST_SYNC), GitHub HEAD `776c702`, inbox нет. Дальше HUD: CoinCounter + полёт монет.

## Чек-лист S2.4 (v0.1.6) — мини-заказ
- [x] план и чек-лист
- [x] OrderJudge — оценка смеси по заказу (эффект / сила / чистота, «безупречно», оплата): первая версия S5.3; GameState.start_order/finish_order
- [x] CarryVessel (баночка мази) — перенос содержимого ступки: тянуть за тело чаши или «тап — тап»; Mortar.hand_off
- [x] Client — портрет, пузырь заказа иконками (свойство × звёзды силы, кристалл чистоты), приём баночки, реакция (рад / качает головой), уход и приход
- [x] HUD — счётчик монет (прокрутка цифр; вздрагивает на «монет не хватает»), полёт монет со шлейфом — `scenes/hud/`
- [x] OrderDesk — очередь заказов S2.4 (FTUE 1–2 + заказы пекарши), текущий заказ в сохранении — `scenes/client/order_desk.*`
- [x] Workshop — полка + ступка + клиент + HUD в лавке, ландшафт и портрет; main без изменений. Фон вынесен в `workshop_room.tscn` (его берут grind/juice/shelf_check), клиент — дочерний `Room/ClientSpot` (за прилавком)
- [x] графика: баночка, пузырь, кристалл чистоты — временные + промпты; звуки: монеты, «вжух», «уф» (+ sfx_happy)
- [ ] order_check (проверочная сцена), валидатор, документы, v0.1.6, выдача `--base gh-776c702`

## Чек-лист S2.3a (v0.1.4) — правки ступки
- [x] база с GitHub `0ee28a7`; финальные ступка и пестик в холсты (`tools/art/fit_final.py`); передний край по нижней дуге горлышка
- [x] референсы содержимого: `docs/art/refs/ref_mortar_herbs_whole|herbs_crushed|powder_heap.jpg`
- [x] godotshaders.com: обзор (код там грузится скриптом — берём приёмы, пишем своё), список в THIRD_PARTY
- [x] геометрия горлышка → общие параметры (центр, полуоси, глубина) для порошка, пестика, кольца (ColorRect Powder = горлышко)
- [x] пестик: головка в полости, ручка через задний край; позы помола — PIL-макет
- [x] порошок: шейдер горки в полости (raymarch по полости, тон-заливка, зерно, искры, налёт на стенках, свечение «идеально»), numpy-превью; MortarJuice/grind_check под новые параметры
- [x] травы: распад с обломками и светящейся каёмкой (ingredient_material.tres — сверить параметры)
- [x] частицы: текстуры искры/мягкой точки, крошки-обломки, магические искорки, пыль, всплеск «идеально»; FX кольца + лучей
- [x] превью-картинки для пользователя (покой / травы / помол / горка / «идеально») — `python tools/art/mortar_preview.py --sheet …`, лист в беседе `mortar_preview_S2.3a.jpg`
- [x] grind_check (47), валидатор, документы, версия 0.1.4, выдача `--base gh-0ee28a7`
- [ ] приёмка пользователем (Output `GRIND: 47/47 OK` + замечания на глаз) — до неё S2.4 не начинаем
- Отзыв на v0.1.4 (2026-10-27 14:43 UTC): «очень хорошо, почти идеально»; одно замечание — в покое пестик «проваливается» в ступу (у правого края горлышка часть пестика уходит под передний край). GitHub `ab70b01` = 0.1.4.
- [x] S2.3b: синхронизация с GitHub ab70b01 — `fx_rays.gdshader.uid` и 4 `assets/fx/*.png.import` (hash-object совпали), ветка sync/2026-10-27b → master, тег `gh-ab70b01`; деревья assets/ и scenes/ = GitHub
- [x] S2.3b: поза покоя пестика (20,-216)/0.5 — ручка лежит на заднем крае, ничего не уходит под передний край (макет `pestle_rest_fix_S2.3b.jpg` в беседе)
- [x] S2.3b: позы помола — тот же дефект у стенок при 48×9 / 0.5 → tip_reach 44×9, max_lean 0.35; `mortar_preview.py --pestle-check` — 3/3 OK
- [x] S2.3b: документы, v0.1.5, выдача `--base gh-ab70b01`
- [ ] приёмка S2.3b пользователем — до неё S2.4 не начинаем

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
- 2026-10-27 12:44 UTC — сессия 17 (агент g): восстановлено из tar.gz GitHub 0ee28a7 (0.1.3), теги gh-0ee28a7, v0.1.3; финальные ступка и пестик от пользователя → Pod inbox/art/. Задача: правки S2.3 (слои ступки, линия среза, порошок, частицы/шейдеры, финальная графика)
- 2026-10-27 12:48 UTC — финальные ступка/пестик вписаны в холсты контракта (tools/art/fit_final.py, пестик поставлен вертикально); эллипс горлышка найден по маске полости (холст 250.0,112.4,169.2×79.9); BowlFront пересрезан по нижней дуге горлышка. Дальше: референсы содержимого (генерация), затем шейдеры/частицы
- 2026-10-27 12:49 UTC — референсы содержимого ступки (ImageGen по финальной ступке): целые травы, полупомол, горка порошка → docs/art/refs/*.jpg. Дальше: шейдер горки порошка (raymarch heightfield в полости), распад трав, частицы
- 2026-10-27 13:10 UTC — 17h: чек-лист S2.3a в HANDOFF; godotshaders.com просмотрен (код грузится JS — пишем своё по приёмам: glitter, glowing burn edge, shockwave, sun pulse glow, god rays, magic circle). Дальше: геометрия горлышка, пестик
- 2026-10-27 13:14 UTC — 17h: пестик — головка в полости (кончик у дна BowlBottom -2,-207, низ прячет передний край), ручка через задний край; Pestle.tip_center; поза покоя 16,-212 / 0.45; tip_reach 48×9, max_lean 0.5; tools/art/mortar_preview.py (база макета). Дальше: шейдер горки порошка + numpy-превью; MortarJuice/grind_check под новые параметры
- 2026-10-27 13:20 UTC — 17h: powder.gdshader переписан — горка лежит В полости (луч по полуэллипсоиду, поле высот, 3 тона, зерно, кусочки трав, налёт на стенках, искры, свет «идеально»), numpy-копия shade_powder в mortar_preview.py; поза покоя пестика 44,-214/0.55 (горка видна). Дальше: травы (распад) + референс
- 2026-10-27 13:53 UTC — 17i: найдена несохранённая работа 17h — ingredient.gdshader (распад на куски Вороного, трещины, оседание, искристая каёмка), места Slots в полости, правки powder.gdshader и mortar_preview.py (shade_crumble). Дальше: проверка превью трав, частицы
- 2026-10-27 13:56 UTC — 17i: порошок подключён к сцене: ColorRect Powder = горлышко (-124.65,-334.6)-(119.75,-221.9), powder_material.tres с новыми параметрами; MortarJuice задаёт amount/flecks/coat/glow/sparkle/spin, перетёр = цвет пыли + без искр; grind_check обновлён; THIRD_PARTY. Дальше: текстуры частиц и сцены fx
- 2026-10-27 13:57 UTC — 17i: ingredient_material.tres сверен с новым ingredient.gdshader (glint_color, crack_width, ragged, spread, sink); HANDOFF чек-лист обновлён. Дальше: текстуры частиц (искра-звезда, мягкий ореол, обломки трав 4 кадра) и сцены fx
- 2026-10-27 14:00 UTC — 17i: tools/art/fx_textures.py — процедурные текстуры частиц assets/fx/fx_spark|fx_glow|fx_puff|fx_flakes.png (статус proc в реестре). Дальше: BurstParticles с дочерними слоями, сцены fx_crumbs (обломки+искры+пыльца), fx_dust (облака), fx_sparkle_burst, fx_motes
- 2026-10-27 14:01 UTC — 17i: BurstParticles — дочерние CPUParticles2D как слои (tint_layers); сцены fx_crumbs (обломки 4 кадра + искры + пыльца), fx_dust (облака fx_puff), fx_sparkle_burst (звёзды, вспышка, светлячки — «идеально»), fx_motes (Idle/Perfect — светлячки над порошком). Генератор /tmp/gen/fxgen.py (одноразовый). Дальше: подключить к mortar.tscn и MortarJuice, затем шейдеры кольца и лучей
- 2026-10-27 14:03 UTC — 17i: шейдеры волшебства: fx_ring.gdshader (волна по горлышку: белое ядро, ореол, след, рябь, мерцающие искры, вспышка, blend_add), fx_rays.gdshader + fx_rays.tscn/material (веер лучей из чаши); FxRing ведёт спутников extras общим progress, ring_sec 0.9. Дальше: mortar.tscn — Rays, SparkleBurst, Motes, размеры Ring; MortarJuice — светлячки и всплеск
- 2026-10-27 14:04 UTC — 17i: mortar.tscn — Motes (Idle/Perfect), Rays, Ring по горлышку ×1.6 с extras=Rays, SparkleBurst; MortarJuice: светлячки (motes_from 0.25), всплеск на входе в «идеально»; grind_check +2 проверки. Дальше: превью-картинки для пользователя (mortar_preview.py main: частицы, кольцо, лучи)
- 2026-10-27 14:13 UTC — S2.3a: mortar_preview.py — парсер CPUParticles2D из .tscn, копии fx_ring/fx_rays, кадры rest/land/grind/heap/perfect/overgrind (main). Дальше: смотреть кадры, тюнинг, превью пользователю
- 2026-10-27 14:14 UTC — S2.3a: лучи/волна больше не обрезаются краями прямоугольника (side_fade, edge_fade), убрано белое ядро лучей; вспышка искр 0.75→0.5. Дальше: смотреть лист кадров
- 2026-10-27 14:15 UTC — S2.3a: частицы и превью закрыты (лист mortar_preview_S2.3a.jpg). Дальше: grind_check, валидатор, документы, v0.1.4
- 2026-10-27 14:15 UTC — S2.3a: grind_check — проверка лучей (спутники FxRing); валидатор OK. Дальше: документы, v0.1.4
- 2026-10-27 14:17 UTC — S2.3a: ASSET_REGISTRY (чаша/пестик/передний край — final), PLAN S2.3a, README GRIND 47/47, версия 0.1.4. Дальше: PROGRESS, DEVLOG, inbox→_done, коммит/тег, выдача --base gh-0ee28a7
- 2026-10-27 14:18 UTC — S2.3a: PROGRESS (v0.1.4, ждём приёмку, GRIND 47/47), DEVLOG сессии 17; inbox/art → inbox/_done/2026-10-27. Дальше: коммит S2.3a, тег v0.1.4, выдача --base gh-0ee28a7
- 2026-10-27 14:24 UTC — S2.3a выдан: v0.1.4 (c0e42f4), outbox/alchemist_update_gh-0ee28a7_to_v0.1.4.zip (40 файлов, с PNG), patches/v0.1.4. Ждём приёмку пользователя: GRIND 47/47 + замечания на глаз; до неё S2.4 не начинаем
- 2026-10-27 14:44 UTC — S2.3b начат: отзыв на 0.1.4 — пестик в покое проваливается под передний край; GitHub ab70b01 = 0.1.4. Дальше: синхронизация с GitHub, затем поза покоя
- 2026-10-27 14:46 UTC — S2.3b: синхронизация с GitHub ab70b01 (uid + import fx), тег gh-ab70b01. Дальше: поза покоя пестика
- 2026-10-27 14:49 UTC — S2.3b: макет 4 поз покоя (_rest_cmp.jpg): текущая (44,-214)/0.55 — обойма уходит под правый край; кандидаты A (20,-216)/0.5, B (16,-214)/0.55 чистые. Дальше: проверить позы помола
- 2026-10-27 14:50 UTC — S2.3b: поза покоя пестика (20,-216)/0.5 — обойма и ручка над задним краем; помол tip_reach 44×9, max_lean 0.4 — на крайних позициях обойма не уходит под боковой край (макеты _rest_cmp/_grind_cmp). Дальше: --pestle-check в mortar_preview, превью, документы
- 2026-10-27 14:51 UTC — S2.3b: mortar_preview.py --pestle-check (дерево пестика не под передним краем с запасом 6 px, головка в покое не под боковым краем) — все 3 позы OK; max_lean 0.35. Дальше: превью rest, документы, v0.1.5
- 2026-10-27 14:52 UTC — S2.3b: документы (PLAN, PROGRESS, DEVLOG), версия 0.1.5, валидатор OK. Дальше: коммит/тег v0.1.5, выдача --base gh-ab70b01
- 2026-10-27 15:38 UTC — сессия 18: новый Pod, рабочая копия восстановлена с GitHub 776c702 (426 файлов, hash-object OK), S2.3b принят пользователем. Дальше: чек-лист S2.4
- 2026-10-27 16:00 UTC — S2.4: старт сессии 19, чек-лист S2.4 в HANDOFF; дальше OrderJudge
- 2026-10-27 16:05 UTC — S2.4: OrderJudge (scenes/client/order_judge.gd) + GameState.start_order/finish_order; дальше CarryVessel в ступке
- 2026-10-27 16:12 UTC — сессия 20: найдена несохранённая работа 19 — временная графика prop_jar_ointment.png (256×256) и ui_order_bubble.png (512×320) после cutout; дальше реестр/промпты, CarryVessel + Mortar.hand_off
- 2026-10-27 16:16 UTC — S2.4: реестр и промпты P-PROP-05 (баночка), P-UI-08 (пузырь), P-UI-09 (кристалл чистоты, icon_purity 128×128); дальше генерация кристалла, затем CarryVessel
- 2026-10-27 16:17 UTC — S2.4: временный icon_purity.png (128×128, cutout); графика баночки/пузыря/кристалла готова; дальше CarryVessel + Mortar.hand_off
- 2026-10-27 16:18 UTC — S2.4: scenes/vessel/carry_vessel.tscn/.gd — баночка (fill/show_up/stow, mixture+grind); дальше Mortar: BodyArea + VesselDrag + hand_off
- 2026-10-27 16:20 UTC — S2.4: Mortar — перенос: body_area (тело чаши) + VesselDrag (Draggable, kind potion) + Vessel; hand_off/handed_off, баночка прячется при возврате; валидатор OK. Дальше OrderTemplate.needs_perfect_grind (FTUE 1–3) и Client
- 2026-10-27 16:22 UTC — S2.4: needs_perfect_grind в OrderTemplate (ftue_1–3 = true); scenes/client/client.gd (приход, пузырь иконками, приём баночки, реакция, уход). Дальше client.tscn + order_icon.tscn
- 2026-10-27 16:24 UTC — S2.4: звуки sfx_whoosh/happy/oof/coin_1–3 (synth_sfx.py, рецепты добавлены), AUDIO.md; дальше client.tscn + order_icon.tscn
- 2026-10-27 16:24 UTC — S2.4: client.tscn (портрет, пузырь с рядами иконок, DropTarget potion, OrderJudge, StateMachine Away→Arriving→Waiting→Reacting→Leaving, звуки) + order_icon.tscn; валидатор OK. Дальше HUD: CoinCounter + полёт монет
- 2026-10-27 16:32 UTC — сессия 21: старт, рабочая копия цела (f88c351), GitHub 776c702, inbox нет; дальше HUD CoinCounter
- 2026-10-27 16:37 UTC — HUD: scenes/hud/coin_counter.gd+.tscn (прокрутка, hold/release монет в полёте, deny — дрожь+красный); дальше flying_coin + coin_flight + hud
- 2026-10-27 16:39 UTC — HUD: flying_coin (шлейф CPUParticles2D, поворот ребром), coin_flight (пул, веер, дуга Безье, coin_landed), hud.tscn (CanvasLayer 10, fly_coins/deny_coins); дальше OrderDesk
- 2026-10-27 16:42 UTC — OrderDesk (scenes/client/order_desk.gd+.tscn): сохранённый заказ → FTUE 1–2 (ftue_limit) → заказы пекарши по весу и открытым свойствам; оплата+репутация → finish_order(ftue_done) → Hud.fly_coins. Client: coin_point, is_present, безопасный уход после радости. DataCatalog.order(id), OrderJudge.reputation_for. Дальше Workshop
- 2026-10-27 16:45 UTC — Workshop собран: workshop_room.tscn (фон, прилавок, ClientSpot) + workshop.tscn (Client в Room/ClientSpot, Mortar, Shelf, OrderDesk, Hud, LayoutSwitcher), workshop.gd (item_released→take_back, coins→deny). Debug-сцены берут workshop_room. Shelf перестраивается на state_reset. Дальше order_check
