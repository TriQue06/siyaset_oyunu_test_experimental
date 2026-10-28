extends Control
## SEÇİM GECESİ: haber kanalı tarzı canlı sayım yayını. Seçim yapılınca
## (CardManager.election_completed) GameScreen'den buraya geçilir.
##   - Solda harita: iller sandıkları açıldıkça öndeki partinin rengine boyanır,
##     sayımı sürenler soluk kalır; il üstündeki vekil kareleri canlı değişir.
##   - Sağda oy oranları (baraj çizgili, sıralaması canlı değişen çubuklar) ve
##     sandalyeleri dolan meclis diyagramı.
##   - Üstte CANLI etiketi, yayın saati ve açılan sandık oranı; altta SON DAKİKA
##     bandı ve kayan haber yazısı.
## Sayımın kendisi ElectionNightSim'de; her karede yeniden hesaplanıp çizilir
## (haritanın mesh renkleri güncellenir, bkz. province_map.gd). Süre bitince
## kesin sonuç bir süre ekranda kalır, sonuç gazetesi (EventFx) BU ekranda
## oynar, sonra GameScreen'e dönülür (0.0.180; ATLA / 2× kaldırıldı).
## STÜDYO KAMERALARI (0.0.180): harita, oy oranları ve meclis üç pencerede;
## sayımın her çeyreğinde büyük pencereye sırayla biri geçer (TV flaşıyla),
## diğer ikisi sağda küçük kalır. Sayım bitince klasik düzene oturur.
## Host hükümet kurma süresine bu yayının süresini ekler (bkz.
## CardManager._hold_election).

const DURATION := GameRules.ELECTION_NIGHT_SECONDS
const HOLD_AFTER := GameRules.ELECTION_NIGHT_HOLD
const REFRESH_INTERVAL := 0.12
## Harita boyaması piksel piksel yapıldığı için daha seyrek yenilenir.
const MAP_REFRESH_INTERVAL := 0.3
const FLASH_SECONDS := 2.6
const TICKER_SPEED := 120.0

const BG_TOP := UiTheme.FELT_LIGHT
const BG_BOTTOM := UiTheme.FELT_DARK
const STRIP_COLOR := UiTheme.WOOD
const RED := UiTheme.RED
const GOLD := UiTheme.GOLD
const TEXT_DIM := UiTheme.HEAD
const UNCOUNTED := UiTheme.PANEL_LIGHT

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
## Meclis diyagramında partilerin sabit sırası: işçi desteği yüksek olanlar
## solda, işveren desteği yüksek olanlar sağda (sadece görsel sıralama).
var _party_order: Array = []
const RANK_HYSTERESIS := 0.1
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
var _top_bar: Control
var _live_badge: Panel
var _live_label: Label
var _title: Label
var _subtitle: Label
var _clock: Label
var _counted: Label
var _progress_bg: ColorRect
var _progress_fill: ColorRect
var _section_map: Label
var _section_votes: Label
var _section_parliament: Label
var _majority_label: Label
var _flash: Panel
var _flash_tag: Label
var _flash_text: Label
var _ticker_bg: Control
var _ticker_tag: Panel
var _ticker_clip: Control
var _ticker_label: Label
var _final_stamp: Label
var _frames: Array = []          # [harita, oylar, meclis] pencere çerçeveleri
var _pane_now: Array = []        # ekrandaki (yumuşatılmış) pencere dikdörtgenleri
var _content := Rect2()
var _camera := -1
var _cam_flash: ColorRect
var _event_fx: EventFx
var _paper_started := false

