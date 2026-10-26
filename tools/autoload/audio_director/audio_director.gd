## AudioDirector — музыка с плавным входом/выходом, пул плееров для звуков, громкость шин.
## Глушит всё на паузе (реклама, потеря фокуса — Яндекс 1.3, 4.7) и по настройке «звук выкл».
## Пул звуков — дочерние AudioStreamPlayer узла sfx_pool: сколько узлов в сцене, столько звуков одновременно.
## Сигналы: нет.
## Зависимости: EventBus (pause_changed, settings_changed), GameState.settings; шины из audio/default_bus_layout.tres.
extends Node

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"

@export var music_player: AudioStreamPlayer
## Узел, дочерние AudioStreamPlayer которого — пул звуков (шина SFX).
@export var sfx_pool: Node
## Плеер для звуков интерфейса (шина UI).
@export var ui_player: AudioStreamPlayer
## Длительность входа и выхода музыки, секунды.
@export var music_fade_sec: float = 0.8
## Громкость «тишины» для затухания музыки, дБ.
@export var silent_db: float = -40.0
## Разброс высоты тона звуков (±), чтобы повторы не звучали одинаково.
@export var pitch_jitter: float = 0.06

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx: int = 0
var _music_tween: Tween


func _ready() -> void:
	for child: Node in sfx_pool.get_children():
		if child is AudioStreamPlayer:
			_sfx_players.append(child as AudioStreamPlayer)
	EventBus.pause_changed.connect(_on_pause_changed)
	EventBus.settings_changed.connect(apply_settings)


## Применить громкость и «звук выкл» из GameState.settings. Вызывается после загрузки и при смене настроек.
func apply_settings() -> void:
	var s: Dictionary = GameState.settings
	set_bus_volume(BUS_MUSIC, float(s.get(GameState.SETTING_MUSIC, 1.0)))
	set_bus_volume(BUS_SFX, float(s.get(GameState.SETTING_SFX, 1.0)))
	set_bus_volume(BUS_UI, float(s.get(GameState.SETTING_UI, 1.0)))
	_update_master_mute()


func play_sfx(stream: AudioStream, vary_pitch: bool = true, volume_db: float = 0.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + (randf_range(-pitch_jitter, pitch_jitter) if vary_pitch else 0.0)
	player.play()


func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	ui_player.stream = stream
	ui_player.volume_db = volume_db
	ui_player.play()


func play_music(stream: AudioStream) -> void:
	if stream == null:
		stop_music()
		return
	if music_player.stream == stream and music_player.playing:
		return
	_kill_music_tween()
	music_player.stream = stream
	music_player.volume_db = silent_db
	music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(music_player, "volume_db", 0.0, music_fade_sec)


func stop_music() -> void:
	if not music_player.playing:
		return
	_kill_music_tween()
	_music_tween = create_tween()
	_music_tween.tween_property(music_player, "volume_db", silent_db, music_fade_sec)
	_music_tween.tween_callback(music_player.stop)


## Громкость шины от 0 до 1. Ноль — шина выключена.
func set_bus_volume(bus: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx < 0:
		push_warning("AudioDirector: нет шины %s" % bus)
		return
	var v: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	if v > 0.0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))


func _update_master_mute() -> void:
	var muted: bool = bool(GameState.settings.get(GameState.SETTING_MUTED, false)) or Platform.is_paused()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), muted)


func _on_pause_changed(_paused: bool) -> void:
	_update_master_mute()


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
