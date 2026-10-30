class_name PoliticalAxisReplay
extends Control
## SİYASİ YOLCULUK (0.0.304, politik eksen konsepti A "Masa haritası", bkz.
## konseptler/politik_eksen_konseptleri.html): oyun sonunda partilerin
## politik eksendeki yolu tur tur oynatılır. Kareli pano dört renkli bölgeye
## ayrılır (köşelerde bölge adları), eksen uçlarında grup pulları; parti
## logoları baloncuk animasyonuyla kayar, arkalarında solan noktalı iz kalır.
## Sağda partiler ve bulundukları bölge. Veri: CardManager.axis_history.

signal closed
## Oyun sonu sahne dizisinde (EndgameSequence) oynatma bitince.
signal finished

## Sahne dizisinin içinde: kendi zemini ve düğmeleri yok, bitince finished.
var embedded := false

const MAP := 440.0
const MARGIN := 40.0
## 0.0.306: her adım bir oyuncunun SIRASI; yumuşak ve görece yavaş.
const STEP_SECONDS := 1.0
const PAWN := 34.0
const C_TEAL := Color("1f6e70")
const C_MUTED := Color("7a7166")
const C_INK := Color("2d2a26")
const QUADS := [[Color("e8f3e8"), "MUHAFAZAKÂR SOL"], [Color("e6eef8"), "MUHAFAZAKÂR SAĞ"],
	[Color("fbe9ee"), "İLERİCİ SOL"], [Color("f3eafa"), "İLERİCİ SAĞ"]]

var _parties: Array = []        # [{pid, name, color, data, path: [[round, Vector2]]}]
var _rounds: Array = []
var _index := 0
var _map: _Map
var _pawns: Dictionary = {}     # pid -> Control
var _legend: VBoxContainer
var _round_label: Label
var _timer := 0.0
var _playing := true
var _step_seconds := STEP_SECONDS

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
		_index = 0
		_map.trails.clear()
		_playing = true
		_show_step(0, false))
	buttons.add_child(again)
	var close := Button.new()
	close.text = L.t("Kapat")
	close.focus_mode = Control.FOCUS_NONE
	UiSkin.skin_color_button(close, UiTheme.GREEN_DARK)
	close.pressed.connect(func():
		closed.emit()
		queue_free())
	buttons.add_child(close)
	_show_step.call_deferred(0, false)

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
	# Toplam ~40 sn: adım başına 0,45–1 sn (çok oyunculu uzun oyunda kısalır).
	_step_seconds = clampf(40.0 / maxf(1.0, float(_rounds.size())), 0.45, STEP_SECONDS)

## Partinin bu tura kadarki son konumu (henüz yoksa null).
static func _position_at(path: Array, round_value: int) -> Variant:
	var found: Variant = null
	for point in path:
		if int(point[0]) <= round_value:
			found = point[1]
	return found

func _to_map(p: Vector2) -> Vector2:
	return Vector2(MARGIN, MARGIN) + Vector2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5) * MAP

func _process(delta: float) -> void:
	if not _playing or _rounds.is_empty():
		return
	_timer += delta
	if _timer >= _step_seconds:
		_timer = 0.0
		if _index + 1 < _rounds.size():
			_index += 1
			_show_step(_index, true)
		else:
			_playing = false
			if embedded:
				get_tree().create_timer(2.0).timeout.connect(func():
					if is_instance_valid(self):
						finished.emit())

func _show_step(i: int, animate: bool) -> void:
	if _rounds.is_empty():
		_round_label.text = L.t("kayıt yok")
		if embedded:
			get_tree().create_timer(1.5).timeout.connect(func():
				if is_instance_valid(self):
					finished.emit())
		return
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
	for p in _parties:
		var pawn: Control = _pawns[p["pid"]]
		var pos: Variant = _position_at(p["path"], round_value)
		if pos == null:
			pawn.hide()
			continue
		var target := _to_map(pos) - Vector2(PAWN, PAWN) * 0.5
		var was_hidden := not pawn.visible
		pawn.show()
		if was_hidden or not animate:
			pawn.position = target
			_trail(p).append(_to_map(pos))
			continue
		var from := pawn.position + Vector2(PAWN, PAWN) * 0.5
		if from.distance_to(target + Vector2(PAWN, PAWN) * 0.5) < 1.0:
			continue
		# Baloncuk: eski yerde parti renginde baloncuklar yükselip söner.
		for k in 4:
			_bubble(from + Vector2(randf_range(-8, 8), randf_range(-6, 6)), p["color"], 0.08 * k)
		_trail(p).append(target + Vector2(PAWN, PAWN) * 0.5)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pawn, "position", target, _step_seconds * 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var pop := create_tween()
		var grow := 1.22 if int(p["pid"]) == actor else 1.06
		pop.tween_property(pawn, "scale", Vector2(grow, grow), _step_seconds * 0.45).set_trans(Tween.TRANS_SINE)
		pop.tween_property(pawn, "scale", Vector2.ONE, _step_seconds * 0.45).set_trans(Tween.TRANS_SINE)
	_map.queue_redraw()
	_refresh_legend(round_value)

