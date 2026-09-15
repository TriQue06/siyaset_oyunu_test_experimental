extends Control
## SEÇİM GECESİ: haber kanalı tarzı canlı sayım yayını. Seçim yapılınca
## (CardManager.election_completed) GameScreen'den buraya geçilir.
##   - Solda harita: iller sandıkları açıldıkça öndeki partinin rengine boyanır,
##     sayımı sürenler soluk kalır; il üstündeki vekil kareleri canlı değişir.
##   - Sağda oy oranları (baraj çizgili, sıralaması canlı değişen çubuklar) ve
##     sandalyeleri dolan meclis diyagramı.
##   - Üstte CANLI etiketi, yayın saati ve açılan sandık oranı; altta SON DAKİKA
##     bandı ve kayan haber yazısı.
## Sayımın kendisi ElectionNightSim'de. Süre bitince kesin sonuç bir süre
## ekranda kalır, sonra GameScreen'e dönülür. "Sonuca Geç" sadece bu oyuncunun
## ekranını atlatır; host hükümet kurma süresine bu yayının süresini ekler
## (bkz. CardManager._hold_election).

const DURATION := GameRules.ELECTION_NIGHT_SECONDS
const HOLD_AFTER := GameRules.ELECTION_NIGHT_HOLD
const REFRESH_INTERVAL := 0.12
## Harita boyaması piksel piksel yapıldığı için daha seyrek yenilenir.
const MAP_REFRESH_INTERVAL := 0.3
const FLASH_SECONDS := 3.4
const TICKER_SPEED := 120.0

const BG_TOP := Color(0.04, 0.08, 0.19)
const BG_BOTTOM := Color(0.01, 0.02, 0.06)
const STRIP_COLOR := Color(0.03, 0.06, 0.16, 0.97)
const RED := Color(0.84, 0.05, 0.1)
const GOLD := Color(1.0, 0.78, 0.18)
const TEXT_DIM := Color(0.68, 0.74, 0.86)
const UNCOUNTED := Color(0.17, 0.2, 0.27)

const FLAVOR := [
	"Yurt genelinde sandıklar tek tek açılıyor",
	"Parti genel merkezlerinde heyecanlı bekleyiş sürüyor",
	"Sonuçlar kesin değildir, sayım devam ediyor",
	"Liderlerin seçim gecesi açıklaması bekleniyor",
	"Meclis aritmetiği son sandıklarla netleşecek",
	"Baraj çevresindeki partiler için gerilim sürüyor",
]

var _sim := ElectionNightSim.new()
var _t := 0.0
var _finished := false
var _leaving := false
var _hold_left := HOLD_AFTER
var _sample: Dictionary = {}
var _refresh_left := 0.0
var _map_refresh_left := 0.0
var _last_map_key := ""
var _last_parliament_key := ""
## Meclis diyagramında partilerin sabit sırası (ekonomik eksen: soldan sağa).
var _party_order: Array = []
## peer_id -> {"percent", "rank"} ekranda gösterilen (yumuşatılmış) değerler.
var _display: Dictionary = {}
var _targets: Dictionary = {}
var _flash_queue: Array = []
var _flash_left := 0.0
var _ticker_x := 0.0
var _ticker_round := 0
var _blink := 0.0
## Yerleşim hesaplanmadan (boyutlar 0 iken) çizim yapılmasın.
var _laid_out := false

# Olay takibi (SON DAKİKA bandı)
var _first_fired := false
var _leader := -1
var _leader_since := 0.0
var _above: Dictionary = {}
var _above_changed_at: Dictionary = {}
var _done_provinces: Dictionary = {}
var _majority_fired: Dictionary = {}

var _map: Node2D
var _map_frame := Rect2()
var _bars: LiveBars
var _parliament: ParliamentDiagram
var _background: TextureRect
var _top_bar: Panel
var _live_badge: Panel
var _live_label: Label
var _title: Label
var _subtitle: Label
var _clock: Label
var _counted: Label
var _progress_bg: ColorRect
var _progress_fill: ColorRect
var _section_votes: Label
var _section_parliament: Label
var _majority_label: Label
var _flash: Panel
var _flash_tag: Label
var _flash_text: Label
var _ticker_bg: Panel
var _ticker_tag: Panel
var _ticker_clip: Control
var _ticker_label: Label
var _skip_button: Button
var _final_stamp: Label

