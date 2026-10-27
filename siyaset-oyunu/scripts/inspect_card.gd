class_name InspectCard
extends RefCounted
## SAĞ PANEL İNCELEME KARTI (0.0.272, konsept "Oyun kartı"; bkz.
## konseptler/inceleme_paneli_oyun_karti.html). İl ve parti aynı tasarımda:
##   - renkli ŞERİT: büyük pul (il: vekil sayısı, parti: logo), ad ve alt satır;
##     altında sağa yaslı çipler,
##   - SANDIK: il -> partilerin son seçimi (çizgili çubuk, soluk vekil pulları)
##     ve ildeki anket (dolu çubuk, vekil pulları, değişim rozeti); parti ->
##     ülke geneli son seçim ve oyuncunun SON ANKETİ (anket kartı; seçimde sıfırlanır),
##   - SEÇMEN GRUPLARI: sekiz halkalı jeton (il: nüfus payı; parti: oy payı,
##     halka sadık seçmen oranı),
##   - il: BU İLDE SEN (kadran) ve SON OLAYLAR; parti: kendi kartında parti işlemleri.
## Ölçüler HTML pikseli (1920 genişlik); UiTheme.d ile tasarım birimine çevrilir.

const CARD_BG := Color("FFFAF0")
const LINE := Color("E3D5B0")
const MUTED2 := Color("9A9082")
const MAX_EVENTS := 5

static func d(px: float) -> float:
	return UiTheme.d(px)

# --- İL ----------------------------------------------------------------------------

static func fill_province(box: VBoxContainer, province_id: String, on_close: Callable) -> void:
	var me := multiplayer_id()
	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	var leader := -1
	var best := -1.0
	for pid in results.keys():
		if float(results[pid].get("percent", 0.0)) > best:
			best = float(results[pid].get("percent", 0.0))
			leader = int(pid)
	var band_color: Color = PartyManager.data_of(leader).get("bg_color", UiTheme.TEAL) if leader != -1 else UiTheme.TEAL
	var seats := CardManager.province_seat_count(province_id)
	box.add_child(_banner(band_color, NumberPawn.make(str(seats), UiTheme.TEAL, d(86)),
		ElectionNightSim.province_name(province_id), L.t("%d milletvekili") % seats, on_close))
	var chips: Array = []
	if PartyManager.parties.has(CardManager.party_of(me)):
		chips.append([L.t("Teşkilatın %d/%d") % [CardManager.organization_level(province_id, me), GameRules.ORG_MAX_LEVEL], UiTheme.TEAL])
	if leader != -1:
		chips.append([L.t("Lider %s") % GovernmentHud.party_name_of(leader), band_color])
	box.add_child(_chip_row(chips))

	box.add_child(_section(L.t("Sandık")))
	box.add_child(_province_ballot(province_id, me, results))

	box.add_child(_section(L.t("Seçmen grupları"), L.t("ilin nüfusu")))
	var profile := CardManager.province_profile(province_id)
	var shares := {}
	for group in VoterGroups.GROUP_IDS:
		shares[group] = VoterGroups.share(profile, group) * 100.0
	box.add_child(_tokens(shares, shares))

	if PartyManager.parties.has(CardManager.party_of(me)):
		box.add_child(_section(L.t("Bu ilde sen")))
		box.add_child(_standing(province_id, me))
	box.add_child(_section(L.t("Son olaylar")))
	box.add_child(_events(province_id))

