class_name EconomyPanel
extends VBoxContainer
## SAĞ SÜTUN · EKONOMİ ÖZETİ (Hükümet sekmesinde, meclisin altında).
##   - başlık + VERGİ şeridi (Düşük / Normal / Yüksek; yürürlükteki vurgulu,
##     dokununca Vergi Politikası paneli açılır),
##   - tek satırda üç gösterge: Ekonomi 0–100, Enflasyon %, İşsizlik %
##     (yanlarında bir önceki tur sonuna göre eğilim),
##   - DEVLET HAZİNESİ şeridi: gerçek bakiye, eğilim, dönem sonu vergi geliri,
##   - (varsa) vergi değişikliğinin yerleşme çubuğu,
##   - seçim bu dönemin sonundaysa (erken ya da takvim) göstergelerin yerine
##     SANDIK ÖNCESİ özeti (sağ sütun yüksekliği sabit: ikisi birden sığmaz).
## Durum tutmaz: her şeyi CardManager.economy'den okur (tek kaynak). Para
## hareketleri (yatırım, tur sonu geliri, vergi değişikliği) play_event ile
## kısa animasyon oynatır; değerler animasyondan bağımsız olarak doğrudur.
##
## Ayrıca VERGİ POLİTİKASI panelinin içeriğini kurar (fill_policy): üç kademe
## kartı, seçilenin ayrıntısı ve meclise sunma düğmesi.

signal tax_policy_requested

const TILE_BG := Color("15112b")
const TILE_BORDER := Color("3f3775")
const TAX_COLORS := [UiTheme.GREEN, UiTheme.GOLD, UiTheme.RED]
const CAPTION_SIZE := 9
const VALUE_SIZE := 14
const DELTA_SIZE := 10
const SEGMENTS := 10

var _tax_buttons: Array = []
var _tiles: Dictionary = {}       # key -> {"panel", "style", "value", "delta"}
var _indicators: HBoxContainer
var _income_label: Label
var _transition: HBoxContainer
var _transition_title: Label
var _transition_bar: Control
var _transition_ratio: float = 0.0
var _transition_text: Label
var _summary: PanelContainer
var _summary_box: VBoxContainer
var _summary_key: String = ""
## Hazine kutusunda gösterilen değer (sayaç animasyonu bunu kaydırır).
var _shown_treasury: float = NAN
var _treasury_tween: Tween

func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_header()
	_indicators = HBoxContainer.new()
	_indicators.add_theme_constant_override("separation", 4)
	add_child(_indicators)
	for entry in [["index", "EKONOMİ", "0–100 arası ekonomi göstergesi (50 olağan). Vergi ve yatırımlarla her dönem yavaşça değişir; hükümet partilerinin seçmen memnuniyetine yansır."],
			["inflation", "ENFLASYON", "Yıllık enflasyon. Düşük vergi ve yoğun yatırım artırır; emeklilerin ve işçilerin hükümete desteğini azaltır."],
			["unemployment", "İŞSİZLİK", "İşsizlik oranı. Ekonomi büyüdükçe düşer."]]:
		_indicators.add_child(_make_tile(String(entry[0]), String(entry[1]), String(entry[2])))
	add_child(_make_treasury_row())
	_build_transition()
	_summary = PanelContainer.new()
	_summary.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_summary)
	_summary_box = VBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 2)
	_summary.add_child(_summary_box)
	_summary.hide()

# --- Kurulum ----------------------------------------------------------------------

func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var title := UiTheme.section_label("EKONOMİ")
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	# VERGİ ŞERİDİ: üç kademe yan yana; yürürlükteki dolu renkli.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	row.add_child(strip)
	var caption := UiTheme.mono_label("VERGİ", CAPTION_SIZE, UiTheme.TEXT_DIM, true)
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(caption)
	for level in Economy.TAX_LEVELS:
		var button := Button.new()
		button.text = Economy.tax_title(level).to_upper()
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", 9)
		button.custom_minimum_size = Vector2(0, 20)
		button.pressed.connect(func(): tax_policy_requested.emit())
		strip.add_child(button)
		_tax_buttons.append(button)

