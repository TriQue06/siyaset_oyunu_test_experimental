class_name ProvinceActions
extends PanelContainer
## İL MENÜSÜ (0.0.301, konsept A "Tek ekran + 4'lü pul ızgarası", bkz.
## konseptler/il_menusu_ve_sira_konseptleri.html): haritada bir ile dokununca
## tıklanan yerin yanında SABİT BOYUTLU (320 × 430) bağlam menüsü açılır.
## Konseptteki ölçüler oyun birimine bire bir aktarılır; hiçbir sayfada
## kaydırma yoktur.
##   ANA EKRAN: teşkilat satırı (seviye pulları + doğrudan KUR / GELİŞTİR,
##     ayrı onay sayfası yok), altında MİTİNG ve YATIRIM, en altta İL BİLGİSİ.
##   MİTİNG: üstte miting boyu, altta hedef gruplar (4 sütun, karşıt grup
##     altta; yalnız simge ve ildeki yüzde), en altta MİTİNG YAP. Ek yazı yok;
##     yapılamıyorsa düğme söner, basınca nedeni kısa bildirim olarak çıkar.
##   YATIRIM: aynı düzende yatırım boyu ve YATIRIM YAP.
## Üstte GERİ / İLERİ / X: tarayıcı gibi sayfalar arasında gezinir.
## Kurallar ve sınırlar CardManager'da doğrulanır.

signal closed
signal info_requested(province_id: String)
signal toast_requested(text: String)

## Menünün sabit boyutu (konsept .menu).
const MENU_SIZE := Vector2(320, 430)
const WIDTH := 320.0
var panel_width := WIDTH
const TIER_NAMES := ["KÜÇÜK", "ORTA", "BÜYÜK"]

# Konsept renkleri (:root).
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
const C_GHOST_INK := Color("5d6b6b")
const C_ORG := Color("2569cf")
const C_ORG_LIP := Color("174a96")
const C_MIT := Color("d93636")
const C_MIT2 := Color("a12424")
const C_INV := Color("2e9e52")
const C_GO := Color("1f8a4c")
const C_DIM := Color("b9ad95")
## Boy segmenti: seçili değil (açık) ve seçili (dolu) renkler, sayfaya göre.
const SEG := {
	"miting": {"off": Color("f1c9c9"), "off_ink": Color("7b2323"), "off_lip": Color("d79c9c"),
		"on": Color("d93636"), "on_lip": Color("a12424"), "on_cost": Color("ffe1a0")},
	"invest": {"off": Color("cfe9d6"), "off_ink": Color("1d5a33"), "off_lip": Color("9fcfae"),
		"on": Color("2e9e52"), "on_lip": Color("1d6b37"), "on_cost": Color("e4ffd0")},
}

var province_id := ""
var tab := ""
var _miting_tier := CardManager.DEFAULT_TIER
var _focus: Array = []
## Karalama kararı: -1 = sakla (karalama ayrı kart, bkz. 0.0.237).
var _smear := -1
var _invest_tier := CardManager.DEFAULT_TIER
var _sent_version := -1
var _body: VBoxContainer
## İLERİ ile dönülecek sayfa (GERİ'ye basınca dolar, yeni sayfa açınca silinir).
var _forward_page := ""
var max_height := MENU_SIZE.y

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 96
	# Konsept .menu: krem karton, 4 px içeride 2 px deniz yeşili çizgi,
	# altta karton kalınlığı ve gölge.
	var style := BoardBox.new()
	style.fill = C_BOARD
	style.fill_bottom = C_BOARD2
	style.set_radius(18)
	style.rings = [[4.0, 2.0, C_TEAL]]
	style.lips = [[8.0, C_EDGE]]
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_offset = Vector2(0, 18)
	style.shadow_size = 13
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = MENU_SIZE
	size = MENU_SIZE
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 9)
	add_child(_body)
	hide()

## Menü tıklanan noktanın yanına oturur (sağa sığmazsa soluna), bounds içinde kalır.
func place_at(point: Vector2, bounds: Rect2) -> void:
	var pos := point + Vector2(18, -MENU_SIZE.y * 0.4)
	if pos.x + MENU_SIZE.x > bounds.end.x:
		pos.x = point.x - 18 - MENU_SIZE.x
	pos.x = clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - MENU_SIZE.x))
	pos.y = clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - MENU_SIZE.y))
	position = pos.round()

## Eski çağrılar için (önizleme betikleri): menü dikdörtgenin içine oturur.
func set_panel_rect(rect: Rect2) -> void:
	place_at(rect.position, rect)

