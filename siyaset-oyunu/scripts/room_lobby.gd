extends Control
## ODA LOBİSİ (0.0.278, konsept C "komuta panosu"): her şey tek ekranda,
## kaydırma yok.
##   - Solda sekiz satırlık OYUNCU listesi: pul, ad, rol; oda sahibine
##     Devret / At (insan) ve Çıkar (bot); boş satırda kesik çizgili sandalye
##     ve ilk boş satırda "Bot" ekleme düğmesi.
##   - Ortada ÜLKE: tohum girildiyse ya da Türkiye haritasıysa haritanın
##     önizlemesi (yoksa "her oyunda rastgele"); "Yeni harita" rastgele bir
##     tohum verir. Altta dört büyük rakamla oyunun özeti.
##   - Sağda katlanır KURAL bölümleri: biri açıkken diğerleri tek satırda
##     seçili değeri gösterir. Herkes görür, yalnız oda sahibi değiştirir.
##   - Altta solda "Ayrıl", sağda "Oyunu başlat".
## Arayüz tamamen kodla kurulur (sahne yalnız kök düğüm). Ölçüler konseptin
## 1280×720 ekranındaki pikselleri (konseptler/lobi_konseptleri.html).

const MAP_SCENE := preload("res://scenes/Map.tscn")
const CREAM := Color("FFF6E0")
const MINT := Color("D8EFE2")
const MUTED2 := Color("9A9082")
const FELT_INK := Color("0B3A28")
const SEA := Color("93D2D7")
const ROW_H := 50.0
## Harita önizlemesi ayar değiştikçe bu kadar bekleyip bir kez üretilir.
const MAP_DEBOUNCE := 0.3

const ICON_PATHS := {
	"bot": '<rect x="5" y="8" width="14" height="11" rx="3"/><path d="M12 4v4M9 13h.01M15 13h.01M9 16h6"/>',
	"map": '<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
	"ballot": '<rect x="4" y="11" width="16" height="9" rx="2"/><path d="M8 11V5h8v6M10 8h4"/>',
	"clock": '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6"/>',
	"dice": '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M9 9h.01M15 15h.01M15 9h.01M9 15h.01M12 12h.01"/>',
}

# Testlerin ve önizlemelerin eriştiği denetimler.
var player_list_box: VBoxContainer
var start_button: Button
var leave_button: Button
var copy_code_button: Button
var code_label: Label
var info_label: Label
var interval_value_label: Label
var interval_minus: Button
var interval_plus: Button
var count_value_label: Label
var count_minus: Button
var count_plus: Button
var game_length_summary: Label
var threshold_slider: HSlider
var threshold_value_label: Label
var map_seed_edit: LineEdit
var random_parties_check: CheckButton
var alliances_check: CheckButton
var away_bot_check: CheckButton
var bot_funds_buttons: Array = []
## Kaydırıcılı dünya ayarları (il / ulusal milletvekili): ayar -> HSlider.
var world_controls: Dictionary = {}
var world_values: Dictionary = {}
## Düğmeli dünya ayarları (tur süresi, miting / yatırım sınırı): ayar -> düğmeler.
var world_choice_buttons: Dictionary = {}
var density_buttons: Array[Button] = []
var map_mode_buttons: Array[Button] = []
var vote_time_buttons: Array[Button] = []
## Kural bölümleri: kimlik -> {"body": Control, "summary": Label, "header": Button}.
var _sections: Dictionary = {}
var _open_section: String = "map"

var _player_count_label: Label
var _seed_note: Label
var _new_map_button: Button
var _map_clip: Control
var _map: Node2D
var _map_placeholder: Control
var _map_timer: Timer
var _shown_map_key: String = ""
var _facts: Dictionary = {}
var _icon_cache: Dictionary = {}

func _ready() -> void:
	add_child(TableSurface.felt())
	_build()
	_refresh_code_display()
	GameSettings.streamer_mode_changed.connect(_on_streamer_mode_changed)
	MultiplayerManager.player_list_updated.connect(_refresh)
	MultiplayerManager.settings_updated.connect(_refresh_settings_display)
	MultiplayerManager.room_closed.connect(_on_room_closed)
	MultiplayerManager.game_started.connect(_on_game_started)
	_refresh()

# --- Kurulum ------------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	column.add_child(_build_top())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	body.add_child(_build_players())
	body.add_child(_build_country())
	body.add_child(_build_rules())
	column.add_child(_build_footer())
	_map_timer = Timer.new()
	_map_timer.one_shot = true
	_map_timer.wait_time = MAP_DEBOUNCE
	_map_timer.timeout.connect(_update_map_preview)
	add_child(_map_timer)

func _build_top() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 52
	row.add_theme_constant_override("separation", 14)
	var title := UiTheme.mono_label(L.t("Oda"), 34, CREAM, true)
	title.add_theme_color_override("font_shadow_color", FELT_INK)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	# BİLET: oda kodu ve Kopyala (çevrim dışında yalnız "ÇEVRİM DIŞI OYUN").
	var ticket := PanelContainer.new()
	var style := BoardBox.new()
	style.fill = UiTheme.PANEL
	style.set_radius(14)
	style.lips = [[4.0, UiTheme.EDGE]]
	style.content_margin_left = 14
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	ticket.add_theme_stylebox_override("panel", style)
	ticket.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ticket)
	var ticket_row := HBoxContainer.new()
	ticket_row.add_theme_constant_override("separation", 10)
	ticket.add_child(ticket_row)
	var key := _small(L.t("ODA KODU"), UiTheme.TEXT_MUTED, 11)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.name = "Key"
	ticket_row.add_child(key)
	code_label = UiTheme.mono_label("", 26, UiTheme.TEXT, true)
	code_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ticket_row.add_child(code_label)
	copy_code_button = _teal_button(L.t("Kopyala"), 14)
	copy_code_button.custom_minimum_size = Vector2(0, 36)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	ticket_row.add_child(copy_code_button)
	# Sağ üstteki Menü düğmesine (SettingsOverlay) yer.
	var menu_gap := Control.new()
	menu_gap.custom_minimum_size.x = 120
	row.add_child(menu_gap)
	return row

