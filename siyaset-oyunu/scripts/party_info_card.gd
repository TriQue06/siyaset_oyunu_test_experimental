class_name PartyInfoCard
extends RefCounted
## Sağdaki oyuncu kartının üstüne gelince çıkan parti profili: parti ve oyuncu
## adı, meclis / oy / puan / kamuoyu bilgisi, hükümetteki yeri ve 8 seçmen
## grubundaki ULUSAL desteği (grup renginde çubuklar, son seçimden beri değişim,
## varsa geçici toplantı desteği).

const WIDTH := 320.0
const DIM := UiTheme.TEXT_MUTED
## Son build()'in genişliği (notların satır kırma genişliği için).
static var _width := WIDTH

## on_action(kind: String, peer_id: int): parti işlemi düğmeleri (fesih,
## kongre, davet...) basılınca çağrılır; verilmezse kart sadece bilgi gösterir.
static func build(peer_id: int, my_id: int, on_action: Callable = Callable(), width: float = WIDTH,
		on_close: Callable = Callable()) -> PanelContainer:
	_width = width
	var party: Dictionary = PartyManager.data_of(peer_id)
	var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
	var parts := PopupKit.frame(width, color)
	var card: PanelContainer = parts[0]
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: VBoxContainer = parts[1]

	# BAŞLIK: siyasetçinin adı (büyük) ve partisi (alt satır) — ikisi de vurgulu.
	var independent := PartyManager.is_independent(peer_id)
	var title := PoliticianPresets.display_name(peer_id)
	if peer_id == my_id:
		title += " (sen)"
	var sub := "Bağımsız siyasetçi" if independent else String(party.get("name", "?"))
	if MultiplayerManager.is_bot(peer_id):
		sub += " · bot"
	box.add_child(PopupKit.header(title, sub, PartyBadge.build(party, Vector2(40, 40), 64), on_close))
	# GENEL BAŞKANIN PROFİLİ: eski mesleği (ve memleketi).
	var leader_id := CardManager.party_of(peer_id) if not independent else peer_id
	var job := PoliticianPresets.title(PoliticianPresets.background_of(leader_id))
	if job != "":
		var hometown := String(PoliticianPresets.of(leader_id).get("hometown", ""))
		var who := "Bağımsız siyasetçi" if independent else "Genel başkan %s" % PoliticianPresets.display_name(leader_id)
		var line := "%s · eski meslek: %s" % [who, job]
		if hometown != "":
			line += " · memleket: %s" % ElectionNightSim.province_name(hometown)
		box.add_child(PopupKit.note(line, color.lightened(0.45), _text_width()))
	# İki kişilik parti: kadro.
	var members: Array = PartyManager.members_of(CardManager.party_of(peer_id))
	if members.size() >= 2:
		box.add_child(PopupKit.note("Genel başkan: %s  ·  Yardımcı: %s" % [PoliticianPresets.display_name(int(members[0])),
			PoliticianPresets.display_name(int(members[1]))], color.lightened(0.45), _text_width()))

	# Sayılar: dört eşit kutu (sol panelde 2x2).
	var stats := GridContainer.new()
	stats.columns = 2 if PopupKit.embedded else 4
	stats.add_theme_constant_override("h_separation", 4)
	stats.add_theme_constant_override("v_separation", 4)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	var pid := CardManager.party_of(peer_id)
	var has_seats: bool = CardManager.last_seats.has(pid)
	stats.add_child(_stat(str(int(CardManager.last_seats.get(pid, 0))) if has_seats else "—", "vekil", UiTheme.TEXT))
	stats.add_child(_stat("%%%.1f" % float(CardManager.last_vote_shares.get(pid, 0.0)) if has_seats else "—", "oy", UiTheme.TEXT))
	stats.add_child(_stat(str(GovernmentManager.score_of(peer_id)), "puan", UiTheme.GOLD))
	var opinion := CardManager.national_of(peer_id)
	stats.add_child(_stat("%+.1f" % opinion, "kamuoyu", ProvincePanel._opinion_color(opinion)))

	var role := role_text(peer_id)
	var role_row := HBoxContainer.new()
	role_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_row.add_child(PopupKit.chip(role, UiTheme.GREEN if role.begins_with("Hükümet:") else UiTheme.TEXT_MUTED))
	box.add_child(role_row)

	_add_group_section(box, peer_id)
	if on_action.is_valid():
		var actions := _actions(peer_id, my_id, on_action)
		if actions != null:
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			box.add_child(actions)
	return card