func _ready() -> void:
	_sim.setup(CardManager.last_province_results, CardManager.last_vote_shares, CardManager.last_seats,
		CardManager.passed_threshold, MultiplayerManager.election_threshold, _seed(), DURATION)
	_party_order = _sim.peer_ids.duplicate()
	_party_order.sort_custom(func(a, b):
		var ia: Dictionary = _party(a).get("ideology", {})
		var ib: Dictionary = _party(b).get("ideology", {})
		var ea := int(ia.get("economic", 0))
		var eb := int(ib.get("economic", 0))
		if ea != eb:
			return ea < eb
		return int(a) < int(b))
	for peer_id in _sim.peer_ids:
		_display[peer_id] = {"percent": 0.0, "rank": float(_party_order.find(peer_id))}
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	await get_tree().process_frame
	_layout()
	_laid_out = true
	_refresh()
	_refresh_map()
	_ticker_label.text = _ticker_text()
	_ticker_x = _ticker_clip.size.x

## Her istemcide aynı gece oynansın diye tohum sonuçtan türetilir.
func _seed() -> int:
	var keys: Array = CardManager.last_seats.keys()
	keys.sort()
	var text := str(CardManager.last_election_round)
	for peer_id in keys:
		text += "|%s:%d" % [str(peer_id), int(CardManager.last_seats[peer_id])]
	return hash(text)

func _process(delta: float) -> void:
	if not _laid_out:
		return
	if not _finished:
		_t = minf(_t + delta, DURATION)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		_refresh()
	_map_refresh_left -= delta
	if _map_refresh_left <= 0.0:
		_map_refresh_left = MAP_REFRESH_INTERVAL
		_refresh_map()
	_animate(delta)
	if _finished and not _leaving:
		_hold_left -= delta
		if _hold_left <= 0.0:
			_leave()

# --- Veri -> ekran -------------------------------------------------------------

func _refresh() -> void:
	if _bars == null:
		return
	_sample = _sim.sample(_t)
	var counted: float = float(_sample["counted"])
	_counted.text = "AÇILAN SANDIK  %%%.2f" % counted
	_progress_fill.size = Vector2(_progress_bg.size.x * counted / 100.0, _progress_bg.size.y)
	var minutes := 21 * 60 + int(_t / DURATION * 300.0)
	_clock.text = "%02d:%02d" % [(minutes / 60) % 24, minutes % 60]

	var national: Dictionary = _sample["national"]
	var ranked: Array = _sim.peer_ids.duplicate()
	if counted > 0.0:
		ranked.sort_custom(func(a, b):
			if float(national[a]) != float(national[b]):
				return float(national[a]) > float(national[b])
			return int(a) < int(b))
	else:
		ranked = _party_order.duplicate()
	var seats: Dictionary = _sample["seats"]
	var eligible: Array = _sample["eligible"]
	for i in ranked.size():
		var peer_id = ranked[i]
		_targets[peer_id] = {
			"percent": float(national.get(peer_id, 0.0)), "rank": float(i),
			"seats": int(seats.get(peer_id, 0)), "below": counted > 0.0 and not eligible.has(peer_id),
		}
	_bars.counted = counted
	_refresh_parliament()
	_detect_events()
	if _t >= DURATION and not _finished:
		_finish()

func _refresh_parliament() -> void:
	var seats: Dictionary = _sample["seats"]
	var entries: Array = []
	var assigned := 0
	var key := ""
	for peer_id in _party_order:
		var n := int(seats.get(peer_id, 0))
		assigned += n
		key += "%d," % n
		entries.append({"seats": n, "color": _party_color(peer_id)})
	if key == _last_parliament_key:
		return
	_last_parliament_key = key
	entries.append({"seats": maxi(0, _sim.total_seats - assigned), "color": UNCOUNTED})
	_parliament.set_results(entries)
	_majority_label.text = "Salt çoğunluk: %d   ·   Dağıtılan vekil: %d / %d" % [
		_sim.total_seats / 2 + 1, assigned, _sim.total_seats]

