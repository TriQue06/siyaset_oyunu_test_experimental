class_name EndgameSequence
extends Control
## OYUN SONU SAHNELERİ (0.0.305, bkz. konseptler/oyun_sonu_konseptleri*.html):
## oyun bittiği an jenerik müziği başlar ve sahneler sırayla oynar:
##   1. ÜNVANLAR (1A Damga): oyuncular yan yana; ünvan ortaya mühür kartı gibi
##      çarpar, açıklaması söner, kart küçülüp sahibinin listesine çakılır.
##      Eşitlikte kart her bölünmede daha sert sarsıntıyla ikiye, üçe... bölünür.
##   2. SİYASİ YOLCULUK (2A Masa haritası, PoliticalAxisReplay).
##   3. PERDE ARKASI (3C Karanlık arşiv): kaset ve iç karışıklıklar, parti
##      parti, spot ışığı altında gazete kupürleri olarak flaşla dizilir.
##   4. SEÇİM GRAFİĞİ (4A): tur tur oy oranı çizgileri; logo merkezi çizginin
##      ucunda; seçim turunda beyaz flaş, seçim çizgisi, rozet ve yüzdeler.
##   5. PUAN SIRALAMASI (5A Kürsü): basamaklar yükselir, avatarlar iner, taç ve konfeti.
## Herkes bütün sahneleri izler (atlama yok). Veriler: CardManager.game_stats,
## axis_history, final_ranking (her istemci kendi ekranında oynatır).

const C_RED := Color("d93636")
const C_RED_DARK := Color("8a1f1f")
const C_CARD := Color("fffaf0")
const C_INK := Color("2d2a26")
const C_MUTED := Color("7a7166")
const C_GOLD := Color("f2b632")
const C_GOLD_DARK := Color("b58312")
const C_CREAM := Color("fff6e0")

## [ünvan, açıklama, simge, sayaç ("" = eksen), en çok mu]
const TITLES := [
	["Meydanların Sultanı", "Oyun boyunca en çok miting yapan.", "t_miting", "mitings", true],
	["Müteahhit", "Devlet hazinesinden en çok yatırım yapan.", "t_invest", "invest", true],
	["Yasa Fabrikası", "Mecliste en çok yasa geçiren.", "t_law", "laws", true],
	["Hayır Cephesi", "Mecliste en çok HAYIR diyen.", "t_no", "no_votes", true],
	["Hükümet Avcısı", "En çok gensoru veren.", "t_hunt", "censures", true],
	["Koalisyon Kelebeği", "En sık koalisyonlarda yer alan.", "t_butterfly", "coalitions", true],
	["Dönek", "Politik eksende en uzun yolu kateden.", "t_turn", "", true],
	["Omurga", "Politik eksende en az yol kateden.", "t_spine", "", false],
	["Kara Kedi", "En çok olumsuzluk yaşayan: para cezası, kaset, iç karışıklık, karalanma.", "t_cat", "bad", true],
	["Afet Kahramanı", "Afetlere en çok yardım eden.", "t_aid", "aid", true],
]

var _stage_index := -1
var _stage: Control
var _old_stages: Array = []
var _layer: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 150
	var bg := _Felt.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	# 0.0.306: SONRAKİ düğmesi yok; herkes bütün sahneleri izler.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)
	_next.call_deferred()

## Sıradaki sahne. Atlanan sahne gizlenir ama silinmez: yarım kalan
## animasyonları kendi "cancelled" işaretiyle durur, dizi kapanınca gider.
func _next() -> void:
	if _stage != null:
		_stage.set("cancelled", true)
		_stage.hide()
		_old_stages.append(_stage)
	_stage_index += 1
	match _stage_index:
		0:
			_stage = _TitlesStage.new()
		1:
			var replay := PoliticalAxisReplay.new()
			replay.embedded = true
			replay.finished.connect(_next_if(replay))
			_stage = replay
		2:
			_stage = _RevealStage.new()
		3:
			_stage = _ChartStage.new()
		4:
			_stage = _PodiumStage.new()
		_:
			return
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_stage)
	if _stage.has_signal("done"):
		_stage.connect("done", _next_if(_stage))

## Yalnız hâlâ oynayan sahnenin bitişi diziyi ilerletir.
func _next_if(stage: Control) -> Callable:
	return func():
		if stage == _stage:
			_next()

## Baştan izle (son ekrandaki düğme).
func restart() -> void:
	for old in _old_stages:
		old.queue_free()
	_old_stages.clear()
	if _stage != null:
		_stage.set("cancelled", true)
		_stage.queue_free()
		_stage = null
	_stage_index = -1
	_next()

# --- Ortak yardımcılar ------------------------------------------------------------

## Oyun sonu partileri: pid -> {name, bg_color, icon_index, icon_color, leader, sayaçlar}.
static func stat_parties() -> Dictionary:
	return CardManager.game_stats.get("parties", {})

static func party_data(pid: int) -> Dictionary:
	var entry: Dictionary = stat_parties().get(pid, {})
	var party: Dictionary = PartyManager.data_of(pid)
	if not party.is_empty():
		return party
	return {"name": entry.get("name", "?"), "bg_color": entry.get("bg_color", Color.GRAY),
		"icon_index": int(entry.get("icon_index", 0)), "icon_color": entry.get("icon_color", Color.WHITE)}

