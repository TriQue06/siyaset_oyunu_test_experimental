class_name ProvincePanel
extends PanelContainer
## Haritada bir ile TIKLAYINCA açılan il menüsü (görünüm: PopupKit).
##   - başlık: il adı, vekil sayısı, kale çipi,
##   - SENİN TEŞKİLATIN (sadece bu oyuncu): seviye, ilin görüşü, seçmen
##     yakınlığı, kale yolu çubukları ve anket (1. seviye yaklaşık, 2. seviye
##     %90 doğru). Teşkilat yoksa bilgi yok,
##   - SEN BU İLDE: güç, teşkilat bonusu, miting riski, sonraki teşkilat bedeli,
##   - SON SEÇİM (herkese açık) ve SON OLAYLAR.
## İlin gerçek görüşü burada ASLA doğrudan gösterilmez — teşkilatla öğrenilir.
## Durum değiştikçe GameScreen refresh() çağırır.

signal closed

const PANEL_WIDTH := 330.0
const DIM := UiTheme.TEXT_MUTED
const INTEL_COLOR := Color("8CC4FF")
## Son olaylar bölümünde en fazla bu kadar kayıt.
const MAX_EVENTS := 5

var province_id: String = ""
var _body: VBoxContainer
var _scroll: ScrollContainer
var _max_height := 600.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 95
	refresh()

## Panel en fazla bu kadar uzar; içerik daha uzunsa kaydırılır.
func clamp_to_height(max_height: float) -> void:
	_max_height = max_height
	await get_tree().process_frame
	_fit()

func _fit() -> void:
	if _body == null:
		return
	# Başlık + kaydırılan içerik + kenar boşlukları.
	var wanted: float = get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y \
		+ _body.get_combined_minimum_size().y
	size = Vector2(PANEL_WIDTH, minf(wanted, maxf(140.0, _max_height)))

func show_province(id: String) -> void:
	province_id = id
	refresh()
	show()

func refresh() -> void:
	if province_id == "" or not is_inside_tree():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var me := multiplayer.get_unique_id()
	var owner := CardManager.stronghold_of(province_id)
	var accent: Color = PartyManager.parties.get(owner, {}).get("bg_color", UiTheme.PANEL_LIGHT) if owner != -1 else UiTheme.PANEL_LIGHT
	var parts := PopupKit.frame(PANEL_WIDTH, accent, self)
	var root: VBoxContainer = parts[1]

	var head := PopupKit.header(ElectionNightSim.province_name(province_id),
		"%d milletvekili" % CardManager.province_seat_count(province_id), null, func():
			hide()
			closed.emit())
	root.add_child(head)
	if owner != -1:
		var party: Dictionary = PartyManager.parties.get(owner, {})
		var kale := HBoxContainer.new()
		kale.add_theme_constant_override("separation", 6)
		kale.add_child(PopupKit.chip("KALE · %s" % String(party.get("name", "?")), (party.get("bg_color", UiTheme.GOLD) as Color).lightened(0.2)))
		kale.add_child(PopupKit.chip("kuşatma %%%d" % int(round(CardManager.siege_total(province_id) / PublicOpinion.SIEGE_BREAK * 100.0)), UiTheme.RED))
		root.add_child(kale)
		root.add_child(PopupKit.note("Rakipler burada seçmeni %%%d daha yavaş çevirir, karalama yarı etkili. 2-3 partinin mitingi kaleyi düşürebilir." % int(round(PublicOpinion.STRONGHOLD_RESISTANCE * 100.0))))

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	# Sağda kaydırma çubuğuna yer: değerler çubuğun altında kalmasın.
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 10)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(gutter)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", PopupKit.GAP)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_child(_body)

	if PartyManager.parties.has(me):
		_build_intel(me)
		_build_own(me)
	_build_last_election(me)
	_build_events()
	if is_visible_in_tree():
		_fit.call_deferred()

