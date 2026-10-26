## ServicesSmoke — ручная проверка автозагрузок в Godot (F6 на этой сцене), пока у агента нет движка.
## Проверяет: загрузку, запись и обратное чтение сохранения, списание монет, рекламу-заглушку с паузой.
## Итог — в Output строкой «SMOKE: x/y»; в конце сцена плавно сменяется на лавку через SceneRouter.
## Сигналы: нет. Зависимости: Platform, SaveService, GameState, SceneRouter.
extends Node

const TEST_COINS: int = 7
const TEST_PLACEMENT: StringName = &"smoke"
const NEXT_SCENE: String = "res://scenes/workshop/workshop.tscn"

var _passed: int = 0
var _total: int = 0


func _ready() -> void:
	await Platform.initialize()
	_check("Platform.initialize", Platform.is_initialized)
	var loaded_ok: bool = await SaveService.load_game()
	_check("SaveService.load_game", loaded_ok and SaveService.is_loaded)

	var start_coins: int = GameState.coins
	GameState.add_coins(TEST_COINS)
	var saved_ok: bool = await SaveService.saved
	_check("запись после add_coins", saved_ok)
	var on_disk: Dictionary = await Platform.load_data()
	_check("обратное чтение: монеты", int(on_disk.get("coins", -1)) == start_coins + TEST_COINS)
	_check("try_spend_coins", GameState.try_spend_coins(TEST_COINS) and GameState.coins == start_coins)
	await SaveService.saved

	_check("лишнее списание отклонено", not GameState.try_spend_coins(GameState.coins + TEST_COINS))

	var rewarded: bool = await Platform.show_rewarded_ad(TEST_PLACEMENT)
	_check("реклама за награду (mock)", rewarded)
	_check("пауза снята после рекламы", not Platform.is_paused() and not get_tree().paused)

	print("SMOKE: %d/%d %s" % [_passed, _total, "OK" if _passed == _total else "ЕСТЬ ОШИБКИ"])
	SceneRouter.go_to(NEXT_SCENE)


func _check(title: String, ok: bool) -> void:
	_total += 1
	if ok:
		_passed += 1
		print("  [OK] ", title)
	else:
		push_error("SMOKE FAIL: " + title)
