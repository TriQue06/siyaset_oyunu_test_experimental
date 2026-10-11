extends Control
## SİYASETÇİ PROFİLİ ekranı — parti kurulumundan ÖNCE, her oyuncuya özel.
## Solda siyasetçinin adı ve 6 geçmiş (her biri bir seçmen grubuyla bağlantılı),
## sağda bu oyunun haritası: tıklanan il memleket olur. Geçmiş ve memleket
## seçilince "Partini Kur" açılır; seçimler PartyManager.set_my_politician ile
## gider ve oyuncu Parti Kurulum ekranına geçer. Kurallar: PoliticianPresets.
## Arayüz tamamen kodla kurulur (sahne sadece kök düğüm).

const MAP_SCENE := preload("res://scenes/Map.tscn")
const LEFT_WIDTH := 540.0
const CARD_SIZE := Vector2(258, 132)
const MAP_PADDING := 12.0
const HOME_COLOR := Color("FFC93C")
## Cinsiyet düğmeleri: erkek mavi, kadın pembe.
const GENDER_STYLE := {"m": {"text": "Erkek", "color": Color("3A8DE0")},
	"f": {"text": "Kadın", "color": Color("E8559C")}}

var _background_id: String = ""
var _hometown: String = ""
var _hovered: String = ""
var _gender: String = "m"
var _gender_buttons: Dictionary = {}   # "m"/"f" -> Button
var _first_name: String = ""
var _surname: String = ""
var _first_edit: LineEdit
var _surname_edit: LineEdit
var _cards: Dictionary = {}          # background id -> Button
var _map_clip: Control
var _map: Node2D
var _info_title: Label
var _info_body: Label
var _summary: Label
var _continue: Button

func _ready() -> void:
	theme = load("res://assets/ui/main_theme.tres")
	# Harita tıklamaları _unhandled_input ile gelir: tam ekran kök düğüm
	# (varsayılan STOP) tıklamaları yutuyordu, memleket seçilemiyordu.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_restore_previous()
	if GameMap.province_ids().is_empty():
		# Tek başına çalıştırılan sahne (oyun yok): örnek bir harita kur.
		GameMap.generate_new(GameMap.DEFAULT_SEED)
	_refresh()

# --- Kurulum ------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top := VBoxContainer.new()
	top.position = Vector2(28, 14)
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(UiTheme.mono_label("SİYASETÇİNİ OLUŞTUR", 26, UiTheme.GOLD, true))
	top.add_child(PopupKit.label("Parti kurmadan önce: kim olduğunu ve nereden geldiğini seç.", 13, UiTheme.TEXT_MUTED))

	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = 16
	main.offset_top = 78
	main.offset_right = -16
	main.offset_bottom = -16
	main.add_theme_constant_override("separation", 14)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main)
	main.add_child(_build_left())
	main.add_child(_build_right())

func _panel(width: float) -> Array:
	var built := PopupKit.frame(width, UiTheme.GOLD)
	var panel: PanelContainer = built[0]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return built

