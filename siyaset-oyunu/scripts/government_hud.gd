class_name GovernmentHud
extends RefCounted
## Oyun ekranının sol panelindeki kategoriler (hükümet, puan tablosu) ve
## meclis durum metni. Hepsi mevcut autoload durumundan okuyarak çizer,
## kendi durumu yoktur.

const BADGE_SIZE := Vector2(26, 26)
const BADGE_ICON_PIXEL_SIZE := 48
const TITLE_COLOR := UiTheme.TEXT_MUTED
const DIM_COLOR := UiTheme.TEXT_MUTED

static func party_name_of(peer_id: int) -> String:
	return PartyManager.data_of(peer_id).get("name", "?")

static func leader_name_of(peer_id: int) -> String:
	return PoliticianPresets.display_name(peer_id)

static func _clear(box: Container) -> void:
	for child in box.get_children():
		child.queue_free()

static func _label(text: String, font_size: int, modulate: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.modulate = modulate
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
	badge.tooltip_text = party_name_of(peer_id)
	return badge

## "Başbakan [logo] Parti  ·  Yrd. [logo]" — TEK SATIR.
## Dar sol panelde iki parti adı yan yana sığmıyor, ikisi de kırpılıyordu;
## bu yüzden yardımcının partisi sadece LOGOSUYLA gösterilir (adı ipucunda).
static func _leadership_row(pm: int, deputy: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var pm_label := _label(L.t("Başbakan"), 12, DIM_COLOR)
	row.add_child(pm_label)
	var chip := _party_chip(pm, true)
	row.add_child(chip)
	var used := pm_label.get_combined_minimum_size().x + 28.0 + 16.0
	if deputy != -1:
		var dep_label := _label(L.t("·  Yrd."), 12, DIM_COLOR)
		row.add_child(dep_label)
		row.add_child(_party_chip(deputy, false))
		used += dep_label.get_combined_minimum_size().x + 28.0 + 12.0
	# Parti adı KISALTILMAZ: sığmazsa yazısı küçülür (sütun ~256 px).
	var name_label := chip.get_node_or_null("Name") as Label
	if name_label != null:
		var room := 250.0 - used
		var font := name_label.get_theme_font("font")
		var size := 13
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
	chip.tooltip_text = party_name_of(peer_id)
	# Kalan genişliği ADI GÖSTEREN öbek alır; sadece logo olan öbek büzülür.
	if show_name:
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.add_child(_badge(peer_id))
	if show_name:
		var name_label := _label(party_name_of(peer_id), 13)
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
		title.modulate = UiTheme.GOLD
		box.add_child(title)
		_fill_cabinet(box, GovernmentManager.proposal_assignments)
		return

	box.add_child(section_title(L.t("HÜKÜMET")))
	if not GovernmentManager.has_government():
		box.add_child(_label(L.t("Hükümet yok"), 13, DIM_COLOR))
		return
	_fill_cabinet(box, GovernmentManager.government)

	var me := box.multiplayer.get_unique_id()
	if GovernmentManager.can_withdraw(me):
		var withdraw := Button.new()
		UiSkin.skin_button(withdraw)
		withdraw.text = L.t("Koalisyondan Çekil")
		withdraw.add_theme_font_size_override("font_size", 12)
		UiSkin.set_side_icon(withdraw, "koalisyondan_cekil", 16)
		withdraw.tooltip_text = L.t("Görevlerin ana iktidar partisine geçer. Puan tablon etkilenmez ama kamuoyunda bir miktar destek kaybedersin. Ortağın yalnız kalıp gensoruyla düşerse o %d puan kaybeder.") % GovernmentPresets.ABANDONED_FALL_PENALTY
		withdraw.pressed.connect(func():
			if bool(withdraw.get_meta("armed", false)):
				GovernmentManager.withdraw_from_coalition()
			else:
				withdraw.set_meta("armed", true)
				withdraw.text = L.t("Emin misin? Tekrar dokun (ortağın yalnız düşerse −%d)") % GovernmentPresets.ABANDONED_FALL_PENALTY
		)
		box.add_child(withdraw)

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
	var ministry_title := _label(L.t("Bakanlıklar"), 12, DIM_COLOR)
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
		chip.add_child(_label("×%d" % int(ministries[peer_id]), 14))
		chips.add_child(chip)
	ministry_row.add_child(chips)
	box.add_child(ministry_row)

	var seats := 0
	for peer_id in party_ids:
		seats += GovernmentManager.seats_of(peer_id)
	var total := GovernmentManager.total_seats()
	var majority: bool = seats * 2 > total
	box.add_child(_label(L.t("%d/%d sandalye — %s") % [seats, total, L.t("çoğunluk var") if majority else L.t("AZINLIK")],
		UiTheme.FS_TINY, UiTheme.TEXT_MUTED if majority else UiTheme.RED))

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
			"short": L.t("Vergi %s → %s: seçmen tepkisi kademeli gelir, en çok başbakanın partisi hisseder") % [now, Economy.tax_title(level)]}
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
				return "ANAYASA DEĞİŞİKLİĞİ oylanıyor — %s getirdi · baraj %%%s, seçimler %d yılda bir, sayım: %s%s
EVET %d / gereken %d (2/3) · %s kaldı%s" % [
					party_name_of(GovernmentManager.proposal_peer_id),
					String.num(float(payload.get("threshold", 0.0)), 1), int(payload.get("interval", 0)),
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