## Partiler: son seçim (çizgili) ve ildeki anket (dolu) aynı satırda.
static func _province_ballot(province_id: String, me: int, results: Dictionary) -> Control:
	var poll := CardManager.province_card_poll(me, province_id)
	var ids: Array = []
	for pid in CardManager.party_ids():
		if poll.has(pid) or results.has(pid):
			ids.append(int(pid))
	ids.sort_custom(func(a, b): return float(poll.get(a, {}).get("percent", 0.0)) > float(poll.get(b, {}).get("percent", 0.0)))
	var top := 10.0
	for pid in ids:
		top = maxf(top, maxf(float(poll.get(pid, {}).get("percent", 0.0)), float(results.get(pid, {}).get("percent", 0.0))))
	var card := _card()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(list)
	var head := _ballot_row()
	head.add_child(_fixed(Control.new(), d(30)))
	var hp := _lbl(L.t("PARTİ"), 11, UiTheme.TEXT_MUTED, false, true)
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hp)
	head.add_child(_fixed(_right(_lbl(L.t("SON SEÇİM"), 11, UiTheme.TEXT_MUTED, false, true)), d(70)))
	head.add_child(_fixed(_right(_lbl(L.t("ANKET"), 11, UiTheme.TEXT_MUTED, false, true)), d(78)))
	list.add_child(head)
	list.add_child(_rule(LINE, 2.0))
	for i in ids.size():
		var pid: int = ids[i]
		var party: Dictionary = PartyManager.data_of(pid)
		var color: Color = party.get("bg_color", Color.GRAY)
		var row := _ballot_row()
		row.add_theme_constant_override("separation", int(d(8)))
		var pawn := PartyBadge.build(party, Vector2(d(30), d(30)), 64, pid == CardManager.party_of(me))
		pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pawn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pawn)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", int(d(5)))
		mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name := _lbl(GovernmentHud.party_name_of(pid), 15, UiTheme.TEXT, true)
		name.clip_text = true
		mid.add_child(name)
		var last_pct := float(results.get(pid, {}).get("percent", -1.0))
		var now_pct := float(poll.get(pid, {}).get("percent", -1.0))
		mid.add_child(DualBar.make(color, maxf(0.0, last_pct) / top, maxf(0.0, now_pct) / top))
		row.add_child(mid)
		var last_col := VBoxContainer.new()
		last_col.add_theme_constant_override("separation", int(d(3)))
		last_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		last_col.add_child(_right(_lbl(L.pct(last_pct, 0) if last_pct >= 0.0 else "—", 13, UiTheme.TEXT_MUTED, false, true)))
		last_col.add_child(SeatPips.make(int(results.get(pid, {}).get("seats", 0)), color, true))
		row.add_child(_fixed(last_col, d(70)))
		var now_col := VBoxContainer.new()
		now_col.add_theme_constant_override("separation", int(d(3)))
		now_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var now_row := HBoxContainer.new()
		now_row.alignment = BoxContainer.ALIGNMENT_END
		now_row.add_theme_constant_override("separation", int(d(4)))
		now_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var now_label := _lbl(L.pct(now_pct, 0) if now_pct >= 0.0 else "—", 17, color, true)
		_shadow(now_label, color.darkened(0.6), 2)
		now_row.add_child(now_label)
		if now_pct >= 0.0 and last_pct >= 0.0:
			now_row.add_child(_delta(roundf(now_pct) - roundf(last_pct), 0))
		now_col.add_child(now_row)
		now_col.add_child(SeatPips.make(int(poll.get(pid, {}).get("seats", 0)), color, false))
		row.add_child(_fixed(now_col, d(78)))
		list.add_child(_pad(row, d(8)))
		if i < ids.size() - 1:
			list.add_child(_dashed())
	return card

