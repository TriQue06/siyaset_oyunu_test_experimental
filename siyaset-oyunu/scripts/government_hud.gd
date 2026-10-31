class_name GovernmentHud
extends RefCounted
## Oyun ekranının sol panelindeki kategoriler (hükümet, puan tablosu) ve
## meclis durum metni. Hepsi mevcut autoload durumundan okuyarak çizer,
## kendi durumu yoktur.

## Konsept .gov .chipico: 32 px pul.
const BADGE_SIZE := Vector2(32.0 / 1.5, 32.0 / 1.5)
const BADGE_ICON_PIXEL_SIZE := 48
const TITLE_COLOR := UiTheme.TEXT_MUTED
const DIM_COLOR := UiTheme.TEXT_MUTED

## Hükümet panelinde açık onay satırı ("" / "withdraw" / "dissolve").
static var _confirming := ""

static func party_name_of(peer_id: int) -> String:
	return PartyManager.data_of(peer_id).get("name", "?")

static func leader_name_of(peer_id: int) -> String:
	return PoliticianPresets.display_name(peer_id)

static func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

## Konsept .gov: anahtar Nunito 800 (soluk), değer Siyaset Display (koyu).
static func _label(text: String, font_size: int, color: Color = UiTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if color == DIM_COLOR:
		label.add_theme_font_override("font", UiTheme.mono_regular())
	else:
		label.add_theme_font_override("font", UiTheme.mono(true))
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

## Bölüm başlığı: monospace, altın, "> " önekli (tarzın imzası).
static func section_title(text: String) -> Label:
	return UiTheme.section_label(text)

## Monospace etiket: tablodaki sayılar sütun sütun hizalansın.
static func _mono_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, Color.WHITE)
	label.add_theme_font_override("font", UiTheme.mono())
	label.add_theme_color_override("font_color", color)
	return label

static func _badge(peer_id: int) -> Control:
	var badge := PartyBadge.build(PartyManager.data_of(peer_id), BADGE_SIZE, BADGE_ICON_PIXEL_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge

## "Başbakan [logo] Parti  ·  Yrd. [logo]" — TEK SATIR.
## Dar sol panelde iki parti adı yan yana sığmıyor, ikisi de kırpılıyordu;
## bu yüzden yardımcının partisi sadece LOGOSUYLA gösterilir (adı ipucunda).
## 0.0.302 (avatar konsepti A): Başbakan ve Yardımcısı yan yana iki kartta,
## genel başkanlarının avatarıyla (parti logosu madalyonun köşesinde).
static func _leadership_row(pm: int, deputy: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_post_card(L.t("Başbakan"), pm))
	row.add_child(_post_card(L.t("Başbakan Yrd."), deputy))
	return row

static func _post_card(title: String, pid: int) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := BoardBox.new()
	style.fill = Color("fffaf0")
	style.set_radius(13)
	style.rings = [[0.0, 1.5, Color("e3d5b0")]]
	style.lips = [[3.0, Color("c9b689")]]
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	style.content_margin_left = 4
	style.content_margin_right = 4
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var key := _label(title.to_upper(), 9, DIM_COLOR)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key)
	if pid == -1:
		var none := _label("—", 16)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
		return card
	var medal := AvatarMedal.make(PoliticianPresets.of(pid), PartyManager.data_of(pid), 46.0)
	medal.tooltip_text = party_name_of(pid)
	box.add_child(medal)
	var person := _label(leader_name_of(pid), 11)
	person.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	person.clip_text = true
	person.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(person)
	var party := _label(party_name_of(pid), 9, DIM_COLOR)
	party.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	party.clip_text = true
	party.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(party)
	return card

