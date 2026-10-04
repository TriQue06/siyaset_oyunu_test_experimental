class_name PartyInfoCard
extends RefCounted
## Sağdaki oyuncu kartının üstüne gelince çıkan parti profili: parti ve oyuncu
## adı, meclis / oy / puan / kamuoyu bilgisi, hükümetteki yeri ve ideoloji
## tablosu (her eksende -3..+3 arası 7 kutu, partinin konumu kendi renginde).

const WIDTH := 320.0
const DIM := UiTheme.TEXT_MUTED

static func build(peer_id: int, my_id: int) -> PanelContainer:
	var party: Dictionary = PartyManager.data_of(peer_id)
	var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
	var parts := PopupKit.frame(WIDTH, color)
	var card: PanelContainer = parts[0]
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: VBoxContainer = parts[1]

	var leader := PoliticianPresets.display_name(peer_id)
	if MultiplayerManager.is_bot(peer_id):
		leader += " · bot"
	if peer_id == my_id:
		leader += " (sen)"
	box.add_child(PopupKit.header(String(party.get("name", "?")), leader, PartyBadge.build(party, Vector2(40, 40), 64)))

	# Sayılar: dört eşit kutu.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	var has_seats: bool = CardManager.last_seats.has(peer_id)
	stats.add_child(_stat(str(int(CardManager.last_seats.get(peer_id, 0))) if has_seats else "—", "vekil", UiTheme.TEXT))
	stats.add_child(_stat("%%%.1f" % float(CardManager.last_vote_shares[peer_id]) if has_seats else "—", "oy", UiTheme.TEXT))
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
	var title := _label(String(info[0]), PopupKit.FS_TEXT, UiTheme.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label(IdeologyAxes.position_text(axis, value), PopupKit.FS_TEXT, color.lightened(0.35)))

	var scale := HBoxContainer.new()
	scale.add_theme_constant_override("separation", 6)
	scale.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(scale)
	var left := _label(String(info[1]), PopupKit.FS_SECTION, DIM)
	left.custom_minimum_size = Vector2(64, 0)
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
		cell.custom_minimum_size = Vector2(10, 12)
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
	right.custom_minimum_size = Vector2(64, 0)
	scale.add_child(right)
	return box

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