static func _ballot_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(d(8)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

## BU İLDE SEN: kadran (seçmenin sana yakınlığı) ve yerel güç.
static func _standing(province_id: String, me: int) -> Control:
	var card := _card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(d(12)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var closeness := PublicOpinion.appeal_closeness(CardManager.appeal_of(province_id, me))
	var dial := Dial.new()
	dial.value = closeness
	dial.custom_minimum_size = Vector2(d(84), d(46))
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dial)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", int(d(4)))
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var power := CardManager.activity_of(province_id, me)
	var word := EffectWords.amount(power, "local")
	var color := UiTheme.GREEN_DARK if closeness >= PublicOpinion.CLOSENESS_NEAR else (Color("C97A12") if closeness >= 0.3 else UiTheme.CRISIS)
	texts.add_child(_lbl(word.substr(0, 1).to_upper() + word.substr(1), 26, color, true))
	var near := L.t("çok yakın") if closeness >= 0.75 else (L.t("yakın") if closeness >= PublicOpinion.CLOSENESS_NEAR \
		else (L.t("uzak") if closeness >= 0.3 else L.t("çok uzak")))
	var sub := L.t("seçmen sana %s") % near
	if CardManager.organization_level(province_id, me) > 0:
		sub += L.t(" · miting riski %s") % EffectWords.risk(CardManager.miting_risk(me, province_id))
	var note := _lbl(sub, 13, UiTheme.TEXT_MUTED, false)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(note)
	return card

static func _events(province_id: String) -> Control:
	var card := _card()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(list)
	var events: Array = CardManager.province_events.get(province_id, [])
	if events.is_empty():
		list.add_child(_lbl(L.t("Bu ilde henüz bir olay yok."), 13, UiTheme.TEXT_MUTED, false))
		return card
	var shown := 0
	for i in range(events.size() - 1, -1, -1):
		if shown >= MAX_EVENTS:
			break
		if shown > 0:
			list.add_child(_dashed())
		shown += 1
		var event: Dictionary = events[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(d(10)))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pid := int(event.get("peer_id", event.get("peer", -1)))
		var dot := NumberPawn.make("", PartyManager.data_of(pid).get("bg_color", UiTheme.GOLD) if pid != -1 else UiTheme.GOLD, d(14))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", int(d(2)))
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var text := _lbl(String(event.get("text", "")), 13, UiTheme.TEXT, false, true)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(text)
		texts.add_child(_lbl(GameRules.period_label(int(event.get("round", 1))), 11, UiTheme.TEXT_MUTED, false, true))
		row.add_child(_pad(texts, d(8)))
		list.add_child(row)
	return card

# --- PARTİ -------------------------------------------------------------------------

static func fill_party(box: VBoxContainer, peer_id: int, on_close: Callable) -> void:
	var me := multiplayer_id()
	var pid := CardManager.party_of(peer_id)
	var party: Dictionary = PartyManager.data_of(peer_id)
	var color: Color = party.get("bg_color", Color.GRAY)
	var independent := PartyManager.is_independent(peer_id)
	var leader_id := pid if not independent else peer_id
	var title := PoliticianPresets.display_name(peer_id) if independent else String(party.get("name", "?"))
	var bits: PackedStringArray = [PoliticianPresets.display_name(leader_id) + (L.t(" (sen)") if leader_id == me else "")]
	var job := PoliticianPresets.title(PoliticianPresets.background_of(leader_id))
	if job != "":
		bits.append(job)
	var pawn := PartyBadge.build(party, Vector2(d(86), d(86)), 192, pid == CardManager.party_of(me))
	pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_banner(color, pawn, title, " · ".join(bits), on_close))
	var chips: Array = []
	var role := PartyInfoCard.role_text(peer_id)
	chips.append([role.trim_prefix(L.t("Hükümet: ")) if role.begins_with(L.t("Hükümet: ")) else role,
		UiTheme.GREEN_DARK if role.begins_with(L.t("Hükümet: ")) else UiTheme.TEXT_MUTED])
	var alliance_id := CardManager.alliance_of(peer_id)
	if alliance_id >= 0:
		var alliance: Dictionary = CardManager.alliances[alliance_id]
		chips.append([String(alliance.get("name", "")), alliance.get("color", UiTheme.BLUE)])
	chips.append([L.t("%d puan") % GovernmentManager.score_of(peer_id), UiTheme.GOLD_DIM])
	var hometown := String(PoliticianPresets.of(leader_id).get("hometown", ""))
	if hometown != "":
		chips.append([ElectionNightSim.province_name(hometown), UiTheme.TEAL])
	box.add_child(_chip_row(chips))

	box.add_child(_section(L.t("Sandık"), L.t("ülke geneli")))
	box.add_child(_party_ballot(pid, me, color))

	box.add_child(_section(L.t("Seçmen grupları"), L.t("halka: sadık seçmen")))
	var votes := CardManager.group_vote_estimates(pid)
	var levels := CardManager.group_level_shares(pid)
	var rings := {}
	for group in VoterGroups.GROUP_IDS:
		var parts: Array = levels.get(group, [])
		var total := 0.0
		for v in parts:
			total += float(v)
		rings[group] = float(parts[2]) / total * 100.0 if parts.size() == 3 and total > 0.0 else 0.0
	box.add_child(_tokens(votes, rings))

