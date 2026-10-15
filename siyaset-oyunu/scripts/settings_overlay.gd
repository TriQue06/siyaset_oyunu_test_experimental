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

var _category := "game"
var _building_category := ""
var _pages: Dictionary = {}
var _nav_buttons: Dictionary = {}
var _content_scroll: ScrollContainer
var _menu: Control
var _leave_button: Button
## Oyundaki haritanın tohumu: görülür ve tek tuşla kopyalanır.
var _seed_row: HBoxContainer
var _seed_label: Label
var _seed_copy: Button
var _leave_note: Label
var _save_button: Button
var _tutorial_button: Button
## Kodla eklenen satırlar: dil değişince silinip yeni dilde yeniden kurulur.
var _dynamic: Array = []
## "Oyundan Ayrıl" iki adımlı: ilk basış onay ister.
var _leave_armed: bool = false

func _ready() -> void:
	# Oyun duraklatılınca menü ve ayarlar çalışmaya devam etsin.
	process_mode = Node.PROCESS_MODE_ALWAYS
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

	_build_province_view_row()
	_build_language_row()
	_build_event_fx_row()
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
		display_label.text = L.t("> EKRAN MODU")
		display_label.add_theme_font_override("font", UiTheme.mono())
		display_label.add_theme_font_size_override("font_size", UiTheme.FS_TINY + 3)
		display_label.add_theme_color_override("font_color", UiTheme.GOLD)
	fps_label.add_theme_font_override("font", UiTheme.mono())

