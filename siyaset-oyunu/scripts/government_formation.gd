extends Control
## HÜKÜMET KURMA EKRANI (0.0.277, konsept C "pazarlık kartları"): görevi alan
## oyuncuda açılır; diğerleri GameScreen'de "Hükümet kuruluyor" perdesini görür.
## TEK EKRAN, adım yok:
##   - Üstte meclis NOKTA ŞERİDİ: ortakların sandalyeleri renkli, ortadaki
##     çizgi salt çoğunluk; yanda toplam ve "Çoğunluk var / yok" rozeti.
##   - Ortada PARTİ KARTLARI: dokununca ortak olur (kart kalkar, renkli
##     çerçeve alır), tekrar dokununca çıkar. Görevli parti çıkarılamaz.
##   - Altta dokuz GÖREV KARTI: dokundukça görev ortaklar arasında sırayla
##     döner; kartın alt şeridi atanan partinin rengi. Başbakanlık kimdeyse
##     ANA İKTİDAR PARTİSİ odur.
##   - Sağ altta ortakların PUAN PAYLARI ve "Teklifi sun".
## Arayüz tamamen kodla kurulur (sahne yalnız kök düğüm). Ölçüler konseptin
## 1280×720 ekranındaki pikselleri (konseptler/hukumet_kurma_konseptleri.html).

const CREAM := Color("FFF6E0")
const MINT := Color("D8EFE2")
const MUTED2 := Color("9A9082")
const FELT_INK := Color("0B3A28")
const CARD_W := 190.0
const CARD_H := 184.0
## Ortak kartın kalkma payı ve el şeridinin yüksekliği.
const CARD_LIFT := 14.0
const HAND_H := 196.0
const HAND_GAP := 16.0

## Görev simgeleri (24×24 çizgi SVG; beyaz çizilip boyanır).
const ICON_PATHS := {
	"pm": '<path d="M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.4 6.7 19.4l1.2-6L3.4 9.3l6-.7z"/>',
	"deputy_pm": '<path d="M5 15l7-7 7 7"/><path d="M5 20l7-7 7 7"/>',
	"ministry_interior": '<path d="M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7z"/><path d="M9 12l2 2 4-4"/>',
	"ministry_foreign": '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>',
	"ministry_finance": '<circle cx="12" cy="12" r="9"/><path d="M15 9h-4a2 2 0 000 4h2a2 2 0 010 4H9M12 6v2M12 17v1"/>',
	"ministry_justice": '<path d="M12 4v16M7 20h10M5 8h14"/><path d="M5 8l-3 6a3 3 0 006 0zM19 8l-3 6a3 3 0 006 0z"/>',
	"ministry_education": '<path d="M3 9l9-5 9 5-9 5z"/><path d="M7 11v5c3 2 7 2 10 0v-5"/>',
	"ministry_health": '<path d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6z"/>',
	"ministry_defense": '<path d="M12 3l8 3v6c0 4-3 7-8 9-5-2-8-5-8-9V6z"/><path d="M12 7v10M8 11h8"/>',
	"clock": '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6"/>',
}
## Görev kartındaki kısa ad (dar kart).
const SHORT_TITLES := {
	"pm": "Başbakanlık", "deputy_pm": "Başbakan Yardımcılığı", "ministry_interior": "İçişleri",
	"ministry_foreign": "Dışişleri", "ministry_finance": "Maliye", "ministry_justice": "Adalet",
	"ministry_education": "Milli Eğitim", "ministry_health": "Sağlık", "ministry_defense": "Milli Savunma",
}

## Hükümete girecek partiler (peer_id); ilki her zaman görevli parti.
var _partners: Array = []
## post_id -> peer_id
var _assignments: Dictionary = {}

var _timer_label: Label
var _tries_box: HBoxContainer
var _seat_total: Label
var _seat_of: Label
var _majority_tag: Label
var _strip: SeatStrip
var _hand: HBoxContainer
var _slots: HBoxContainer
var _shares: VBoxContainer
var _propose_button: Button
var _last_shown_second: int = -1
var _icon_cache: Dictionary = {}

func _ready() -> void:
	AudioManager.play_game_music()
	add_child(TableSurface.felt())
	_partners = [PartyManager.party_of(multiplayer.get_unique_id())]
	for post_id in GovernmentPresets.post_ids():
		_assignments[post_id] = _partners[0]
	_build()
	GovernmentManager.phase_changed.connect(_on_phase_changed)
	_refresh()

