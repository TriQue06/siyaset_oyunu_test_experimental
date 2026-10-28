class_name AidPanel
extends PanelContainer
## YARDIM GÖTÜR (0.0.181): afet sürerken YARDIM hamlesine basılınca haritanın
## altında açılır. Tutarı oyuncu belirler: iki kaydırıcı, PARTİ KASASINDAN ve
## (hükümet partisiyse) DEVLET HAZİNESİNDEN, Disaster.AID_STEP adımlarla.
## Altında afetteki iller, tahmini etki (il başına yerel puan) ve bu afete
## şimdiye kadar yapılan yardımlar; ONAYLA / Vazgeç.

signal confirmed(party_m: float, state_m: float)
signal cancelled

const WIDTH := 452.0

var peer_id: int = -1
var _title: Label
var _where: Label
var _party_slider: HSlider
var _state_slider: HSlider
var _party_value: Label
var _state_value: Label
var _state_row: Control
var _effect: Label
var _given: Label
var _note: Label
var _confirm: Button
var _cancel: Button

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 107
	var style := UiSkin.board()
	style.set_content_margin_all(UiTheme.PAD_S + 2)
	UiSkin.apply_style(self, "panel", style)
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	_title = UiTheme.mono_label("", 14, UiTheme.TEXT, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(PopupKit.chip(L.t("AFET YARDIMI"), UiTheme.RED))
	_where = PopupKit.label("", 11, UiTheme.TEXT_MUTED)
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_where.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	box.add_child(_where)
	var party_row := _slider_row(box, L.t("PARTİ KASASINDAN"), FundingSlider.PARTY_COLOR)
	_party_slider = party_row[0]
	_party_value = party_row[1]
	var state_row := _slider_row(box, L.t("DEVLET HAZİNESİNDEN"), FundingSlider.STATE_COLOR)
	_state_slider = state_row[0]
	_state_value = state_row[1]
	_state_row = state_row[2]
	_effect = UiTheme.mono_label("", 13, UiTheme.GREEN, true)
	box.add_child(_effect)
	_given = PopupKit.label("", 11, UiTheme.TEXT_MUTED)
	_given.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_given.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	box.add_child(_given)
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
	_confirm.pressed.connect(func(): confirmed.emit(_party_slider.value, _state_slider.value))
	buttons.add_child(_confirm)
	_cancel = Button.new()
	_cancel.text = L.t("Vazgeç")
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.custom_minimum_size = Vector2(90, 34)
	UiSkin.skin_button(_cancel)
	_cancel.add_theme_font_size_override("font_size", 12)
	_cancel.pressed.connect(func(): cancelled.emit())
	buttons.add_child(_cancel)

## Tur başı afet sahnesi: vazgeç düğmesi bilinçli karardır ("bu tur yardım yapma").
func set_cancel_text(text: String) -> void:
	_cancel.text = text
	_cancel.custom_minimum_size = Vector2(170, 34)

## [kaydırıcı, değer etiketi, satır]
func _slider_row(parent: VBoxContainer, title: String, color: Color) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	parent.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var name_label := UiTheme.mono_label(title, 10, color, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var value := UiTheme.mono_label("", 13, color.lightened(0.15), true)
	head.add_child(value)
	var slider := VectorSlider.new()
	slider.step = Disaster.AID_STEP
	slider.min_value = 0.0
	slider.value_changed.connect(func(_v: float): _refresh())
	col.add_child(slider)
	return [slider, value, col]

func open(p_peer: int) -> void:
	peer_id = p_peer
	var active := CardManager.active_disaster()
	if active.is_empty():
		return
	var lim := CardManager.aid_limits(peer_id)
	_party_slider.max_value = maxf(0.0, float(lim["party_max"]))
	_state_slider.max_value = maxf(0.0, float(lim["state_max"]))
	_state_row.visible = bool(lim["state_allowed"])
	# Varsayılan: hükümetse devletten, değilse kasadan makul bir tutar.
	var state_default := minf(float(lim["state_max"]), 40.0) if bool(lim["state_allowed"]) else 0.0
	var party_default := 0.0 if state_default >= Disaster.AID_MIN else minf(float(lim["party_max"]), Disaster.snap_amount(CardManager.funds_of(peer_id) * 0.5))
	_state_slider.set_value_no_signal(Disaster.snap_amount(state_default))
	_party_slider.set_value_no_signal(maxf(Disaster.snap_amount(party_default), 0.0))
	var kind := String(active["kind"])
	_title.text = L.t("%s · yardım götür") % Disaster.title(kind)
	var names: Array = []
	for province_id in active.get("provinces", []):
		names.append(ElectionNightSim.province_name(String(province_id)))
	_where.text = L.t("Afet bölgesi: %s. Afet bu tur sürer.") % ", ".join(PackedStringArray(names))
	var given: Dictionary = active.get("aid", {})
	if given.is_empty():
		_given.text = L.t("Henüz kimse yardım götürmedi.")
	else:
		var parts: Array = []
		for pid in given.keys():
			parts.append("%s %s" % [String(PartyManager.data_of(int(pid)).get("name", "?")), Economy.money_full(float(given[pid]))])
		_given.text = L.t("Şimdiye kadar: %s") % ", ".join(PackedStringArray(parts))
	_refresh()
	show()

func _refresh() -> void:
	var active := CardManager.active_disaster()
	if active.is_empty() or peer_id == -1:
		return
	var party_m := _party_slider.value
	var state_m := _state_slider.value
	_party_value.text = Economy.money_full(party_m)
	_state_value.text = Economy.money_full(state_m)
	var provinces: Array = active.get("provinces", [])
	var prev := CardManager.disaster_aid_of(peer_id)
	var total := party_m + state_m
	var gain := Disaster.local_gain(prev, prev + total, provinces.size())
	_effect.text = L.t("Etki: afetteki %d ilin her birinde +%s yerel puan") % [provinces.size(), String.num(gain, 1)] \
		if provinces.size() > 1 else L.t("Etki: ilde +%s yerel puan") % String.num(gain, 1)
	var reason := CardManager.aid_block_reason(peer_id, party_m, state_m)
	_note.text = reason if reason != "" else L.t("Hemen etki eder, seçmen gruplarına dokunmaz. Aynı afete tekrar yardım daha az getirir.")
	_note.remove_theme_color_override("font_color")
	_note.add_theme_color_override("font_color", UiTheme.RED if reason != "" else UiTheme.TEXT_MUTED)
	if reason == "":
		_confirm.text = L.t("YARDIM GÖTÜR · %s") % Economy.money_full(total)
		UiSkin.skin_color_button(_confirm, UiTheme.GREEN_DARK)
		_confirm.disabled = false
	else:
		_confirm.text = L.t("YAPILAMIYOR")
		UiSkin.skin_color_button(_confirm, UiTheme.PANEL_DARK)
		_confirm.disabled = true