## PARTİ İŞLEMLERİ (bkz. CardManager "Parti siyaseti"). Sadece kendi kartında:
## genel başkan: kongreye git, partiyi feshet; üye: kongre iste, istifa et;
## bağımsız: yeni parti kur. Sırası gelmeyen ya da manası yetmeyen için düğme
## sönük durur; neden yapılamadığı not olarak yazar.
static func _actions(peer_id: int, my_id: int, on_action: Callable) -> Control:
	var list: Array = []  # [metin, tür, basılabilir mi, onay ister mi]
	var notes: Array = []
	if peer_id != my_id and CardManager.party_of(peer_id) != CardManager.party_of(my_id):
		return null
	var pid := CardManager.party_of(my_id)
	if PartyManager.is_independent(my_id):
		list.append(["Yeni Parti Kur · %d mana" % CardManager.FOUND_PARTY_COST, "found", CardManager.can_found_party(my_id), false])
		notes.append("Bağımsızken her yerde teşkilatsız miting yapabilirsin; mitingler güvenilirliğini artırır. Parti kurduğunda güvenilirliğin kadar ilde teşkilatla başlarsın (şu an %d il)." %
			mini(CardManager.FOUND_ORG_MAX, int(CardManager.credibility_of(my_id) / CardManager.FOUND_ORG_PER_CREDIBILITY)))
		var former: Dictionary = CardManager.former_parties.get(my_id, {})
		var moving := CardManager.former_org_count(my_id)
		if moving > 0:
			notes.append("Eski partin %s'nin %d teşkilatından şu an %d tanesi (%%%d) yeni partine geçer. Pay ayrılıştan beri geçen süre (her tur azalır), puanın, ulusal desteğin ve güvenilirliğinle belirlenir (%%10-90)." % [
				String(former.get("name", "")), CardManager.former_org_source(my_id).size(), moving,
				int(round(CardManager.former_org_share(my_id) * 100.0))])
	elif CardManager.is_party_member(my_id):
		list.append(["Kongre İste · %d mana" % CardManager.CONGRESS_REQUEST_COST, "congress", CardManager.can_request_congress(my_id), false])
		list.append(["Partiden İstifa Et", "resign", CardManager.can_resign(my_id), true])
		notes.append("Partinin üyesisin: sadece miting yapabilirsin (partine ve güvenilirliğine yazar). Parti hükümetteyse başkanla aynı puanı alırsın.")
		var reason := CardManager.congress_block_reason(my_id)
		if reason != "":
			notes.append("Kongre: " + reason)
	else:
		list.append(["Kongreye Git · %d mana" % CardManager.CONGRESS_COST, "congress", CardManager.can_hold_congress(my_id), false])
		list.append(["Partiyi Feshet", "dissolve", CardManager.can_dissolve(my_id), true])
		var left := CardManager.CONGRESS_MAX_ELECTIONS - CardManager.elections_since_congress(pid)
		notes.append("Zorunlu kongreye %s. Güç: %d/100 (oy değişimi, hükümet, karışıklık, güvenilirlik); güç ne kadar yüksekse rakip o kadar az." % [
			"bu seçimden sonra sıran gelince gidilecek" if left <= 0 else "%d seçim kaldı" % left, int(round(CardManager.congress_strength(pid)))])
	if list.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(PopupKit.section("Parti"))
	for note in notes:
		box.add_child(PopupKit.note(String(note), UiTheme.TEXT_MUTED, _text_width()))
	var any_disabled := false
	for entry in list:
		var button := Button.new()
		button.text = String(entry[0])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 32)
		button.add_theme_font_size_override("font_size", 13)
		button.disabled = not bool(entry[2])
		any_disabled = any_disabled or button.disabled
		var kind := String(entry[1])
		if kind == "dissolve" or kind == "leave":
			UiSkin.skin_color_button(button, UiTheme.RED_DARK)
		else:
			UiSkin.skin_button(button)
		if bool(entry[3]):
			# Geri dönüşü olmayan işlem: iki kez basınca olur.
			button.pressed.connect(func():
				if not button.has_meta("armed"):
					button.set_meta("armed", true)
					button.text = "Emin misin? Tekrar bas"
					return
				on_action.call(kind, peer_id))
		else:
			button.pressed.connect(func(): on_action.call(kind, peer_id))
		box.add_child(button)
	if any_disabled:
		box.add_child(PopupKit.note("Sıran gelince ve manan yetince yapabilirsin.", DIM))
	return box