## Solda oyuncu listesi.
func _build_players() -> Control:
	var board := _board()
	board.custom_minimum_size.x = 300
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	board.add_child(box)
	var head := _section_header(L.t("Oyuncular"))
	box.add_child(head[0])
	_player_count_label = head[1]
	player_list_box = VBoxContainer.new()
	player_list_box.add_theme_constant_override("separation", 7)
	box.add_child(player_list_box)
	return board

## Ortada ülke önizlemesi ve oyunun özeti.
func _build_country() -> Control:
	var board := _board()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	board.add_child(box)
	var head := _section_header(L.t("Ülke"))
	box.add_child(head[0])
	_seed_note = head[1]
	var frame := PanelContainer.new()
	var sea := BoardBox.new()
	sea.fill = SEA
	sea.set_radius(14)
	sea.rings = [[0.0, 3.0, UiTheme.TEAL]]
	sea.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", sea)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	_map_clip = Control.new()
	_map_clip.clip_contents = true
	_map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_clip.resized.connect(_fit_map)
	frame.add_child(_map_clip)
	_map_placeholder = _build_map_placeholder()
	frame.add_child(_map_placeholder)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	_new_map_button = _chip_button(L.t("Yeni harita"), "dice")
	_new_map_button.pressed.connect(_on_new_map_pressed)
	bar.add_child(_new_map_button)
	map_seed_edit = LineEdit.new()
	map_seed_edit.placeholder_text = L.t("Rastgele")
	map_seed_edit.max_length = MultiplayerManager.MAP_SEED_MAX_DIGITS
	map_seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	map_seed_edit.custom_minimum_size = Vector2(130, 34)
	map_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_seed_edit.add_theme_font_override("font", UiTheme.mono(true))
	map_seed_edit.add_theme_font_size_override("font_size", 15)
	map_seed_edit.tooltip_text = L.t("Aynı tohum her zaman aynı ülkeyi üretir. Boş bırakırsan her oyunda rastgele.")
	map_seed_edit.text_submitted.connect(func(text: String): MultiplayerManager.set_map_seed(text))
	map_seed_edit.focus_exited.connect(func(): MultiplayerManager.set_map_seed(map_seed_edit.text))
	bar.add_child(map_seed_edit)
	var note := _small(L.t("Aynı tohum her zaman aynı ülkeyi üretir."), UiTheme.TEXT_MUTED, 12)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 1
	bar.add_child(note)
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 8)
	box.add_child(facts)
	for key in ["start", "elections", "seats", "threshold"]:
		var card := PanelContainer.new()
		var style := UiSkin.card()
		style.content_margin_top = 8
		style.content_margin_bottom = 7
		style.content_margin_left = 4
		style.content_margin_right = 4
		card.add_theme_stylebox_override("panel", style)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts.add_child(card)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 3)
		card.add_child(inner)
		var value := UiTheme.mono_label("", 24, UiTheme.TEXT, true)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(value)
		var caption: String = {"start": L.t("BAŞLANGIÇ"), "elections": L.t("SEÇİM"), "seats": L.t("VEKİL"), "threshold": L.t("BARAJ")}[key]
		var label := _small(caption, UiTheme.TEXT_MUTED, 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(label)
		_facts[key] = value
	return board

func _build_map_placeholder() -> Control:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	var icon := _icon("dice", 44, UiTheme.TEAL, 2.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var title := UiTheme.mono_label(L.t("Her oyunda rastgele ülke"), 20, UiTheme.TEAL_DARK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := _small(L.t("Haritayı önceden görmek için \"Yeni harita\"ya dokun ya da tohum yaz."), UiTheme.TEAL_DARK, 12)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	return center

## Sağda katlanır kural bölümleri.
func _build_rules() -> Control:
	var board := _board()
	board.custom_minimum_size.x = 360
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	board.add_child(box)
	box.add_child(_section_header(L.t("Kurallar"))[0])

	# HARİTA VE MECLİS
	var map_body := _rule_section(box, "map", "map", L.t("Harita ve meclis"))
	map_body.add_child(_row_name(L.t("Harita")))
	var mode_row := _seg_row()
	map_body.add_child(mode_row)
	var mode_names := {"random": L.t("Rastgele"), "turkiye_altigen": L.t("Türkiye")}
	for mode in MultiplayerManager.WORLD_OPTIONS["map_mode"]:
		var button := _seg_button(String(mode_names[mode]))
		button.set_meta("value", mode)
		button.pressed.connect(func(): MultiplayerManager.set_world_setting("map_mode", String(button.get_meta("value"))))
		mode_row.add_child(button)
		map_mode_buttons.append(button)
	map_body.add_child(_row_name(L.t("İl sayısı")))
	var density_row := _seg_row()
	map_body.add_child(density_row)
	for i in 3:
		var button := _seg_button([L.t("Az"), L.t("Ortalama"), L.t("Fazla")][i])
		button.set_meta("value", MultiplayerManager.WORLD_OPTIONS["province_scale"][i])
		button.pressed.connect(func(): MultiplayerManager.set_world_setting("province_scale", button.get_meta("value")))
		density_row.add_child(button)
		density_buttons.append(button)
	for key in ["province_seats", "national_seats"]:
		world_values[key] = _value_row(map_body, L.t("İl milletvekilleri") if key == "province_seats" else L.t("Ulusal milletvekilleri"))
		var control := _slider()
		var values: Array = MultiplayerManager.WORLD_OPTIONS[key]
		control.min_value = float(values[0])
		control.max_value = float(values[-1])
		control.step = float(values[1]) - float(values[0])
		control.set_meta("key", key)
		control.value_changed.connect(func(value: float): MultiplayerManager.set_world_setting(String(control.get_meta("key")), int(value)))
		map_body.add_child(control)
		world_controls[key] = control

	# SEÇİMLER
	var vote_body := _rule_section(box, "elections", "ballot", L.t("Seçimler"))
	var interval_row := _stepper_row(vote_body, L.t("Seçimler kaç yılda bir"))
	interval_minus = interval_row[0]
	interval_value_label = interval_row[1]
	interval_plus = interval_row[2]
	var count_row := _stepper_row(vote_body, L.t("Kaç seçim olacak"))
	count_minus = count_row[0]
	count_value_label = count_row[1]
	count_plus = count_row[2]
	interval_minus.pressed.connect(func(): _change_game_length(-GameRules.ELECTION_INTERVAL_STEP, 0))
	interval_plus.pressed.connect(func(): _change_game_length(GameRules.ELECTION_INTERVAL_STEP, 0))
	count_minus.pressed.connect(func(): _change_game_length(0, -1))
	count_plus.pressed.connect(func(): _change_game_length(0, 1))
	game_length_summary = _small("", UiTheme.HEAD, 12)
	game_length_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_length_summary.custom_minimum_size.x = 1
	vote_body.add_child(game_length_summary)
	threshold_value_label = _value_row(vote_body, L.t("Seçim barajı"))
	threshold_slider = _slider()
	threshold_slider.min_value = MultiplayerManager.THRESHOLD_MIN
	threshold_slider.max_value = MultiplayerManager.THRESHOLD_MAX
	threshold_slider.step = MultiplayerManager.THRESHOLD_STEP
	threshold_slider.value_changed.connect(func(value: float): MultiplayerManager.set_election_threshold(value))
	vote_body.add_child(threshold_slider)
	alliances_check = _switch(L.t("İttifaklar açık"),
		L.t("Açıksa partiler ittifak kurabilir; barajda ortak oy sayılır. Oyun içinde anayasayla değişebilir."))
	alliances_check.toggled.connect(func(on: bool): MultiplayerManager.set_world_setting("alliances", on))
	vote_body.add_child(alliances_check)

	# SÜRELER
	var time_body := _rule_section(box, "timing", "clock", L.t("Süreler"))
	for key in ["turn_seconds", "vote", "action_limit"]:
		var heading: String = {"turn_seconds": L.t("Tur süresi"), "vote": L.t("Meclis oylama süresi"),
			"action_limit": L.t("Sırada miting / yatırım sınırı")}[key]
		time_body.add_child(_row_name(heading))
		var row := _seg_row()
		time_body.add_child(row)
		if key == "vote":
			for seconds in MultiplayerManager.VOTE_TIME_OPTIONS:
				var button := _seg_button(str(seconds))
				button.set_meta("seconds", seconds)
				button.pressed.connect(func(): MultiplayerManager.set_vote_timeout(int(button.get_meta("seconds"))))
				row.add_child(button)
				vote_time_buttons.append(button)
			continue
		var buttons: Array = []
		for value in MultiplayerManager.WORLD_OPTIONS[key]:
			var button := _seg_button(str(value))
			button.set_meta("value", value)
			button.pressed.connect(func(): MultiplayerManager.set_world_setting(key, button.get_meta("value")))
			row.add_child(button)
			buttons.append(button)
		world_choice_buttons[key] = buttons

	# BOTLAR VE ODA
	var bot_body := _rule_section(box, "bots", "bot", L.t("Botlar ve oda"))
	random_parties_check = _switch(L.t("Yeni partiler katılabilir"),
		L.t("Açıksa seçimlerden sonra arada bir yeni bir parti (bot) kurulur; bir iki seçim sonra kendini fesheder."))
	random_parties_check.toggled.connect(func(on: bool): MultiplayerManager.set_random_parties(on))
	bot_body.add_child(random_parties_check)
	away_bot_check = _switch(L.t("Yerine bot oynasın"),
		L.t("Bağlantısı kopan oyuncunun yerine bot oynar ya da dönene kadar pasif kalır (sırası geçer, oylarda çekimser). Aynı cihazdan odaya yeniden katılınca kaldığı yerden devam eder."))
	away_bot_check.toggled.connect(func(on: bool): MultiplayerManager.set_away_mode(
		MultiplayerManager.AWAY_BOT if on else MultiplayerManager.AWAY_PASSIVE))
	bot_body.add_child(away_bot_check)
	var funds_name := _row_name(L.t("Bot gelir zayıflatması"))
	funds_name.tooltip_text = L.t("Botların dönemlik geliri ve bağış kampanyaları seçilen tutar kadar (¤ M) azalır. 0 = zayıflatma yok.")
	funds_name.mouse_filter = Control.MOUSE_FILTER_PASS
	bot_body.add_child(funds_name)
	var funds_row := _seg_row()
	bot_body.add_child(funds_row)
	for value in MultiplayerManager.BOT_FUNDS_PENALTY_OPTIONS:
		var button := _seg_button(("%.1f" % float(value)).replace(".0", "").replace(".", ","))
		button.set_meta("value", float(value))
		button.pressed.connect(func(): MultiplayerManager.set_bot_funds_penalty(float(value)))
		funds_row.add_child(button)
		bot_funds_buttons.append(button)
	_apply_open_section()
	return board

## Altta solda "Ayrıl", ortada bilgi, sağda "Oyunu başlat".
func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	start_button = Button.new()
	start_button.text = L.t("Oyunu başlat")
	start_button.custom_minimum_size = Vector2(190, 54)
	start_button.add_theme_font_size_override("font_size", 20)
	UiSkin.skin_color_button(start_button, UiTheme.GREEN_DARK)
	start_button.pressed.connect(func(): MultiplayerManager.start_game())
	info_label = Label.new()
	info_label.add_theme_font_override("font", UiTheme.body_black())
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", MINT)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.x = 1
	row.add_child(info_label)
	leave_button = Button.new()
	leave_button.text = L.t("Ayrıl")
	leave_button.custom_minimum_size = Vector2(110, 54)
	leave_button.add_theme_font_size_override("font_size", 20)
	UiSkin.skin_color_button(leave_button, UiTheme.PANEL)
	leave_button.add_theme_color_override("font_color", UiTheme.TEAL)
	leave_button.add_theme_color_override("font_hover_color", UiTheme.TEAL)
	leave_button.add_theme_color_override("font_pressed_color", UiTheme.TEAL)
	leave_button.pressed.connect(_on_leave_pressed)
	row.add_child(leave_button)
	row.move_child(leave_button, 0)
	row.add_child(start_button)
	return row

# --- Tazeleme -----------------------------------------------------------------

func _refresh() -> void:
	_clear(player_list_box)
	var am_owner := MultiplayerManager.is_local_owner()
	var local_id := multiplayer.get_unique_id()
	# Satırlar sırayla dolar: önce insanlar, sonra botlar, sonra boş yerler. Bot
	# sadece İLK boş yere eklenebilir.
	var order := MultiplayerManager.lobby_order()
	for i in MultiplayerManager.MAX_PLAYERS:
		if i < order.size():
			player_list_box.add_child(_player_row(int(order[i]), i, am_owner, local_id))
		else:
			player_list_box.add_child(_empty_row(i, am_owner and i == order.size()))
	var count := MultiplayerManager.players.size()
	_player_count_label.text = "%d / %d" % [count, MultiplayerManager.MAX_PLAYERS]
	start_button.visible = am_owner
	start_button.disabled = count < MultiplayerManager.MIN_PLAYERS_TO_START
	threshold_slider.editable = am_owner
	random_parties_check.disabled = not am_owner
	alliances_check.disabled = not am_owner
	away_bot_check.disabled = not am_owner
	for button in bot_funds_buttons:
		(button as Button).disabled = not am_owner
	_new_map_button.disabled = not am_owner
	_refresh_settings_display()

func _refresh_settings_display() -> void:
	var owner := MultiplayerManager.is_local_owner()
	var settings: Dictionary = MultiplayerManager.world_settings
	var turkey: bool = String(settings["map_mode"]) != "random"
	for key in world_controls:
		var control: HSlider = world_controls[key]
		control.set_value_no_signal(float(settings[key]))
		world_values[key].text = str(settings[key])
		control.editable = owner
	# Türkiye haritası: 81 il ve gerçek vekil dağılımı sabit; yalnız ulusal liste ayarlanır.
	if turkey and world_controls.has("province_seats"):
		(world_controls["province_seats"] as HSlider).editable = false
		world_values["province_seats"].text = L.t("%d (sabit)") % GameMap.preset_seat_total(String(settings["map_mode"]))
	for button in map_mode_buttons:
		_mark_seg(button, String(button.get_meta("value")) == String(settings["map_mode"]), not owner)
	for button in density_buttons:
		_mark_seg(button, is_equal_approx(float(button.get_meta("value")), float(settings["province_scale"])), not owner or turkey)
	for key in world_choice_buttons:
		for button in world_choice_buttons[key]:
			_mark_seg(button, button.get_meta("value") == settings[key], not owner)
	for button in vote_time_buttons:
		_mark_seg(button, int(button.get_meta("seconds")) == MultiplayerManager.vote_timeout, not owner)
	for button in bot_funds_buttons:
		_mark_seg(button, is_equal_approx(float(button.get_meta("value")), MultiplayerManager.bot_funds_penalty), not owner)
	map_seed_edit.editable = owner and not turkey
	map_seed_edit.placeholder_text = L.t("Türkiye haritasında tohum yok") if turkey else L.t("Rastgele")
	if not map_seed_edit.has_focus():
		map_seed_edit.text = "" if turkey else MultiplayerManager.map_seed
	_new_map_button.disabled = not owner or turkey
	random_parties_check.set_pressed_no_signal(MultiplayerManager.random_parties)
	alliances_check.set_pressed_no_signal(bool(settings.get("alliances", true)))
	away_bot_check.set_pressed_no_signal(MultiplayerManager.away_mode == MultiplayerManager.AWAY_BOT)
	for check in [random_parties_check, alliances_check, away_bot_check]:
		check.queue_redraw()

	var t := MultiplayerManager.election_threshold
	var interval := MultiplayerManager.election_interval
	var count := MultiplayerManager.election_count
	interval_value_label.text = GameRules.years_text(interval)
	count_value_label.text = str(count)
	var years: Array = []
	for i in range(1, count + 1):
		years.append(_election_date(interval * i))
	if years.size() > 5:
		years = years.slice(0, 3) + ["…"] + years.slice(years.size() - 1)
	game_length_summary.text = L.t("%d'de başlar, %s yıl sürer (bir tur 6 ay). Seçimler: %s.") % [GameRules.START_YEAR,
		GameRules.years_text(interval * count), ", ".join(PackedStringArray(years))]
	for button in [interval_minus, interval_plus, count_minus, count_plus]:
		button.disabled = not owner
	if owner:
		interval_minus.disabled = interval <= GameRules.ELECTION_INTERVAL_MIN
		interval_plus.disabled = interval >= GameRules.ELECTION_INTERVAL_MAX
		count_minus.disabled = count <= GameRules.ELECTION_COUNT_MIN
		count_plus.disabled = count >= GameRules.ELECTION_COUNT_MAX
	threshold_value_label.text = "%%%s" % _format_threshold(t)
	if not threshold_slider.has_focus():
		threshold_slider.set_value_no_signal(t)

	# Özet rakamlar ve kapalı bölümlerin tek satırı.
	var district := GameMap.preset_seat_total(String(settings["map_mode"])) if turkey else int(settings["province_seats"])
	var seats := district + int(settings["national_seats"])
	_facts["start"].text = str(GameRules.START_YEAR)
	_facts["elections"].text = str(count)
	_facts["seats"].text = str(seats)
	_facts["threshold"].text = "%%%s" % _format_threshold(t)
	var mode_text := L.t("Türkiye") if turkey else L.t("Rastgele")
	_sections["map"]["summary"].text = "%s · %d" % [mode_text, seats]
	_sections["elections"]["summary"].text = L.t("%d seçim · %%%s") % [count, _format_threshold(t)]
	_sections["timing"]["summary"].text = L.t("%d sn · %d sn") % [int(settings["turn_seconds"]), MultiplayerManager.vote_timeout]
	_sections["bots"]["summary"].text = L.t("zayıflatma %s") % ("%.1f" % MultiplayerManager.bot_funds_penalty).replace(".0", "").replace(".", ",")
	_seed_note.text = L.t("Türkiye") if turkey else (L.t("tohum: %s") % MultiplayerManager.map_seed if MultiplayerManager.map_seed != "" else L.t("tohum: rastgele"))
	info_label.text = _footer_text()
	_map_timer.start()

func _footer_text() -> String:
	var count := MultiplayerManager.players.size()
	var interval := MultiplayerManager.election_interval
	var length := L.t("%d'de başlar · %d seçim, %s yılda bir · %s yıl") % [GameRules.START_YEAR,
		MultiplayerManager.election_count, GameRules.years_text(interval),
		GameRules.years_text(interval * MultiplayerManager.election_count)]
	if count < MultiplayerManager.MIN_PLAYERS_TO_START:
		return L.t("Başlamak için en az %d oyuncu gerekir.") % MultiplayerManager.MIN_PLAYERS_TO_START
	if not MultiplayerManager.is_local_owner():
		return L.t("Oyunu oda sahibi başlatır · %s") % length
	return length

## Harita önizlemesi: Türkiye ya da tohumlu rastgele harita çizilir; tohumsuz
## rastgele haritada yer tutucu görünür (her oyunda başka ülke).
var _preview_thread: Thread
var _preview_job_key := ""

func _exit_tree() -> void:
	if _preview_thread != null:
		_preview_thread.wait_to_finish()

func _update_map_preview() -> void:
	var settings: Dictionary = MultiplayerManager.world_settings
	var turkey: bool = String(settings["map_mode"]) != "random"
	var has_seed: bool = MultiplayerManager.map_seed != ""
	var show := turkey or has_seed
	_map_placeholder.visible = not show
	_map_clip.visible = show
	if not show:
		return
	var key := "%s|%s|%s|%s" % [settings["map_mode"], MultiplayerManager.map_seed, settings["province_scale"], settings["province_seats"]]
	if key == _shown_map_key and _map != null:
		return
	if turkey:
		GameMap.generate_new(int(MultiplayerManager.map_seed) if has_seed else 1)
	else:
		if _preview_thread == null:
			var seed_value := int(MultiplayerManager.map_seed)
			var scale_value := float(settings["province_scale"])
			var seats_value := int(settings["province_seats"])
			_preview_job_key = key
			_preview_thread = Thread.new()
			_preview_thread.start(func() -> Dictionary:
				var generated := CountryGenerator.generate(seed_value, scale_value, seats_value)
				return {"data": generated, "geometry": CountryGenerator.geometry(generated)})
			_map_timer.start(0.05)
			return
		if _preview_thread.is_alive():
			_map_timer.start(0.05)
			return
		var result: Dictionary = _preview_thread.wait_to_finish()
		_preview_thread = null
		if key != _preview_job_key:
			_map_timer.start(0.05)
			return
		GameMap.set_data(result["data"], result["geometry"])
	_shown_map_key = key
	if _map == null:
		_map = MAP_SCENE.instantiate()
		_map_clip.add_child(_map)
		var markers := _map.get_node_or_null("SeatMarkers")
		if markers != null:
			markers.visible = false
	# İller krem karton (konsept): parti rengi yokken koyu görünmesinler.
	var creams := [Color("F7EED8"), Color("EFE2C0"), Color("F3E7C9"), Color("E9DBB5"), Color("F5EBD2")]
	var colors := {}
	var ids: Array = GameMap.province_ids()
	for i in ids.size():
		colors[ids[i]] = creams[i % creams.size()]
	_map.clear_overlay()
	_map.set_province_colors(colors)
	_fit_map.call_deferred()

func _fit_map() -> void:
	if _map == null or _map_clip == null:
		return
	var native := GameMap.map_size()
	var space := _map_clip.size - Vector2(12, 12)
	if native.x <= 0.0 or native.y <= 0.0 or space.x <= 0.0 or space.y <= 0.0:
		return
	var s := minf(space.x / native.x, space.y / native.y)
	_map.scale = Vector2(s, s)
	_map.position = (_map_clip.size - native * s) * 0.5

func _refresh_code_display() -> void:
	var key := code_label.get_parent().get_node("Key") as Label
	if MultiplayerManager.offline_mode:
		# ÇEVRİM DIŞI modda oda kodu yok: kod ve kopyala gizlenir.
		key.hide()
		code_label.text = L.t("ÇEVRİM DIŞI OYUN")
		code_label.add_theme_font_size_override("font_size", 18)
		copy_code_button.hide()
		return
	key.show()
	copy_code_button.show()
	code_label.text = "•••••" if GameSettings.streamer_mode else MultiplayerManager.room_code

# --- Oyuncu satırları -----------------------------------------------------------

func _player_color(index: int) -> Color:
	return PartyPresets.COLORS[(index * 7) % PartyPresets.COLORS.size()]

func _player_row(peer_id: int, index: int, am_owner: bool, local_id: int) -> Control:
	var pdata: Dictionary = MultiplayerManager.players[peer_id]
	var is_bot := MultiplayerManager.is_bot(peer_id)
	var player_name: String = pdata.get("name", "?")
	var row := PanelContainer.new()
	var style := UiSkin.card()
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	row.add_theme_stylebox_override("panel", style)
	row.custom_minimum_size.y = ROW_H
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 9)
	row.add_child(line)
	var pawn := Pawn.new()
	pawn.color = _player_color(index)
	pawn.text = "" if is_bot else player_name.substr(0, 1).to_upper()
	pawn.robot = is_bot
	pawn.custom_minimum_size = Vector2(34, 34)
	pawn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(pawn)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 1)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(texts)
	var name_label := UiTheme.mono_label(player_name, 15, UiTheme.TEXT, true)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 1
	texts.add_child(name_label)
	var roles: Array = []
	if peer_id == MultiplayerManager.owner_id:
		roles.append(L.t("Oda sahibi"))
	if peer_id == local_id:
		roles.append(L.t("sen"))
	if is_bot:
		roles.append(L.t("Bot"))
	elif roles.is_empty():
		roles.append(L.t("Oyuncu"))
	var role := Label.new()
	role.text = " · ".join(roles)
	role.add_theme_font_size_override("font_size", 11)
	role.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	texts.add_child(role)
	if am_owner and peer_id != local_id:
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 4)
		actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(actions)
		if is_bot:
			var remove := _mini_button(L.t("Çıkar"), true)
			remove.pressed.connect(func(): MultiplayerManager.remove_bot(peer_id))
			actions.add_child(remove)
		else:
			var transfer := _mini_button(L.t("Devret"), false)
			transfer.pressed.connect(func(): MultiplayerManager.transfer_ownership(peer_id))
			actions.add_child(transfer)
			var kick := _mini_button(L.t("At"), true)
			kick.pressed.connect(func(): MultiplayerManager.kick_player(peer_id))
			actions.add_child(kick)
	return row