## Görev artık bizde değilse (teklif reddedilip sıra devrettiyse) burada
## kalmanın anlamı yok.
func _on_phase_changed() -> void:
	if GovernmentManager.phase != GovernmentManager.Phase.FORMING or not GovernmentManager.is_my_mandate():
		SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")

func _process(_delta: float) -> void:
	var second := int(ceil(GovernmentManager.phase_seconds_left()))
	if second != _last_shown_second:
		_last_shown_second = second
		_timer_label.text = GameRules.format_seconds(GovernmentManager.phase_seconds_left())

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
	column.add_child(_build_track())
	_hand = HBoxContainer.new()
	_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand.add_theme_constant_override("separation", int(HAND_GAP))
	_hand.custom_minimum_size.y = HAND_H
	column.add_child(_hand)
	var lower := HBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_theme_constant_override("separation", 16)
	column.add_child(lower)
	lower.add_child(_build_cabinet())
	lower.add_child(_build_shares())

## Başlık, teklif hakları ve süre.
func _build_top() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 52
	row.add_theme_constant_override("separation", 14)
	var title := UiTheme.mono_label(L.t("Hükümeti Kur"), 34, CREAM, true)
	title.add_theme_color_override("font_shadow_color", FELT_INK)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_tries_box = HBoxContainer.new()
	_tries_box.add_theme_constant_override("separation", 6)
	_tries_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tries_box)
	var pill := PanelContainer.new()
	var pill_style := BoardBox.new()
	pill_style.fill = UiTheme.PANEL
	pill_style.set_radius(14)
	pill_style.lips = [[4.0, UiTheme.EDGE]]
	pill_style.content_margin_left = 14
	pill_style.content_margin_right = 14
	pill_style.content_margin_top = 6
	pill_style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", pill_style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pill)
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 8)
	pill.add_child(pill_row)
	pill_row.add_child(_icon("clock", 20, UiTheme.TEXT_ON_GOLD, 2.6))
	_timer_label = UiTheme.mono_label("", 22, UiTheme.TEXT_ON_GOLD, true)
	pill_row.add_child(_timer_label)
	# Sağ üstteki Menü düğmesine (SettingsOverlay) yer.
	var menu_gap := Control.new()
	menu_gap.custom_minimum_size.x = 120
	row.add_child(menu_gap)
	return row

## Meclis nokta şeridi.
func _build_track() -> Control:
	var board := _board(14, 20)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	board.add_child(row)
	var numbers := VBoxContainer.new()
	numbers.alignment = BoxContainer.ALIGNMENT_CENTER
	numbers.add_theme_constant_override("separation", 0)
	numbers.custom_minimum_size.x = 64
	row.add_child(numbers)
	_seat_total = UiTheme.mono_label("", 40, UiTheme.TEXT, true)
	numbers.add_child(_seat_total)
	_seat_of = _small("", UiTheme.TEXT_MUTED, 11)
	numbers.add_child(_seat_of)
	_strip = SeatStrip.new()
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip.custom_minimum_size.y = 96
	row.add_child(_strip)
	_majority_tag = _tag("", UiTheme.GREEN_DARK, Color.WHITE)
	_majority_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_majority_tag)
	return board

func _build_cabinet() -> Control:
	var board := _board(14, 16)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	board.add_child(box)
	box.add_child(_section(L.t("Kabine"), L.t("göreve dokun: ortaklar arasında sırayla döner")))
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", 9)
	_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_slots)
	return board

func _build_shares() -> Control:
	var board := _board(16, 16)
	board.custom_minimum_size.x = 250
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	board.add_child(box)
	box.add_child(_section(L.t("Paylar")))
	_shares = VBoxContainer.new()
	_shares.add_theme_constant_override("separation", 10)
	_shares.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_shares)
	_propose_button = Button.new()
	_propose_button.text = L.t("Teklifi sun")
	_propose_button.custom_minimum_size.y = 46
	_propose_button.add_theme_font_size_override("font_size", 18)
	UiSkin.skin_color_button(_propose_button, UiTheme.GREEN_DARK)
	_propose_button.pressed.connect(_on_propose_pressed)
	box.add_child(_propose_button)
	return board

# --- Tazeleme -----------------------------------------------------------------

func _rebuild() -> void:
	_refresh()

func _refresh() -> void:
	var seats := _coalition_seats()
	var total := GovernmentManager.total_seats()
	var has_majority := seats * 2 > total
	_seat_total.text = str(seats)
	_seat_of.text = "/ %d" % total
	_majority_tag.text = L.t("Çoğunluk var") if has_majority else L.t("Çoğunluk yok")
	_majority_tag.add_theme_stylebox_override("normal", _tag_style(UiTheme.GREEN_DARK if has_majority else Color("F3D7D2"),
		UiTheme.GREEN_DARK.darkened(0.3) if has_majority else Color(0, 0, 0, 0)))
	_majority_tag.add_theme_color_override("font_color", Color.WHITE if has_majority else UiTheme.CRISIS)
	_refresh_tries()
	_refresh_strip(total)
	_refresh_hand()
	_refresh_slots()
	_refresh_shares()

