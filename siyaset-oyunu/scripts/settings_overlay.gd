extends CanvasLayer
## Autoload sahne. Oyunun HERHANGİ bir ekranında ESC'ye basınca (veya sağ alt
## köşedeki evrensel Ayarlar butonuna tıklanınca) açılıp kapanan, TAM EKRAN
## genel oyun ayarları paneli (FPS sınırı, VSync, ekran modu, yayıncı modu).
## Sahne değişimlerinden etkilenmez çünkü kökten (autoload) bağımsız yaşar.
##
## F11: her yerde pencereli <-> tam ekran geçişi (ayarlar paneli kapalıyken
## de çalışır).
## Sağ alt köşedeki Ayarlar butonu HER sahnenin üstünde sabit durur (bu
## CanvasLayer'ın layer'ı yüksek olduğu için), bu oyundaki TEK ayarlar
## giriş noktasıdır.

# FPS sınırı elle sayı girilerek değil, bu sabit seçenekler arasından bir
# eksen/slider ile seçilir. 0 = sınırsız (GameSettings ile aynı sözleşme).
const FPS_OPTIONS := [30, 48, 60, 120, 144, 165, 240, 0]
const FPS_DEFAULT_INDEX := 4  # 144

@onready var panel: Control = %FullScreenPanel
@onready var fps_slider: HSlider = %FpsSlider
@onready var fps_label: Label = %FpsLabel
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var close_button: Button = %CloseButton

@onready var windowed_button: Button = %WindowedButton
@onready var fullscreen_button: Button = %FullscreenButton

@onready var streamer_mode_check: CheckButton = %StreamerModeCheck
@onready var open_settings_button: Button = %OpenSettingsButton

func _ready() -> void:
	fps_slider.min_value = 0
	fps_slider.max_value = FPS_OPTIONS.size() - 1
	fps_slider.step = 1
	fps_slider.value = _index_for_fps(GameSettings.fps_limit)
	fps_slider.value_changed.connect(_on_fps_slider_changed)
	_update_fps_label()

	vsync_check.button_pressed = GameSettings.vsync_enabled
	vsync_check.toggled.connect(_on_vsync_toggled)

	windowed_button.pressed.connect(func(): _on_display_mode_pressed(GameSettings.DisplayMode.WINDOWED))
	fullscreen_button.pressed.connect(func(): _on_display_mode_pressed(GameSettings.DisplayMode.FULLSCREEN))
	_refresh_display_mode_buttons()
	GameSettings.display_mode_changed.connect(func(_m): _refresh_display_mode_buttons())

	streamer_mode_check.button_pressed = GameSettings.streamer_mode
	streamer_mode_check.toggled.connect(_on_streamer_mode_toggled)

	close_button.pressed.connect(close)
	open_settings_button.pressed.connect(open)
	panel.hide()

func _index_for_fps(fps: int) -> int:
	var idx := FPS_OPTIONS.find(fps)
	return idx if idx != -1 else FPS_DEFAULT_INDEX

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if panel.visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		GameSettings.toggle_display_mode()
		get_viewport().set_input_as_handled()

## Diğer ekranlardaki "Ayarlar" butonlarının da aynı paneli açması için.
func open() -> void:
	panel.show()

func close() -> void:
	panel.hide()

func _on_fps_slider_changed(value: float) -> void:
	var fps: int = FPS_OPTIONS[int(value)]
	GameSettings.set_fps_limit(fps)
	_update_fps_label()

func _update_fps_label() -> void:
	var fps: int = FPS_OPTIONS[int(fps_slider.value)]
	fps_label.text = "FPS Sınırı: %s" % ("Sınırsız" if fps == 0 else str(fps))

func _on_vsync_toggled(pressed: bool) -> void:
	GameSettings.set_vsync_enabled(pressed)

func _on_display_mode_pressed(mode: int) -> void:
	GameSettings.set_display_mode(mode)
	_refresh_display_mode_buttons()

func _refresh_display_mode_buttons() -> void:
	windowed_button.button_pressed = GameSettings.display_mode == GameSettings.DisplayMode.WINDOWED
	fullscreen_button.button_pressed = GameSettings.display_mode == GameSettings.DisplayMode.FULLSCREEN

func _on_streamer_mode_toggled(pressed: bool) -> void:
	GameSettings.set_streamer_mode(pressed)
