class_name ProvinceActions
extends PanelContainer
## İL İŞLEM PANELİ (0.0.231): sıram gelince haritada bir ile dokununca harita
## paneli ikiye bölünür (0.0.232): harita solda, bu panel aynı alanın sağ
## yarısında. Üç başlık: TEŞKİLAT, MİTİNG, YATIRIM; birine basınca yalnız
## onun ayrıntısı açılır.
##   MİTİNG: bütçe (küçük / orta / büyük) → isteğe bağlı hitap grupları (teşkilat
##     seviyesi kadar; varsayılan genel halk) → özet ve MİTİNGİ DÜZENLE
##     (karalama 0.0.237'den beri yine ayrı kart). Hazırlık ya da iptal hak ve
##     para tüketmez; kart yalnız son onayda elden çıkar.
##   YATIRIM: sadece hükümet partisi; bütçe → etki özeti → onay.
## Kurallar ve sınırlar CardManager'da doğrulanır (sıra başına miting / yatırım sınırı lobi ayarı).

signal closed
signal info_requested(province_id: String)
signal toast_requested(text: String)

## Varsayılan genişlik (yerleşimde harita alanının sağ yarısına oturur).
const WIDTH := 380.0
var panel_width := WIDTH
const TIER_NAMES := ["KÜÇÜK", "ORTA", "BÜYÜK"]
const TIER_NOTES := ["daha az etki, paraya göre en verimli", "olağan miting", "en güçlü etki, en pahalı"]
const INVEST_NOTES := ["küçük yatırım", "olağan yatırım", "büyük yatırım; il tavanına çabuk dayanır"]

var province_id := ""
var tab := ""
var _miting_tier := CardManager.DEFAULT_TIER
var _focus: Array = []
## Karalama kararı: -2 = karar yok (kart elde kalır), -1 = sakla, parti id = kullan.
var _smear := -1
var _invest_tier := CardManager.DEFAULT_TIER
var _sent_version := -1
var _scroll: ScrollContainer
var _body: VBoxContainer
var max_height := 440.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 96
	# Haritanın yanında karton pano (masa oyunu).
	var style := UiSkin.board()
	style.set_content_margin_all(UiTheme.PAD_S + 4)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(WIDTH, 0)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	hide()

## Panel harita alanının sağ yarısına oturur (sabit boyut, içerik kayar).
func set_panel_rect(rect: Rect2) -> void:
	panel_width = rect.size.x
	max_height = rect.size.y
	position = rect.position
	custom_minimum_size = rect.size
	size = rect.size
	_body.custom_minimum_size = Vector2(panel_width - 28.0, 0)
	if visible:
		refresh()

func open(p_province: String) -> void:
	if p_province != province_id:
		tab = ""
		_reset_miting()
		_invest_tier = CardManager.DEFAULT_TIER
	province_id = p_province
	show()
	refresh()

func _reset_miting() -> void:
	_miting_tier = CardManager.DEFAULT_TIER
	_focus = []
	_smear = -1

func close() -> void:
	hide()
	province_id = ""
	tab = ""
	closed.emit()

func refresh() -> void:
	if province_id == "" or not visible:
		return
	var keep := _scroll.scroll_vertical
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_build_header()
	_build_tabs()
	match tab:
		"org":
			_build_org()
		"miting":
			_build_miting()
		"invest":
			_build_invest()
		_:
			_body.add_child(PopupKit.note(L.t("Bu ilde ne yapmak istiyorsun? Bir başlık seç."), UiTheme.TEXT_MUTED))
	_fit.call_deferred(keep)

func _fit(keep: int) -> void:
	_scroll.custom_minimum_size = Vector2(panel_width - 20.0, max_height - 24.0)
	size = Vector2(panel_width, max_height)
	_scroll.scroll_vertical = keep

# --- Başlık ve sekmeler ------------------------------------------------------------

