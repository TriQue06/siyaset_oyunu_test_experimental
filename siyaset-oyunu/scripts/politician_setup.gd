extends Control
## SİYASETÇİ PROFİLİ ekranı — parti kurulumundan ÖNCE, her oyuncuya özel.
## Solda siyasetçinin adı ve 6 geçmiş (her biri bir eksen ucuyla uyumlu),
## sağda bu oyunun haritası: tıklanan il memleket olur. Geçmiş ve memleket
## seçilince "Partini Kur" açılır; seçimler PartyManager.set_my_politician ile
## gider ve oyuncu Parti Kurulum ekranına geçer. Kurallar: PoliticianPresets.
## Arayüz tamamen kodla kurulur (sahne sadece kök düğüm).

const MAP_SCENE := preload("res://scenes/Map.tscn")
const LEFT_WIDTH := 540.0
const CARD_SIZE := Vector2(258, 116)
const MAP_PADDING := 12.0
## Eksen renkleri (parti profil kartındaki işaretlerle aynı aile).
const AXIS_COLORS := {
	"economic": Color("E67324"),
	"social": Color("70EC98"),
	"administrative": Color("AA67F4"),
}
const HOME_COLOR := Color("FFC93C")
const NEIGHBOR_COLOR := Color(1.0, 0.79, 0.24, 0.42)

var _background_id: String = ""
var _hometown: String = ""
var _hovered: String = ""
var _first_name: String = ""
var _surname: String = ""
var _name_label: Label
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
	_name_label = UiTheme.mono_label("", 24, UiTheme.TEXT, true)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	name_row.add_child(_name_label)
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

	body.add_child(PopupKit.section("Geçmiş", "partinin bir ekseni buradan gelir"))
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

## Bir geçmiş kartı: ad, eksen ucu çipi, kısa hikâye, avantaj.
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
	head.add_child(PopupKit.chip(PoliticianPresets.side_text(id).to_upper(), AXIS_COLORS[info["axis"]]))
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
	body.add_child(PopupKit.note(("Memleketinde 2. seviye teşkilatla başlarsın, il seçmeni görüşüne çekilir; " +
		"memleketinde +%.0f, komşu illerde +%.1f kalıcı hemşehri desteğin olur.") % [
		PoliticianPresets.HOMETOWN_ACTIVITY, PoliticianPresets.NEIGHBOR_ACTIVITY], UiTheme.TEXT_MUTED))

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

func _reroll_name(first: bool, last: bool) -> void:
	if first:
		_first_name = PoliticianPresets.random_first_name(_first_name)
	if last:
		var avoid := PoliticianPresets.used_surnames(multiplayer.get_unique_id())
		if _surname != "":
			avoid.append(_surname)  # her basışta farklı bir soyad
		_surname = PoliticianPresets.random_surname(avoid)
	_name_label.text = _full_name()
	if _continue != null:
		_refresh()

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
	var colors := {_hometown: HOME_COLOR}
	for n in GameMap.neighbors().get(_hometown, []):
		colors[n] = NEIGHBOR_COLOR
	_map.set_province_colors(colors)

## Alt bilgi: üzerinde durulan il, yoksa seçili memleket.
func _refresh_info() -> void:
	var id := _hovered if _hovered != "" else _hometown
	if id == "":
		_info_title.text = "Bir il seç"
		_info_body.text = "Büyük iller çok vekil getirir; komşusu çok olan il hemşehri desteğini geniş alana yayar."
		return
	var neighbors: Array = GameMap.neighbors().get(id, [])
	var near_seats := 0
	for n in neighbors:
		near_seats += GameMap.seats_of(String(n))
	_info_title.text = GameMap.name_of(id) + ("  ★ memleket" if id == _hometown else "")
	_info_body.text = "%d vekil · %d komşu il (toplam %d vekil)%s" % [GameMap.seats_of(id), neighbors.size(),
		near_seats, " · kıyı" if GameMap.is_coastal(id) else ""]

func _is_complete() -> bool:
	return _surname != "" and _background_id != "" and _hometown != ""

func _on_continue_pressed() -> void:
	if not _is_complete():
		return
	_continue.disabled = true
	PartyManager.set_my_politician(PoliticianPresets.make(_first_name, _surname, _background_id, _hometown))
	SceneTransition.fade_to_scene("res://scenes/PartySetup.tscn")
