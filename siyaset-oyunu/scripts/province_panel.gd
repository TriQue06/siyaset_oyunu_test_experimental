class_name ProvincePanel
extends PanelContainer
## Haritada bir ile TIKLAYINCA açılan il menüsü (görünüm: PopupKit).
##   - başlık: il adı, vekil sayısı,
##   - SEÇMEN PROFİLİ (herkese açık): 4 ikili dağılım (her çift toplam %100),
##   - PARTİN BU İLDE: grup uyumu, ilin kalabalık gruplarında partinin desteği,
##     mitingin bu ilde partiyi hangi gruplara yaklaştıracağı (potansiyel),
##   - SENİN TEŞKİLATIN (sadece bu oyuncu): seviye ve anket (1. seviye
##     yaklaşık, 2. seviye %90 doğru),
##   - SEN BU İLDE: güç, teşkilat bonusu, miting riski, sonraki teşkilat bedeli,
##   - SON SEÇİM (herkese açık) ve SON OLAYLAR (miting, yatırım...).
## Durum değiştikçe GameScreen refresh() çağırır.

signal closed

const PANEL_WIDTH := 330.0
## Sol panelde açılınca panelin genişliğine uyar.
static var panel_width := PANEL_WIDTH
const DIM := UiTheme.TEXT_MUTED
const INTEL_COLOR := Color("8CC4FF")
## Son olaylar bölümünde en fazla bu kadar kayıt.
const MAX_EVENTS := 5

var province_id: String = ""
## Sol panelin parçası olarak (çerçevesiz) çizilir.
var embedded_mode := false
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
	size = Vector2(panel_width, minf(wanted, maxf(140.0, _max_height)))

func show_province(id: String) -> void:
	var same := id == province_id and _body != null and is_instance_valid(_body)
	province_id = id
	if same:
		refresh()
	else:
		_rebuild()
	show()

## Durum değişince (başkaları hamle yaptıkça) çağrılır. Aynı il açıkken panel
## baştan kurulmaz: sadece kaydırılan içerik yenilenir, kaydırma kutusu yerinde
## kaldığı için oyuncunun kaydırdığı yer korunur (en üste zıplamaz).
func refresh() -> void:
	if province_id == "" or not is_inside_tree():
		return
	if _body == null or not is_instance_valid(_body) or _built_for != province_id:
		_rebuild()
		return
	var keep := _scroll.scroll_vertical
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	PopupKit.embedded = embedded_mode
	_build_sections()
	PopupKit.embedded = false
	_scroll.scroll_vertical = keep
	if is_visible_in_tree():
		_fit.call_deferred()
		_restore_scroll.call_deferred(keep)

## Bu panelin içeriğinin kurulduğu il (başka ile geçince baştan kurulur).
var _built_for: String = ""

## Paneli baştan kurar (yeni il): başlık, kaydırma kutusu ve bölümler.
func _rebuild() -> void:
	if province_id == "" or not is_inside_tree():
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_built_for = province_id
	PopupKit.embedded = embedded_mode
	var parts := PopupKit.frame(panel_width, UiTheme.PANEL_LIGHT, self)
	var root: VBoxContainer = parts[1]

	var head := PopupKit.header(ElectionNightSim.province_name(province_id),
		L.t("%d milletvekili") % CardManager.province_seat_count(province_id), null, func():
			hide()
			closed.emit())
	root.add_child(head)

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
	_build_sections()
	PopupKit.embedded = false
	if is_visible_in_tree():
		_fit.call_deferred()

func _build_sections() -> void:
	var me := multiplayer.get_unique_id()
	_build_profile()
	if PartyManager.parties.has(CardManager.party_of(me)):
		_build_appeal(me)
		_build_intel(me)
		_build_own(me)
	_build_last_election(me)
	_build_events()

## İçerik yeniden ölçülünce kaydırma sınırı geçici olarak küçülebilir:
## konum bir kez daha yazılır.
func _restore_scroll(value: int) -> void:
	if value > 0 and _scroll != null and is_instance_valid(_scroll):
		_scroll.scroll_vertical = value