## SON SEÇİM ve SON ANKET (oyuncunun anket kartı; yoksa boş kutu).
static func _party_ballot(pid: int, me: int, color: Color) -> Control:
	var duo := HBoxContainer.new()
	duo.add_theme_constant_override("separation", int(d(8)))
	duo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var has_last: bool = CardManager.last_vote_shares.has(pid)
	var last_pct := float(CardManager.last_vote_shares.get(pid, 0.0))
	var last_sub := L.t("henüz seçim yok")
	if has_last:
		last_sub = L.t("%d vekil · %d. parti") % [int(CardManager.last_seats.get(pid, 0)), _rank(CardManager.last_vote_shares, pid)]
	duo.add_child(_ballot_box(L.t("SON SEÇİM"), L.pct(last_pct, 1) if has_last else "—", last_sub, UiTheme.TEXT if has_last else MUTED2, Color(0, 0, 0, 0)))
	var poll := CardManager.my_poll(me)
	var parties: Dictionary = poll.get("parties", {})
	if parties.has(pid):
		var now := float(parties[pid].get("percent", 0.0))
		var flat := {}
		for key in parties.keys():
			flat[key] = float(parties[key].get("percent", 0.0))
		var box := _ballot_box(L.t("SON ANKET"), L.pct(now, 1), L.t("~%d vekil · %d. parti") % [int(parties[pid].get("seats", 0)), _rank(flat, pid)],
			color, color)
		if has_last:
			var delta := _delta(snappedf(now - last_pct, 0.1), 1)
			delta.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			(box.get_child(0) as VBoxContainer).add_child(delta)
		duo.add_child(box)
	else:
		duo.add_child(_ballot_box(L.t("SON ANKET"), "—", L.t("bu dönem anket yok"), MUTED2, Color(0, 0, 0, 0)))
	return duo

static func _ballot_box(caption: String, value: String, sub: String, value_color: Color, hot: Color) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiSkin.card(CARD_BG if hot.a == 0.0 else CARD_BG.lerp(hot, 0.1), LINE if hot.a == 0.0 else CARD_BG.lerp(hot, 0.45),
		UiTheme.CARD_LIP if hot.a == 0.0 else UiTheme.CARD_LIP.lerp(hot, 0.45), 3.0)
	style.set_content_margin_all(d(10))
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(d(5)))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	col.add_child(_center(_lbl(caption, 11, UiTheme.TEXT_MUTED, false, true)))
	col.add_child(_center(_lbl(value, 30, value_color, true)))
	var s := _center(_lbl(sub, 13, UiTheme.TEXT_MUTED, false, true))
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(s)
	return panel

static func _rank(shares: Dictionary, pid: int) -> int:
	var mine := float(shares.get(pid, 0.0))
	var rank := 1
	for key in shares.keys():
		if int(key) != pid and float(shares[key]) > mine:
			rank += 1
	return rank

# --- Ortak parçalar ----------------------------------------------------------------

static func multiplayer_id() -> int:
	return (Engine.get_main_loop() as SceneTree).root.multiplayer.get_unique_id()

