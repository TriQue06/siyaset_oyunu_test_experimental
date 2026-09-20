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
	return PartyManager.parties.get(peer_id, {}).get("name", "?")

static func leader_name_of(peer_id: int) -> String:
	return MultiplayerManager.players.get(peer_id, {}).get("name", "?")

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

static func _badge(peer_id: int) -> Control:
	var badge := PartyBadge.build(PartyManager.parties.get(peer_id, {}), BADGE_SIZE, BADGE_ICON_PIXEL_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.tooltip_text = party_name_of(peer_id)
	return badge

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
		var title := section_title("%s\n%s teklifi" % [
			"KOALİSYON GÖRÜŞMESİ" if GovernmentManager.is_coalition_stage() else "OYLANAN HÜKÜMET",
			party_name_of(GovernmentManager.proposal_peer_id)])
		title.modulate = UiTheme.GOLD
		box.add_child(title)
		_fill_cabinet(box, GovernmentManager.proposal_assignments)
		return

	box.add_child(section_title("HÜKÜMET"))
	if not GovernmentManager.has_government():
		box.add_child(_label("Hükümet yok", 13, DIM_COLOR))
		return
	_fill_cabinet(box, GovernmentManager.government)

	var me := box.multiplayer.get_unique_id()
	if GovernmentManager.can_withdraw(me):
		var withdraw := Button.new()
		UiSkin.skin_button(withdraw)
		withdraw.text = "Koalisyondan Çekil"
		withdraw.add_theme_font_size_override("font_size", 12)
		withdraw.tooltip_text = "Görevlerin ana iktidar partisine geçer. Puan tablon etkilenmez; sonraki seçime yansıyan ulusal puanın bıraktığın görev sayısına göre biraz düşer. Ortağın yalnız kalıp gensoruyla düşerse o %d puan kaybeder." % GovernmentPresets.ABANDONED_FALL_PENALTY
		withdraw.pressed.connect(func():
			if bool(withdraw.get_meta("armed", false)):
				GovernmentManager.withdraw_from_coalition()
			else:
				withdraw.set_meta("armed", true)
				withdraw.text = "Emin misin? Tekrar dokun (ortağın yalnız düşerse −%d)" % GovernmentPresets.ABANDONED_FALL_PENALTY
		)
		box.add_child(withdraw)

## government: post_id -> peer_id
static func _fill_cabinet(box: VBoxContainer, government: Dictionary) -> void:
	var party_ids: Array = []
	for post_id in government.keys():
		var owner: int = int(government[post_id])
		if not party_ids.has(owner):
			party_ids.append(owner)

	box.add_child(_post_row("Başbakan", int(government.get(GovernmentPresets.POST_PM, -1))))
	box.add_child(_post_row("Başbakan Yrd.", int(government.get(GovernmentPresets.POST_DEPUTY_PM, -1))))

	# Bakanlık sayıları, hükümet partilerinin sırasıyla.
	var ministries: Dictionary = {}
	for post_id in government.keys():
		if post_id == GovernmentPresets.POST_PM or post_id == GovernmentPresets.POST_DEPUTY_PM:
			continue
		var peer_id: int = int(government[post_id])
		ministries[peer_id] = int(ministries.get(peer_id, 0)) + 1

	var ministry_row := HBoxContainer.new()
	ministry_row.add_theme_constant_override("separation", 6)
	var ministry_title := _label("Bakanlıklar", 12, DIM_COLOR)
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
	box.add_child(_label("%d/%d sandalye — %s" % [seats, total, "çoğunluk var" if majority else "AZINLIK"],
		UiTheme.FS_TINY, UiTheme.TEXT_MUTED if majority else UiTheme.RED))

## Puan tablosu: logo, parti adı, oyuncu adı ve sağda puan. Her satır TEK
## satır yüksekliğinde — 8 oyuncuda da sol panele sığsın.
static func fill_score_panel(box: VBoxContainer, peer_ids: Array, my_id: int) -> void:
	_clear(box)
	box.add_child(section_title("Puan tablosu"))
	var ids: Array = peer_ids.duplicate()
	ids.sort_custom(func(a, b):
		var sa := GovernmentManager.score_of(a)
		var sb := GovernmentManager.score_of(b)
		if sa != sb:
			return sa > sb
		return int(CardManager.last_seats.get(a, 0)) > int(CardManager.last_seats.get(b, 0))
	)
	for peer_id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_badge(peer_id))

		var party_label := _label(party_name_of(peer_id), 13,
			UiTheme.GOLD if peer_id == my_id else UiTheme.TEXT)
		row.add_child(party_label)

		var leader_label := _label(leader_name_of(peer_id), 11, DIM_COLOR)
		leader_label.clip_text = true
		leader_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(leader_label)

		# Ulusal kamuoyu (seçime taşınan artı/eksi).
		var opinion := CardManager.national_of(peer_id)
		var opinion_label := _label("%+.1f" % opinion, 11, ProvincePanel._opinion_color(opinion))
		opinion_label.tooltip_text = "Ulusal kamuoyu"
		opinion_label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(opinion_label)

		var score_label := _label(str(GovernmentManager.score_of(peer_id)), 16)
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(score_label)
		box.add_child(row)