func _build_intel(me: int) -> void:
	var level := CardManager.organization_level(province_id, me)
	_body.add_child(PopupKit.section(L.t("Senin teşkilatın"), L.t("sadece sen görürsün")))
	_body.add_child(_level_row(level))
	if level == 0:
		_body.add_child(PopupKit.note(L.t("Burada teşkilatın yok. Kurmak %s: anketi açar, oy kazandırır. Miting ve karalama teşkilat ister.") % GameRules.cost_text(CardManager.org_cost_for(multiplayer.get_unique_id(), province_id))))
		return
	_build_poll(me, level)

## İLİN SEÇMEN PROFİLİ: dört ikili dağılım (herkese açık, oyun boyunca sabit).
func _build_profile() -> void:
	var profile := CardManager.province_profile(province_id)
	if profile.is_empty():
		return
	_body.add_child(PopupKit.section(L.t("Seçmen profili"), L.t("her çift toplam %100")))
	for pair in VoterGroups.PAIR_IDS:
		_body.add_child(VoterGroupUI.pair_rows(pair, profile))

## PARTİN BU İLDE: grup uyumu, kalabalık gruplardaki desteğin ve mitingin
## buradaki siyasi hitap etkisi (gerçek kuralla hesaplanan önizleme).
func _build_appeal(me: int) -> void:
	var profile := CardManager.province_profile(province_id)
	if profile.is_empty():
		return
	var appeal := CardManager.appeal_of(province_id, me)
	var closeness := PublicOpinion.appeal_closeness(appeal)
	var closeness_text := L.t("çok yakın") if closeness >= 0.75 else (L.t("yakın") if closeness >= PublicOpinion.CLOSENESS_NEAR \
		else (L.t("uzak") if closeness >= 0.3 else L.t("çok uzak")))
	var closeness_color := UiTheme.GREEN if closeness >= PublicOpinion.CLOSENESS_NEAR else (UiTheme.GOLD if closeness >= 0.3 else UiTheme.RED)
	_body.add_child(PopupKit.section(L.t("Partin bu ilde"), L.t("seçmen grupları")))
	_body.add_child(PopupKit.kv(L.t("Seçmen sana"), closeness_text, closeness_color))
	var groups := CardManager.effective_groups(me)
	var core: Array = PartyManager.data_of(CardManager.party_of(me)).get("core", [])
	var effects := CardManager.miting_group_gains(me, province_id)
	if effects.is_empty():
		return
	var slots := CardManager.miting_focus_slots(me, province_id)
	_body.add_child(PopupKit.note(L.t("Burada miting yaparsan (odaksız; teşkilatla %d grup odağı seçebilirsin):") % slots if slots > 0
		else L.t("Burada miting yaparsan (teşkilatsız: etkisi düşük, odak seçilemez):"), DIM))
	effects.sort_custom(func(a, b): return float(a["gain"]) > float(b["gain"]))
	for effect in effects.slice(0, 4):
		_body.add_child(VoterGroupUI.effect_row(String(effect["group"]),
			VoterGroups.effective_delta(groups, String(effect["group"]), float(effect["gain"]), core)))