## Eski tek satırlık başkan / yardımcı satırı (kullanılmıyor, önizlemeler için).
static func _leadership_row_compact(pm: int, deputy: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var pm_label := _label(L.t("Başbakan"), UiTheme.fs(16), DIM_COLOR)
	row.add_child(pm_label)
	var chip := _party_chip(pm, true)
	row.add_child(chip)
	var used := pm_label.get_combined_minimum_size().x + 28.0 + 16.0
	if deputy != -1:
		var dep_label := _label(L.t("Yrd."), UiTheme.fs(16), DIM_COLOR)
		row.add_child(dep_label)
		row.add_child(_party_chip(deputy, false))
		used += dep_label.get_combined_minimum_size().x + 28.0 + 12.0
	# Parti adı KISALTILMAZ: sığmazsa yazısı küçülür (sütun ~256 px).
	var name_label := chip.get_node_or_null("Name") as Label
	if name_label != null:
		var room := 250.0 - used
		var font := name_label.get_theme_font("font")
		var size := UiTheme.fs(20)
		while size > 8 and font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > room:
			size -= 1
		name_label.add_theme_font_size_override("font_size", size)
	return row

## Küçük "logo (+ parti adı)" öbeği. Ad gösterilmese de ipucunda durur.
static func _party_chip(peer_id: int, show_name: bool) -> Control:
	if peer_id == -1:
		return _label("—", 13)
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	# Kalan genişliği ADI GÖSTEREN öbek alır; sadece logo olan öbek büzülür.
	if show_name:
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.add_child(_badge(peer_id))
	if show_name:
		var name_label := _label(party_name_of(peer_id), UiTheme.fs(20))
		name_label.name = "Name"
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_child(name_label)
	return chip

## "Başbakan: [logo] Parti" satırı.
static func _post_row(title: String, peer_id: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var title_label := _label(title, 12, DIM_COLOR)
	title_label.custom_minimum_size = Vector2(92, 0)
	row.add_child(title_label)
	if peer_id == -1:
		row.add_child(_label("—", 13))
		return row
	row.add_child(_badge(peer_id))
	var name_label := _label(party_name_of(peer_id), 13)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	return row

## Kurulu hükümet: başbakan ve yardımcısının partisi, her partinin bakanlık
## sayısı (logo + sayı) ve meclis gücü.
## Mecliste bir hükümet teklifi oylanırken kurulu hükümet yerine OYLANAN
## hükümet aynı düzende gösterilir — herkes neye oy verdiğini görsün.
static func fill_government_panel(box: VBoxContainer) -> void:
	_clear(box)
	if GovernmentManager.is_voting() and GovernmentManager.proposal_kind == GovernmentManager.KIND_GOVERNMENT:
		# İki satır: tek satırda sol paneli genişletip yandaki alanı itiyordu.
		var title := section_title(L.t("%s\n%s teklifi") % [
			L.t("KOALİSYON GÖRÜŞMESİ") if GovernmentManager.is_coalition_stage() else L.t("OYLANAN HÜKÜMET"),
			party_name_of(GovernmentManager.proposal_peer_id)])
		box.add_child(title)
		_fill_cabinet(box, GovernmentManager.proposal_assignments)
		return

	box.add_child(section_title(L.t("HÜKÜMET")))
	if not GovernmentManager.has_government():
		box.add_child(_label(L.t("Hükümet yok"), 13, DIM_COLOR))
		return
	_fill_cabinet(box, GovernmentManager.government)

	var me := box.multiplayer.get_unique_id()
	# 0.0.300: ortak "Koalisyondan Çekil", başbakan "Koalisyonu Dağıt" /
	# "Hükümetten Ayrıl". Basınca onay satırı açılır: Onayla ya da Vazgeç.
	var kind := ""
	var title := ""
	var warning := ""
	if GovernmentManager.can_withdraw(me):
		kind = "withdraw"
		title = L.t("Koalisyondan Çekil")
		warning = L.t("Görevlerin başbakanın partisine geçer. Ortağın yalnız kalıp düşerse −%d puan alır.") % GovernmentPresets.ABANDONED_FALL_PENALTY
	elif GovernmentManager.can_dissolve_government(me):
		kind = "dissolve"
		var coalition := GovernmentManager.government_party_ids().size() > 1
		title = L.t("Koalisyonu Dağıt") if coalition else L.t("Hükümetten Ayrıl")
		warning = L.t("Hükümet düşer ve yeni hükümet kurulur.")
	if kind == "":
		_confirming = ""
		return
	if _confirming != kind:
		_confirming = ""
		var leave := Button.new()
		UiSkin.skin_button(leave)
		leave.text = title
		leave.add_theme_font_size_override("font_size", 12)
		UiSkin.set_side_icon(leave, "koalisyondan_cekil", 16)
		leave.pressed.connect(func():
			_confirming = kind
			fill_government_panel.call_deferred(box))
		box.add_child(leave)
		return
	box.add_child(_label(L.t("%s: emin misin?") % title, 12))
	var hint := _label(warning, 11, DIM_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(150, 0)
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cancel := Button.new()
	UiSkin.skin_button(cancel)
	cancel.text = L.t("Vazgeç")
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func():
		_confirming = ""
		fill_government_panel.call_deferred(box))
	row.add_child(cancel)
	var confirm := Button.new()
	UiSkin.skin_color_button(confirm, UiTheme.RED_DARK)
	confirm.text = L.t("Onayla")
	confirm.add_theme_font_size_override("font_size", 12)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func():
		_confirming = ""
		if kind == "withdraw":
			GovernmentManager.withdraw_from_coalition()
		else:
			GovernmentManager.dissolve_government())
	row.add_child(confirm)
	box.add_child(row)

## government: post_id -> peer_id
static func _fill_cabinet(box: VBoxContainer, government: Dictionary) -> void:
	var party_ids: Array = []
	for post_id in government.keys():
		var owner: int = int(government[post_id])
		if not party_ids.has(owner):
			party_ids.append(owner)

	# BAŞBAKAN ve YARDIMCISI TEK SATIRDA: ikisini ayrı satıra yaymak paneli
	# gereksiz uzatıyordu, üstelik yardımcı çoğu zaman boş kalıyor.
	box.add_child(_leadership_row(
		int(government.get(GovernmentPresets.POST_PM, -1)),
		int(government.get(GovernmentPresets.POST_DEPUTY_PM, -1))))

	# Bakanlık sayıları, hükümet partilerinin sırasıyla.
	var ministries: Dictionary = {}
	for post_id in government.keys():
		if post_id == GovernmentPresets.POST_PM or post_id == GovernmentPresets.POST_DEPUTY_PM:
			continue
		var peer_id: int = int(government[post_id])
		ministries[peer_id] = int(ministries.get(peer_id, 0)) + 1

	var ministry_row := HBoxContainer.new()
	ministry_row.add_theme_constant_override("separation", 6)
	var ministry_title := _label(L.t("Bakanlıklar"), UiTheme.fs(16), DIM_COLOR)
	ministry_title.custom_minimum_size = Vector2(92, 0)
	ministry_row.add_child(ministry_title)
	var chips := HFlowContainer.new()
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_theme_constant_override("h_separation", 10)
	chips.add_theme_constant_override("v_separation", 4)
	for peer_id in party_ids:
		if not ministries.has(peer_id):
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.add_child(_badge(peer_id))
		chip.add_child(_label("×%d" % int(ministries[peer_id]), UiTheme.fs(20)))
		chips.add_child(chip)
	ministry_row.add_child(chips)
	box.add_child(ministry_row)

	var seats := 0
	for peer_id in party_ids:
		seats += GovernmentManager.seats_of(peer_id)
	var total := GovernmentManager.total_seats()
	var majority: bool = seats * 2 > total
	var summary := _label(L.t("%d/%d sandalye — %s") % [seats, total, L.t("çoğunluk var") if majority else L.t("AZINLIK")],
		UiTheme.fs(19), UiTheme.TEXT_MUTED if majority else UiTheme.ON_COLOR)
	if not majority:
		# Konsept .warn: kırmızı kurdele, koyu kalınlık, hafif eğik.
		var ribbon := BoardBox.new()
		ribbon.fill = UiTheme.CRISIS
		ribbon.set_radius(UiTheme.d(10))
		ribbon.lips = [[UiTheme.d(4), UiTheme.CRISIS_DARK]]
		ribbon.content_margin_left = UiTheme.d(14)
		ribbon.content_margin_right = UiTheme.d(14)
		ribbon.content_margin_top = UiTheme.d(5)
		ribbon.content_margin_bottom = UiTheme.d(5)
		summary.add_theme_stylebox_override("normal", ribbon)
		summary.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		summary.rotation_degrees = -1.5
		var wrap := MarginContainer.new()
		wrap.add_theme_constant_override("margin_top", int(UiTheme.d(6)))
		wrap.add_child(summary)
		box.add_child(wrap)
	else:
		box.add_child(summary)

## Yasa oylaması: 1. satır yasa ve oy durumu, 2. satır bu oyuncu için oyların
## genel etkisi (yasanın hedef seçmen grubu ve karşıtı).
static func _law_status_text(my_id: int, time_text: String) -> String:
	var law_type := GovernmentManager.proposal_law
	var totals := GovernmentManager.vote_seat_totals()
	var first := L.t("YASA: %s (%s) — %s getirdi · EVET %d / ÇEK. %d / HAYIR %d · %s") % [
		CardPresets.card_title(law_type), CardPresets.law_direction_text(law_type),
		party_name_of(GovernmentManager.proposal_peer_id), totals.x, GovernmentManager.abstain_seats(), totals.y, time_text,
	]
	if GovernmentManager.has_voted(my_id):
		return first + L.t("\nOyun: %s · diğer partilerin oyu bekleniyor") % GovernmentManager.vote_text(GovernmentManager.my_vote())
	# IPUCU SATIRI KALDIRILDI: teklifi veren parti artik parlamento
	# diyagraminin yaninda logosuyla gosteriliyor (bkz. game_screen.gd).
	return first

## Bu oyuncunun oylamadaki yeri için EVET / HAYIR ipuçları.
static func law_vote_hint(my_id: int) -> Dictionary:
	var proposer := GovernmentManager.proposal_peer_id
	if CardPresets.is_tax_law(GovernmentManager.proposal_law):
		var level := CardPresets.tax_law_level(GovernmentManager.proposal_law)
		var now := Economy.tax_title(CardManager.tax_level())
		return {"yes": L.t("EVET: vergi %s olur (gelir %s / dönem)") % [Economy.tax_title(level), Economy.money_full(CardManager.expected_revenue(level))],
			"no": L.t("HAYIR: vergi %s kalır") % now,
			"short": L.t("Vergi %s » %s: seçmen tepkisi kademeli gelir, en çok başbakanın partisi hisseder") % [now, Economy.tax_title(level)]}
	var no_text := L.t("HAYIR: yasaya yakın illerde güç kaybı, zıt illerde kazanç")
	if my_id == proposer:
		return {"yes": L.t("EVET: kabul edilirse yasanın etkisi 2 katına çıkar"), "no": no_text,
			"short": L.t("Senin yasan: kabul edilirse il etkileri 2 kat")}
	var me_gov := GovernmentManager.proposal_gov_ids.has(my_id)
	var proposer_gov := GovernmentManager.proposal_gov_ids.has(proposer)
	if me_gov and not proposer_gov:
		return {"yes": L.t("EVET: muhalefete gündem kaptırırsın — her ilde eksi, yasaya yakın illerde nötr/artı"),
			"no": no_text,
			"short": L.t("İktidardasın: muhalefetin yasasına EVET her ilde eksi (yakın illerde az) · kabul edilirse getiren güçlenir")}
	return {"yes": L.t("EVET: yasaya yakın illerde artı, zıt illerde eksi"), "no": no_text,
		"short": L.t("Etkisi il il değişir: yasaya yakın illerde EVET, zıt illerde HAYIR kazandırır")}

## Hükümet teklifi: 1/2 koalisyon görüşmesi ya da 2/2 meclis oylaması.
static func _government_status_text(my_id: int, time_text: String) -> String:
	var eligible: Array = GovernmentManager.eligible_voter_ids()
	var voted := 0
	for peer_id in eligible:
		if GovernmentManager.has_voted(peer_id):
			voted += 1
	var proposer := party_name_of(GovernmentManager.proposal_peer_id)
	if GovernmentManager.is_coalition_stage():
		var text := L.t("1/2 KOALİSYON GÖRÜŞMESİ — %s teklifi · ortak onayı %d/%d · %s") % [
			proposer, voted, eligible.size(), time_text]
		if eligible.has(my_id) and not GovernmentManager.has_voted(my_id):
			text += L.t("\nORTAK önerildin: EVET kabul, HAYIR ret (çekimser yok)")
		elif my_id == GovernmentManager.proposal_peer_id:
			text += L.t("\nOrtaklarının cevabı bekleniyor")
		return text
	var totals := GovernmentManager.vote_seat_totals()
	var text2 := L.t("2/2 MECLİS OYLAMASI — %s hükümeti · EVET %d / ÇEK. %d / HAYIR %d · %d/%d oy · %s") % [
		proposer, totals.x, GovernmentManager.abstain_seats(), totals.y, voted, eligible.size(), time_text]
	if GovernmentManager.has_voted(my_id):
		text2 += L.t("\nOyun: %s") % GovernmentManager.vote_text(GovernmentManager.my_vote())
	return text2

## Meclis butonlarının altındaki durum metni (kalan süre dahil).
static func proposal_status_text(my_id: int) -> String:
	var time_text := GameRules.format_seconds(GovernmentManager.phase_seconds_left())
	match GovernmentManager.phase:
		GovernmentManager.Phase.FORMING:
			var holder: int = GovernmentManager.mandate_peer_id()
			if holder == -1:
				return ""
			return L.t("%s hükümet kuruyor… (%d. teklif hakkı, %s)") % [
				party_name_of(holder), GovernmentManager.current_attempt_number(), time_text,
			]
		GovernmentManager.Phase.VOTING:
			if GovernmentManager.is_resolving():
				var totals := GovernmentManager.vote_seat_totals()
				return L.t("Oylama tamamlandı — EVET %d / ÇEKİMSER %d / HAYIR %d · sonuç açıklanıyor…") % [
					totals.x, GovernmentManager.abstain_seats(), totals.y]
			if GovernmentManager.proposal_kind == GovernmentManager.KIND_LAW:
				return _law_status_text(my_id, time_text)
			if GovernmentManager.proposal_kind == GovernmentManager.KIND_GOVERNMENT:
				return _government_status_text(my_id, time_text)
			var mine := ""
			if GovernmentManager.has_voted(my_id):
				mine = L.t("  (oyun: %s)") % GovernmentManager.vote_text(GovernmentManager.my_vote())
			var totals_now := GovernmentManager.vote_seat_totals()
			if GovernmentManager.proposal_kind == GovernmentManager.KIND_EARLY:
				return L.t("ERKEN SEÇİM önergesi oylanıyor — %s getirdi · EVET %d / HAYIR %d · %s kaldı%s") % [
					party_name_of(GovernmentManager.proposal_peer_id), totals_now.x, totals_now.y, time_text, mine,
				]
			if GovernmentManager.proposal_kind == GovernmentManager.KIND_CONSTITUTION:
				var payload := GovernmentManager.proposal_assignments
				var method := String(payload.get("seat_method", MultiplayerManager.seat_method))
				return L.t("ANAYASA DEĞİŞİKLİĞİ oylanıyor — %s getirdi · baraj %%%s, seçimler %s yılda bir, sayım: %s%s\nEVET %d / gereken %d (2/3) · %s kaldı%s") % [
					party_name_of(GovernmentManager.proposal_peer_id),
					String.num(float(payload.get("threshold", 0.0)), 1),
					GameRules.years_text(float(payload.get("interval", MultiplayerManager.election_interval))),
					ElectionModel.method_title(method),
					L.t(" (değişmiyor)") if method == MultiplayerManager.seat_method else L.t(" (şu an: %s)") % ElectionModel.method_title(MultiplayerManager.seat_method),
					totals_now.x, GovernmentManager.constitution_threshold_seats(), time_text, mine,
				]
			return L.t("GENSORU oylanıyor — %d/%d oy, %s kaldı%s") % [
				GovernmentManager.votes.size(), GovernmentManager.voter_ids().size(), time_text, mine,
			]
		_:
			if GovernmentManager.last_resolution_reason != "":
				return GovernmentManager.last_resolution_reason
			return ""
