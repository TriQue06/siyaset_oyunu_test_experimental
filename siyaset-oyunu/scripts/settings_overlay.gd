extends CanvasLayer
## HTML Konsept A'nın ölçüleri, kategorileri ve satır düzeni.
const FPS_OPTIONS := [30, 48, 60, 120, 144, 165, 240, 0]
const CATEGORIES := [["game", "Oyun menüsü", "Oyuna devam et, kaydet veya oturumdan ayrıl."], ["display", "Görüntü", "Ekran modu ve performans tercihleri."], ["sound", "Ses", "Müzik ve efektleri ayrı ayrı ayarla."], ["play", "Oynanış", "Bilgi panelleri ve olay gösterimleri."], ["language", "Dil", "Arayüzün dilini seç."]]
const ART := "res://assets/ui/settings/"
const MUTED := Color("b1a6d1")
const FONT := preload("res://assets/fonts/IBMPlexMono-Regular.ttf")
const BOLD := preload("res://assets/fonts/IBMPlexMono-Bold.ttf")

@onready var panel: Control = %FullScreenPanel
@onready var open_settings_button: Button = %OpenSettingsButton
var _menu: Control
var _category := "game"
var _nav_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _content_scroll: ScrollContainer
var _notice: Label
var _status: Label
var _leave_button: Button
var _seed_copy: Button
var _save_button: Button
var _tutorial_button: Button
var _leave_armed := false
var _reset_armed := false
var _reset_button: Button
var _display_buttons: Array[Button] = []
var _rows: Array[BoxContainer] = []
var _nav_panel: PanelContainer
var _content_margin: MarginContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu = panel
	_build_menu()
	panel.hide()
	open_settings_button.pressed.connect(_on_menu_button_pressed)
	GameSettings.display_mode_changed.connect(func(_mode): _refresh_display_buttons())
	get_viewport().size_changed.connect(_adapt_layout)

func _label(text: String, font_size: int, color: Color = UiTheme.TEXT, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = L.t(text)
	label.add_theme_font_override("font", BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _margin(parent: Node, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, horizontal)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, vertical)
	parent.add_child(margin)
	return margin

func _surface(color: Color) -> PanelContainer:
	var surface := PanelContainer.new()
	var style := UiSkin.color_box(color, UiSkin.FILL, 0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 0)
	surface.add_theme_stylebox_override("panel", style)
	return surface

func _button(text: String, callback: Callable, kind: String = "normal", font_size: int = 11) -> Button:
	var button := Button.new()
	button.text = L.t(text)
	button.custom_minimum_size.y = 44
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(callback)
	_style_button(button, kind)
	return button

func _style_button(button: Button, kind: String = "normal") -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := UiSkin.stylebox(ART + kind + ".png")
		box.content_margin_left = 18
		box.content_margin_right = 18
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		if state == "hover" or state == "focus":
			box.modulate_color = Color(1.15, 1.15, 1.15)
		elif state == "pressed":
			box.modulate_color = Color(0.85, 0.85, 0.85)
		elif state == "disabled":
			box.modulate_color = Color(0.6, 0.6, 0.6)
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, UiTheme.INK if kind == "gold" else UiTheme.TEXT)
	button.add_theme_font_override("font", BOLD if kind == "gold" else FONT)

