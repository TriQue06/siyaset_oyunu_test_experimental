extends Control
## ANA MENÜ: oyuncu adı, oda kurma ve koda göre odaya katılma tek ekranda.
##
## Bağlantı, internete açık bir röle sunucusu üzerinden kurulur (bkz.
## multiplayer_manager.gd, RELAY_URL). Oyuncular hiçbir IP/port bilgisi
## girmez; sadece oda kurulunca üretilen 5 harfli kod yeterlidir. Oda nerede
## kapanırsa kapansın oyuncu buraya sebebiyle birlikte döner.

## 0.0.265: giriş ekranının bütün ögeleri 1,5 kat (küçük kalıyordu).
const S := 1.5
const CARD_WIDTH := 320.0 * S
const ACCENT := UiTheme.GOLD
const BG_TOP := UiTheme.FELT_LIGHT
const BG_BOTTOM := UiTheme.FELT_DARK

var name_edit: LineEdit
var create_button: Button
var code_edit: LineEdit
var join_button: Button
var status_label: Label
## ÇEVRİM İÇİ / ÇEVRİM DIŞI ayrımı: çevrim dışında röle sunucusu, oda kodu ve
## katılma yoktur; oyun bu cihazda döner ve sadece bot eklenebilir.
var _online_mode: bool = true
var _online_tab: Button
var _offline_tab: Button
var _online_box: VBoxContainer
var _offline_box: VBoxContainer
var _offline_button: Button

func _ready() -> void:
	AudioManager.stop_music()  # menüler sessiz
	_build_background()
	_build_card()
	_build_footer()
	MultiplayerManager.room_created.connect(_on_room_created)
	MultiplayerManager.connection_error.connect(_on_connection_error)
	MultiplayerManager.join_failed.connect(_on_join_failed)
	MultiplayerManager.join_succeeded.connect(_on_join_succeeded)
	MultiplayerManager.connection_status.connect(_on_connection_status)
	GameSettings.streamer_mode_changed.connect(_on_streamer_mode_changed)
	# Oda (oyun ortasında bile) kapandıysa buraya sebebiyle birlikte dönülür.
	if MultiplayerManager.last_close_reason != "":
		_set_status(MultiplayerManager.last_close_reason, true)
		MultiplayerManager.last_close_reason = ""

# --- Görünüm ---------------------------------------------------------------------

func _build_background() -> void:
	add_child(TableSurface.felt())
	var bg := Control.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_background_gui_input)
	add_child(bg)
	# Arka planda silik bir meclis yayı.
	var arc := Control.new()
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arc.draw.connect(func():
		var center := Vector2(arc.size.x * 0.5, arc.size.y * 1.02)
		var rows := 9
		for row in rows:
			var radius := arc.size.y * (0.42 + row * 0.07)
			var count := 18 + row * 5
			for i in count:
				var a := PI + PI * (float(i) + 0.5) / count
				var color := Color(UiTheme.PANEL, 0.07) if (i + row) % 5 != 0 else Color(ACCENT, 0.12)
				arc.draw_circle(center + Vector2(cos(a), sin(a)) * radius, 7.0, color, true, -1.0, true))
	add_child(arc)

## Panel zemini: 9-slice PNG (pixel çerçeve). Renk parametresi kalmadı — tarz
## tek yerden geliyor; sadece koyu/normal ayrımı var.
func _panel_style(dark: bool = false, padding: int = 24) -> StyleBox:
	var style := UiSkin.stylebox(UiSkin.PANEL_DARK if dark else UiSkin.PANEL)
	style.set_content_margin_all(padding)
	return style

func _button(text: String, color: Color, height: float = 54.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, height * S)
	button.add_theme_font_size_override("font_size", int(UiTheme.FS_HEAD * S))
	UiSkin.skin_color_button(button, color)
	return button