func _make_tile(key: String, caption: String, tip: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.tooltip_text = tip
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = TILE_BG
	style.border_color = TILE_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var cap := UiTheme.mono_label(caption, CAPTION_SIZE, UiTheme.TEXT_DIM, true)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cap)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var value := UiTheme.mono_label("—", VALUE_SIZE, UiTheme.TEXT, true)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	var delta := UiTheme.mono_label("", DELTA_SIZE, UiTheme.TEXT_MUTED, true)
	delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	delta.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(delta)
	_tiles[key] = {"panel": panel, "style": style, "value": value, "delta": delta}
	return panel

## DEVLET HAZİNESİ şeridi: "HAZİNE  613 milyon ₺  ▲140 ........ +96 / dönem".
func _make_treasury_row() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = TILE_BG
	style.border_color = TILE_BORDER
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.content_margin_left = 7
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	var cap := UiTheme.mono_label("HAZİNE", CAPTION_SIZE, UiTheme.TEXT_DIM, true)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(cap)
	var value := UiTheme.mono_label("—", VALUE_SIZE + 1, UiTheme.GOLD, true)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	var unit := UiTheme.mono_label("milyon ₺", DELTA_SIZE, UiTheme.TEXT_MUTED)
	unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(unit)
	var delta := UiTheme.mono_label("", DELTA_SIZE, UiTheme.TEXT_MUTED, true)
	delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(delta)
	_income_label = UiTheme.mono_label("", DELTA_SIZE, UiTheme.TEXT_MUTED)
	_income_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_income_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_income_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_income_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_income_label)
	_tiles["treasury"] = {"panel": panel, "style": style, "value": value, "delta": delta}
	return panel

func _build_transition() -> void:
	_transition = HBoxContainer.new()
	_transition.add_theme_constant_override("separation", 6)
	_transition.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_transition)
	_transition_title = UiTheme.mono_label("", 10, UiTheme.GOLD, true)
	_transition_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition.add_child(_transition_title)
	_transition_bar = Control.new()
	_transition_bar.custom_minimum_size = Vector2(0, 8)
	_transition_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transition_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_transition_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_bar.draw.connect(_draw_transition_bar)
	_transition.add_child(_transition_bar)
	_transition_text = UiTheme.mono_label("", 10, UiTheme.TEXT, true)
	_transition_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition.add_child(_transition_text)

## Parçalı ilerleme çubuğu: dolu parçalar yerleşen etki.
func _draw_transition_bar() -> void:
	var w := _transition_bar.size.x
	var h := _transition_bar.size.y
	var gap := 2.0
	var cell := (w - gap * (SEGMENTS - 1)) / SEGMENTS
	var filled := int(round(_transition_ratio * SEGMENTS))
	for i in SEGMENTS:
		var color := UiTheme.GOLD if i < filled else UiTheme.SLOT
		_transition_bar.draw_rect(Rect2(i * (cell + gap), 0, cell, h), color, true)

# --- Yenileme ------------------------------------------------------------------------

