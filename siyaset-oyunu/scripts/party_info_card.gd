class_name PartyInfoCard
extends RefCounted
## Sağdaki oyuncu kartının üstüne gelince çıkan parti profili: parti ve oyuncu
## adı, meclis / oy / puan / kamuoyu bilgisi, hükümetteki yeri ve ideoloji
## tablosu (her eksende -3..+3 arası 7 kutu, partinin konumu kendi renginde).

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

	box.add_child(PopupKit.section("İdeoloji"))
	var ideology: Dictionary = party.get("ideology", IdeologyAxes.default_values())
	for axis in IdeologyAxes.AXES:
		box.add_child(_axis_row(axis, float(ideology.get(axis, 0)), color))
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

## value: 0.5 adımlı; ölçekte her yarım adım bir hücre (−3 … +3 = 13 hücre).
static func _axis_row(axis: String, value: float, color: Color) -> Control:
	var titles: Dictionary = CardPresets.AXIS_TITLES.get(axis, {"title": axis, "neg": "-", "pos": "+"})
	var info: Array = [titles["title"], titles["neg"], titles["pos"]]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var title := _label(String(info[0]), PopupKit.FS_TEXT, UiTheme.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label(IdeologyAxes.position_text(axis, value), PopupKit.FS_TEXT, color.lightened(0.35)))

	var scale := HBoxContainer.new()
	scale.add_theme_constant_override("separation", 3 if PopupKit.embedded else 6)
	scale.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(scale)
	var left := _label(String(info[1]), PopupKit.FS_SECTION, DIM)
	var side_width := 68.0 if PopupKit.embedded else 64.0
	var cell_width := 5.0 if PopupKit.embedded else 10.0
	left.custom_minimum_size = Vector2(side_width, 0)

	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale.add_child(left)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 1 if PopupKit.embedded else 2)
	cells.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale.add_child(cells)
	var steps := int(roundf((IdeologyAxes.AXIS_MAX - IdeologyAxes.AXIS_MIN) / IdeologyAxes.STEP))
	for i in steps + 1:
		var v: float = IdeologyAxes.AXIS_MIN + i * IdeologyAxes.STEP
		var whole := is_equal_approx(v, roundf(v))
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(cell_width, 12)
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cell_color := color if is_equal_approx(v, value) else (
			UiTheme.PANEL_LIGHT if is_zero_approx(v) else (UiTheme.PANEL if whole else UiTheme.SLOT))
		var cell_style := StyleBoxFlat.new()
		cell_style.bg_color = cell_color
		if is_equal_approx(v, value):
			cell_style.border_color = Color.WHITE
			cell_style.set_border_width_all(1)
		cell.add_theme_stylebox_override("panel", cell_style)
		cells.add_child(cell)
	var right := _label(String(info[2]), PopupKit.FS_SECTION, DIM)
	right.custom_minimum_size = Vector2(side_width, 0)

	scale.add_child(right)
	return box

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
