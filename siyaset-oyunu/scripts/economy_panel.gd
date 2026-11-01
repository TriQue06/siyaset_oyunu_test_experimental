class_name EconomyPanel
extends VBoxContainer
## SAĞ SÜTUN · EKONOMİ ÖZETİ (Hükümet sekmesinde, meclisin altında).
##   - başlık + VERGİ şeridi (Düşük / Normal / Yüksek; yürürlükteki vurgulu,
##     dokununca Vergi paneli o kademeyle açılır),
##   - HAZİNE kartı (0.0.313 sade): solda devlet hazinesi, sağda dönem geliri,
##     altında tek satır: vergi seçmene olumlu / olumsuz / etkisiz,
##   - seçim bu dönemin sonundaysa (erken ya da takvim) kartın yerine
##     SANDIK ÖNCESİ özeti (sağ sütun yüksekliği sabit: ikisi birden sığmaz).
## Durum tutmaz: her şeyi CardManager.economy'den okur (tek kaynak). Para
## hareketleri (yatırım, tur sonu geliri, vergi değişikliği) play_event ile
## kısa animasyon oynatır; değerler animasyondan bağımsız olarak doğrudur.
##
## Ayrıca VERGİ panelinin içeriğini kurar (fill_policy): üç kademe kartı
## (gelir + seçmene etkisi) ve meclise sunma düğmesi.

signal tax_policy_requested(level: int)

const TILE_BG := UiTheme.PANEL_DARK
const TILE_BORDER := UiTheme.PANEL_LIGHT
const TAX_COLORS := [UiTheme.GREEN, UiTheme.GOLD, UiTheme.RED]

var _tax_buttons: Array = []
var _styled_tax_level := -1
var _tiles: Dictionary = {}       # key -> {"panel", "style", "value"}
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
	title.add_theme_font_size_override("font_size", 13)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	# VERGİ ŞERİDİ: üç kademe yan yana; yürürlükteki dolu renkli.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", int(UiTheme.d(6)))
	row.add_child(strip)
	var caption := UiTheme.mono_label(L.t("VERGİ"), UiTheme.fs(12), UiTheme.TEXT_MUTED)
	caption.add_theme_font_override("font", UiTheme.mono_regular())
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_child(caption)
	for level in Economy.TAX_LEVELS:
		var button := Button.new()
		button.text = Economy.tax_title(level).to_upper()
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", UiTheme.fs(13))
		button.custom_minimum_size = Vector2(0, UiTheme.d(30))
		button.pressed.connect(func(): tax_policy_requested.emit(level))
		strip.add_child(button)
		_tax_buttons.append(button)

## HAZİNE kartı: solda bakiye, sağda dönem geliri; altında seçmen etkisi.
func _make_treasury_row() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# Konsept .treas: beyaz kart, ince kenar, 3 px kalınlık.
	var style := UiSkin.card(UiTheme.PANEL_DARK, UiTheme.PANEL_LIGHT, UiTheme.CARD_LIP, 3.0)
	style.set_radius(UiTheme.d(12))
	style.content_margin_left = UiTheme.d(14)
	style.content_margin_right = UiTheme.d(14)
	style.content_margin_top = UiTheme.d(6)
	style.content_margin_bottom = UiTheme.d(8)
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(UiTheme.d(8)))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(line)
	var left := _figure(L.t("HAZİNE"), UiTheme.fs(28), UiTheme.MONEY, HORIZONTAL_ALIGNMENT_LEFT)
	line.add_child(left[0])
	var right := _figure(L.t("GELİR / DÖNEM"), UiTheme.fs(20), UiTheme.GREEN, HORIZONTAL_ALIGNMENT_RIGHT)
	(right[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(right[0])
	_income_label = right[1]
	_tax_effect = UiTheme.mono_label("", UiTheme.fs(14), UiTheme.TEXT_MUTED, true)
	_tax_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_tax_effect)
	_tiles["treasury"] = {"panel": panel, "style": style, "value": left[1]}
	return panel

## Küçük başlık + büyük rakam: [kutu, rakam etiketi].
static func _figure(caption: String, size: int, color: Color, align: HorizontalAlignment) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_END
	var cap := UiTheme.mono_label(caption, UiTheme.fs(12), UiTheme.TEXT_MUTED)
	cap.add_theme_font_override("font", UiTheme.mono_regular())
	cap.horizontal_alignment = align
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cap)
	var value := UiTheme.mono_label("—", size, color, true)
	value.horizontal_alignment = align
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(value)
	return [box, value]

# --- Yenileme ------------------------------------------------------------------------

func refresh() -> void:
	var econ: Dictionary = CardManager.economy
	var level := CardManager.tax_level()
	for i in _tax_buttons.size():
		if _styled_tax_level == level:
			break
		var button := _tax_buttons[i] as Button
		var active := i == level
		# Konsept: seçili kademe deniz yeşili, diğerleri oyuk renginde.
		UiSkin.skin_color_button(button, UiTheme.TEAL if active else UiTheme.SLOT)
		UiSkin.compact(button, int(UiTheme.d(8)))
		if not active:
			button.add_theme_color_override("font_color", UiTheme.TEXT_MUTED2)
			button.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	_styled_tax_level = level
	if _treasury_tween == null or not _treasury_tween.is_running():
		_shown_treasury = CardManager.state_treasury()
		_show_treasury(_shown_treasury)
	_income_label.text = "+" + GameRules.amount(CardManager.expected_revenue())
	var election := not election_headline().is_empty()
	# Sandık öncesi: özet hazine kartının yerini alır.
	(_tiles["treasury"]["panel"] as Control).visible = not election
	var effect := tax_effect_text()
	_tax_effect.text = effect[0]
	_tax_effect.add_theme_color_override("font_color", effect[1])
	_refresh_summary()

