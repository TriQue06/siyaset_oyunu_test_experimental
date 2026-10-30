class_name AvatarEditor
extends Control
## AVATAR EKRANI (0.0.304, konsept A "Stüdyo", bkz.
## konseptler/avatar_ekrani_konseptleri.html): solda parti renginde fotoğraf
## stüdyosu (üstten spot ışık, portre, altta isim plakası), ortada dikey
## kategori rayı (simge + ad), sağda 3 sütunlu seçenek kartları ve kategorinin
## renk pulları. Altta Rastgele, Geri al ve Tamam. İstek üzerine portre
## konseptten küçük tutulur.

signal appearance_changed(value: Dictionary)
const TITLES := {"face": "Yüz", "hair": "Saç", "eyebrows": "Kaş", "iris": "Göz", "moustache": "Bıyık", "beard": "Sakal"}
const ICONS := {"face": "av_face", "hair": "av_hair", "eyebrows": "av_brow", "iris": "av_eye", "moustache": "av_moustache", "beard": "av_beard"}
const PANEL_SIZE := Vector2(1000, 600)
const STAGE_WIDTH := 290.0
## Stüdyodaki portrenin boyu (konseptten küçük).
const PORTRAIT_SIZE := Vector2(200, 248)

const C_BOARD := Color("f7eed8")
const C_BOARD2 := Color("efe2c0")
const C_CARD := Color("fffaf0")
const C_SLOT := Color("eadfc4")
const C_LINE := Color("e3d5b0")
const C_LIP := Color("c9b689")
const C_EDGE := Color("b79a68")
const C_TEAL := Color("1f6e70")
const C_TEAL2 := Color("16575a")
const C_MUS := Color("f2b632")
const C_MUS2 := Color("b58312")
const C_INK := Color("2d2a26")
const C_MUTED := Color("7a7166")
const C_GHOST := Color("5d6b6b")
const C_GO := Color("1f8a4c")

var appearance: Dictionary = {}
## Stüdyo plakası ve zemin: {"name", "party", "party_data"(PartyBadge verisi), "color"}.
var context: Dictionary = {}
var _gender_drafts: Dictionary = {}
var _history: Array = []
var _category := "face"
var _preview: AvatarPortrait
var _stage: Control
var _rail: VBoxContainer
var _title: Label
var _sub: Label
var _genders: HBoxContainer
var _grid: GridContainer
var _scroll: ScrollContainer
var _palettes: VBoxContainer
var _undo: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# Konsept .screen: krem pano, 4 px içeride deniz yeşili çizgi, karton kalınlığı.
	var panel := PanelContainer.new()
	var style := BoardBox.new()
	style.fill = C_BOARD
	style.fill_bottom = C_BOARD2
	style.set_radius(20)
	style.rings = [[4.0, 2.0, C_TEAL]]
	style.lips = [[10.0, C_EDGE]]
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_offset = Vector2(0, 22)
	style.shadow_size = 16
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	var view := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(PANEL_SIZE.x, view.x - 24), minf(PANEL_SIZE.y, view.y - 24))
	center.add_child(panel)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	panel.add_child(main)
	_build_stage(main)
	_rail = VBoxContainer.new()
	_rail.custom_minimum_size.x = 78
	_rail.add_theme_constant_override("separation", 8)
	main.add_child(_rail)
	_build_panel(main)
	_refresh()

func set_appearance(value: Dictionary) -> void:
	appearance = AvatarCatalog.clean(value, String(value.get("gender", "m")))
	_gender_drafts[appearance.gender] = appearance.duplicate(true)
	if is_node_ready():
		_refresh()

# --- Stüdyo -------------------------------------------------------------------------

func _party_color() -> Color:
	return context.get("color", Color("e0283a"))