func _ready() -> void:
	AudioManager.play_music("election")
	_sim.setup(CardManager.last_province_results, CardManager.last_vote_shares, CardManager.last_seats,
		CardManager.passed_threshold, MultiplayerManager.election_threshold, _seed(), DURATION,
		CardManager.election_alliance_membership())
	_party_order = _sim.peer_ids.duplicate()
	_party_order.sort_custom(func(a, b):
		var ia: Dictionary = _party(a).get("groups", {})
		var ib: Dictionary = _party(b).get("groups", {})
		var ea := float(ia.get("isveren", 50)) - float(ia.get("isci", 50))
		var eb := float(ib.get("isveren", 50)) - float(ib.get("isci", 50))
		if ea != eb:
			return ea < eb
		return int(a) < int(b))
	for peer_id in _sim.peer_ids:
		_display[peer_id] = {"percent": 0.0, "rank": float(_party_order.find(peer_id))}
	_build_ui()
	_event_fx = EventFx.new()
	add_child(_event_fx)
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
	# Her karede: sayım, harita ve meclis kare hızında akar.
	_refresh()
	_refresh_map()
	_animate(delta)
	_update_camera(delta)
	if _finished and not _leaving:
		_hold_left -= delta
		if _hold_left <= 0.0 and not _paper_started:
			_start_paper()
		elif _paper_started and not _event_fx.is_playing():
			_leave()

# --- Veri -> ekran -------------------------------------------------------------

