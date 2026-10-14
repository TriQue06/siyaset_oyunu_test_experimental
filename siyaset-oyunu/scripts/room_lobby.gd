extends Control

const SETTINGS_SHIFT := 220.0
const SLIDE_DURATION := 0.2

@onready var code_label: Label = %CodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var player_list_box: GridContainer = %PlayerListBox

## 8 sabit oyuncu kartı, 2 sütun. Robot butonu kartın sağ üst köşesine taşar.
const SLOT_SIZE := Vector2(230, 86)
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
const SECTION_COLOR := UiTheme.GOLD
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
var away_bot_check: CheckButton
var bot_funds_buttons: Array = []
var world_controls: Dictionary = {}
var world_values: Dictionary = {}
var density_buttons: Array[Button] = []
var _lobby_columns: GridContainer
var vote_time_buttons: Array[Button] = []
var threshold_value_label: Label

var _settings_open: bool = false
var _setting_sections: Dictionary = {}
var _sections_box: VBoxContainer
var _center_base_x: float = 0.0

func _ready() -> void:
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

	interval_minus.pressed.connect(func(): _change_game_length(-1, 0))
	interval_plus.pressed.connect(func(): _change_game_length(1, 0))
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

	var shared_size := SLOT_SIZE
	for slot in player_list_box.get_children():
		if slot.has_meta("card_minimum") and not slot.is_queued_for_deletion():
			var minimum: Vector2 = slot.get_meta("card_minimum")
			shared_size.x = maxf(shared_size.x, minimum.x + BOT_BUTTON_SIZE * 0.45)
			shared_size.y = maxf(shared_size.y, minimum.y + BOT_BUTTON_SIZE * 0.45)
	for slot in player_list_box.get_children():
		if not slot.is_queued_for_deletion():
			slot.custom_minimum_size = shared_size
	var count := MultiplayerManager.players.size()
	if MultiplayerManager.offline_mode:
		# Çevrim dışında katılan olmaz: boş yuvalar "bot ekle" demektir.
		info_label.text = L.t("Sen + %d bot  ·  en az %d oyuncu gerekir") % [
			count - 1, MultiplayerManager.MIN_PLAYERS_TO_START]
	else:
		info_label.text = L.t("Oyuncular: %d / %d  (başlamak için en az %d gerekir)") % [
			count, MultiplayerManager.MAX_PLAYERS, MultiplayerManager.MIN_PLAYERS_TO_START
		]

	settings_button.visible = am_owner
	start_button.visible = am_owner
	start_button.disabled = count < MultiplayerManager.MIN_PLAYERS_TO_START

	# Konsept A: kurallar herkese görünür; yalnız sahibi düzenler.

	threshold_slider.editable = am_owner
	map_seed_edit.editable = am_owner
	random_parties_check.disabled = not am_owner
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
	UiSkin.skin_panel(card, UiSkin.PANEL)
	card.custom_minimum_size = Vector2(420, 60)
	if peer_id == local_id:
		card.modulate = Color(1.12, 1.08, 0.92)  # sıradaki/senin kartın hafif altın

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	# Kare rozet (pixel tarz): koyu çizgi + düz renk.
	UiSkin.apply_style(avatar, "panel",
		UiSkin.color_box(color if not is_bot else UiTheme.PANEL_LIGHT, UiSkin.BUTTON_TINT_NORMAL))
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
	name_label.tooltip_text = player_name
	info.add_child(name_label)
	var tags: Array[String] = []
	if peer_id == MultiplayerManager.owner_id:
		tags.append(L.t("★ Oda sahibi"))
	if peer_id == local_id:
		tags.append(L.t("Sen"))
	if is_bot:
		tags.append(L.t("Bot"))
	if not tags.is_empty():
		var tag_label := Label.new()
		tag_label.text = "  ·  ".join(tags)
		tag_label.add_theme_font_size_override("font_size", 12)
		tag_label.modulate = UiTheme.GOLD if peer_id == MultiplayerManager.owner_id else UiTheme.TEXT_MUTED
		info.add_child(tag_label)
	row.add_child(info)

	if am_owner and peer_id != local_id:
		var actions := VBoxContainer.new()
		actions.add_theme_constant_override("separation", UiTheme.GAP_S)
		actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var action := Button.new()
		UiSkin.skin_button(action)
		if is_bot:
			action.text = L.t("Çıkar")
			action.pressed.connect(func(): MultiplayerManager.remove_bot(peer_id))
		else:
			action.text = L.t("Devret")
			action.tooltip_text = L.t("Sahipliği Devret")
			action.pressed.connect(func(): MultiplayerManager.transfer_ownership(peer_id))
		actions.add_child(action)
		if not is_bot:
			# Oyuncu atma: sadece lobi sahibinde ve kendisi dışındakiler için.
			var kick := Button.new()
			UiSkin.skin_color_button(kick, UiTheme.RED)
			kick.text = L.t("At")
			kick.tooltip_text = L.t("Lobiden At")
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
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_top = BOT_BUTTON_SIZE * 0.45
	card.offset_right = -BOT_BUTTON_SIZE * 0.45
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.clip_contents = true
	slot.add_child(frame)
	frame.add_child(card)
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
	robot.color = UiTheme.TEXT if enabled else UiTheme.TEXT_DIM
	button.add_child(robot)
	if enabled:
		button.pressed.connect(MultiplayerManager.add_bot)
	slot.add_child(button)
	return slot

