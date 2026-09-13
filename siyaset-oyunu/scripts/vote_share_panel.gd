class_name VoteSharePanel
extends VBoxContainer
## Sağ haznede gösterilen, en son turun oy oranlarını sıralı listeleyen
## panel. eksen_projeksiyon/index.html'deki updateSelectionUI() yan liste
## satırının GDScript'e birebir yakın portu: sağa yaslı gri parti adı +
## koyu arka planlı sandalye rozeti + EN YÜKSEK partiye göre orantılı bar
## (bar genişliği 100%'e değil, lider partiye göre ölçekleniyor), barın
## üstünde her zaman okunaklı olsun diye clip-path ile ikiye bölünmüş
## (dolu kısımda beyaz, boş kısımda renkli) yüzde yazısı.

const BAR_HEIGHT := 20.0
const ROW_SEPARATION := 6.0
const NAME_LABEL_WIDTH := 78.0
const SEAT_BADGE_WIDTH := 30.0
const NAME_FONT_SIZE := 12
const PERCENT_FONT_SIZE := 11
const NAME_COLOR := Color(0.62, 0.62, 0.65) # eksen_projeksiyon: #888
## Parti liderinin (oyuncunun) adı — parti adının hemen altında, daha küçük
## ve daha soluk.
const LEADER_FONT_SIZE := 9
const LEADER_COLOR := Color(0.52, 0.52, 0.56)
const SEAT_BADGE_BG := Color(0.09, 0.09, 0.09) # eksen_projeksiyon: #111
const BAR_BG_COLOR := Color(1, 1, 1, 0.07)      # eksen_projeksiyon: var(--surface-alt) yaklaşık karşılığı

## Satırlar kaydırma kutusundan kısaysa dikey olarak ortalansın mı?
@export var center_vertically: bool = false
## Dar alanlar (sol panel) için: lider adı gösterilmez, çubuk alçak — satır
## başına daha az yer kaplar, 8 partide de liste okunur kalır.
@export var compact: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", ROW_SEPARATION)

## entries: Array of {"name": String, "color": Color, "percent": float, "seats": int} —
## BÜYÜKTEN KÜÇÜĞE sıralı olmalı.
func set_data(entries: Array) -> void:
	for child in get_children():
		child.queue_free()

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Henüz sonuç yok"
		empty_label.modulate.a = 0.6
		add_child(empty_label)
		return

	var max_percent := 0.0
	for e in entries:
		max_percent = maxf(max_percent, float(e["percent"]))
	if max_percent <= 0.0:
		max_percent = 1.0

	# Üst boşluk ("spacer"): satırlar az olduğunda (örn. tek parti) liste
	# ScrollContainer'ın en üstüne yapışmasın, DÜŞEY OLARAK ORTALANMIŞ gibi
	# görünsün diye. VBoxContainer'ın kendisi ScrollContainer içinde her
	# zaman İÇERİĞİ KADAR yükseklik alır (scroll edilebilsin diye), bu
	# yüzden Container'ın "alignment" özelliği burada işe yaramaz — bunun
	# yerine mevcut boşluğun yarısı kadar boş bir Control ekleyip satırları
	# manuel olarak aşağı itiyoruz.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 0)
	add_child(top_spacer)

	for e in entries:
		add_child(_build_row(e["name"], e["color"], e["percent"], int(e.get("seats", 0)), max_percent, "" if compact else String(e.get("leader", ""))))

	call_deferred("_apply_vertical_centering", top_spacer, entries.size())

func _apply_vertical_centering(top_spacer: Control, row_count: int) -> void:
	if not is_instance_valid(top_spacer) or row_count <= 0:
		return
	var scroll_parent := get_parent()
	# Sol paneldeki gibi başlığın hemen altından başlaması gereken listelerde
	# ortalama kapalı (center_vertically = false).
	if not center_vertically or not (scroll_parent is ScrollContainer):
		return
	var available: float = scroll_parent.size.y
	var content_height: float = row_count * BAR_HEIGHT + maxf(0.0, float(row_count - 1)) * ROW_SEPARATION
	var spacer_height: float = maxf(0.0, (available - content_height) * 0.5)
	top_spacer.custom_minimum_size = Vector2(0, spacer_height)

func _build_row(party_name: String, color: Color, percent: float, seats: int, max_percent: float, leader_name: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Parti adı ve ALTINDA parti liderinin (oyuncunun) adı.
	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(NAME_LABEL_WIDTH, 0)
	name_box.add_theme_constant_override("separation", 0)
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var name_label := Label.new()
	name_label.text = party_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	name_box.add_child(name_label)

	if leader_name != "":
		var leader_label := Label.new()
		leader_label.text = leader_name
		leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		leader_label.clip_text = true
		leader_label.add_theme_font_size_override("font_size", LEADER_FONT_SIZE)
		leader_label.add_theme_color_override("font_color", LEADER_COLOR)
		name_box.add_child(leader_label)

	row.add_child(name_box)

	var seat_badge := PanelContainer.new()
	seat_badge.custom_minimum_size = Vector2(SEAT_BADGE_WIDTH, 0)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = SEAT_BADGE_BG
	badge_style.set_content_margin_all(3)
	seat_badge.add_theme_stylebox_override("panel", badge_style)
	var seat_label := Label.new()
	seat_label.text = str(seats)
	seat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat_label.add_theme_font_size_override("font_size", PERCENT_FONT_SIZE)
	seat_label.add_theme_color_override("font_color", Color.WHITE)
	seat_badge.add_child(seat_label)
	row.add_child(seat_badge)

	var bar_bg := Panel.new()
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.custom_minimum_size = Vector2(0, BAR_HEIGHT * (0.8 if compact else 1.0))
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BAR_BG_COLOR
	bar_bg.add_theme_stylebox_override("panel", bg_style)

	var fill_width_ratio: float = clampf(percent / max_percent, 0.0, 1.0)

	var bar_fill := Panel.new()
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.anchor_right = fill_width_ratio
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	bar_fill.add_theme_stylebox_override("panel", fill_style)
	bar_bg.add_child(bar_fill)

	# eksen_projeksiyon'daki clip-path ikilisi: dolu kısımda BEYAZ, boş
	# kısımda RENKLİ yazı — yazı her zaman zeminine göre okunaklı kalır.
	var percent_text := "%%%.1f" % percent
	var label_white := Label.new()
	label_white.text = percent_text
	label_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_white.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_white.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_white.add_theme_font_size_override("font_size", PERCENT_FONT_SIZE)
	label_white.add_theme_color_override("font_color", Color.WHITE)
	label_white.clip_text = true
	bar_bg.add_child(label_white)

	row.add_child(bar_bg)
	return row