func _refresh() -> void:
	if _bars == null:
		return
	_sample = _sim.sample(_t)
	var counted: float = float(_sample["counted"])
	_counted.text = L.t("AÇILAN SANDIK  %%%.1f") % counted
	_progress_fill.size = Vector2(_progress_bg.size.x * counted / 100.0, _progress_bg.size.y)
	var minutes := 21 * 60 + int(_t / DURATION * 300.0)
	_clock.text = "%02d:%02d" % [(minutes / 60) % 24, minutes % 60]

	var national: Dictionary = _sample["national"]
	var ranked: Array = _sim.peer_ids.duplicate()
	if counted > 0.0:
		# HİSTEREZİS: oyları neredeyse eşit iki parti her karede yer değiştirip
		# satırları yarı yolda bırakıyordu; fark RANK_HYSTERESIS'i geçmedikçe
		# önceki sıra korunur.
		ranked.sort_custom(func(a, b):
			var diff := float(national[a]) - float(national[b])
			if absf(diff) > (0.0 if _finished else RANK_HYSTERESIS):
				return diff > 0.0
			var ra := float(_targets.get(a, {}).get("rank", 0.0))
			var rb := float(_targets.get(b, {}).get("rank", 0.0))
			if ra != rb:
				return ra < rb
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
	_majority_label.text = L.t("Salt çoğunluk %d  ·  Vekil %d/%d") % [
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
		key += "%s;" % province_id
	# İl renkleri her karede (sadece küçük palet dokusu güncellenir); vekil
	# kareleri sadece dağılım değişince yeniden kurulur.
	_map.set_province_colors(colors)
	if key == _last_map_key:
		return
	_last_map_key = key
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
		# İvme: yavaş ortalamaya göre yükselen ▲ / düşen ▼ (sayım sürerken).
		d["slow"] = lerpf(float(d.get("slow", 0.0)), float(target["percent"]), 1.0 - exp(-1.2 * delta))
		var trend := 0.0 if _finished else float(target["percent"]) - float(d["slow"])
		d["rank"] = lerpf(float(d["rank"]), float(target["rank"]), k * 0.7)
		rows.append({
			"name": _party_name(peer_id), "leader": _leader_name(peer_id), "color": _party_color(peer_id),
			"icon": _party_icon(peer_id),
			"percent": d["percent"], "rank": d["rank"], "seats": target["seats"], "below": target["below"],
			"trend": trend, "alliance": _alliance_label(peer_id), "alliance_color": _alliance_color(peer_id),
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
	while _flash_queue.size() > 2:  # geride kalmasın: canlı yayın
		_flash_queue.pop_front()

func _detect_events() -> void:
	var counted := float(_sample["counted"])
	if counted <= 0.0 or _finished:
		return
	var national: Dictionary = _sample["national"]
	if not _first_fired:
		_first_fired = true
		_push_flash(L.t("İLK SONUÇLAR"), L.t("Sandıklar açılmaya başladı — sonuçlar kesin değildir"))

	var leader = _top_peer(national)
	if counted >= 6.0 and leader != _leader:
		if _leader != -1 and _t - _leader_since > 3.0:
			_push_flash(L.t("SON DAKİKA"), L.t("%s öne geçti!  (%%%.1f)") % [_party_name(leader), float(national[leader])])
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
				_push_flash(L.t("BARAJ"), L.t("%s barajın %s  (%%%.1f)") % [_party_name(peer_id),
					L.t("üzerine çıktı!") if above else L.t("altına düştü!"), float(national[peer_id])])

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
				L.t("Sandıkların tamamı açıldı — birinci %s  (%%%.1f)") % [_party_name(winner), float(shares[winner])])

	if counted >= 40.0:
		var seats: Dictionary = _sample["seats"]
		for peer_id in seats.keys():
			if int(seats[peer_id]) * 2 > _sim.total_seats and not _majority_fired.has(peer_id):
				_majority_fired[peer_id] = true
				_push_flash(L.t("ÇOĞUNLUK"), L.t("%s tek başına çoğunluğu yakaladı!  (%d vekil)") % [_party_name(peer_id), int(seats[peer_id])])

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
		_push_flash(L.t("SONUÇ"), L.t("Tüm sandıklar açıldı. Kesin olmayan sonuçlara göre birinci parti: %s  (%%%.1f · %d vekil)") % [
			_party_name(winner), float(national[winner]), int(_sample["seats"].get(winner, 0))])
	_final_stamp.visible = true
	_ticker_label.text = _ticker_text()

func _ticker_text() -> String:
	var parts: Array = []
	var counted := float(_sample.get("counted", 0.0))
	var national: Dictionary = _sample.get("national", {})
	if counted > 0.0:
		parts.append(L.t("AÇILAN SANDIK %%%.1f") % counted)
		var ids: Array = national.keys()
		ids.sort_custom(func(a, b): return float(national[a]) > float(national[b]))
		for peer_id in ids:
			parts.append("%s %%%.1f" % [_party_name(peer_id), float(national[peer_id])])
	parts.append(L.t(FLAVOR[_ticker_round % FLAVOR.size()]))
	_ticker_round += 1
	return "     ·     ".join(PackedStringArray(parts))

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")

# --- Parti bilgisi ---------------------------------------------------------------

func _party(peer_id) -> Dictionary:
	return PartyManager.data_of(peer_id)

func _party_name(peer_id) -> String:
	return String(_party(peer_id).get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?")))

## İTTİFAK (0.0.226): seçime ittifakla giren partinin satırında ittifakın adı
## ve o anki ortak oyu; çubuğun solunda ittifak renginde şerit.
func _alliance_label(peer_id) -> String:
	var aid := int(CardManager.election_alliance_membership().get(int(peer_id), 0))
	if aid == 0:
		return ""
	var total := 0.0
	var national: Dictionary = _sample.get("national", {})
	for pid in CardManager.last_election_alliances[aid].get("members", []):
		total += float(national.get(pid, national.get(int(pid), 0.0)))
	return L.t("%s %%%.1f") % [String(CardManager.last_election_alliances[aid].get("name", "")), total]

func _alliance_color(peer_id) -> Color:
	var aid := int(CardManager.election_alliance_membership().get(int(peer_id), 0))
	return Color(CardManager.last_election_alliances[aid].get("color", Color.TRANSPARENT)) if aid != 0 else Color.TRANSPARENT

func _leader_name(peer_id) -> String:
	return PoliticianPresets.display_name(int(peer_id))

## Parti logosu (seçim gecesi çubuklarında rengin üstüne çizilir).
func _party_icon(peer_id) -> Texture2D:
	var party := _party(peer_id)
	if not party.has("icon_index"):
		return null
	return PartyPresets.get_icon_texture(int(party["icon_index"]), 64)

func _party_color(peer_id) -> Color:
	var color: Color = _party(peer_id).get("bg_color", Color(0.5, 0.5, 0.5))
	color.a = 1.0
	return color

# --- Arayüz kurulumu ---------------------------------------------------------------

func _build_ui() -> void:
	add_child(TableSurface.felt())

	for i in 3:
		var frame := Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
		_frames.append(frame)
	_style_frames(-1)

	_map = (load("res://scenes/Map.tscn") as PackedScene).instantiate()
	add_child(_map)

	_top_bar = TableSurface.wood("band")
	add_child(_top_bar)
	_live_badge = _panel(RED)
	_top_bar.add_child(_live_badge)
	_live_label = _label(L.t("CANLI"), 20, Color.WHITE)
	_live_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_live_badge.add_child(_live_label)
	_title = _label(L.t("SEÇİM GECESİ  ·  ÖZEL YAYIN"), 26, Color.WHITE)
	_top_bar.add_child(_title)
	_subtitle = _label("%s  ·  %s" % [GameRules.election_label(CardManager.last_election_round).to_upper(),
		L.t("ERKEN SEÇİM") if CardManager.last_election_was_early else L.t("GENEL SEÇİM")], 14, UiTheme.WOOD_TEXT_MUTED)
	_top_bar.add_child(_subtitle)
	_clock = _label("21:00", 34, Color.WHITE)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top_bar.add_child(_clock)
	_counted = _label("", 22, UiTheme.WOOD_TEXT)
	_counted.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top_bar.add_child(_counted)

	_progress_bg = ColorRect.new()
	_progress_bg.color = UiTheme.SLOT
	_progress_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_progress_bg)
	_progress_fill = ColorRect.new()
	_progress_fill.color = GOLD
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(_progress_fill)

	_section_map = _label(L.t("SANDIK HARİTASI"), 15, TEXT_DIM)
	add_child(_section_map)
	_section_votes = _label(L.t("OY ORANLARI"), 15, TEXT_DIM)
	add_child(_section_votes)
	_bars = LiveBars.new()
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bars)
	_section_parliament = _label(L.t("MECLİS DAĞILIMI"), 15, TEXT_DIM)
	add_child(_section_parliament)
	_parliament = ParliamentDiagram.new()
	_parliament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_parliament)
	_majority_label = _label("", 12, UiTheme.TEXT_MUTED)
	_majority_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_majority_label)

	_final_stamp = _label(L.t("KESİN OLMAYAN SONUÇLAR"), 22, UiTheme.RED_DARK)
	_final_stamp.visible = false
	add_child(_final_stamp)

	_flash = _panel(UiTheme.GOLD)
	_flash.modulate.a = 0.0
	add_child(_flash)
	var flash_tag_bg := _panel(RED)
	flash_tag_bg.name = L.t("TagBg")
	_flash.add_child(flash_tag_bg)
	_flash_tag = _label("", 18, Color.WHITE)
	_flash_tag.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flash_tag_bg.add_child(_flash_tag)
	_flash_text = _label("", 17, UiTheme.INK, false)
	_flash_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flash_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flash_text.clip_text = true
	_flash.add_child(_flash_text)

	# Kamera geçişinde TV flaşı (pencerelerin üstünde, bantların altında).
	_cam_flash = ColorRect.new()
	_cam_flash.color = Color(1, 1, 1, 0)
	_cam_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cam_flash)

	_ticker_bg = TableSurface.wood("desk")
	add_child(_ticker_bg)
	_ticker_tag = _panel(RED)
	_ticker_bg.add_child(_ticker_tag)
	var ticker_tag_label := _label(L.t("SON DAKİKA"), 18, Color.WHITE)
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
	var menu_reserved := 130.0  # sağ üstteki Menü butonu (SettingsOverlay)
	_clock.position = Vector2(s.x - margin - menu_reserved - 110, 10)
	_clock.size = Vector2(110, 50)
	_counted.position = Vector2(s.x - margin - menu_reserved - 470, 19)
	_counted.size = Vector2(340, 34)
	# Başlık sayaca kadar kalan yere sığsın (İngilizce başlık daha uzun).
	var title_room := _counted.position.x - _title.position.x - 16.0
	var title_font := _title.get_theme_font("font")
	var title_size := 26
	while title_size > 14 and title_font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > title_room:
		title_size -= 1
	_title.add_theme_font_size_override("font_size", title_size)
	_progress_bg.position = Vector2(0, top_h)
	_progress_bg.size = Vector2(s.x, 6)

	var content_top := top_h + 6.0 + margin
	var content_bottom := s.y - bottom_h - margin
	var flash_h := 60.0
	_content = Rect2(margin, content_top, s.x - margin * 2.0, content_bottom - content_top - flash_h - margin)
	_flash.position = Vector2(margin, content_bottom - flash_h)
	_flash.size = Vector2(s.x - margin * 2.0, flash_h)
	_layout_flash()
	_cam_flash.position = _content.position
	_cam_flash.size = _content.size
	_pane_now = _pane_targets()
	_apply_panes()

	_ticker_bg.position = Vector2(0, s.y - bottom_h)
	_ticker_bg.size = Vector2(s.x, bottom_h)
	_ticker_tag.position = Vector2.ZERO
	_ticker_tag.size = Vector2(170, bottom_h)
	_ticker_clip.position = Vector2(182, 0)
	_ticker_clip.size = Vector2(s.x - 182, bottom_h)
	_last_parliament_key = ""
	if not _sample.is_empty():
		_refresh_parliament()

