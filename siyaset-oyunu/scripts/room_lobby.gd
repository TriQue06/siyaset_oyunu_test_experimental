extends Control

const SETTINGS_SHIFT := 220.0
const SLIDE_DURATION := 0.2

@onready var code_label: Label = %CodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var player_list_box: GridContainer = %PlayerListBox

## 8 sabit oyuncu kartı, 2 sütun. Robot butonu kartın sağ üst köşesine taşar.
const SLOT_SIZE := Vector2(230, 92)
const BOT_BUTTON_SIZE := 34.0
@onready var settings_button: Button = %SettingsButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var info_label: Label = %InfoLabel
@onready var threshold_label: Label = %ThresholdLabel
@onready var center_box: VBoxContainer = %CenterBox

@onready var settings_side_panel: Control = %SettingsSidePanel
@onready var side_close_button: Button = %SideCloseButton
@onready var settings_vbox: VBoxContainer = $SettingsSidePanel/Margin/VBox

## Ayar paneli kodla kurulur (bkz. _build_settings_panel).
const SECTION_COLOR := UiTheme.HEAD
var interval_value_label: Label
var interval_minus: Button
var interval_plus: Button
var count_value_label: Label
var count_minus: Button
var count_plus: Button
var game_length_summary: Label
var threshold_slider: HSlider
var map_seed_edit: LineEdit
var random_parties_check: CheckButton
var alliances_check: CheckButton
var away_bot_check: CheckButton
var bot_funds_buttons: Array = []
var world_controls: Dictionary = {}
var world_values: Dictionary = {}
## Düğmeli dünya ayarları (tur süresi, miting / yatırım sınırı): ayar -> düğmeler.
var world_choice_buttons: Dictionary = {}
## Ayar seçenek düğmelerinin ortak yüksekliği.
const CHOICE_HEIGHT := 34.0
var density_buttons: Array[Button] = []
var map_mode_buttons: Array[Button] = []
var _lobby_columns: GridContainer
var vote_time_buttons: Array[Button] = []
var threshold_value_label: Label

var _settings_open: bool = false
var _setting_sections: Dictionary = {}
var _sections_box: VBoxContainer
var _center_base_x: float = 0.0