## SES seviyeleri: ana ses, müzik, efekt. Sahneye elle node eklemek yerine
## kod içinde kurulur (satırların hepsi aynı kalıpta).
func _build_volume_rows() -> void:
	_building_category = "sound"
	var box := panel.get_node("CenterBox") as VBoxContainer
	# "Kapat" butonu her zaman en altta kalsın: yeni satırlar onun ÜSTÜNE girer.
	var title := UiTheme.section_label(L.t("Ses"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_insert_before_close(box, title)
	for row in [["master", L.t("Ana ses")], ["music", L.t("Müzik")], ["sfx", L.t("Efektler")]]:
		_volume_row(box, String(row[0]), String(row[1]))

## İL İNCELEME: panel (sağ sütun, fareyle canlı) ya da pencere (tıklayınca).
func _build_province_view_row() -> void:
	_building_category = "play"
	var box := panel.get_node("CenterBox") as VBoxContainer
	var title := UiTheme.section_label(L.t("İl inceleme"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_insert_before_close(box, title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_insert_before_close(box, row)
	var buttons: Array = []
	var refresh := func():
		for i in buttons.size():
			var on: bool = GameSettings.province_view == i
			UiSkin.skin_color_button(buttons[i], UiTheme.GOLD if on else UiTheme.PANEL_LIGHT)
			(buttons[i] as Button).add_theme_color_override("font_color", UiTheme.INK if on else UiTheme.TEXT)
	for i in 2:
		var button := Button.new()
		button.text = [L.t("Panel"), L.t("Pencere")][i]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			GameSettings.set_province_view(i)
			refresh.call())
		row.add_child(button)
		buttons.append(button)
	refresh.call()

## DİL: Türkçe / English. Değişince açık ekran yeniden kurulur (metinler
## kurulurken çevrildiği için); oyun durumu yöneticilerde olduğundan kaybolmaz.
## OLAY ANİMASYONLARI: büyük olaylardan sonra fırlatılan gazete (EventFx).
func _build_event_fx_row() -> void:
	_building_category = "play"
	var box := panel.get_node("CenterBox") as VBoxContainer
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = L.t("Olay Animasyonları")
	row.add_child(label)
	var check := CheckButton.new()
	check.button_pressed = GameSettings.event_fx
	check.toggled.connect(GameSettings.set_event_fx)
	row.add_child(check)
	_insert_before_close(box, row)

func _build_language_row() -> void:
	_building_category = "language"
	var box := panel.get_node("CenterBox") as VBoxContainer
	var title := UiTheme.section_label(L.t("Dil"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_insert_before_close(box, title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_insert_before_close(box, row)
	for code in L.LOCALES:
		var button := Button.new()
		button.text = String(L.LOCALE_NAMES[code])
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on: bool = GameSettings.language == code
		UiSkin.skin_color_button(button, UiTheme.GOLD if on else UiTheme.PANEL_LIGHT)
		button.add_theme_color_override("font_color", UiTheme.INK if on else UiTheme.TEXT)
		button.pressed.connect(func():
			if GameSettings.language == code:
				return
			GameSettings.set_language(code)
			# Menü açık kalır: önce arkadaki ekran, sonra bu panel yeni dilde kurulur.
			get_tree().reload_current_scene()
			_rebuild_for_language.call_deferred())
		row.add_child(button)

## Yeni satırı "Kapat" butonunun hemen üstüne yerleştirir.
func _insert_before_close(box: VBoxContainer, node: Control) -> void:
	node.set_meta("settings_category", _building_category)
	_dynamic.append(node)
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
	title.text = L.t("Oyun Menüsü")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

	box.add_child(_menu_button(L.t("Devam Et (ESC)"), close_menu))
	box.add_child(_menu_button(L.t("Ayarlar"), func():
		close_menu()
		open()
	))
	_seed_row = HBoxContainer.new()
	_seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_seed_row.add_theme_constant_override("separation", 8)
	_seed_label = Label.new()
	_seed_label.add_theme_font_size_override("font_size", 16)
	_seed_row.add_child(_seed_label)
	_seed_copy = Button.new()
	_seed_copy.text = L.t("Kopyala")
	_seed_copy.custom_minimum_size = Vector2(96, 36)
	_seed_copy.pressed.connect(func():
		DisplayServer.clipboard_set(str(GameMap.seed_value()))
		_seed_copy.text = L.t("Kopyalandı!"))
	_seed_row.add_child(_seed_copy)
	box.add_child(_seed_row)
	_save_button = _menu_button(L.t("Oyunu Kaydet"), func():
		var err := SaveGame.save(SaveGame.MANUAL_SLOT)
		_leave_note.text = L.t("Oyun kaydedildi. Ana menüden \"Kayıtlı Oyuna Devam Et\" ile dönebilirsin.") if err == "" else err)
	box.add_child(_save_button)
	_tutorial_button = _menu_button(L.t("Rehberi Baştan Göster"), func():
		var scene := get_tree().current_scene
		if scene != null and scene.get("_tutorial") != null:
			scene._tutorial.restart()
		else:
			TutorialGuide.reset()
		_leave_note.text = L.t("İlk oyun rehberi baştan gösterilecek.")
		close_menu())
	box.add_child(_tutorial_button)
	_leave_button = _menu_button(L.t("Oyundan Ayrıl"), _on_leave_pressed)
	box.add_child(_leave_button)

	_leave_note = Label.new()
	_leave_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_leave_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_leave_note.add_theme_font_size_override("font_size", 13)
	_leave_note.modulate = UiTheme.GOLD
	box.add_child(_leave_note)
	_build_concept_a(box, center)

func _menu_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 48)
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
		"res://scenes/ElectionResults.tscn", "res://scenes/PartySetup.tscn", "res://scenes/PoliticianSetup.tscn"]
	_leave_button.visible = MultiplayerManager.room_code != "" or in_game_scene
	_leave_button.text = L.t("Oyundan Ayrıl")
	_leave_note.text = ""
	_seed_row.visible = scene_path in ["res://scenes/GameScreen.tscn", "res://scenes/GovernmentFormation.tscn",
		"res://scenes/ElectionResults.tscn"]
	_seed_label.text = L.t("Harita tohumu: %d") % GameMap.seed_value()
	# Kayıt sadece çevrim dışı oyunun oyun ekranında.
	_save_button.visible = scene_path == "res://scenes/GameScreen.tscn" and MultiplayerManager.offline_mode
	_save_button.disabled = SaveGame.block_reason() != ""
	_tutorial_button.visible = scene_path == "res://scenes/GameScreen.tscn"
	_seed_copy.text = L.t("Kopyala")
	_select_category("game")
	_menu.show()
	_sync_pause()

func close_menu() -> void:
	_menu.hide()
	_sync_pause()

## ÇEVRİM DIŞI DURAKLATMA (0.0.191): menü ya da ayarlar açıkken çevrim dışı
## oyun tamamen durur (tur sayacı, botlar, oylama ve kurma süreleri). Çevrim
## içi oyunda diğer oyuncular beklemez, orada durmaz.
func _sync_pause() -> void:
	var scene := get_tree().current_scene
	var in_game := scene != null and scene.scene_file_path in ["res://scenes/GameScreen.tscn",
		"res://scenes/GovernmentFormation.tscn", "res://scenes/ElectionResults.tscn"]
	get_tree().paused = MultiplayerManager.offline_mode and in_game and (_menu.visible or panel.visible)

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
		_leave_button.text = L.t("Emin misin? Ayrılmak için tekrar bas")
		if MultiplayerManager.room_code == "":
			_leave_note.text = L.t("Oyun kapanır, ana menüye dönersin.")
		elif MultiplayerManager.is_host:
			_leave_note.text = L.t("Oda sahibisin: ayrılırsan oda herkes için kapanır.")
		else:
			_leave_note.text = L.t("Oyun sensiz devam eder; kartların ve vekillerin oyundan çıkarılır.")
		return
	close_menu()
	MultiplayerManager.leave_game()

## Dil değişince: ayarlar paneli açık kalır, kodla kurulan bütün yazılar
## (satırlar ve oyun menüsü) yeni dilde yeniden kurulur.
func _rebuild_for_language() -> void:
	# Sahnedeki sabit kontrolleri eski taşıyıcıya al; yeni düzen kurulurken korunurlar.
	var box := panel.get_node("CenterBox") as VBoxContainer
	for page in _pages.values():
		if not is_instance_valid(page) or page == _pages.get("game"):
			continue
		for child in page.get_children():
			child.reparent(box)
	for node in _dynamic:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_dynamic.clear()
	_menu.get_parent().remove_child(_menu)
	_menu.queue_free()
	_build_province_view_row()
	_build_language_row()
	_build_event_fx_row()
	_build_volume_rows()
	_apply_pixel_style()
	_update_fps_label()
	_build_menu()
	open_menu()
	_select_category("language")

## Bütün giriş noktaları aynı kategori ekranını kullanır.
func open() -> void:
	open_menu()
	_select_category("display")

func close() -> void:
	panel.hide()
	close_menu()

func _on_fps_slider_changed(value: float) -> void:
	var fps: int = FPS_OPTIONS[int(value)]
	GameSettings.set_fps_limit(fps)
	_update_fps_label()

func _update_fps_label() -> void:
	var fps: int = FPS_OPTIONS[int(fps_slider.value)]
	fps_label.text = L.t("FPS Sınırı: %s") % (L.t("Sınırsız") if fps == 0 else str(fps))

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

## Konsept A: sabit başlık ve sol gezinme; sağ içerik üstten başlar ve kayar.
func _build_concept_a(session: VBoxContainer, old_center: CenterContainer) -> void:
	_pages.clear()
	_nav_buttons.clear()
	var shell := VBoxContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	_menu.add_child(shell)
	var header := PanelContainer.new()
	UiSkin.skin_panel(header)
	shell.add_child(header)
	var header_margin := _margin(header, 18)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 18)
	header_margin.add_child(heading)
	var title := UiTheme.mono_label(L.t("Oyun Menüsü"), 24)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var resume := _menu_button(L.t("Devam Et (ESC)"), close_menu)
	UiSkin.skin_color_button(resume, UiTheme.GOLD)
	resume.add_theme_color_override("font_color", UiTheme.INK)
	heading.add_child(resume)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	shell.add_child(body)
	var nav_panel := PanelContainer.new()
	UiSkin.skin_panel(nav_panel, UiSkin.PANEL_DARK)
	nav_panel.custom_minimum_size.x = 190
	body.add_child(nav_panel)
	var nav_scroll := ScrollContainer.new()
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin(nav_panel, 10).add_child(nav_scroll)
	var nav := VBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", 10)
	nav_scroll.add_child(nav)
	_content_scroll = ScrollContainer.new()
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_content_scroll)
	var content_margin := _margin(_content_scroll, 22)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(stack)
	for entry in [["game", "Oyun Menüsü"], ["display", "Ekran Modu"], ["sound", "Ses"], ["play", "Ayarlar"], ["language", "Dil"]]:
		var key: String = entry[0]
		var button := Button.new()
		button.text = L.t(entry[1])
		button.custom_minimum_size = Vector2(0, 46)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func(): _select_category(key))
		nav.add_child(button)
		_nav_buttons[key] = button
		var card := PanelContainer.new()
		UiSkin.skin_panel(card)
		stack.add_child(card)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 18)
		_margin(card, 20).add_child(page)
		_pages[key] = page
		card.set_meta("category", key)
	var original := panel.get_node("CenterBox") as VBoxContainer
	for child in original.get_children():
		var key := String(child.get_meta("settings_category", "display"))
		if child.name == "StreamerModeRow":
			key = "play"
		if child == close_button or child.name == "TitleLabel":
			child.hide()
			continue
		child.reparent(_pages[key])
		if child is Label:
			child.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for child in session.get_children():
		# Eski ayrı Ayarlar düğmesinin yerini soldaki kategoriler alır.
		if child is Button and child.text == L.t("Ayarlar"):
			child.queue_free()
		elif child is Label and child != _leave_note:
			child.queue_free()
		else:
			child.reparent(_pages["game"])
			if child is Button:
				UiSkin.skin_color_button(child, UiTheme.RED_DARK if child == _leave_button else UiTheme.PANEL_LIGHT)
	old_center.queue_free()
	var footer := PanelContainer.new()
	UiSkin.skin_panel(footer, UiSkin.PANEL_DARK)
	shell.add_child(footer)
	var hint := UiTheme.mono_label(L.t("F11 ile de değiştirebilirsin"), 12)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_margin(footer, 12).add_child(hint)
	_select_category("game")

func _margin(parent: Node, padding: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, padding)
	parent.add_child(margin)
	return margin

func _select_category(key: String) -> void:
	_category = key
	for category in _pages:
		var page: VBoxContainer = _pages[category]
		page.get_parent().get_parent().visible = category == key
		var button: Button = _nav_buttons[category]
		UiSkin.skin_color_button(button, UiTheme.GOLD if category == key else UiTheme.PANEL_LIGHT)
		button.add_theme_color_override("font_color", UiTheme.INK if category == key else UiTheme.TEXT)
	_content_scroll.scroll_vertical = 0
