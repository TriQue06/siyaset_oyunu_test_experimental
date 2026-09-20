extends Node
## Autoload. Genel oyun ayarları (FPS sınırı, VSync, ekran modu, yayıncı modu).
## user:// içine kaydedilir, açılışta uygulanır.

signal streamer_mode_changed(enabled: bool)
signal display_mode_changed(mode: int)

## Sadece iki ekran modu var: pencereli veya tam ekran. Çerçevesiz tam ekran
## kaldırıldı (kasıtlı — karmaşayı azaltmak için).
enum DisplayMode { WINDOWED, FULLSCREEN }

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_FPS_LIMIT := 144
const DEFAULT_VSYNC := true
const DEFAULT_DISPLAY_MODE := DisplayMode.WINDOWED
const DEFAULT_STREAMER_MODE := false
## Ses seviyeleri 0.0 - 1.0 (0 = kapalı). AudioManager bunları bus'lara uygular.
const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_MUSIC_VOLUME := 0.5
const DEFAULT_SFX_VOLUME := 0.8

var fps_limit: int = DEFAULT_FPS_LIMIT
var vsync_enabled: bool = DEFAULT_VSYNC
var display_mode: int = DEFAULT_DISPLAY_MODE
# Açıkken: oda kodu hem lobide hem "odaya katıl" ekranındaki giriş kutusunda
# (yapıştırılsa da elle yazılsa da) gizlenir — yayın yaparken kod ekranda
# görünmesin diye.
var streamer_mode: bool = DEFAULT_STREAMER_MODE
var master_volume: float = DEFAULT_MASTER_VOLUME
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME

func _ready() -> void:
	_load()
	_apply()

func set_fps_limit(value: int) -> void:
	fps_limit = max(0, value)  # 0 = sınırsız
	_apply()
	_save()

func set_vsync_enabled(value: bool) -> void:
	vsync_enabled = value
	_apply()
	_save()

func set_display_mode(mode: int) -> void:
	display_mode = mode
	_apply()
	_save()
	display_mode_changed.emit(display_mode)

## F11 gibi kısayollar için: pencereli <-> tam ekran arasında geçiş yapar.
func toggle_display_mode() -> void:
	set_display_mode(DisplayMode.WINDOWED if display_mode == DisplayMode.FULLSCREEN else DisplayMode.FULLSCREEN)

## volume_kind: "master" | "music" | "sfx"
func set_volume(kind: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match kind:
		"master": master_volume = value
		"music": music_volume = value
		"sfx": sfx_volume = value
		_: return
	AudioManager.apply_volumes()
	_save()

func set_streamer_mode(value: bool) -> void:
	streamer_mode = value
	streamer_mode_changed.emit(streamer_mode)
	_save()

func _apply() -> void:
	Engine.max_fps = fps_limit
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	match display_mode:
		DisplayMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		fps_limit = config.get_value("settings", "fps_limit", DEFAULT_FPS_LIMIT)
		vsync_enabled = config.get_value("settings", "vsync_enabled", DEFAULT_VSYNC)
		var loaded_mode: int = config.get_value("settings", "display_mode", DEFAULT_DISPLAY_MODE)
		# Eski sürümde "Çerçevesiz Tam Ekran" (=2) diye bir üçüncü seçenek
		# vardı; kaydedilmiş eski bir değer varsa Tam Ekran'a düşürüyoruz.
		display_mode = loaded_mode if loaded_mode in [DisplayMode.WINDOWED, DisplayMode.FULLSCREEN] else DisplayMode.FULLSCREEN
		streamer_mode = config.get_value("settings", "streamer_mode", DEFAULT_STREAMER_MODE)
		master_volume = float(config.get_value("settings", "master_volume", DEFAULT_MASTER_VOLUME))
		music_volume = float(config.get_value("settings", "music_volume", DEFAULT_MUSIC_VOLUME))
		sfx_volume = float(config.get_value("settings", "sfx_volume", DEFAULT_SFX_VOLUME))

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "fps_limit", fps_limit)
	config.set_value("settings", "vsync_enabled", vsync_enabled)
	config.set_value("settings", "display_mode", display_mode)
	config.set_value("settings", "streamer_mode", streamer_mode)
	config.set_value("settings", "master_volume", master_volume)
	config.set_value("settings", "music_volume", music_volume)
	config.set_value("settings", "sfx_volume", sfx_volume)
	config.save(CONFIG_PATH)