func open(p_province: String) -> void:
	var fresh := p_province != province_id or not visible
	if p_province != province_id:
		_reset_miting()
		_invest_tier = CardManager.DEFAULT_TIER
	if fresh:
		tab = ""
		_forward_page = ""
	province_id = p_province
	size = MENU_SIZE
	var was_visible := visible
	show()
	refresh()
	if not was_visible:
		pivot_offset = MENU_SIZE * 0.5
		scale = Vector2(0.85, 0.85)
		modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 1.0, 0.12)

func _reset_miting() -> void:
	_miting_tier = CardManager.DEFAULT_TIER
	_focus = []
	_smear = -1

func close() -> void:
	hide()
	province_id = ""
	tab = ""
	_forward_page = ""
	closed.emit()

## Sayfa aç (ana menüden): ileri geçmişi silinir.
func open_page(page: String) -> void:
	tab = page
	_forward_page = ""
	refresh()

## GERİ: ayrıntıdan ana menüye (miting hazırlığı bırakılır, hak ve para gitmez).
func go_back() -> void:
	if tab == "":
		return
	_forward_page = tab
	tab = ""
	refresh()

## İLERİ: GERİ ile çıkılan sayfaya dön (seçimler korunur).
func go_forward() -> void:
	if _forward_page == "" or not _page_available(_forward_page):
		return
	tab = _forward_page
	_forward_page = ""
	refresh()

func refresh() -> void:
	if province_id == "" or not visible:
		return
	if tab != "" and not _page_available(tab):
		tab = ""
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_build_nav()
	_build_header()
	match tab:
		"miting":
			_build_miting()
		"invest":
			_build_invest()
		_:
			_build_menu()
	size = MENU_SIZE

## Hangi sayfa açılabilir: miting teşkilatlı ilde (bağımsız her ilde), yatırım
## yalnız hükümet partisinin genel başkanına.
func _page_available(page: String) -> bool:
	var me := multiplayer.get_unique_id()
	var level := CardManager.organization_level(province_id, me)
	if PartyManager.is_independent(me):
		return page == "miting"
	match page:
		"miting":
			return level > 0
		"invest":
			return level > 0 and CardManager.is_government_party(me) and not CardManager.is_party_member(me)
	return false

# --- Yapı taşları (konsept sınıfları) ------------------------------------------

static func _font_display() -> Font:
	return UiTheme.mono(true)

static func _font_body() -> Font:
	return UiTheme.mono_regular()

static func _text(text: String, font: Font, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Konsept düğmelerinin yüzü: dolgu, alt kalınlık (lip), üstte parlaklık.
## pressed: yüz kalınlık kadar iner.
static func _face(fill: Color, lip: Color, radius: float, lip_px: float, state: String, highlight: bool = true) -> BoardBox:
	var b := BoardBox.new()
	b.fill = fill
	b.set_radius(radius)
	if highlight:
		b.highlight_size = 3.0
		b.highlight_color = Color(1, 1, 1, 0.3)
	b.lips = [[lip_px, lip]]
	match state:
		"hover":
			b.fill = fill.lightened(0.06)
		"pressed":
			b.offset_y = lip_px - 1.0
			b.lips = [[1.0, lip]]
	return b

static func _skin(button: Button, fill: Color, lip: Color, radius: float, lip_px: float, highlight: bool = true) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _face(fill, lip, radius, lip_px, state, highlight))
	button.add_theme_stylebox_override("hover_pressed", _face(fill, lip, radius, lip_px, "pressed", highlight))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func _button() -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button

## İki satırlı yazı (başlık + küçük alt satır) düğmenin ortasında.
static func _two_lines(button: Button, title: String, title_px: int, title_color: Color, sub: String, sub_px: float,
		sub_color: Color, shadow: bool) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var head := _text(title, _font_display(), title_px, title_color)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if shadow:
		head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.25))
		head.add_theme_constant_override("shadow_offset_x", 0)
		head.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(head)
	if sub != "":
		var small := _text(sub, _font_body(), int(round(sub_px)), sub_color)
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(small)
	# Basılınca yazı da yüzle birlikte iner.
	button.button_down.connect(func(): box.position.y = 4.0)
	button.button_up.connect(func(): box.position.y = 0.0)

## Konsept .big: renkli kalın düğme (dim: soluk, basılınca nedeni bildirilir).
func _big(title: String, sub: String, color: Color, min_h: float, dim: bool, action: Callable) -> Button:
	var button := _button()
	button.custom_minimum_size = Vector2(0, min_h)
	var fill := C_DIM if dim else color
	_skin(button, fill, fill.lerp(Color.BLACK, 0.4), 14, 5)
	_two_lines(button, title, 19, Color.WHITE, sub, 11.5, Color(1, 1, 1, 0.9), true)
	button.pressed.connect(action)
	return button

