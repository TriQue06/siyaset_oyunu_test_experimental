class_name CongressShow
extends Control
## KONGRE GECESİ: bir partinin kongre seçimi herkesin ekranında, seçim gecesiyle
## aynı yayın tarzında oynar. Sonuç host'ta önceden hesaplanmıştır
## (CardManager._compute_congress); burada sadece gösterilir.
## DELEGE SALONU (0.0.180): üstte delegeleri temsil eden koltuklar oy verdikçe
## adayın rengine döner; altta her adayın renkli kartı (sayaç + yarı çizgisi).
##   1. TUR: koltuklar sıra sıra dolar. Biri yarıyı geçerse kazanır.
##   2. TUR (gerekirse): ilk iki aday; elenenlerin koltukları griye döner ve
##      iki finaliste akar.
##   SONUÇ: konfeti + "GENEL BAŞKAN" damgası, ardından sonuç gazetesi (EventFx)
##   bu ekranda oynar ve ekran kapanır.
## Adaylar partinin renk skalasından ayrı tonlar alır (palette); ATLA / 2×
## 0.0.181'de kaldırıldı.
## Süre: CardManager.congress_duration (gazete hariç).

const BG_TOP := UiTheme.BG
const BG_BOTTOM := UiTheme.INK
const GOLD := UiTheme.GOLD
const RED := UiTheme.RED
## Salondaki koltuk sayısı (her koltuk 1200 / SEATS delegeyi temsil eder).
const SEATS := 300
const HALL_ROWS := 10

var data: Dictionary = {}
var _t := 0.0
var _duration := 6.0
var _cards: Array = []        # [{"panel","fill","value","index"}]
var _round_label: Label
var _status: Label
var _stamp: PanelContainer
var _stamp_label: Label
var _progress_fill: ColorRect
var _cards_box: HBoxContainer
var _hall: Hall
var _second_built := false
var _ended := false
var _end_t := 0.0
var _paper_started := false
var _event_fx: EventFx

func _ready() -> void:
	# Ekranın TAMAMINI kaplar (ebeveynin düzeninden bağımsız).
	top_level = true
	position = Vector2.ZERO
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	_duration = maxf(2.0, float(data.get("duration", 6.0)))
	_build()
	_hall.colors = palette(data.get("color", GOLD))
	_build_cards(range((data.get("candidates", []) as Array).size()))
	_hall.setup(data)
	# Gazete kendi katmanında: salonun (top_level, z 200) üstünde kesin görünür.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_event_fx = EventFx.new()
	layer.add_child(_event_fx)

func _phase_ends() -> Array:
	# [1. tur sayımı biter, 2. tur başlar, 2. tur biter]
	if (data.get("round2", []) as Array).is_empty():
		return [_duration * 0.62, _duration * 0.62, _duration * 0.62]
	return [_duration * 0.36, _duration * 0.46, _duration * 0.78]

func _process(delta: float) -> void:
	if _paper_started:
		# Gazete oynarken salon donmasın: konfeti sürer.
		_t += delta
		_hall.confetti_t = _t - _end_t
		if not _event_fx.is_playing():
			queue_free()
		return
	_t += delta
	var ends := _phase_ends()
	var candidates: Array = data.get("candidates", [])
	var round1: Array = data.get("round1", [])
	var round2: Array = data.get("round2", [])
	_progress_fill.size.x = (_progress_fill.get_parent() as Control).size.x * clampf(_t / _duration, 0.0, 1.0)
	if _t <= ends[0]:
		var k := _ease(clampf(_t / ends[0], 0.0, 1.0))
		_fill_cards(round1, k)
		_hall.show_round1(k)
		_status.text = L.t("Delegeler oy kullanıyor…")
	elif _t <= ends[1]:
		_fill_cards(round1, 1.0)
		_hall.show_between(clampf((_t - ends[0]) / maxf(0.01, ends[1] - ends[0]), 0.0, 1.0))
		_status.text = L.t("Kimse delegelerin yarısını geçemedi: İKİNCİ TURA kalanlar belli oldu.")
	elif not round2.is_empty() and _t <= ends[2]:
		_enter_round2(round2)
		var k := _ease(clampf((_t - ends[1]) / maxf(0.01, ends[2] - ends[1]), 0.0, 1.0))
		_fill_pair(round1, round2, k)
		_hall.show_round2(k)
		_status.text = L.t("İkinci tur oylaması…")
	else:
		if not round2.is_empty():
			_enter_round2(round2)
			_fill_pair(round1, round2, 1.0)
			_hall.show_round2(1.0)
		else:
			_fill_cards(round1, 1.0)
			_hall.show_round1(1.0)
		if not _ended:
			_ended = true
			_end_t = _t
			_show_winner(candidates)
		var since := _t - _end_t
		_hall.confetti_t = since
		_stamp.scale = Vector2.ONE * (1.0 + maxf(0.0, 0.3 - since) * 2.2)
	if _t >= _duration and not _paper_started:
		_start_paper()