func _coalition_seats() -> int:
	var seats := 0
	for peer_id in _partners:
		seats += GovernmentManager.seats_of(peer_id)
	return seats

func _refresh_tries() -> void:
	_clear(_tries_box)
	_tries_box.add_child(_small(L.t("Teklif hakkı"), MINT, 13))
	var left := GovernmentManager.attempts_left()
	for i in GovernmentManager.MAX_ATTEMPTS:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := BoardBox.new()
		style.set_radius(7)
		if i < left:
			style.fill = UiTheme.GOLD
			style.lips = [[2.0, UiTheme.GOLD_DIM]]
		else:
			style.fill = Color(1, 0.98, 0.94, 0.2)
		dot.add_theme_stylebox_override("panel", style)
		_tries_box.add_child(dot)

## Sandalyeler: önce ortaklar (seçilme sırasıyla), sonra diğerleri boş yuva.
func _refresh_strip(total: int) -> void:
	var colors: Array = []
	for peer_id in _partners:
		var color := _party_color(peer_id)
		for i in GovernmentManager.seats_of(peer_id):
			colors.append(color)
	while colors.size() < total:
		colors.append(UiTheme.SLOT)
	_strip.colors = colors
	_strip.majority = total / 2 + 1
	_strip.label = L.t("çoğunluk %d") % (total / 2 + 1)
	_strip.queue_redraw()

func _hand_order() -> Array:
	var ids: Array = GovernmentManager.seated_party_ids()
	ids.sort_custom(func(a, b): return GovernmentManager.seats_of(a) > GovernmentManager.seats_of(b))
	return ids

func _refresh_hand() -> void:
	_clear(_hand)
	var ids := _hand_order()
	var available := 1236.0 - HAND_GAP * float(maxi(0, ids.size() - 1))
	var width := minf(CARD_W, available / float(maxi(1, ids.size())))
	for peer_id in ids:
		_hand.add_child(_party_card(int(peer_id), width))

