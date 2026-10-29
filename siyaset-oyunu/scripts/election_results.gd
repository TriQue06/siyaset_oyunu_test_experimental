extends Control
## Sabit seçim masası: harita, hover edilen il, en büyük üç il, oylar ve meclis.
## Sayım yalnız gösterimdir; gazete ve sonraki oyun aşaması kesin host sonucunu kullanır.

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
var _canvas: Control
var _province_cards: Array = []
var _largest_provinces: Array = []
var _hovered_province := ""
var _map_sea: Panel
var _meclis_count: Label
var _threshold_label: Label
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
	_refresh_left -= delta
	_map_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = REFRESH_INTERVAL
		_refresh()
	if _map_refresh_left <= 0.0:
		_map_refresh_left = 0.18
		_refresh_map()
	_animate(delta)

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
	var minutes := 19 * 60 + int(minf(1.0, _t / (DURATION * ElectionNightSim.SETTLE)) * 300.0)
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
	_refresh_province_cards()
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
	_parliament._count_plate.hide()
	_meclis_count.text = "%d / %d" % [assigned, _sim.total_seats]
	_refresh_province_cards()

func _refresh_map() -> void:
	if _map == null or _sample.is_empty():
		return
	var colors := {}
	for id in _sample["provinces"]:
		var p: Dictionary = _sample["provinces"][id]
		var winner = _top_peer(p["shares"])
		colors[id] = UNCOUNTED if float(p["c"]) <= 0 else _party_color(winner).lerp(UNCOUNTED, (1.0 - float(p["c"])) * 0.6)
	_map.replace_province_colors(colors)

func _province_winner(_seats: Dictionary, shares: Dictionary):
	return _top_peer(shares)

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
			"percent": d["percent"], "rank": target["rank"], "seats": target["seats"], "below": target["below"],
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
	var target_alpha := 1.0 if _flash_text.text != "" else 0.0
	_flash.modulate.a = move_toward(_flash.modulate.a, target_alpha, delta * 5.0)

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
	_final_stamp.visible = false
	_live_label.text = L.t("SONUÇ")
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
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.add_child(TableSurface.felt())

	for i in 3:
		var frame := Panel.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(frame)
		_frames.append(frame)
	_style_frames(-1)

	_map = (load("res://scenes/Map.tscn") as PackedScene).instantiate()
	_canvas.add_child(_map)

	_top_bar = TableSurface.wood("band")
	_canvas.add_child(_top_bar)
	_live_badge = _panel(RED)
	_top_bar.add_child(_live_badge)
	_live_label = _label(L.t("CANLI"), 20, Color.WHITE)
	_live_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_live_badge.add_child(_live_label)
	_title = _label(L.t("SEÇİM GECESİ"), 26, Color.WHITE)
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
	_canvas.add_child(_progress_bg)
	_progress_fill = ColorRect.new()
	_progress_fill.color = GOLD
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bg.add_child(_progress_fill)

	_section_map = _label(L.t("Ülke sandık başında"), 15, TEXT_DIM)
	_canvas.add_child(_section_map)
	_section_votes = _label(L.t("Ülke geneli"), 15, TEXT_DIM)
	_canvas.add_child(_section_votes)
	_threshold_label = _label(L.t("BARAJ %%%s") % String.num(MultiplayerManager.election_threshold, 1), 11, UiTheme.TEXT_MUTED)
	_threshold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_canvas.add_child(_threshold_label)
	_bars = LiveBars.new()
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_bars)
	_section_parliament = _label(L.t("Meclis"), 15, TEXT_DIM)
	_canvas.add_child(_section_parliament)
	_parliament = ParliamentDiagram.new()
	_parliament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_parliament)
	_majority_label = _label("", 12, UiTheme.TEXT_MUTED)
	_majority_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_canvas.add_child(_majority_label)

	_final_stamp = _label(L.t("KESİN OLMAYAN SONUÇLAR"), 22, UiTheme.RED_DARK)
	_final_stamp.visible = false
	_canvas.add_child(_final_stamp)

	_flash = _panel(UiTheme.PANEL_DARK)
	_flash.modulate.a = 0.0
	_canvas.add_child(_flash)
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
	_canvas.add_child(_cam_flash)

	_ticker_bg = TableSurface.wood("desk")
	_canvas.add_child(_ticker_bg)
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


	_subtitle.hide()
	_majority_label.hide()
	_ticker_bg.hide()
	_cam_flash.hide()
	_map_sea = Panel.new()
	_map_sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sea_style := UiSkin.flat(Color("93d2d7"), 10)
	sea_style.border_color = UiTheme.TEAL
	sea_style.set_border_width_all(2)
	_map_sea.add_theme_stylebox_override("panel", sea_style)
	_canvas.add_child(_map_sea)
	_canvas.move_child(_map_sea, _map.get_index())
	_map.draw_sea = false
	_map.get_node("SeatMarkers").hide()
	_meclis_count = _label("", 28, UiTheme.TEAL)
	_meclis_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_canvas.add_child(_meclis_count)
	_map.province_hovered.connect(_on_province_hovered)
	_map.province_clicked.connect(_on_province_hovered)
	_largest_provinces = _sim.province_ids.duplicate()
	var electorate: Dictionary = GameMap.electorate_counts()
	_largest_provinces.sort_custom(func(a, b):
		if int(_sim.province_seats[a]) != int(_sim.province_seats[b]):
			return int(_sim.province_seats[a]) > int(_sim.province_seats[b])
		if int(electorate.get(a, 0)) != int(electorate.get(b, 0)):
			return int(electorate.get(a, 0)) > int(electorate.get(b, 0))
		return String(a) < String(b))
	_largest_provinces = _largest_provinces.slice(0, 3)
	_hovered_province = String(_sim.province_ids[0]) if not _sim.province_ids.is_empty() else ""
	for i in 4:
		var card := ProvinceCard.new()
		card.wide = i == 0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(card)
		_province_cards.append(card)