func _show_winner(candidates: Array) -> void:
	var w := int(data.get("winner", 0))
	var winner: Dictionary = candidates[w]
	_stamp_label.text = L.t("GENEL BAŞKAN: %s") % String(winner.get("name", "?"))
	_stamp.visible = true
	_stamp.reset_size()
	_stamp.pivot_offset = _stamp.size * 0.5
	_stamp.position = Vector2(_hall.global_position.x + (_hall.size.x - _stamp.size.x) * 0.5,
		_hall.global_position.y + (_hall.size.y - _stamp.size.y) * 0.5)
	_status.text = L.t("Genel başkanlığını korudu.") if bool(winner.get("incumbent", false)) else L.t("Parti yeni genel başkanını seçti.")
	for card in _cards:
		var on := int(card["index"]) == w
		(card["panel"] as Control).modulate = Color(1.15, 1.12, 1.0) if on else Color(0.55, 0.55, 0.65)

## Sonuç gazetesi kongre ekranında oynar; bitince (ya da animasyonlar
## kapalıysa hemen) ekran kapanır.
func _start_paper() -> void:
	_paper_started = true
	var candidates: Array = data.get("candidates", [])
	var w := int(data.get("winner", 0))
	if w < 0 or w >= candidates.size():
		queue_free()
		return
	var winner: Dictionary = candidates[w]
	var round2: Array = data.get("round2", [])
	var round1: Array = data.get("round1", [])
	var delegates := 0
	if round2.size() >= 4:
		delegates = int(round2[2]) if int(round2[0]) == w else int(round2[3])
	elif w < round1.size():
		delegates = int(round1[w])
	var kept := bool(winner.get("incumbent", false))
	var shown := _event_fx.present("cg|%d|%d|%s" % [int(data.get("pid", -1)), CardManager.round_number, String(winner.get("name", ""))], {
		"headline": L.t("GENEL BAŞKAN KOLTUĞUNU KORUDU!") if kept else L.t("YENİ GENEL BAŞKAN BELLİ OLDU!"),
		"subtitle": L.t("%s kongresi: %s, %d delegenin oyuyla genel başkan.") % [
			String(data.get("party", "")), String(winner.get("name", "?")), delegates],
		"party": int(data.get("pid", -1)), "accent": data.get("color", GOLD),
		"stamp": L.t("GENEL BAŞKAN"), "sound": "law_passed"})
	if not shown:
		queue_free()

## Partinin renk skalası: ana renk, açık, koyu, çok açık, iki yana kayık ton.
## Birbirinden ayırt edilsin diye açıklık ve ton birlikte oynar.
static func palette(base: Color) -> Array:
	base.a = 1.0
	var shift := func(dh: float, dv: float) -> Color:
		return Color.from_hsv(fposmod(base.h + dh, 1.0), clampf(base.s * (0.85 if dv > 0.0 else 1.0), 0.0, 1.0),
			clampf(base.v + dv, 0.25, 1.0))
	return [base, base.lerp(Color.WHITE, 0.45), base.darkened(0.42), base.lerp(Color.WHITE, 0.72),
		shift.call(0.07, 0.08), shift.call(-0.07, -0.12)]

func candidate_color(index: int) -> Color:
	return _hall.colors[index % _hall.colors.size()]

func _enter_round2(round2: Array) -> void:
	if _second_built:
		return
	_second_built = true
	_round_label.text = L.t("2. TUR")
	_build_cards([int(round2[0]), int(round2[1])])

func _fill_cards(delegates: Array, k: float) -> void:
	for card in _cards:
		var i := int(card["index"])
		_set_card(card, (float(delegates[i]) if i < delegates.size() else 0.0) * k)

