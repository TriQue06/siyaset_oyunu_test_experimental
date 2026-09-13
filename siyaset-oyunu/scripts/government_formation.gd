extends Control
## Hükümet kurma görevini alan oyuncunun ekranı. İKİ AŞAMALI:
##
##   1) ORTAKLAR: hükümete hangi partiler girecek seçilir. Görevi alan parti
##      her zaman dahildir ve çıkarılamaz.
##   2) DAĞITIM: görevler (1 başbakanlık, 1 başbakan yardımcılığı, bakanlıklar)
##      SADECE seçilen ortaklar arasında paylaştırılır.
##
## Sonra "Teklifte Bulun" ile teklif meclise gider. Bu sahne yalnızca görevli
## oyuncuda açılır; diğerleri GameScreen'de "Hükümet kuruluyor" perdesini görür.

enum Step { PARTNERS, DISTRIBUTE }

const CHIP_SIZE := Vector2(34, 34)

@onready var title_label: Label = %TitleLabel
@onready var info_label: Label = %InfoLabel
@onready var post_list: VBoxContainer = %PostList
@onready var summary_label: Label = %SummaryLabel
@onready var propose_button: Button = %ProposeButton
@onready var back_button: Button = %BackButton
@onready var parliament_diagram: ParliamentDiagram = %ParliamentDiagram
@onready var seat_list: VoteSharePanel = %SeatList

## Başlığın süre sayacı eklenmemiş hali.
var _title_base: String = ""
var _last_shown_second: int = -1

var _step: int = Step.PARTNERS
## Hükümete girecek partiler (peer_id listesi).
var _partners: Array = []
## post_id -> peer_id
var _assignments: Dictionary = {}
## Dağıtım aşamasında: post_id -> { peer_id -> çip Control }
var _chips: Dictionary = {}

func _ready() -> void:
	var backdrop := UiSkin.panel_background(UiSkin.PANEL_DARK)
	add_child(backdrop)
	move_child(backdrop, 0)

	UiSkin.skin_button(propose_button)
	UiSkin.skin_button(back_button)
	propose_button.pressed.connect(_on_primary_pressed)
	back_button.pressed.connect(_on_back_pressed)

	GovernmentManager.phase_changed.connect(_on_phase_changed)

	_partners = [multiplayer.get_unique_id()]
	_step = Step.PARTNERS
	_rebuild()

## Görev artık bizde değilse (teklif reddedilip sıra devrettiyse) burada
## kalmanın anlamı yok.
func _on_phase_changed() -> void:
	if GovernmentManager.phase != GovernmentManager.Phase.FORMING or not GovernmentManager.is_my_mandate():
		SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")

func _process(_delta: float) -> void:
	var second := int(ceil(GovernmentManager.phase_seconds_left()))
	if second != _last_shown_second:
		_last_shown_second = second
		_update_title()

func _update_title() -> void:
	title_label.text = "%s   (Süre: %s)" % [_title_base, GameRules.format_seconds(GovernmentManager.phase_seconds_left())]

func _rebuild() -> void:
	for child in post_list.get_children():
		child.queue_free()
	_chips.clear()

	var attempt: int = GovernmentManager.MAX_ATTEMPTS - GovernmentManager.attempts_left() + 1
	if _step == Step.PARTNERS:
		_title_base = "1/2 — Hükümet Ortakları"
		info_label.text = "Hükümete girecek partileri seç. Kendi partin her zaman dahildir.\nGörev verdiğin her ortak oylamada EVET demezse teklif düşer. Süre dolarsa hak yanar.\n%d. teklif hakkın (toplam %d)." % [
			attempt, GovernmentManager.MAX_ATTEMPTS,
		]
		propose_button.text = "Dağıtıma Geç"
		back_button.visible = false
		_build_partner_rows()
	else:
		_title_base = "2/2 — Görev Dağılımı"
		info_label.text = "%d görevi ortaklar arasında paylaştır. Başbakanlık kimdeyse ANA İKTİDAR PARTİSİ odur.\nMecliste %d sandalye var; teklifin düşmesi için HAYIR oylarının %d sandalyeyi geçmesi gerekir." % [
			GovernmentPresets.POSTS.size(), GovernmentManager.total_seats(), GovernmentManager.total_seats() / 2,
		]
		propose_button.text = "Teklifte Bulun"
		back_button.visible = true
		_build_post_rows()

	_refresh_summary()
	_refresh_seat_view()
	_update_title()