func _style_frames(_big: int) -> void:
	for frame in _frames:
		frame.add_theme_stylebox_override("panel", UiSkin.board())

func _layout() -> void:
	var screen := get_viewport_rect().size
	var factor := minf(screen.x / 1440.0, screen.y / 810.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (screen - Vector2(1440, 810) * factor) * 0.5
	_canvas.size = Vector2(1440, 810)
	_top_bar.position = Vector2(24, 22)
	_top_bar.size = Vector2(1392, 68)
	_live_badge.position = Vector2(18, 16)
	_live_badge.size = Vector2(80, 36)
	_title.position = Vector2(112, 15)
	_title.add_theme_font_size_override("font_size", 28)
	_counted.position = Vector2(830, 18)
	_counted.size = Vector2(330, 34)
	_clock.position = Vector2(1175, 17)
	_clock.size = Vector2(92, 34)
	_clock.add_theme_font_size_override("font_size", 24)
	_progress_bg.position = Vector2(1010, 73)
	_progress_bg.size = Vector2(160, 5)
	var rects := [Rect2(24, 110, 801, 610), Rect2(843, 110, 573, 300), Rect2(843, 428, 573, 292)]
	for i in 3:
		_frames[i].position = rects[i].position
		_frames[i].size = rects[i].size
	_map_frame = Rect2(42, 158, 765, 360)
	_map_sea.position = _map_frame.position
	_map_sea.size = _map_frame.size
	var native := GameMap.map_size()
	var fit := minf((_map_frame.size.x - 20) / native.x, (_map_frame.size.y - 20) / native.y)
	_map.scale = Vector2.ONE * fit
	_map.position = _map_frame.position + (_map_frame.size - native * fit) * 0.5
	_section_map.position = Vector2(42, 125)
	_section_votes.position = Vector2(861, 125)
	_threshold_label.position = Vector2(1300, 128)
	_threshold_label.size = Vector2(96, 22)
	_section_parliament.position = Vector2(861, 443)
	for label in [_section_map, _section_votes, _section_parliament]:
		label.add_theme_font_size_override("font_size", 20)
	_bars.position = Vector2(861, 157)
	_bars.size = Vector2(537, 235)
	_parliament.position = Vector2(861, 475)
	_parliament.size = Vector2(537, 226)
	_meclis_count.position = Vector2(1000, 664)
	_meclis_count.size = Vector2(260, 40)
	_province_cards[0].position = Vector2(42, 529)
	_province_cards[0].size = Vector2(765, 66)
	for i in 3:
		_province_cards[i + 1].position = Vector2(42 + i * 258, 605)
		_province_cards[i + 1].size = Vector2(249, 96)
	_flash.position = Vector2(24, 738)
	_flash.size = Vector2(1392, 50)
	_layout_flash()

func _on_province_hovered(id: String) -> void:
	if id == "" or not _sim.province_seats.has(id):
		return
	_hovered_province = id
	_refresh_province_cards()

func _refresh_province_cards() -> void:
	if _sample.is_empty():
		return
	var shown := [_hovered_province] + _largest_provinces
	for i in _province_cards.size():
		var card: ProvinceCard = _province_cards[i]
		card.visible = i < shown.size() and String(shown[i]) != ""
		if not card.visible:
			continue
		var id := String(shown[i])
		var p: Dictionary = _sample["provinces"].get(id, {})
		var shares: Dictionary = p.get("shares", {})
		var order: Array = shares.keys()
		order.sort_custom(func(a, b): return float(shares[a]) > float(shares[b]) if shares[a] != shares[b] else int(a) < int(b))
		var entries: Array = []
		for pid in order:
			entries.append({"name": _party_name(pid), "color": _party_color(pid), "percent": shares[pid], "seats": int(p.get("seats", {}).get(pid, 0))})
		card.province_id = id
		card.title = GameMap.name_of(id)
		card.entries = entries
		card.seats = int(_sim.province_seats[id])
		card.counted = float(p.get("c", 0))
		card.queue_redraw()

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
	var threshold := 0.0
	var counted := 0.0
	var _card := UiSkin.card()

	func _draw() -> void:
		var font := UiTheme.mono()
		var rh := size.y / maxf(1, rows.size())
		var fs := clampi(int(rh * 0.42), 12, 17)
		for r in rows:
			var y := float(r["rank"]) * rh
			var color: Color = r["color"]
			var alpha := 0.5 if r["below"] else 1.0
			draw_style_box(_card, Rect2(0, y, size.x, rh - 4))
			var radius := minf(15, rh * 0.3)
			var center := Vector2(21, y + rh * 0.45)
			draw_circle(center + Vector2(0, 2), radius, color.darkened(0.3))
			draw_circle(center, radius, Color(color, alpha))
			var icon: Texture2D = r.get("icon")
			if icon != null:
				draw_texture_rect(icon, Rect2(center - Vector2.ONE * radius * 0.65, Vector2.ONE * radius * 1.3), false, Color(1, 1, 1, alpha))
			draw_string(font, Vector2(45, y + rh * 0.43), String(r["name"]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 195, fs, Color(UiTheme.TEXT, alpha))
			var bar := Rect2(45, y + rh * 0.62, size.x - 195, maxf(4, rh * 0.12))
			draw_style_box(UiSkin.flat(UiTheme.SLOT, 4), bar)
			bar.size.x *= clampf(float(r["percent"]) / 50, 0, 1)
			if bar.size.x > 0:
				draw_style_box(UiSkin.flat(Color(color, alpha), 4), bar)
			if threshold > 0:
				var bx := 45 + (size.x - 195) * clampf(threshold / 50.0, 0, 1)
				draw_line(Vector2(bx, y + rh * 0.62 - 3), Vector2(bx, y + rh * 0.74 + 3), Color(UiTheme.RED, 0.5), 1)
			draw_string(font, Vector2(size.x - 142, y + rh * 0.6), L.pct(float(r["percent"])), HORIZONTAL_ALIGNMENT_RIGHT, 83, fs + 5, Color(UiTheme.TEXT, alpha))
			draw_string(font, Vector2(size.x - 50, y + rh * 0.6), str(r["seats"]), HORIZONTAL_ALIGNMENT_CENTER, 43, fs + 3, Color(UiTheme.TEAL, alpha))

class ProvinceCard extends Control:
	var province_id := ""
	var title := ""
	var entries: Array = []
	var seats := 0
	var counted := 0.0
	var wide := false
	var _card := UiSkin.card()

	func _draw() -> void:
		draw_style_box(_card, Rect2(Vector2.ZERO, size))
		var font := UiTheme.mono()
		var body := UiTheme.body()
		draw_string(font, Vector2(10, 24 if wide else 20), title, HORIZONTAL_ALIGNMENT_LEFT, 150 if wide else size.x - 62, 19 if wide else 16, UiTheme.TEAL)
		if entries.is_empty():
			return
		if wide:
			draw_string(body, Vector2(10, 44), L.t("%d vekil") % seats + " · " + L.pct(counted * 100), HORIZONTAL_ALIGNMENT_LEFT, 145, 10, UiTheme.TEXT_MUTED)
			var bar := Rect2(155, 19, size.x - 250, 6)
			draw_style_box(UiSkin.flat(UiTheme.SLOT, 4), bar)
			bar.size.x *= counted
			if bar.size.x > 0:
				draw_style_box(UiSkin.flat(UiTheme.TEAL, 4), bar)
			for i in mini(3, entries.size()):
				var e: Dictionary = entries[i]
				draw_string(font, Vector2(155 + i * 145, 44), String(e["name"]) + " " + L.pct(float(e["percent"])), HORIZONTAL_ALIGNMENT_LEFT, 140, 11, e["color"])
			var slot := 0
			var columns := 10
			var rows := maxi(1, ceili(float(seats) / columns))
			var spacing := minf(7, 48.0 / rows)
			for e in entries:
				for j in int(e["seats"]):
					draw_circle(Vector2(size.x - 83 + (slot % columns) * 7, 12 + (slot / columns) * spacing), minf(2.7, spacing * 0.4), e["color"])
					slot += 1
		else:
			draw_string(body, Vector2(size.x - 61, 20), L.t("%d vekil") % seats, HORIZONTAL_ALIGNMENT_RIGHT, 50, 10, UiTheme.TEXT_MUTED)
			for i in mini(2, entries.size()):
				var e: Dictionary = entries[i]
				var y := 40 + i * 17
				draw_string(font, Vector2(10, y), String(e["name"]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 80, 12 if i == 0 else 10, e["color"])
				draw_string(font, Vector2(size.x - 68, y), L.pct(float(e["percent"])), HORIZONTAL_ALIGNMENT_RIGHT, 58, 12 if i == 0 else 10, UiTheme.TEXT)
			var bar := Rect2(10, 68, size.x - 20, 5)
			draw_style_box(UiSkin.flat(UiTheme.SLOT, 3), bar)
			bar.size.x *= counted
			if bar.size.x > 0:
				draw_style_box(UiSkin.flat(UiTheme.TEAL, 3), bar)
			draw_string(body, Vector2(size.x - 65, 87), L.pct(counted * 100), HORIZONTAL_ALIGNMENT_RIGHT, 55, 9, UiTheme.TEXT_MUTED)