## PARTİ KARTI: renkli bant, bandın üstüne oturan pul, ad, sandalye ve lider.
func _party_card(peer_id: int, width: float) -> Control:
	var party: Dictionary = PartyManager.data_of(peer_id)
	var color := _party_color(peer_id)
	var is_mandate: bool = peer_id == _partners[0]
	var is_in: bool = _partners.has(peer_id)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(width, HAND_H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	card.position = Vector2(0, HAND_H - CARD_H - (CARD_LIFT if is_in else 0.0))
	card.size = Vector2(width, CARD_H)
	if not is_mandate:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.pressed.connect(_on_partner_toggled.bind(peer_id))
	slot.add_child(card)
	# Pasif kartın rengi solgun (konsept: saturate .55).
	var band_color := color if is_in else color.lerp(Color(color.get_luminance(), color.get_luminance(), color.get_luminance()), 0.45)
	var face := BoardBox.new()
	face.fill = UiTheme.PANEL_DARK
	face.set_radius(16)
	face.lips = [[5.0, color.lerp(Color.BLACK, 0.4) if is_in else UiTheme.CARD_LIP]]
	face.shadow_color = Color(0, 0, 0, 0.3 if is_in else 0.25)
	face.shadow_offset = Vector2(0, 16 if is_in else 10)
	face.shadow_size = 11 if is_in else 8
	card.add_child(_layer(face, Rect2(0, 0, width, CARD_H)))
	var band := BoardBox.new()
	band.fill = band_color
	band.radius_tl = 16
	band.radius_tr = 16
	band.radius_bl = 0
	band.radius_br = 0
	card.add_child(_layer(band, Rect2(0, 0, width, 54)))
	var ring := BoardBox.new()
	ring.draw_fill = false
	ring.set_radius(16)
	ring.rings = [[0.0, 4.0 if is_in else 2.0, color if is_in else UiTheme.PANEL_LIGHT]]
	card.add_child(_layer(ring, Rect2(0, 0, width, CARD_H)))
	# Pulun çevresinde krem halka.
	var halo := BoardBox.new()
	halo.fill = UiTheme.PANEL_DARK
	halo.set_radius(35)
	card.add_child(_layer(halo, Rect2(width * 0.5 - 35, 16, 70, 70)))
	var pawn := PartyBadge.build(party, Vector2(62, 62), 128)
	pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pawn.position = Vector2(width * 0.5 - 31, 20)
	card.add_child(pawn)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.position = Vector2(8, 92)
	texts.size = Vector2(width - 16, CARD_H - 100)
	texts.add_theme_constant_override("separation", 2)
	card.add_child(texts)
	var name_label := UiTheme.mono_label(String(party.get("name", "?")), 19, UiTheme.TEXT, true)
	var seats_label := UiTheme.mono_label(str(GovernmentManager.seats_of(peer_id)), 30, UiTheme.TEXT, true)
	var leader_label := _small(PoliticianPresets.display_name(peer_id), UiTheme.TEXT_MUTED, 12)
	for label in [name_label, seats_label, leader_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(label)
	if is_in:
		var corner := _tag(L.t("Görevli") if is_mandate else L.t("Ortak"),
			UiTheme.TEAL if is_mandate else UiTheme.GREEN_DARK, Color.WHITE)
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(corner)
		corner.reset_size()
		corner.position = Vector2(width - 10 - corner.get_combined_minimum_size().x, 10)
	return slot

## GÖREV KARTLARI: simge, kısa ad, atanan partinin pulu, puan, alt renk şeridi.
func _refresh_slots() -> void:
	_clear(_slots)
	for post_id in GovernmentPresets.post_ids():
		var peer_id := int(_assignments.get(post_id, _partners[0]))
		var color := _party_color(peer_id)
		var is_pm: bool = post_id == GovernmentPresets.POST_PM
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.clip_contents = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = 1.0
		button.custom_minimum_size.x = 1
		var face := BoardBox.new()
		face.set_radius(12)
		if is_pm:
			face.fill = Color("FFF4D6")
			face.fill_bottom = Color("FDEEC4")
			face.rings = [[0.0, 3.0, UiTheme.GOLD]]
			face.lips = [[4.0, UiTheme.GOLD_DIM]]
		else:
			face.fill = UiTheme.PANEL_DARK
			face.rings = [[0.0, 2.0, UiTheme.PANEL_LIGHT]]
			face.lips = [[4.0, UiTheme.CARD_LIP]]
		for state in ["normal", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, face)
		var hover := face.copy()
		hover.fill = face.fill.lightened(0.25)
		button.add_theme_stylebox_override("hover", hover)
		var pressed := face.copy()
		pressed.offset_y = 2
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("hover_pressed", pressed)
		if _partners.size() > 1:
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_post_pressed.bind(post_id))
		_slots.add_child(button)
		var strip := BoardBox.new()
		strip.fill = color
		strip.radius_tl = 0
		strip.radius_tr = 0
		strip.radius_bl = 12
		strip.radius_br = 12
		var strip_panel := Panel.new()
		strip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip_panel.add_theme_stylebox_override("panel", strip)
		strip_panel.anchor_left = 0
		strip_panel.anchor_right = 1
		strip_panel.anchor_top = 1
		strip_panel.anchor_bottom = 1
		strip_panel.offset_top = -8
		button.add_child(strip_panel)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 4
		box.offset_right = -4
		box.offset_top = 10
		box.offset_bottom = -12
		box.add_theme_constant_override("separation", 6)
		button.add_child(box)
		var icon := _icon(post_id, 26, UiTheme.GOLD_DIM if is_pm else UiTheme.TEAL, 2.2)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(icon)
		var title := UiTheme.mono_label(L.t(String(SHORT_TITLES.get(post_id, GovernmentPresets.post_title(post_id)))), 13, UiTheme.TEXT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(1, 32)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(title)
		var pawn := PartyBadge.build(PartyManager.data_of(peer_id), Vector2(32, 32), 64)
		pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pawn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(pawn)
		var points := _small("+%d" % GovernmentPresets.post_points(post_id), UiTheme.GOLD_DIM, 11)
		points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		points.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(points)

func _refresh_shares() -> void:
	_clear(_shares)
	var points: Dictionary = {}
	for post_id in _assignments.keys():
		var peer_id := int(_assignments[post_id])
		points[peer_id] = int(points.get(peer_id, 0)) + GovernmentPresets.post_points(post_id)
	for peer_id in _partners:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_shares.add_child(row)
		var pawn := PartyBadge.build(PartyManager.data_of(peer_id), Vector2(26, 26), 64)
		pawn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pawn)
		var name_label := UiTheme.mono_label(String(PartyManager.data_of(peer_id).get("name", "?")), 15, UiTheme.TEXT, true)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size.x = 1
		row.add_child(name_label)
		row.add_child(UiTheme.mono_label(str(int(points.get(peer_id, 0))), 20, UiTheme.TEXT, true))

# --- Etkileşim ------------------------------------------------------------------

func _on_partner_toggled(peer_id: int) -> void:
	if peer_id == _partners[0]:
		return
	if _partners.has(peer_id):
		_partners.erase(peer_id)
		# Çıkan ortağın görevleri görevli partiye düşer.
		for post_id in _assignments.keys():
			if int(_assignments[post_id]) == peer_id:
				_assignments[post_id] = _partners[0]
	else:
		_partners.append(peer_id)
	_refresh()

func _on_post_pressed(post_id: String) -> void:
	if _partners.size() < 2:
		return
	var index := _partners.find(int(_assignments.get(post_id, _partners[0])))
	_assignments[post_id] = _partners[(index + 1) % _partners.size()]
	_refresh_slots()
	_refresh_shares()

func _on_propose_pressed() -> void:
	_propose_button.disabled = true
	GovernmentManager.submit_government_proposal(_assignments)
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")

# --- Parçalar -------------------------------------------------------------------

func _party_color(peer_id: int) -> Color:
	return PartyManager.data_of(peer_id).get("bg_color", UiTheme.PANEL_LIGHT)

## Krem pano (UiSkin.board); kenar payları verilen ölçüde.
func _board(pad_y: float, pad_x: float) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiSkin.board()
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	style.dot_radius = 0.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

## Bölüm başlığı (konsept .sech): hardal nokta + başlık, sağda küçük not.
func _section(title: String, note: String = "") -> Control:
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
	if note != "":
		var small := _small(note, MUTED2, 12)
		small.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(small)
	return row

func _small(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.body_black())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _tag_style(bg: Color, lip: Color) -> BoardBox:
	var style := BoardBox.new()
	style.fill = bg
	style.set_radius(8)
	if lip.a > 0.0:
		style.lips = [[2.0, lip]]
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _tag(text: String, bg: Color, fg: Color) -> Label:
	var label := UiTheme.mono_label(text, 13, fg, true)
	label.add_theme_stylebox_override("normal", _tag_style(bg, bg.darkened(0.3)))
	return label

## Verilen kutuyu çizen, tıklamayı geçiren katman.
func _layer(style: StyleBox, rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	panel.position = rect.position
	panel.size = rect.size
	return panel

## Çizgi simgesi (ICON_PATHS), tam boyda rasterleşir ve boyanır.
func _icon(key: String, side: int, color: Color, stroke: float) -> TextureRect:
	var cache_key := "%s@%d@%.1f" % [key, side, stroke]
	if not _icon_cache.has(cache_key):
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#ffffff" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [stroke, String(ICON_PATHS.get(key, ""))]
		var image := Image.new()
		image.load_svg_from_string(svg, float(side) * 2.0 / 24.0)
		image.generate_mipmaps()
		_icon_cache[cache_key] = ImageTexture.create_from_image(image)
	var rect := TextureRect.new()
	rect.texture = _icon_cache[cache_key]
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

## MECLİS NOKTA ŞERİDİ: sandalyeler sütun sütun soldan sağa; çoğunluk
## sandalyesinin sütununda dikey çizgi ve üstünde etiket.
class SeatStrip extends Control:
	var colors: Array = []
	var majority: int = 0
	var label: String = ""
	const GAP := 3.0
	const LABEL_H := 16.0

	func _draw() -> void:
		var n := colors.size()
		if n == 0:
			return
		var area := Vector2(size.x, size.y - LABEL_H)
		var rows := clampi(int(round(sqrt(float(n) * area.y / maxf(1.0, area.x)))), 3, 10)
		var cols := int(ceil(float(n) / rows))
		var dot := minf((area.x - GAP * (cols - 1)) / cols, (area.y - GAP * (rows - 1)) / rows)
		var step := dot + GAP
		var width := step * cols - GAP
		var height := step * rows - GAP
		var origin := Vector2((size.x - width) * 0.5, LABEL_H + (area.y - height) * 0.5)
		for i in n:
			var p := origin + Vector2(float(i / rows) * step, float(i % rows) * step) + Vector2(dot, dot) * 0.5
			draw_circle(p, dot * 0.5, colors[i], true, -1.0, true)
		if majority > 0:
			var x := origin.x + float((majority - 1) / rows) * step - GAP * 0.5
			draw_line(Vector2(x, origin.y - 8), Vector2(x, origin.y + height + 8), UiTheme.INK, 3.0, true)
			var font := UiTheme.body_black()
			var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2(x - text_w * 0.5, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_MUTED)
