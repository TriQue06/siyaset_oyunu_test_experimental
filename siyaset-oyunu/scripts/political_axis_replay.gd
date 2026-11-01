class_name PoliticalAxisReplay
extends Control
## SİYASİ YOLCULUK (0.0.304, politik eksen konsepti A "Masa haritası", bkz.
## konseptler/politik_eksen_konseptleri.html): oyun sonunda partilerin
## politik eksendeki yolu tur tur oynatılır. Kareli pano dört renkli bölgeye
## ayrılır (köşelerde bölge adları), eksen uçlarında grup pulları; parti
## logoları kayar, arkalarında solan iz kalır. Sağda partiler ve bulundukları
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
const QUADS := [[Color("e8f3e8"), "MUHAFAZAKÂR SOL"], [Color("e6eef8"), "MUHAFAZAKÂR SAĞ"],
	[Color("fbe9ee"), "İLERİCİ SOL"], [Color("f3eafa"), "İLERİCİ SAĞ"]]

var _parties: Array = []        # [{pid, name, color, data, path: [[round, Vector2]], values: [Vector2 her adımda], start}]
var _rounds: Array = []
var _map: _Map
var _pawns: Dictionary = {}     # pid -> Control
var _legend: VBoxContainer
var _legend_rows: Dictionary = {}   # pid -> {"card", "where", "move"}
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
		add_child(shade)
	_load_history()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	center.add_child(row)
	# Pano.
	var board := PanelContainer.new()
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
	row.add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	board.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	head.add_child(_text(L.t("Siyasi yolculuk"), true, 24, C_INK))
	_round_label = _text("", false, 12, C_MUTED)
	_round_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_round_label)
	_map = _Map.new()
	_map.custom_minimum_size = Vector2(MAP + MARGIN * 2.0, MAP + MARGIN * 2.0)
	_map.replay = self
	col.add_child(_map)
	for spec in [["dindar", Vector2(0.5, 0.0)], ["ilerici", Vector2(0.5, 1.0)], ["isci", Vector2(0.0, 0.5)], ["isveren", Vector2(1.0, 0.5)]]:
		var icon := VoterGroupIcon.make(String(spec[0]), 34.0)
		var at: Vector2 = spec[1]
		icon.position = Vector2(MARGIN, MARGIN) + at * MAP - Vector2(17, 17) + (at - Vector2(0.5, 0.5)) * 2.0 * Vector2(MARGIN - 6.0, MARGIN - 6.0)
		_map.add_child(icon)
	for p in _parties:
		var pawn := PartyBadge.build(p["data"], Vector2(PAWN, PAWN), 64)
		pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pawn.pivot_offset = Vector2(PAWN, PAWN) * 0.5
		pawn.hide()
		_map.add_child(pawn)
		_pawns[p["pid"]] = pawn
	# Sağda partiler.
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size.x = 250
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 7)
	side.add_child(_legend)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.visible = not embedded
	side.add_child(buttons)
	var again := Button.new()
	again.text = L.t("Yeniden oynat")
	again.focus_mode = Control.FOCUS_NONE
	UiSkin.skin_button(again)
	again.pressed.connect(func():
		_p = 0.0
		_shown_step = -1
		_playing = true)
	buttons.add_child(again)
	var close := Button.new()
	close.text = L.t("Kapat")
	close.focus_mode = Control.FOCUS_NONE
	UiSkin.skin_color_button(close, UiTheme.GREEN_DARK)
	close.pressed.connect(func():
		closed.emit()
		queue_free())
	buttons.add_child(close)
	_build_legend()
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
	# Adım: [adım, tur, sırası biten parti] (game_stats.steps).
	var actor := -1
	var turn_no := round_value
	for s in CardManager.game_stats.get("steps", []):
		if int(s[0]) == round_value:
			turn_no = int(s[1])
			actor = int(s[2])
	var actor_name := ""
	for p in _parties:
		if int(p["pid"]) == actor:
			actor_name = String(p["name"])
	_round_label.text = (L.t("%d. tur · %s") % [turn_no, actor_name]) if actor_name != "" else L.t("%d. tur") % turn_no
	_refresh_legend(i)

## İz: son TRAIL_STEPS adımın yolu, eskisi solarak (harita koordinatında örnekler).
func trail_points(p: Dictionary) -> Array:
	var from := maxf(float(p["start"]), _p - TRAIL_STEPS)
	var points: Array = []
	var count := maxi(1, int(ceil((_p - from) * TRAIL_SAMPLES)))
	for k in count + 1:
		var t := lerpf(from, _p, float(k) / float(count))
		points.append(_map_at(p["values"], t))
	return points

func _build_legend() -> void:
	for p in _parties:
		var card := PanelContainer.new()
		var box := BoardBox.new()
		box.fill = Color("fffaf0")
		box.set_radius(12)
		box.rings = [[0.0, 1.5, Color("e3d5b0")]]
		box.lips = [[3.0, Color("c9b689")]]
		box.set_content_margin_all(7)
		card.add_theme_stylebox_override("panel", box)
		card.hide()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		card.add_child(row)
		var logo := PartyBadge.build(p["data"], Vector2(28, 28), 64)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(logo)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 1)
		row.add_child(texts)
		texts.add_child(_text(String(p["name"]), true, 15, C_INK))
		var where := _text("", false, 11, C_MUTED)
		texts.add_child(where)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var move_label := _text("", false, 12, C_MUTED)
		move_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(move_label)
		_legend.add_child(card)
		_legend_rows[p["pid"]] = {"card": card, "where": where, "move": move_label}

func _refresh_legend(i: int) -> void:
	for p in _parties:
		var row: Dictionary = _legend_rows[p["pid"]]
		var shown := i >= int(p["start"])
		(row["card"] as Control).visible = shown
		if not shown:
			continue
		var v: Vector2 = p["values"][i]
		(row["where"] as Label).text = "%s %s" % [L.t("Muhafazakâr") if v.y >= 0.0 else L.t("İlerici"), L.t("sağ") if v.x >= 0.0 else L.t("sol")]
		# Bu adımdaki kayma (konsept: "↑ muhafazakâr").
		var move := "—"
		if i > int(p["start"]):
			var d: Vector2 = v - (p["values"][i - 1] as Vector2)
			if d.length() >= 0.02:
				move = ("↑ " + L.t("muhafazakâr") if d.y > 0.0 else "↓ " + L.t("ilerici")) if absf(d.y) > absf(d.x) \
					else ("→ " + L.t("sağ") if d.x > 0.0 else "← " + L.t("sol"))
		(row["move"] as Label).text = move

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