func refresh() -> void:
	var econ: Dictionary = CardManager.economy
	var level := CardManager.tax_level()
	for i in _tax_buttons.size():
		var button := _tax_buttons[i] as Button
		var active := i == level
		UiSkin.skin_color_button(button, TAX_COLORS[i] if active else UiTheme.PANEL_DARK)
		button.add_theme_color_override("font_color", UiTheme.INK if active else UiTheme.TEXT_DIM)
		button.add_theme_color_override("font_hover_color", UiTheme.INK if active else UiTheme.TEXT)
		button.tooltip_text = ("Yürürlükteki vergi: %s.\n" % Economy.tax_title(level) if active else "") \
			+ "Vergi değişikliği meclis oylaması ister: dokun, Vergi Politikası açılsın."
	var prev: Dictionary = econ.get("prev", {})
	_set_tile("index", str(int(round(CardManager.economy_index()))), prev, "index", CardManager.economy_index(), true, false)
	_set_tile("inflation", Economy.percent_text(CardManager.inflation()), prev, "inflation", CardManager.inflation(), false, true)
	_set_tile("unemployment", Economy.percent_text(CardManager.unemployment()), prev, "unemployment", CardManager.unemployment(), false, true)
	if _treasury_tween == null or not _treasury_tween.is_running():
		_shown_treasury = CardManager.state_treasury()
		_show_treasury(_shown_treasury)
	_set_delta("treasury", prev, "treasury", CardManager.state_treasury(), true, false)
	(_tiles["treasury"]["panel"] as Control).tooltip_text = "Devlet hazinesi: %s (partilerin manasından ayrıdır).\nBu dönemin sonunda %s vergi geliri girer (vergi %s, ekonomi %d). Bir yatırım %s.\n▲▼: bir önceki dönem sonuna göre." % [
		Economy.money_full(CardManager.state_treasury()), Economy.money_full(CardManager.expected_revenue()),
		Economy.tax_title(level), int(round(CardManager.economy_index())), Economy.money_full(Economy.INVEST_COST)]
	_income_label.text = "+%s / dönem" % Economy.money_text(CardManager.expected_revenue())
	var election := not election_headline().is_empty()
	# Sandık öncesi: özet göstergelerin yerini alır (hazine ve vergi özette).
	_indicators.visible = not election
	(_tiles["treasury"]["panel"] as Control).visible = not election
	_refresh_transition(econ)
	if election:
		_transition.visible = false
	_refresh_summary()

func _set_tile(key: String, text: String, prev: Dictionary, prev_key: String, now: float, up_good: bool, decimal: bool) -> void:
	(_tiles[key]["value"] as Label).text = text
	_set_delta(key, prev, prev_key, now, up_good, decimal)

## Eğilim: bir önceki tur sonuna göre fark (▲ / ▼), iyi yön yeşil, kötü kırmızı.
func _set_delta(key: String, prev: Dictionary, prev_key: String, now: float, up_good: bool, decimal: bool) -> void:
	var label := _tiles[key]["delta"] as Label
	if not prev.has(prev_key):
		label.text = ""
		return
	var diff := now - float(prev[prev_key])
	var shown := snappedf(diff, 0.1) if decimal else roundf(diff)
	if absf(shown) < (0.1 if decimal else 1.0):
		label.text = "="
		label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		return
	var number := String.num(absf(shown), 1).replace(".", ",") if decimal else Economy.money_text(absf(shown))
	label.text = ("▲" if shown > 0.0 else "▼") + number
	label.add_theme_color_override("font_color", UiTheme.GREEN if (shown > 0.0) == up_good else UiTheme.RED)

func _show_treasury(value: float) -> void:
	(_tiles["treasury"]["value"] as Label).text = Economy.money_text(value)

func _refresh_transition(econ: Dictionary) -> void:
	var settled := Economy.is_settled(econ)
	_transition.visible = not settled
	if settled:
		return
	var cutting := Economy.target_pressure(int(econ["tax"])) < float(econ.get("pressure_from", 0.0))
	_transition_title.text = "İNDİRİM ETKİSİ" if cutting else "ARTIRIM ETKİSİ"
	_transition_ratio = Economy.settle_ratio(econ)
	_transition_text.text = "%%%d · ~%d dönem" % [int(round(_transition_ratio * 100.0)), Economy.rounds_to_settle(econ)]
	_transition.tooltip_text = "Vergi %s → %s. Seçmen memnuniyetindeki değişimin %%%d'i şimdiye kadar yerleşti; kalanı yaklaşık %d dönemde gelir. Seçim olursa sadece yerleşen kısım sayılır." % [
		Economy.tax_title(int(econ.get("tax_from", econ["tax"]))), Economy.tax_title(int(econ["tax"])),
		int(round(_transition_ratio * 100.0)), Economy.rounds_to_settle(econ)]
	_transition_bar.queue_redraw()

# --- Sandık öncesi özet ---------------------------------------------------------------

## Seçim bu dönemin sonunda mı (ya da erken seçim oylanıyor mu)? Başlık + renk.
static func election_headline() -> Array:
	if CardManager.last_seats.is_empty() or CardManager.game_finished:
		return []
	if CardManager.early_election_pending:
		return ["ERKEN SEÇİM · BU DÖNEMİN SONUNDA", UiTheme.RED]
	if GovernmentManager.is_voting() and GovernmentManager.proposal_kind == GovernmentManager.KIND_EARLY:
		return ["ERKEN SEÇİM OYLANIYOR", UiTheme.GOLD]
	if GameRules.is_election_round(CardManager.round_number):
		return ["SEÇİM · BU DÖNEMİN SONUNDA", UiTheme.GOLD]
	return []