## 2. tur: finalistler 1. turdaki delegeleriyle başlar, elenenlerinkini toplar.
func _fill_pair(round1: Array, round2: Array, k: float) -> void:
	if _cards.size() < 2:
		return
	for j in 2:
		var start := float(round1[int(round2[j])])
		_set_card(_cards[j], lerpf(start, float(round2[2 + j]), k))

func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - k, 2.0)

func _set_card(card: Dictionary, value: float) -> void:
	var total := float(CardManager.CONGRESS_DELEGATES)
	var fill: ColorRect = card["fill"]
	var track: Control = fill.get_parent()
	fill.size = Vector2(track.size.x * clampf(value / total, 0.0, 1.0), track.size.y)
	var half: ColorRect = card["half"]
	half.position = Vector2(track.size.x * 0.5 - 1.0, -5.0)
	half.size = Vector2(3.0, track.size.y + 10.0)
	(card["value"] as Label).text = str(int(round(value)))
	(card["percent"] as Label).text = L.t("%%%d") % int(round(value / total * 100.0))

func _build() -> void:
	var bg := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, BG_TOP)
	gradient.set_color(1, BG_BOTTOM)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	bg.texture = texture
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var color: Color = data.get("color", GOLD)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 0
	root.offset_bottom = -60
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Üst yayın bandı
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UiSkin.color_box(UiTheme.PANEL_DARK))
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_row)
	var live := PanelContainer.new()
	live.add_theme_stylebox_override("panel", UiSkin.color_box(RED))
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.add_child(_label(L.t("  ●  CANLI  "), 18, Color.WHITE))
	top_row.add_child(live)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(28, 28)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(swatch)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(titles)
	titles.add_child(_label(L.t("%s KONGRESİ  ·  CANLI YAYIN") % String(data.get("party", "")).to_upper(), 24, Color.WHITE))
	var kinds := {"mandatory": L.t("OLAĞAN KONGRE (süre doldu)"), "voluntary": L.t("OLAĞANÜSTÜ KONGRE (genel başkanın çağrısı)"),
		"request": L.t("OLAĞANÜSTÜ KONGRE (üyenin talebi)")}
	titles.add_child(_label(L.t("%s  ·  %d delege") % [kinds.get(String(data.get("kind", "")), L.t("KONGRE")), CardManager.CONGRESS_DELEGATES], 13, GOLD))

	var progress := ColorRect.new()
	progress.color = UiTheme.SLOT
	progress.custom_minimum_size = Vector2(0, 6)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(progress)
	_progress_fill = ColorRect.new()
	_progress_fill.color = GOLD
	_progress_fill.size = Vector2(0, 6)
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(_progress_fill)

	# Delege salonu
	_hall = Hall.new()
	_hall.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hall.size_flags_stretch_ratio = 1.25
	_hall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hall)

	_round_label = _label(L.t("1. TUR") if (data.get("candidates", []) as Array).size() > 1 else L.t("TEK ADAY"), 20, GOLD)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_round_label)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 14)
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_cards_box)
	_status = _label("", 15, UiTheme.TEXT_MUTED)
	root.add_child(_status)

	# Sonuç damgası (salonun ortasına, hafif eğik)
	_stamp = PanelContainer.new()
	_stamp.add_theme_stylebox_override("panel", UiSkin.color_box(GOLD))
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.rotation = deg_to_rad(-4.0)
	_stamp.visible = false
	_stamp.z_index = 5
	_stamp_label = Label.new()
	_stamp_label.add_theme_font_override("font", UiTheme.mono(true))
	_stamp_label.add_theme_font_size_override("font_size", 34)
	_stamp_label.add_theme_color_override("font_color", UiTheme.INK)
	_stamp_label.text = " "
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_stamp_label)
	_stamp.add_child(pad)
	add_child(_stamp)