func _refresh_map() -> void:
	if _map == null or _sample.is_empty():
		return
	var provinces: Dictionary = _sample["provinces"]
	var colors := {}
	var markers := {}
	var key := ""
	for province_id in provinces.keys():
		var p: Dictionary = provinces[province_id]
		var c := float(p["c"])
		if c <= 0.0:
			colors[province_id] = UNCOUNTED
			key += "-"
			continue
		var seats: Dictionary = p["seats"]
		var shares: Dictionary = p["shares"]
		var winner = _province_winner(seats, shares)
		var color: Color = _party_color(winner).lerp(UNCOUNTED, (1.0 - c) * 0.6)
		colors[province_id] = color
		var ids: Array = seats.keys()
		ids.sort_custom(func(a, b): return int(seats[a]) > int(seats[b]))
		var seat_colors: Array = []
		for peer_id in ids:
			for i in int(seats[peer_id]):
				seat_colors.append(_party_color(peer_id))
			key += "%s%d" % [str(peer_id), int(seats[peer_id])]
		markers[province_id] = seat_colors
		key += "%s/%d;" % [str(winner), int(c * 8.0)]
	if key == _last_map_key:
		return
	_last_map_key = key
	_map.set_province_colors(colors)
	var seat_markers = _map.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.set_all(markers)

func _province_winner(seats: Dictionary, shares: Dictionary):
	var winner = -1
	for peer_id in shares.keys():
		if winner == -1:
			winner = peer_id
			continue
		var s := int(seats.get(peer_id, 0))
		var ws := int(seats.get(winner, 0))
		if s > ws or (s == ws and float(shares[peer_id]) > float(shares[winner])):
			winner = peer_id
	return winner

func _animate(delta: float) -> void:
	_blink += delta
	if _live_badge != null:
		_live_label.modulate.a = 0.55 + 0.45 * absf(sin(_blink * 3.0))
	if _bars == null:
		return
	var k := 1.0 - exp(-7.0 * delta)
	var rows: Array = []
	for peer_id in _sim.peer_ids:
		var d: Dictionary = _display[peer_id]
		var target: Dictionary = _targets.get(peer_id, {"percent": 0.0, "rank": d["rank"], "seats": 0, "below": false})
		d["percent"] = lerpf(float(d["percent"]), float(target["percent"]), k)
		d["rank"] = lerpf(float(d["rank"]), float(target["rank"]), k * 0.7)
		rows.append({
			"name": _party_name(peer_id), "leader": _leader_name(peer_id), "color": _party_color(peer_id),
			"percent": d["percent"], "rank": d["rank"], "seats": target["seats"], "below": target["below"],
		})
	_bars.rows = rows
	_bars.threshold = MultiplayerManager.election_threshold
	_bars.queue_redraw()

	# SON DAKİKA bandı
	if _flash_left > 0.0:
		_flash_left -= delta
	elif not _flash_queue.is_empty():
		var item: Array = _flash_queue.pop_front()
		_flash_tag.text = String(item[0])
		_flash_text.text = String(item[1])
		_layout_flash()
		_flash.modulate.a = 0.0
		_flash_left = FLASH_SECONDS if not _finished else HOLD_AFTER + 5.0
	var target_alpha := 1.0 if _flash_left > 0.35 else 0.0
	_flash.modulate.a = move_toward(_flash.modulate.a, target_alpha, delta * 5.0)

	# Kayan haber yazısı
	_ticker_x -= TICKER_SPEED * delta
	if _ticker_x < -_ticker_label.get_combined_minimum_size().x:
		_ticker_label.text = _ticker_text()
		_ticker_label.reset_size()
		_ticker_x = _ticker_clip.size.x
	_ticker_label.position = Vector2(_ticker_x, (_ticker_clip.size.y - _ticker_label.get_combined_minimum_size().y) * 0.5)

