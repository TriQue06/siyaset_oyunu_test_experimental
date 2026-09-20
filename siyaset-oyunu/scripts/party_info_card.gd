class_name PartyInfoCard
extends RefCounted
## Sağdaki oyuncu kartının üstüne gelince çıkan parti profili: parti ve oyuncu
## adı, meclis / oy / puan / kamuoyu bilgisi, hükümetteki yeri ve ideoloji
## tablosu (her eksende -3..+3 arası 7 kutu, partinin konumu kendi renginde).

const WIDTH := 330.0
const DIM := UiTheme.TEXT_MUTED

static func build(peer_id: int, my_id: int) -> PanelContainer:
	var party: Dictionary = PartyManager.parties.get(peer_id, {})
	var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(WIDTH, 0)
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	card.add_theme_stylebox_override("panel", style)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.GAP_S)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(outer)
	# Solda parti renginde şerit.
	outer.add_child(UiTheme.stripe(color))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(box)

	# Başlık: logo, parti adı, oyuncu adı.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	var badge := PartyBadge.build(party, Vector2(46, 46), 64)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(names)
	names.add_child(_label(String(party.get("name", "?")), 20, Color.WHITE))
	var leader := String(MultiplayerManager.players.get(peer_id, {}).get("name", "?"))
	if MultiplayerManager.is_bot(peer_id):
		leader += "  · bot"
	if peer_id == my_id:
		leader += "  (Sen)"
	names.add_child(_label(leader, 13, DIM))

	# Sayılar.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	var has_seats: bool = CardManager.last_seats.has(peer_id)
	stats.add_child(_stat(str(int(CardManager.last_seats.get(peer_id, 0))) if has_seats else "—", "vekil", Color.WHITE))
	stats.add_child(_stat("%%%.1f" % float(CardManager.last_vote_shares[peer_id]) if has_seats else "—", "oy", Color.WHITE))
	stats.add_child(_stat(str(GovernmentManager.score_of(peer_id)), "puan", UiTheme.GOLD))
	var opinion := CardManager.national_of(peer_id)
	stats.add_child(_stat("%+.1f" % opinion, "kamuoyu", ProvincePanel._opinion_color(opinion)))

	var role := role_text(peer_id)
	box.add_child(_label(role, UiTheme.FS_SMALL, UiTheme.GREEN if role.begins_with("Hükümet:") else DIM))

	box.add_child(UiTheme.rule())
	box.add_child(_label("İDEOLOJİ", 11, DIM))
	var ideology: Dictionary = party.get("ideology", IdeologyAxes.default_values())
	for axis in IdeologyAxes.AXES:
		box.add_child(_axis_row(axis, float(ideology.get(axis, 0)), color))
	return card

## "Hükümet: Başbakanlık, 3 bakanlık" / "Muhalefet" / "Hükümet yok".
static func role_text(peer_id: int) -> String:
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
	var title := _label(String(info[0]), 13, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label(IdeologyAxes.format_value(value), 13, color.lightened(0.25)))

	var scale := HBoxContainer.new()
	scale.add_theme_constant_override("separation", 6)
	scale.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(scale)
	var left := _label(String(info[1]), 11, DIM)
	left.custom_minimum_size = Vector2(76, 0)
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale.add_child(left)
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 2)
	cells.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scale.add_child(cells)
	var steps := int(roundf((IdeologyAxes.AXIS_MAX - IdeologyAxes.AXIS_MIN) / IdeologyAxes.STEP))
	for i in steps + 1:
		var v: float = IdeologyAxes.AXIS_MIN + i * IdeologyAxes.STEP
		var whole := is_equal_approx(v, roundf(v))
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(9, 12 if whole else 8)
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cell_color := color if is_equal_approx(v, value) else (
			UiTheme.PANEL_LIGHT if is_zero_approx(v) else (UiTheme.PANEL_DARK if whole else UiTheme.SLOT))
		cell.add_theme_stylebox_override("panel", UiSkin.color_box(cell_color))
		cells.add_child(cell)
	var right := _label(String(info[2]), 11, DIM)
	right.custom_minimum_size = Vector2(76, 0)
	scale.add_child(right)
	return box

static func _stat(value: String, caption: String, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value_label := _label(value, 18, color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value_label)
	var caption_label := _label(caption, 10, DIM)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption_label)
	return box

static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
