class_name AidPanel
extends PanelContainer
## YARDIM GÖTÜR (0.0.181; 0.0.321 sadeleşti): afet sürerken YARDIM hamlesine
## basılınca (ya da sıra başındaki afet sahnesinde) açılır. Tek kaydırıcı:
## parti kasasından tutar (Disaster.AID_STEP adımlarla). Altında tek satır
## etki: bölgede güçlü yerel oy, ülke genelinde seçmen. YARDIM GÖTÜR / Vazgeç.

signal confirmed(party_m: float, state_m: float)
signal cancelled

const WIDTH := 452.0

var peer_id: int = -1
var _title: Label
var _party_slider: HSlider
var _party_value: Label
var _effect: Label
var _note: Label
var _confirm: Button
var _cancel: Button

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 107
	var style := UiSkin.board()
	style.set_content_margin_all(UiTheme.PAD_S + 4)
	UiSkin.apply_style(self, "panel", style)
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiTheme.mono_label("", 15, UiTheme.TEXT, true)
	box.add_child(_title)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := UiTheme.mono_label(L.t("TUTAR"), 11, FundingSlider.PARTY_COLOR, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	_party_value = UiTheme.mono_label("", 15, FundingSlider.PARTY_COLOR.lightened(0.15), true)
	head.add_child(_party_value)
	_party_slider = VectorSlider.new()
	_party_slider.step = Disaster.AID_STEP
	_party_slider.min_value = 0.0
	_party_slider.value_changed.connect(func(_v: float): _refresh())
	box.add_child(_party_slider)
	_effect = UiTheme.mono_label("", 14, UiTheme.GREEN, true)
	box.add_child(_effect)
	_note = PopupKit.label("", 11, UiTheme.RED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	_confirm = Button.new()
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.custom_minimum_size = Vector2(0, 38)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.add_theme_font_override("font", UiTheme.mono(true))
	_confirm.add_theme_font_size_override("font_size", 14)
	_confirm.pressed.connect(func(): confirmed.emit(_party_slider.value, 0.0))
	buttons.add_child(_confirm)
	_cancel = Button.new()
	_cancel.text = L.t("Vazgeç")
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.custom_minimum_size = Vector2(110, 38)
	UiSkin.skin_button(_cancel)
	_cancel.add_theme_font_size_override("font_size", 13)
	_cancel.pressed.connect(func(): cancelled.emit())
	buttons.add_child(_cancel)

## Tur başı afet sahnesi: vazgeç düğmesi bilinçli karardır ("bu tur yardım yapma").
func set_cancel_text(text: String) -> void:
	_cancel.text = text

func open(p_peer: int) -> void:
	peer_id = p_peer
	var active := CardManager.active_disaster()
	if active.is_empty():
		return
	var lim := CardManager.aid_limits(peer_id)
	_party_slider.max_value = maxf(0.0, float(lim["party_max"]))
	_party_slider.set_value_no_signal(minf(float(lim["party_max"]), Disaster.snap_amount(CardManager.funds_of(peer_id) * 0.5)))
	_title.text = L.t("%s · yardım götür") % Disaster.title(String(active["kind"]))
	_refresh()
	show()

func _refresh() -> void:
	var active := CardManager.active_disaster()
	if active.is_empty() or peer_id == -1:
		return
	var total := _party_slider.value
	_party_value.text = Economy.money_full(total)
	var provinces: Array = active.get("provinces", [])
	var prev := CardManager.disaster_aid_of(peer_id)
	var local := Disaster.local_gain(prev, prev + total, provinces.size())
	var national := Disaster.national_gain(prev, prev + total)
	_effect.text = L.t("Bölgede +%s oy · Ülke genelinde +%s") % [L.dec(local, 1), L.dec(national, 1)]
	var reason := CardManager.aid_block_reason(peer_id, total, 0.0)
	_note.text = reason
	_note.visible = reason != ""
	if reason == "":
		_confirm.text = L.t("YARDIM GÖTÜR · %s") % Economy.money_full(total)
		UiSkin.skin_color_button(_confirm, UiTheme.GREEN_DARK)
		_confirm.disabled = false
	else:
		_confirm.text = L.t("YAPILAMIYOR")
		UiSkin.skin_color_button(_confirm, UiTheme.PANEL_DARK)
		_confirm.disabled = true