func _push_flash(tag: String, text: String) -> void:
	_flash_queue.append([tag, text])
	while _flash_queue.size() > 3:  # geride kalmasın: canlı yayın
		_flash_queue.pop_front()

func _detect_events() -> void:
	var counted := float(_sample["counted"])
	if counted <= 0.0 or _finished:
		return
	var national: Dictionary = _sample["national"]
	if not _first_fired:
		_first_fired = true
		_push_flash("İLK SONUÇLAR", "Sandıklar açılmaya başladı — sonuçlar kesin değildir")

	var leader = _top_peer(national)
	if counted >= 6.0 and leader != _leader:
		if _leader != -1 and _t - _leader_since > 3.0:
			_push_flash("SON DAKİKA", "%s öne geçti!  (%%%.1f)" % [_party_name(leader), float(national[leader])])
		_leader = leader
		_leader_since = _t

	if counted >= 12.0:
		var eligible: Array = _sample["eligible"]
		for peer_id in _sim.peer_ids:
			var above := eligible.has(peer_id)
			if not _above.has(peer_id):
				_above[peer_id] = above
				_above_changed_at[peer_id] = _t
			elif above != bool(_above[peer_id]) and _t - float(_above_changed_at[peer_id]) > 4.0:
				_above[peer_id] = above
				_above_changed_at[peer_id] = _t
				_push_flash("BARAJ", "%s barajın %s  (%%%.2f)" % [_party_name(peer_id),
					"üzerine çıktı!" if above else "altına düştü!", float(national[peer_id])])

	var provinces: Dictionary = _sample["provinces"]
	for province_id in _sim.province_ids:
		var p: Dictionary = provinces[province_id]
		if float(p["c"]) < 1.0 or _done_provinces.has(province_id):
			continue
		_done_provinces[province_id] = true
		if int(_sim.province_seats[province_id]) >= 9:
			var shares: Dictionary = p["shares"]
			var winner = _province_winner(p["seats"], shares)
			_push_flash(ElectionNightSim.province_name(province_id).to_upper(),
				"Sandıkların tamamı açıldı — birinci %s  (%%%.1f)" % [_party_name(winner), float(shares[winner])])

	if counted >= 40.0:
		var seats: Dictionary = _sample["seats"]
		for peer_id in seats.keys():
			if int(seats[peer_id]) * 2 > _sim.total_seats and not _majority_fired.has(peer_id):
				_majority_fired[peer_id] = true
				_push_flash("ÇOĞUNLUK", "%s tek başına çoğunluğu yakaladı!  (%d vekil)" % [_party_name(peer_id), int(seats[peer_id])])

func _top_peer(values: Dictionary):
	var best = -1
	for peer_id in values.keys():
		if best == -1 or float(values[peer_id]) > float(values[best]):
			best = peer_id
	return best

func _finish() -> void:
	_finished = true
	_t = DURATION
	_flash_queue.clear()
	_flash_left = 0.0
	var national: Dictionary = _sample["national"]
	var winner = _top_peer(national)
	if winner != -1:
		_push_flash("SONUÇ", "Tüm sandıklar açıldı. Kesin olmayan sonuçlara göre birinci parti: %s  (%%%.1f · %d vekil)" % [
			_party_name(winner), float(national[winner]), int(_sample["seats"].get(winner, 0))])
	_final_stamp.visible = true
	_skip_button.text = "Devam  ▸"
	_map_refresh_left = 0.0
	_ticker_label.text = _ticker_text()

func _ticker_text() -> String:
	var parts: Array = []
	var counted := float(_sample.get("counted", 0.0))
	var national: Dictionary = _sample.get("national", {})
	if counted > 0.0:
		parts.append("AÇILAN SANDIK %%%.1f" % counted)
		var ids: Array = national.keys()
		ids.sort_custom(func(a, b): return float(national[a]) > float(national[b]))
		for peer_id in ids:
			parts.append("%s %%%.1f" % [_party_name(peer_id), float(national[peer_id])])
	parts.append(FLAVOR[_ticker_round % FLAVOR.size()])
	_ticker_round += 1
	return "     ●     ".join(PackedStringArray(parts))