func _build_left() -> Control:
	var built := _panel(LEFT_WIDTH)
	var body: VBoxContainer = built[1]
	body.add_child(PopupKit.section("Siyasetçi"))
	# İSİM RASTGELE: elle yazılmaz, zar sınırsız atılabilir.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	body.add_child(name_row)
	# Önce cinsiyet: ad listesi buna göre seçilir.
	for g in ["m", "f"]:
		var gb := Button.new()
		gb.text = String(GENDER_STYLE[g]["text"])
		gb.focus_mode = Control.FOCUS_NONE
		gb.custom_minimum_size = Vector2(86, 38)
		gb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gb.add_theme_font_size_override("font_size", 15)
		gb.pressed.connect(_on_gender_pressed.bind(g))
		name_row.add_child(gb)
		_gender_buttons[g] = gb
	# Ad ve soyad elle de yazılabilir; baş harfler zorla büyük yapılır.
	_first_edit = _name_edit("Ad")
	name_row.add_child(_first_edit)
	_surname_edit = _name_edit("Soyad")
	name_row.add_child(_surname_edit)
	# Üç zar: sadece ad, sadece soyad, ikisi birden (sınırsız basılır).
	var dice_row := HBoxContainer.new()
	dice_row.add_theme_constant_override("separation", 8)
	body.add_child(dice_row)
	for spec in [["🎲 Ad", "Sadece adı değiştir", true, false],
			["🎲 Soyad", "Sadece soyadı değiştir", false, true],
			["🎲 İkisi de", "Ad ve soyadı birlikte değiştir", true, true]]:
		var dice := Button.new()
		dice.text = spec[0]
		dice.tooltip_text = spec[1]
		dice.focus_mode = Control.FOCUS_NONE
		dice.custom_minimum_size = Vector2(0, 36)
		dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dice.pressed.connect(_reroll_name.bind(spec[2], spec[3]))
		dice_row.add_child(dice)
	_reroll_name(true, true)

	body.add_child(PopupKit.section("Geçmiş", "partini bir seçmen grubuna biraz yaklaştırır"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for id in PoliticianPresets.BACKGROUND_ORDER:
		var card := _background_card(String(id))
		grid.add_child(card)
		_cards[id] = card
	return built[0]

## Bir geçmiş kartı: ad, seçmen grubu çipi, kısa hikâye, avantaj.
func _background_card(id: String) -> Button:
	var info := PoliticianPresets.background(id)
	var button := Button.new()
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.pressed.connect(_on_background_pressed.bind(id))
	# Seçili kartın altın çerçevesi.
	var frame := Panel.new()
	frame.name = "SelectedFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(UiTheme.GOLD, 0.08)
	ring.border_color = UiTheme.GOLD
	ring.set_border_width_all(3)
	frame.add_theme_stylebox_override("panel", ring)
	frame.visible = false
	button.add_child(frame)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var t := UiTheme.mono_label(String(info["title"]), 15, UiTheme.TEXT, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var group := PoliticianPresets.group_of(id)
	var group_row := HBoxContainer.new()
	group_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group_row.add_theme_constant_override("separation", 4)
	group_row.add_child(VoterGroupIcon.make(group, 16.0))
	group_row.add_child(PopupKit.chip(VoterGroups.title(group), VoterGroups.color(group)))
	box.add_child(group_row)
	var blurb := PopupKit.note(String(info["blurb"]), UiTheme.TEXT_MUTED)
	box.add_child(blurb)
	var perk := PopupKit.note("★ " + String(info["perk"]), UiTheme.GREEN)
	box.add_child(perk)
	return button

func _build_right() -> Control:
	var built := _panel(0)
	var panel: PanelContainer = built[0]
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Harita tıklamaları _unhandled_input ile gelir: paneller yutmasın.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body: VBoxContainer = built[1]
	body.add_child(PopupKit.section("Memleket", "haritadan bir il seç"))
	body.add_child(PopupKit.note("Memleketinde güçlü bir teşkilatla başlarsın; hemşehrilerin sana sahip çıkar.",
		UiTheme.TEXT_MUTED))

	_map_clip = Control.new()
	_map_clip.clip_contents = true
	_map_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_map_clip)
	_map = MAP_SCENE.instantiate()
	_map_clip.add_child(_map)
	var markers := _map.get_node_or_null("SeatMarkers")
	if markers != null:
		markers.visible = false
	_map.province_clicked.connect(_on_province_clicked)
	_map.province_hovered.connect(_on_province_hovered)
	_map_clip.resized.connect(_fit_map)
	GameMap.map_changed.connect(_fit_map)

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 14)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(info)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(texts)
	_info_title = UiTheme.mono_label("", 16, UiTheme.TEXT, true)
	_info_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_info_title)
	_info_body = PopupKit.note("", UiTheme.TEXT_MUTED)
	texts.add_child(_info_body)
	_summary = PopupKit.note("", UiTheme.GOLD)
	texts.add_child(_summary)
	_continue = Button.new()
	_continue.text = "Partini Kur  →"
	_continue.custom_minimum_size = Vector2(200, 48)
	_continue.size_flags_vertical = Control.SIZE_SHRINK_END
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.add_theme_font_size_override("font_size", 18)
	_continue.pressed.connect(_on_continue_pressed)
	info.add_child(_continue)
	return panel

## Haritayı kutuya sığdır ve ortala.
func _fit_map() -> void:
	if _map == null or _map_clip == null:
		return
	var native := GameMap.map_size()
	var space := _map_clip.size - Vector2(MAP_PADDING, MAP_PADDING) * 2.0
	if native.x <= 0.0 or native.y <= 0.0 or space.x <= 0.0 or space.y <= 0.0:
		return
	var s := minf(space.x / native.x, space.y / native.y)
	_map.scale = Vector2(s, s)
	_map.position = (_map_clip.size - native * s) * 0.5

# --- Etkileşim ----------------------------------------------------------------------

func _on_gender_pressed(gender: String) -> void:
	if gender == _gender:
		return
	_gender = gender
	_reroll_name(true, false)