## "Hükümet: Başbakanlık, 3 bakanlık" / "Muhalefet" / "Hükümet yok".
static func role_text(peer_id: int) -> String:
	peer_id = CardManager.party_of(peer_id)  # yardımcı da partisinin görevlerini görür
	if not GovernmentManager.has_government():
		return "Hükümet yok"
	var posts: Array = []
	var ministries := 0
	for post_id in GovernmentManager.government.keys():
		if int(GovernmentManager.government[post_id]) != peer_id:
			continue
		if post_id == GovernmentPresets.POST_PM:
			posts.push_front("Başbakanlık")
		elif post_id == GovernmentPresets.POST_DEPUTY_PM:
			posts.append("Başbakan Yrd.")
		else:
			ministries += 1
	if ministries > 0:
		posts.append("%d bakanlık" % ministries)
	if posts.is_empty():
		return "Muhalefet"
	return "Hükümet: " + ", ".join(PackedStringArray(posts))

## SEÇMEN GRUPLARI: partinin 8 gruptaki ulusal desteği + en güçlü / en zayıf özeti.
static func _add_group_section(box: VBoxContainer, peer_id: int) -> void:
	var pid := CardManager.party_of(peer_id)
	var groups := PartyManager.groups_of(pid)
	var bonuses := CardManager.meeting_bonuses(pid)
	var before: Dictionary = CardManager.election_groups.get(pid, {})
	box.add_child(PopupKit.section("Seçmen grupları", "ulusal destek"))
	var ranked := VoterGroups.ranked_groups(groups)
	box.add_child(PopupKit.note("En güçlü: %s · en zayıf: %s" % [VoterGroups.title(ranked[0]), VoterGroups.title(ranked[-1])],
		UiTheme.TEXT_MUTED, _text_width()))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(list)
	for group in VoterGroups.GROUP_IDS:
		var value := float(groups.get(group, VoterGroups.AFFINITY_NEUTRAL))
		var delta := value - float(before[group]) if before.has(group) else 0.0
		list.add_child(VoterGroupUI.affinity_row(group, value, float(bonuses.get(group, 0.0)), delta))
	box.add_child(PopupKit.note("Destek, grubun ülkedeki nüfus payı değildir. ▲▼: son seçimden beri.", DIM, _text_width()))

## Sarmalı notların genişliği (çerçeveli kartta iç boşluk düşülür).
static func _text_width() -> float:
	return _width if PopupKit.embedded else _width - 2.0 * PopupKit.PAD

static func _stat(value: String, caption: String, color: Color) -> Control:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.SLOT
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var value_label := UiTheme.mono_label(value, 16, color, true)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value_label)
	var caption_label := _label(caption, PopupKit.FS_SECTION, DIM)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption_label)
	return tile

static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