## Teşkilat seviyesi: dolu/boş kareler + seviye adı.
func _level_row(level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var key := PopupKit.label(L.t("Seviye"), PopupKit.FS_TEXT, PopupKit.KEY)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var mine: Color = PartyManager.data_of(multiplayer.get_unique_id()).get("bg_color", UiTheme.BLUE)
	for i in GameRules.ORG_MAX_LEVEL:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = mine if i < level else UiTheme.SLOT
		row.add_child(pip)
	var text := PopupKit.label("  %d/%d" % [level, GameRules.ORG_MAX_LEVEL], PopupKit.FS_TEXT, UiTheme.TEXT)
	row.add_child(text)
	return row

func _build_poll(me: int, level: int) -> void:
	var poll := CardManager.province_poll(me, province_id)
	if poll.is_empty():
		return
	var accuracy := L.t("%90 doğru") if level >= 2 else L.t("yaklaşık")
	_body.add_child(PopupKit.section(L.t("Anket · şimdi seçim olsa"), "%s ±%%%d" % [accuracy,
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
		var color: Color = PartyManager.data_of(peer_id).get("bg_color", Color(0.5, 0.5, 0.5))
		for i in int(poll[peer_id]["seats"]):
			colors.append(color)
	var dots := SeatDots.new()
	dots.colors = colors
	_body.add_child(dots)
	_body.add_child(_columns_header())
	for peer_id in ids:
		var entry: Dictionary = poll[peer_id]
		_body.add_child(PopupKit.party_row(PartyManager.data_of(peer_id), int(peer_id) == CardManager.party_of(me),
			[L.t("%%%.0f") % float(entry["percent"]), str(int(entry["seats"]))], [44, 30]))
	if level < 2:
		_body.add_child(PopupKit.note(L.t("2. seviye teşkilat (%s) çok daha isabetli anket verir.") % GameRules.cost_text(CardManager.org_cost_for(me, province_id)), UiTheme.TEXT_DIM))

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
	_body.add_child(PopupKit.section(L.t("Sen bu ilde")))
	var power := CardManager.activity_of(province_id, me)
	_body.add_child(PopupKit.kv(L.t("Yerel güç"), EffectWords.amount(power, "local"), _opinion_color(power)))
	if level > 0:
		_body.add_child(PopupKit.kv(L.t("Teşkilat desteği"), EffectWords.amount(CardManager.org_bonus(province_id, me), "local"), UiTheme.GREEN))
		var risk := CardManager.miting_risk(me, province_id)
		var color := UiTheme.GREEN if risk < 0.12 else (UiTheme.GOLD if risk < 0.25 else UiTheme.RED)
		_body.add_child(PopupKit.kv(L.t("Miting provokasyonu"), EffectWords.risk(risk), color))
		var mult := PublicOpinion.org_action_mult(level)
		if not is_equal_approx(mult, 1.0):
			_body.add_child(PopupKit.kv(L.t("Miting / karalama"), EffectWords.multiplier(mult), UiTheme.GREEN))
	else:
		_body.add_child(PopupKit.kv(L.t("Miting / karalama"), L.t("teşkilat gerekli"), UiTheme.RED))
	if level < GameRules.ORG_MAX_LEVEL:
		_body.add_child(PopupKit.kv(L.t("Teşkilat %s") % ("kurmak" if level == 0 else L.t("geliştirmek")),
			GameRules.cost_text(CardManager.org_cost_for(me, province_id)), UiTheme.BLUE.lightened(0.3)))

## Son seçim sonucu herkese açık bilgi.
func _build_last_election(me: int) -> void:
	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	if results.is_empty():
		return
	_body.add_child(PopupKit.section(L.t("Son seçim")))
	_body.add_child(_columns_header())
	var ids: Array = results.keys()
	ids.sort_custom(func(a, b): return float(results[a].get("percent", 0.0)) > float(results[b].get("percent", 0.0)))
	for peer_id in ids:
		var entry: Dictionary = results[peer_id]
		var seats := int(entry.get("seats", 0))
		_body.add_child(PopupKit.party_row(PartyManager.data_of(peer_id), int(peer_id) == CardManager.party_of(me),
			[L.t("%%%.0f") % float(entry.get("percent", 0.0)), [str(seats), UiTheme.TEXT if seats > 0 else UiTheme.TEXT_DIM]], [44, 30]))

func _build_events() -> void:
	_body.add_child(PopupKit.section(L.t("Son olaylar")))
	var events: Array = CardManager.province_events.get(province_id, [])
	if events.is_empty():
		_body.add_child(PopupKit.note(L.t("Bu ilde henüz bir olay yok."), UiTheme.TEXT_DIM))
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
		return maxi(1, int((maxf(size.x, ProvincePanel.panel_width - 50.0) + GAP) / (DOT + GAP)))

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