## Konsept .sec: küçük büyük harf başlık + sağa uzanan çizgi (+ isteğe bağlı ek).
func _sec(title: String, extra: Control = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _text(title.to_upper(), _font_body(), 10, C_MUTED)
	row.add_child(label)
	if extra != null:
		row.add_child(extra)
	var rule := ColorRect.new()
	rule.color = C_LINE
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)
	_body.add_child(row)

## Küçük kare pul (seviye ve hedef sayısı göstergesi).
static func _pip(side: float, radius: float, on: bool, on_color: Color, on_lip: Color) -> Control:
	var pip := Panel.new()
	pip.custom_minimum_size = Vector2(side, side)
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := BoardBox.new()
	b.set_radius(radius)
	if on:
		b.fill = on_color
		b.highlight_size = 2.0
		b.highlight_color = Color(1, 1, 1, 0.35)
		b.lips = [[2.0, on_lip]]
	else:
		b.fill = C_SLOT
		b.highlight_size = 2.0
		b.highlight_color = Color(0, 0, 0, 0.08)
	pip.add_theme_stylebox_override("panel", b)
	return pip

static func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

# --- Gezinti ve başlık -------------------------------------------------------------

func _build_nav() -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	_body.add_child(nav)
	nav.add_child(_nav_button(L.t("GERİ"), tab != "", go_back))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(gap)
	nav.add_child(_nav_button(L.t("İLERİ"), _forward_page != "" and _page_available(_forward_page), go_forward))
	nav.add_child(_nav_button("X", true, close))

## Konsept .nav b: deniz yeşili küçük düğme; kullanılamıyorsa soluk.
func _nav_button(text: String, enabled: bool, action: Callable) -> Button:
	var button := _button()
	button.text = text
	button.add_theme_font_override("font", _font_display())
	button.add_theme_font_size_override("font_size", 13)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, Color.WHITE)
	_skin(button, C_TEAL, C_TEAL2, 9, 3, false)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as BoardBox
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 8
		box.content_margin_bottom = 9
	button.disabled = not enabled
	if not enabled:
		button.modulate.a = 0.45
	button.pressed.connect(action)
	return button

func _build_header() -> void:
	# Konsept: alt satır başlığa yapışık (margin-top: -4px).
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(head)
	var title := _text(ElectionNightSim.province_name(province_id), _font_display(), 21, C_INK)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	head.add_child(_text(L.t("%d vekil") % CardManager.province_seat_count(province_id), _font_body(), 11, C_MUTED))

# --- Ana ekran ----------------------------------------------------------------------

func _build_menu() -> void:
	var me := multiplayer.get_unique_id()
	var limit := CardManager.action_limit(me)
	if not PartyManager.is_independent(me):
		_body.add_child(_org_row(me))
	if _page_available("miting"):
		_body.add_child(_big(L.t("MİTİNG"), L.t("bu sıra %d/%d") % [limit - CardManager.miting_count(me), limit], C_MIT, 70, false,
			func(): open_page("miting")))
	if _page_available("invest"):
		_body.add_child(_big(L.t("YATIRIM"), L.t("bu sıra %d/%d") % [limit - CardManager.invest_count(me), limit], C_INV, 70, false,
			func(): open_page("invest")))
	_body.add_child(_spacer())
	var info := _button()
	info.custom_minimum_size = Vector2(0, 38)
	info.text = L.t("İL BİLGİSİ")
	info.add_theme_font_override("font", _font_display())
	info.add_theme_font_size_override("font_size", 14)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		info.add_theme_color_override(key, C_GHOST_INK)
	_skin(info, C_SLOT, C_LIP, 12, 3, false)
	info.pressed.connect(func(): info_requested.emit(province_id))
	_body.add_child(info)

