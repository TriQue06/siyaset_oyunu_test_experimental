class_name PoliticalAxisReplay
extends Control
## SİYASİ YOLCULUK (0.0.304, politik eksen konsepti A "Masa haritası", bkz.
## konseptler/politik_eksen_konseptleri.html): oyun sonunda partilerin
## politik eksendeki yolu tur tur oynatılır. Kareli pano dört renkli bölgeye
## ayrılır (köşelerde bölge adları); parti logoları kayar, arkalarında solan
## iz kalır. 0.0.325: bütün partiler AYNI ANDA hareket eder (adımlar tura göre
## birleşir, sıra sıra gösterilmez); eksen uçlarında grup pulu yok, bölgeler
## sol üst kırmızı, sağ üst mavi, sol alt yeşil, sağ alt sarı. 0.0.326: yalnız
## eksen panosu; yanında parti listesi ve düğme yok (kendi başına açıldığında
## herhangi bir yere tıklamak kapatır). Sağda partiler ve bulundukları
## bölge. Veri: CardManager.axis_history.
## 0.0.314: oy grafiğiyle aynı oynatma: tek bir akan konum (kesirli adım),
## köşesiz (Catmull-Rom) yollar, durmadan ve daha kısa sürede.

signal closed
## Oyun sonu sahne dizisinde (EndgameSequence) oynatma bitince.
signal finished

## Sahne dizisinin içinde: kendi zemini ve düğmeleri yok, bitince finished.
var embedded := false

const MAP := 440.0
const MARGIN := 40.0
## Toplam oynatma süresi adım sayısına göre bu aralıkta kalır (adım başına 0,25 sn).
const MIN_SECONDS := 8.0
const MAX_SECONDS := 16.0
## İz: son kaç adım görünür (eskisi solar) ve adım başına örnek sayısı.
const TRAIL_STEPS := 8.0
const TRAIL_SAMPLES := 6
const PAWN := 34.0
const C_TEAL := Color("1f6e70")
const C_MUTED := Color("7a7166")
const C_INK := Color("2d2a26")
const QUADS := [[Color("f2b8b0"), "MUHAFAZAKÂR SOL"], [Color("b9cff0"), "MUHAFAZAKÂR SAĞ"],
	[Color("bfe1c0"), "İLERİCİ SOL"], [Color("f5df98"), "İLERİCİ SAĞ"]]

var _parties: Array = []        # [{pid, name, color, data, path: [[round, Vector2]], values: [Vector2 her adımda], start}]
var _rounds: Array = []
var _turns: Dictionary = {}     # adım -> tur numarası
var _map: _Map
var _pawns: Dictionary = {}     # pid -> Control
var _round_label: Label
var _p := 0.0                   # akan konum (adım indeksi, kesirli)
var _speed := 1.0               # adım / sn
var _shown_step := -1
var _playing := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 160
	if not embedded:
		var shade := ColorRect.new()
		shade.color = Color(UiTheme.FELT_DARK, 0.94)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				closed.emit()
				queue_free())
	_load_history()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# Pano (tek başına; tıklama alttaki kapatma yüzeyine geçer).
	var board := PanelContainer.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := BoardBox.new()
	style.fill = Color("f7eed8")
	style.fill_bottom = Color("efe2c0")
	style.set_radius(20)
	style.rings = [[4.0, 2.0, C_TEAL]]
	style.lips = [[10.0, Color("b79a68")]]
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_offset = Vector2(0, 22)
	style.shadow_size = 16
	style.set_content_margin_all(18)
	board.add_theme_stylebox_override("panel", style)
	center.add_child(board)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	board.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	head.add_child(_text(L.t("Siyasi yolculuk"), true, 24, C_INK))
	_round_label = _text("", false, 12, C_MUTED)
	_round_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_round_label)
	_map = _Map.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.custom_minimum_size = Vector2(MAP + MARGIN * 2.0, MAP + MARGIN * 2.0)
	_map.replay = self
	col.add_child(_map)
	for p in _parties:
		var pawn := PartyBadge.build(p["data"], Vector2(PAWN, PAWN), 64)
		pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pawn.pivot_offset = Vector2(PAWN, PAWN) * 0.5
		pawn.hide()
		_map.add_child(pawn)
		_pawns[p["pid"]] = pawn
	if _rounds.is_empty():
		_round_label.text = L.t("kayıt yok")
		_playing = false
		if embedded:
			get_tree().create_timer(1.5).timeout.connect(func():
				if is_instance_valid(self):
					finished.emit())

