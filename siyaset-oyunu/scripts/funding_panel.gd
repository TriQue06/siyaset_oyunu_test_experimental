class_name FundingPanel
extends PanelContainer
## FİNANSMAN ONAYI: yatırım ya da (hükümet partisinin) mitingi için il
## seçilince haritanın altında açılır. Ortada FundingSlider; üstünde iki uç
## (PARTİ KASASI / DEVLET HAZİNESİ), altında paylaşım çubuğu, iki kaynağın
## ödediği tutar ve işlem sonrası kalan bakiye, toplam, gerekiyorsa TEK kısa
## not (kısıt ya da partizan harcama uyarısı), ONAYLA / Vazgeç. Değerler
## nokta kaydıkça anında güncellenir. İki kaynak da milyon ₺.

signal confirmed(share: float)
signal cancelled

const WIDTH := 452.0

var peer_id: int = -1
var kind: String = "invest"
var province_id: String = ""
var _range: Dictionary = {}
var _slider: FundingSlider
var _title: Label
var _tag_holder: HBoxContainer
var _party_end: Label
var _state_end: Label
var _bar: Control
var _party_pay: Label
var _party_left: Label
var _state_pay: Label
var _state_left: Label
var _total: Label
var _note: Label
var _confirm: Button

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 107
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_S + 2)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	_title = UiTheme.mono_label("", 13, UiTheme.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	header.add_child(_title)
	_tag_holder = HBoxContainer.new()
	header.add_child(_tag_holder)
	# Uçlar: sol parti kasası, sağ devlet hazinesi (kendi renkleri ve birimleri).
	var ends := HBoxContainer.new()
	box.add_child(ends)
	_party_end = UiTheme.mono_label("PARTİ KASASI", 10, FundingSlider.PARTY_COLOR, true)
	_party_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(_party_end)
	_state_end = UiTheme.mono_label("DEVLET HAZİNESİ", 10, FundingSlider.STATE_COLOR, true)
	ends.add_child(_state_end)
	_slider = FundingSlider.new()
	_slider.share_changed.connect(func(_s: float): _refresh())
	box.add_child(_slider)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 16)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	box.add_child(_bar)
	# İki sütun: her kaynak ne öder, işlemden sonra ne kalır.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	box.add_child(cols)
	var party_col := _column(cols, FundingSlider.PARTY_COLOR)
	_party_pay = party_col[0]
	_party_left = party_col[1]
	var state_col := _column(cols, FundingSlider.STATE_COLOR)
	_state_pay = state_col[0]
	_state_left = state_col[1]
	_state_pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_state_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total = PopupKit.label("", 11, UiTheme.TEXT_MUTED)
	box.add_child(_total)
	_note = PopupKit.label("", 11, UiTheme.TEXT_MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	_confirm = Button.new()
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.custom_minimum_size = Vector2(0, 34)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.add_theme_font_override("font", UiTheme.mono(true))
	_confirm.add_theme_font_size_override("font_size", 13)
	_confirm.pressed.connect(func(): confirmed.emit(_slider.share))
	buttons.add_child(_confirm)
	var cancel := Button.new()
	cancel.text = "Vazgeç"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(90, 34)
	UiSkin.skin_button(cancel)
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.pressed.connect(func(): cancelled.emit())
	buttons.add_child(cancel)

func _column(parent: HBoxContainer, color: Color) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var pay := UiTheme.mono_label("", 14, color.lightened(0.15), true)
	col.add_child(pay)
	var left := UiTheme.mono_label("", 10, UiTheme.TEXT_MUTED)
	left.custom_minimum_size = Vector2(0, 16)
	left.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(left)
	return [pay, left]

## Hamle ve il için paneli açar (değer: hamlenin varsayılan paylaşımı).
func open(p_peer: int, p_kind: String, p_province: String) -> void:
	peer_id = p_peer
	kind = p_kind
	province_id = p_province
	_range = CardManager.funding_range(peer_id, kind)
	_slider.setup(float(_range["default"]), float(_range["min"]), float(_range["max"]))
	var place := ElectionNightSim.province_name(province_id)
	_title.text = ("%s · yatırım finansmanı" if kind == "invest" else "%s · miting finansmanı") % place
	for child in _tag_holder.get_children():
		child.queue_free()
	_tag_holder.add_child(PopupKit.chip("KAMU YATIRIMI" if kind == "invest" else "PARTİ FAALİYETİ",
		UiTheme.GREEN if kind == "invest" else UiTheme.PURPLE))
	_refresh()
	show()

func current_share() -> float:
	return _slider.share

func _split() -> Dictionary:
	return Economy.split_cost(float(_range.get("total", 0.0)), _slider.share)

func _refresh() -> void:
	if _range.is_empty():
		return
	var split := _split()
	var party_million := float(split["party"])
	var state_million := float(split["state"])
	_party_pay.text = "%s milyon ₺" % Economy.money_text(party_million)
	_party_left.text = "kasada kalır: %s" % GameRules.money_text(CardManager.funds_of(peer_id) - party_million)
	_state_pay.text = "%s milyon ₺" % Economy.money_text(state_million)
	_state_left.text = "hazinede kalır: %s" % Economy.money_text(CardManager.state_treasury() - state_million)
	# Hangi kaynak daha çok ödüyor: o uç parlak, diğeri sönük.
	var party_more := party_million > state_million
	_party_end.modulate.a = 1.0 if party_more or is_equal_approx(party_million, state_million) else 0.55
	_state_end.modulate.a = 1.0 if not party_more else 0.55
	_total.text = "Toplam %s milyon ₺" % Economy.money_text(float(_range["total"]))
	var reason := CardManager.funding_block_reason(peer_id, kind, _slider.share)
	var note := ""
	if float(_range["min"]) > float(_range["max"]) + 0.001:
		reason = "Parti kasası ve devlet hazinesi birlikte yetmiyor."
	elif not bool(_range["state_allowed"]):
		note = "Devlet hazinesini sadece hükümet kullanabilir."
	elif float(_range["max"]) < 0.999:
		note = "Hazine yetmediği için devlet payı sınırlı."
	elif float(_range["min"]) > 0.001:
		note = "Parti kasası yetmediği için devlet payı gerekli."
	_note.remove_theme_color_override("font_color")
	if reason != "":
		_note.text = reason
		_note.add_theme_color_override("font_color", UiTheme.RED)
	elif kind == "miting" and state_million > 0.0:
		_note.text = "PARTİZAN HARCAMA: devlet parasıyla miting, soruşturmada usulsüzlük olarak çıkar."
		_note.add_theme_color_override("font_color", UiTheme.RED.lightened(0.2))
	else:
		_note.text = note
		_note.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_note.visible = _note.text != ""
	if reason == "":
		_confirm.text = "ONAYLA · %s milyon ₺" % Economy.money_text(float(_range["total"]))
		UiSkin.skin_color_button(_confirm, UiTheme.GREEN_DARK)
		_confirm.disabled = false
	else:
		_confirm.text = "ÖDENEMİYOR"
		UiSkin.skin_color_button(_confirm, UiTheme.PANEL_DARK)
		_confirm.disabled = true
	_bar.queue_redraw()

## Paylaşım çubuğu: soldan partinin payı (mavi), sağdan devletin payı (altın);
## parçaların içinde yüzdeler.
func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	var pad := FundingSlider.PAD
	var inner := w - 2.0 * pad
	var party_w := inner * (1.0 - _slider._shown)
	_bar.draw_rect(Rect2(pad, 0, inner, h), UiTheme.SLOT, true)
	if party_w > 0.5:
		_bar.draw_rect(Rect2(pad, 0, party_w, h), FundingSlider.PARTY_COLOR.darkened(0.15), true)
	if inner - party_w > 0.5:
		_bar.draw_rect(Rect2(pad + party_w, 0, inner - party_w, h), FundingSlider.STATE_COLOR.darkened(0.2), true)
	var font := UiTheme.mono(true)
	var party_pct := int(round((1.0 - _slider.share) * 100.0))
	if party_w > 34.0:
		_bar.draw_string(font, Vector2(pad + 4.0, h - 4.0), "%%%d" % party_pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT)
	if inner - party_w > 34.0:
		_bar.draw_string(font, Vector2(w - pad - 32.0, h - 4.0), "%%%d" % (100 - party_pct), HORIZONTAL_ALIGNMENT_RIGHT, 28, 10, UiTheme.INK)

func _process(_delta: float) -> void:
	if visible and not is_equal_approx(_slider._shown, _slider.share):
		_bar.queue_redraw()