## Boş yer: kesik çizgili çerçeve ve sandalye; ilk boş yerde "Bot" düğmesi.
func _empty_row(index: int, can_add: bool) -> Control:
	var row := DashedBox.new()
	row.custom_minimum_size.y = ROW_H
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 9
	line.offset_right = -9
	line.add_theme_constant_override("separation", 9)
	row.add_child(line)
	var chair := DashedBox.new()
	chair.circle = true
	chair.custom_minimum_size = Vector2(34, 34)
	chair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chair)
	var label := UiTheme.mono_label("%d · %s" % [index + 1, L.t("Bot ekle") if MultiplayerManager.offline_mode else L.t("Boş")], 15, MUTED2, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	if can_add:
		var add := _mini_button(L.t("Bot"), false, "bot")
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add.pressed.connect(MultiplayerManager.add_bot)
		line.add_child(add)
	return row

# --- Kural bölümleri ----------------------------------------------------------------

## Katlanır bölüm: başlık satırı (simge, ad, kapalıyken seçili değer, "+")
## ve içerik kutusu. İçerik kutusunu döner.
func _rule_section(parent: Control, id: String, icon_key: String, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := UiSkin.card()
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var header := Button.new()
	header.flat = true
	header.focus_mode = Control.FOCUS_NONE
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		header.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	header.custom_minimum_size.y = 22
	header.pressed.connect(_on_section_pressed.bind(id))
	box.add_child(header)
	var head_row := HBoxContainer.new()
	head_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	head_row.add_theme_constant_override("separation", 8)
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(head_row)
	head_row.add_child(_icon(icon_key, 20, UiTheme.TEAL, 2.2))
	var name_label := UiTheme.mono_label(title, 16, UiTheme.TEAL, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(name_label)
	var summary := _small("", MUTED2, 12)
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(summary)
	var plus := UiTheme.mono_label("+", 16, UiTheme.TEAL, true)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(plus)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	box.add_child(body)
	_sections[id] = {"body": body, "summary": summary, "plus": plus}
	return body

func _on_section_pressed(id: String) -> void:
	_open_section = id
	_apply_open_section()

func _apply_open_section() -> void:
	for id in _sections:
		var open: bool = id == _open_section
		(_sections[id]["body"] as Control).visible = open
		(_sections[id]["summary"] as Control).visible = not open
		(_sections[id]["plus"] as Control).visible = not open

# --- Etkileşim ------------------------------------------------------------------

func _change_game_length(interval_delta: float, count_delta: int) -> void:
	MultiplayerManager.set_game_length(MultiplayerManager.election_interval + interval_delta,
		MultiplayerManager.election_count + count_delta)

func _on_new_map_pressed() -> void:
	MultiplayerManager.set_map_seed(str(randi_range(1, 999999999)))

func _on_streamer_mode_changed(_enabled: bool) -> void:
	_refresh_code_display()

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(MultiplayerManager.room_code)
	copy_code_button.text = L.t("Kopyalandı!")
	await get_tree().create_timer(1.0).timeout
	copy_code_button.text = L.t("Kopyala")

func _on_game_started() -> void:
	SceneTransition.fade_to_scene("res://scenes/PartySetup.tscn")

func _on_leave_pressed() -> void:
	MultiplayerManager.leave_room()
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_room_closed(reason: String) -> void:
	info_label.text = reason
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _format_threshold(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

## Başlangıçtan "years" yıl sonraki seçim: buçuklu ise yılın ortası ("2002 ortası").
static func _election_date(years: float) -> String:
	var whole := int(floor(years + 0.001))
	var year := GameRules.START_YEAR + whole
	return str(year) if is_equal_approx(years, float(whole)) else L.t("%d ortası") % year

# --- Parçalar -------------------------------------------------------------------

func _board() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiSkin.board()
	style.set_content_margin_all(14)
	style.dot_radius = 0.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

## Bölüm başlığı (konsept .sech): hardal nokta + başlık; sağdaki küçük notu da döner.
func _section_header(title: String) -> Array:
	var row := HBoxContainer.new()
	var label := UiTheme.mono_label(title, 18, UiTheme.HEAD, true)
	var dot := BoardBox.new()
	dot.draw_fill = false
	dot.dot_radius = 6
	dot.dot_pos = Vector2(6, 12)
	dot.dot_color = UiTheme.GOLD
	dot.dot_lip = 2
	dot.dot_lip_color = UiTheme.GOLD_DIM
	dot.content_margin_left = 20
	label.add_theme_stylebox_override("normal", dot)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var note := _small("", MUTED2, 12)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	return [row, note]

func _small(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.body_black())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _row_name(text: String) -> Label:
	return UiTheme.mono_label(text, 15, UiTheme.TEXT, true)

## "Ad ........ değer" satırı; değer etiketini döner.
func _value_row(parent: Control, text: String) -> Label:
	var row := HBoxContainer.new()
	var name_label := _row_name(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := UiTheme.mono_label("", 15, UiTheme.TEAL, true)
	row.add_child(value)
	parent.add_child(row)
	return value

## "Ad   [−] değer [+]" satırı: [eksi, değer, artı].
func _stepper_row(parent: Control, text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := _row_name(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var minus := _step_button("−")
	var value := UiTheme.mono_label("", 18, UiTheme.TEXT, true)
	value.custom_minimum_size.x = 56
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := _step_button("+")
	row.add_child(minus)
	row.add_child(value)
	row.add_child(plus)
	parent.add_child(row)
	return [minus, value, plus]

func _step_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(30, 30)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style := BoardBox.new()
		style.fill = UiTheme.TEAL.lightened(0.08) if state == "hover" else UiTheme.TEAL
		if state == "disabled":
			style.fill = UiTheme.TEAL.lerp(UiTheme.PANEL_LIGHT, 0.6)
		style.set_radius(9)
		style.lips = [[3.0, UiTheme.TEAL_DARK if state != "disabled" else UiTheme.CARD_LIP]]
		if state == "pressed" or state == "hover_pressed":
			style.offset_y = 2
			style.lips = [[1.0, UiTheme.TEAL_DARK]]
		button.add_theme_stylebox_override(state, style)
	for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(prop, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	return button

func _seg_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	return row

func _seg_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 32)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 14)
	return button

## Seçili parça hardal, diğerleri krem oyuk (konsept .seg).
func _mark_seg(button: Button, on: bool, locked: bool) -> void:
	button.set_pressed_no_signal(on)
	button.disabled = locked
	var face := UiTheme.GOLD if on else UiTheme.SLOT
	var lip := UiTheme.GOLD_DIM if on else UiTheme.CARD_LIP
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style := BoardBox.new()
		style.fill = face.lightened(0.08) if state.begins_with("hover") and not on else face
		style.set_radius(10)
		style.lips = [[3.0, lip]]
		if on:
			style.highlight_size = 2
			style.highlight_color = Color(1, 1, 1, 0.4)
		style.content_margin_left = 4
		style.content_margin_right = 4
		button.add_theme_stylebox_override(state, style)
	var ink := UiTheme.TEXT_ON_GOLD if on else UiTheme.TAB_TEXT
	for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(prop, ink)

func _slider() -> HSlider:
	return VectorSlider.new()

func _switch(text: String, tip: String) -> CheckButton:
	var check := VectorSwitch.new()
	check.text = text
	check.tooltip_text = tip
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_override("font", UiTheme.mono(true))
	check.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		check.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		check.add_theme_color_override(prop, UiTheme.TEXT)
	return check

func _teal_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := BoardBox.new()
		style.fill = UiTheme.TEAL.lightened(0.08) if state == "hover" else UiTheme.TEAL
		style.set_radius(10)
		style.lips = [[3.0, UiTheme.TEAL_DARK]]
		if state.ends_with("pressed"):
			style.offset_y = 2
			style.lips = [[1.0, UiTheme.TEAL_DARK]]
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(prop, Color.WHITE)
	return button

## Küçük krem düğme (konsept .mini); red: kırmızı tonlu (At, Çıkar).
func _mini_button(text: String, red: bool, icon_key: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 12)
	var face := Color("F3D7D2") if red else UiTheme.SLOT
	var lip := Color("D9A9A0") if red else UiTheme.CARD_LIP
	var ink := UiTheme.CRISIS if red else UiTheme.TEXT_MUTED
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style := BoardBox.new()
		style.fill = face.lightened(0.1) if state == "hover" else face
		style.set_radius(8)
		style.lips = [[2.0, lip]]
		if state.ends_with("pressed"):
			style.offset_y = 1
			style.lips = [[1.0, lip]]
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		button.add_theme_stylebox_override(state, style)
	for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(prop, ink)
	if icon_key != "":
		button.icon = _icon_texture(icon_key, 15, 2.2)
		button.add_theme_color_override("icon_normal_color", ink)
		button.add_theme_color_override("icon_hover_color", ink)
		button.add_theme_color_override("icon_pressed_color", ink)
		button.add_theme_constant_override("h_separation", 4)
	return button

## Simgeli krem çip düğme ("Yeni harita").
func _chip_button(text: String, icon_key: String) -> Button:
	var button := _mini_button(text, false, icon_key)
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size.y = 34
	return button

func _icon_texture(key: String, side: int, stroke: float) -> Texture2D:
	var cache_key := "%s@%d@%.1f" % [key, side, stroke]
	if not _icon_cache.has(cache_key):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#ffffff" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [stroke, String(ICON_PATHS.get(key, ""))]
		var image := Image.new()
		image.load_svg_from_string(svg, float(side) / 24.0)
		_icon_cache[cache_key] = ImageTexture.create_from_image(image)
	return _icon_cache[cache_key]

func _icon(key: String, side: int, color: Color, stroke: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = _icon_texture(key, side * 2, stroke)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

## Oyuncu pulu: renkli, tepesi açık pul; insanda baş harf, botta robot.
class Pawn extends Control:
	var color := Color.WHITE
	var text := ""
	var robot := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		draw_style_box(VoterGroupIcon.pawn_style(color, side), rect)
		var c := rect.get_center() - Vector2(0, side * 0.04)
		var ink := UiSkin.text_on(color)
		if robot:
			var s := side * 0.62
			var line := maxf(1.5, s * 0.09)
			draw_line(c + Vector2(0, -0.2) * s, c + Vector2(0, -0.34) * s, ink, line, true)
			draw_rect(Rect2(c + Vector2(-0.3, -0.2) * s, Vector2(0.6, 0.46) * s), ink, false, line)
			draw_circle(c + Vector2(-0.12, 0.0) * s, s * 0.06, ink)
			draw_circle(c + Vector2(0.12, 0.0) * s, s * 0.06, ink)
			draw_line(c + Vector2(-0.12, 0.14) * s, c + Vector2(0.12, 0.14) * s, ink, line * 0.8, true)
			return
		var font := UiTheme.mono(true)
		var fs := int(side * 0.44)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

## Kesik çizgili çerçeve (boş oyuncu yeri) ya da daire (boş sandalye).
class DashedBox extends Control:
	var circle := false
	const DASH := 5.0
	const GAP := 4.0
	const RADIUS := 14.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var color := UiTheme.EDGE
		if circle:
			var r := minf(size.x, size.y) * 0.5 - 1.5
			var n := int(TAU * r / (DASH + GAP))
			for i in n:
				var a0 := TAU * i / n
				draw_arc(size * 0.5, r, a0, a0 + TAU / n * DASH / (DASH + GAP), 6, color, 2.5, true)
			return
		var rect := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var r := RADIUS
		var edges := [
			[rect.position + Vector2(r, 0), rect.position + Vector2(rect.size.x - r, 0)],
			[rect.position + Vector2(rect.size.x, r), rect.end - Vector2(0, r)],
			[rect.end - Vector2(r, 0), rect.position + Vector2(r, rect.size.y)],
			[rect.position + Vector2(0, rect.size.y - r), rect.position + Vector2(0, r)],
		]
		for e in edges:
			draw_dashed_line(e[0], e[1], color, 2.0, DASH, true, true)
		var corners := [rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r),
			rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r)]
		var starts := [PI, -PI * 0.5, 0.0, PI * 0.5]
		for i in 4:
			draw_arc(corners[i], r, starts[i], starts[i] + PI * 0.5, 8, color, 2.0, true)