func _refresh_summary() -> void:
	var headline := election_headline()
	if headline.is_empty():
		_summary.hide()
		_summary_key = ""
		return
	var key := "%s|%s|%d" % [headline[0], str(CardManager.economy), GovernmentManager.main_gov_peer_id]
	_summary.show()
	if key == _summary_key:
		return
	_summary_key = key
	var color: Color = headline[1]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.08)
	style.border_color = color
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	_summary.add_theme_stylebox_override("panel", style)
	for child in _summary_box.get_children():
		_summary_box.remove_child(child)
		child.queue_free()
	_fill_summary(_summary_box, headline)

## SANDIK ÖNCESİ: görünen durumun özeti (tahmin DEĞİL): vergi ve son
## değişikliğin yerleşmesi, hazine, süren yatırımlar (gerçekleşen / bekleyen),
## hükümetin ekonomiden gelen seçmen memnuniyeti ve yönü.
static func _fill_summary(box: VBoxContainer, headline: Array) -> void:
	var econ: Dictionary = CardManager.economy
	var title := UiTheme.mono_label(String(headline[0]), 10, headline[1], true)
	box.add_child(title)
	var tax_text := Economy.tax_title(int(econ["tax"]))
	if not Economy.is_settled(econ):
		tax_text += " (%s'den) · %%%d yerleşti" % [Economy.tax_title(int(econ.get("tax_from", econ["tax"]))),
			int(round(Economy.settle_ratio(econ) * 100.0))]
	else:
		tax_text += " · yerleşik"
	box.add_child(_summary_row("Vergi", tax_text))
	box.add_child(_summary_row("Hazine", "%s · +%s / dönem" % [Economy.money_full(float(econ["treasury"])),
		Economy.money_text(CardManager.expected_revenue())]))
	var pending: Array = econ.get("investments", [])
	if pending.is_empty():
		box.add_child(_summary_row("Yatırım", "süren yatırım yok"))
	else:
		var after := 0
		for entry in pending:
			after += maxi(0, int(entry["rounds_left"]) - 1)
		box.add_child(_summary_row("Yatırım", "%d il sürüyor · %s" % [pending.size(),
			"%d dilim seçimden sonra" % after if after > 0 else "hepsi seçimden önce biter"]))
	var pm := GovernmentManager.main_gov_peer_id
	if pm == -1 or not GovernmentManager.has_government():
		box.add_child(PopupKit.label("Hükümet yok: ekonomi kimsenin hanesine yazılmıyor.", 10, UiTheme.TEXT_MUTED))
		return
	var mood := CardManager.economy_mood(pm)
	var next_state: Dictionary = econ.duplicate(true)
	Economy.advance(next_state)
	var next_mood := Economy.group_mood(next_state, CardManager.economy_share(pm))
	var ranked: Array = mood.keys()
	ranked.sort_custom(func(a, b): return absf(float(mood[a])) > absf(float(mood[b])))
	# Hükümetin ekonomiden gelen seçmen memnuniyeti: tek satır (simge + değer +
	# yön). Grupların tam adı ipucunda.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var k := PopupKit.label("Seçmen", 10, UiTheme.TEXT_MUTED)
	k.custom_minimum_size = Vector2(52, 0)
	row.add_child(k)
	var tip := PackedStringArray()
	if ranked.is_empty():
		row.add_child(PopupKit.label("ekonominin belirgin etkisi yok", 10, UiTheme.TEXT_DIM))
	for i in mini(3, ranked.size()):
		var group := String(ranked[i])
		var now := float(mood[group])
		var trend := float(next_mood.get(group, 0.0)) - now
		var icon := VoterGroupIcon.make(group, 13.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var arrow := ("▲" if trend > 0.0 else "▼") if absf(trend) >= 0.05 else ""
		row.add_child(UiTheme.mono_label(_signed(now) + arrow, 9, UiTheme.GREEN if now > 0.0 else UiTheme.RED, true))
		tip.append("%s %s%s" % [VoterGroups.title(group), _signed(now),
			(" (gelecek dönem %s)" % ("toparlanıyor" if trend > 0.0 else "kötüleşiyor")) if arrow != "" else ""])
	row.tooltip_text = "%s hükümetinin ekonomiden (vergi, büyüme, enflasyon) gelen seçmen desteği:\n%s" % [
		PartyManager.data_of(pm).get("name", "?"), "\n".join(tip)]
	box.add_child(row)
	box.add_child(PopupKit.label("Görünen durumun özeti; seçim tahmini değildir.", 9, UiTheme.TEXT_DIM))

static func _summary_row(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := PopupKit.label(key, 10, UiTheme.TEXT_MUTED)
	k.custom_minimum_size = Vector2(52, 0)
	row.add_child(k)
	var v := PopupKit.label(value, 10, UiTheme.TEXT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(v)
	return row

# --- Animasyonlar -------------------------------------------------------------------

## CardManager.economy_event: para hareketi ve vergi değişikliği geri bildirimi.
func play_event(data: Dictionary) -> void:
	if not is_visible_in_tree():
		refresh()
		return
	match String(data.get("kind", "")):
		"invest":
			_count_treasury(float(data.get("before", CardManager.state_treasury())), float(data.get("after", CardManager.state_treasury())))
			_float_text("treasury", "−%s" % Economy.money_text(float(data.get("cost", 0.0))), UiTheme.RED)
			_flash("treasury", UiTheme.RED)
		"round":
			var revenue := float(data.get("revenue", 0.0))
			_count_treasury(CardManager.state_treasury() - revenue, CardManager.state_treasury())
			_float_text("treasury", "+%s" % Economy.money_text(revenue), UiTheme.GREEN)
			_flash("treasury", UiTheme.GREEN)
			for key in ["index", "inflation", "unemployment"]:
				_flash(key, UiTheme.GOLD)
		"tax":
			var level := int(data.get("to", CardManager.tax_level()))
			if level >= 0 and level < _tax_buttons.size():
				_pop(_tax_buttons[level])
			for key in ["inflation", "treasury"]:
				_flash(key, TAX_COLORS[clampi(level, 0, 2)])
	refresh()

func _count_treasury(from: float, to: float) -> void:
	if _treasury_tween != null:
		_treasury_tween.kill()
	_shown_treasury = from
	_show_treasury(from)
	_treasury_tween = create_tween()
	_treasury_tween.tween_method(func(v: float):
		_shown_treasury = v
		_show_treasury(v), from, to, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Kutunun çerçevesi bir an olayın renginde parlar.
func _flash(key: String, color: Color) -> void:
	var style := _tiles[key]["style"] as StyleBoxFlat
	style.border_color = color
	style.set_border_width_all(2)
	var tween := create_tween()
	tween.tween_property(style, "border_color", TILE_BORDER, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): style.set_border_width_all(1))

## Kutunun üstünden yükselip sönen tutar ("−100", "+140").
func _float_text(key: String, text: String, color: Color) -> void:
	var panel := _tiles[key]["panel"] as Control
	if not panel.is_visible_in_tree():
		return
	var label := UiTheme.mono_label(text, 13, color, true)
	label.add_theme_color_override("font_outline_color", UiTheme.INK)
	label.add_theme_constant_override("outline_size", 4)
	label.top_level = true
	label.z_index = 20
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var start := panel.global_position + Vector2(panel.size.x - 8.0 - label.get_minimum_size().x, -label.get_minimum_size().y + 4.0)
	label.global_position = start
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", start.y - 18.0, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.35)
	tween.chain().tween_callback(label.queue_free)

func _pop(control: Control) -> void:
	control.pivot_offset = control.size / 2.0
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(1.18, 1.18), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Vergi Politikası paneli ------------------------------------------------------------

## Panel içeriği: başlık, üç kademe kartı, seçilen kademenin ayrıntısı ve
## meclise sunma düğmesi. selected: seçili kademe (-1: henüz seçilmedi).
static func fill_policy(box: VBoxContainer, me: int, selected: int, on_select: Callable, on_propose: Callable, on_close: Callable) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var current := CardManager.tax_level()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := UiTheme.mono_label("VERGİ POLİTİKASI", 14, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(PopupKit.chip("MECLİS ONAYI GEREKİR", UiTheme.GOLD))
	var close := Button.new()
	close.text = "Kapat"
	UiSkin.skin_button(close)
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(on_close)
	header.add_child(close)
	box.add_child(PopupKit.label("Yürürlükte: %s · dönem geliri %s · hazine %s" % [Economy.tax_title(current),
		Economy.money_full(CardManager.expected_revenue()), Economy.money_full(CardManager.state_treasury())], 11, UiTheme.TEXT_MUTED))
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	box.add_child(cards)
	for level in Economy.TAX_LEVELS:
		cards.add_child(_policy_card(me, level, current, selected, on_select))
	box.add_child(UiTheme.rule())
	var detail := VBoxContainer.new()
	detail.add_theme_constant_override("separation", 3)
	box.add_child(detail)
	if selected < 0 or selected == current:
		detail.add_child(PopupKit.note("Bir kademe seç: geliri, seçmene etkisini ve ne zaman yerleşeceğini gör.", UiTheme.TEXT_MUTED, 380))
		var reason := CardManager.tax_law_block_reason(me)
		if reason != "":
			detail.add_child(PopupKit.note("Şu an sunamazsın: " + reason, UiTheme.RED, 380))
		return
	_fill_policy_detail(detail, me, selected, current, on_propose)

## Kademe kartı: ad, dönem geliri ve farkı, seçmen etkisi (simgeler), ekonomi
## yönü; durum: yürürlükte (altın çerçeve), seçili (beyaz), sunulamaz (sönük).
static func _policy_card(me: int, level: int, current: int, selected: int, on_select: Callable) -> Control:
	var is_current := level == current
	var is_selected := level == selected and not is_current
	var available := CardManager.can_propose_tax_law(me, level)
	var color: Color = TAX_COLORS[level]
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(128, 132)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color, 0.16) if is_current else (Color("2a2350") if state == "hover" and not is_current else TILE_BG)
		style.border_color = color if is_current else (UiTheme.TEXT if is_selected else TILE_BORDER)
		style.set_border_width_all(2 if is_current or is_selected else 1)
		style.border_width_top = 4 if is_current or is_selected else 1
		button.add_theme_stylebox_override(state, style)
	button.disabled = is_current
	button.pressed.connect(func(): on_select.call(level))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -6
	box.offset_top = 6
	box.offset_bottom = -4
	button.add_child(box)
	var name := UiTheme.mono_label(Economy.tax_title(level).to_upper(), 13, color, true)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var revenue := CardManager.expected_revenue(level)
	var money := UiTheme.mono_label("+%s" % Economy.money_text(revenue), 16, UiTheme.TEXT, true)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(money)
	var diff := revenue - CardManager.expected_revenue(current)
	var sub := "milyon ₺ / dönem" if is_current else "%s%s / dönem" % ["+" if diff > 0.0 else "−", Economy.money_text(absf(diff))]
	box.add_child(PopupKit.label(sub, 9, UiTheme.TEXT_DIM if is_current else (UiTheme.GREEN if diff > 0.0 else UiTheme.RED)))
	# Seçmen etkisi (tam yerleşince başbakanın partisinde, şimdiki kademeye göre).
	var effects := _tax_mood_change(level, current)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 3)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icons)
	var ranked: Array = effects.keys()
	ranked.sort_custom(func(a, b): return absf(float(effects[a])) > absf(float(effects[b])))
	for i in mini(2, ranked.size()):
		var group := String(ranked[i])
		var icon := VoterGroupIcon.make(group, 14.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons.add_child(icon)
		var amount := float(effects[group])
		icons.add_child(PopupKit.label(_signed(amount), 10, UiTheme.GREEN if amount > 0.0 else UiTheme.RED))
	if ranked.is_empty():
		icons.add_child(PopupKit.label("seçmen: dengeli", 10, UiTheme.TEXT_MUTED))
	var growth := float(Economy.TAX_GROWTH[level]) - float(Economy.TAX_GROWTH[current])
	var econ_text := "ekonomi %s · enflasyon %s" % ["▲" if growth > 0.0 else ("▼" if growth < 0.0 else "="),
		"▲" if level < current else ("▼" if level > current else "=")]
	box.add_child(PopupKit.label(econ_text, 9, UiTheme.TEXT_MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var tag_text := "YÜRÜRLÜKTE" if is_current else ("SEÇİLDİ" if is_selected else ("SEÇ" if available else "SUNULAMAZ"))
	var tag_color: Color = color if is_current else (UiTheme.TEXT if is_selected else (UiTheme.TEXT_MUTED if available else UiTheme.TEXT_DIM))
	box.add_child(PopupKit.chip(tag_text, tag_color))
	if not available and not is_current:
		button.modulate = Color(1, 1, 1, 0.7)
		button.tooltip_text = CardManager.tax_law_block_reason(me, level)
	return button

static func _tax_mood_change(level: int, current: int) -> Dictionary:
	var target := Economy.tax_mood_at(level)
	var base := Economy.tax_mood_at(current)
	var result := {}
	for group in VoterGroups.GROUP_IDS:
		var diff := float(target.get(group, 0.0)) - float(base.get(group, 0.0))
		if absf(diff) >= 0.05:
			result[group] = diff
	return result

static func _fill_policy_detail(detail: VBoxContainer, me: int, level: int, current: int, on_propose: Callable) -> void:
	var law_type := CardPresets.tax_law_type(level)
	detail.add_child(UiTheme.mono_label(CardPresets.card_title(law_type), 13, TAX_COLORS[level], true))
	var revenue_now := CardManager.expected_revenue(current)
	var revenue_new := CardManager.expected_revenue(level)
	detail.add_child(PopupKit.kv("Hazine geliri", "%s → %s milyon ₺ / dönem" % [Economy.money_text(revenue_now), Economy.money_text(revenue_new)],
		UiTheme.GREEN if revenue_new > revenue_now else UiTheme.RED))
	var after := Economy.pressure_after_change(float(CardManager.economy["pressure"]), level)
	var probe := {"tax": level, "pressure": after}
	detail.add_child(PopupKit.kv("Seçmene yansıma", "%%%d hemen · kalanı ~%d dönemde" % [int(round(Economy.TAX_IMMEDIATE * 100.0)),
		Economy.rounds_to_settle(probe)], UiTheme.GOLD))
	detail.add_child(PopupKit.kv("Kimi etkiler", "hükümet partileri (ortaklar %%%d)" % int(round(Economy.PARTNER_SHARE * 100.0))))
	var effects := _tax_mood_change(level, current)
	var ranked: Array = effects.keys()
	ranked.sort_custom(func(a, b): return absf(float(effects[a])) > absf(float(effects[b])))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 1)
	detail.add_child(grid)
	for i in mini(4, ranked.size()):
		var row := VoterGroupUI.effect_row(String(ranked[i]), float(effects[ranked[i]]), 10)
		row.custom_minimum_size = Vector2(180, 0)
		grid.add_child(row)
	detail.add_child(PopupKit.note("Değerler tam yerleşince başbakanın partisinin grup desteğindeki değişimdir; seçim erken gelirse sadece yerleşen kısım sayılır.",
		UiTheme.TEXT_DIM, 380))
	var reason := CardManager.tax_law_block_reason(me, level)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 14)
	if reason == "":
		button.text = "MECLİSE SUN · %s" % GameRules.cost_text(GameRules.LAW_MANA_COST)
		UiSkin.skin_color_button(button, UiTheme.GREEN_DARK)
		button.pressed.connect(func(): on_propose.call(law_type))
	else:
		button.text = "SUNULAMAZ"
		UiSkin.skin_color_button(button, UiTheme.PANEL_DARK)
		button.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		button.disabled = true
	detail.add_child(button)
	if reason != "":
		detail.add_child(PopupKit.note(reason, UiTheme.RED, 380))

static func _signed(value: float) -> String:
	return ("+" if value > 0.0 else "−") + String.num(snappedf(absf(value), 0.1), 1).replace(".", ",")