func _ready() -> void:
	TableSurface.cover(self)
	_build_concept_a()
	_build_settings_panel()
	_refresh_code_display()
	GameSettings.streamer_mode_changed.connect(_on_streamer_mode_changed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	side_close_button.pressed.connect(_on_settings_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	threshold_slider.min_value = MultiplayerManager.THRESHOLD_MIN
	threshold_slider.max_value = MultiplayerManager.THRESHOLD_MAX
	threshold_slider.step = MultiplayerManager.THRESHOLD_STEP
	threshold_slider.value_changed.connect(_on_threshold_slider_changed)

	interval_minus.pressed.connect(func(): _change_game_length(-GameRules.ELECTION_INTERVAL_STEP, 0))
	interval_plus.pressed.connect(func(): _change_game_length(GameRules.ELECTION_INTERVAL_STEP, 0))
	count_minus.pressed.connect(func(): _change_game_length(0, -1))
	count_plus.pressed.connect(func(): _change_game_length(0, 1))

	MultiplayerManager.player_list_updated.connect(_refresh)
	MultiplayerManager.settings_updated.connect(_refresh_settings_display)
	MultiplayerManager.room_closed.connect(_on_room_closed)
	MultiplayerManager.game_started.connect(_on_game_started)

	# Anchor tabanlı offset'ler ilk layout geçişinden sonra kesinleşir; kaymanın
	# doğru hesaplanması için taban X konumunu bir sonraki frame'de yakalıyoruz.
	await get_tree().process_frame
	_center_base_x = center_box.position.x

	_refresh()
	_refresh_settings_display()

func _refresh() -> void:
	for child in player_list_box.get_children():
		player_list_box.remove_child(child)
		child.queue_free()

	var am_owner := MultiplayerManager.is_local_owner()
	var local_id := multiplayer.get_unique_id()

	# Kartlar sırayla dolar: önce insanlar, sonra botlar, sonra boş kartlar. Bot
	# sadece İLK boş karta eklenebilir (sonraki boş kartların butonu pasif).
	var order := MultiplayerManager.lobby_order()
	for i in MultiplayerManager.MAX_PLAYERS:
		if i < order.size():
			player_list_box.add_child(_build_slot(_build_player_card(order[i], i, am_owner, local_id), false, false))
		else:
			player_list_box.add_child(_build_slot(_build_empty_card(i), am_owner, i == order.size()))

	var count := MultiplayerManager.players.size()
	if MultiplayerManager.offline_mode:
		# Çevrim dışında katılan olmaz: boş yuvalar "bot ekle" demektir.
		info_label.text = L.t("Sen + %d bot  ·  en az %d oyuncu gerekir") % [
			count - 1, MultiplayerManager.MIN_PLAYERS_TO_START]
	else:
		info_label.text = L.t("Oyuncular: %d / %d  (başlamak için en az %d gerekir)") % [
			count, MultiplayerManager.MAX_PLAYERS, MultiplayerManager.MIN_PLAYERS_TO_START
		]

	# Eski "LOBİ AYARLARI" düğmesi gizli kalır: kurallar sağ sütunda hep açık.
	start_button.visible = am_owner
	start_button.disabled = count < MultiplayerManager.MIN_PLAYERS_TO_START

	# Konsept A: kurallar herkese görünür; yalnız sahibi düzenler.

	threshold_slider.editable = am_owner
	map_seed_edit.editable = am_owner and MultiplayerManager.world_settings["map_mode"] == "random"
	random_parties_check.disabled = not am_owner
	alliances_check.disabled = not am_owner
	if away_bot_check != null:
		away_bot_check.disabled = not am_owner
	for button in bot_funds_buttons:
		(button as Button).disabled = not am_owner
	for button in [interval_minus, interval_plus, count_minus, count_plus]:
		button.disabled = not am_owner
	_refresh_settings_display()

## Her oyuncu bir kart: renkli baş harf rozeti, isim, etiketler (Sahip / Sen /
## Bot) ve sahibe özel işlem (sahipliği devret ya da botu çıkar).
func _build_player_card(peer_id: int, index: int, am_owner: bool, local_id: int) -> Control:
	var pdata: Dictionary = MultiplayerManager.players[peer_id]
	var is_bot := MultiplayerManager.is_bot(peer_id)
	var player_name: String = pdata.get("name", "?")
	var color: Color = PartyPresets.COLORS[(index * 7) % PartyPresets.COLORS.size()]

	var card := PanelContainer.new()
	# Panel içindeki beyaz kart; senin kartın hardal kenarlı.
	var card_style := UiSkin.card()
	card_style.set_content_margin_all(2)
	if peer_id == local_id:
		card_style.border_color = UiTheme.GOLD
		card_style.bg_color = Color("FFF6DC")
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(420, 60)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	# Yuvarlak pul: parti rengi, altında kalınlık.
	var badge_style := UiSkin.flat(color if not is_bot else UiTheme.PANEL_LIGHT, 999)
	badge_style.border_color = (color if not is_bot else UiTheme.PANEL_LIGHT).darkened(0.35)
	badge_style.border_width_bottom = 4
	avatar.add_theme_stylebox_override("panel", badge_style)
	if is_bot:
		var robot := RobotIcon.new()
		robot.custom_minimum_size = Vector2(44, 44)
		avatar.add_child(robot)
	else:
		var initial := Label.new()
		initial.text = player_name.substr(0, 1).to_upper()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 20)
		initial.add_theme_font_override("font", UiTheme.mono(true))
		initial.add_theme_color_override("font_color", UiSkin.text_on(color))
		avatar.add_child(initial)
	row.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = player_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(name_label)
	var tags: Array[String] = []
	if peer_id == MultiplayerManager.owner_id:
		tags.append(L.t("Oda sahibi"))
	if peer_id == local_id:
		tags.append(L.t("Sen"))
	if is_bot:
		tags.append(L.t("Bot"))
	if not tags.is_empty():
		var tag_label := Label.new()
		tag_label.text = "  ·  ".join(tags)
		tag_label.clip_text = true
		tag_label.add_theme_font_size_override("font_size", 12)
		tag_label.add_theme_color_override("font_color", UiTheme.HEAD if peer_id == MultiplayerManager.owner_id else UiTheme.TEXT_MUTED)
		info.add_child(tag_label)
	row.add_child(info)

	if am_owner and peer_id != local_id:
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 4)
		actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var action := Button.new()
		UiSkin.skin_button(action)
		_compact_player_action(action)
		if is_bot:
			action.text = L.t("Çıkar")
			action.pressed.connect(func(): MultiplayerManager.remove_bot(peer_id))
		else:
			action.text = L.t("Devret")
			action.pressed.connect(func(): MultiplayerManager.transfer_ownership(peer_id))
		actions.add_child(action)
		if not is_bot:
			# Oyuncu atma: sadece lobi sahibinde ve kendisi dışındakiler için.
			var kick := Button.new()
			UiSkin.skin_color_button(kick, UiTheme.RED)
			_compact_player_action(kick)
			kick.text = L.t("At")
			kick.pressed.connect(func(): MultiplayerManager.kick_player(peer_id))
			actions.add_child(kick)
		row.add_child(actions)
	return card