## Renkli şerit: büyük pul solda (şeridin altından taşar), ad ve alt satır, X.
static func _banner(color: Color, pawn: Control, title: String, subtitle: String, on_close: Callable) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, d(118))
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var band := Panel.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := BoardBox.new()
	style.fill = color.lerp(Color.WHITE, 0.25)
	style.fill_bottom = color
	style.radius_tl = d(14)
	style.radius_tr = d(14)
	style.radius_bl = 0
	style.radius_br = 0
	style.shade_size = d(6)
	style.shade_color = Color(0, 0, 0, 0.3)
	style.highlight_size = d(2)
	style.highlight_color = Color(1, 1, 1, 0.3)
	band.add_theme_stylebox_override("panel", style)
	holder.add_child(band)
	# Pul: şeridin sol altında, krem halkayla şeritten ayrılır.
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = UiTheme.PANEL
	ring_style.set_corner_radius_all(int(d(60)))
	ring_style.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", ring_style)
	var side := pawn.custom_minimum_size.x
	ring.size = Vector2(side + d(10), side + d(10))
	ring.position = Vector2(d(18) - d(5), d(118) + d(30) - side - d(5))
	holder.add_child(ring)
	pawn.position = Vector2(d(18), d(118) + d(30) - side)
	pawn.size = Vector2(side, side)
	holder.add_child(pawn)
	var title_label := _lbl(title, 28, UiTheme.ON_COLOR, true)
	_shadow(title_label, Color(0, 0, 0, 0.22), 3)
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.position = Vector2(d(18) + side + d(16), d(118) - d(42) - d(28))
	title_label.size = Vector2(d(260), d(32))
	title_label.set_anchor(SIDE_RIGHT, 1.0)
	title_label.offset_right = -d(14)
	holder.add_child(title_label)
	var sub_label := _lbl(subtitle, 13, UiTheme.ON_COLOR, false, true)
	sub_label.clip_text = true
	sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label.position = Vector2(d(18) + side + d(16), d(118) - d(20) - d(15))
	sub_label.set_anchor(SIDE_RIGHT, 1.0)
	sub_label.offset_right = -d(14)
	holder.add_child(sub_label)
	if on_close.is_valid():
		var x := Button.new()
		x.text = "X"
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(d(40), d(36))
		x.add_theme_font_override("font", UiTheme.mono(true))
		x.add_theme_font_size_override("font_size", UiTheme.fs(16))
		UiSkin.skin_color_button(x, color.darkened(0.25))
		x.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		x.position = Vector2(-d(40) - d(10), d(10))
		x.offset_left = -d(40) - d(10)
		x.offset_right = -d(10)
		x.offset_top = d(10)
		x.offset_bottom = d(10) + d(36)
		x.pressed.connect(on_close)
		holder.add_child(x)
	return holder

## Şeridin altında sağa yaslı çipler (pulun taştığı yüksekliği de kaplar).
static func _chip_row(chips: Array) -> Control:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_END
	row.add_theme_constant_override("h_separation", int(d(6)))
	row.add_theme_constant_override("v_separation", int(d(6)))
	row.custom_minimum_size = Vector2(0, d(34))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", int(d(8)))
	margin.add_theme_constant_override("margin_left", int(d(110)))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	for chip in chips:
		row.add_child(_chip(String(chip[0]), chip[1]))
	return margin

static func _chip(text: String, color: Color) -> Label:
	var label := _lbl(text, 13, UiTheme.ON_COLOR, true)
	var style := BoardBox.new()
	style.fill = color
	style.set_radius(d(8))
	style.lips = [[d(2), color.darkened(0.4)]]
	style.content_margin_left = d(8)
	style.content_margin_right = d(8)
	style.content_margin_top = d(4)
	style.content_margin_bottom = d(4)
	label.add_theme_stylebox_override("normal", style)
	return label

