extends Control

const SETTINGS_SHIFT := 150.0
const SLIDE_DURATION := 0.2

@onready var code_label: Label = %CodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var player_list_box: GridContainer = %PlayerListBox

## 8 sabit oyuncu kartı, 2 sütun. Robot butonu kartın sağ üst köşesine taşar.
const SLOT_SIZE := Vector2(412, 74)
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
const SECTION_COLOR := Color(0.93, 0.66, 0.22)
var interval_value_label: Label
var interval_minus: Button
var interval_plus: Button
var count_value_label: Label
var count_minus: Button
var count_plus: Button
var game_length_summary: Label
var threshold_slider: HSlider
var threshold_value_label: Label
var axis_start_slider: HSlider
var axis_start_value_label: Label
var axis_increment_slider: HSlider
var axis_increment_value_label: Label
var axis_max_enabled_check: CheckButton
var axis_max_value_row: HBoxContainer
var axis_max_value_slider: HSlider
var axis_max_value_value_label: Label

var _settings_open: bool = false
var _center_base_x: float = 0.0

func _ready() -> void:
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

	axis_start_slider.min_value = MultiplayerManager.AXIS_SHARPNESS_START_MIN
	axis_start_slider.max_value = MultiplayerManager.AXIS_SHARPNESS_START_MAX
	axis_start_slider.step = 0.5
	axis_start_slider.value_changed.connect(_on_axis_start_slider_changed)

	axis_increment_slider.min_value = MultiplayerManager.AXIS_SHARPNESS_INCREMENT_MIN
	axis_increment_slider.max_value = MultiplayerManager.AXIS_SHARPNESS_INCREMENT_MAX
	axis_increment_slider.step = 0.05
	axis_increment_slider.value_changed.connect(_on_axis_increment_slider_changed)

	axis_max_enabled_check.toggled.connect(_on_axis_max_enabled_toggled)

	axis_max_value_slider.min_value = 0
	axis_max_value_slider.max_value = MultiplayerManager.AXIS_SHARPNESS_CAP_OPTIONS.size() - 1
	axis_max_value_slider.step = 1
	axis_max_value_slider.value_changed.connect(_on_axis_max_value_slider_changed)

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

	var count := MultiplayerManager.players.size()
	info_label.text = "Oyuncular: %d / %d  (başlamak için en az %d gerekir)" % [
		count, MultiplayerManager.MAX_PLAYERS, MultiplayerManager.MIN_PLAYERS_TO_START
	]

	settings_button.visible = am_owner
	start_button.visible = am_owner
	start_button.disabled = count < MultiplayerManager.MIN_PLAYERS_TO_START

	if not am_owner and _settings_open:
		_close_settings_panel()

	threshold_slider.editable = am_owner
	for button in [interval_minus, interval_plus, count_minus, count_plus]:
		button.disabled = not am_owner
	axis_start_slider.editable = am_owner
	axis_increment_slider.editable = am_owner
	axis_max_enabled_check.disabled = not am_owner
	axis_max_value_slider.editable = am_owner
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
		card.modulate = Color(1.08, 1.05, 0.9)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = color.darkened(0.2) if not is_bot else Color(0.35, 0.37, 0.42)
	avatar_style.set_corner_radius_all(22)
	avatar.add_theme_stylebox_override("panel", avatar_style)
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
	name_label.add_theme_font_size_override("font_size", 18)
	info.add_child(name_label)
	var tags: Array[String] = []
	if peer_id == MultiplayerManager.owner_id:
		tags.append("★ Oda sahibi")
	if peer_id == local_id:
		tags.append("Sen")
	if is_bot:
		tags.append("Bot")
	if not tags.is_empty():
		var tag_label := Label.new()
		tag_label.text = "  ·  ".join(tags)
		tag_label.add_theme_font_size_override("font_size", 12)
		tag_label.modulate = Color(1.0, 0.85, 0.4) if peer_id == MultiplayerManager.owner_id else Color(1, 1, 1, 0.6)
		info.add_child(tag_label)
	row.add_child(info)

	if am_owner and peer_id != local_id:
		var action := Button.new()
		UiSkin.skin_button(action)
		action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if is_bot:
			action.text = "Çıkar"
			action.pressed.connect(func(): MultiplayerManager.remove_bot(peer_id))
		else:
			action.text = "Sahipliği Devret"
			action.pressed.connect(func(): MultiplayerManager.transfer_ownership(peer_id))
		row.add_child(action)
	return card