## Konsept .orgrow: seviye pulları, "Teşkilat / n. seviye" ve doğrudan
## KUR / GELİŞTİR düğmesi (bedeli altında). En üst seviyede düğme yok.
func _org_row(me: int) -> Control:
	var level := CardManager.organization_level(province_id, me)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := BoardBox.new()
	style.fill = C_CARD
	style.set_radius(14)
	style.rings = [[0.0, 1.5, C_LINE]]
	style.lips = [[3.0, C_LIP]]
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in GameRules.ORG_MAX_LEVEL:
		pips.add_child(_pip(14, 5, i < level, C_ORG, C_ORG_LIP))
	row.add_child(pips)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(_text(L.t("Teşkilat"), _font_display(), 15, C_INK))
	texts.add_child(_text(_level_name(level), _font_body(), 10, C_MUTED))
	row.add_child(texts)
	if level >= GameRules.ORG_MAX_LEVEL:
		return card
	var cost := CardManager.org_cost_for(me, province_id)
	var ok := CardManager.can_build_organization(me, province_id)
	var go := _button()
	go.custom_minimum_size = Vector2(88, 44)
	var fill := C_ORG if ok else C_DIM
	_skin(go, fill, fill.lerp(Color.BLACK, 0.4), 11, 5)
	_two_lines(go, L.t("KUR") if level == 0 else L.t("GELİŞTİR"), 14, Color.WHITE, GameRules.cost_text(cost), 11.5, Color(1, 1, 1, 0.9), true)
	go.pressed.connect(func():
		if not CardManager.can_build_organization(me, province_id):
			toast_requested.emit(_org_block_reason(me, cost))
			return
		if not _first_send():
			return
		CardManager.build_organization(province_id)
		toast_requested.emit(L.t("%s teşkilatı: %s") % [ElectionNightSim.province_name(province_id), _level_name(level + 1)]))
	row.add_child(go)
	return card

func _org_block_reason(me: int, cost: float) -> String:
	if CardManager.is_party_member(me):
		return L.t("Teşkilatı partinin genel başkanı kurar.")
	if not CardManager.can_choose_main_action(me):
		return L.t("Sıra sende değil.")
	if CardManager.funds_of(me) < cost:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(cost)
	return L.t("Şu an teşkilat kurulamaz.")

# --- Boy segmenti ve grup pulları ------------------------------------------------

## Konsept .seg: üç boy (ad + bedel); seçili dolu renkte.
func _segment(page: String, selected: int, costs: Array, on_pick: Callable) -> Control:
	var palette: Dictionary = SEG[page]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	for i in costs.size():
		var on := i == selected
		var button := _button()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 44)
		if on:
			_skin(button, palette["on"], palette["on_lip"], 11, 3)
		else:
			_skin(button, palette["off"], palette["off_lip"], 11, 3, false)
		_two_lines(button, L.t(TIER_NAMES[i]), 14, Color.WHITE if on else palette["off_ink"], String(costs[i]), 11,
			palette["on_cost"] if on else palette["off_ink"], false)
		button.pressed.connect(on_pick.bind(i))
		grid.add_child(button)
	return grid

## Konsept .gtok (4'lü ızgara): grup simgesi üstte, ildeki yüzde altta.
## Seçili: grubun renginde dolu, beyaz simge, altın halka. Dolu: soluk.
func _group_token(group: String, percent: int, selected: bool, full: bool) -> Button:
	var g := VoterGroups.color(group)
	var button := _button()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 52)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var b: BoardBox
		if selected:
			b = _face(g, g.lerp(Color.BLACK, 0.4), 11, 3, state)
			b.rings = [[0.0, 2.5, C_MUS]]
		else:
			b = _face(g.lerp(C_CARD, 0.7), g.lerp(C_LIP, 0.55), 11, 3, state, false)
		button.add_theme_stylebox_override(state, b)
	button.add_theme_stylebox_override("hover_pressed", button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var icon := VoterGroupIcon.make(group, 24.0, true)
	icon.ink_override = Color.WHITE if selected else g.lerp(C_INK, 0.45)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var pct := _text("%%%d" % percent, _font_body(), 12, Color.WHITE if selected else C_INK)
	pct.modulate.a = 0.85
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pct)
	button.button_down.connect(func(): box.position.y = 2.0)
	button.button_up.connect(func(): box.position.y = 0.0)
	if full:
		button.modulate.a = 0.45
	return button

# --- MİTİNG ------------------------------------------------------------------------

