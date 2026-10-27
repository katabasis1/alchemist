## GameState — сохраняемое состояние игрока (GDD §11) и единственное место, где оно меняется.
## Каждое изменение, которое надо записать, просит SaveService через EventBus.save_requested.
## Сигналы: state_reset() — состояние заменено целиком (новая игра или загрузка).
## Зависимости: EventBus, DataCatalog (@export: стартовые значения новой игры; сцены берут данные через GameState.catalog),
##   GrimoireRules (рецепт зелья, страницы Гримуара, разбор Гримуара из сохранения).
## На диск не пишет — это делает SaveService.
extends Node

signal state_reset

## Версия формата сохранения. Поднимать при несовместимых изменениях и дописывать _migrate().
const SAVE_VERSION: int = 1
const KEY_VERSION: String = "version"

## Ключи настроек.
const SETTING_MUSIC: String = "music"
const SETTING_SFX: String = "sfx"
const SETTING_UI: String = "ui"
const SETTING_MUTED: String = "muted"
## Тряска камеры и вибрация (GDD-2 §2: можно выключить в настройках).
const SETTING_SHAKE: String = "shake"
## Пусто — язык платформы.
const SETTING_LOCALE: String = "locale"

## Причины записи (для журнала и отладки).
const REASON_COINS: StringName = &"coins"
const REASON_SETTINGS: StringName = &"settings"
const REASON_RESET: StringName = &"reset"
const REASON_ORDER: StringName = &"order"
const REASON_GRIMOIRE: StringName = &"grimoire"

## Ключи текущего заказа (current_order): id клиента и шаблона заказа.
const ORDER_CLIENT: String = "client"
const ORDER_TEMPLATE: String = "order"

## Все данные игры (data/catalog.tres). Стартовые значения новой игры берутся отсюда.
@export var catalog: DataCatalog

var coins: int = 0
var crystals: int = 0
var reputation: int = 0
var rank: int = 0
## Купленные станции, приборы и улучшения (id из ToolData).
var purchases: Array[StringName] = []
## Открытые ингредиенты (id из IngredientData).
var unlocked_ingredients: Array[StringName] = []
## Гримуар (GDD §3.5): id рецепта (строка) → страница GrimoireRules — целые KEY_BREWS, KEY_BEST_STRENGTH,
## KEY_BEST_PURITY, KEY_FLAWLESS. Рецепт открыт — страница есть. Меняется только в record_brew.
var grimoire: Dictionary = {}
var day: int = 1
var order_in_day: int = 0
var streak_3star: int = 0
## Текущий заказ: после перезагрузки приходит тот же клиент с тем же заказом (GDD §11).
## {ORDER_CLIENT: id клиента, ORDER_TEMPLATE: id шаблона}; пусто — заказа нет.
var current_order: Dictionary = {}
var ftue_step: int = 0
## Ежедневная награда: {"chain_day": int, "last_claim": "YYYY-MM-DD"}.
var daily_reward: Dictionary = {}
## Бесплатные подсказки и подарки: flag → дата последнего использования "YYYY-MM-DD".
var free_flags: Dictionary = {}
var settings: Dictionary = {}


func _ready() -> void:
	_set_defaults()


## Новая игра: всё по умолчанию. Запись — только если просили (после загрузки пустого сохранения не нужна).
func new_game(save_now: bool = false) -> void:
	_set_defaults()
	state_reset.emit()
	if save_now:
		request_save(REASON_RESET)


func request_save(reason: StringName) -> void:
	EventBus.save_requested.emit(reason)


# --- изменения состояния ----------------------------------------------------

func add_coins(delta: int) -> void:
	if delta == 0:
		return
	coins = maxi(coins + delta, 0)
	EventBus.coins_changed.emit(coins, delta)
	request_save(REASON_COINS)


## Списать монеты, если хватает. Возвращает true, если списано.
func try_spend_coins(cost: int) -> bool:
	if cost < 0 or cost > coins:
		return false
	add_coins(-cost)
	return true


## Клиент пришёл с заказом: запомнить его, чтобы перезагрузка не меняла заказ (GDD §5.4).
func start_order(client_id: StringName, order_id: StringName) -> void:
	current_order = {ORDER_CLIENT: String(client_id), ORDER_TEMPLATE: String(order_id)}
	request_save(REASON_ORDER)


## Заказ закрыт (GDD §5.3): оплата, репутация, серия 3★, счёт заказов дня — одной записью.
## three_stars — оценка 3★: серия растёт, иначе обнуляется. ftue_done — закрыт обучающий заказ: шаг FTUE +1.
## Счётчик монет HUD узнаёт об оплате из coins_changed.
func finish_order(pay: int, reputation_gain: int, three_stars: bool, ftue_done: bool = false) -> void:
	coins = maxi(coins + pay, 0)
	reputation += maxi(reputation_gain, 0)
	streak_3star = streak_3star + 1 if three_stars else 0
	order_in_day += 1
	current_order = {}
	if ftue_done:
		ftue_step += 1
	if pay != 0:
		EventBus.coins_changed.emit(coins, pay)
	request_save(REASON_ORDER)