static func _section(title: String, note: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(d(8)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", int(d(12)))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var dot := NumberPawn.make("", UiTheme.GOLD, d(12))
	dot.flat = true
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var head := _lbl(title, 17, UiTheme.TEAL, true)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(head)
	if note != "":
		var small := _lbl(note, 12, MUTED2, false, true)
		small.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(small)
	return margin

static func _card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiSkin.card(CARD_BG, LINE, UiTheme.CARD_LIP, 4.0)
	style.set_content_margin_all(d(12))
	panel.add_theme_stylebox_override("panel", style)
	return panel

## Sekiz grup jetonu: halka (ring %) ve altında yüzde (values) ile ad.
static func _tokens(values: Dictionary, rings: Dictionary) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", int(d(6)))
	grid.add_theme_constant_override("v_separation", int(d(8)))
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for group in VoterGroups.GROUP_IDS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", int(d(3)))
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ring := RingToken.new()
		ring.group = String(group)
		ring.value = float(rings.get(group, 0.0)) / 100.0
		ring.custom_minimum_size = Vector2(d(62), d(62))
		ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ring)
		col.add_child(_center(_lbl(L.pct(float(values.get(group, 0.0)), 0), 17, UiTheme.TEXT, true)))
		var name := _center(_lbl(VoterGroups.title(String(group)), 11, UiTheme.TEXT_MUTED, false, true))
		name.clip_text = true
		col.add_child(name)
		grid.add_child(col)
	return grid

static func _delta(value: float, decimals: int) -> Label:
	var text := ("+" if value > 0.0 else ("−" if value < 0.0 else "±")) + String.num(absf(value), decimals).replace(".", ",")
	var color := UiTheme.GREEN_DARK if value > 0.0 else (UiTheme.CRISIS if value < 0.0 else MUTED2)
	var label := _lbl(text, 11, UiTheme.ON_COLOR, true)
	var style := BoardBox.new()
	style.fill = color
	style.set_radius(d(6))
	style.lips = [[d(2), color.darkened(0.35)]]
	style.content_margin_left = d(5)
	style.content_margin_right = d(5)
	style.content_margin_top = d(2)
	style.content_margin_bottom = d(2)
	label.add_theme_stylebox_override("normal", style)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

static func _lbl(text: String, html_px: float, color: Color, display: bool, black: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true) if display else (UiTheme.body_black() if black else UiTheme.body()))
	label.add_theme_font_size_override("font_size", UiTheme.fs(html_px))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _shadow(label: Label, color: Color, px: float) -> void:
	label.add_theme_color_override("font_shadow_color", color)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(d(px)))))
	label.add_theme_constant_override("shadow_outline_size", 0)