func _field(placeholder: String, max_length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(0, 40 * S)
	edit.add_theme_font_override("font", UiTheme.mono())
	edit.add_theme_font_size_override("font_size", int(UiTheme.FS_HEAD * S))
	var style := UiSkin.stylebox(UiSkin.SLOT)
	style.set_content_margin_all(UiTheme.PAD_S)
	UiSkin.apply_style(edit, "normal", style)
	var focus := UiSkin.color_box(UiTheme.GOLD, UiSkin.SLOT)
	focus.set_content_margin_all(UiTheme.PAD_S)
	UiSkin.apply_style(edit, "focus", focus)
	return edit

func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", int(UiTheme.FS_SMALL * S))
	label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	return label

func _build_card() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(16 * S))
	center.add_child(column)

	# KİMLİK: ince, hap biçimli ayrı bir şerit (oda kartından farklı görünür).
	var profile := PanelContainer.new()
	var profile_style := _panel_style(false, UiTheme.PAD_M)
	profile_style.set_content_margin_all(10 * S)
	profile_style.content_margin_left = 18 * S
	profile_style.content_margin_right = 10 * S
	UiSkin.apply_style(profile, "panel", profile_style)
	# Oda kartıyla aynı genişlikte (sütun genişliği = CARD_WIDTH).
	column.add_child(profile)
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", int(10 * S))
	profile.add_child(profile_row)
	var who := _small_label(L.t("Oyuncu adın"))
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_theme_color_override("font_color", UiTheme.HEAD)
	who.add_theme_font_override("font", UiTheme.mono(true))
	profile_row.add_child(who)
	name_edit = _field(L.t("Oyuncu adı"), 20)
	name_edit.custom_minimum_size = Vector2(0, 34 * S)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", int(15 * S))
	name_edit.text = PlayerProfile.player_name
	name_edit.text_changed.connect(_on_name_changed)
	profile_row.add_child(name_edit)

	# ODA: kurma ve katılma.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var card_style := _panel_style(true, 24)
	card_style.set_content_margin_all(20 * S)
	UiSkin.apply_style(card, "panel", card_style)
	column.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(12 * S))
	card.add_child(box)

	# MOD SEÇİCİ: iki sekme. Seçili olan altın, diğeri sönük.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", int(8 * S))
	box.add_child(tabs)
	_online_tab = _button(L.t("Çevrim İçi"), ACCENT, 38.0)
	_online_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online_tab.add_theme_font_size_override("font_size", int(UiTheme.FS_BODY * S))
	_online_tab.pressed.connect(_set_mode.bind(true))
	tabs.add_child(_online_tab)
	_offline_tab = _button(L.t("Çevrim Dışı"), UiTheme.PANEL_LIGHT, 38.0)
	_offline_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offline_tab.add_theme_font_size_override("font_size", int(UiTheme.FS_BODY * S))
	_offline_tab.pressed.connect(_set_mode.bind(false))
	tabs.add_child(_offline_tab)

	# İki mod aynı yuvada üst üste: yuva ikisinin uzununa göre sabit, kart
	# sekme değişince boy değiştirmez.
	var mode_stack := PanelContainer.new()
	mode_stack.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	box.add_child(mode_stack)

	# ÇEVRİM DIŞI: tek buton, kod alanı ve katılma yok.
	_offline_box = VBoxContainer.new()
	_offline_box.add_theme_constant_override("separation", int(10 * S))
	_offline_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_stack.add_child(_offline_box)
	_offline_button = _button(L.t("Botlarla Oyna"), UiTheme.GREEN_DARK, 42.0)
	_offline_button.pressed.connect(_on_offline_pressed)
	_offline_box.add_child(_offline_button)
	# KAYITLI OYUN: elle kayıt ya da otomatik kayıt varsa en yenisinden devam.
	var slot := _latest_save()
	if slot != "":
		ResourceLoader.load_threaded_request("res://scenes/GameScreen.tscn")
		var info := SaveGame.summary(slot)
		var resume := _button(L.t("Kayıtlı Oyuna Devam Et"), UiTheme.BLUE.darkened(0.2), 42.0)
		resume.pressed.connect(func():
			resume.disabled = true
			var err := SaveGame.load_game(get_tree(), slot)
			if err != "":
				resume.disabled = false
				_set_status(err, true))
		_offline_box.add_child(resume)
		var when := _small_label("%s · %s" % [String(info.get("party", "")), String(info.get("period", ""))])
		when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_offline_box.add_child(when)

	_online_box = VBoxContainer.new()
	_online_box.add_theme_constant_override("separation", int(12 * S))
	_online_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_stack.add_child(_online_box)

	create_button = _button(L.t("Oda Kur"), ACCENT, 42.0)
	create_button.pressed.connect(_on_create_pressed)
	_online_box.add_child(create_button)

	var divider := HBoxContainer.new()
	divider.add_theme_constant_override("separation", int(8 * S))
	var left := HSeparator.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.add_child(left)
	divider.add_child(_small_label(L.t("ya da koda katıl")))
	var right := HSeparator.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.add_child(right)
	_online_box.add_child(divider)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", int(10 * S))
	code_edit = _field(L.t("ODA KODU"), 5)
	code_edit.custom_minimum_size = Vector2(0, 44 * S)
	code_edit.add_theme_font_size_override("font_size", int(16 * S))
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.secret_character = "•"
	code_edit.secret = GameSettings.streamer_mode
	code_edit.text_changed.connect(_on_code_text_changed)
	code_edit.text_submitted.connect(func(_t): _on_join_pressed())
	join_row.add_child(code_edit)
	join_button = _button(L.t("Katıl"), UiTheme.BLUE, 44.0)
	join_button.custom_minimum_size.x = 96 * S
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)
	_online_box.add_child(join_row)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(CARD_WIDTH - 40.0 * S, 18 * S)
	status_label.add_theme_font_size_override("font_size", int(12 * S))
	box.add_child(status_label)
	mode_stack.custom_minimum_size.y = maxf(_online_box.get_combined_minimum_size().y,
		_offline_box.get_combined_minimum_size().y)
	_set_mode(true)