func _build_stage(parent: Control) -> void:
	_stage = _Studio.new()
	_stage.color = _party_color()
	_stage.custom_minimum_size = Vector2(STAGE_WIDTH, 0)
	_stage.clip_contents = true
	parent.add_child(_stage)
	_preview = AvatarPortrait.new()
	_preview.size = PORTRAIT_SIZE
	_stage.add_child(_preview)
	_stage.resized.connect(_place_stage)
	# İsim plakası.
	var plate := PanelContainer.new()
	plate.name = "Plate"
	var box := BoardBox.new()
	box.fill = C_CARD
	box.set_radius(14)
	box.rings = [[0.0, 1.5, C_LINE]]
	box.lips = [[4.0, C_LIP]]
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	plate.add_theme_stylebox_override("panel", box)
	_stage.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	plate.add_child(row)
	var party: Dictionary = context.get("party_data", {})
	if not party.is_empty():
		var logo := PartyBadge.build(party, Vector2(34, 34), 64)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(logo)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 1)
	row.add_child(texts)
	var name_label := _text(String(context.get("name", L.t("Siyasetçin"))), true, 19, C_INK)
	name_label.clip_text = true
	name_label.custom_minimum_size.x = 180
	texts.add_child(name_label)
	var party_name := String(context.get("party", ""))
	texts.add_child(_text((party_name + " · " if party_name != "" else "") + L.t("Genel Başkan"), false, 11, C_MUTED))

func _place_stage() -> void:
	var plate := _stage.get_node_or_null("Plate") as Control
	if plate == null:
		return
	plate.reset_size()
	plate.size.x = _stage.size.x - 48
	plate.position = Vector2(24, _stage.size.y - plate.size.y - 18)
	_preview.position = Vector2((_stage.size.x - PORTRAIT_SIZE.x) * 0.5, plate.position.y - PORTRAIT_SIZE.y - 28)
	_preview.size = PORTRAIT_SIZE

## Parti renginde stüdyo zemini, üstten spot ışık ve portrenin ayak gölgesi.
class _Studio extends Control:
	var color := Color("e0283a")
	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = color.lerp(Color("3a1a10"), 0.35)
		box.set_corner_radius_all(18)
		box.border_color = color.lerp(Color.BLACK, 0.4)
		box.set_border_width_all(3)
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		# Radyal açık merkez: iç içe yumuşak daireler.
		var c := Vector2(size.x * 0.5, size.y * 0.4)
		for i in 14:
			var k := 1.0 - float(i) / 14.0
			draw_circle(c, size.x * 0.95 * k, Color(color.lerp(Color("fff8ea"), 0.78), 0.09), true, -1.0, true)
		# Spot: üstten inen açık koni.
		var top := Vector2(size.x * 0.5, -40)
		for i in 10:
			var w := size.x * (0.25 + 0.06 * i)
			var pts := PackedVector2Array([top + Vector2(-20, 0), top + Vector2(20, 0), Vector2(size.x * 0.5 + w, size.y * 0.75), Vector2(size.x * 0.5 - w, size.y * 0.75)])
			draw_colored_polygon(pts, Color(1, 0.98, 0.86, 0.035))
		# Sahne gölgesi (ayak).
		var plate_y := size.y - 70.0
		draw_set_transform(Vector2(size.x * 0.5, plate_y - 18), 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, size.x * 0.36, Color(0, 0, 0, 0.22), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- Sağ panel ------------------------------------------------------------------------

func _build_panel(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_title = _text("", true, 26, C_INK)
	titles.add_child(_title)
	_sub = _text("", false, 12, C_MUTED)
	titles.add_child(_sub)
	_genders = HBoxContainer.new()
	_genders.add_theme_constant_override("separation", 5)
	_genders.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_genders)
	col.add_child(_sec(L.t("Şekil")))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	_palettes = VBoxContainer.new()
	_palettes.add_theme_constant_override("separation", 6)
	col.add_child(_palettes)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	var random := _button(L.t("Rastgele"), _party_color(), func(): _apply(AvatarCatalog.random(String(appearance.gender), randi())))
	foot.add_child(random)
	_undo = _button(L.t("Geri al"), C_SLOT, _undo_last, C_GHOST, C_LIP)
	foot.add_child(_undo)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var done := _button(L.t("Tamam"), C_GO, queue_free)
	done.custom_minimum_size = Vector2(150, 46)
	done.add_theme_font_size_override("font_size", 19)
	foot.add_child(done)

# --- Yapı taşları ---------------------------------------------------------------------

static func _text(text: String, display: bool, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true) if display else UiTheme.mono_regular())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _face(fill: Color, lip: Color, radius: float, lip_px: float, state: String, highlight: bool) -> BoardBox:
	var b := BoardBox.new()
	b.fill = fill.lightened(0.06) if state == "hover" else fill
	b.set_radius(radius)
	if highlight:
		b.highlight_size = 3.0
		b.highlight_color = Color(1, 1, 1, 0.3)
	b.lips = [[1.0 if state == "pressed" else lip_px, lip]]
	if state == "pressed":
		b.offset_y = lip_px - 1.0
	return b