func _load_history() -> void:
	var rounds := {}
	for pid in CardManager.axis_history.keys():
		var entry: Dictionary = CardManager.axis_history[pid]
		var path: Array = []
		for point in entry.get("path", []):
			path.append([int(point[0]), Vector2(float(point[1]), float(point[2]))])
			rounds[int(point[0])] = true
		if path.is_empty():
			continue
		var color: Color = entry.get("bg_color", Color.GRAY)
		_parties.append({"pid": int(pid), "name": String(entry.get("name", "?")), "color": color, "path": path,
			"data": {"name": entry.get("name", "?"), "bg_color": color, "icon_index": int(entry.get("icon_index", 0)),
				"icon_color": entry.get("icon_color", Color.WHITE)}})
	_rounds = rounds.keys()
	_rounds.sort()
	# EŞZAMANLI (0.0.325): kayıt her sıradan sonra alınır; aynı turun adımları
	# tek adımda birleşir (turun son kaydı), bütün partiler birlikte kayar.
	var turn_of := {}
	for s in CardManager.game_stats.get("steps", []):
		turn_of[int(s[0])] = int(s[1])
	var last_of_turn := {}
	for r in _rounds:
		last_of_turn[int(turn_of.get(int(r), int(r)))] = int(r)
	_rounds = last_of_turn.values()
	_rounds.sort()
	_turns = {}
	for t in last_of_turn.keys():
		_turns[int(last_of_turn[t])] = int(t)
	# Her adımda konum: eksik adım bir öncekiyle dolar; start = ilk kayıt.
	for p in _parties:
		var values: Array = []
		var start := -1
		for k in _rounds.size():
			var pos: Variant = _position_at(p["path"], int(_rounds[k]))
			if pos == null:
				values.append(null)
				continue
			if start < 0:
				start = k
			values.append(pos)
		for k in values.size():
			if values[k] == null:
				values[k] = values[maxi(start, 0)]
		p["values"] = values
		p["start"] = maxi(start, 0)
	var total := clampf(float(_rounds.size()) * 0.25, MIN_SECONDS, MAX_SECONDS)
	_speed = maxf(1.0, float(_rounds.size() - 1)) / total

## Partinin bu tura kadarki son konumu (henüz yoksa null).
static func _position_at(path: Array, round_value: int) -> Variant:
	var found: Variant = null
	for point in path:
		if int(point[0]) <= round_value:
			found = point[1]
	return found

func _to_map(p: Vector2) -> Vector2:
	return Vector2(MARGIN, MARGIN) + Vector2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5) * MAP

## Catmull-Rom: köşesiz yol; i..i+1 arasında t (0..1), eksen koordinatında.
static func _curve(values: Array, i: int, t: float) -> Vector2:
	var n := values.size()
	var p0: Vector2 = values[clampi(i - 1, 0, n - 1)]
	var p1: Vector2 = values[clampi(i, 0, n - 1)]
	var p2: Vector2 = values[clampi(i + 1, 0, n - 1)]
	var p3: Vector2 = values[clampi(i + 2, 0, n - 1)]
	var t2 := t * t
	var t3 := t2 * t
	var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
	return v.clamp(Vector2(-1, -1), Vector2(1, 1))

## Partinin p anındaki konumu (harita koordinatında).
func _map_at(values: Array, p: float) -> Vector2:
	if values.size() < 2:
		return _to_map(values[0])
	var i := clampi(int(floor(p)), 0, values.size() - 2)
	return _to_map(_curve(values, i, clampf(p - float(i), 0.0, 1.0)))