## Soldaki meclis görünümü: her partinin sandalye sayısı (liste) ve parlamento
## diyagramı. Hükümete seçilen ortaklar diyagramın solunda TAM renkli,
## dışarıda kalanlar soluk — koalisyonun meclisteki ağırlığı bir bakışta görünür.
func _refresh_seat_view() -> void:
	var ids: Array = GovernmentManager.voter_ids()
	ids.sort_custom(func(a, b):
		var in_a: bool = _partners.has(a)
		var in_b: bool = _partners.has(b)
		if in_a != in_b:
			return in_a
		return GovernmentManager.seats_of(a) > GovernmentManager.seats_of(b)
	)
	var seat_entries: Array = []
	var rows: Array = []
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
		var seats := GovernmentManager.seats_of(peer_id)
		seat_entries.append({"seats": seats, "color": color if _partners.has(peer_id) else color.darkened(0.6)})
		rows.append({
			"name": party.get("name", "?"),
			"leader": MultiplayerManager.players.get(peer_id, {}).get("name", ""),
			"color": color,
			"percent": float(CardManager.last_vote_shares.get(peer_id, 0.0)),
			"seats": seats,
		})
	parliament_diagram.set_results(seat_entries)
	seat_list.set_data(rows)

## Dağıtım adımının başında: ortakları geri dönmeden ekleyip çıkarmak için.
## Çıkarılan ortağın görevleri görevli partiye geçer (bkz. _build_post_rows).
func _build_partner_bar() -> void:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	var title := Label.new()
	title.text = "Ortaklar (tıkla: ekle/çıkar):"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(title)
	var me := multiplayer.get_unique_id()
	for peer_id in GovernmentManager.voter_ids():
		var in_gov: bool = _partners.has(peer_id)
		var btn := Button.new()
		UiSkin.skin_button(btn)
		btn.text = "%s (%d)" % [PartyManager.parties.get(peer_id, {}).get("name", "?"), GovernmentManager.seats_of(peer_id)]
		btn.modulate = Color.WHITE if in_gov else Color(1, 1, 1, 0.5)
		btn.tooltip_text = "Görevli parti (sabit)" if peer_id == me else ("Hükümetten çıkar" if in_gov else "Hükümete ekle")
		btn.disabled = peer_id == me
		if peer_id != me:
			btn.pressed.connect(_on_partner_toggled.bind(peer_id))
		bar.add_child(btn)
	post_list.add_child(bar)

# --- 1. Aşama: ortak seçimi -------------------------------------------------

func _build_partner_rows() -> void:
	var me := multiplayer.get_unique_id()
	for peer_id in GovernmentManager.voter_ids():
		var is_me: bool = peer_id == me
		var row := PanelContainer.new()
		UiSkin.skin_panel(row, UiSkin.PANEL)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		row.add_child(margin)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		margin.add_child(hbox)

		hbox.add_child(_build_party_chip(peer_id))

		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.text = "%s — %s   (%d sandalye)" % [
			PartyManager.parties.get(peer_id, {}).get("name", "?"),
			MultiplayerManager.players.get(peer_id, {}).get("name", "?"),
			GovernmentManager.seats_of(peer_id),
		]
		hbox.add_child(name_label)

		var toggle := Button.new()
		toggle.custom_minimum_size = Vector2(150, 34)
		UiSkin.skin_button(toggle)
		if is_me:
			toggle.text = "GÖREVLİ (sabit)"
			toggle.disabled = true
		else:
			toggle.text = "Çıkar" if _partners.has(peer_id) else "Ekle"
			toggle.pressed.connect(_on_partner_toggled.bind(peer_id))
		hbox.add_child(toggle)

		if not _partners.has(peer_id):
			row.modulate = Color(1, 1, 1, 0.55)
		post_list.add_child(row)

func _on_partner_toggled(peer_id: int) -> void:
	if _partners.has(peer_id):
		_partners.erase(peer_id)
	else:
		_partners.append(peer_id)
	_rebuild()

# --- 2. Aşama: görev dağılımı ----------------------------------------------

func _build_post_rows() -> void:
	_build_partner_bar()
	for post in GovernmentPresets.POSTS:
		var post_id: String = post["id"]
		# Ortak listesi değiştiyse geçersiz kalan atamaları tazele.
		if not _partners.has(int(_assignments.get(post_id, -1))):
			_assignments[post_id] = _partners[0]

		var row := PanelContainer.new()
		UiSkin.skin_panel(row, UiSkin.PANEL)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		row.add_child(margin)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		margin.add_child(hbox)

		var name_label := Label.new()
		name_label.text = "%s  (+%d)" % [post["title"], post["points"]]
		name_label.custom_minimum_size = Vector2(240, 0)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		hbox.add_child(name_label)

		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 6)
		chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(chips)

		var per_post: Dictionary = {}
		for peer_id in _partners:
			var chip := _build_party_chip(peer_id)
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			chip.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_on_chip_pressed(post_id, peer_id)
			)
			chips.add_child(chip)
			per_post[peer_id] = chip
		_chips[post_id] = per_post

		post_list.add_child(row)

	_refresh_chip_states()