## Kartı sabit boyutlu bir slota yerleştirir; istenirse sağ üst köşesine
## yuvarlak robot butonu oturtur (enabled=false ise soluk ve basılamaz).
func _build_slot(card: Control, show_bot_button: bool, enabled: bool) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2.ZERO
	slot.set_meta("card_minimum", card.get_combined_minimum_size())
	slot.set_meta("card", card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.offset_top = BOT_BUTTON_SIZE * 0.45
	card.offset_right = -BOT_BUTTON_SIZE * 0.45
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	frame.clip_contents = true
	slot.add_child(frame)
	frame.add_child(card)
	# Container minimums must not independently size occupied/empty cards.
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var fit_card := func():
		var reserve := roundf(BOT_BUTTON_SIZE * 0.45)
		frame.position = Vector2.ZERO
		frame.size = Vector2(slot.size.x, SLOT_SIZE.y)
		card.position = Vector2(0, reserve)
		card.size = Vector2(slot.size.x - reserve, SLOT_SIZE.y - reserve)
	slot.resized.connect(fit_card)
	fit_card.call_deferred()
	if not show_bot_button:
		return slot
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -BOT_BUTTON_SIZE
	button.offset_right = 0.0
	button.offset_top = 0.0
	button.offset_bottom = BOT_BUTTON_SIZE
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_NONE
	UiSkin.skin_color_button(button, UiTheme.GREEN_DARK if enabled else UiTheme.PANEL_DARK)
	var robot := RobotIcon.new()
	robot.set_anchors_preset(Control.PRESET_FULL_RECT)
	robot.color = UiTheme.ON_COLOR if enabled else UiTheme.TEXT_DIM
	button.add_child(robot)
	if enabled:
		button.pressed.connect(MultiplayerManager.add_bot)
	slot.add_child(button)
	return slot

func _build_empty_card(index: int) -> Control:
	var card := PanelContainer.new()
	# Boş koltuk: içe basık oyuk.
	card.add_theme_stylebox_override("panel", UiSkin.groove())
	var label := Label.new()
	label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	label.text = "%d · %s" % [index + 1, L.t("Bot ekle") if MultiplayerManager.offline_mode else L.t("Boş")]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	card.add_child(label)
	return card

## Emoji fontu her cihazda yok (Android): robot simgesi çizilerek üretilir.
class RobotIcon extends Control:
	var color: Color = Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c: Vector2 = size * 0.5 + Vector2(0, s * 0.04)
		var line: float = maxf(1.5, s * 0.07)
		# anten
		draw_line(c + Vector2(0, -0.2) * s, c + Vector2(0, -0.32) * s, color, line)
		draw_circle(c + Vector2(0, -0.35) * s, s * 0.055, color)
		# kafa, gözler, ağız, kulaklar
		draw_rect(Rect2(c + Vector2(-0.27, -0.2) * s, Vector2(0.54, 0.42) * s), color, false, line)
		draw_rect(Rect2(c + Vector2(-0.16, -0.08) * s, Vector2(0.1, 0.1) * s), color)
		draw_rect(Rect2(c + Vector2(0.06, -0.08) * s, Vector2(0.1, 0.1) * s), color)
		draw_line(c + Vector2(-0.11, 0.1) * s, c + Vector2(0.11, 0.1) * s, color, maxf(1.5, s * 0.05))
		draw_rect(Rect2(c + Vector2(-0.36, -0.06) * s, Vector2(0.07, 0.14) * s), color)
		draw_rect(Rect2(c + Vector2(0.29, -0.06) * s, Vector2(0.07, 0.14) * s), color)

func _refresh_settings_display() -> void:
	for key in world_controls:
		var control: HSlider = world_controls[key]
		control.set_value_no_signal(float(MultiplayerManager.world_settings[key]))
		world_values[key].text = str(MultiplayerManager.world_settings[key])
		control.editable = MultiplayerManager.is_local_owner()
	# Türkiye haritası: 81 il ve gerçek vekil dağılımı sabit; yalnız ulusal liste ayarlanır.
	var turkey: bool = MultiplayerManager.world_settings["map_mode"] != "random"
	if turkey and world_controls.has("province_seats"):
		(world_controls["province_seats"] as HSlider).editable = false
		world_values["province_seats"].text = L.t("%d (sabit)") % GameMap.preset_seat_total(String(MultiplayerManager.world_settings["map_mode"]))
	for button in map_mode_buttons:
		var on: bool = String(button.get_meta("value")) == String(MultiplayerManager.world_settings["map_mode"])
		button.set_pressed_no_signal(on)
		button.disabled = not MultiplayerManager.is_local_owner()
		UiSkin.skin_color_button(button, UiTheme.GOLD if on else UiTheme.PANEL_LIGHT)
	if map_seed_edit != null:
		map_seed_edit.editable = MultiplayerManager.is_local_owner() and not turkey
		map_seed_edit.placeholder_text = L.t("Türkiye haritasında tohum yok") if turkey else L.t("Rastgele")

	for button in density_buttons:
		var on := is_equal_approx(float(button.get_meta("value")), float(MultiplayerManager.world_settings["province_scale"]))
		button.set_pressed_no_signal(on)
		button.disabled = not MultiplayerManager.is_local_owner() or turkey
		UiSkin.skin_color_button(button, UiTheme.GOLD if on else UiTheme.PANEL_LIGHT)
	for key in world_choice_buttons:
		for button in world_choice_buttons[key]:
			var on: bool = button.get_meta("value") == MultiplayerManager.world_settings[key]
			button.set_pressed_no_signal(on)
			button.disabled = not MultiplayerManager.is_local_owner()
			UiSkin.skin_color_button(button, UiTheme.GOLD if on else UiTheme.PANEL_LIGHT)
	for button in vote_time_buttons:
		var selected := int(button.get_meta("seconds")) == MultiplayerManager.vote_timeout
		UiSkin.skin_color_button(button, UiTheme.GOLD if selected else UiTheme.PANEL_LIGHT)
		button.set_pressed_no_signal(int(button.get_meta("seconds")) == MultiplayerManager.vote_timeout)
		button.disabled = not MultiplayerManager.is_local_owner()

	if map_seed_edit != null and not map_seed_edit.has_focus():
		map_seed_edit.text = MultiplayerManager.map_seed
	if random_parties_check != null:
		random_parties_check.set_pressed_no_signal(MultiplayerManager.random_parties)
	if alliances_check != null:
		alliances_check.set_pressed_no_signal(bool(MultiplayerManager.world_settings.get("alliances", true)))
	if away_bot_check != null:
		away_bot_check.set_pressed_no_signal(MultiplayerManager.away_mode == MultiplayerManager.AWAY_BOT)
	for button in bot_funds_buttons:
		var on: bool = is_equal_approx(float((button as Button).get_meta("value")), MultiplayerManager.bot_funds_penalty)
		(button as Button).set_pressed_no_signal(on)
		UiSkin.skin_color_button(button, UiTheme.GOLD if on else UiTheme.PANEL_LIGHT)
		(button as Button).add_theme_color_override("font_color", UiTheme.INK if on else UiTheme.TEXT)
	var t := MultiplayerManager.election_threshold
	var interval := MultiplayerManager.election_interval
	var count := MultiplayerManager.election_count
	threshold_label.text = L.t("Baraj %%%s  ·  %d seçim, %s yılda bir (%d'den %s yıl)") % [_format_threshold(t), count,
		GameRules.years_text(interval), GameRules.START_YEAR, GameRules.years_text(interval * count)]
	interval_value_label.text = GameRules.years_text(interval)
	count_value_label.text = str(count)
	var years: Array = []
	for i in range(1, count + 1):
		years.append(_election_date(interval * i))
	if years.size() > 5:
		years = years.slice(0, 3) + ["…"] + years.slice(years.size() - 1)
	game_length_summary.text = L.t("%d'de başlar, %s yıl sürer (bir tur 6 ay). Seçimler: %s.") % [GameRules.START_YEAR,
		GameRules.years_text(interval * count), ", ".join(PackedStringArray(years))]
	if MultiplayerManager.is_local_owner():
		interval_minus.disabled = interval <= GameRules.ELECTION_INTERVAL_MIN
		interval_plus.disabled = interval >= GameRules.ELECTION_INTERVAL_MAX
		count_minus.disabled = count <= GameRules.ELECTION_COUNT_MIN
		count_plus.disabled = count >= GameRules.ELECTION_COUNT_MAX
	threshold_value_label.text = L.t("%%%s") % _format_threshold(t)
	if not threshold_slider.has_focus():
		threshold_slider.value = t

func _format_threshold(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

func _on_threshold_slider_changed(value: float) -> void:
	MultiplayerManager.set_election_threshold(value)

## Başlangıçtan "years" yıl sonraki seçim: buçuklu ise yılın ortası ("2002 ortası").
static func _election_date(years: float) -> String:
	var whole := int(floor(years + 0.001))
	var year := GameRules.START_YEAR + whole
	return str(year) if is_equal_approx(years, float(whole)) else L.t("%d ortası") % year

func _change_game_length(interval_delta: float, count_delta: int) -> void:
	MultiplayerManager.set_game_length(MultiplayerManager.election_interval + interval_delta,
		MultiplayerManager.election_count + count_delta)

# --- Ayar paneli ------------------------------------------------------------------

func _build_settings_panel() -> void:
	settings_vbox.add_theme_constant_override("separation", 8)
	var title := settings_vbox.get_node("HeaderRow/TitleLabel") as Label
	title.text = L.t("OYUN KURALLARI")
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_font_override("font", UiTheme.mono(true))
	title.add_theme_color_override("font_color", UiTheme.HEAD)
	# Bölümler kaydırılabilir bir alanda: başlık ve ✕ hep görünür kalır.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_vbox.add_child(scroll)
	_sections_box = VBoxContainer.new()
	_sections_box.add_theme_constant_override("separation", 8)
	_sections_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 12)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	gutter.add_child(_sections_box)
	var close_bottom := Button.new()
	close_bottom.text = L.t("Kapat")
	close_bottom.custom_minimum_size = Vector2(0, 40)
	close_bottom.hide()
	close_bottom.focus_mode = Control.FOCUS_NONE
	close_bottom.pressed.connect(_close_settings_panel)
	settings_vbox.add_child(close_bottom)

	var length := _section(L.t("OYUN SÜRESİ"), "")
	var interval_row := _stepper_row(length, L.t("Seçimler kaç yılda bir"))
	interval_minus = interval_row[0]
	interval_value_label = interval_row[1]
	interval_plus = interval_row[2]
	var count_row := _stepper_row(length, L.t("Kaç seçim olacak"))
	count_minus = count_row[0]
	count_value_label = count_row[1]
	count_plus = count_row[2]
	game_length_summary = _note(length, "")
	game_length_summary.add_theme_color_override("font_color", SECTION_COLOR)

	var election := _section(L.t("SEÇİM"), "")
	var threshold_row := _value_row(election, L.t("Seçim barajı"))
	threshold_value_label = threshold_row
	threshold_slider = HSlider.new()
	election.add_child(threshold_slider)

	var votes_box := _section(L.t("MECLİS OYLAMA SÜRESİ"), "")
	var votes_row := HBoxContainer.new()
	votes_box.add_child(votes_row)
	for seconds in MultiplayerManager.VOTE_TIME_OPTIONS:
		var button := Button.new()
		button.text = str(seconds)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, CHOICE_HEIGHT)
		button.set_meta("seconds", seconds)
		UiSkin.skin_button(button)
		button.pressed.connect(func(): MultiplayerManager.set_vote_timeout(int(button.get_meta("seconds"))))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		votes_row.add_child(button)
		vote_time_buttons.append(button)
	var world_box := _section(L.t("HARİTA VE MECLİS"), "")
	world_box.add_child(UiTheme.mono_label(L.t("Harita"), 12, UiTheme.TEXT))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	world_box.add_child(mode_row)
	var mode_names := {"random": L.t("Rastgele"), "turkiye_altigen": L.t("Türkiye")}
	for mode in MultiplayerManager.WORLD_OPTIONS["map_mode"]:
		var button := Button.new()
		button.text = mode_names[mode]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(56, 34)
		button.clip_text = false
		button.add_theme_font_size_override("font_size", 12)
		button.set_meta("value", mode)
		button.pressed.connect(func(): MultiplayerManager.set_world_setting("map_mode", String(button.get_meta("value"))))
		mode_row.add_child(button)
		map_mode_buttons.append(button)
	var labels := {"province_scale": L.t("İl sayısı"), "province_seats": L.t("İl milletvekilleri"), "national_seats": L.t("Ulusal milletvekilleri"), "turn_seconds": L.t("Tur süresi"), "action_limit": L.t("Sırada miting / yatırım sınırı")}
	world_box.add_child(UiTheme.mono_label(labels["province_scale"], 12, UiTheme.TEXT))
	var density_row := HBoxContainer.new()
	density_row.add_theme_constant_override("separation", 6)
	world_box.add_child(density_row)
	for i in 3:
		var button := Button.new()
		button.text = [L.t("Az"), L.t("Ortalama"), L.t("Fazla")][i]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(56, 34)
		button.set_meta("value", MultiplayerManager.WORLD_OPTIONS["province_scale"][i])
		button.pressed.connect(func(): MultiplayerManager.set_world_setting("province_scale", button.get_meta("value")))
		density_row.add_child(button)
		density_buttons.append(button)
	# TUR SÜRESİ ve MİTİNG / YATIRIM SINIRI: kaydırıcı değil, oylama süresi gibi
	# düğmeler (0.0.239). Seçenek arttıkça düğmeler daralır, yükseklik aynı kalır.
	for key in ["turn_seconds", "action_limit"]:
		var timing: VBoxContainer = _setting_sections["timing"]
		timing.add_child(HSeparator.new())
		var heading_text := L.t("TUR SÜRESİ") if key == "turn_seconds" else L.t("SIRADA MİTİNG / YATIRIM SINIRI")
		timing.add_child(UiTheme.mono_label(heading_text, 12, SECTION_COLOR, true))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		timing.add_child(row)
		var buttons: Array = []
		for value in MultiplayerManager.WORLD_OPTIONS[key]:
			var button := Button.new()
			button.text = str(value)
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(0, CHOICE_HEIGHT)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.set_meta("value", value)
			button.pressed.connect(func(): MultiplayerManager.set_world_setting(key, button.get_meta("value")))
			row.add_child(button)
			buttons.append(button)
		world_choice_buttons[key] = buttons
	for key in ["province_seats", "national_seats"]:
		var target_box: VBoxContainer = world_box
		world_values[key] = _value_row(target_box, labels[key])
		var control := HSlider.new()
		var values: Array = MultiplayerManager.WORLD_OPTIONS[key]
		control.min_value = float(values[0])
		control.max_value = float(values[-1])
		control.step = float(values[1]) - float(values[0])
		control.set_meta("key", key)
		control.value_changed.connect(func(value: float): MultiplayerManager.set_world_setting(String(control.get_meta("key")), int(value)))
		target_box.add_child(control)
		world_controls[key] = control
	var map_box := _section(L.t("HARİTA"), L.t("Aynı tohum her zaman aynı ülkeyi üretir. Boş bırakırsan her oyunda rastgele."))
	map_seed_edit = LineEdit.new()
	map_seed_edit.placeholder_text = L.t("Rastgele")
	map_seed_edit.max_length = MultiplayerManager.MAP_SEED_MAX_DIGITS
	map_seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	map_seed_edit.text_submitted.connect(func(text: String): MultiplayerManager.set_map_seed(text))
	map_seed_edit.focus_exited.connect(func(): MultiplayerManager.set_map_seed(map_seed_edit.text))
	map_box.add_child(map_seed_edit)

	var alliance_box := _section(L.t("SEÇİM İTTİFAKLARI"), L.t("Açıksa partiler ittifak kurabilir; barajda ortak oy sayılır. Oyun içinde anayasayla değişebilir."))
	alliances_check = CheckButton.new()
	alliances_check.text = L.t("İttifaklar açık")
	alliances_check.focus_mode = Control.FOCUS_NONE
	alliances_check.toggled.connect(func(on: bool): MultiplayerManager.set_world_setting("alliances", on))
	alliance_box.add_child(alliances_check)

	var parties_box := _section(L.t("RASTGELE PARTİLER"), L.t("Açıksa seçimlerden sonra arada bir yeni bir parti (bot) kurulur; bir iki seçim sonra kendini fesheder."))
	random_parties_check = CheckButton.new()
	random_parties_check.text = L.t("Yeni partiler katılabilir")
	random_parties_check.focus_mode = Control.FOCUS_NONE
	random_parties_check.toggled.connect(func(on: bool): MultiplayerManager.set_random_parties(on))
	parties_box.add_child(random_parties_check)

	var away_box := _section(L.t("OYUNDAN DÜŞEN OYUNCU"), L.t("Bağlantısı kopan oyuncunun yerine bot oynar ya da dönene kadar pasif kalır (sırası geçer, oylarda çekimser). Aynı cihazdan odaya yeniden katılınca kaldığı yerden devam eder."))
	away_bot_check = CheckButton.new()
	away_bot_check.text = L.t("Yerine bot oynasın")
	away_bot_check.focus_mode = Control.FOCUS_NONE
	away_bot_check.toggled.connect(func(on: bool): MultiplayerManager.set_away_mode(
		MultiplayerManager.AWAY_BOT if on else MultiplayerManager.AWAY_PASSIVE))
	away_box.add_child(away_bot_check)

	var bot_box := _section(L.t("BOT GELİR ZAYIFLATMASI"), L.t("Botların dönemlik geliri ve bağış kampanyaları seçilen tutar kadar (¤ M) azalır. 0 = zayıflatma yok."))
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 6)
	bot_box.add_child(bot_row)
	bot_funds_buttons.clear()
	for value in MultiplayerManager.BOT_FUNDS_PENALTY_OPTIONS:
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.text = ("%.1f" % float(value)).replace(".0", "").replace(".", ",")
		button.custom_minimum_size = Vector2(56, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.set_meta("value", float(value))
		button.pressed.connect(func(): MultiplayerManager.set_bot_funds_penalty(float(value)))
		bot_row.add_child(button)
		bot_funds_buttons.append(button)

## Başlıklı, çerçeveli bir ayar bölümü; içeriğin ekleneceği kutuyu döner.
func _section(title_text: String, note_text: String) -> VBoxContainer:
	var category := "bots"
	var heading := L.t("BOTLAR VE DİĞER AYARLAR")
	if title_text in [L.t("OYUN SÜRESİ"), L.t("SEÇİM"), L.t("MECLİS OYLAMA SÜRESİ")]:
		category = "timing"
		heading = L.t("SÜRELER VE SEÇİMLER")
	elif title_text in [L.t("HARİTA VE MECLİS"), L.t("HARİTA")]:
		category = "map"
		heading = L.t("HARİTA VE TEMSİL")
	var box: VBoxContainer
	if _setting_sections.has(category):
		box = _setting_sections[category]
		box.add_child(HSeparator.new())
		box.add_child(UiTheme.mono_label(title_text, 12, SECTION_COLOR, true))
	else:
		var panel := PanelContainer.new()
		var style := UiSkin.card()
		style.set_content_margin_all(UiTheme.PAD_M)
		panel.add_theme_stylebox_override("panel", style)
		_sections_box.add_child(panel)
		if category == "map":
			_sections_box.move_child(panel, 0)
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		box.add_child(UiTheme.mono_label(heading, 13, SECTION_COLOR, true))
		_setting_sections[category] = box
	if note_text != "":
		_note(box, note_text)
	return box

func _note(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	parent.add_child(label)
	return label

func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	return label

func _value_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiTheme.TEXT)
	return label

## "Etiket ........ değer" satırı; değer etiketini döner.
func _value_row(parent: Control, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_child(_row_label(text))
	var value := _value_label()
	row.add_child(value)
	parent.add_child(row)
	return value

## "Etiket   [−] değer [+]" satırı: [eksi, değer, artı].
func _stepper_row(parent: Control, text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_row_label(text))
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(32, 30)
	var value := _value_label()
	value.custom_minimum_size = Vector2(28, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", SECTION_COLOR)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(32, 30)
	row.add_child(minus)
	row.add_child(value)
	row.add_child(plus)
	parent.add_child(row)
	return [minus, value, plus]

func _refresh_code_display() -> void:
	# ÇEVRİM DIŞI modda oda kodu diye bir şey yok: kod ve kopyala butonu gizlenir.
	var hint := get_node_or_null("CenterBox/HintLabel") as Label
	if MultiplayerManager.offline_mode:
		code_label.text = L.t("ÇEVRİM DIŞI OYUN")
		code_label.add_theme_color_override("font_color", UiTheme.WOOD_TEXT_MUTED)
		copy_code_button.hide()
		if hint != null:
			hint.text = L.t("Ağ yok: sadece sen ve eklediğin botlar oynar.")
		return
	copy_code_button.show()
	if hint != null:
		hint.text = L.t("Bu kodu arkadaşına gönder, o da 'Odaya Katıl' ekranına girsin.")
	var shown := "•••••" if GameSettings.streamer_mode else MultiplayerManager.room_code
	code_label.text = L.t("ODA KODU: %s") % shown
	code_label.add_theme_color_override("font_color", UiTheme.WOOD_TEXT)

func _on_streamer_mode_changed(_enabled: bool) -> void:
	_refresh_code_display()

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(MultiplayerManager.room_code)
	copy_code_button.text = L.t("Kopyalandı!")
	await get_tree().create_timer(1.0).timeout
	copy_code_button.text = L.t("Kopyala")

## Lobi ayarları butonu: panel kapalıysa ekranın sağında açar ve ortadaki
## içeriği hafifçe sola kaydırır; açıksa tersini yapıp kapatır.
func _on_settings_pressed() -> void:
	if _settings_open:
		_close_settings_panel()
	else:
		_open_settings_panel()

func _open_settings_panel() -> void:
	settings_side_panel.show()

func _close_settings_panel() -> void:
	settings_side_panel.show()

func _on_start_pressed() -> void:
	MultiplayerManager.start_game()

func _on_game_started() -> void:
	SceneTransition.fade_to_scene("res://scenes/PartySetup.tscn")

func _on_leave_pressed() -> void:
	MultiplayerManager.leave_room()
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_room_closed(reason: String) -> void:
	info_label.text = reason
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

## A konsepti: oda başlığı, eşit oyuncu yuvaları ve kalıcı kural sütunu.
func _build_concept_a() -> void:
	settings_button.hide()
	side_close_button.hide()
	var original_panel := settings_side_panel
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	# Başlık satırı sağ üstteki Menü düğmesiyle aynı hizada (üst 14, yükseklik 44).
	margin.add_theme_constant_override("margin_top", 14)
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 16)
	margin.add_child(root_box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	header.custom_minimum_size.y = 44
	root_box.add_child(header)
	var title := UiTheme.mono_label(L.t("SİYASET OYUNU"), 26, UiTheme.WOOD_TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var code_row := center_box.get_node("CodeRow")
	code_row.reparent(header)
	UiSkin.skin_button(copy_code_button)
	copy_code_button.custom_minimum_size.y = 44
	copy_code_button.size_flags_vertical = Control.SIZE_FILL
	var menu_space := Control.new()
	menu_space.custom_minimum_size.x = 124
	header.add_child(menu_space)
	var main_scroll := ScrollContainer.new()
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(main_scroll)
	_lobby_columns = GridContainer.new()
	_lobby_columns.columns = 2
	_lobby_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_columns.add_theme_constant_override("h_separation", 20)
	_lobby_columns.add_theme_constant_override("v_separation", 16)
	main_scroll.add_child(_lobby_columns)
	var left := PanelContainer.new()
	_skin_lobby_panel(left)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_columns.add_child(left)
	center_box.reparent(left)
	center_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.add_theme_constant_override("separation", 10)
	var heading := UiTheme.mono_label(L.t("OYUNCULAR"), 16, UiTheme.HEAD, true)
	center_box.add_child(heading)
	center_box.move_child(heading, 0)
	for child in center_box.get_children():
		if child is HSeparator or child.name == "HintLabel":
			child.hide()
	player_list_box.add_theme_constant_override("h_separation", 8)
	player_list_box.add_theme_constant_override("v_separation", 8)
	threshold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threshold_label.add_theme_font_size_override("font_size", 12)
	center_box.move_child(threshold_label, center_box.get_child_count() - 1)
	var right := PanelContainer.new()
	_skin_lobby_panel(right)
	right.custom_minimum_size = Vector2(380, 480)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_columns.add_child(right)
	settings_vbox.reparent(right)
	settings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_side_panel = right
	original_panel.hide()
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root_box.add_child(footer)
	info_label.reparent(footer)
	info_label.add_theme_color_override("font_color", UiTheme.WOOD_TEXT_MUTED)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	leave_button.reparent(footer)
	leave_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	UiSkin.skin_button(leave_button)
	# Yan yana: AYRIL ile OYUNU BAŞLAT aynı yükseklikte.
	leave_button.custom_minimum_size = Vector2(120, start_button.custom_minimum_size.y)
	leave_button.size_flags_vertical = Control.SIZE_FILL
	start_button.reparent(footer)
	UiSkin.skin_color_button(start_button, UiTheme.GREEN_DARK)
	resized.connect(_fit_concept_a)
	_fit_concept_a()

func _fit_concept_a() -> void:
	if _lobby_columns != null:
		_lobby_columns.columns = 1 if size.x < 1000.0 else 2

func _skin_lobby_panel(panel: PanelContainer) -> void:
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(14)
	UiSkin.apply_style(panel, "panel", style)

func _compact_player_action(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 11)
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := button.get_theme_stylebox(key).duplicate() as StyleBox
		style.set_content_margin_all(3)
		UiSkin.apply_style(button, key, style)
