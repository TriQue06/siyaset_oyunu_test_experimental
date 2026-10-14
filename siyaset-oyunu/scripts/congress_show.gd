class_name CongressShow
extends Control
## KONGRE GECESİ: bir partinin kongre seçimi herkesin ekranında, seçim gecesiyle
## aynı yayın tarzında oynar. Sonuç host'ta önceden hesaplanmıştır
## (CardManager._compute_congress); burada sadece gösterilir.
##   1. TUR: delegeler sayılır, çubuklar büyür. Biri yarıyı geçerse kazanır.
##   2. TUR (gerekirse): ilk iki aday; elenenlerin delegeleri dağılır.
##   SONUÇ: kazanan altın damgayla.
## Süre: oyuncunun partisi seçim gecesinin yarısı, bot partisi dörtte biri.

const BG_TOP := UiTheme.BG
const BG_BOTTOM := UiTheme.INK
const GOLD := UiTheme.GOLD
const RED := UiTheme.RED

var data: Dictionary = {}
var _t := 0.0
var _duration := 6.0
var _rows: Array = []        # [{"panel","fill","name","value","index"}]
var _round_label: Label
var _status: Label
var _stamp: Label
var _progress_fill: ColorRect
var _bars_box: VBoxContainer
var _second_built := false
var _hold_end := 0.0

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
	_build_rows(range((data.get("candidates", []) as Array).size()), data.get("round1", []))
	_build_skip_controls()

func _phase_ends() -> Array:
	# [1. tur sayımı biter, 2. tur başlar, 2. tur biter]
	if (data.get("round2", []) as Array).is_empty():
		return [_duration * 0.62, _duration * 0.62, _duration * 0.62]
	return [_duration * 0.36, _duration * 0.46, _duration * 0.78]

## ATLA / 2× (0.0.179): yalnız bu ekran; kongre sonucu host'ta önceden
## hesaplandığı için atlamak sonucu değiştirmez. ATLA (Boşluk / Esc) önce
## sonucu gösterir, ikinci basış ekranı kapatır.
var _speed := 1.0

func skip_or_close() -> void:
	var ends := _phase_ends()
	if _t < float(ends[2]) + 0.01:
		_t = float(ends[2]) + 0.01
	else:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE):
		skip_or_close()
		get_viewport().set_input_as_handled()

func _build_skip_controls() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var speed := Button.new()
	speed.text = L.t("2× HIZ")
	speed.toggle_mode = true
	speed.toggled.connect(func(on: bool): _speed = 2.0 if on else 1.0)
	var skip := Button.new()
	skip.text = L.t("ATLA ▸▸")
	skip.pressed.connect(skip_or_close)
	for b: Button in [speed, skip]:
		UiSkin.skin_button(b)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiTheme.mono())
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 32)
		row.add_child(b)
	add_child(row)
	row.reset_size()
	var view := get_viewport_rect().size
	row.position = Vector2(view.x - row.size.x - 16.0, view.y - row.size.y - 16.0)

func _process(delta: float) -> void:
	_t += delta * _speed
	var ends := _phase_ends()
	var candidates: Array = data.get("candidates", [])
	var round2: Array = data.get("round2", [])
	_progress_fill.size.x = (_progress_fill.get_parent() as Control).size.x * clampf(_t / _duration, 0.0, 1.0)
	if _t <= ends[0]:
		_fill_rows(data.get("round1", []), clampf(_t / ends[0], 0.0, 1.0))
		_status.text = L.t("Delegeler oy kullanıyor…")
	elif _t <= ends[1]:
		_fill_rows(data.get("round1", []), 1.0)
		_status.text = L.t("Kimse delegelerin yarısını geçemedi: İKİNCİ TURA kalanlar belli oldu.")
	elif not round2.is_empty() and _t <= ends[2]:
		if not _second_built:
			_second_built = true
			_round_label.text = L.t("2. TUR")
			_build_rows([int(round2[0]), int(round2[1])], [])
		var k := clampf((_t - ends[1]) / maxf(0.01, ends[2] - ends[1]), 0.0, 1.0)
		_fill_pair(int(round2[2]), int(round2[3]), k)
		_status.text = L.t("İkinci tur oylaması…")
	else:
		if not round2.is_empty():
			if not _second_built:
				_second_built = true
				_round_label.text = L.t("2. TUR")
				_build_rows([int(round2[0]), int(round2[1])], [])
			_fill_pair(int(round2[2]), int(round2[3]), 1.0)
		else:
			_fill_rows(data.get("round1", []), 1.0)
		var winner: Dictionary = candidates[int(data.get("winner", 0))]
		_stamp.text = L.t("GENEL BAŞKAN: %s") % String(winner.get("name", "?"))
		_stamp.visible = true
		_status.text = L.t("Genel başkanlığını korudu.") if bool(winner.get("incumbent", false)) else L.t("Parti yeni genel başkanını seçti.")
		for row in _rows:
			if int(row["index"]) == int(data.get("winner", 0)):
				(row["panel"] as Panel).modulate = Color(1.15, 1.1, 0.8)
	if _t >= _duration:
		queue_free()

