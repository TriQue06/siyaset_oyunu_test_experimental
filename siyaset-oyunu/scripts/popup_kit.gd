class_name PopupKit
extends RefCounted
## TIKLAMA MENÜLERİNİN ortak görünümü (il paneli, parti profili, kart bilgisi).
## Hepsi aynı ölçüleri kullanır ki biri dev, öbürü minik durmasın:
##   başlık 18 (kalın mono) · alt başlık 12 · bölüm 11 (altın, büyük harf)
##   · metin 13 · ikincil 12 · iç boşluk 12 · satır arası 6.
## Kalıp: üstte renkli şerit + başlık (+ rozet, + kapat), altında bölümler;
## bölümler "anahtar ... değer" satırları, çipler ve çubuklardan oluşur.

const FS_TITLE := 18
const FS_SUB := 12
const FS_SECTION := 11
const FS_TEXT := 13
const FS_SMALL := 12
const PAD := 12
const GAP := 6
const KEY := UiTheme.TEXT_MUTED

## Çerçeve: [panel, gövde]. accent: üst şeridin rengi.
## PANEL İÇİ (sol panel): çerçeve, gölge ve şerit yok; içerik panelin
## parçasıymış gibi doğrudan dar alana yerleşir, uzun yazılar alt satıra iner.
static var embedded := false

static func frame(width: float, accent: Color, panel: PanelContainer = null) -> Array:
	if panel == null:
		panel = PanelContainer.new()
	if embedded:
		UiSkin.apply_style(panel, "panel", StyleBoxEmpty.new())
		panel.custom_minimum_size = Vector2(width, 0)
		var plain := VBoxContainer.new()
		plain.add_theme_constant_override("separation", GAP)
		plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(plain)
		return [panel, plain]
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL_DARK
	# Menünün kime/neye ait olduğu kenar renginden belli (üstte kalın).
	style.border_color = accent
	style.set_border_width_all(2)
	style.border_width_top = 5
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 0
	style.shadow_offset = Vector2(4, 5)
	style.set_corner_radius_all(UiTheme.RADIUS)
	UiSkin.apply_style(panel, "panel", style)
	panel.custom_minimum_size = Vector2(width, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(outer)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PAD)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", GAP)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(body)
	return [panel, body]

## Başlık satırı: [rozet] başlık / alt başlık [kapat ✕].
static func header(title: String, subtitle: String, badge: Control = null, on_close: Callable = Callable()) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if badge != null:
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(names)
	var t := UiTheme.mono_label(title, FS_TITLE, UiTheme.TEXT, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.clip_text = true
	names.add_child(t)
	if subtitle != "":
		names.add_child(label(subtitle, FS_SUB, KEY))
	if on_close.is_valid():
		var close := Button.new()
		close.text = "X"
		close.custom_minimum_size = Vector2(30, 30)
		close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		close.focus_mode = Control.FOCUS_NONE
		close.add_theme_font_size_override("font_size", 14)
		UiSkin.skin_button(close)
		close.pressed.connect(on_close)
		row.add_child(close)
	return row

## Bölüm başlığı: altın küçük büyük harf + sağda ince çizgi; isteğe bağlı sağ not.
static func section(title: String, note: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UiTheme.mono_label(title.to_upper(), FS_SECTION, UiTheme.HEAD, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)
	var line := ColorRect.new()
	line.color = UiTheme.PANEL_LIGHT
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	if note != "" and not embedded:
		row.add_child(label(note, FS_SECTION, UiTheme.TEXT_DIM))
	var box := MarginContainer.new()
	box.add_theme_constant_override("margin_top", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	return box

## "Anahtar ........ değer" satırı.
static func kv(key: String, value: String, value_color: Color = UiTheme.TEXT) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := label(key, FS_TEXT, KEY)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if embedded:
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.custom_minimum_size.x = 60
	row.add_child(k)
	var v := label(value, FS_TEXT, value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

## Açıklama metni (sarmalı). width: sarma genişliği (0 = kapsayıcıya uy).
static func note(text: String, color: Color = KEY, width: float = 0.0) -> Label:
	var l := label(text, FS_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
	return l

## Küçük renkli etiket ("KALE", "GİZLİ", "2 para").
static func chip(text: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.16)
	style.border_color = color
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	UiSkin.apply_style(panel, "panel", style)
	var l := UiTheme.mono_label(text, 11, color.darkened(0.35), true)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Uzun çip satır kaydırır: dar panelde kartı genişletip taşırmasın.
	if text.length() > 22:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 1.0
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(l)
	return panel

## Etiketli ilerleme çubuğu: "Teşkilat ▓▓▓░░ 2/2".
static func meter(key: String, value: float, maximum: float, color: Color, value_text: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := label(key, FS_SMALL, KEY)
	k.custom_minimum_size = Vector2(92, 0)
	row.add_child(k)
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.custom_minimum_size = Vector2(0, 8)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = UiTheme.SLOT
	UiSkin.apply_style(track, "panel", track_style)
	row.add_child(track)
	var fill := ColorRect.new()
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(value / maxf(0.0001, maximum), 0.0, 1.0)
	track.add_child(fill)
	var v := label(value_text, FS_SMALL, UiTheme.TEXT)
	v.custom_minimum_size = Vector2(44, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	return row

## Parti satırı: renk kare, ad, sağda değerler (her biri sabit genişlikte sütun).
static func party_row(party: Dictionary, highlight: bool, values: Array, widths: Array = []) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := PartyBadge.build(party, Vector2(18, 18), 32)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var n := label(String(party.get("name", "?")) + (L.t("  (sen)") if highlight else ""), FS_TEXT,
		UiTheme.GOLD if highlight else UiTheme.TEXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	row.add_child(n)
	for i in values.size():
		var entry = values[i]
		var text: String = entry if entry is String else String(entry[0])
		var color: Color = UiTheme.TEXT if entry is String else entry[1]
		var v := label(text, FS_TEXT, color)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(float(widths[i]) if i < widths.size() else 44.0, 0)
		row.add_child(v)
	return row

static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