static func _skin(button: Button, fill: Color, lip: Color, radius: float, lip_px: float, highlight: bool = true) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := _face(fill, lip, radius, lip_px, state, highlight)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 10
		box.content_margin_bottom = 11
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _button(text: String, fill: Color, action: Callable, ink: Color = Color.WHITE, lip: Color = Color(0, 0, 0, 0)) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 16)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(key, ink)
	_skin(button, fill, lip if lip.a > 0.0 else fill.lerp(Color.BLACK, 0.4), 12, 4, ink == Color.WHITE)
	button.pressed.connect(action)
	return button

## Konsept .sec: küçük büyük harf başlık + çizgi.
static func _sec(title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text(title.to_upper(), false, 10, C_MUTED))
	var rule := ColorRect.new()
	rule.color = C_LINE
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	return row

static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

# --- Durum ------------------------------------------------------------------------

## Yeni görünüm uygulanır; eskisi Geri al için saklanır.
func _apply(value: Dictionary) -> void:
	_history.append(appearance.duplicate(true))
	if _history.size() > 40:
		_history.pop_front()
	appearance = AvatarCatalog.clean(value, String(value.get("gender", appearance.gender)))
	if appearance.gender == "f" and _category in ["beard", "moustache"]:
		_category = "face"
	_refresh()
	appearance_changed.emit(appearance.duplicate(true))

func _undo_last() -> void:
	if _history.is_empty():
		return
	appearance = _history.pop_back()
	_refresh()
	appearance_changed.emit(appearance.duplicate(true))

func _select_gender(gender: String) -> void:
	if gender == appearance.gender:
		return
	_gender_drafts[appearance.gender] = appearance.duplicate(true)
	_apply(AvatarCatalog.clean(_gender_drafts.get(gender, {}), gender))

func _select(category: String, id: Variant) -> void:
	var value := appearance.duplicate(true)
	value[category] = id
	_apply(value)

func _select_color(field: String, id: String) -> void:
	var value := appearance.duplicate(true)
	value[field] = id
	_apply(value)

func _choose_category(category: String) -> void:
	_category = category
	_scroll.scroll_vertical = 0
	_refresh()

func _refresh() -> void:
	if _preview == null:
		return
	_preview.set_appearance(appearance)
	_place_stage.call_deferred()
	_undo.modulate.a = 1.0 if not _history.is_empty() else 0.55
	_refresh_rail()
	_refresh_genders()
	var choices: Array = []
	choices.append_array(AvatarCatalog.options(_category, appearance.gender))
	if AvatarCatalog.OPTIONAL.has(_category):
		choices.push_front(null)
	_title.text = L.t(TITLES[_category])
	_sub.text = L.t("%d seçenek · rengini aşağıdan seç") % choices.size()
	_refresh_palettes()
	_clear(_grid)
	for id: Variant in choices:
		_grid.add_child(_option_card(id))

func _refresh_rail() -> void:
	_clear(_rail)
	for category: String in AvatarCatalog.CATEGORIES:
		if appearance.gender == "f" and category in ["beard", "moustache"]:
			continue
		var on := category == _category
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(78, 58)
		if on:
			_skin(button, C_TEAL, C_TEAL2, 14, 3)
		else:
			_skin(button, C_SLOT, C_LIP, 14, 3, false)
		var icon := _RailIcon.new()
		icon.icon = String(ICONS[category])
		icon.ink = Color.WHITE if on else C_GHOST
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_bottom = -18
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var label := _text(L.t(TITLES[category]), false, 11, Color.WHITE if on else C_GHOST)
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		label.offset_top = -22
		label.offset_bottom = -6
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_child(label)
		button.pressed.connect(_choose_category.bind(category))
		_rail.add_child(button)

class _RailIcon extends Control:
	var icon := ""
	var ink := Color.WHITE
	func _draw() -> void:
		VoterGroupIcon.draw_symbol(self, icon, size * 0.5 + Vector2(0, 3), 13.0, ink)