# --- Stüdyo kameraları -----------------------------------------------------------

## Pencere sırası: 0 harita, 1 oy oranları, 2 meclis.
## Sayımın çeyreklerinde büyük pencere: harita → oylar → meclis → harita.
func _camera_index() -> int:
	if _finished:
		return 3
	return [0, 1, 2, 0][mini(3, int(_t / DURATION * 4.0))]

func _pane_targets() -> Array:
	var c := _content
	var gap := 12.0
	if _camera_index() == 3:
		# Sonuç: harita solda, oylar ve meclis sağda (klasik düzen).
		var left_w := c.size.x * 0.55
		var right := Rect2(c.position.x + left_w + gap, c.position.y, c.size.x - left_w - gap, c.size.y)
		var half := (right.size.y - gap) * 0.5
		return [Rect2(c.position, Vector2(left_w, c.size.y)),
			Rect2(right.position, Vector2(right.size.x, half)),
			Rect2(right.position + Vector2(0, half + gap), Vector2(right.size.x, half))]
	var big_w := c.size.x * 0.55
	var small_x := c.position.x + big_w + gap
	var small_w := c.size.x - big_w - gap
	var small_h := (c.size.y - gap) * 0.5
	var big := _camera_index()
	var rects := [Rect2(), Rect2(), Rect2()]
	rects[big] = Rect2(c.position, Vector2(big_w, c.size.y))
	var slot := 0
	for i in 3:
		if i == big:
			continue
		rects[i] = Rect2(small_x, c.position.y + slot * (small_h + gap), small_w, small_h)
		slot += 1
	return rects