func _on_skip_pressed() -> void:
	if _finished:
		_leave()
		return
	_flash_queue.clear()
	_t = DURATION
	_refresh_left = 0.0

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")

# --- Parti bilgisi ---------------------------------------------------------------

func _party(peer_id) -> Dictionary:
	return PartyManager.parties.get(peer_id, {})

func _party_name(peer_id) -> String:
	return String(_party(peer_id).get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?")))

func _leader_name(peer_id) -> String:
	return String(MultiplayerManager.players.get(peer_id, {}).get("name", ""))

func _party_color(peer_id) -> Color:
	var color: Color = _party(peer_id).get("bg_color", Color(0.5, 0.5, 0.5))
	color.a = 1.0
	return color

# --- Arayüz kurulumu ---------------------------------------------------------------

func _build_ui() -> void:
	_background = TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, BG_TOP)
	gradient.set_color(1, BG_BOTTOM)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	_background.texture = texture
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_map = (load("res://scenes/Map.tscn") as PackedScene).instantiate()
	add_child(_map)

	_top_bar = _panel(STRIP_COLOR)
	add_child(_top_bar)
	_live_badge = _panel(RED)
	_top_bar.add_child(_live_badge)
	_live_label = _label("●  CANLI", 20, Color.WHITE)
	_live_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_live_badge.add_child(_live_label)
	_title = _label("SEÇİM GECESİ  ·  ÖZEL YAYIN", 26, Color.WHITE)
	_top_bar.add_child(_title)
	_subtitle = _label("%d. Tur  ·  %s" % [maxi(1, CardManager.last_election_round),
		"ERKEN SEÇİM" if CardManager.last_election_was_early else "GENEL SEÇİM"], 14, GOLD)
	_top_bar.add_child(_subtitle)
	_clock = _label("21:00", 34, Color.WHITE)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top_bar.add_child(_clock)
	_counted = _label("", 22, GOLD)
	_counted.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top_bar.add_child(_counted)

	_progress_bg = ColorRect.new()
	_progress_bg.color = Color(1, 1, 1, 0.08)
	_progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_bg)
	_progress_fill = ColorRect.new()
	_progress_fill.color = GOLD
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(_progress_fill)

	_section_votes = _label("OY ORANLARI", 15, TEXT_DIM)
	add_child(_section_votes)
	_bars = LiveBars.new()
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars)
	_section_parliament = _label("MECLİS DAĞILIMI", 15, TEXT_DIM)
	add_child(_section_parliament)
	_parliament = ParliamentDiagram.new()
	_parliament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_parliament)
	_majority_label = _label("", 14, TEXT_DIM)
	_majority_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_majority_label)

	_final_stamp = _label("KESİN OLMAYAN SONUÇLAR", 22, GOLD)
	_final_stamp.visible = false
	add_child(_final_stamp)

	_flash = _panel(Color(0.97, 0.97, 0.98))
	_flash.modulate.a = 0.0
	add_child(_flash)
	var flash_tag_bg := _panel(RED)
	flash_tag_bg.name = "TagBg"
	_flash.add_child(flash_tag_bg)
	_flash_tag = _label("", 18, Color.WHITE)
	_flash_tag.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flash_tag_bg.add_child(_flash_tag)
	_flash_text = _label("", 17, Color(0.06, 0.08, 0.16), false)
	_flash_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flash_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flash_text.clip_text = true
	_flash.add_child(_flash_text)

	_ticker_bg = _panel(Color(0.02, 0.03, 0.08))
	add_child(_ticker_bg)
	_ticker_tag = _panel(RED)
	_ticker_bg.add_child(_ticker_tag)
	var ticker_tag_label := _label("SON DAKİKA", 18, Color.WHITE)
	ticker_tag_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	ticker_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticker_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ticker_tag.add_child(ticker_tag_label)
	_ticker_clip = Control.new()
	_ticker_clip.clip_contents = true
	_ticker_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker_bg.add_child(_ticker_clip)
	_ticker_label = _label("", 18, Color.WHITE, false)
	_ticker_clip.add_child(_ticker_label)

	_skip_button = Button.new()
	_skip_button.text = "Sonuca Geç  ▸▸"
	UiSkin.skin_button(_skip_button)
	_skip_button.pressed.connect(_on_skip_pressed)
	add_child(_skip_button)