## Ünvan dağıtılacak partiler: son sıralamadaki sırayla, sonra diğerleri.
static func ordered_parties() -> Array:
	var ids: Array = []
	for entry in CardManager.final_ranking:
		var pid := CardManager.party_of(int(entry.get("peer_id", -1)))
		if stat_parties().has(pid) and not ids.has(pid):
			ids.append(pid)
	for pid in stat_parties().keys():
		if not ids.has(int(pid)):
			ids.append(int(pid))
	return ids

## Eksendeki toplam yol (dönek / omurga). Yolu 2 noktadan kısaysa -1.
static func axis_distance(pid: int) -> float:
	var entry: Dictionary = CardManager.axis_history.get(pid, {})
	var path: Array = entry.get("path", [])
	if path.size() < 2:
		return -1.0
	var total := 0.0
	for i in range(1, path.size()):
		total += Vector2(float(path[i][1]), float(path[i][2])).distance_to(Vector2(float(path[i - 1][1]), float(path[i - 1][2])))
	return total

## Ünvanın sahipleri (eşitlikte birden çok). Kimse hak etmediyse boş.
static func title_winners(spec: Array, parties: Array) -> Array:
	var best := -INF if bool(spec[4]) else INF
	var winners: Array = []
	for pid in parties:
		var value: float
		if String(spec[3]) == "":
			value = axis_distance(int(pid))
			if value < 0.0:
				continue
		else:
			value = float(stat_parties().get(pid, {}).get(String(spec[3]), 0))
			if value <= 0.0:
				continue
		if is_equal_approx(value, best):
			winners.append(pid)
		elif (bool(spec[4]) and value > best) or (not bool(spec[4]) and value < best):
			best = value
			winners = [pid]
	return winners

static func text(value: String, display: bool, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", UiTheme.mono(true) if display else UiTheme.mono_regular())
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Sahneyi sarsar (strength: piksel).
static func shake(node: Control, strength: float = 9.0) -> void:
	var base := node.position
	if node.has_meta("shake_base"):
		base = node.get_meta("shake_base")
	node.set_meta("shake_base", base)
	var tw := node.create_tween()
	for i in 5:
		var k := 1.0 - float(i) / 5.0
		tw.tween_property(node, "position", base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k, 0.05)
	tw.tween_property(node, "position", base, 0.05)

## Beyaz flaş (peak: en yüksek saydamlık).
static func flash(parent: Control, peak: float = 0.8, seconds: float = 0.25) -> void:
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, peak)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", 0.0, seconds)
	tw.tween_callback(rect.queue_free)

class _Felt extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("103a2a"))
		var c := Vector2(size.x * 0.5, size.y * 0.35)
		for i in 16:
			var k := 1.0 - float(i) / 16.0
			draw_circle(c, size.x * 0.75 * k, Color(Color("24624a"), 0.07), true, -1.0, true)

class _Icon extends Control:
	var icon := ""
	var ink := Color.WHITE
	func _draw() -> void:
		VoterGroupIcon.draw_symbol(self, icon, size * 0.5, minf(size.x, size.y) * 0.5, ink)

# --- 1. ÜNVANLAR (Damga) -------------------------------------------------------------