## Yürürlükteki verginin seçmene etkisi: [metin, renk]. Hükümet yoksa etkisiz.
static func tax_effect_text() -> Array:
	var total := CardManager.tax_turn_effect() if GovernmentManager.has_government() else 0.0
	return [L.t("Seçmene %s") % voter_word(total), voter_color(total)]

## Seçmene etki tek kelime: olumlu / olumsuz / etkisiz.
static func voter_word(effect: float) -> String:
	if is_zero_approx(effect):
		return L.t("etkisiz")
	return L.t("olumlu") if effect > 0.0 else L.t("olumsuz")

static func voter_color(effect: float) -> Color:
	if is_zero_approx(effect):
		return UiTheme.TEXT_MUTED
	return UiTheme.GREEN if effect > 0.0 else UiTheme.RED

func _show_treasury(value: float) -> void:
	(_tiles["treasury"]["value"] as Label).text = Economy.money_full(value)

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
	box.add_child(_summary_row(L.t("Vergi"), "%s · %s" % [Economy.tax_title(int(econ["tax"])), String(tax_effect_text()[0]).to_lower()]))
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
	var style: StyleBox = _tiles[key]["style"]
	if style is BoardBox:
		# Kartın kenar çizgisi bir an olayın renginde parlar, sonra söner.
		var box := style as BoardBox
		var tween := create_tween()
		tween.tween_method(func(c: Color):
			box.border_color = c
			box.emit_changed(), color, TILE_BORDER, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		return
	var flat := style as StyleBoxFlat
	if flat == null:
		return
	flat.border_color = color
	var tween := create_tween()
	tween.tween_property(flat, "border_color", TILE_BORDER, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

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

## Panel içeriği (0.0.313 sade): üç kademe kartı (gelir + seçmene etkisi) ve
## seçilen kademe için meclise sunma düğmesi. selected: seçili kademe (-1:
## henüz seçilmedi). show_header false: başlık ve Kapat yok (yasa panelinin
## VERGİ sekmesi).
static func fill_policy(box: VBoxContainer, me: int, selected: int, on_select: Callable, on_propose: Callable, on_close: Callable, show_header: bool = true) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var current := CardManager.tax_level()
	if show_header:
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		box.add_child(header)
		var title := UiTheme.mono_label(L.t("VERGİ"), 14, UiTheme.TEXT, true)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var close := Button.new()
		close.text = L.t("Kapat")
		UiSkin.skin_button(close)
		close.add_theme_font_size_override("font_size", 11)
		close.pressed.connect(on_close)
		header.add_child(close)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	box.add_child(cards)
	for level in Economy.TAX_LEVELS:
		cards.add_child(_policy_card(me, level, current, selected, on_select))
	var picked := selected >= 0 and selected != current
	var reason := CardManager.tax_law_block_reason(me, selected) if picked else CardManager.tax_law_block_reason(me)
	if picked and reason == "":
		var law_type := CardPresets.tax_law_type(selected)
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 36)
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", 14)
		button.text = L.t("MECLİSE SUN · %s") % GameRules.cost_text(GameRules.LAW_FUNDS_COST)
		UiSkin.skin_color_button(button, UiTheme.GREEN_DARK)
		button.pressed.connect(func(): on_propose.call(law_type))
		box.add_child(button)
	elif reason != "":
		box.add_child(PopupKit.note(reason, UiTheme.RED, 380))

## Kademe kartı: ad, dönem geliri, seçmene etkisi ve durum etiketi
## (yürürlükte: renkli çerçeve, seçili: koyu çerçeve, sunulamaz: sönük).
static func _policy_card(me: int, level: int, current: int, selected: int, on_select: Callable) -> Control:
	var is_current := level == current
	var is_selected := level == selected and not is_current
	var available := CardManager.can_propose_tax_law(me, level)
	var color: Color = TAX_COLORS[level]
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(124, 112)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color, 0.16) if is_current else (UiTheme.SLOT if state == "hover" else TILE_BG)
		style.border_color = color if is_current else (UiTheme.TEXT if is_selected else TILE_BORDER)
		style.set_border_width_all(2 if is_current or is_selected else 1)
		style.border_width_top = 4 if is_current or is_selected else 1
		style.set_corner_radius_all(8)
		UiSkin.apply_style(button, state, style)
	button.disabled = is_current
	button.pressed.connect(func(): on_select.call(level))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -6
	box.offset_top = 6
	box.offset_bottom = -6
	button.add_child(box)
	var name := UiTheme.mono_label(Economy.tax_title(level).to_upper(), 13, color.darkened(0.15), true)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	var money := UiTheme.mono_label("+" + GameRules.amount(CardManager.expected_revenue(level)), 18, UiTheme.MONEY, true)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(money)
	var per := UiTheme.mono_label(L.t("/ dönem"), 10, UiTheme.TEXT_DIM)
	per.add_theme_font_override("font", UiTheme.mono_regular())
	per.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(per)
	var effect := CardManager.tax_turn_effect(level)
	box.add_child(PopupKit.chip(L.t("Seçmene %s") % voter_word(effect), voter_color(effect)))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var tag_text := L.t("YÜRÜRLÜKTE") if is_current else (L.t("SEÇİLDİ") if is_selected else (L.t("SEÇ") if available else L.t("SUNULAMAZ")))
	var tag := UiTheme.mono_label(tag_text, 10, color.darkened(0.2) if is_current else (UiTheme.TEXT if is_selected else UiTheme.TEXT_DIM), true)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)
	if not available and not is_current:
		button.modulate = Color(1, 1, 1, 0.7)
	return button

static func _signed(value: float) -> String:
	return ("+" if value > 0.0 else "−") + String.num(snappedf(absf(value), 0.1), 1).replace(".", ",")