func _build_empty_card(index: int) -> Control:
	var card := PanelContainer.new()
	UiSkin.skin_panel(card, UiSkin.PANEL)
	card.modulate = Color(0.75, 0.75, 0.75, 1.0)
	var label := Label.new()
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
		world_values[key].text = str(MultiplayerManager.world_settings[key]) + (" s" if key == "turn_seconds" else "")
		control.editable = MultiplayerManager.is_local_owner()

	for button in density_buttons:
		var on := is_equal_approx(float(button.get_meta("value")), float(MultiplayerManager.world_settings["province_scale"]))
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
	threshold_label.text = L.t("Baraj %%%s  ·  %d seçim, %d yılda bir (%d'den %d yıl)") % [_format_threshold(t), count, interval, GameRules.START_YEAR, interval * count]
	interval_value_label.text = str(interval)
	count_value_label.text = str(count)
	var years: Array = []
	for i in range(1, count + 1):
		years.append(str(GameRules.START_YEAR + interval * i))
	if years.size() > 5:
		years = years.slice(0, 3) + ["…"] + years.slice(years.size() - 1)
	game_length_summary.text = L.t("%d'de başlar, %d yıl sürer (bir tur 6 ay). Seçimler: %s.") % [GameRules.START_YEAR,
		interval * count, ", ".join(PackedStringArray(years))]
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

func _change_game_length(interval_delta: int, count_delta: int) -> void:
	MultiplayerManager.set_game_length(MultiplayerManager.election_interval + interval_delta,
		MultiplayerManager.election_count + count_delta)

# --- Ayar paneli ------------------------------------------------------------------

func _build_settings_panel() -> void:
	settings_vbox.add_theme_constant_override("separation", 8)
	var title := settings_vbox.get_node("HeaderRow/TitleLabel") as Label
	title.text = L.t("OYUN KURALLARI")
	title.add_theme_font_size_override("font_size", 16)
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
		button.text = "%d s" % seconds
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(56, 34)
		button.set_meta("seconds", seconds)
		UiSkin.skin_button(button)
		button.pressed.connect(func(): MultiplayerManager.set_vote_timeout(int(button.get_meta("seconds"))))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		votes_row.add_child(button)
		vote_time_buttons.append(button)
	var world_box := _section(L.t("HARİTA VE MECLİS"), "")
	var labels := {"province_scale": L.t("İl sayısı"), "province_seats": L.t("İl milletvekilleri"), "national_seats": L.t("Ulusal milletvekilleri"), "turn_seconds": L.t("Tur süresi")}
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
	for key in ["province_seats", "national_seats", "turn_seconds"]:
		var target_box: VBoxContainer = _setting_sections["timing"] if key == "turn_seconds" else world_box
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

	var bot_box := _section(L.t("BOT GELİR ZAYIFLATMASI"), L.t("Botların dönemlik geliri ve bağış kampanyaları seçilen tutar kadar (milyon ¤) azalır. 0 = zayıflatma yok."))
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
		var style := UiSkin.stylebox(UiSkin.PANEL_DARK)
		style.set_content_margin_all(UiTheme.PAD_M)
		UiSkin.apply_style(panel, "panel", style)
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
		copy_code_button.hide()
		if hint != null:
			hint.text = L.t("Ağ yok: sadece sen ve eklediğin botlar oynar.")
		return
	copy_code_button.show()
	if hint != null:
		hint.text = L.t("Bu kodu arkadaşına gönder, o da 'Odaya Katıl' ekranına girsin.")
	var shown := "•••••" if GameSettings.streamer_mode else MultiplayerManager.room_code
	code_label.text = L.t("ODA KODU: %s") % shown

func _on_streamer_mode_changed(_enabled: bool) -> void:
	_refresh_code_display()

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(MultiplayerManager.room_code)
	copy_code_button.text = L.t("Kopyalandı!")
	await get_tree().create_timer(1.0).timeout
	copy_code_button.text = L.t("📋 Kopyala")

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
	SceneTransition.fade_to_scene("res://scenes/PoliticianSetup.tscn")

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
	add_child(margin)
	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 16)
	margin.add_child(root_box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root_box.add_child(header)
	var title := UiTheme.mono_label(L.t("SİYASET OYUNU"), 24, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var code_row := center_box.get_node("CodeRow")
	code_row.reparent(header)
	UiSkin.skin_button(copy_code_button)
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
	var heading := UiTheme.mono_label(L.t("OYUNCULAR"), 16, UiTheme.GOLD, true)
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
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	leave_button.reparent(footer)
	leave_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	UiSkin.skin_button(leave_button)
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