func _build_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_body.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	# Başlık yazıları paneli genişletmesin (dar ekranda harita alanından taşmasın).
	var title := UiTheme.mono_label(ElectionNightSim.province_name(province_id), 20, UiTheme.TEXT, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var me := multiplayer.get_unique_id()
	var sub := PopupKit.label(L.t("%d vekil · teşkilatın: %s") % [CardManager.province_seat_count(province_id),
		_level_name(CardManager.organization_level(province_id, me))], 11, UiTheme.TEXT_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 0
	texts.add_child(sub)
	var info := Button.new()
	info.text = L.t("İL BİLGİSİ")
	info.focus_mode = Control.FOCUS_NONE
	info.custom_minimum_size = Vector2(90, 40)
	info.add_theme_font_size_override("font_size", 11)
	UiSkin.skin_button(info)
	info.pressed.connect(func(): info_requested.emit(province_id))
	row.add_child(info)
	var x := Button.new()
	x.text = "X"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(44, 40)
	UiSkin.skin_button(x)
	x.pressed.connect(close)
	row.add_child(x)

func _build_tabs() -> void:
	var me := multiplayer.get_unique_id()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_body.add_child(row)
	var specs := [
		["org", L.t("TEŞKİLAT"), Color("2569CF")],
		["miting", L.t("MİTİNG %d/%d") % [CardManager.action_limit(me) - CardManager.miting_count(me), CardManager.action_limit(me)], Color("F2132A")],
		["invest", L.t("YATIRIM %d/%d") % [CardManager.action_limit(me) - CardManager.invest_count(me), CardManager.action_limit(me)], Color("31C440")],
	]
	for spec in specs:
		var key := String(spec[0])
		var button := Button.new()
		button.text = String(spec[1])
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 44)
		button.clip_text = true
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", 12)
		var color: Color = spec[2]
		UiSkin.skin_color_button(button, color if tab == key else color.lerp(UiTheme.PANEL_LIGHT, 0.55))
		button.pressed.connect(func():
			tab = "" if tab == key else key
			refresh())
		row.add_child(button)

func _section(title: String) -> void:
	_body.add_child(PopupKit.section(title))

func _choice_button(text: String, selected: bool, color: Color, action: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Uzun grup adları kırpılmaz, iki satıra iner; satırdaki düğmeler aynı boyda.
	button.custom_minimum_size = Vector2(0, 48)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", 11)
	UiSkin.skin_color_button(button, color if selected else color.lerp(UiTheme.PANEL_LIGHT, 0.55))
	if selected:
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(key, UiTheme.GOLD.lightened(0.3))
	button.pressed.connect(action)
	return button

func _confirm_button(text: String, enabled: bool, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 50)
	button.disabled = not enabled
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 15)
	UiSkin.skin_color_button(button, UiTheme.GREEN_DARK if enabled else UiTheme.PANEL_LIGHT)
	button.pressed.connect(action)
	return button

## Aynı durum sürümünde ikinci onay gönderilmez (çift tık, çift ücret yok).
func _first_send() -> bool:
	if _sent_version == CardManager.state_version:
		return false
	_sent_version = CardManager.state_version
	return true

static func _level_name(level: int) -> String:
	match level:
		1:
			return L.t("1. seviye")
		2:
			return L.t("2. seviye (en üst)")
	return L.t("yok")

static func org_level_text(level: int) -> String:
	match level:
		1:
			return L.t("az oy bonusu, yaklaşık anket, mitingte bir gruba hitap")
		2:
			return L.t("yüksek oy bonusu, isabetli anket, mitingte iki gruba hitap")
	return ""

# --- TEŞKİLAT ----------------------------------------------------------------------

func _build_org() -> void:
	var me := multiplayer.get_unique_id()
	var level := CardManager.organization_level(province_id, me)
	_section(L.t("Teşkilat"))
	_body.add_child(PopupKit.note(L.t("İlde kalıcı oy, anket bilgisi ve her sıra yerel bağış getirir; mitingte gruplara hitap etmeni sağlar."), UiTheme.TEXT_MUTED))
	_body.add_child(PopupKit.kv(L.t("Şu an"), _level_name(level)))
	if level > 0:
		_body.add_child(PopupKit.kv(L.t("Sıra başı yerel bağış"), GameRules.cost_text(float(GameRules.ORG_INCOME[clampi(level, 0, 2)]))))
	if PartyManager.is_independent(me):
		_body.add_child(PopupKit.note(L.t("Bağımsız siyasetçinin teşkilatı olmaz."), UiTheme.RED))
		return
	if CardManager.is_party_member(me):
		_body.add_child(PopupKit.note(L.t("Teşkilatı partinin genel başkanı kurar."), UiTheme.RED))
		return
	if level >= GameRules.ORG_MAX_LEVEL:
		_body.add_child(PopupKit.note(L.t("Bu ildeki teşkilatın en üst seviyede."), UiTheme.GREEN))
		return
	var cost := CardManager.org_cost_for(me, province_id)
	_body.add_child(PopupKit.kv(L.t("Sonraki seviye"), _level_name(level + 1)))
	_body.add_child(PopupKit.note(L.t("Getirisi: %s; sıra başı %s yerel bağış.") % [org_level_text(level + 1),
		GameRules.cost_text(float(GameRules.ORG_INCOME[level + 1]))], UiTheme.GREEN))
	var ok := CardManager.can_build_organization(me, province_id)
	if not ok and CardManager.funds_of(me) < cost:
		_body.add_child(PopupKit.note(L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(cost), UiTheme.RED))
	_body.add_child(_confirm_button((L.t("TEŞKİLAT KUR · %s") if level == 0 else L.t("TEŞKİLATI GELİŞTİR · %s")) % GameRules.cost_text(cost), ok, func():
		if not _first_send():
			return
		CardManager.build_organization(province_id)
		toast_requested.emit(L.t("%s teşkilatı: %s") % [ElectionNightSim.province_name(province_id), _level_name(level + 1)])))

# --- MİTİNG ------------------------------------------------------------------------

func _build_miting() -> void:
	var me := multiplayer.get_unique_id()
	var left := CardManager.action_limit(me) - CardManager.miting_count(me)
	if left <= 0:
		_body.add_child(PopupKit.note(L.t("Bu sıra %d mitingin hepsini yaptın. Sonraki sıranda yeniden miting yapabilirsin.") % CardManager.action_limit(me), UiTheme.RED))
		return
	_body.add_child(PopupKit.note(L.t("Miting ilde oy kazandırır ve partini ilin seçmen gruplarına yaklaştırır. Seçmen sana uzaksa provokasyon riski vardır."), UiTheme.TEXT_MUTED))
	# 1) BÜTÇE
	_section(L.t("1 · Bütçe"))
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 4)
	_body.add_child(tiers)
	for t in CardManager.MITING_TIERS.size():
		tiers.add_child(_choice_button("%s\n%s" % [L.t(TIER_NAMES[t]), GameRules.cost_text(CardManager.miting_tier_cost(t))],
			_miting_tier == t, Color("F2132A"), func():
				_miting_tier = t
				refresh()))
	_body.add_child(PopupKit.note(L.t(TIER_NOTES[_miting_tier]), UiTheme.TEXT_MUTED))
	# 2) HİTAP
	var slots := CardManager.miting_focus_slots(me, province_id)
	_section(L.t("2 · Kime hitap edeceksin?"))
	if slots <= 0:
		_body.add_child(PopupKit.note(L.t("Bu ilde teşkilatın yok: miting genel halka hitap eder. Teşkilat kurarsan belirli gruplara seslenebilirsin."), UiTheme.TEXT_MUTED))
	else:
		_body.add_child(PopupKit.note(L.t("İsteğe bağlı: en çok %d grup seç. Seçmezsen genel halka hitap edersin.") % slots, UiTheme.TEXT_MUTED))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		_body.add_child(grid)
		var profile := CardManager.province_profile(province_id)
		for group in VoterGroups.GROUP_IDS:
			var selected := _focus.has(group)
			var full := _focus.size() >= slots and not selected
			grid.add_child(_choice_button("%s %%%d" % [VoterGroups.title(group), int(roundf(VoterGroups.share(profile, group) * 100.0))],
				selected, VoterGroups.color(group), func():
					if _focus.has(group):
						_focus.erase(group)
					elif _focus.size() < slots:
						_focus.append(group)
					refresh(), not full))
	_smear = -1  # 0.0.237: karalama yine ayrı kart (elden ile sürükle)
	# 3) ÖZET
	_section(L.t("Özet"))
	var cost := CardManager.miting_tier_cost(_miting_tier)
	_body.add_child(PopupKit.kv(L.t("İl"), ElectionNightSim.province_name(province_id)))
	_body.add_child(PopupKit.kv(L.t("Bütçe"), "%s · %s" % [L.t(TIER_NAMES[_miting_tier]), GameRules.cost_text(cost)]))
	var names: PackedStringArray = []
	for group in _focus:
		names.append(VoterGroups.title(String(group)))
	_body.add_child(PopupKit.kv(L.t("Hitap"), ", ".join(names) if not names.is_empty() else L.t("genel halk")))
	_body.add_child(PopupKit.kv(L.t("Provokasyon riski"), EffectWords.risk(CardManager.miting_risk(me, province_id))))
	var gains := _gain_preview(me)
	if gains != "":
		_body.add_child(PopupKit.note(L.t("Beklenen hitap: %s") % gains, UiTheme.GREEN))
	_body.add_child(PopupKit.kv(L.t("Toplam bedel"), GameRules.cost_text(cost), UiTheme.HEAD))
	var ok := CardManager.can_miting(me, province_id, 0.0, _miting_tier, _smear)
	if not ok:
		_body.add_child(PopupKit.note(L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(cost), UiTheme.RED))
	_body.add_child(_confirm_button(L.t("MİTİNGİ DÜZENLE · %s") % GameRules.cost_text(cost), ok, func(): _do_miting()))
	var cancel := Button.new()
	cancel.text = L.t("Hazırlığı iptal et")
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 40)
	UiSkin.skin_button(cancel)
	cancel.pressed.connect(func():
		_reset_miting()
		tab = ""
		refresh())
	_body.add_child(cancel)