func _build_cards(indices: Array) -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	_cards.clear()
	var candidates: Array = data.get("candidates", [])
	for i in indices:
		var c: Dictionary = candidates[int(i)]
		var color := candidate_color(int(i))
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UiSkin.color_box(UiTheme.PANEL))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards_box.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(col)
		# Adayın renkli ad şeridi
		var strip := PanelContainer.new()
		strip.add_theme_stylebox_override("panel", UiSkin.color_box(color))
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(strip)
		var name_label := Label.new()
		name_label.text = "  " + String(c.get("name", "?"))
		name_label.add_theme_font_override("font", UiTheme.mono(true))
		name_label.add_theme_font_size_override("font_size", 19)
		name_label.add_theme_color_override("font_color", UiTheme.INK if color.get_luminance() > 0.45 else Color.WHITE)
		name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		name_label.clip_text = false
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(name_label)
		var tag := ""
		if bool(c.get("incumbent", false)):
			tag = L.t("GENEL BAŞKAN")
		elif bool(c.get("human", false)):
			tag = L.t("OYUNCU")
		var sub := String(c.get("background", ""))
		if tag != "":
			sub = tag if sub == "" else "%s  ·  %s" % [tag, sub]
		var sub_label := _label("  " + sub, 13, GOLD if tag != "" else UiTheme.TEXT_MUTED)
		col.add_child(sub_label)
		var nums := HBoxContainer.new()
		nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nums)
		var percent := _label("%0", 18, UiTheme.TEXT_MUTED)
		percent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		percent.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		nums.add_child(_spacer(10))
		nums.add_child(percent)
		var value := _label("0", 40, Color.WHITE)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		nums.add_child(value)
		nums.add_child(_spacer(10))
		var track_row := MarginContainer.new()
		track_row.add_theme_constant_override("margin_left", 10)
		track_row.add_theme_constant_override("margin_right", 10)
		track_row.add_theme_constant_override("margin_bottom", 12)
		track_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(track_row)
		var track := ColorRect.new()
		track.color = UiTheme.SLOT
		track.custom_minimum_size = Vector2(0, 18)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track_row.add_child(track)
		var fill := ColorRect.new()
		fill.color = color
		fill.size = Vector2(0, 18)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(fill)
		# Yarı çizgisi (delegelerin yarısı): geçen 1. turda kazanır.
		var half := ColorRect.new()
		half.color = Color.WHITE
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(half)
		_cards.append({"panel": panel, "fill": fill, "half": half, "value": value, "percent": percent, "index": int(i)})