func _process(delta: float) -> void:
	if _rounds.is_empty():
		return
	if _playing:
		_p = minf(_p + delta * _speed, float(_rounds.size() - 1))
		if _p >= float(_rounds.size() - 1):
			_playing = false
			if embedded:
				get_tree().create_timer(2.0).timeout.connect(func():
					if is_instance_valid(self):
						finished.emit())
	for p in _parties:
		var pawn: Control = _pawns[p["pid"]]
		pawn.visible = _p >= float(p["start"])
		pawn.position = _map_at(p["values"], _p) - Vector2(PAWN, PAWN) * 0.5
	var step := int(floor(_p))
	if step != _shown_step:
		_shown_step = step
		_show_step(step)
	_map.queue_redraw()

## Tur yazısı ve sağdaki partiler (adım değişince).
func _show_step(i: int) -> void:
	var round_value := int(_rounds[i])
	_round_label.text = L.t("%d. tur") % int(_turns.get(round_value, round_value))

## İz: son TRAIL_STEPS adımın yolu, eskisi solarak (harita koordinatında örnekler).
func trail_points(p: Dictionary) -> Array:
	var from := maxf(float(p["start"]), _p - TRAIL_STEPS)
	var points: Array = []
	var count := maxi(1, int(ceil((_p - from) * TRAIL_SAMPLES)))
	for k in count + 1:
		var t := lerpf(from, _p, float(k) / float(count))
		points.append(_map_at(p["values"], t))
	return points

static func _text(text: String, display: bool, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true) if display else UiTheme.mono_regular())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Kareli pano, dört bölge, eksenler ve noktalı izler.
class _Map extends Control:
	var replay: PoliticalAxisReplay
	func _draw() -> void:
		var m := PoliticalAxisReplay.MARGIN
		var s := PoliticalAxisReplay.MAP
		var half := s * 0.5
		var origins := [Vector2(m, m), Vector2(m + half, m), Vector2(m, m + half), Vector2(m + half, m + half)]
		for i in 4:
			draw_rect(Rect2(origins[i], Vector2(half, half)), PoliticalAxisReplay.QUADS[i][0])
		var grid := Color(0.12, 0.43, 0.44, 0.09)
		var cell := s / 20.0
		for k in 21:
			draw_line(Vector2(m + k * cell, m), Vector2(m + k * cell, m + s), grid, 1.0)
			draw_line(Vector2(m, m + k * cell), Vector2(m + s, m + k * cell), grid, 1.0)
		var font := UiTheme.mono_regular()
		var label_color := Color(0.18, 0.16, 0.15, 0.45)
		for i in 4:
			var text := L.t(String(PoliticalAxisReplay.QUADS[i][1]))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var x: float = origins[i].x + 10.0 if i % 2 == 0 else origins[i].x + half - 10.0 - w
			var y: float = origins[i].y + 20.0 if i < 2 else origins[i].y + half - 10.0
			draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_color)
		# Kesikli eksenler.
		var axis := Color(0.12, 0.43, 0.44, 0.5)
		draw_dashed_line(Vector2(m + half, m), Vector2(m + half, m + s), axis, 2.0, 6.0)
		draw_dashed_line(Vector2(m, m + half), Vector2(m + s, m + half), axis, 2.0, 6.0)
		var frame := StyleBoxFlat.new()
		frame.draw_center = false
		frame.border_color = Color("1f6e70")
		frame.set_border_width_all(3)
		frame.set_corner_radius_all(6)
		draw_style_box(frame, Rect2(Vector2(m, m), Vector2(s, s)))
		# İzler: oy grafiği gibi kesintisiz çizgi, eski ucu solarak.
		for p in replay._parties:
			if replay._p < float(p["start"]):
				continue
			var color: Color = p["color"]
			var pts: Array = replay.trail_points(p)
			var n := pts.size()
			for i in n - 1:
				var k := float(i + 1) / float(n)
				draw_line(pts[i], pts[i + 1], Color(color, 0.1 + 0.75 * k), 3.0, true)