func _layout() -> void:
	var s := get_viewport_rect().size
	var margin := 16.0
	var top_h := 72.0
	var bottom_h := 52.0

	_top_bar.position = Vector2.ZERO
	_top_bar.size = Vector2(s.x, top_h)
	_live_badge.position = Vector2(margin, 16)
	_live_badge.size = Vector2(118, 40)
	_title.position = Vector2(margin + 134, 8)
	_subtitle.position = Vector2(margin + 136, 42)
	var right_reserved := 200.0  # sağ üstteki Ayarlar butonu (SettingsOverlay)
	_clock.position = Vector2(s.x - margin - right_reserved - 110, 10)
	_clock.size = Vector2(110, 50)
	_counted.position = Vector2(s.x - margin - right_reserved - 470, 19)
	_counted.size = Vector2(340, 34)
	_progress_bg.position = Vector2(0, top_h)
	_progress_bg.size = Vector2(s.x, 6)

	var content_top := top_h + 6.0 + margin
	var content_bottom := s.y - bottom_h - margin
	var split := s.x * 0.56
	var flash_h := 60.0
	_map_frame = Rect2(margin, content_top, split - margin * 1.5, content_bottom - content_top - flash_h - margin)
	if _map.grid_width > 0:
		var native: Vector2 = Vector2(_map.grid_width, _map.grid_height) * float(_map.MAP_UNIT_SCALE)
		var fit: float = minf(_map_frame.size.x / native.x, _map_frame.size.y / native.y)
		_map.scale = Vector2(fit, fit)
		_map.position = _map_frame.position + (_map_frame.size - native * fit) * 0.5
		var seat_markers = _map.get_node_or_null("SeatMarkers")
		if seat_markers != null:
			seat_markers.queue_redraw()
	_final_stamp.position = _map_frame.position + Vector2(4, 0)

	_flash.position = Vector2(margin, content_bottom - flash_h)
	_flash.size = Vector2(split - margin * 1.5, flash_h)
	_layout_flash()

	var right_x := split + margin * 0.5
	var right_w := s.x - right_x - margin
	var right_h := content_bottom - content_top
	_section_votes.position = Vector2(right_x, content_top - 6)
	_bars.position = Vector2(right_x, content_top + 22)
	_bars.size = Vector2(right_w, right_h * 0.5 - 22)
	var par_top := _bars.position.y + _bars.size.y + 14.0
	_section_parliament.position = Vector2(right_x, par_top)
	_majority_label.position = Vector2(right_x + 160, par_top + 1)
	_majority_label.size = Vector2(right_w - 160, 24)
	_parliament.position = Vector2(right_x, par_top + 30)
	_parliament.size = Vector2(right_w, content_bottom - par_top - 30 - 54)
	_skip_button.position = Vector2(s.x - margin - 196, content_bottom - 44)
	_skip_button.size = Vector2(196, 44)

	_ticker_bg.position = Vector2(0, s.y - bottom_h)
	_ticker_bg.size = Vector2(s.x, bottom_h)
	_ticker_tag.position = Vector2.ZERO
	_ticker_tag.size = Vector2(170, bottom_h)
	_ticker_clip.position = Vector2(182, 0)
	_ticker_clip.size = Vector2(s.x - 182, bottom_h)
	_last_parliament_key = ""
	if not _sample.is_empty():
		_refresh_parliament()