## Klasik düğme dokusu, cinsiyet renginde: seçili tam renk, diğeri koyu ve sönük.
func _style_gender_buttons() -> void:
	for g in _gender_buttons.keys():
		var gb: Button = _gender_buttons[g]
		var color: Color = GENDER_STYLE[g]["color"]
		var selected: bool = g == _gender
		UiSkin.skin_color_button(gb, color if selected else color.darkened(0.55))
		if not selected:
			for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				gb.add_theme_color_override(prop, UiTheme.TEXT_MUTED)

func _reroll_name(first: bool, last: bool) -> void:
	_style_gender_buttons()
	if first:
		_first_name = PoliticianPresets.random_first_name(_gender, _first_name)
	if last:
		var avoid := PoliticianPresets.used_surnames(multiplayer.get_unique_id())
		if _surname != "":
			avoid.append(_surname)  # her basışta farklı bir soyad
		_surname = PoliticianPresets.random_surname(avoid)
	_first_edit.text = _first_name
	_surname_edit.text = _surname
	if _continue != null:
		_refresh()

func _name_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = PoliticianPresets.PART_MAX_LENGTH
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 40)
	edit.add_theme_font_override("font", UiTheme.mono(true))
	edit.add_theme_font_size_override("font_size", 20)
	edit.text_changed.connect(_on_name_typed.bind(edit))
	return edit

func _on_name_typed(text: String, edit: LineEdit) -> void:
	var fixed := PoliticianPresets.normalize_name(text)
	if fixed != text:
		var caret := edit.caret_column
		edit.text = fixed
		edit.caret_column = mini(caret, fixed.length())
	if edit == _first_edit:
		_first_name = fixed.strip_edges()
	else:
		_surname = fixed.strip_edges()
	if _continue != null:
		_refresh()

## Parti kurulumundan GERİ dönüldüyse önceki seçimler yerinde durur.
func _restore_previous() -> void:
	var data: Dictionary = PartyManager.my_politician
	if data.is_empty():
		return
	_gender = String(data.get("gender", _gender))
	_first_name = String(data.get("first_name", _first_name))
	_surname = String(data.get("surname", _surname))
	_background_id = String(data.get("background", ""))
	_hometown = String(data.get("hometown", ""))
	_style_gender_buttons()
	_first_edit.text = _first_name
	_surname_edit.text = _surname

func _full_name() -> String:
	return "%s %s" % [_first_name, _surname]

func _on_background_pressed(id: String) -> void:
	_background_id = id
	_refresh()

func _on_province_clicked(province_id: String) -> void:
	_hometown = province_id
	_refresh()

func _on_province_hovered(province_id: String) -> void:
	_hovered = province_id
	_refresh_info()

func _refresh() -> void:
	for id in _cards.keys():
		var card: Button = _cards[id]
		card.button_pressed = id == _background_id
		card.modulate = Color.WHITE if (_background_id == "" or id == _background_id) else Color(1, 1, 1, 0.62)
		var frame := card.get_node_or_null("SelectedFrame")
		if frame != null:
			frame.visible = id == _background_id
	_paint_map()
	_refresh_info()
	var ready := _is_complete()
	_continue.disabled = not ready
	var missing: Array = []
	if _background_id == "":
		missing.append("geçmiş")
	if _hometown == "":
		missing.append("memleket")
	if ready:
		_summary.text = "%s · %s · memleket %s" % [_full_name(),
			PoliticianPresets.title(_background_id), GameMap.name_of(_hometown)]
	else:
		_summary.text = "Seçilmedi: " + ", ".join(missing)

func _paint_map() -> void:
	_map.clear_overlay()
	if _hometown == "":
		return
	_map.set_province_colors({_hometown: HOME_COLOR})

## Alt bilgi: üzerinde durulan il, yoksa seçili memleket.
func _refresh_info() -> void:
	var id := _hovered if _hovered != "" else _hometown
	if id == "":
		_info_title.text = "Bir il seç"
		_info_body.text = "Haritada bir ile tıkla: orası senin memleketin olur."
		return
	_info_title.text = GameMap.name_of(id) + ("  ★ memleket" if id == _hometown else "")
	_info_body.text = "Senin memleketin." if id == _hometown else "Seçmek için tıkla."

func _is_complete() -> bool:
	return _first_name != "" and _surname != "" and not PoliticianPresets.is_banned_surname(_surname) \
		and _background_id != "" and _hometown != ""

func _on_continue_pressed() -> void:
	if not _is_complete():
		return
	_continue.disabled = true
	PartyManager.set_my_politician(PoliticianPresets.make(_first_name, _surname, _background_id, _hometown, _gender))
	SceneTransition.fade_to_scene("res://scenes/PartySetup.tscn")