func _update_camera(delta: float) -> void:
	if _pane_now.size() < 3:
		return
	var cam := _camera_index()
	if cam != _camera:
		if _camera != -1:
			_cam_flash.color.a = 0.6
		_camera = cam
		_style_frames(cam)
	_cam_flash.color.a = move_toward(_cam_flash.color.a, 0.0, delta * 2.4)
	var targets := _pane_targets()
	var k := 1.0 - exp(-9.0 * delta)
	var moving := false
	for i in 3:
		var now: Rect2 = _pane_now[i]
		var to: Rect2 = targets[i]
		if now.position.distance_to(to.position) + now.size.distance_to(to.size) < 0.6:
			if now != to:
				_pane_now[i] = to
				moving = true
			continue
		_pane_now[i] = Rect2(now.position.lerp(to.position, k), now.size.lerp(to.size, k))
		moving = true
	if moving:
		_apply_panes()

func _style_frames(big: int) -> void:
	for i in _frames.size():
		# Karton pano: büyük pencere hardal kenarlı.
		var box := UiSkin.board(UiTheme.PANEL, GOLD if i == big else UiTheme.TEAL)
		(_frames[i] as Panel).add_theme_stylebox_override("panel", box)

## Pencere dikdörtgenlerini ekrana uygular (pencere başlığı + içerik).
func _apply_panes() -> void:
	if _pane_now.size() < 3:
		return
	var pad := 10.0
	var head := 26.0
	for i in 3:
		var r: Rect2 = _pane_now[i]
		_frames[i].position = r.position.round()
		_frames[i].size = r.size.round()
	# Harita
	var mr: Rect2 = _pane_now[0]
	_map_frame = Rect2(mr.position + Vector2(pad, pad + head), mr.size - Vector2(pad * 2.0, pad * 2.0 + head))
	if GameMap.map_size().x > 0:
		var native: Vector2 = GameMap.map_size()
		var fit: float = minf(_map_frame.size.x / native.x, _map_frame.size.y / native.y)
		_map.scale = Vector2(fit, fit)
		_map.position = _map_frame.position + (_map_frame.size - native * fit) * 0.5
		var seat_markers = _map.get_node_or_null("SeatMarkers")
		if seat_markers != null:
			seat_markers.queue_redraw()
	_section_map.position = mr.position + Vector2(pad, 3)
	_section_map.visible = not _finished
	_final_stamp.position = mr.position + Vector2(pad, 0)
	# Oy oranları
	var br: Rect2 = _pane_now[1]
	_section_votes.position = br.position + Vector2(pad, 3)
	_bars.position = (br.position + Vector2(pad, pad + head)).round()
	_bars.size = (br.size - Vector2(pad * 2.0, pad * 2.0 + head + 12.0)).round()
	# Meclis
	var pr: Rect2 = _pane_now[2]
	_section_parliament.position = pr.position + Vector2(pad, 3)
	_majority_label.position = pr.position + Vector2(pad + 150, 4)
	_majority_label.size = Vector2(maxf(0.0, pr.size.x - pad * 2.0 - 150), 24)
	_parliament.position = (pr.position + Vector2(pad, pad + head)).round()
	_parliament.size = (pr.size - Vector2(pad * 2.0, pad * 2.0 + head)).round()

