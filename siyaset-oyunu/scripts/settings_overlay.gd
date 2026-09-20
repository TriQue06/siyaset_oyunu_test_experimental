extends CanvasLayer
## Autoload sahne. Her ekranda:
##   - ESC: OYUN MENÜSÜ açılır/kapanır (Devam Et · Ayarlar · Oyundan Ayrıl).
##     Ayarlar paneli açıkken ESC önce onu kapatır.
##   - Sağ üstteki "Menü" butonu da aynı menüyü açar/kapatır (dokunmatik ve
##     klavyesiz cihazlar için; ESC'ye basmak gerekmez).
##   - F11: pencereli <-> tam ekran.
## Sahne değişimlerinden etkilenmez çünkü kökten (autoload) bağımsız yaşar.

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

var _menu: Control
var _leave_button: Button
var _leave_note: Label
## "Oyundan Ayrıl" iki adımlı: ilk basış onay ister.
var _leave_armed: bool = false

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

	_build_volume_rows()
	_apply_pixel_style()

	close_button.pressed.connect(close)
	open_settings_button.pressed.connect(_on_menu_button_pressed)
	panel.hide()
	_build_menu()

## Ekranın tarzı tek kaynaktan (UiTheme) geliyor: başlık monospace + altın,
## bölüm adları "> " önekli. Sahnedeki etiketler burada biçimlendirilir.
func _apply_pixel_style() -> void:
	var box := panel.get_node("CenterBox") as VBoxContainer
	box.add_theme_constant_override("separation", UiTheme.GAP_M)
	var title := box.get_node("TitleLabel") as Label
	title.add_theme_font_override("font", UiTheme.mono(true))
	title.add_theme_font_size_override("font_size", UiTheme.FS_TITLE)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	var display_label := box.get_node_or_null("DisplayModeLabel") as Label
	if display_label != null:
		display_label.text = "> EKRAN MODU"
		display_label.add_theme_font_override("font", UiTheme.mono())
		display_label.add_theme_font_size_override("font_size", UiTheme.FS_TINY + 3)
		display_label.add_theme_color_override("font_color", UiTheme.GOLD)
	fps_label.add_theme_font_override("font", UiTheme.mono())

## SES seviyeleri: ana ses, müzik, efekt. Sahneye elle node eklemek yerine
## kod içinde kurulur (satırların hepsi aynı kalıpta).
func _build_volume_rows() -> void:
	var box := panel.get_node("CenterBox") as VBoxContainer
	# "Kapat" butonu her zaman en altta kalsın: yeni satırlar onun ÜSTÜNE girer.
	var title := UiTheme.section_label("Ses")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_insert_before_close(box, title)
	for row in [["master", "Ana ses"], ["music", "Müzik"], ["sfx", "Efektler"]]:
		_volume_row(box, String(row[0]), String(row[1]))

## Yeni satırı "Kapat" butonunun hemen üstüne yerleştirir.
func _insert_before_close(box: VBoxContainer, node: Control) -> void:
	box.add_child(node)
	box.move_child(node, close_button.get_index())

## Tek satır: solda ad + yüzde, sağda kaydırıcı (panel uzamasın diye yan yana).
func _volume_row(box: VBoxContainer, kind: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := UiTheme.mono_label("", UiTheme.FS_BODY)
	label.custom_minimum_size.x = 150.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _volume_of(kind)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	_insert_before_close(box, row)
	var refresh := func(value: float):
		label.text = "%s  %%%d" % [title, int(round(value * 100.0))]
	refresh.call(slider.value)
	slider.value_changed.connect(func(value: float):
		GameSettings.set_volume(kind, value)
		refresh.call(value)
		# Kaydırırken duyulsun: efekt ve ana ses için kısa bir örnek çal.
		if kind != "music":
			AudioManager.play("ui_click"))

func _volume_of(kind: String) -> float:
	match kind:
		"master": return GameSettings.master_volume
		"music": return GameSettings.music_volume
		_: return GameSettings.sfx_volume

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.theme = panel.theme
	_menu.hide()
	add_child(_menu)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Arkadaki ekranın yazıları menü başlığıyla karışmasın diye neredeyse opak.
	backdrop.color = Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.94)
	_menu.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "Oyun Menüsü"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	box.add_child(_menu_button("Devam Et (ESC)", close_menu))
	box.add_child(_menu_button("Ayarlar", func():
		close_menu()
		open()
	))
	_leave_button = _menu_button("Oyundan Ayrıl", _on_leave_pressed)
	box.add_child(_leave_button)

	_leave_note = Label.new()
	_leave_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leave_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leave_note.add_theme_font_size_override("font_size", 13)
	_leave_note.modulate = UiTheme.GOLD
	box.add_child(_leave_note)

func _menu_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 52)
	button.pressed.connect(callback)
	return button

func _index_for_fps(fps: int) -> int:
	var idx := FPS_OPTIONS.find(fps)
	return idx if idx != -1 else FPS_DEFAULT_INDEX

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if panel.visible:
			close()
		elif _menu.visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		GameSettings.toggle_display_mode()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	_leave_armed = false
	# Odada ya da (ağsız örnek oyun dahil) herhangi bir oyun ekranındayken görünür.
	var scene := get_tree().current_scene
	var scene_path: String = scene.scene_file_path if scene != null else ""
	var in_game_scene: bool = scene_path in ["res://scenes/GameScreen.tscn", "res://scenes/GovernmentFormation.tscn",
		"res://scenes/ElectionResults.tscn", "res://scenes/PartySetup.tscn"]
	_leave_button.visible = MultiplayerManager.room_code != "" or in_game_scene
	_leave_button.text = "Oyundan Ayrıl"
	_leave_note.text = ""
	_menu.show()

func close_menu() -> void:
	_menu.hide()

func _on_menu_button_pressed() -> void:
	if panel.visible:
		close()
	elif _menu.visible:
		close_menu()
	else:
		open_menu()

## İlk basış onay ister (yanlışlıkla ayrılmayı önler); ikinci basış ayrılır.
func _on_leave_pressed() -> void:
	if not _leave_armed:
		_leave_armed = true
		_leave_button.text = "Emin misin? Ayrılmak için tekrar bas"
		if MultiplayerManager.room_code == "":
			_leave_note.text = "Oyun kapanır, ana menüye dönersin."
		elif MultiplayerManager.is_host:
			_leave_note.text = "Oda sahibisin: ayrılırsan oda herkes için kapanır."
		else:
			_leave_note.text = "Oyun sensiz devam eder; kartların ve vekillerin oyundan çıkarılır."
		return
	close_menu()
	MultiplayerManager.leave_game()

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
