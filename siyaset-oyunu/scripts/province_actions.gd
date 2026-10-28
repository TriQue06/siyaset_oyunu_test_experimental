class_name ProvinceActions
extends PanelContainer
## İL MENÜSÜ (0.0.269): haritada bir ile dokununca tıklanan yerin yanında
## SABİT BOYUTLU bir bağlam menüsü açılır (harita artık ikiye bölünmez).
## Ana sayfada alt alta TEŞKİLAT, MİTİNG, YATIRIM düğmeleri; birine basınca
## ayrıntısı AYNI menüde (boyut değişmeden) açılır. Üstte GERİ / İLERİ:
## tarayıcı gibi sayfalar arasında gezinir; vazgeçmek için GERİ.
##   TEŞKİLAT: en üst seviyedeyse düğme yer almaz.
##   MİTİNG ve YATIRIM: yalnız teşkilat kurulmuş ilde (miting için teşkilat şart).
##   MİTİNG: bütçe -> isteğe bağlı hitap grupları (teşkilat seviyesi kadar) ->
##     özet ve MİTİNGİ DÜZENLE. Hazırlık ya da GERİ hak ve para tüketmez.
## Kurallar ve sınırlar CardManager'da doğrulanır (sıra başına miting / yatırım sınırı lobi ayarı).

signal closed
signal info_requested(province_id: String)
signal toast_requested(text: String)

## Menünün sabit boyutu (tasarım birimi).
const MENU_SIZE := Vector2(320, 430)
const WIDTH := 320.0
var panel_width := WIDTH
const TIER_NAMES := ["KÜÇÜK", "ORTA", "BÜYÜK"]
const TIER_NOTES := ["daha az etki, paraya göre en verimli", "olağan miting", "en güçlü etki, en pahalı"]
const INVEST_NOTES := ["küçük yatırım", "olağan yatırım", "büyük yatırım; il tavanına çabuk dayanır"]
const PAGE_COLORS := {"org": Color("2569CF"), "miting": Color("D93636"), "invest": Color("2E9E52")}

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
var _nav: HBoxContainer
var _back: Button
var _forward: Button
## İLERİ ile dönülecek sayfa (GERİ'ye basınca dolar, yeni sayfa açınca silinir).
var _forward_page := ""
var max_height := MENU_SIZE.y

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 96
	# Karton pano (masa oyunu): çift çizgi, kalınlık, masaya düşen gölge.
	var style := UiSkin.board()
	style.set_content_margin_all(UiTheme.d(20))
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = MENU_SIZE
	size = MENU_SIZE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	_nav = HBoxContainer.new()
	_nav.add_theme_constant_override("separation", 6)
	column.add_child(_nav)
	_back = _nav_button(L.t("GERİ"), go_back)
	_nav.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav.add_child(spacer)
	_forward = _nav_button(L.t("İLERİ"), go_forward)
	_nav.add_child(_forward)
	var x := _nav_button("X", close)
	x.custom_minimum_size.x = 40
	_nav.add_child(x)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	hide()

func _nav_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(74, 34)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 13)
	UiSkin.skin_color_button(button, UiTheme.TEAL)
	button.pressed.connect(action)
	return button

## Menü tıklanan noktanın yanına oturur (sağa sığmazsa soluna), bounds içinde kalır.
func place_at(point: Vector2, bounds: Rect2) -> void:
	var pos := point + Vector2(18, -MENU_SIZE.y * 0.4)
	if pos.x + MENU_SIZE.x > bounds.end.x:
		pos.x = point.x - 18 - MENU_SIZE.x
	pos.x = clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - MENU_SIZE.x))
	pos.y = clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - MENU_SIZE.y))
	position = pos.round()

## Eski çağrılar için (önizleme betikleri): menü dikdörtgenin içine oturur.
func set_panel_rect(rect: Rect2) -> void:
	place_at(rect.position, rect)

func open(p_province: String) -> void:
	var fresh := p_province != province_id or not visible
	if p_province != province_id:
		_reset_miting()
		_invest_tier = CardManager.DEFAULT_TIER
	if fresh:
		tab = ""
		_forward_page = ""
	province_id = p_province
	size = MENU_SIZE
	var was_visible := visible
	show()
	refresh()
	if not was_visible:
		pivot_offset = MENU_SIZE * 0.5
		scale = Vector2(0.85, 0.85)
		modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "modulate:a", 1.0, 0.12)

func _reset_miting() -> void:
	_miting_tier = CardManager.DEFAULT_TIER
	_focus = []
	_smear = -1

func close() -> void:
	hide()
	province_id = ""
	tab = ""
	_forward_page = ""
	closed.emit()

## Sayfa aç (ana menüden): ileri geçmişi silinir.
func open_page(page: String) -> void:
	tab = page
	_forward_page = ""
	_scroll.scroll_vertical = 0
	refresh()

## GERİ: ayrıntıdan ana menüye (miting hazırlığı bırakılır, hak ve para gitmez).
func go_back() -> void:
	if tab == "":
		return
	_forward_page = tab
	tab = ""
	refresh()

## İLERİ: GERİ ile çıkılan sayfaya dön (seçimler korunur).
func go_forward() -> void:
	if _forward_page == "" or not _page_available(_forward_page):
		return
	tab = _forward_page
	_forward_page = ""
	refresh()

func refresh() -> void:
	if province_id == "" or not visible:
		return
	if tab != "" and not _page_available(tab):
		tab = ""
	var keep := _scroll.scroll_vertical
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_back.disabled = tab == ""
	_forward.disabled = _forward_page == "" or not _page_available(_forward_page)
	_build_header()
	match tab:
		"org":
			_build_org()
		"miting":
			_build_miting()
		"invest":
			_build_invest()
		_:
			_build_menu()
	size = MENU_SIZE
	_fit.call_deferred(keep)