class _TitlesStage extends Control:
	signal done
	var cancelled := false
	var _columns: Dictionary = {}   # pid -> sütun
	var _lists: Dictionary = {}     # pid -> VBox
	var _fx: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 30
		row.offset_right = -30
		row.offset_top = 70
		row.add_theme_constant_override("separation", 14)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var parties := EndgameSequence.ordered_parties()
		var width := minf(240.0, (get_viewport_rect().size.x - 60.0) / maxf(1.0, float(parties.size())) - 14.0)
		for pid in parties:
			var col := VBoxContainer.new()
			col.custom_minimum_size.x = width
			col.add_theme_constant_override("separation", 4)
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(col)
			var data := EndgameSequence.party_data(int(pid))
			var medal := AvatarMedal.make(PoliticianPresets.of(int(pid)), data, 64.0)
			medal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(medal)
			var name_label := EndgameSequence.text(String(data.get("name", "?")), true, 18, Color("fff6e0"))
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.clip_text = true
			col.add_child(name_label)
			var leader := EndgameSequence.text(String(EndgameSequence.stat_parties().get(pid, {}).get("leader", "")), false, 11, Color("bfe0cf"))
			leader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			leader.clip_text = true
			col.add_child(leader)
			var list := VBoxContainer.new()
			list.add_theme_constant_override("separation", 5)
			list.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(list)
			_columns[int(pid)] = col
			_lists[int(pid)] = list
			col.modulate.a = 0.0
		_fx = Control.new()
		_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fx)
		_run()

	func _wait(seconds: float) -> bool:
		await get_tree().create_timer(seconds).timeout
		return not cancelled and is_inside_tree()

	func _run() -> void:
		var i := 0
		for pid in _columns:
			var col: Control = _columns[pid]
			var tw := create_tween()
			tw.tween_interval(0.12 * i)
			tw.tween_property(col, "modulate:a", 1.0, 0.35)
			i += 1
		if not await _wait(0.9):
			return
		var parties: Array = _columns.keys()
		for spec in EndgameSequence.TITLES:
			var winners := EndgameSequence.title_winners(spec, parties)
			if winners.is_empty():
				continue
			if not await _give(spec, winners):
				return
		if await _wait(1.6):
			done.emit()

	## Ünvan kartı (büyük: ortada; küçük: listede).
	static func card(spec: Array, small: bool) -> PanelContainer:
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = EndgameSequence.C_CARD
		box.border_color = EndgameSequence.C_RED
		box.set_border_width_all(2 if small else 3)
		box.set_corner_radius_all(9 if small else 14)
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 3 if small else 10
		box.shadow_offset = Vector2(0, 3 if small else 6)
		box.content_margin_left = 8 if small else 18
		box.content_margin_right = 10 if small else 20
		box.content_margin_top = 5 if small else 12
		box.content_margin_bottom = 5 if small else 12
		box.anti_aliasing = true
		panel.add_theme_stylebox_override("panel", box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6 if small else 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var icon := EndgameSequence._Icon.new()
		icon.icon = String(spec[2])
		icon.ink = EndgameSequence.C_RED
		icon.custom_minimum_size = Vector2(16, 16) if small else Vector2(36, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var label := EndgameSequence.text(L.t(String(spec[0])).to_upper(), true, 12 if small else 32, EndgameSequence.C_RED)
		row.add_child(label)
		panel.rotation_degrees = -2.0 if small else -3.0
		return panel

	func _center_of(control: Control) -> Vector2:
		return control.get_global_rect().get_center() - _fx.get_global_rect().position

	func _give(spec: Array, winners: Array) -> bool:
		var view := get_viewport_rect().size
		# 1) Büyük kart ortaya ÇARPAR, ekran sarsılır.
		var big := card(spec, false)
		_fx.add_child(big)
		await get_tree().process_frame
		big.reset_size()
		big.pivot_offset = big.size * 0.5
		big.position = Vector2(view.x * 0.5, view.y * 0.55) - big.size * 0.5
		big.scale = Vector2(3, 3)
		big.modulate.a = 0.0
		big.rotation_degrees = -14.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(big, "scale", Vector2.ONE, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(big, "modulate:a", 1.0, 0.18)
		tw.tween_property(big, "rotation_degrees", -3.0, 0.28)
		await tw.finished
		AudioManager.play("censure_open")
		EndgameSequence.shake(self, 10.0)
		EndgameSequence.flash(self, 0.35, 0.2)
		# 2) Açıklama.
		var desc := EndgameSequence.text(L.t(String(spec[1])), false, 17, EndgameSequence.C_CREAM)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 560
		_fx.add_child(desc)
		desc.reset_size()
		desc.position = Vector2(view.x * 0.5 - 280, big.position.y + big.size.y + 18)
		desc.modulate.a = 0.0
		create_tween().tween_property(desc, "modulate:a", 1.0, 0.25)
		if not await _wait(1.4):
			return false
		var fade := create_tween()
		fade.tween_property(desc, "modulate:a", 0.0, 0.2)
		await fade.finished
		desc.queue_free()
		# 3) Küçülür: küçük kart büyük kartın yerinden doğar.
		var center := big.position + big.size * 0.5
		var pieces: Array = []
		var first := _piece(spec, center)
		pieces.append(first)
		first.scale = Vector2(2.4, 2.4)
		big.queue_free()
		var shrink := create_tween()
		shrink.tween_property(first, "scale", Vector2.ONE, 0.26).set_ease(Tween.EASE_IN)
		await shrink.finished
		# 4) Eşitlik: son parça her seferinde daha sert bölünür.
		for k in range(1, winners.size()):
			var last: Control = pieces[pieces.size() - 1]
			var power := 1.0 + float(k) * 0.35
			EndgameSequence.flash(self, minf(0.95, 0.35 + 0.15 * k), 0.16 + 0.04 * k)
			EndgameSequence.shake(self, 8.0 + 4.0 * k)
			var at := last.position + last.size * 0.5
			var gap := 70.0 + 14.0 * k
			var offset := Vector2(gap * 0.5 * (1.0 if k % 2 == 1 else -1.0), (26.0 * (1.0 if k % 2 == 1 else -1.0)) if k > 2 else 0.0)
			var piece := _piece(spec, at)
			piece.scale = Vector2(0.4, 0.4)
			pieces.append(piece)
			var sp := create_tween().set_parallel(true)
			sp.tween_property(last, "position", last.position - offset, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			sp.tween_property(last, "rotation_degrees", -2.0 + 6.0 * power, 0.12)
			sp.tween_property(piece, "position", piece.position + offset, 0.24 + 0.03 * k).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			sp.tween_property(piece, "scale", Vector2.ONE, 0.24)
			await sp.finished
			last.rotation_degrees = -2.0
			if not await _wait(maxf(0.12, 0.26 - 0.03 * k)):
				return false
		if not await _wait(0.25):
			return false
		# 5) Sahiplerine sert uçuş; listeye çakılır.
		for j in winners.size():
			_fly(pieces[j], spec, int(winners[j]), 0.07 * j)
		return await _wait(0.75 + 0.07 * winners.size())

	func _piece(spec: Array, center: Vector2) -> PanelContainer:
		var piece := card(spec, true)
		_fx.add_child(piece)
		piece.reset_size()
		piece.pivot_offset = piece.size * 0.5
		piece.position = center - piece.size * 0.5
		return piece

	func _fly(piece: Control, spec: Array, pid: int, delay: float) -> void:
		var list: VBoxContainer = _lists.get(pid)
		if list == null:
			piece.queue_free()
			return
		var holder := card(spec, true)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		holder.modulate.a = 0.0
		list.add_child(holder)
		await get_tree().process_frame
		await get_tree().process_frame
		if cancelled or not is_instance_valid(piece):
			return
		var target := _center_of(holder) - piece.size * 0.5
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(piece, "position", target - Vector2(0, 30), 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(piece, "scale", Vector2(1.3, 1.3), 0.25)
		tw.tween_property(piece, "position", target, 0.08)
		tw.parallel().tween_property(piece, "scale", Vector2.ONE, 0.08)
		await tw.finished
		piece.queue_free()
		holder.modulate.a = 1.0
		holder.pivot_offset = holder.size * 0.5
		holder.scale = Vector2(1.25, 1.25)
		create_tween().tween_property(holder, "scale", Vector2.ONE, 0.2)
		var col: Control = _columns.get(pid)
		if col != null:
			EndgameSequence.shake(col, 6.0)

# --- 3. PERDE ARKASI (Karanlık arşiv) --------------------------------------------

class _RevealStage extends Control:
	signal done
	var cancelled := false
	const MAX_CLIPS := 7
	var _rows: Array = []
	var _spot: Control

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0b0e17"))
		var c := Vector2(size.x * 0.5, size.y * 0.3)
		for i in 14:
			var k := 1.0 - float(i) / 14.0
			draw_circle(c, size.x * 0.7 * k, Color(Color("22293d"), 0.08), true, -1.0, true)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spot = _Spot.new()
		_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spot.size = Vector2(get_viewport_rect().size.x, 120)
		_spot.position = Vector2(0, -300)
		add_child(_spot)
		var banner := EndgameSequence.text(L.t("PERDE ARKASI"), true, 24, Color.WHITE)
		var banner_box := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = EndgameSequence.C_RED
		style.set_corner_radius_all(10)
		style.shadow_color = EndgameSequence.C_RED_DARK
		style.shadow_offset = Vector2(0, 4)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 6
		style.content_margin_bottom = 8
		banner_box.add_theme_stylebox_override("panel", style)
		banner_box.add_child(banner)
		banner_box.position = Vector2(30, 18)
		add_child(banner_box)
		var parties := EndgameSequence.ordered_parties()
		var top := 74.0
		var row_h := minf(96.0, (get_viewport_rect().size.y - top - 20.0) / maxf(1.0, float(parties.size())))
		for i in parties.size():
			var pid := int(parties[i])
			var row := HBoxContainer.new()
			row.position = Vector2(30, top + i * row_h)
			row.custom_minimum_size = Vector2(get_viewport_rect().size.x - 60, row_h - 10)
			row.add_theme_constant_override("separation", 12)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(row)
			row.add_child(_plate(pid, row_h - 14))
			var deeds := HBoxContainer.new()
			deeds.add_theme_constant_override("separation", 10)
			deeds.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(deeds)
			row.set_meta("pid", pid)
			row.set_meta("deeds", deeds)
			row.modulate.a = 0.0
			_rows.append(row)
		_run()

	func _plate(pid: int, height: float) -> Control:
		var data := EndgameSequence.party_data(pid)
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(220, minf(height, 64))
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = Color("1b2133")
		style.set_corner_radius_all(14)
		style.border_color = data.get("bg_color", Color.GRAY)
		style.border_width_left = 5
		style.content_margin_left = 12
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.shadow_color = Color(0, 0, 0, 0.6)
		style.shadow_offset = Vector2(0, 4)
		panel.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var badge := PartyBadge.build(data, Vector2(38, 38), 64)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", 1)
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(texts)
		texts.add_child(EndgameSequence.text(String(data.get("name", "?")), true, 17, Color.WHITE))
		texts.add_child(EndgameSequence.text(String(EndgameSequence.stat_parties().get(pid, {}).get("leader", "")), false, 11, Color("9aa3bd")))
		return panel

	func _clip(deed: Array) -> Control:
		var kind := String(deed[1])
		var target := int(deed[3])
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(150, 0)
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var style := StyleBoxFlat.new()
		style.bg_color = Color("efe3c4")
		style.set_corner_radius_all(3)
		style.shadow_color = Color(0, 0, 0, 0.6)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 5)
		style.border_color = Color("c9a46a")
		style.set_border_width_all(1)
		style.content_margin_left = 9
		style.content_margin_right = 9
		style.content_margin_top = 7
		style.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", style)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		panel.add_child(box)
		box.add_child(EndgameSequence.text(L.t("%d. tur") % int(deed[0]), true, 13, EndgameSequence.C_INK))
		var stamp := EndgameSequence.text(L.t("KASET") if kind == "kaset" else L.t("İÇ KARIŞIKLIK"), true, 11, EndgameSequence.C_RED)
		var stamp_box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = EndgameSequence.C_RED
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 1
		sb.content_margin_bottom = 2
		stamp_box.add_theme_stylebox_override("panel", sb)
		stamp_box.add_child(stamp)
		stamp_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		stamp_box.rotation_degrees = -4.0
		box.add_child(stamp_box)
		var hit := HBoxContainer.new()
		hit.add_theme_constant_override("separation", 5)
		box.add_child(hit)
		hit.add_child(EndgameSequence.text(L.t("hedef"), false, 11, EndgameSequence.C_MUTED))
		var data := EndgameSequence.party_data(target)
		var badge := PartyBadge.build(data, Vector2(20, 20), 64)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit.add_child(badge)
		var name_label := EndgameSequence.text(String(data.get("name", "?")), false, 11, EndgameSequence.C_MUTED)
		name_label.clip_text = true
		name_label.custom_minimum_size.x = 70
		hit.add_child(name_label)
		panel.rotation_degrees = randf_range(-3.0, 3.0)
		return panel

	func _wait(seconds: float) -> bool:
		await get_tree().create_timer(seconds).timeout
		return not cancelled and is_inside_tree()

	func _run() -> void:
		for i in _rows.size():
			var row: Control = _rows[i]
			var start := row.position
			row.position.x = start.x - 260
			var tw := create_tween().set_parallel(true)
			tw.tween_property(row, "position:x", start.x, 0.38).set_delay(0.11 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(row, "modulate:a", 1.0, 0.25).set_delay(0.11 * i)
		if not await _wait(0.9):
			return
		var all_deeds: Array = CardManager.game_stats.get("deeds", [])
		for i in _rows.size():
			var row: Control = _rows[i]
			var pid := int(row.get_meta("pid"))
			for k in _rows.size():
				create_tween().tween_property(_rows[k], "modulate:a", 1.0 if k == i else 0.28, 0.3)
			create_tween().tween_property(_spot, "position:y", row.position.y + row.size.y * 0.5 - _spot.size.y * 0.5, 0.35)
			var mine: Array = []
			for deed in all_deeds:
				if int(deed[2]) == pid:
					mine.append(deed)
			mine.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
			var deeds: HBoxContainer = row.get_meta("deeds")
			if mine.is_empty():
				var clean := EndgameSequence.text(L.t("Temiz çıktı. Ya da çok iyi saklandı."), false, 14, Color("9aa3bd"))
				deeds.add_child(clean)
				clean.modulate.a = 0.0
				create_tween().tween_property(clean, "modulate:a", 1.0, 0.4)
				if not await _wait(1.1):
					return
				continue
			for n in mine.size():
				if n >= MAX_CLIPS:
					deeds.add_child(EndgameSequence.text("+%d" % (mine.size() - MAX_CLIPS), true, 22, Color("ff6b6b")))
					break
				var clip := _clip(mine[n])
				deeds.add_child(clip)
				await get_tree().process_frame
				if cancelled:
					return
				clip.pivot_offset = clip.size * 0.5
				clip.scale = Vector2(1.8, 1.8)
				clip.modulate = Color(4, 4, 4, 0)
				EndgameSequence.flash(self, 0.9, 0.14)
				AudioManager.play("censure_open")
				var tw := create_tween().set_parallel(true)
				tw.tween_property(clip, "scale", Vector2.ONE, 0.24).set_ease(Tween.EASE_IN)
				tw.tween_property(clip, "modulate", Color.WHITE, 0.24)
				await tw.finished
				EndgameSequence.shake(row, 5.0)
				if not await _wait(0.34):
					return
			if not await _wait(0.5):
				return
		for row in _rows:
			create_tween().tween_property(row, "modulate:a", 1.0, 0.3)
		if await _wait(2.0):
			done.emit()

	class _Spot extends Control:
		func _draw() -> void:
			var c := Vector2(size.x * 0.25, size.y * 0.5)
			for i in 10:
				var k := 1.0 - float(i) / 10.0
				draw_set_transform(c, 0.0, Vector2(2.6, 1.0))
				draw_circle(Vector2.ZERO, size.y * 0.55 * k, Color(1, 0.95, 0.8, 0.025), true, -1.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- 4. SEÇİM GRAFİĞİ (çizgi + seçim flaşı) ---------------------------------------

class _ChartStage extends Control:
	signal done
	var cancelled := false
	## 0.0.306: grafik SIRA SIRA kaydedilir ve sürekli, yumuşak (köşesiz) akar.
	## Toplam süre adım sayısına göre bu aralıkta kalır.
	const MIN_SECONDS := 22.0
	const MAX_SECONDS := 50.0
	const ELECTION_PAUSE := 1.6
	const PAWN := 34.0
	var _series: Array = []      # [{pid, color, values: [% her adımda]}]
	var _steps: Array = []
	var _elections: Array = []
	var _revealed: Array = []
	var _pawns: Dictionary = {}
	var _min := 0.0
	var _max := 40.0
	var _p := 0.0                 # akan konum (adım indeksi, kesirli)
	var _speed := 1.0             # adım / sn
	var _pause := 0.0
	var _finished := false
	var _grid := 5.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shares: Dictionary = CardManager.game_stats.get("shares", {})
		_elections = CardManager.game_stats.get("elections", []).duplicate()
		var steps := {}
		for pid in shares.keys():
			for point in shares[pid]:
				steps[int(point[0])] = true
		_steps = steps.keys()
		_steps.sort()
		var lo := INF
		var hi := -INF
		for pid in shares.keys():
			var by_step := {}
			for point in shares[pid]:
				by_step[int(point[0])] = float(point[1])
			# Eksik adımlar bir öncekiyle (parti sonradan kurulduysa ilk değerle) dolar.
			var values: Array = []
			var last: Variant = null
			for s in _steps:
				if by_step.has(s):
					last = by_step[s]
				values.append(last)
			var first: Variant = null
			var start := 0
			for v in values:
				if v != null:
					first = v
					break
				start += 1
			if first == null:
				continue
			for k in values.size():
				if values[k] == null:
					values[k] = first
				lo = minf(lo, float(values[k]))
				hi = maxf(hi, float(values[k]))
			var data := EndgameSequence.party_data(int(pid))
			# start: partinin ilk kaydı (sonradan kurulan parti oradan çizilir).
			_series.append({"pid": int(pid), "color": data.get("bg_color", Color.GRAY), "values": values, "start": start})
			var pawn := PartyBadge.build(data, Vector2(PAWN, PAWN), 64)
			pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(pawn)
			_pawns[int(pid)] = pawn
		# Dar aralık: küçük artış ve azalışlar da okunur.
		if lo != INF:
			_min = maxf(0.0, floorf(lo - 1.0))
			_max = ceilf(hi + 1.0)
			_grid = maxf(1.0, roundf((_max - _min) / 6.0))
		var total := clampf(float(_steps.size()) * 0.4, MIN_SECONDS, MAX_SECONDS)
		_speed = maxf(1.0, float(_steps.size() - 1)) / total

	func _plot() -> Rect2:
		var m := Vector2(90, 100)
		return Rect2(m, size - m - Vector2(150, 80))

	func _x(index: float) -> float:
		var r := _plot()
		return r.position.x + r.size.x * index / maxf(1.0, float(_steps.size() - 1))

	func _y(value: float) -> float:
		var r := _plot()
		return r.position.y + r.size.y * (1.0 - (value - _min) / maxf(1.0, _max - _min))

	func _point(values: Array, k: int) -> Vector2:
		k = clampi(k, 0, values.size() - 1)
		return Vector2(_x(float(k)), _y(float(values[k])))

	## Catmull-Rom: köşesiz eğri; i..i+1 arasında t (0..1).
	func _curve(values: Array, i: int, t: float) -> Vector2:
		var p0 := _point(values, i - 1)
		var p1 := _point(values, i)
		var p2 := _point(values, i + 1)
		var p3 := _point(values, i + 2)
		var t2 := t * t
		var t3 := t2 * t
		return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

	func _at(values: Array, p: float) -> Vector2:
		if values.size() < 2:
			return _point(values, 0)
		var i := clampi(int(floor(p)), 0, values.size() - 2)
		return _curve(values, i, clampf(p - float(i), 0.0, 1.0))

	func _process(delta: float) -> void:
		if cancelled or _finished:
			return
		if _steps.is_empty():
			_finished = true
			get_tree().create_timer(1.5).timeout.connect(func():
				if not cancelled:
					done.emit())
			return
		if _pause > 0.0:
			_pause -= delta
			return
		var before := _p
		_p = minf(_p + delta * _speed, float(_steps.size() - 1))
		# Seçim adımına varıldı: dur, flaş, seçim çizgisi ve yüzdeler.
		for k in range(int(ceil(before)), int(floor(_p)) + 1):
			if k < 0 or k >= _steps.size():
				continue
			var step := int(_steps[k])
			if _elections.has(step) and not _revealed.has(step):
				_revealed.append(step)
				_p = float(k)
				_pause = ELECTION_PAUSE
				EndgameSequence.flash(self, 0.85, 0.45)
				EndgameSequence.shake(self, 10.0)
				AudioManager.play("censure_open")
				break
		# Logonun MERKEZİ çizginin son ucunda.
		for s in _series:
			var pawn: Control = _pawns[s["pid"]]
			pawn.visible = _p >= float(s["start"])
			pawn.position = _at(s["values"], _p) - Vector2(PAWN, PAWN) * 0.5
		queue_redraw()
		if _p >= float(_steps.size() - 1) and _pause <= 0.0:
			_finished = true
			get_tree().create_timer(3.0).timeout.connect(func():
				if not cancelled:
					done.emit())

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("efe2c0"))
		var font := UiTheme.mono(true)
		var body := UiTheme.mono_regular()
		draw_string(font, Vector2(90, 56), L.t("Oy oranları, sıra sıra"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, EndgameSequence.C_INK)
		var r := _plot()
		var v := _min
		while v <= _max + 0.01:
			var y := _y(v)
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(0.12, 0.43, 0.44, 0.15), 1.0)
			draw_string(body, Vector2(r.position.x - 52, y + 5), "%%%d" % int(v), HORIZONTAL_ALIGNMENT_RIGHT, 40, 13, EndgameSequence.C_MUTED)
			v += _grid
		# Tur başları: alt eksende küçük işaret ve tur numarası.
		var turns := {}
		for s in CardManager.game_stats.get("steps", []):
			turns[int(s[0])] = int(s[1])
		var last_round := -1
		for k in _steps.size():
			var turn_no := int(turns.get(int(_steps[k]), -1))
			if turn_no != last_round and turn_no > 0:
				last_round = turn_no
				var x := _x(float(k))
				draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y + 6), EndgameSequence.C_MUTED, 1.0)
				draw_string(body, Vector2(x - 10, r.end.y + 22), str(turn_no), HORIZONTAL_ALIGNMENT_CENTER, 20, 11, EndgameSequence.C_MUTED)
		# Seçimler: çizgilerin ve logoların ARKASINDA.
		for step in _revealed:
			var k := _steps.find(step)
			var x := _x(float(k))
			draw_line(Vector2(x, r.position.y - 20), Vector2(x, r.end.y), Color(EndgameSequence.C_GOLD, 0.9), 4.0)
			var label := L.t("%d. SEÇİM") % (_elections.find(step) + 1)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 20
			var rect := Rect2(Vector2(x - w * 0.5, r.position.y - 50), Vector2(w, 28))
			draw_rect(Rect2(rect.position + Vector2(0, 4), rect.size), EndgameSequence.C_GOLD_DARK)
			draw_rect(rect, EndgameSequence.C_GOLD)
			draw_string(font, rect.position + Vector2(10, 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("4a3203"))
			# Etikette seçimin GERÇEK sonucu; konum çizgideki noktaya göre.
			var results: Dictionary = CardManager.game_stats.get("election_results", {}).get(step, {})
			var items: Array = []
			for s in _series:
				if k < int(s["start"]):
					continue
				var value: float = s["values"][k]
				var shown := float(results.get(s["pid"], value))
				items.append([_y(value), shown, s["color"]])
			items.sort_custom(func(a, b): return a[0] < b[0])
			var last_y := -INF
			for item in items:
				var ly: float = maxf(float(item[0]), last_y + 22.0)
				last_y = ly
				var text := "%%%s" % L.dec(float(item[1]), 1)
				var tw := body.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
				draw_rect(Rect2(Vector2(x + PAWN * 0.5 + 6, ly - 12), Vector2(tw + 8, 22)), Color(0.97, 0.93, 0.85, 0.85))
				draw_string(body, Vector2(x + PAWN * 0.5 + 10, ly + 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, item[2])
		# Köşesiz çizgiler: tamamlanan aralıklar + akan son parça.
		for s in _series:
			var values: Array = s["values"]
			if values.size() < 2:
				continue
			var pts := PackedVector2Array()
			var full := int(floor(_p))
			for i in range(int(s["start"]), mini(full, values.size() - 1)):
				for n in 10:
					pts.append(_curve(values, i, float(n) / 10.0))
			if full < int(s["start"]):
				continue
			if full < values.size() - 1:
				var frac := _p - float(full)
				for n in 11:
					pts.append(_curve(values, full, frac * float(n) / 10.0))
			else:
				pts.append(_point(values, values.size() - 1))
			if pts.size() >= 2:
				draw_polyline(pts, s["color"], 5.0, true)

# --- 5. PUAN SIRALAMASI (Kürsü) -----------------------------------------------------

class _PodiumStage extends Control:
	var cancelled := false
	const HEIGHTS := [230.0, 170.0, 130.0]
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0b0e17"))
		var c := Vector2(size.x * 0.5, size.y * 0.45)
		var rays := 22
		for i in rays:
			var a := _t * 0.12 + TAU * float(i) / float(rays)
			var pts := PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * 1600.0, c + Vector2(cos(a + 0.14), sin(a + 0.14)) * 1600.0])
			draw_colored_polygon(pts, Color(1, 0.94, 0.7, 0.05))

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := EndgameSequence.text(L.t("SONUÇ"), true, 30, EndgameSequence.C_CREAM)
		title.position = Vector2(get_viewport_rect().size.x * 0.5 - 50, 20)
		add_child(title)
		_run()

	func _wait(seconds: float) -> bool:
		await get_tree().create_timer(seconds).timeout
		return not cancelled and is_inside_tree()

	func _run() -> void:
		var view := get_viewport_rect().size
		var ranking: Array = CardManager.final_ranking
		var order := [1, 0, 2]
		var base_y := view.y - 150.0
		var columns := {}
		var x := view.x * 0.5 - 330.0
		for k in order:
			if k >= ranking.size():
				x += 220.0
				continue
			var entry: Dictionary = ranking[k]
			var pid := int(entry.get("peer_id", -1))
			var data := EndgameSequence.party_data(CardManager.party_of(pid))
			if data.get("name", "?") == "?":
				data["name"] = entry.get("name", "?")
				data["bg_color"] = entry.get("color", Color.GRAY)
			var color: Color = data.get("bg_color", Color.GRAY)
			var step := Panel.new()
			var style := StyleBoxFlat.new()
			style.bg_color = color
			style.corner_radius_top_left = 14
			style.corner_radius_top_right = 14
			style.border_width_top = 4
			style.border_color = color.lightened(0.3)
			step.add_theme_stylebox_override("panel", style)
			step.size = Vector2(200, HEIGHTS[k])
			step.position = Vector2(x, base_y - HEIGHTS[k])
			step.pivot_offset = Vector2(100, HEIGHTS[k])
			step.scale = Vector2(1, 0)
			add_child(step)
			var rank := EndgameSequence.text(str(k + 1), true, 54, Color.WHITE)
			rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rank.size = Vector2(200, 60)
			rank.position = Vector2(0, 12)
			step.add_child(rank)
			var score := EndgameSequence.text(L.t("%d puan") % int(entry.get("score", 0)), true, 22, Color.WHITE)
			score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			score.size = Vector2(200, 30)
			score.position = Vector2(0, 76)
			step.add_child(score)
			var top := VBoxContainer.new()
			top.alignment = BoxContainer.ALIGNMENT_END
			top.add_theme_constant_override("separation", 6)
			var medal := AvatarMedal.make(PoliticianPresets.of(pid), data, 96.0 if k == 0 else 80.0)
			medal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			top.add_child(medal)
			var name_label := EndgameSequence.text(String(data.get("name", "?")), true, 20, EndgameSequence.C_CREAM)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			top.add_child(name_label)
			top.size = Vector2(200, 140)
			top.position = Vector2(x, base_y - HEIGHTS[k] - 148)
			top.modulate.a = 0.0
			add_child(top)
			columns[k] = [step, top]
			x += 220.0
		# Altta kalanlar.
		var rest := HBoxContainer.new()
		rest.add_theme_constant_override("separation", 12)
		rest.alignment = BoxContainer.ALIGNMENT_CENTER
		rest.position = Vector2(40, view.y - 132)
		rest.size = Vector2(view.x - 80, 40)
		add_child(rest)
		for i in range(3, ranking.size()):
			var entry: Dictionary = ranking[i]
			var card := EndgameSequence.text("%d. %s · %d %s" % [i + 1, String(entry.get("name", "?")), int(entry.get("score", 0)), L.t("puan")], true, 16, EndgameSequence.C_INK)
			var box := PanelContainer.new()
			var bs := StyleBoxFlat.new()
			bs.bg_color = EndgameSequence.C_CARD
			bs.set_corner_radius_all(12)
			bs.content_margin_left = 14
			bs.content_margin_right = 14
			bs.content_margin_top = 8
			bs.content_margin_bottom = 8
			box.add_theme_stylebox_override("panel", bs)
			box.add_child(card)
			box.modulate.a = 0.0
			rest.add_child(box)
		# Düğmeler.
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 12)
		buttons.position = Vector2(view.x * 0.5 - 230, view.y - 70)
		add_child(buttons)
		var again := Button.new()
		again.text = L.t("Baştan izle")
		again.custom_minimum_size = Vector2(200, 46)
		again.focus_mode = Control.FOCUS_NONE
		UiSkin.skin_button(again)
		again.pressed.connect(func():
			var sequence := get_parent().get_parent()
			if sequence is EndgameSequence:
				(sequence as EndgameSequence).restart())
		buttons.add_child(again)
		var back := Button.new()
		back.text = L.t("Ana Menüye Dön")
		back.custom_minimum_size = Vector2(240, 46)
		back.focus_mode = Control.FOCUS_NONE
		UiSkin.skin_color_button(back, UiTheme.GREEN_DARK)
		back.pressed.connect(func():
			MultiplayerManager.leave_room()
			SceneTransition.fade_to_scene("res://scenes/Lobby.tscn"))
		buttons.add_child(back)
		buttons.modulate.a = 0.0
		if not await _wait(0.5):
			return
		for k in [2, 1, 0]:
			if not columns.has(k):
				continue
			var step: Control = columns[k][0]
			var top: Control = columns[k][1]
			var rise := create_tween()
			rise.tween_property(step, "scale:y", 1.08, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			rise.tween_property(step, "scale:y", 1.0, 0.12)
			await rise.finished
			var end_y := top.position.y
			top.position.y = end_y - 200
			var drop := create_tween().set_parallel(true)
			drop.tween_property(top, "position:y", end_y, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			drop.tween_property(top, "modulate:a", 1.0, 0.2)
			await drop.finished
			EndgameSequence.shake(top, 6.0)
			if k == 0:
				EndgameSequence.flash(self, 0.8, 0.35)
				EndgameSequence.shake(self, 10.0)
				var crown := _Crown.new()
				crown.size = Vector2(60, 40)
				crown.position = Vector2(top.position.x + 70, top.position.y - 160)
				add_child(crown)
				var fall := create_tween()
				fall.tween_property(crown, "position:y", top.position.y - 14, 0.3).set_ease(Tween.EASE_IN)
				_confetti(view)
			if not await _wait(0.5):
				return
		var i := 0
		for card in rest.get_children():
			create_tween().tween_property(card, "modulate:a", 1.0, 0.3).set_delay(0.15 * i)
			i += 1
		create_tween().tween_property(buttons, "modulate:a", 1.0, 0.4).set_delay(0.3)

	func _confetti(view: Vector2) -> void:
		var colors := [Color("f2b632"), Color("e0283a"), Color("2fa866"), Color("7b5bd6"), Color.WHITE]
		for n in 90:
			var bit := ColorRect.new()
			bit.color = colors[n % colors.size()]
			bit.size = Vector2(10, 16)
			bit.position = Vector2(randf() * view.x, -20)
			bit.pivot_offset = bit.size * 0.5
			bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(bit)
			var tw := bit.create_tween().set_parallel(true)
			var t := randf_range(1.6, 3.0)
			tw.tween_property(bit, "position:y", view.y + 40, t).set_delay(randf() * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(bit, "rotation", randf_range(-12.0, 12.0), t)
			tw.chain().tween_callback(bit.queue_free)

	## Altın taç (yazı / emoji yerine vektör).
	class _Crown extends Control:
		func _draw() -> void:
			var w := size.x
			var h := size.y
			var pts := PackedVector2Array([Vector2(0, h), Vector2(0, h * 0.25), Vector2(w * 0.25, h * 0.6), Vector2(w * 0.5, 0),
				Vector2(w * 0.75, h * 0.6), Vector2(w, h * 0.25), Vector2(w, h)])
			draw_colored_polygon(PackedVector2Array([Vector2(0, h + 4), Vector2(w, h + 4), Vector2(w, h * 0.3 + 4), Vector2(0, h * 0.3 + 4)]), Color("b58312"))
			draw_colored_polygon(pts, Color("f2b632"))
			for p in [Vector2(0, h * 0.25), Vector2(w * 0.5, 0), Vector2(w, h * 0.25)]:
				draw_circle(p, 4.0, Color("fff3c6"), true, -1.0, true)