## Kartı sabit boyutlu bir slota yerleştirir; istenirse sağ üst köşesine
## yuvarlak robot butonu oturtur (enabled=false ise soluk ve basılamaz).
func _build_slot(card: Control, show_bot_button: bool, enabled: bool) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = SLOT_SIZE
	card.custom_minimum_size = Vector2.ZERO
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_top = BOT_BUTTON_SIZE * 0.45
	card.offset_right = -BOT_BUTTON_SIZE * 0.45
	slot.add_child(card)
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
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(int(BOT_BUTTON_SIZE / 2.0))
		style.set_border_width_all(2)
		style.border_color = Color(1, 1, 1, 0.85 if enabled else 0.25)
		style.bg_color = Color(0.16, 0.55, 0.5) if enabled else Color(0.22, 0.24, 0.28)
		if state == "hover":
			style.bg_color = style.bg_color.lightened(0.15)
		elif state == "pressed":
			style.bg_color = style.bg_color.darkened(0.2)
		button.add_theme_stylebox_override(state, style)
	var robot := RobotIcon.new()
	robot.set_anchors_preset(Control.PRESET_FULL_RECT)
	robot.color = Color.WHITE if enabled else Color(1, 1, 1, 0.35)
	button.add_child(robot)
	if enabled:
		button.pressed.connect(MultiplayerManager.add_bot)
	slot.add_child(button)
	return slot

func _build_empty_card(index: int) -> Control:
	var card := PanelContainer.new()
	UiSkin.skin_panel(card, UiSkin.PANEL)
	card.modulate = Color(1, 1, 1, 0.4)
	var label := Label.new()
	label.text = "%d · Boş" % (index + 1)
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
	var t := MultiplayerManager.election_threshold
	var interval := MultiplayerManager.election_interval
	var count := MultiplayerManager.election_count
	threshold_label.text = "Baraj %%%s  ·  %d seçim, %d turda bir (%d tur)" % [_format_threshold(t), count, interval, interval * count]
	interval_value_label.text = str(interval)
	count_value_label.text = str(count)
	var rounds: Array = []
	for i in range(1, count + 1):
		rounds.append(str(interval * i))
	if rounds.size() > 5:
		rounds = rounds.slice(0, 3) + ["…"] + rounds.slice(rounds.size() - 1)
	game_length_summary.text = "Toplam %d tur. Seçimler: %s. turlarda." % [interval * count, ", ".join(PackedStringArray(rounds))]
	if MultiplayerManager.is_local_owner():
		interval_minus.disabled = interval <= GameRules.ELECTION_INTERVAL_MIN
		interval_plus.disabled = interval >= GameRules.ELECTION_INTERVAL_MAX
		count_minus.disabled = count <= GameRules.ELECTION_COUNT_MIN
		count_plus.disabled = count >= GameRules.ELECTION_COUNT_MAX
	threshold_value_label.text = "%%%s" % _format_threshold(t)
	if not threshold_slider.has_focus():
		threshold_slider.value = t

	axis_start_value_label.text = "%.1f" % MultiplayerManager.axis_sharpness_start
	if not axis_start_slider.has_focus():
		axis_start_slider.value = MultiplayerManager.axis_sharpness_start

	axis_increment_value_label.text = "%.1f" % MultiplayerManager.axis_sharpness_increment
	if not axis_increment_slider.has_focus():
		axis_increment_slider.value = MultiplayerManager.axis_sharpness_increment

	axis_max_enabled_check.button_pressed = MultiplayerManager.axis_sharpness_max_enabled
	axis_max_value_row.visible = MultiplayerManager.axis_sharpness_max_enabled
	axis_max_value_slider.visible = MultiplayerManager.axis_sharpness_max_enabled
	axis_max_value_value_label.text = "%.0f" % MultiplayerManager.axis_sharpness_max_value
	if not axis_max_value_slider.has_focus():
		var cap_idx := MultiplayerManager.AXIS_SHARPNESS_CAP_OPTIONS.find(MultiplayerManager.axis_sharpness_max_value)
		axis_max_value_slider.value = cap_idx if cap_idx != -1 else 0