func _build_intel(me: int) -> void:
	var level := CardManager.organization_level(province_id, me)
	_body.add_child(PopupKit.section("Senin teşkilatın", "sadece sen görürsün"))
	_body.add_child(_level_row(level))
	if level == 0:
		_body.add_child(PopupKit.note("Burada teşkilatın yok. Kurmak %d mana: ilin görüşünü ve yaklaşık anketi açar, oy bonusu verir. Miting ve karalama da teşkilat ister." % GameRules.ORG_MANA_COST))
		return
	var center := CardManager.province_center(province_id)
	for axis in IdeologyAxes.AXES:
		_body.add_child(PopupKit.kv(IdeologyAxes.AXIS_SIDES[axis]["title"],
			IdeologyAxes.position_text(axis, float(center.get(axis, 0.0))), INTEL_COLOR))
	var closeness := CardManager.stronghold_closeness(province_id, me)
	var closeness_text := "çok yakın" if closeness >= 0.75 else ("yakın" if closeness >= PublicOpinion.STRONGHOLD_THRESHOLD \
		else ("uzak" if closeness >= 0.3 else "çok uzak"))
	var closeness_color := UiTheme.GREEN if closeness >= PublicOpinion.STRONGHOLD_THRESHOLD else (UiTheme.GOLD if closeness >= 0.3 else UiTheme.RED)
	_body.add_child(PopupKit.kv("Seçmen sana", closeness_text, closeness_color))
	_build_kale_progress(me, level, closeness)
	_build_poll(me, level)