func _build_menu() -> void:
	_pages.clear()
	_nav_buttons.clear()
	_rows.clear()
	_display_buttons.clear()
	var frame := _surface(Color("65528e"))
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(frame)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 3)
	var inner := _surface(UiTheme.INK)
	_margin(frame, 3, 3).add_child(inner)
	inner.add_child(shell)
	var header := _surface(Color("241d43"))
	shell.add_child(header)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	_margin(header, 24, 18).add_child(heading)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 7)
	brand.add_child(_label("OYUN MENÜSÜ", 21, UiTheme.TEXT, true))
	brand.add_child(_label("SİYASET OYUNU / AYARLAR", 10, MUTED))
	heading.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	_status = _label("", 10, Color("74e6a0"))
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(_status)
	heading.add_child(_button("DEVAM ET · ESC", close_menu, "gold"))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(body)
	_nav_panel = _surface(Color("201a3c"))
	_nav_panel.custom_minimum_size.x = 217
	body.add_child(_nav_panel)
	var nav_scroll := ScrollContainer.new()
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_margin(_nav_panel, 14, 20).add_child(nav_scroll)
	var nav := VBoxContainer.new()
	nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_theme_constant_override("separation", 8)
	nav_scroll.add_child(nav)
	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var scroll_bg := _surface(UiTheme.BG)
	scroll_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll_bg)
	scroll_bg.add_child(_content_scroll)
	var scrollbar := _content_scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 12
	scrollbar.add_theme_stylebox_override("scroll", UiSkin.color_box(UiTheme.INK, UiSkin.FILL, 0))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var style := UiSkin.stylebox(ART + "scroll.png", 3)
		style.content_margin_left = 3
		style.content_margin_right = 3
		scrollbar.add_theme_stylebox_override(state, style)
	_content_margin = _margin(_content_scroll, 24, 24)
	_content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	_content_margin.add_child(stack)
	for entry in CATEGORIES:
		var key: String = entry[0]
		var button := _button(entry[1], func(): _select_category(key), "normal", 12)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nav.add_child(button)
		_nav_buttons[key] = button
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 0)
		stack.add_child(page)
		_pages[key] = page
		var page_heading := HBoxContainer.new()
		page_heading.add_theme_constant_override("separation", 16)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 7)
		words.add_child(_label(entry[1], 17, UiTheme.TEXT, true))
		var description := _label(entry[2], 11, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(description)
		page_heading.add_child(words)
		var tag := _label("OTURUM" if key == "game" else "KİŞİSEL AYARLAR", 10, UiTheme.GOLD)
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		page_heading.add_child(tag)
		page.add_child(page_heading)
		_gap(page, 20)
		var card := PanelContainer.new()
		var card_style := UiSkin.stylebox(ART + "card.png")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: card_style.set_content_margin(side, 3)
		card.add_theme_stylebox_override("panel", card_style)
		page.add_child(card)
		var card_content := VBoxContainer.new()
		card_content.add_theme_constant_override("separation", 0)
		_margin(card, 20, 20).add_child(card_content)
		var card_title := _label(_caps(L.t(entry[1])), 12, UiTheme.GOLD, true)
		card_content.add_child(card_title)
		_gap(card_content, 18)
		_build_category(key, card_content)
		_gap(page, 28)
		var end := _label("Ayarlar için soldaki kategorileri kullan." if key == "game" else "Tercihler değiştirildiğinde anında uygulanır.", 10, MUTED)
		end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		end.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(end)
	_gap(nav, 14)
	var shortcuts := _label("ESC · Oyuna dön\n\nF11 · Tam ekran", 10, MUTED)
	_margin(nav, 8, 0).add_child(shortcuts)
	var footer := _surface(Color("201a3c"))
	shell.add_child(footer)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	_margin(footer, 24, 12).add_child(footer_row)
	_notice = _label("Tercihler değiştirildiğinde anında uygulanır.", 10, MUTED)
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_row.add_child(_notice)
	_reset_button = _button("AYARLARI SIFIRLA", _on_reset_pressed)
	footer_row.add_child(_reset_button)
	_select_category(_category)
	_adapt_layout()

func _caps(text: String) -> String:
	return text.to_upper() if L.is_en() else text.replace("i", "İ").replace("ı", "I").to_upper()

func _gap(parent: Node, height: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)

func _row(box: VBoxContainer, title: String, help: String, control: Control) -> BoxContainer:
	var index: int = int(box.get_meta("row_count", 0))
	if index > 0:
		_gap(box, 17)
		var line := _surface(Color("51426f"))
		line.custom_minimum_size.y = 1
		box.add_child(line)
		_gap(box, 17)
	box.set_meta("row_count", index + 1)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 7)
	var name_label := _label(title, 12, UiTheme.TEXT, true)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(name_label)
	var help_label := _label(help, 10, MUTED)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(help_label)
	row.add_child(words)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	_rows.append(row)
	return row