func _format_threshold(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

func _on_threshold_slider_changed(value: float) -> void:
	MultiplayerManager.set_election_threshold(value)

func _change_game_length(interval_delta: int, count_delta: int) -> void:
	MultiplayerManager.set_game_length(MultiplayerManager.election_interval + interval_delta,
		MultiplayerManager.election_count + count_delta)

func _on_axis_start_slider_changed(value: float) -> void:
	MultiplayerManager.set_axis_sharpness_start(value)

func _on_axis_increment_slider_changed(value: float) -> void:
	MultiplayerManager.set_axis_sharpness_increment(value)

func _on_axis_max_enabled_toggled(enabled: bool) -> void:
	axis_max_value_row.visible = enabled
	axis_max_value_slider.visible = enabled
	MultiplayerManager.set_axis_sharpness_max_enabled(enabled)

func _on_axis_max_value_slider_changed(index: float) -> void:
	var value: float = MultiplayerManager.AXIS_SHARPNESS_CAP_OPTIONS[int(index)]
	MultiplayerManager.set_axis_sharpness_max_value(value)

# --- Ayar paneli ------------------------------------------------------------------

func _build_settings_panel() -> void:
	settings_vbox.add_theme_constant_override("separation", 8)
	var title := settings_vbox.get_node("HeaderRow/TitleLabel") as Label
	title.add_theme_font_size_override("font_size", 20)

	var length := _section("OYUN SÜRESİ", "")
	var interval_row := _stepper_row(length, "Seçimler kaç turda bir")
	interval_minus = interval_row[0]
	interval_value_label = interval_row[1]
	interval_plus = interval_row[2]
	var count_row := _stepper_row(length, "Kaç seçim olacak")
	count_minus = count_row[0]
	count_value_label = count_row[1]
	count_plus = count_row[2]
	game_length_summary = _note(length, "")
	game_length_summary.add_theme_color_override("font_color", Color(SECTION_COLOR, 0.9))

	var election := _section("SEÇİM", "")
	var threshold_row := _value_row(election, "Seçim barajı")
	threshold_value_label = threshold_row
	threshold_slider = HSlider.new()
	election.add_child(threshold_slider)

	var axis := _section("GELİŞMİŞ · EKSEN KESKİNLİĞİ", "İller görüşüne en yakın partiye ne kadar yönelir.")
	axis_start_value_label = _value_row(axis, "Başlangıç")
	axis_start_slider = HSlider.new()
	axis.add_child(axis_start_slider)
	axis_increment_value_label = _value_row(axis, "Tur başına artış")
	axis_increment_slider = HSlider.new()
	axis.add_child(axis_increment_slider)
	var cap_row := HBoxContainer.new()
	var cap_label := _row_label("Üst sınır")
	cap_row.add_child(cap_label)
	axis_max_enabled_check = CheckButton.new()
	cap_row.add_child(axis_max_enabled_check)
	axis.add_child(cap_row)
	axis_max_value_row = HBoxContainer.new()
	axis_max_value_row.add_child(_row_label("Sınır değeri"))
	axis_max_value_value_label = _value_label()
	axis_max_value_row.add_child(axis_max_value_value_label)
	axis.add_child(axis_max_value_row)
	axis_max_value_slider = HSlider.new()
	axis.add_child(axis_max_value_slider)

## Başlıklı, çerçeveli bir ayar bölümü; içeriğin ekleneceği kutuyu döner.
func _section(title_text: String, note_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.04)
	style.border_color = Color(1, 1, 1, 0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	settings_vbox.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", SECTION_COLOR)
	box.add_child(title)
	if note_text != "":
		_note(box, note_text)
	return box

func _note(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
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
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
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
	var shown := "•••••" if GameSettings.streamer_mode else MultiplayerManager.room_code
	code_label.text = "ODA KODU: %s" % shown

func _on_streamer_mode_changed(_enabled: bool) -> void:
	_refresh_code_display()

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(MultiplayerManager.room_code)
	copy_code_button.text = "Kopyalandı!"
	await get_tree().create_timer(1.0).timeout
	copy_code_button.text = "📋 Kopyala"

## Lobi ayarları butonu: panel kapalıysa ekranın sağında açar ve ortadaki
## içeriği hafifçe sola kaydırır; açıksa tersini yapıp kapatır.
func _on_settings_pressed() -> void:
	if _settings_open:
		_close_settings_panel()
	else:
		_open_settings_panel()

func _open_settings_panel() -> void:
	_settings_open = true
	settings_side_panel.show()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(center_box, "position:x", _center_base_x - SETTINGS_SHIFT, SLIDE_DURATION)

func _close_settings_panel() -> void:
	_settings_open = false
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(center_box, "position:x", _center_base_x, SLIDE_DURATION)
	tween.finished.connect(func(): settings_side_panel.hide())

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