## Sonuç gazetesi seçim ekranında oynar; bitince (ya da animasyonlar
## kapalıysa hemen) oyun ekranına dönülür.
func _start_paper() -> void:
	_paper_started = true
	var winner := -1
	for peer_id in CardManager.last_seats.keys():
		if winner == -1 or int(CardManager.last_seats[peer_id]) > int(CardManager.last_seats[winner]):
			winner = int(peer_id)
	if winner == -1:
		_leave()
		return
	var seats := int(CardManager.last_seats.get(winner, 0))
	var majority := seats * 2 > _sim.total_seats
	var shown := _event_fx.present("el|%d" % CardManager.last_election_round, {
		"headline": L.t("SANDIKTAN TEK PARTİ ÇOĞUNLUĞU!") if majority else L.t("SANDIKTAN KOALİSYON MECLİSİ ÇIKTI!"),
		"subtitle": L.t("%s seçimi: %s %d vekille birinci (oy oranı %s).") % [
			GameRules.election_label(CardManager.last_election_round), _party_name(winner), seats,
			L.pct(float(CardManager.last_vote_shares.get(winner, 0.0)))] + _alliance_paper_line(),
		"party": winner, "accent": GOLD, "stamp": L.t("BİRİNCİ PARTİ"), "sound": "law_passed",
		"status": L.t("%d VEKİL") % seats})
	if not shown:
		_leave()

## Gazetede seçime giren ittifakların ortak oyu ve vekili (en büyükten).
func _alliance_paper_line() -> String:
	var parts: Array = []
	for aid in CardManager.last_election_alliances:
		var alliance: Dictionary = CardManager.last_election_alliances[aid]
		var votes := 0.0
		var seats := 0
		for pid in alliance.get("members", []):
			votes += float(CardManager.last_vote_shares.get(int(pid), 0.0))
			seats += int(CardManager.last_seats.get(int(pid), 0))
		parts.append([seats, L.t("%s %s · %d vekil") % [String(alliance.get("name", "")), L.pct(votes), seats]])
	if parts.is_empty():
		return ""
	parts.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var texts: Array[String] = []
	for p in parts:
		texts.append(String(p[1]))
	return " " + "; ".join(PackedStringArray(texts)) + "."

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
	UiSkin.apply_style(panel, "panel", UiSkin.flat(color, UiTheme.RADIUS_S))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel

