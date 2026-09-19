extends Control
## ANA MENÜ: oyuncu adı, oda kurma ve koda göre odaya katılma tek ekranda.
##
## Bağlantı, internete açık bir röle sunucusu üzerinden kurulur (bkz.
## multiplayer_manager.gd, RELAY_URL). Oyuncular hiçbir IP/port bilgisi
## girmez; sadece oda kurulunca üretilen 5 harfli kod yeterlidir. Oda nerede
## kapanırsa kapansın oyuncu buraya sebebiyle birlikte döner.

const CARD_WIDTH := 320.0
const ACCENT := Color(0.93, 0.66, 0.22)
const BG_TOP := Color(0.08, 0.1, 0.17)
const BG_BOTTOM := Color(0.16, 0.12, 0.24)

var name_edit: LineEdit
var create_button: Button
var code_edit: LineEdit
var join_button: Button
var status_label: Label

func _ready() -> void:
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
	var bg := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([BG_TOP, BG_BOTTOM])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	bg.texture = texture
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
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
				var color := Color(1, 1, 1, 0.035) if (i + row) % 5 != 0 else Color(ACCENT, 0.08)
				arc.draw_circle(center + Vector2(cos(a), sin(a)) * radius, 7.0, color, true, -1.0, true))
	add_child(arc)

func _panel_style(bg: Color, border: Color, radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(24)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 18
	return style

func _button(text: String, color: Color, height: float = 54.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.bg_color = color
		style.set_content_margin_all(8)
		match state:
			"hover", "focus":
				style.bg_color = color.lightened(0.12)
			"pressed":
				style.bg_color = color.darkened(0.2)
			"disabled":
				style.bg_color = color.darkened(0.5)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color(0.1, 0.07, 0.02) if color.get_luminance() > 0.5 else Color.WHITE)
	button.add_theme_color_override("font_hover_color", button.get_theme_color("font_color"))
	button.add_theme_color_override("font_pressed_color", button.get_theme_color("font_color"))
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	return button

func _field(placeholder: String, max_length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(0, 40)
	edit.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1)
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	edit.add_theme_stylebox_override("normal", style)
	var focus := style.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT
	edit.add_theme_stylebox_override("focus", focus)
	return edit

func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return label

func _build_card() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	# KİMLİK: ince, hap biçimli ayrı bir şerit (oda kartından farklı görünür).
	var profile := PanelContainer.new()
	var profile_style := _panel_style(Color(0.2, 0.16, 0.3, 0.85), Color(ACCENT, 0.55), 22)
	profile_style.set_content_margin_all(8)
	profile_style.content_margin_left = 16
	profile_style.content_margin_right = 10
	profile_style.shadow_size = 8
	profile.add_theme_stylebox_override("panel", profile_style)
	profile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(profile)
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 10)
	profile.add_child(profile_row)
	var who := _small_label("Oyuncu adın")
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_theme_color_override("font_color", Color(ACCENT, 0.9))
	profile_row.add_child(who)
	name_edit = _field("Oyuncu adı", 20)
	name_edit.custom_minimum_size = Vector2(190, 34)
	name_edit.add_theme_font_size_override("font_size", 15)
	name_edit.text = PlayerProfile.player_name
	name_edit.text_changed.connect(_on_name_changed)
	profile_row.add_child(name_edit)

	# ODA: kurma ve katılma.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var card_style := _panel_style(Color(0.1, 0.11, 0.17, 0.94), Color(1, 1, 1, 0.1), 14)
	card_style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", card_style)
	column.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	create_button = _button("Oda Kur", ACCENT, 42.0)
	create_button.pressed.connect(_on_create_pressed)
	box.add_child(create_button)

	var divider := HBoxContainer.new()
	divider.add_theme_constant_override("separation", 8)
	var left := HSeparator.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.add_child(left)
	divider.add_child(_small_label("ya da koda katıl"))
	var right := HSeparator.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.add_child(right)
	box.add_child(divider)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	code_edit = _field("ODA KODU", 5)
	code_edit.custom_minimum_size = Vector2(0, 40)
	code_edit.add_theme_font_size_override("font_size", 16)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.secret_character = "•"
	code_edit.secret = GameSettings.streamer_mode
	code_edit.text_changed.connect(_on_code_text_changed)
	code_edit.text_submitted.connect(func(_t): _on_join_pressed())
	join_row.add_child(code_edit)
	join_button = _button("Katıl", Color(0.25, 0.45, 0.8), 40.0)
	join_button.custom_minimum_size.x = 96
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)
	box.add_child(join_row)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(CARD_WIDTH - 36.0, 18)
	status_label.add_theme_font_size_override("font_size", 12)
	box.add_child(status_label)

func _build_footer() -> void:
	var version := Label.new()
	version.text = "sürüm %s" % MultiplayerManager.game_version()
	version.add_theme_font_size_override("font_size", 13)
	version.modulate = Color(1, 1, 1, 0.6)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.position += Vector2(12, -28)
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)
	var quit := _button("Çıkış", Color(0.3, 0.3, 0.36), 32.0)
	quit.add_theme_font_size_override("font_size", 13)
	quit.custom_minimum_size.x = 84
	quit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	quit.position += Vector2(-100, -46)
	quit.pressed.connect(func(): get_tree().quit())
	add_child(quit)

func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if is_error else Color(1, 1, 1, 0.8))

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

func _on_create_pressed() -> void:
	create_button.disabled = true
	join_button.disabled = true
	_set_status("Oda kuruluyor...")
	MultiplayerManager.create_room(_player_name())

func _on_join_pressed() -> void:
	var code := code_edit.text.strip_edges()
	if code.length() != 5:
		_set_status("Oda kodu 5 harfli olmalı.", true)
		return
	_set_status("Bağlanılıyor...")
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

func _on_join_failed(reason: String) -> void:
	_set_status(reason, true)
	create_button.disabled = false
	join_button.disabled = false