## Зелье отдали клиенту, даже если он отказался (GDD §3.5): рецепт узнаётся по значимым свойствам смеси, его страница
## открывается (EventBus.recipe_discovered), варок +1, рекорды силы и чистоты и счёт «безупречных» обновляются;
## страница, которая только что стала золотой, — EventBus.grimoire_page_golden. «Странная смесь» страницы не даёт
## и ничего не пишет. Возвращает id узнанного рецепта, &"" — «Странная смесь».
func record_brew(mixture: Dictionary) -> StringName:
	var recipe: RecipeData = GrimoireRules.recognize(mixture, catalog)
	if recipe == null:
		return &""
	var key: String = String(recipe.id)
	var discovered: bool = not grimoire.has(key)
	var before: Dictionary = GrimoireRules.parse_page(grimoire.get(key))
	var page: Dictionary = GrimoireRules.after_brew(before, GrimoireRules.brew(mixture, recipe, catalog.economy))
	grimoire[key] = page
	if discovered:
		EventBus.recipe_discovered.emit(recipe.id)
	if GrimoireRules.is_golden(page, catalog.economy) and not GrimoireRules.is_golden(before, catalog.economy):
		EventBus.grimoire_page_golden.emit(recipe.id)
	request_save(REASON_GRIMOIRE)
	return recipe.id


func get_setting(key: String) -> Variant:
	return settings.get(key)


func set_setting(key: String, value: Variant) -> void:
	var old: Variant = settings.get(key)
	if typeof(old) == typeof(value) and old == value:
		return
	settings[key] = value
	EventBus.settings_changed.emit()
	request_save(REASON_SETTINGS)


# --- сериализация -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		KEY_VERSION: SAVE_VERSION,
		"coins": coins,
		"crystals": crystals,
		"reputation": reputation,
		"rank": rank,
		"purchases": _ids_to_strings(purchases),
		"unlocked_ingredients": _ids_to_strings(unlocked_ingredients),
		"grimoire": grimoire.duplicate(true),
		"day": day,
		"order_in_day": order_in_day,
		"streak_3star": streak_3star,
		"current_order": current_order.duplicate(true),
		"ftue_step": ftue_step,
		"daily_reward": daily_reward.duplicate(true),
		"free_flags": free_flags.duplicate(true),
		"settings": settings.duplicate(true),
	}


## Применить сохранение. Неизвестные поля игнорируются, отсутствующие берутся по умолчанию.
## JSON хранит числа как float — целые приводим явно. Возвращает false, если формат не распознан.
func from_dict(data: Dictionary) -> bool:
	if not data.has(KEY_VERSION):
		push_warning("GameState: в сохранении нет версии — начинаем новую игру")
		new_game()
		return false
	var d: Dictionary = _migrate(data)
	_set_defaults()
	coins = int(d.get("coins", coins))
	crystals = int(d.get("crystals", crystals))
	reputation = int(d.get("reputation", reputation))
	rank = int(d.get("rank", rank))
	purchases = _strings_to_ids(d.get("purchases", []))
	unlocked_ingredients = _strings_to_ids(d.get("unlocked_ingredients", []))
	grimoire = GrimoireRules.parse_grimoire(d.get("grimoire", {}))
	day = int(d.get("day", day))
	order_in_day = int(d.get("order_in_day", order_in_day))
	streak_3star = int(d.get("streak_3star", streak_3star))
	current_order = _as_dict(d.get("current_order", {}))
	ftue_step = int(d.get("ftue_step", ftue_step))
	daily_reward.merge(_as_dict(d.get("daily_reward", {})), true)
	free_flags = _as_dict(d.get("free_flags", {}))
	settings.merge(_as_dict(d.get("settings", {})), true)
	state_reset.emit()
	return true


# --- внутреннее ---------------------------------------------------------------

func _set_defaults() -> void:
	coins = 0
	rank = 0
	unlocked_ingredients = []
	if catalog != null and catalog.economy != null:
		coins = catalog.economy.start_coins
		rank = catalog.first_rank()
		unlocked_ingredients = catalog.starting_ingredients()
	else:
		push_error("GameState: не задан catalog — новая игра с нулями")
	crystals = 0
	reputation = 0
	purchases = []
	grimoire = {}
	day = 1
	order_in_day = 0
	streak_3star = 0
	current_order = {}
	ftue_step = 0
	daily_reward = {"chain_day": 0, "last_claim": ""}
	free_flags = {}
	settings = {
		SETTING_MUSIC: 1.0,
		SETTING_SFX: 1.0,
		SETTING_UI: 1.0,
		SETTING_MUTED: false,
		SETTING_SHAKE: true,
		SETTING_LOCALE: "",
	}


## Перевод старых форматов в текущий. Сохранение из более новой сборки читаем как есть.
func _migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get(KEY_VERSION, SAVE_VERSION))
	if version > SAVE_VERSION:
		push_warning("GameState: сохранение новее сборки (v%d > v%d)" % [version, SAVE_VERSION])
	return data


func _ids_to_strings(ids: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for id: StringName in ids:
		out.append(String(id))
	return out


func _strings_to_ids(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if value is Array:
		for v: Variant in value:
			out.append(StringName(str(v)))
	return out


func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}