## Teşkilat seviyesi: dolu/boş kareler + seviye adı.
func _level_row(level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var key := PopupKit.label("Seviye", PopupKit.FS_TEXT, PopupKit.KEY)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var mine: Color = PartyManager.parties.get(multiplayer.get_unique_id(), {}).get("bg_color", UiTheme.BLUE)
	for i in GameRules.ORG_MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = mine if i < level else UiTheme.SLOT
		row.add_child(pip)
	var text := PopupKit.label("  %d/%d" % [level, GameRules.ORG_MAX_LEVEL], PopupKit.FS_TEXT, UiTheme.TEXT)
	row.add_child(text)
	return row

## Kale yolu: teşkilat tam + kale emeği (miting/yatırım) + seçmen yakınlığı.
func _build_kale_progress(me: int, level: int, closeness: float) -> void:
	if CardManager.stronghold_of(province_id) == me:
		_body.add_child(PopupKit.kv("Kale", "SENİN KALEN", UiTheme.GOLD))
		return
	var effort := CardManager.kale_effort_of(province_id, me)
	var need := PublicOpinion.STRONGHOLD_EFFORT
	_body.add_child(PopupKit.label("Kale yolu", PopupKit.FS_SMALL, UiTheme.TEXT))
	_body.add_child(PopupKit.meter("Teşkilat", level, GameRules.ORG_MAX_LEVEL, UiTheme.BLUE, "%d/%d" % [level, GameRules.ORG_MAX_LEVEL]))
	_body.add_child(PopupKit.meter("Miting/yatırım", minf(effort, need), need, UiTheme.GOLD, "%d/%d" % [mini(int(effort), int(need)), int(need)]))
	_body.add_child(PopupKit.meter("Seçmen", closeness, PublicOpinion.STRONGHOLD_THRESHOLD,
		UiTheme.GREEN if closeness >= PublicOpinion.STRONGHOLD_THRESHOLD else UiTheme.GOLD,
		"tamam" if closeness >= PublicOpinion.STRONGHOLD_THRESHOLD else "uzak"))

func _build_poll(me: int, level: int) -> void:
	var poll := CardManager.province_poll(me, province_id)
	if poll.is_empty():
		return
	var accuracy := "%90 doğru" if level >= 2 else "yaklaşık"
	_body.add_child(PopupKit.section("Anket · şimdi seçim olsa", "%s ±%%%d" % [accuracy,
		int(round(CardManager.poll_error(me, province_id) * 100.0))]))
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
	_body.add_child(_columns_header())
	for peer_id in ids:
		var entry: Dictionary = poll[peer_id]
		_body.add_child(PopupKit.party_row(PartyManager.parties.get(peer_id, {}), int(peer_id) == me,
			["%%%.0f" % float(entry["percent"]), str(int(entry["seats"]))], [44, 30]))
	if level < 2:
		_body.add_child(PopupKit.note("2. seviye teşkilat (%d mana) %%90 doğru anket verir." % GameRules.ORG_UPGRADE_MANA_COST, UiTheme.TEXT_DIM))

func _columns_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for pair in [["oy", 44], ["mv", 30]]:
		var l := PopupKit.label(pair[0], PopupKit.FS_SECTION, UiTheme.TEXT_DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(pair[1], 0)
		row.add_child(l)
	return row

func _build_own(me: int) -> void:
	var level := CardManager.organization_level(province_id, me)
	_body.add_child(PopupKit.section("Sen bu ilde"))
	var power := CardManager.activity_of(province_id, me)
	_body.add_child(PopupKit.kv("Yerel güç", "%+.1f" % power, _opinion_color(power)))
	if level > 0:
		_body.add_child(PopupKit.kv("Teşkilat oy bonusu", "%+.1f" % CardManager.org_bonus(province_id, me), UiTheme.GREEN))
		var risk := CardManager.miting_risk(me, province_id)
		var color := UiTheme.GREEN if risk < 0.15 else (UiTheme.GOLD if risk < 0.3 else UiTheme.RED)
		_body.add_child(PopupKit.kv("Miting provokasyon riski", "%%%d" % int(round(risk * 100.0)), color))
		var mult := PublicOpinion.org_action_mult(level)
		if not is_equal_approx(mult, 1.0):
			_body.add_child(PopupKit.kv("Miting/karalama etkisi", "×%.1f" % mult, UiTheme.GREEN))
	else:
		_body.add_child(PopupKit.kv("Miting / karalama", "teşkilat gerekli", UiTheme.RED))
	if level < GameRules.ORG_MAX_LEVEL:
		_body.add_child(PopupKit.kv("Teşkilat %s" % ("kurmak" if level == 0 else "geliştirmek"),
			"%d mana" % GameRules.org_cost(level), UiTheme.BLUE.lightened(0.3)))

## Son seçim sonucu herkese açık bilgi.
func _build_last_election(me: int) -> void:
	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	if results.is_empty():
		return
	_body.add_child(PopupKit.section("Son seçim"))
	_body.add_child(_columns_header())
	var ids: Array = results.keys()
	ids.sort_custom(func(a, b): return float(results[a].get("percent", 0.0)) > float(results[b].get("percent", 0.0)))
	for peer_id in ids:
		var entry: Dictionary = results[peer_id]
		var seats := int(entry.get("seats", 0))
		_body.add_child(PopupKit.party_row(PartyManager.parties.get(peer_id, {}), int(peer_id) == me,
			["%%%.0f" % float(entry.get("percent", 0.0)), [str(seats), UiTheme.TEXT if seats > 0 else UiTheme.TEXT_DIM]], [44, 30]))

func _build_events() -> void:
	_body.add_child(PopupKit.section("Son olaylar"))
	var events: Array = CardManager.province_events.get(province_id, [])
	if events.is_empty():
		_body.add_child(PopupKit.note("Bu ilde henüz bir olay yok.", UiTheme.TEXT_DIM))
		return
	var shown := 0
	for i in range(events.size() - 1, -1, -1):
		if shown >= MAX_EVENTS:
			break
		shown += 1
		var event: Dictionary = events[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var when := PopupKit.label(GameRules.period_label(int(event.get("round", 1))), PopupKit.FS_SECTION, UiTheme.TEXT_DIM)
		when.custom_minimum_size = Vector2(64, 0)
		when.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(when)
		var text := PopupKit.note(String(event.get("text", "")), UiTheme.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_body.add_child(row)

static func _opinion_color(value: float) -> Color:
	if value > 0.05:
		return UiTheme.GREEN
	if value < -0.05:
		return UiTheme.RED
	return DIM


## Anlık vekil tahmini: her vekil bir kare nokta, parti sırasıyla satır satır.
class SeatDots extends Control:
	const DOT := 12.0
	const GAP := 3.0
	var colors: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_update_height)
		_update_height()

	func _per_row() -> int:
		return maxi(1, int((maxf(size.x, ProvincePanel.PANEL_WIDTH - 50.0) + GAP) / (DOT + GAP)))

	func _update_height() -> void:
		var rows := int(ceil(float(colors.size()) / _per_row()))
		custom_minimum_size = Vector2(0, maxf(DOT, rows * (DOT + GAP) - GAP))
		queue_redraw()

	func _draw() -> void:
		var per_row := _per_row()
		for i in colors.size():
			var pos := Vector2((i % per_row) * (DOT + GAP), (i / per_row) * (DOT + GAP))
			draw_rect(Rect2(pos, Vector2(DOT, DOT)), UiTheme.INK)
			draw_rect(Rect2(pos + Vector2(2, 2), Vector2(DOT - 4, DOT - 4)), colors[i])
