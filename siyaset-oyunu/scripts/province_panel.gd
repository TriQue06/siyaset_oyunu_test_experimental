class_name ProvincePanel
extends PanelContainer
## Haritada bir ile TIKLAYINCA açılan il detay paneli. Oyuncu burada o ildeki
## gücünü ve kimin ne yaptığını görür:
##   - milletvekili sayısı, siyasi denge (seçmen eğilimi -> güncel denge),
##   - partilerin son seçim oyu, milletvekili ve İL KAMUOYU puanı,
##   - kendi partisi burada miting yaparsa provokasyon riski,
##   - ildeki son olaylar (miting, provokasyon, yatırım).
## Durum değiştikçe GameScreen refresh() çağırır.

signal closed

const PANEL_WIDTH := 340.0
const BADGE_SIZE := Vector2(22, 22)
const DIM := Color(1, 1, 1, 0.6)

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
	var title := _label(province_id.capitalize(), 18)
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

	_build_balance()
	_build_parties()
	_build_risk()
	_build_events()

func _section(text: String) -> void:
	_body.add_child(HSeparator.new())
	_body.add_child(_label(text, 11, DIM))

func _build_balance() -> void:
	_section("SİYASİ DENGE  (seçmen eğilimi → güncel denge)")
	var voters: Dictionary = ElectionModel.load_province_voters().get(province_id, {})
	var balance := CardManager.province_balance(province_id)
	for axis in IdeologyAxes.AXES:
		var info: Dictionary = CardPresets.AXIS_TITLES[axis]
		var value: float = float(balance.get(axis, 0.0))
		var lean: String = info["pos"] if value > 0.25 else (info["neg"] if value < -0.25 else "Orta")
		_body.add_child(_label("%s: %+.1f → %+.1f  (%s)" % [info["title"], float(voters.get(axis, 0.0)), value, lean], 12))

func _build_parties() -> void:
	_section("PARTİLER  (oy · mv · il kamuoyu)")
	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	var ids: Array = CardManager.turn_order.duplicate()
	ids.sort_custom(func(a, b):
		return float(results.get(a, {}).get("percent", 0.0)) > float(results.get(b, {}).get("percent", 0.0)))
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
		var stats := _label("%%%.1f · %d mv" % [float(entry.get("percent", 0.0)), int(entry.get("seats", 0))] if not entry.is_empty() else "—", 12, DIM)
		stats.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(stats)
		var local := CardManager.local_of(province_id, peer_id)
		var local_label := _label("%+.1f" % local, 12, _opinion_color(local))
		local_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		local_label.custom_minimum_size = Vector2(40, 0)
		local_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(local_label)
		_body.add_child(row)

func _build_risk() -> void:
	var me := multiplayer.get_unique_id()
	if not PartyManager.parties.has(me):
		return
	_section("BURADA MİTİNG YAPARSAN")
	var risk := CardManager.miting_risk(me, province_id)
	var color := Color(0.6, 1.0, 0.6) if risk < 0.15 else (Color(1.0, 0.85, 0.4) if risk < 0.3 else Color(1.0, 0.5, 0.45))
	_body.add_child(_label("Provokasyon riski: %%%d" % int(round(risk * 100.0)), 13, color))

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
