class_name ProvincePanel
extends PanelContainer
## Haritada bir ile TIKLAYINCA açılan il detay paneli:
##   - milletvekili sayısı,
##   - TEŞKİLAT RAPORU (sadece bu oyuncu): 1. seviyede ilin görüşü (her eksende
##     hangi uç), 2. seviyede orta, 3. seviyede yüksek isabetli ANKET ("şimdi
##     seçim olsa" oy ve vekil tahmini, daireler). Teşkilat yoksa bilgi yok.
##   - son seçimin il sonucu (herkese açık),
##   - kendi partinin burada gücü, miting riski ve il başkanlığı durumu,
##   - ildeki son olaylar.
## İlin gerçek görüşü burada ASLA doğrudan gösterilmez — teşkilatla öğrenilir.
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
	var level := CardManager.organization_level(province_id, me)
	_section("TEŞKİLAT RAPORU  ·  seviye %d/%d  (sadece sen görürsün)" % [level, GameRules.ORG_MAX_LEVEL])
	if level == 0:
		_body.add_child(_label("Bu ilde teşkilatın yok. Teşkilatlanma (%d mana): 1. seviye ilin görüşünü, 2. seviye orta, 3. seviye yüksek isabetli anketi açar; her seviye oy bonusu da verir." % GameRules.ORG_MANA_COST, 12, DIM))
		return
	var center := CardManager.province_center(province_id)
	for axis in IdeologyAxes.AXES:
		_body.add_child(_label(CardPresets.leaning_text(axis, int(center.get(axis, 0))), 12, INTEL_COLOR))
	var poll := CardManager.province_poll(me, province_id)
	if poll.is_empty():
		_body.add_child(_label("Anket için teşkilatı 2. seviyeye çıkar (%d mana)." % GameRules.ORG_MANA_COST, 12, DIM))
		return
	var accuracy := "yüksek isabetli" if level >= 3 else "orta isabetli"
	_body.add_child(_label("Anket (%s, ±%%%d)  ·  şimdi seçim olsa (oy · mv):" % [accuracy,
		int(round(CardManager.poll_error(me, province_id) * 100.0))], 12, INTEL_COLOR))
	var ids: Array = poll.keys()
	ids.sort_custom(func(x, y):
		var sa := int(poll[x]["seats"])
		var sb := int(poll[y]["seats"])
		if sa != sb:
			return sa > sb
		return float(poll[x]["percent"]) > float(poll[y]["percent"]))
	var colors: Array = []
	for peer_id in ids:
		var color: Color = PartyManager.parties.get(peer_id, {}).get("bg_color", Color(0.5, 0.5, 0.5))
		for i in int(poll[peer_id]["seats"]):
			colors.append(color)
	var dots := SeatDots.new()
	dots.colors = colors
	_body.add_child(dots)
	for peer_id in ids:
		var entry: Dictionary = poll[peer_id]
		_body.add_child(_party_row(int(peer_id), "%%%.0f · %d" % [float(entry["percent"]), int(entry["seats"])], false))

## Bir parti satırı: rozet, ad, istatistik; show_strength ise ildeki gücü ve il başkanlığı.
func _party_row(peer_id: int, stats_text: String, show_strength: bool) -> Control:
	var me := multiplayer.get_unique_id()
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
	var stats := _label(stats_text, 12, DIM)
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(stats)
	if show_strength:
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
		row.add_child(org_label)
	return row

## Son seçim sonucu herkese açık bilgi.
func _build_parties() -> void:
	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	if results.is_empty():
		return
	_section("SON SEÇİM  (oy · mv)")
	var ids: Array = results.keys()
	ids.sort_custom(func(a, b): return float(results[a].get("percent", 0.0)) > float(results[b].get("percent", 0.0)))
	for peer_id in ids:
		var entry: Dictionary = results[peer_id]
		_body.add_child(_party_row(int(peer_id), "%%%.0f · %d" % [float(entry.get("percent", 0.0)), int(entry.get("seats", 0))], false))

func _build_own() -> void:
	var me := multiplayer.get_unique_id()
	if not PartyManager.parties.has(me):
		return
	_section("SEN BU İLDE")
	var risk := CardManager.miting_risk(me, province_id)
	var color := Color(0.6, 1.0, 0.6) if risk < 0.15 else (Color(1.0, 0.85, 0.4) if risk < 0.3 else Color(1.0, 0.5, 0.45))
	_body.add_child(_label("Miting provokasyon riski: %%%d" % int(round(risk * 100.0)), 13, color))
	var power := CardManager.activity_of(province_id, me)
	_body.add_child(_label("Buradaki gücün: %+.1f" % power, 12, _opinion_color(power)))
	var level := CardManager.organization_level(province_id, me)
	var org_text := "Teşkilat yok" if level == 0 else "Teşkilat: seviye %d/%d (oy bonusu %+.1f)" % [level, GameRules.ORG_MAX_LEVEL,
		CardManager.org_bonus(province_id, me)]
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


## Anlık vekil tahmini: her vekil bir daire, parti sırasıyla satır satır.
class SeatDots extends Control:
	const DOT := 14.0
	const GAP := 4.0
	var colors: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_update_height)
		_update_height()

	func _per_row() -> int:
		return maxi(1, int((maxf(size.x, ProvincePanel.PANEL_WIDTH - 24.0) + GAP) / (DOT + GAP)))

	func _update_height() -> void:
		var rows := int(ceil(float(colors.size()) / _per_row()))
		custom_minimum_size = Vector2(0, maxf(DOT, rows * (DOT + GAP) - GAP))
		queue_redraw()

	func _draw() -> void:
		var per_row := _per_row()
		for i in colors.size():
			var center := Vector2((i % per_row) * (DOT + GAP) + DOT * 0.5, (i / per_row) * (DOT + GAP) + DOT * 0.5)
			draw_circle(center, DOT * 0.5, Color(0.05, 0.05, 0.07), true, -1.0, true)
			draw_circle(center, DOT * 0.5 - 2.0, colors[i], true, -1.0, true)