## Partinin izi (harita koordinatında noktalar).
func _trail(p: Dictionary) -> Array:
	if not _map.trails.has(p["pid"]):
		_map.trails[p["pid"]] = {"color": p["color"], "points": []}
	return _map.trails[p["pid"]]["points"]

func _bubble(at: Vector2, color: Color, delay: float) -> void:
	var b := _Bubble.new()
	b.color = color
	b.radius = randf_range(4.0, 8.0)
	b.position = at
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(b)
	_map.move_child(b, 0)
	var tw := b.create_tween().set_parallel(true)
	tw.tween_property(b, "position", at + Vector2(randf_range(-12, 12), -randf_range(26, 44)), 0.9).set_delay(delay).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "modulate:a", 0.0, 0.9).set_delay(delay)
	tw.chain().tween_callback(b.queue_free)

func _refresh_legend(round_value: int) -> void:
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()
	for p in _parties:
		var pos: Variant = _position_at(p["path"], round_value)
		if pos == null:
			continue
		var card := PanelContainer.new()
		var box := BoardBox.new()
		box.fill = Color("fffaf0")
		box.set_radius(12)
		box.rings = [[0.0, 1.5, Color("e3d5b0")]]
		box.lips = [[3.0, Color("c9b689")]]
		box.set_content_margin_all(7)
		card.add_theme_stylebox_override("panel", box)
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
		var v: Vector2 = pos
		texts.add_child(_text("%s %s" % [L.t("Muhafazakâr") if v.y >= 0.0 else L.t("İlerici"), L.t("sağ") if v.x >= 0.0 else L.t("sol")], false, 11, C_MUTED))
		# Bu turki kayma (konsept: "↑ muhafazakâr").
		var prev: Variant = _position_at(p["path"], round_value - 1)
		var move := "—"
		if prev != null:
			var d: Vector2 = v - (prev as Vector2)
			if d.length() >= 0.02:
				move = ("↑ " + L.t("muhafazakâr") if d.y > 0.0 else "↓ " + L.t("ilerici")) if absf(d.y) > absf(d.x) 					else ("→ " + L.t("sağ") if d.x > 0.0 else "← " + L.t("sol"))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var move_label := _text(move, false, 12, C_MUTED)
		move_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(move_label)
		_legend.add_child(card)

static func _text(text: String, display: bool, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true) if display else UiTheme.mono_regular())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

class _Bubble extends Control:
	var color := Color.WHITE
	var radius := 6.0
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, Color(color, 0.55), true, -1.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(color.lightened(0.4), 0.9), 1.5, true)
		draw_circle(Vector2(-radius * 0.35, -radius * 0.35), radius * 0.25, Color(1, 1, 1, 0.7), true, -1.0, true)

## Kareli pano, dört bölge, eksenler ve noktalı izler.
class _Map extends Control:
	var replay: PoliticalAxisReplay
	var trails: Dictionary = {}   # pid -> {"color", "points": [konum]}
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
		# İzler: eskiden yeniye solan noktalı çizgi ve noktalar (son 6 adım).
		for pid in trails:
			var color: Color = trails[pid]["color"]
			var pts: Array = trails[pid]["points"]
			var start := maxi(0, pts.size() - 7)
			var n := pts.size() - start
			for i in range(start, pts.size()):
				var k := float(i - start + 1) / float(n)
				if i + 1 < pts.size():
					draw_dashed_line(pts[i], pts[i + 1], Color(color, 0.25 + 0.6 * k), 3.0, 4.0)
				if i < pts.size() - 1:
					draw_circle(pts[i], 4.0, Color(color, 0.2 + 0.5 * k), true, -1.0, true)