func _on_chip_pressed(post_id: String, peer_id: int) -> void:
	_assignments[post_id] = peer_id
	_refresh_chip_states()
	_refresh_summary()

func _refresh_chip_states() -> void:
	for post_id in _chips.keys():
		var selected: int = int(_assignments.get(post_id, -1))
		for peer_id in _chips[post_id].keys():
			var chip: Control = _chips[post_id][peer_id]
			var halo: Control = chip.get_node_or_null("Halo")
			if halo != null:
				halo.visible = peer_id == selected
			chip.modulate = Color.WHITE if peer_id == selected else Color(1, 1, 1, 0.5)

# --- Ortak parçalar ---------------------------------------------------------

## Bir partiyi temsil eden çip. Görünen her şey PNG: zemin ui_slot.png
## (parti rengiyle boyanmış) + parti ikonu + seçim vurgusu.
func _build_party_chip(peer_id: int) -> Control:
	var party: Dictionary = PartyManager.parties.get(peer_id, {})

	var chip := Control.new()
	chip.custom_minimum_size = CHIP_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = "%s — %s" % [
		party.get("name", "?"),
		MultiplayerManager.players.get(peer_id, {}).get("name", "?"),
	]

	var bg := UiSkin.color_surface(party.get("bg_color", Color(0.4, 0.4, 0.4)), UiSkin.SLOT)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(bg)

	if party.has("icon_index"):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = PartyPresets.get_icon_texture(party["icon_index"], 64)
		icon.modulate = party.get("icon_color", Color.WHITE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		chip.add_child(icon)

	var halo := TextureRect.new()
	halo.name = "Halo"
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.texture = load("res://assets/ui/target_highlight.png")
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_SCALE
	halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo.hide()
	chip.add_child(halo)

	return chip

func _refresh_summary() -> void:
	if _step == Step.PARTNERS:
		var seats := 0
		var names: Array[String] = []
		for peer_id in _partners:
			seats += GovernmentManager.seats_of(peer_id)
			names.append(PartyManager.parties.get(peer_id, {}).get("name", "?"))
		var total := GovernmentManager.total_seats()
		summary_label.text = "Ortaklar: %s\nToplam %d/%d sandalye — %s" % [
			" + ".join(names), seats, total,
			"salt çoğunluk VAR" if seats * 2 > total else "salt çoğunluk YOK (muhalefet dağınıksa yine de geçebilir)",
		]
		return

	var points: Dictionary = {}
	for post_id in _assignments.keys():
		var peer_id: int = int(_assignments[post_id])
		points[peer_id] = int(points.get(peer_id, 0)) + GovernmentPresets.post_points(post_id)

	var gov_seats := 0
	for peer_id in points.keys():
		gov_seats += GovernmentManager.seats_of(peer_id)

	var parts: Array[String] = []
	for peer_id in points.keys():
		parts.append("%s +%d" % [PartyManager.parties.get(peer_id, {}).get("name", "?"), points[peer_id]])

	var pm_peer: int = int(_assignments.get(GovernmentPresets.POST_PM, -1))
	var total2 := GovernmentManager.total_seats()
	summary_label.text = "Ana iktidar partisi: %s  |  Hükümet %d/%d sandalye (%s)\n%s" % [
		PartyManager.parties.get(pm_peer, {}).get("name", "?"),
		gov_seats, total2,
		"salt çoğunluk VAR" if gov_seats * 2 > total2 else "salt çoğunluk YOK",
		" · ".join(parts),
	]

func _on_back_pressed() -> void:
	_step = Step.PARTNERS
	_rebuild()

func _on_primary_pressed() -> void:
	if _step == Step.PARTNERS:
		# Atamalar KORUNUR: geri dönüp ortak ekleyip/çıkarıp tekrar ilerleyince
		# yapılan dağıtım kaybolmaz; sadece artık ortak olmayan partinin
		# görevleri görevli partiye düşer (bkz. _build_post_rows).
		_step = Step.DISTRIBUTE
		_rebuild()
		return
	propose_button.disabled = true
	GovernmentManager.submit_government_proposal(_assignments)
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")