## Yasa oylaması: 1. satır yasa ve oy durumu, 2. satır bu oyuncu için oyların
## genel etkisi (il il değişir; illerin görüşü gizli olduğu için sayı verilmez).
static func _law_status_text(my_id: int, time_text: String) -> String:
	var law_type := GovernmentManager.proposal_law
	var totals := GovernmentManager.vote_seat_totals()
	var first := "YASA: %s (%s) — %s getirdi · EVET %d / ÇEK. %d / HAYIR %d · %s" % [
		CardPresets.card_title(law_type), CardPresets.law_direction_text(law_type),
		party_name_of(GovernmentManager.proposal_peer_id), totals.x, GovernmentManager.abstain_seats(), totals.y, time_text,
	]
	if GovernmentManager.has_voted(my_id):
		return first + "\nOyun: %s · diğer partilerin oyu bekleniyor" % GovernmentManager.vote_text(GovernmentManager.my_vote())
	if not GovernmentManager.voter_ids().has(my_id):
		return first
	return first + "\n" + String(law_vote_hint(my_id)["short"])

## Bu oyuncunun oylamadaki yeri için EVET / HAYIR ipuçları.
static func law_vote_hint(my_id: int) -> Dictionary:
	var proposer := GovernmentManager.proposal_peer_id
	var no_text := "HAYIR: yasaya yakın illerde güç kaybı, zıt illerde kazanç"
	if my_id == proposer:
		return {"yes": "EVET: kabul edilirse yasanın etkisi 2 katına çıkar", "no": no_text,
			"short": "Senin yasan: kabul edilirse il etkileri 2 kat"}
	var me_gov := GovernmentManager.proposal_gov_ids.has(my_id)
	var proposer_gov := GovernmentManager.proposal_gov_ids.has(proposer)
	if me_gov and not proposer_gov:
		return {"yes": "EVET: muhalefete gündem kaptırırsın — her ilde eksi, yasaya yakın illerde nötr/artı",
			"no": no_text,
			"short": "İktidardasın: muhalefetin yasasına EVET her ilde eksi (yakın illerde az) · kabul edilirse getiren güçlenir"}
	return {"yes": "EVET: yasaya yakın illerde artı, zıt illerde eksi", "no": no_text,
		"short": "Etkisi il il değişir: yasaya yakın illerde EVET, zıt illerde HAYIR kazandırır"}

## Hükümet teklifi: 1/2 koalisyon görüşmesi ya da 2/2 meclis oylaması.
static func _government_status_text(my_id: int, time_text: String) -> String:
	var eligible: Array = GovernmentManager.eligible_voter_ids()
	var voted := 0
	for peer_id in eligible:
		if GovernmentManager.has_voted(peer_id):
			voted += 1
	var proposer := party_name_of(GovernmentManager.proposal_peer_id)
	if GovernmentManager.is_coalition_stage():
		var text := "1/2 KOALİSYON GÖRÜŞMESİ — %s teklifi · ortak onayı %d/%d · %s" % [
			proposer, voted, eligible.size(), time_text]
		if eligible.has(my_id) and not GovernmentManager.has_voted(my_id):
			text += "\nORTAK önerildin: EVET kabul, HAYIR ret (çekimser yok)"
		elif my_id == GovernmentManager.proposal_peer_id:
			text += "\nOrtaklarının cevabı bekleniyor"
		return text
	var totals := GovernmentManager.vote_seat_totals()
	var text2 := "2/2 MECLİS OYLAMASI — %s hükümeti · EVET %d / ÇEK. %d / HAYIR %d · %d/%d oy · %s" % [
		proposer, totals.x, GovernmentManager.abstain_seats(), totals.y, voted, eligible.size(), time_text]
	if GovernmentManager.has_voted(my_id):
		text2 += "\nOyun: %s" % GovernmentManager.vote_text(GovernmentManager.my_vote())
	return text2

## Meclis butonlarının altındaki durum metni (kalan süre dahil).
static func proposal_status_text(my_id: int) -> String:
	var time_text := GameRules.format_seconds(GovernmentManager.phase_seconds_left())
	match GovernmentManager.phase:
		GovernmentManager.Phase.FORMING:
			var holder: int = GovernmentManager.mandate_peer_id()
			if holder == -1:
				return ""
			return "%s hükümet kuruyor… (%d. teklif hakkı, %s)" % [
				party_name_of(holder), GovernmentManager.current_attempt_number(), time_text,
			]
		GovernmentManager.Phase.VOTING:
			if GovernmentManager.is_resolving():
				var totals := GovernmentManager.vote_seat_totals()
				return "Oylama tamamlandı — EVET %d / ÇEKİMSER %d / HAYIR %d · sonuç açıklanıyor…" % [
					totals.x, GovernmentManager.abstain_seats(), totals.y]
			if GovernmentManager.proposal_kind == GovernmentManager.KIND_LAW:
				return _law_status_text(my_id, time_text)
			if GovernmentManager.proposal_kind == GovernmentManager.KIND_GOVERNMENT:
				return _government_status_text(my_id, time_text)
			var mine := ""
			if GovernmentManager.has_voted(my_id):
				mine = "  (oyun: %s)" % GovernmentManager.vote_text(GovernmentManager.my_vote())
			return "GENSORU oylanıyor — %d/%d oy, %s kaldı%s" % [
				GovernmentManager.votes.size(), GovernmentManager.voter_ids().size(), time_text, mine,
			]
		_:
			if GovernmentManager.last_resolution_reason != "":
				return GovernmentManager.last_resolution_reason
			return ""