func _build_miting() -> void:
	var me := multiplayer.get_unique_id()
	_sec(L.t("Miting boyu"))
	var costs: Array = []
	for t in CardManager.MITING_TIERS.size():
		costs.append(GameRules.cost_text(CardManager.miting_tier_cost(t)))
	_body.add_child(_segment("miting", _miting_tier, costs, func(t: int):
		_miting_tier = t
		refresh()))
	var slots := CardManager.miting_focus_slots(me, province_id)
	var counter := HBoxContainer.new()
	counter.add_theme_constant_override("separation", 4)
	counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 0.0.302: dolu kutucuk seçilen grubun renginde.
	for i in slots:
		var group_color := VoterGroups.color(String(_focus[i])) if i < _focus.size() else C_MUS
		counter.add_child(_pip(12, 4, i < _focus.size(), group_color, group_color.lerp(Color.BLACK, 0.4)))
	_sec(L.t("Hedef grup"), counter)
	if slots > 0:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_body.add_child(grid)
		var profile := CardManager.province_profile(province_id)
		# Karşıt gruplar üst üste (0.0.301).
		for group in VoterGroups.stacked_order(4):
			var selected := _focus.has(group)
			var full := _focus.size() >= slots and not selected
			var token := _group_token(group, int(roundf(VoterGroups.share(profile, group) * 100.0)), selected, full)
			token.pressed.connect(func():
				if _focus.has(group):
					_focus.erase(group)
				elif _focus.size() < slots:
					_focus.append(group)
				refresh())
			grid.add_child(token)
	_smear = -1  # 0.0.237: karalama yine ayrı kart (elden ile sürükle)
	_body.add_child(_spacer())
	var cost := CardManager.miting_tier_cost(_miting_tier)
	var ok := CardManager.can_miting(me, province_id, 0.0, _miting_tier, _smear) and _focus.size() == slots
	_body.add_child(_big(L.t("MİTİNG YAP"), GameRules.cost_text(cost), C_GO, 50, not ok, func(): _do_miting()))

## Miting her zaman parti kasasından (0.0.238).
func _do_miting() -> void:
	var me := multiplayer.get_unique_id()
	var slots := CardManager.miting_focus_slots(me, province_id)
	if CardManager.miting_count(me) >= CardManager.action_limit(me):
		toast_requested.emit(L.t("Bu sıra %d mitingin hepsini yaptın.") % CardManager.action_limit(me))
		return
	if _focus.size() != slots:
		toast_requested.emit(L.t("Mitingi düzenlemek için %d seçmen grubu seç.") % slots)
		return
	if not CardManager.can_miting(me, province_id, 0.0, _miting_tier, _smear):
		var reason := CardManager.funding_block_reason(me, "miting", 0.0, CardManager.miting_tier_cost(_miting_tier))
		toast_requested.emit(reason if reason != "" else L.t("Sıra sende değil."))
		return
	if not _first_send():
		return
	# Bütçe ve hedef gruplar korunur: aynı ayarla art arda miting yapılabilir.
	CardManager.miting(province_id, 0.0, _focus.duplicate(), _miting_tier, _smear)

# --- YATIRIM -----------------------------------------------------------------------

func _build_invest() -> void:
	var me := multiplayer.get_unique_id()
	_sec(L.t("Yatırım boyu"))
	var costs: Array = []
	for t in CardManager.INVEST_TIERS.size():
		costs.append(Economy.money_full(CardManager.invest_tier_cost(t)))
	_body.add_child(_segment("invest", _invest_tier, costs, func(t: int):
		_invest_tier = t
		refresh()))
	var req := CardManager.invest_request(province_id)
	if not req.is_empty():
		_sec(L.t("İlin isteği"))
		var done := bool(req.get("done", false))
		var amount_label := _text(L.t("karşılandı") if done else Economy.money_full(float(req["amount"])), _font_display(), 18,
			C_GO if done else C_INK)
		_body.add_child(amount_label)
	_body.add_child(_spacer())
	var amount := CardManager.invest_tier_cost(_invest_tier)
	var ok := CardManager.can_invest(me, province_id, 1.0, _invest_tier)
	_body.add_child(_big(L.t("YATIRIM YAP"), Economy.money_full(amount), C_GO, 50, not ok, func():
		if CardManager.invest_count(me) >= CardManager.action_limit(me):
			toast_requested.emit(L.t("Bu sıra %d yatırımın hepsini yaptın.") % CardManager.action_limit(me))
			return
		if not CardManager.can_invest(me, province_id, 1.0, _invest_tier):
			var reason := CardManager.funding_block_reason(me, "invest", 1.0, amount)
			toast_requested.emit(reason if reason != "" else L.t("Sıra sende değil."))
			return
		if not _first_send():
			return
		CardManager.invest(province_id, 1.0, _invest_tier)))

## Aynı durum sürümünde ikinci onay gönderilmez (çift tık, çift ücret yok).
func _first_send() -> bool:
	if _sent_version == CardManager.state_version:
		return false
	_sent_version = CardManager.state_version
	return true

static func _level_name(level: int) -> String:
	match level:
		1:
			return L.t("1. seviye")
		2:
			return L.t("2. seviye (en üst)")
	return L.t("yok")

static func org_level_text(level: int) -> String:
	match level:
		1:
			return L.t("az oy bonusu, yaklaşık anket, mitingte bir gruba hitap")
		2:
			return L.t("yüksek oy bonusu, isabetli anket, mitingte iki gruba hitap")
	return ""
