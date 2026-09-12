class_name GovernmentHud
extends RefCounted
## Oyun ekranının sol panelleri (hükümet, puan tablosu) ve meclis durum
## metni. game_screen.gd'den ayrıldı; hepsi mevcut autoload durumundan
## okuyarak çizer, kendi durumu yoktur.

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
	return label

## Kurulu hükümetin partileri ve ANA İKTİDAR PARTİSİ (başbakanlığı tutan).
static func fill_government_panel(box: VBoxContainer) -> void:
	_clear(box)
	box.add_child(_label("HÜKÜMET", 12, Color(1, 1, 1, 0.65)))

	if not GovernmentManager.has_government():
		box.add_child(_label("Hükümet yok", 13))
		return

	for peer_id in GovernmentManager.government_party_ids():
		var is_main: bool = peer_id == GovernmentManager.main_gov_peer_id
		var color: Color = PartyManager.parties.get(peer_id, {}).get("bg_color", Color.WHITE)
		box.add_child(_label("%s%s  (+%d)" % [
			"★ " if is_main else "· ",
			party_name_of(peer_id),
			GovernmentManager.round_points_of(peer_id),
		], 13, color.lightened(0.35)))

	var seats := GovernmentManager.government_seats()
	var total := GovernmentManager.total_seats()
	var majority := GovernmentManager.has_majority()
	box.add_child(_label("%d/%d sandalye — %s" % [seats, total, "çoğunluk var" if majority else "AZINLIK"],
		12, Color(1, 1, 1, 0.7) if majority else Color(1, 0.6, 0.5, 0.95)))

## Puan tablosu — oyuncular sürekli görebilsin diye kalıcı olarak ekranda.
static func fill_score_panel(box: VBoxContainer, peer_ids: Array, my_id: int) -> void:
	_clear(box)
	box.add_child(_label("PUAN TABLOSU", 12, Color(1, 1, 1, 0.65)))
	var ids: Array = peer_ids.duplicate()
	ids.sort_custom(func(a, b):
		var sa := GovernmentManager.score_of(a)
		var sb := GovernmentManager.score_of(b)
		if sa != sb:
			return sa > sb
		return int(CardManager.last_seats.get(a, 0)) > int(CardManager.last_seats.get(b, 0))
	)
	for peer_id in ids:
		box.add_child(_label("%d  %s (%s)" % [
			GovernmentManager.score_of(peer_id), party_name_of(peer_id), leader_name_of(peer_id),
		], 13, Color(1.0, 0.85, 0.35) if peer_id == my_id else Color.WHITE))

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
			var kind_text := "GENSORU" if GovernmentManager.proposal_kind == GovernmentManager.KIND_CENSURE else "HÜKÜMET TEKLİFİ"
			var mine := ""
			if GovernmentManager.has_voted(my_id):
				mine = "  (oyun: %s)" % ("EVET" if GovernmentManager.my_vote() else "HAYIR")
			elif GovernmentManager.proposal_kind == GovernmentManager.KIND_GOVERNMENT \
					and GovernmentManager.proposal_partner_ids().has(my_id):
				mine = "  — ORTAK olarak önerildin; HAYIR dersen teklif düşer"
			return "%s oylanıyor — %d/%d oy, %s kaldı%s" % [
				kind_text, GovernmentManager.votes.size(), GovernmentManager.voter_ids().size(), time_text, mine,
			]
		_:
			if GovernmentManager.last_resolution_reason != "":
				return GovernmentManager.last_resolution_reason
			return ""
