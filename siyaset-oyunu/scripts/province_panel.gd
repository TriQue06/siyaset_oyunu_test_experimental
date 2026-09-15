class_name ProvincePanel
extends PanelContainer
## Haritada bir ile TIKLAYINCA açılan il detay paneli:
##   - milletvekili sayısı,
##   - İSTİHBARATIN (sadece bu oyuncu): gözcü bilgisi (ilin görüşü, eksen başına
##     uç ya da orta) ve son anket,
##   - partilerin son seçim oyu, vekili, bu ildeki GÜCÜ (aktivite) ve il başkanlığı,
##   - kendi partinin burada miting riski ve il başkanlığı durumu,
##   - ildeki son olaylar.
## İlin gerçek görüşü burada ASLA doğrudan gösterilmez — gözcü kartıyla öğrenilir.
## Durum değiştikçe GameScreen refresh() çağırır.

signal closed

const PANEL_WIDTH := 340.0
const BADGE_SIZE := Vector2(22, 22)
const DIM := Color(1, 1, 1, 0.6)
const INTEL_COLOR := Color(0.6, 0.85, 1.0)

var province_id: String = ""
var _body: VBoxContainer

func _ready() -> void:
	UiSkin.skin_panel(self, UiSkin.PANEL_DARK)
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 95
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	margin.add_child(_body)
	refresh()

func show_province(id: String) -> void:
	province_id = id
	refresh()
	show()

static func _label(text: String, size: int = 12, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func refresh() -> void:
	if _body == null or province_id == "":
		return
	for child in _body.get_children():
		child.queue_free()

	var header := HBoxContainer.new()
	var title := _label(ElectionNightSim.province_name(province_id), 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Kapat"
	UiSkin.skin_button(close_button)
	close_button.pressed.connect(func():
		hide()
		closed.emit()
	)
	header.add_child(close_button)
	_body.add_child(header)
	_body.add_child(_label("%d milletvekili" % CardManager.province_seat_count(province_id), 12, DIM))

	_build_intel()
	_build_parties()
	_build_own()
	_build_events()

func _section(text: String) -> void:
	_body.add_child(HSeparator.new())
	_body.add_child(_label(text, 11, DIM))

func _build_intel() -> void:
	var me := multiplayer.get_unique_id()
	_section("İSTİHBARATIN  (sadece sen görürsün)")
	if CardManager.has_scouted(me, province_id):
		var center := CardManager.province_center(province_id)
		for axis in IdeologyAxes.AXES:
			_body.add_child(_label(CardPresets.leaning_text(axis, int(center.get(axis, 0))), 12, INTEL_COLOR))
	else:
		_body.add_child(_label("İlin görüşü bilinmiyor — Gözcü kartıyla öğren.", 12, DIM))
	var poll := CardManager.poll_of(me, province_id)
	if poll.is_empty():
		return
	_body.add_child(_label("Anket (%d. tur, ±%%%d hata):" % [int(poll.get("round", 0)), int(PublicOpinion.POLL_ERROR * 100)], 12, INTEL_COLOR))
	var shares: Dictionary = poll.get("shares", {})
	var ids: Array = shares.keys()
	ids.sort_custom(func(a, b): return float(shares[a]) > float(shares[b]))
	for peer_id in ids:
		_body.add_child(_label("   %s  %%%.0f" % [GovernmentHud.party_name_of(int(peer_id)), float(shares[peer_id])], 12))

func _build_parties() -> void:
	_section("PARTİLER  (oy · mv · güç · il başkanlığı)")
	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	var ids: Array = CardManager.turn_order.duplicate()
	ids.sort_custom(func(a, b):
		return CardManager.activity_of(province_id, a) > CardManager.activity_of(province_id, b))
	var me := multiplayer.get_unique_id()
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var badge := PartyBadge.build(party, BADGE_SIZE, 40)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var name_label := _label(party.get("name", "?"), 12, Color(1.0, 0.85, 0.35) if peer_id == me else Color.WHITE)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var entry: Dictionary = results.get(peer_id, {})
		var stats := _label("%%%.0f · %d" % [float(entry.get("percent", 0.0)), int(entry.get("seats", 0))] if not entry.is_empty() else "—", 12, DIM)
		stats.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(stats)
		var activity := CardManager.activity_of(province_id, peer_id)
		var activity_label := _label("%+.1f" % activity, 12, _opinion_color(activity))
		activity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		activity_label.custom_minimum_size = Vector2(40, 0)
		activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(activity_label)
		var level := CardManager.organization_level(province_id, peer_id)
		var org_label := _label("B%d" % level if level > 0 else "—", 12, Color(0.55, 0.9, 0.85) if level > 0 else DIM)
		org_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		org_label.custom_minimum_size = Vector2(24, 0)
		org_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		org_label.tooltip_text = "İl başkanlığı seviyesi"
		org_label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(org_label)
		_body.add_child(row)

func _build_own() -> void:
	var me := multiplayer.get_unique_id()
	if not PartyManager.parties.has(me):
		return
	_section("SEN BU İLDE")
	var risk := CardManager.miting_risk(me, province_id)
	var color := Color(0.6, 1.0, 0.6) if risk < 0.15 else (Color(1.0, 0.85, 0.4) if risk < 0.3 else Color(1.0, 0.5, 0.45))
	_body.add_child(_label("Miting provokasyon riski: %%%d" % int(round(risk * 100.0)), 13, color))
	var level := CardManager.organization_level(province_id, me)
	var org_text := "İl başkanlığı yok" if level == 0 else "İl başkanlığı: seviye %d/%d" % [level, GameRules.ORG_MAX_LEVEL]
	if level < GameRules.ORG_MAX_LEVEL:
		org_text += "  ·  %s: %d mana" % ["kurmak" if level == 0 else "geliştirmek", GameRules.ORG_MANA_COST]
	_body.add_child(_label(org_text, 12))

func _build_events() -> void:
	_section("SON OLAYLAR")
	var events: Array = CardManager.province_events.get(province_id, [])
	if events.is_empty():
		_body.add_child(_label("Bu ilde henüz bir olay yok.", 12, DIM))
		return
	for i in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[i]
		_body.add_child(_label("Tur %d: %s" % [int(event.get("round", 0)), event.get("text", "")], 11))

static func _opinion_color(value: float) -> Color:
	if value > 0.05:
		return Color(0.55, 1.0, 0.55)
	if value < -0.05:
		return Color(1.0, 0.5, 0.45)
	return DIM