func _segments(options: Array, selected: int, callback: Callable, display: bool = false) -> HBoxContainer:
	var control := HBoxContainer.new()
	control.custom_minimum_size.x = 240
	control.add_theme_constant_override("separation", 5)
	var buttons: Array[Button] = []
	for i in options.size():
		var button := _button(options[i], func():
			callback.call(i)
			for j in buttons.size(): _style_button(buttons[j], "gold" if i == j else "normal"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		control.add_child(button)
		buttons.append(button)
		_style_button(button, "gold" if i == selected else "normal")
	if display: _display_buttons = buttons
	return control

func _toggle(value: bool, callback: Callable) -> HBoxContainer:
	var control := HBoxContainer.new()
	control.custom_minimum_size.x = 76
	control.add_theme_constant_override("separation", 8)
	var text := _label("Açık" if value else "Kapalı", 10, UiTheme.GOLD)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.add_child(text)
	var check := Button.new()
	check.toggle_mode = true
	check.button_pressed = value
	check.custom_minimum_size = Vector2(38, 24)
	for state in ["normal", "hover", "focus", "disabled"]:
		check.add_theme_stylebox_override(state, UiSkin.stylebox(ART + "toggle_off.png", 3))
	for state in ["pressed", "hover_pressed"]:
		check.add_theme_stylebox_override(state, UiSkin.stylebox(ART + "toggle_on.png", 3))
	check.toggled.connect(func(on):
		text.text = L.t("Açık" if on else "Kapalı")
		callback.call(on))
	control.add_child(check)
	return control

func _range(value: float, minimum: float, maximum: float, step: float, formatter: Callable, callback: Callable) -> VBoxContainer:
	var control := VBoxContainer.new()
	control.custom_minimum_size.x = 240
	control.add_theme_constant_override("separation", 9)
	var outputs := HBoxContainer.new()
	outputs.add_theme_constant_override("separation", 0)
	control.add_child(outputs)
	var left := _label(formatter.call(minimum), 10, MUTED)
	outputs.add_child(left)
	var current := _label(formatter.call(value), 10, UiTheme.GOLD)
	current.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outputs.add_child(current)
	outputs.add_child(_label(formatter.call(maximum), 10, MUTED))
	var slider := HSlider.new()
	slider.custom_minimum_size.y = 24
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	var track := UiSkin.color_box(UiTheme.INK, UiSkin.FILL, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", UiSkin.color_box(UiTheme.GOLD, UiSkin.FILL, 0))
	slider.add_theme_stylebox_override("grabber_area_highlight", UiSkin.color_box(UiTheme.GOLD, UiSkin.FILL, 0))
	slider.add_theme_icon_override("grabber", load(ART + "grabber.png"))
	slider.add_theme_icon_override("grabber_highlight", load(ART + "grabber.png"))
	slider.add_theme_icon_override("grabber_disabled", load(ART + "grabber.png"))
	slider.value_changed.connect(func(v):
		current.text = formatter.call(v)
		callback.call(v))
	control.add_child(slider)
	return control

func _build_category(key: String, box: VBoxContainer) -> void:
	match key:
		"game":
			_row(box, "Oyuna dön", "Kaldığın yerden devam et. Kısayol: ESC", _button("DEVAM ET →", close_menu, "gold"))
			_save_button = _button("OYUNU KAYDET", _save_game)
			_row(box, "Oyun kaydı", "Çevrim dışı oyunun ilerlemesini kaydet.", _save_button)
			_seed_copy = _button("— · KOPYALA", func():
				DisplayServer.clipboard_set(str(GameMap.seed_value()))
				_notice.text = L.t("Kopyalandı!"))
			_row(box, "Harita tohumu", "Aynı ülke haritasını yeniden oluşturmak için.", _seed_copy)
			_row(box, "Oyun günlüğü", "Bütün olayları, seçimleri, oyuncu ve bot kararlarını bir metin dosyasına yazar.", _button("LOG İNDİR", func():
				var path: String = GameLog.export_file()
				_notice.text = (L.t("Günlük kaydedildi: %s") % path) if path != "" else L.t("Günlük yazılamadı.")))
			_tutorial_button = _button("REHBERİ AÇ", _restart_tutorial)
			_row(box, "İlk oyun rehberi", "Oynanışı anlatan rehberi yeniden başlat.", _tutorial_button)
			_leave_button = _button("OYUNDAN AYRIL", _on_leave_pressed, "danger")
			_row(box, "Oyundan ayrıl", "Ayrılmadan önce onay istenir.", _leave_button)
		"display":
			_row(box, "Ekran modu", "F11 ile de değiştirebilirsin.", _segments(["Pencereli", "Tam ekran"], GameSettings.display_mode, GameSettings.set_display_mode, true))
			var index := FPS_OPTIONS.find(GameSettings.fps_limit)
			_row(box, "FPS sınırı", "Ekran modu ve performans tercihleri.", _range(maxi(index, 0), 0, 7, 1, func(v): return L.t("Sınırsız") if FPS_OPTIONS[int(v)] == 0 else str(FPS_OPTIONS[int(v)]) + " FPS", func(v): GameSettings.set_fps_limit(FPS_OPTIONS[int(v)])))
			_row(box, "Dikey eşitleme", "Görüntü yırtılmasını azaltır.", _toggle(GameSettings.vsync_enabled, GameSettings.set_vsync_enabled))
		"sound":
			for entry in [["master", "Ana ses", "Tüm seslerin genel seviyesi."], ["music", "Müzik", "Oyun ve seçim gecesi müzikleri."], ["sfx", "Efektler", "Butonlar, kartlar ve oylama sesleri."]]:
				var kind: String = entry[0]
				var value: float = GameSettings.get(kind + "_volume")
				_row(box, entry[1], entry[2], _range(value * 100, 0, 100, 5, func(v): return str(int(v)) + "%", func(v):
					GameSettings.set_volume(kind, v / 100.0)
					if kind != "music": AudioManager.play("ui_click")))
		"play":
			_row(box, "İl inceleme", "İl ayrıntılarının nasıl açılacağını seç.", _segments(["Panel", "Pencere"], GameSettings.province_view, GameSettings.set_province_view))
			_row(box, "Olay animasyonları", "Gazete ve haber manşeti gösterimleri.", _toggle(GameSettings.event_fx, GameSettings.set_event_fx))
			_row(box, "Yayıncı modu", "Yayın sırasında gizlilik tercihi.", _toggle(GameSettings.streamer_mode, GameSettings.set_streamer_mode))
		"language":
			_row(box, "Oyun dili", "Arayüzde kullanılacak dil.", _segments([L.t("Türkçe"), L.t("İngilizce")], L.LOCALES.find(GameSettings.language), func(i):
				if GameSettings.language != L.LOCALES[i]:
					GameSettings.set_language(L.LOCALES[i])
					get_tree().reload_current_scene()
					_rebuild.call_deferred("language")))

func _adapt_layout() -> void:
	var width := get_viewport().get_visible_rect().size.x
	_nav_panel.custom_minimum_size.x = 217 if width > 850 else (157 if width > 600 else 122)
	_status.visible = width > 850
	for side in ["left", "right", "top", "bottom"]:
		_content_margin.add_theme_constant_override("margin_" + side, 24 if width > 850 else 16)
	for row in _rows:
		row.vertical = width <= 850
		var control := row.get_child(1) as Control
		control.size_flags_horizontal = Control.SIZE_FILL if width > 850 else Control.SIZE_EXPAND_FILL

func _select_category(key: String) -> void:
	_category = key
	for category in _pages:
		_pages[category].visible = category == key
		_style_button(_nav_buttons[category], "gold" if category == key else "normal")
	_content_scroll.scroll_vertical = 0

func _refresh_display_buttons() -> void:
	for i in _display_buttons.size():
		_style_button(_display_buttons[i], "gold" if i == GameSettings.display_mode else "normal")

func _scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""

func open_menu() -> void:
	_leave_armed = false
	_reset_armed = false
	_leave_button.text = L.t("OYUNDAN AYRIL")
	_reset_button.text = L.t("AYARLARI SIFIRLA")
	_notice.text = L.t("Tercihler değiştirildiğinde anında uygulanır.")
	var path := _scene_path()
	var in_game := path in ["res://scenes/GameScreen.tscn", "res://scenes/GovernmentFormation.tscn", "res://scenes/ElectionResults.tscn"]
	_leave_button.disabled = MultiplayerManager.room_code == "" and not in_game and path != "res://scenes/PartySetup.tscn"
	_seed_copy.disabled = not in_game
	_seed_copy.text = (str(GameMap.seed_value()) if in_game else "—") + " · " + L.t("KOPYALA")
	_save_button.disabled = path != "res://scenes/GameScreen.tscn" or not MultiplayerManager.offline_mode or SaveGame.block_reason() != ""
	_tutorial_button.disabled = path != "res://scenes/GameScreen.tscn"
	_status.text = L.t("● Çevrim dışı · Oyun duraklatıldı") if MultiplayerManager.offline_mode and in_game else L.t("● Çevrim içi · Oyun devam ediyor") if in_game else L.t("● SİYASET OYUNU")
	_select_category("game")
	panel.show()
	_sync_pause()

func close_menu() -> void:
	panel.hide()
	_sync_pause()

func open() -> void:
	open_menu()
	_select_category("display")

func close() -> void:
	close_menu()

func _on_menu_button_pressed() -> void:
	if panel.visible: close_menu()
	else: open_menu()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_menu_button_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		GameSettings.toggle_display_mode()
		get_viewport().set_input_as_handled()

func _sync_pause() -> void:
	get_tree().paused = MultiplayerManager.offline_mode and _scene_path() in ["res://scenes/GameScreen.tscn", "res://scenes/GovernmentFormation.tscn", "res://scenes/ElectionResults.tscn"] and panel.visible

func _save_game() -> void:
	var err := SaveGame.save(SaveGame.MANUAL_SLOT)
	_notice.text = L.t("Oyun kaydedildi. Ana menüden \"Kayıtlı Oyuna Devam Et\" ile dönebilirsin.") if err == "" else err

func _restart_tutorial() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.get("_tutorial") != null: scene._tutorial.restart()
	else: TutorialGuide.reset()
	close_menu()

func _on_leave_pressed() -> void:
	if not _leave_armed:
		_leave_armed = true
		_leave_button.text = L.t("TEKRAR BAS · AYRIL")
		_notice.text = L.t("Oyun kapanır, ana menüye dönersin.") if MultiplayerManager.room_code == "" else L.t("Oda sahibisin: ayrılırsan oda herkes için kapanır.") if MultiplayerManager.is_host else L.t("Oyun sensiz devam eder; kartların ve vekillerin oyundan çıkarılır.")
		return
	close_menu()
	MultiplayerManager.leave_game()

func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = L.t("TEKRAR BAS · SIFIRLA")
		_notice.text = L.t("Kişisel ayarların varsayılan değerlerine dönecek.")
		return
	GameSettings.set_fps_limit(GameSettings.DEFAULT_FPS_LIMIT)
	GameSettings.set_vsync_enabled(GameSettings.DEFAULT_VSYNC)
	GameSettings.set_display_mode(GameSettings.DEFAULT_DISPLAY_MODE)
	GameSettings.set_volume("master", GameSettings.DEFAULT_MASTER_VOLUME)
	GameSettings.set_volume("music", GameSettings.DEFAULT_MUSIC_VOLUME)
	GameSettings.set_volume("sfx", GameSettings.DEFAULT_SFX_VOLUME)
	GameSettings.set_province_view(GameSettings.DEFAULT_PROVINCE_VIEW)
	GameSettings.set_event_fx(true)
	GameSettings.set_streamer_mode(GameSettings.DEFAULT_STREAMER_MODE)
	_rebuild.call_deferred(_category)

func _rebuild(category: String) -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	_category = category
	_build_menu()
	open_menu()
	_select_category(category)