func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", UiTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Delege salonu: amfi biçiminde SEATS koltuk. Her koltuk bir adaya aittir;
## oy sırası salonun ortasından kenarlara dalga gibi ilerler.
class Hall extends Control:
	var owner_r1: PackedInt32Array = []   # koltuk -> 1. tur adayı
	var owner_r2: PackedInt32Array = []   # koltuk -> 2. tur adayı
	var order: PackedInt32Array = []      # oy sırası (koltuk indeksleri)
	var transfer_rank: PackedInt32Array = []  # 2. turda el değiştiren koltukların sırası (-1: değişmez)
	var transfers := 0
	var mode := 0        # 0: 1. tur, 1: turlar arası, 2: 2. tur
	var k := 0.0
	var confetti_t := -1.0
	var colors: Array = []

	func setup(d: Dictionary) -> void:
		var total := float(CardManager.CONGRESS_DELEGATES)
		var round1: Array = d.get("round1", [])
		var round2: Array = d.get("round2", [])
		# Koltukları delegelere orantılı dağıt (en büyük kalan yöntemi).
		var counts := _apportion(round1, total)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(round1) + str(round2))
		var pool: Array = []
		for i in counts.size():
			for j in int(counts[i]):
				pool.append(i)
		while pool.size() < SEATS:
			pool.append(0)
		# Karışık oturma düzeni (aynı kongre her ekranda aynı görünür).
		for i in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		owner_r1 = PackedInt32Array(pool)
		owner_r2 = owner_r1.duplicate()
		transfer_rank.resize(SEATS)
		transfer_rank.fill(-1)
		if round2.size() >= 4:
			var a := int(round2[0])
			var b := int(round2[1])
			var target_a := int(round(float(round2[2]) / total * SEATS))
			var have_a := 0
			for i in SEATS:
				if owner_r1[i] == a:
					have_a += 1
			transfers = 0
			for i in SEATS:
				if owner_r1[i] != a and owner_r1[i] != b:
					owner_r2[i] = a if have_a < target_a else b
					if owner_r2[i] == a:
						have_a += 1
					transfer_rank[i] = transfers
					transfers += 1
		# Oy sırası: ortadan kenarlara, ön sıradan arkaya.
		var idx: Array = range(SEATS)
		idx.sort_custom(func(p, q): return _wave_key(p) < _wave_key(q))
		order = PackedInt32Array(idx)
		queue_redraw()

	func _apportion(delegates: Array, total: float) -> Array:
		var counts: Array = []
		var rems: Array = []
		var used := 0
		for i in delegates.size():
			var exact := float(delegates[i]) / total * SEATS
			counts.append(int(floor(exact)))
			rems.append([exact - floor(exact), i])
			used += int(floor(exact))
		rems.sort_custom(func(p, q): return p[0] > q[0])
		var r := 0
		while used < SEATS and r < rems.size():
			counts[int(rems[r][1])] += 1
			used += 1
			r += 1
		return counts

	func _seat_pos(i: int) -> Vector2:
		var per_row := SEATS / HALL_ROWS
		var row := i / per_row
		var col := i % per_row
		var w := size.x
		var h := size.y
		var t := (float(col) + 0.5) / float(per_row)
		var row_k := float(row) / float(HALL_ROWS - 1)
		# Hafif amfi: arka sıralar geniş ve yukarıda, kenarlar öne kıvrılır.
		var spread := 0.62 + 0.36 * row_k
		var x := w * 0.5 + (t - 0.5) * w * spread
		var y := h * (0.92 - 0.82 * row_k) - pow(absf(t - 0.5) * 2.0, 2.0) * h * 0.08 * (1.0 - row_k * 0.5)
		return Vector2(x, y)

	func _wave_key(i: int) -> float:
		var per_row := SEATS / HALL_ROWS
		return absf(float(i % per_row) / per_row - 0.5) * 2.0 + float(i / per_row) * 0.09

	func _color(i: int) -> Color:
		return colors[i % colors.size()]

	func show_round1(value: float) -> void:
		mode = 0
		k = value
		queue_redraw()

	func show_between(value: float) -> void:
		mode = 1
		k = value
		queue_redraw()

	func show_round2(value: float) -> void:
		mode = 2
		k = value
		queue_redraw()

	func _process(_delta: float) -> void:
		if confetti_t >= 0.0:
			queue_redraw()

	func _draw() -> void:
		if owner_r1.is_empty():
			return
		var per_row := SEATS / HALL_ROWS
		var r: float = clampf(minf(size.x * 0.62 / per_row * 0.42, size.y / HALL_ROWS * 0.4), 3.0, 14.0)
		var lit_count := int(k * SEATS) if mode == 0 else SEATS
		var rank := PackedInt32Array()
		rank.resize(SEATS)
		for n in order.size():
			rank[order[n]] = n
		var transfer_lit := int(k * transfers)
		for i in SEATS:
			var p := _seat_pos(i)
			var color := UiTheme.PANEL
			var radius := r
			if mode == 0:
				if rank[i] < lit_count:
					color = _color(owner_r1[i])
					if lit_count - rank[i] < 8:
						radius = r * 1.35  # yeni oy veren delege "parlar"
			elif transfer_rank[i] < 0:
				color = _color(owner_r1[i])
			elif mode == 1:
				# Elenen adayların koltukları griye döner.
				color = _color(owner_r1[i]).lerp(UiTheme.PANEL_LIGHT, k)
			elif transfer_rank[i] < transfer_lit:
				color = _color(owner_r2[i])
				if transfer_lit - transfer_rank[i] < 6:
					radius = r * 1.35
			else:
				color = UiTheme.PANEL_LIGHT
			draw_circle(p, radius, color)
		if confetti_t >= 0.0:
			_draw_confetti()

	func _draw_confetti() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1789
		for n in 120:
			var x0 := rng.randf() * size.x
			var speed := rng.randf_range(0.35, 0.8) * size.y
			var y := -20.0 + confetti_t * speed - rng.randf() * size.y * 0.4
			if y < -20.0 or y > size.y + 20.0:
				continue
			var x := x0 + sin(confetti_t * 3.0 + n) * 14.0
			var c := _color(n)
			if n % 3 == 0:
				c = GOLD
			draw_set_transform(Vector2(x, y), confetti_t * 4.0 + n, Vector2.ONE)
			draw_rect(Rect2(-4, -6, 8, 12), c)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