static func _right(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

static func _center(label: Label) -> Label:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

static func _fixed(control: Control, width: float) -> Control:
	control.custom_minimum_size.x = width
	control.size_flags_horizontal = Control.SIZE_SHRINK_END
	return control

static func _pad(control: Control, vertical: float) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", int(vertical))
	margin.add_theme_constant_override("margin_bottom", int(vertical))
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(control)
	return margin

static func _rule(color: Color, px: float) -> Control:
	var rect := ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = Vector2(0, d(px))
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

static func _dashed() -> Control:
	var line := DashedLine.new()
	line.custom_minimum_size = Vector2(0, d(2))
	return line

# --- Çizilen küçük parçalar --------------------------------------------------------

## Yuvarlak 3B pul, ortasında yazı (il: vekil sayısı). flat: düz nokta.
class NumberPawn extends Control:
	var text := ""
	var color := UiTheme.TEAL
	var flat := false

	static func make(p_text: String, p_color: Color, side: float) -> NumberPawn:
		var pawn := NumberPawn.new()
		pawn.text = p_text
		pawn.color = p_color
		pawn.custom_minimum_size = Vector2(side, side)
		pawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return pawn

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		if flat:
			draw_circle(rect.get_center() + Vector2(0, side * 0.15), side * 0.5, color.darkened(0.35), true, -1.0, true)
			draw_circle(rect.get_center(), side * 0.5, color, true, -1.0, true)
			return
		draw_style_box(VoterGroupIcon.pawn_style(color, side), rect)
		if text == "":
			return
		var font := UiTheme.mono(true)
		var font_size := int(side * 0.42)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := rect.position + Vector2((side - w) * 0.5, (side + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5 - side * 0.04)
		draw_string(font, pos + Vector2(0, side * 0.03), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.25))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

## Son seçim (çizgili, soluk) ve anket (dolu) üst üste çubuk.
class DualBar extends Control:
	var color := Color.GRAY
	var last := 0.0
	var now := 0.0

	static func make(p_color: Color, p_last: float, p_now: float) -> DualBar:
		var bar := DualBar.new()
		bar.color = p_color
		bar.last = clampf(p_last, 0.0, 1.0)
		bar.now = clampf(p_now, 0.0, 1.0)
		bar.custom_minimum_size = Vector2(0, UiTheme.d(10))
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return bar

	func _draw() -> void:
		var r := size.y * 0.5
		_pill(Rect2(Vector2.ZERO, size), UiTheme.SLOT)
		if last > 0.0:
			var old := Rect2(Vector2.ZERO, Vector2(size.x * last, size.y))
			_pill(old, color.lerp(InspectCard.CARD_BG, 0.65))
			# Çizgiler: son seçim.
			var step := size.y * 0.8
			var x := 0.0
			while x < old.size.x:
				draw_line(Vector2(x, size.y), Vector2(minf(x + size.y, old.size.x), 0), color.lerp(InspectCard.CARD_BG, 0.85), size.y * 0.3, true)
				x += step
		if now > 0.0:
			_pill(Rect2(Vector2(0, size.y * 0.2), Vector2(maxf(size.y, size.x * now), size.y * 0.6)), color)

	func _pill(rect: Rect2, fill: Color) -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.set_corner_radius_all(int(ceil(rect.size.y * 0.5)))
		style.anti_aliasing = true
		draw_style_box(style, rect)

## Vekil pulları (krem, parti renginde kenar); ghost: son seçim (soluk).
class SeatPips extends Control:
	var count := 0
	var color := Color.GRAY
	var ghost := false

	static func make(p_count: int, p_color: Color, p_ghost: bool) -> SeatPips:
		var pips := SeatPips.new()
		pips.count = p_count
		pips.color = p_color
		pips.ghost = p_ghost
		pips.custom_minimum_size = Vector2(0, UiTheme.d(11) + 2.0)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return pips

	func _draw() -> void:
		var r := UiTheme.d(11) * 0.5
		var gap := UiTheme.d(2)
		var per_row := maxi(1, int((size.x + gap) / (r * 2.0 + gap)))
		var shown := mini(count, per_row)
		var alpha := 0.45 if ghost else 1.0
		for i in shown:
			var c := Vector2(size.x - r - i * (r * 2.0 + gap), r)
			draw_circle(c + Vector2(0, UiTheme.d(1.5)), r, Color(Color("8F6C40"), alpha), true, -1.0, true)
			draw_circle(c, r, Color(color, alpha), true, -1.0, true)
			draw_circle(c, r * 0.55, Color(InspectCard.CARD_BG, alpha), true, -1.0, true)

## Halkalı grup jetonu: halka değeri (0..1) grup renginde, ortada grup pulu.
class RingToken extends Control:
	var group := ""
	var value := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := VoterGroupIcon.make(group, UiTheme.d(46))
		icon.position = (custom_minimum_size - Vector2(UiTheme.d(46), UiTheme.d(46))) * 0.5
		icon.size = Vector2(UiTheme.d(46), UiTheme.d(46))
		add_child(icon)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c + Vector2(0, UiTheme.d(3)), r, UiTheme.CARD_LIP, true, -1.0, true)
		draw_circle(c, r, UiTheme.SLOT, true, -1.0, true)
		if value > 0.0:
			var width := UiTheme.d(9)
			draw_arc(c, r - width * 0.5, -PI * 0.5, -PI * 0.5 + TAU * clampf(value, 0.0, 1.0),
				maxi(3, int(64 * value)), VoterGroups.color(group), width, true)

## Yarım daire kadran: kırmızıdan yeşile beş dilim, ibre değeri (0..1) gösterir.
class Dial extends Control:
	var value := 0.5
	const COLORS := [Color("C42B2B"), Color("F2B632"), Color("E5D16A"), Color("7AC25A"), Color("1F8A4C")]

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y)
		var r := minf(size.x * 0.5, size.y)
		if r < 4.0:
			return
		for i in 5:
			var pts := PackedVector2Array([c])
			for k in 9:
				var a := PI + PI * (float(i) + float(k) / 8.0) / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, COLORS[i])
		draw_circle(c, r * 0.58, InspectCard.CARD_BG, true, -1.0, true)
		var angle := PI + PI * clampf(value, 0.0, 1.0)
		draw_line(c, c + Vector2(cos(angle), sin(angle)) * r * 0.95, UiTheme.INK, UiTheme.d(3), true)
		draw_circle(c, UiTheme.d(4), UiTheme.INK, true, -1.0, true)

class DashedLine extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var x := 0.0
		var dash := UiTheme.d(6)
		while x < size.x:
			draw_line(Vector2(x, size.y * 0.5), Vector2(minf(x + dash, size.x), size.y * 0.5), InspectCard.LINE, maxf(1.0, size.y), false)
			x += dash * 2.0