func _fit(keep: int) -> void:
	size = MENU_SIZE
	_scroll.scroll_vertical = keep

## Ana menüde hangi düğmeler var: teşkilat en üst seviyedeyse yok; miting ve
## yatırım yalnız teşkilatlı ilde.
func _page_available(page: String) -> bool:
	var me := multiplayer.get_unique_id()
	var level := CardManager.organization_level(province_id, me)
	# Bağımsız siyasetçinin teşkilatı olmaz: her ilde miting yapar.
	if PartyManager.is_independent(me):
		return page == "miting"
	match page:
		"org":
			return level < GameRules.ORG_MAX_LEVEL
		"miting":
			return level > 0
		"invest":
			# Yatırımı yalnız hükümetteki partinin genel başkanı yapar.
			return level > 0 and CardManager.is_government_party(me) and not CardManager.is_party_member(me)
	return false

# --- Başlık ve ana menü ------------------------------------------------------------

func _build_header() -> void:
	var title := UiTheme.mono_label(ElectionNightSim.province_name(province_id), 20, UiTheme.TEXT, true)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.add_child(title)
	var me := multiplayer.get_unique_id()
	var sub := PopupKit.label(L.t("%d vekil · teşkilatın: %s") % [CardManager.province_seat_count(province_id),
		_level_name(CardManager.organization_level(province_id, me))], 12, UiTheme.TEXT_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(sub)
	if tab != "":
		_section({"org": L.t("Teşkilat"), "miting": L.t("Miting"), "invest": L.t("Yatırım")}.get(tab, ""))

func _build_menu() -> void:
	var me := multiplayer.get_unique_id()
	var level := CardManager.organization_level(province_id, me)
	var limit := CardManager.action_limit(me)
	var any := false
	if _page_available("org"):
		any = true
		var cost := CardManager.org_cost_for(me, province_id)
		_body.add_child(_menu_button("org", L.t("TEŞKİLAT KUR") if level == 0 else L.t("TEŞKİLATI GELİŞTİR"),
			"%s · %s" % [_level_name(level + 1), GameRules.cost_text(cost)]))
	if _page_available("miting"):
		any = true
		_body.add_child(_menu_button("miting", L.t("MİTİNG"), L.t("bu sıra %d/%d hakkın kaldı") % [limit - CardManager.miting_count(me), limit]))
	if _page_available("invest"):
		any = true
		_body.add_child(_menu_button("invest", L.t("YATIRIM"), L.t("bu sıra %d/%d hakkın kaldı") % [limit - CardManager.invest_count(me), limit]))
	if level == 0 and not PartyManager.is_independent(me):
		_body.add_child(PopupKit.note(L.t("Miting ve yatırım için önce bu ilde teşkilat kur."), UiTheme.TEXT_MUTED))
	elif not any:
		_body.add_child(PopupKit.note(L.t("Bu ilde yapılacak hamle yok."), UiTheme.TEXT_MUTED))
	var info := Button.new()
	info.text = L.t("İL BİLGİSİ")
	info.focus_mode = Control.FOCUS_NONE
	info.custom_minimum_size = Vector2(0, 38)
	info.add_theme_font_size_override("font_size", 13)
	UiSkin.skin_button(info)
	info.pressed.connect(func(): info_requested.emit(province_id))
	_body.add_child(info)

## Ana menüde alt alta duran büyük renkli düğme: başlık ve altında kısa bilgi.
func _menu_button(page: String, title: String, sub: String) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 66)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiSkin.skin_color_button(button, PAGE_COLORS[page])
	var texts := VBoxContainer.new()
	texts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texts.offset_bottom = -UiTheme.d(6)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(texts)
	var head := UiTheme.mono_label(title, 20, UiTheme.ON_COLOR, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin._text_shadow(head, true)
	texts.add_child(head)
	var small := PopupKit.label(sub, 12, Color(UiTheme.ON_COLOR, 0.9))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(small)
	button.pressed.connect(open_page.bind(page))
	return button

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
	_body.add_child(PopupKit.note(L.t("%d seçmen grubu seç (zorunlu). Büyük illerde 2, küçük illerde 1 grup hedeflenir.") % slots, UiTheme.TEXT_MUTED))
	if slots > 0:
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
	_body.add_child(PopupKit.kv(L.t("Hitap"), ", ".join(names) if not names.is_empty() else L.t("seçilmedi")))
	_body.add_child(PopupKit.kv(L.t("Provokasyon riski"), EffectWords.risk(CardManager.miting_risk(me, province_id))))
	var gains := _gain_preview(me)
	if gains != "":
		_body.add_child(PopupKit.note(L.t("Beklenen hitap: %s") % gains, UiTheme.GREEN))
	_body.add_child(PopupKit.kv(L.t("Toplam bedel"), GameRules.cost_text(cost), UiTheme.HEAD))
	var funded := CardManager.can_miting(me, province_id, 0.0, _miting_tier, _smear)
	var ok := funded and _focus.size() == slots
	if not funded:
		_body.add_child(PopupKit.note(L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(cost), UiTheme.RED))
	elif not ok:
		_body.add_child(PopupKit.note(L.t("Mitingi düzenlemek için %d seçmen grubu seç.") % slots, UiTheme.RED))
	_body.add_child(_confirm_button(L.t("MİTİNGİ DÜZENLE · %s") % GameRules.cost_text(cost), ok, func(): _do_miting()))

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