## Mod sekmesi değişti: ilgili kutu görünür, diğeri gizlenir.
func _set_mode(online: bool) -> void:
	_online_mode = online
	_online_box.visible = online
	_offline_box.visible = not online
	UiSkin.skin_color_button(_online_tab, ACCENT if online else UiTheme.PANEL_LIGHT)
	UiSkin.skin_color_button(_offline_tab, UiTheme.PANEL_LIGHT if online else UiTheme.GREEN_DARK)
	_set_status("")

func _build_footer() -> void:
	var version := Label.new()
	version.text = L.t("sürüm %s") % MultiplayerManager.game_version()
	version.add_theme_font_size_override("font_size", int(13 * S))
	version.add_theme_color_override("font_color", Color(UiTheme.PANEL, 0.6))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.position += Vector2(16, -40)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)
	var quit := _button(L.t("Çıkış"), UiTheme.PANEL_LIGHT, 36.0)
	quit.add_theme_font_size_override("font_size", int(13 * S))
	quit.custom_minimum_size.x = 84 * S
	quit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quit.position += Vector2(-84 * S - 16, -36 * S - 18)
	quit.pressed.connect(func(): get_tree().quit())
	add_child(quit)

func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", UiTheme.RED if is_error else UiTheme.TEXT_MUTED)

# --- Olaylar ---------------------------------------------------------------------

## Boş bir yere tıklanınca yazı imleci kutuda takılı kalmasın.
func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func _on_name_changed(new_text: String) -> void:
	var trimmed := new_text.strip_edges()
	if trimmed != "":
		PlayerProfile.player_name = trimmed

## Yayıncı modu açıkken kod kutusu noktalarla gizlenir.
func _on_streamer_mode_changed(enabled: bool) -> void:
	code_edit.secret = enabled

func _on_code_text_changed(new_text: String) -> void:
	# Kod sadece büyük İngilizce harflerden oluşur (A-Z), rakam/sembol yok.
	var filtered := ""
	for c in new_text.to_upper():
		if c >= "A" and c <= "Z":
			filtered += c
	if filtered != new_text:
		code_edit.text = filtered
		code_edit.caret_column = filtered.length()

func _player_name() -> String:
	var trimmed := name_edit.text.strip_edges()
	return trimmed if trimmed != "" else PlayerProfile.player_name

## En yeni kayıt yuvası (elle kayıt ya da otomatik kayıt; yoksa "").
static func _latest_save() -> String:
	var best := ""
	var best_time := -1
	for slot in [SaveGame.MANUAL_SLOT, SaveGame.AUTOSAVE_SLOT]:
		if SaveGame.exists(slot):
			var t := FileAccess.get_modified_time(SaveGame.path_of(slot))
			if t > best_time:
				best_time = t
				best = slot
	return best

## ÇEVRİM DIŞI: ağa hiç çıkılmaz, doğrudan lobiye geçilir.
func _on_offline_pressed() -> void:
	_offline_button.disabled = true
	MultiplayerManager.start_offline(_player_name())

func _on_create_pressed() -> void:
	create_button.disabled = true
	join_button.disabled = true
	_set_status(L.t("Oda kuruluyor..."))
	MultiplayerManager.create_room(_player_name())

func _on_join_pressed() -> void:
	var code := code_edit.text.strip_edges()
	if code.length() != 5:
		_set_status(L.t("Oda kodu 5 harfli olmalı."), true)
		return
	_set_status(L.t("Bağlanılıyor..."))
	create_button.disabled = true
	join_button.disabled = true
	MultiplayerManager.join_room(code, _player_name())

func _on_connection_status(text: String) -> void:
	_set_status(text)

func _on_room_created(_code: String) -> void:
	get_tree().change_scene_to_file("res://scenes/RoomLobby.tscn")

func _on_join_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/RoomLobby.tscn")

func _on_connection_error(reason: String) -> void:
	_set_status(reason, true)
	create_button.disabled = false
	join_button.disabled = false
	_offline_button.disabled = false

func _on_join_failed(reason: String) -> void:
	_set_status(reason, true)
	create_button.disabled = false
	join_button.disabled = false
	_offline_button.disabled = false