func _fill_rows(delegates: Array, k: float) -> void:
	for row in _rows:
		var i := int(row["index"])
		var value := float(delegates[i]) if i < delegates.size() else 0.0
		_set_row(row, value * _ease(k))

func _fill_pair(a_value: int, b_value: int, k: float) -> void:
	if _rows.size() < 2:
		return
	_set_row(_rows[0], a_value * _ease(k))
	_set_row(_rows[1], b_value * _ease(k))

func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - k, 2.0)

func _set_row(row: Dictionary, value: float) -> void:
	var total := float(CardManager.CONGRESS_DELEGATES)
	var fill: ColorRect = row["fill"]
	var track: Control = fill.get_parent()
	fill.size = Vector2(track.size.x * clampf(value / total, 0.0, 1.0), track.size.y)
	var half: ColorRect = row["half"]
	half.position = Vector2(track.size.x * 0.5 - 1.0, -4.0)
	half.size = Vector2(2.0, track.size.y + 8.0)
	(row["value"] as Label).text = L.t("%d  ·  %%%d") % [int(round(value)), int(round(value / total * 100.0))]

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_TOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var color: Color = data.get("color", GOLD)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 48
	root.offset_right = -48
	root.offset_top = 0
	root.offset_bottom = -24
	root.add_theme_constant_override("separation", 12)
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

	_round_label = _label(L.t("1. TUR") if (data.get("candidates", []) as Array).size() > 1 else L.t("TEK ADAY"), 18, UiTheme.TEXT_MUTED)
	root.add_child(_round_label)
	_bars_box = VBoxContainer.new()
	_bars_box.add_theme_constant_override("separation", 10)
	_bars_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bars_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bars_box)
	_status = _label("", 15, UiTheme.TEXT_MUTED)
	root.add_child(_status)
	_stamp = _label("", 30, GOLD)
	_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp.visible = false
	root.add_child(_stamp)

func _build_rows(indices: Array, _delegates: Array) -> void:
	for child in _bars_box.get_children():
		child.queue_free()
	_rows.clear()
	var candidates: Array = data.get("candidates", [])
	var party_color: Color = data.get("color", GOLD)
	for i in indices:
		var c: Dictionary = candidates[int(i)]
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0, 58)
		panel.add_theme_stylebox_override("panel", UiSkin.color_box(UiTheme.PANEL_DARK))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bars_box.add_child(panel)
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -10
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var names := VBoxContainer.new()
		names.custom_minimum_size = Vector2(300, 0)
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(names)
		var tag := ""
		if bool(c.get("incumbent", false)):
			tag = L.t("  · GENEL BAŞKAN")
		elif bool(c.get("human", false)):
			tag = L.t("  · OYUNCU")
		names.add_child(_label(String(c.get("name", "?")) + tag, 18, GOLD if bool(c.get("human", false)) else Color.WHITE))
		names.add_child(_label(String(c.get("background", "")), 12, UiTheme.TEXT_MUTED))
		var track := ColorRect.new()
		track.color = UiTheme.SLOT
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.custom_minimum_size = Vector2(0, 26)
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(track)
		var fill := ColorRect.new()
		fill.color = party_color if bool(c.get("incumbent", false)) else party_color.lerp(Color.WHITE, 0.35 + 0.15 * float(int(i) % 3))
		fill.size = Vector2(0, 26)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(fill)
		# Yarı çizgisi (delegelerin yarısı): geçen 1. turda kazanır.
		var half := ColorRect.new()
		half.color = Color.WHITE
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(half)
		var value := _label("0  ·  %0", 16, Color.WHITE)
		value.custom_minimum_size = Vector2(150, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(value)
		_rows.append({"panel": panel, "fill": fill, "half": half, "value": value, "index": int(i)})

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