func _gain_preview(me: int) -> String:
	var parts: PackedStringArray = []
	var gains := CardManager.miting_group_gains(me, province_id, _focus, CardManager.miting_tier_mult(_miting_tier))
	gains.sort_custom(func(a, b): return float(a["gain"]) > float(b["gain"]))
	for item in gains.slice(0, 3):
		if float(item["gain"]) > 0.0:
			parts.append(VoterGroups.title(String(item["group"])))
	return ", ".join(parts)

## Miting her zaman parti kasasından (0.0.238).
func _do_miting() -> void:
	var me := multiplayer.get_unique_id()
	if not _first_send():
		return
	if not CardManager.can_miting(me, province_id, 0.0, _miting_tier, _smear):
		_sent_version = -1
		toast_requested.emit(CardManager.funding_block_reason(me, "miting", 0.0, CardManager.miting_tier_cost(_miting_tier)))
		return
	CardManager.miting(province_id, 0.0, _focus.duplicate(), _miting_tier, _smear)
	_reset_miting()

# --- YATIRIM -----------------------------------------------------------------------

func _build_invest() -> void:
	var me := multiplayer.get_unique_id()
	if not CardManager.is_government_party(me):
		_body.add_child(PopupKit.note(L.t("Yatırımı yalnız hükümetteki partiler yapabilir. Muhalefetteyken bu ilde teşkilat ve miting kullanabilirsin."), UiTheme.TEXT_MUTED))
		return
	if CardManager.is_party_member(me):
		_body.add_child(PopupKit.note(L.t("Yatırımı partinin genel başkanı yapar."), UiTheme.TEXT_MUTED))
		return
	var left := CardManager.action_limit(me) - CardManager.invest_count(me)
	if left <= 0:
		_body.add_child(PopupKit.note(L.t("Bu sıra %d yatırımın hepsini yaptın.") % CardManager.action_limit(me), UiTheme.RED))
		return
	_body.add_child(PopupKit.note(L.t("Devlet hazinesinden il yatırımı: ildeki bütün seçmen memnun olur, ekonomi canlanır. Partinin hazine kotası bakanlık payına göredir."), UiTheme.TEXT_MUTED))
	_section(L.t("1 · Bütçe"))
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 4)
	_body.add_child(tiers)
	for t in CardManager.INVEST_TIERS.size():
		tiers.add_child(_choice_button("%s\n%s" % [L.t(TIER_NAMES[t]), Economy.money_full(CardManager.invest_tier_cost(t))],
			_invest_tier == t, Color("31C440"), func():
				_invest_tier = t
				refresh()))
	_body.add_child(PopupKit.note(L.t(INVEST_NOTES[_invest_tier]), UiTheme.TEXT_MUTED))
	_section(L.t("Özet"))
	var amount := CardManager.invest_tier_cost(_invest_tier)
	_body.add_child(PopupKit.kv(L.t("İl"), ElectionNightSim.province_name(province_id)))
	_body.add_child(PopupKit.kv(L.t("Tutar"), Economy.money_full(amount)))
	_body.add_child(PopupKit.note(L.t("Etkinin bir kısmı hemen, kalanı sonraki %d dönemde gelir; seçimde yalnız gelmiş olan sayılır.") % Economy.INVEST_DELAY_ROUNDS, UiTheme.GREEN))
	_body.add_child(PopupKit.kv(L.t("Hazine kotan"), Economy.money_full(CardManager.state_quota(me))))
	var quota := CardManager.state_quota(me)
	if quota < amount - 0.001:
		_body.add_child(PopupKit.note(L.t("Hazine kotan yetmiyor (%s kaldı). Daha küçük bir yatırım seç.") % Economy.money_full(quota), UiTheme.RED))
	var ok := CardManager.can_invest(me, province_id, 1.0, _invest_tier)
	_body.add_child(_confirm_button(L.t("YATIRIMI YAP · %s") % Economy.money_full(amount), ok, func():
		if not _first_send():
			return
		if CardManager.can_invest(me, province_id, 1.0, _invest_tier):
			CardManager.invest(province_id, 1.0, _invest_tier)
		else:
			_sent_version = -1
			toast_requested.emit(CardManager.funding_block_reason(me, "invest", 1.0, amount))))