func _label(text: String, font_size: int, color: Color, outline: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline:
		label.add_theme_color_override("font_outline_color", UiTheme.INK)
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
		# Rakamlar ve parti adları monospace: yayın grafiği havası (bkz. UiTheme).
		var font: Font = UiTheme.mono()
		var n := rows.size()
		var row_h: float = minf(60.0, size.y / float(n))
		var h: float = row_h - 8.0
		var name_w: float = minf(250.0, size.x * 0.36)
		var value_w := 104.0
		var bar_x := name_w + 24.0
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
			# Parti rozeti: renkli kare + logo.
			var badge: float = minf(h, 44.0)
			var stripe: Color = r.get("alliance_color", Color.TRANSPARENT)
			if stripe.a > 0.0:
				draw_rect(Rect2(0, y + 2, 5, h), Color(stripe, alpha))
			var badge_rect := Rect2(9 if stripe.a > 0.0 else 0, y + 2 + (h - badge) * 0.5, badge, badge)
			draw_rect(badge_rect, Color(color, alpha))
			var icon: Texture2D = r.get("icon")
			if icon != null:
				draw_texture_rect(icon, badge_rect.grow(-badge * 0.14), false, Color(1, 1, 1, alpha))
			var text_x := badge_rect.end.x + 8.0
			draw_string(font, Vector2(text_x, y + h * 0.5 + 2), String(r["name"]), HORIZONTAL_ALIGNMENT_LEFT,
				name_w - text_x, name_size, Color(UiTheme.TEXT, alpha))
			var sub_line := String(r["leader"])
			var sub_color := Color(UiTheme.TEXT_MUTED, alpha)
			if String(r.get("alliance", "")) != "":
				sub_line = String(r["alliance"])
				sub_color = Color(stripe.darkened(0.3), alpha)
			draw_string(font, Vector2(text_x, y + h * 0.5 + 4 + name_size * 0.8), sub_line, HORIZONTAL_ALIGNMENT_LEFT,
				name_w - text_x, maxi(9, name_size - 6), sub_color)
			var trend := float(r.get("trend", 0.0))
			if absf(trend) > 0.08:
				var cx := bar_x - 10.0
				var cy := y + 2 + h * 0.5
				var a := minf(7.0, h * 0.3)
				var up := trend > 0.0
				var base_y := cy + (a * 0.6 if up else -a * 0.6)
				var tip_y := cy + (-a * 0.7 if up else a * 0.7)
				draw_colored_polygon(PackedVector2Array([Vector2(cx - a, base_y), Vector2(cx + a, base_y), Vector2(cx, tip_y)]),
					Color(UiTheme.GREEN if up else UiTheme.RED, alpha))
			draw_rect(Rect2(bar_x, y + 2, bar_w, h), Color(UiTheme.SLOT, alpha))
			var fill: float = bar_w * clampf(float(r["percent"]) / scale, 0.0, 1.0)
			draw_rect(Rect2(bar_x, y + 2, fill, h), Color(color, alpha))
			draw_rect(Rect2(bar_x, y + 2, fill, maxf(2.0, h * 0.12)), Color(UiTheme.TEXT, 0.25 * alpha))
			draw_string(font, Vector2(size.x - value_w, y + h * 0.5 + 4), L.t("%%%.1f") % float(r["percent"]),
				HORIZONTAL_ALIGNMENT_RIGHT, value_w, clampi(int(h * 0.45), 12, 24), Color(UiTheme.TEXT, alpha))
			var sub := L.t("BARAJ ALTI") if below else L.t("%d vekil") % int(r["seats"])
			draw_string(font, Vector2(size.x - value_w, y + h * 0.5 + 6 + name_size * 0.8), sub,
				HORIZONTAL_ALIGNMENT_RIGHT, value_w, maxi(9, name_size - 6),
				UiTheme.RED if below else UiTheme.TEXT_MUTED)
		if threshold > 0.0:
			var tx: float = bar_x + bar_w * clampf(threshold / scale, 0.0, 1.0)
			var yy := 0.0
			while yy < row_h * n:
				draw_line(Vector2(tx, yy), Vector2(tx, minf(yy + 6.0, row_h * n)), UiTheme.RED, 3.0)
				yy += 11.0
			draw_string(font, Vector2(tx + 4, row_h * n + 12), L.t("BARAJ %%%s") % String.num(threshold, 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.RED)