## SON DAKİKA kutusu: kırmızı etiket yazısı kadar geniş, metin kalan alana sarılır.
func _layout_flash() -> void:
	var tag_bg: Panel = _flash.get_node("TagBg")
	var tag_w: float = clampf(_flash_tag.get_combined_minimum_size().x + 32.0, 140.0, _flash.size.x * 0.45)
	tag_bg.position = Vector2.ZERO
	tag_bg.size = Vector2(tag_w, _flash.size.y)
	_flash_text.position = Vector2(tag_w + 14.0, 0)
	_flash_text.size = Vector2(_flash.size.x - tag_w - 24.0, _flash.size.y)

func _panel(color: Color) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _label(text: String, font_size: int, color: Color, outline: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Oy oranı çubukları: sıralama değiştikçe satırlar yumuşakça yer değiştirir,
## baraj kesik kırmızı çizgiyle gösterilir.
class LiveBars extends Control:
	var rows: Array = []
	var threshold: float = 0.0
	var counted: float = 0.0

	func _draw() -> void:
		if rows.is_empty():
			return
		var font := get_theme_default_font()
		var n := rows.size()
		var row_h: float = minf(60.0, size.y / float(n))
		var h: float = row_h - 8.0
		var name_w: float = minf(200.0, size.x * 0.32)
		var value_w := 104.0
		var bar_x := name_w + 10.0
		var bar_w: float = maxf(40.0, size.x - bar_x - value_w - 10.0)
		var max_percent := 0.0
		for r in rows:
			max_percent = maxf(max_percent, float(r["percent"]))
		var scale: float = maxf(25.0, max_percent * 1.12)
		var name_size: int = clampi(int(h * 0.36), 11, 19)
		for r in rows:
			var y: float = float(r["rank"]) * row_h
			var color: Color = r["color"]
			var below: bool = bool(r["below"])
			var alpha := 0.45 if below else 1.0
			draw_rect(Rect2(0, y + 2, 6, h), Color(color, alpha))
			draw_string(font, Vector2(14, y + h * 0.5 + 2), String(r["name"]), HORIZONTAL_ALIGNMENT_LEFT,
				name_w - 14, name_size, Color(1, 1, 1, alpha))
			draw_string(font, Vector2(14, y + h * 0.5 + 4 + name_size * 0.8), String(r["leader"]), HORIZONTAL_ALIGNMENT_LEFT,
				name_w - 14, maxi(9, name_size - 6), Color(0.65, 0.7, 0.8, alpha))
			draw_rect(Rect2(bar_x, y + 2, bar_w, h), Color(1, 1, 1, 0.05))
			var fill: float = bar_w * clampf(float(r["percent"]) / scale, 0.0, 1.0)
			draw_rect(Rect2(bar_x, y + 2, fill, h), Color(color, alpha))
			draw_rect(Rect2(bar_x, y + 2, fill, maxf(2.0, h * 0.12)), Color(1, 1, 1, 0.2 * alpha))
			draw_string(font, Vector2(size.x - value_w, y + h * 0.5 + 4), "%%%.2f" % float(r["percent"]),
				HORIZONTAL_ALIGNMENT_RIGHT, value_w, clampi(int(h * 0.45), 12, 24), Color(1, 1, 1, alpha))
			var sub := "BARAJ ALTI" if below else "%d vekil" % int(r["seats"])
			draw_string(font, Vector2(size.x - value_w, y + h * 0.5 + 6 + name_size * 0.8), sub,
				HORIZONTAL_ALIGNMENT_RIGHT, value_w, maxi(9, name_size - 6),
				Color(1, 0.45, 0.45) if below else Color(0.7, 0.75, 0.85))
		if threshold > 0.0:
			var tx: float = bar_x + bar_w * clampf(threshold / scale, 0.0, 1.0)
			var yy := 0.0
			while yy < row_h * n:
				draw_line(Vector2(tx, yy), Vector2(tx, minf(yy + 6.0, row_h * n)), Color(1, 0.3, 0.3, 0.85), 2.0)
				yy += 11.0
			draw_string(font, Vector2(tx + 4, row_h * n + 12), "BARAJ %%%s" % String.num(threshold, 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.45, 0.45))
