class_name EconomyPanel
extends VBoxContainer
## SAĞ SÜTUN · EKONOMİ ÖZETİ (Hükümet sekmesinde, meclisin altında).
##   - başlık + VERGİ şeridi (Düşük / Normal / Yüksek; yürürlükteki vurgulu,
##     dokununca Vergi Politikası paneli açılır),
##   - DEVLET HAZİNESİ şeridi: gerçek bakiye, eğilim, dönem sonu vergi geliri,
##   - VERGİ ETKİSİ: hükümete her sırada yazılan ulusal puan (seçime yaklaştıkça
##     artar; 0.0.259: ekonomi göstergeleri ve kademeli yerleşme kalktı),
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
var _income_label: Label
var _tax_effect: Label
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
	add_child(_make_treasury_row())
	_tax_effect = UiTheme.mono_label("", DELTA_SIZE, UiTheme.TEXT_MUTED, true)
	_tax_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tax_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_tax_effect)
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
	var title := UiTheme.section_label(L.t("BÜTÇE"))
	title.add_theme_font_size_override("font_size", 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	# VERGİ ŞERİDİ: üç kademe yan yana; yürürlükteki dolu renkli.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	row.add_child(strip)
	var caption := UiTheme.mono_label(L.t("VERGİ"), CAPTION_SIZE, UiTheme.TEXT_DIM, true)
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

func _make_tile(key: String, caption: String, _tip: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = TILE_BG
	style.border_color = TILE_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 5
	style.content_margin_top = 1
	style.content_margin_bottom = 2
	UiSkin.apply_style(panel, "panel", style)
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

## DEVLET HAZİNESİ şeridi: "HAZİNE  613 milyon ¤  ▲140 ........ +96 / dönem".
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
	UiSkin.apply_style(panel, "panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	var cap := UiTheme.mono_label(L.t("HAZİNE"), CAPTION_SIZE, UiTheme.TEXT_DIM, true)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(cap)
	# Para simgesi tutarın solunda ("¤ 200 M").
	var icon := UiTheme.mono_label(L.t("¤"), VALUE_SIZE + 1, UiTheme.GOLD, true)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon)
	var value := UiTheme.mono_label("—", VALUE_SIZE + 1, UiTheme.GOLD, true)
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value)
	var unit := UiTheme.mono_label(L.t("M"), DELTA_SIZE, UiTheme.TEXT_MUTED)
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
	var prev: Dictionary = econ.get("prev", {})
	if _treasury_tween == null or not _treasury_tween.is_running():
		_shown_treasury = CardManager.state_treasury()
		_show_treasury(_shown_treasury)
	_set_delta("treasury", prev, "treasury", CardManager.state_treasury(), true, false)
	_income_label.text = L.t("+%s / dönem") % GameRules.amount(CardManager.expected_revenue())
	var election := not election_headline().is_empty()
	# Sandık öncesi: özet hazine ve vergi satırlarının yerini alır.
	(_tiles["treasury"]["panel"] as Control).visible = not election
	_tax_effect.visible = not election
	var effect := tax_effect_text()
	_tax_effect.text = effect[0]
	_tax_effect.add_theme_color_override("font_color", effect[1])
	_refresh_summary()

## VERGİ ETKİSİ satırı: [metin, renk], sayısız (0.0.260). Hükümet yoksa
## kimsenin hanesine yazılmaz.
static func tax_effect_text() -> Array:
	if not GovernmentManager.has_government():
		return [L.t("Hükümet yok: vergi kimseyi etkilemez"), UiTheme.TEXT_MUTED]
	var total := CardManager.tax_turn_effect()
	if is_zero_approx(total):
		return [L.t("Normal vergi: seçmene etkisi yok"), UiTheme.TEXT_MUTED]
	if total > 0.0:
		return [L.t("Düşük vergi: hükümete her sıra artı"), UiTheme.GREEN]
	return [L.t("Yüksek vergi: hükümete her sıra eksi"), UiTheme.RED]

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
	# Göstergelerde sadece yön; hazinede tutar da yazar (gerçek para hareketi).
	var number := Economy.money_text(absf(shown)) if key == "treasury" else ""
	label.text = ("▲" if shown > 0.0 else "▼") + number
	label.add_theme_color_override("font_color", UiTheme.GREEN if (shown > 0.0) == up_good else UiTheme.RED)

func _show_treasury(value: float) -> void:
	(_tiles["treasury"]["value"] as Label).text = Economy.money_text(value)

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
	UiSkin.apply_style(_summary, "panel", style)
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
	box.add_child(_summary_row(L.t("Vergi"), "%s · %s" % [Economy.tax_title(int(econ["tax"])), String(tax_effect_text()[0])]))
	box.add_child(_summary_row(L.t("Hazine"), L.t("%s · +%s / dönem") % [Economy.money_full(float(econ["treasury"])),
		GameRules.amount(CardManager.expected_revenue())]))
	var pending: Array = econ.get("investments", [])
	if pending.is_empty():
		box.add_child(_summary_row(L.t("Yatırım"), L.t("süren yatırım yok")))
	else:
		var after := 0
		for entry in pending:
			after += maxi(0, int(entry["rounds_left"]) - 1)
		box.add_child(_summary_row(L.t("Yatırım"), L.t("%d il sürüyor · %s") % [pending.size(),
			L.t("%d dilim seçimden sonra") % after if after > 0 else L.t("hepsi seçimden önce biter")]))
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
			if float(data.get("cost", 0.0)) <= 0.0:
				refresh()
				return  # tamamı parti kasasından: hazine değişmedi
			_count_treasury(float(data.get("before", CardManager.state_treasury())), float(data.get("after", CardManager.state_treasury())))
			_float_text("treasury", "−%s" % GameRules.amount(float(data.get("cost", 0.0))), UiTheme.RED)
			_flash("treasury", UiTheme.RED)
		"round":
			var revenue := float(data.get("revenue", 0.0))
			_count_treasury(CardManager.state_treasury() - revenue, CardManager.state_treasury())
			_float_text("treasury", "+%s" % GameRules.amount(revenue), UiTheme.GREEN)
			_flash("treasury", UiTheme.GREEN)
		"tax":
			var level := int(data.get("to", CardManager.tax_level()))
			if level >= 0 and level < _tax_buttons.size():
				_pop(_tax_buttons[level])
			_flash("treasury", TAX_COLORS[clampi(level, 0, 2)])
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
## show_header false: başlık ve Kapat yok (yasa panelinin VERGİ sekmesi).
static func fill_policy(box: VBoxContainer, me: int, selected: int, on_select: Callable, on_propose: Callable, on_close: Callable, show_header: bool = true) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var current := CardManager.tax_level()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	if show_header:
		var title := UiTheme.mono_label(L.t("VERGİ POLİTİKASI"), 14, UiTheme.TEXT, true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
	header.add_child(PopupKit.chip(L.t("MECLİS ONAYI GEREKİR"), UiTheme.GOLD))
	if show_header:
		var close := Button.new()
		close.text = L.t("Kapat")
		UiSkin.skin_button(close)
		close.add_theme_font_size_override("font_size", 11)
		close.pressed.connect(on_close)
		header.add_child(close)
	box.add_child(PopupKit.label(L.t("Yürürlükte: %s · dönem geliri %s · hazine %s") % [Economy.tax_title(current),
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
		detail.add_child(PopupKit.note(L.t("Bir kademe seç: geliri ve seçmene etkisini gör."), UiTheme.TEXT_MUTED, 380))
		var reason := CardManager.tax_law_block_reason(me)
		if reason != "":
			detail.add_child(PopupKit.note(L.t("Şu an sunamazsın: ") + reason, UiTheme.RED, 380))
		return
	_fill_policy_detail(detail, me, selected, current, on_propose)

## Kademe kartı: ad, dönem geliri ve farkı, sıra başı seçmen etkisi; durum: yürürlükte (altın çerçeve), seçili (beyaz), sunulamaz (sönük).
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
		UiSkin.apply_style(button, state, style)
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
	var money := UiTheme.mono_label(L.t("¤ %s") % ("+" + GameRules.amount(revenue)), 16, UiTheme.TEXT, true)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(money)
	var diff := revenue - CardManager.expected_revenue(current)
	var sub := L.t("dönem başına") if is_current else L.t("%s%s / dönem") % ["+" if diff > 0.0 else "−", GameRules.amount(absf(diff))]
	box.add_child(PopupKit.label(sub, 9, UiTheme.TEXT_DIM if is_current else (UiTheme.GREEN if diff > 0.0 else UiTheme.RED)))
	# Seçmen etkisi: hükümete her sırada (bu turun çarpanıyla).
	var effect := CardManager.tax_turn_effect(level)
	var effect_text := L.t("seçmen: etkisiz") if is_zero_approx(effect) else (L.t("seçmen: artı") if effect > 0.0 else L.t("seçmen: eksi"))
	box.add_child(PopupKit.label(effect_text, 10, UiTheme.TEXT_MUTED if is_zero_approx(effect) else (UiTheme.GREEN if effect > 0.0 else UiTheme.RED)))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var tag_text := L.t("YÜRÜRLÜKTE") if is_current else (L.t("SEÇİLDİ") if is_selected else (L.t("SEÇ") if available else L.t("SUNULAMAZ")))
	var tag_color: Color = color if is_current else (UiTheme.TEXT if is_selected else (UiTheme.TEXT_MUTED if available else UiTheme.TEXT_DIM))
	box.add_child(PopupKit.chip(tag_text, tag_color))
	if not available and not is_current:
		button.modulate = Color(1, 1, 1, 0.7)
	return button

static func _fill_policy_detail(detail: VBoxContainer, me: int, level: int, current: int, on_propose: Callable) -> void:
	var law_type := CardPresets.tax_law_type(level)
	detail.add_child(UiTheme.mono_label(CardPresets.card_title(law_type), 13, TAX_COLORS[level], true))
	var revenue_now := CardManager.expected_revenue(current)
	var revenue_new := CardManager.expected_revenue(level)
	detail.add_child(PopupKit.kv(L.t("Hazine geliri"), L.t("%s → %s / dönem") % [Economy.money_full(revenue_now), Economy.money_full(revenue_new)],
		UiTheme.GREEN if revenue_new > revenue_now else UiTheme.RED))
	var effect := CardManager.tax_turn_effect(level)
	var effect_word := L.t("etkisi yok") if is_zero_approx(effect) else (L.t("hükümete her sıra artı") if effect > 0.0 else L.t("hükümete her sıra eksi"))
	detail.add_child(PopupKit.kv(L.t("Seçmene yansıma"), effect_word,
		UiTheme.GREEN if effect > 0.0 else (UiTheme.RED if effect < 0.0 else UiTheme.TEXT_MUTED)))
	detail.add_child(PopupKit.kv(L.t("Kimi etkiler"), L.t("hükümet partileri, bakanlık payına göre")))
	detail.add_child(PopupKit.note(L.t("Etki seçime yaklaştıkça artar."), UiTheme.TEXT_DIM, 380))
	var reason := CardManager.tax_law_block_reason(me, level)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 36)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 14)
	if reason == "":
		button.text = L.t("MECLİSE SUN · %s") % GameRules.cost_text(GameRules.LAW_FUNDS_COST)
		UiSkin.skin_color_button(button, UiTheme.GREEN_DARK)
		button.pressed.connect(func(): on_propose.call(law_type))
	else:
		button.text = L.t("SUNULAMAZ")
		UiSkin.skin_color_button(button, UiTheme.PANEL_DARK)
		button.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		button.disabled = true
	detail.add_child(button)
	if reason != "":
		detail.add_child(PopupKit.note(reason, UiTheme.RED, 380))


static func _signed(value: float) -> String:
	return ("+" if value > 0.0 else "−") + String.num(snappedf(absf(value), 0.1), 1).replace(".", ",")