func _refresh_genders() -> void:
	_clear(_genders)
	for g: String in ["m", "f"]:
		var on: bool = g == appearance.gender
		var button := _button(L.t("Erkek" if g == "m" else "Kadın"), C_MUS if on else C_LINE, _select_gender.bind(g),
			Color("4a3203") if on else C_GHOST, C_MUS2 if on else C_LIP)
		button.add_theme_font_size_override("font_size", 15)
		_genders.add_child(button)

## Konsept .opt: krem kart, içinde o parçanın değiştiği yüz; seçili kart
## altın halkalı ve sağ üstte altın işaret.
func _option_card(id: Variant) -> Button:
	var selected: bool = appearance.get(_category) == id
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 132)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	for state in ["normal", "hover", "pressed"]:
		var b := BoardBox.new()
		b.fill = Color("fff6dc") if selected else (C_CARD.lightened(0.3) if state == "hover" else C_CARD)
		b.set_radius(14)
		b.rings = [[0.0, 3.0, C_MUS]] if selected else [[0.0, 1.5, C_LINE]]
		b.lips = [[3.0, C_MUS2 if selected else C_LIP]]
		button.add_theme_stylebox_override(state, b)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_select.bind(_category, id))
	var thumb := AvatarPortrait.new()
	var sample := appearance.duplicate(true)
	sample[_category] = id
	thumb.set_appearance(sample)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Yüz kartı doldursun: tuval karttan büyük, alttan taşar.
	thumb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	thumb.size = Vector2(130, 130)
	thumb.position = Vector2(-65, 2)
	thumb.offset_left = -65
	thumb.offset_right = 65
	thumb.offset_top = -4
	thumb.offset_bottom = 126
	button.add_child(thumb)
	var label := _text(L.t("Yok") if id == null else L.t(String(AvatarCatalog.data().assets[id].label)), false, 11, C_MUTED)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -22
	label.offset_bottom = -5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var strip := ColorRect.new()
	strip.color = Color("fff6dc") if selected else C_CARD
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -24
	strip.offset_left = 3
	strip.offset_right = -3
	strip.offset_bottom = -4
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(strip)
	button.add_child(label)
	if selected:
		var tick := _Tick.new()
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		tick.offset_left = -26
		tick.offset_right = -8
		tick.offset_top = 8
		tick.offset_bottom = 26
		button.add_child(tick)
	return button

class _Tick extends Control:
	func _draw() -> void:
		var r := size.x * 0.5
		draw_circle(size * 0.5, r, Color("f2b632"), true, -1.0, true)
		draw_polyline(PackedVector2Array([Vector2(r * 0.5, r), Vector2(r * 0.85, r * 1.35), Vector2(r * 1.5, r * 0.65)]), Color("4a3203"), 2.4, true)

## Kategorinin renk pulları (yüzde ten ve dudak).
func _refresh_palettes() -> void:
	_clear(_palettes)
	var fields: Array = ["skin_color", "lip_color"] if _category == "face" else ["eyebrow_color" if _category == "eyebrows" else _category + "_color"]
	for field: String in fields:
		var title := "Ten rengi" if field == "skin_color" else ("Dudak rengi" if field == "lip_color" else (String(TITLES[_category]) + " rengi"))
		var selected := AvatarColors.preset(field, appearance)
		_palettes.add_child(_sec(L.t(title) + " · " + L.t(selected[1])))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 9)
		row.add_theme_constant_override("v_separation", 8)
		_palettes.add_child(row)
		for option: Array in AvatarColors.palette(field, appearance.gender):
			var swatch := _Swatch.new()
			swatch.color = Color(option[3])
			swatch.active = appearance.get(field) == option[0]
			swatch.custom_minimum_size = Vector2(36, 36)
			swatch.tooltip_text = L.t(option[1])
			swatch.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			swatch.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_select_color(field, String(option[0])))
			row.add_child(swatch)

## Konsept .sw: yuvarlak renk pulu; seçili olanda krem boşluk + altın halka.
class _Swatch extends Control:
	var color := Color.WHITE
	var active := false
	func _draw() -> void:
		var c := size * 0.5
		var r := 15.0
		if active:
			draw_circle(c, r + 6.0, Color("f2b632"), true, -1.0, true)
			draw_circle(c, r + 3.0, Color("fffaf0"), true, -1.0, true)
		draw_circle(c + Vector2(0, 2), r, color.lerp(Color.BLACK, 0.3), true, -1.0, true)
		draw_circle(c, r, color, true, -1.0, true)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
