extends Control
## PARTİ KURMA SİHİRBAZI (0.0.230) — eski "Siyasetçini Oluştur" ve "Partini Kur"
## ekranları TEK ekranda, beş adımda:
##   1 Siyasetçi (cinsiyet, ad, soyad, isim dili) · 2 Meslek ve kişilik ·
##   3 Memleket (harita) · 4 Parti kimliği (ad, logo, renk) · 5 Seçmen (2 çekirdek grup)
## Adımlar sırayla gelir ama üstteki adım şeridinden istenen adıma atlanabilir.
## Sağda hep görünen ADAY KARTI (portre, meslek + kişilik, memleket, parti) ve
## ODA listesi (herkesin partisi, hazır durumu; oda sahibine bot düzenleme).
## Hazır olmak için her adım tamam olmalı; "Hazırım" siyasetçiyi ve partiyi
## birlikte gönderir (set_my_politician + set_party_and_ready). Herkes hazır
## olunca host oyunu başlatır. Kilitliyken adım içeriği kapalıdır.
## ODA SAHİBİ BOT DÜZENLER: odada ✎ -> sihirbaz o botun siyasetçisini ve
## partisini düzenler (her değişiklik anında gider); "Ben" ile kendine dönülür.
## Arayüz tamamen kodla kurulur (sahne sadece kök düğüm).

const MAP_SCENE := preload("res://scenes/Map.tscn")
const STEP_COUNT := 5
const STEP_TITLES := ["Siyasetçi", "Meslek ve kişilik", "Memleket", "Parti kimliği", "Seçmen"]
const STEP_HINTS := ["Kim olduğunu seç: adın ve soyadın.",
	"Meslek oyun boyunca sana bir avantaj verir; kişilik tarzını biraz daha belirler.",
	"Haritadan bir il seç: memleketinde güçlü bir teşkilatla başlarsın.",
	"Partinin adı, logosu ve rengi.",
	"Partinin dayanacağı iki çekirdek seçmen grubunu seç."]
const SIDE_WIDTH := 350.0
const PORTRAIT_SIZE := 76.0
const LOGO_SIZE := 38.0
const PREVIEW_SIZE := 150.0
const ICON_BUTTON_SIZE := 34.0
const SWATCH_SIZE := 28.0
const GRID_ICON_PIXEL_SIZE := 64
const PREVIEW_ICON_PIXEL_SIZE := 256
const MAP_PADDING := 10.0
const HOME_COLOR := Color("FFC93C")
## Parti ikonları her zaman beyaz; beyaz zemin seçilemez.
const ICON_COLOR := Color.WHITE
## Cinsiyet düğmeleri: erkek mavi, kadın pembe.
const GENDER_STYLE := {"m": {"text": "Erkek", "color": Color("3A8DE0")},
	"f": {"text": "Kadın", "color": Color("E8559C")}}

# --- Taslak (düzenlenen hedefin: kendim ya da bir bot) ----------------------------
var _gender: String = "m"
var _first_name: String = ""
var _surname: String = ""
## Rastgele isimlerin dili; oyun diliyle başlar.
var _name_lang: String = "en" if L.is_en() else "tr"
var _background_id: String = ""
var _trait_id: String = ""
var _hometown: String = ""
var _portrait: String = ""
var _party_name: String = ""
var _icon_index: int = 0
var _bg_color: Color = PartyPresets.COLORS[0]
var _core: Array = []

var _step: int = 0
var _visited: Dictionary = {0: true}
var _is_locked: bool = false
## Düzenlenen bot (-1 = kendim). Bot düzenlenirken kendi taslağım burada saklanır.
var _edit_target: int = -1
var _own_backup: Dictionary = {}
var _hovered_profile: String = ""
var _hovered_province: String = ""

# --- Düğümler ---------------------------------------------------------------------
var _title: Label
var _ready_count: Label
var _step_buttons: Array = []
var _step_title: Label
var _step_hint: Label
var _pages: Array = []
var _blocker: Control
var _back_button: Button
var _next_button: Button
var _status: Label
# 1 siyasetçi
var _gender_buttons: Dictionary = {}
var _first_edit: LineEdit
var _surname_edit: LineEdit
var _lang_button: Button
var _bot_random_button: Button
# 2 meslek / kişilik
var _profession_cards: Dictionary = {}
var _trait_cards: Dictionary = {}
var _detail_box: HBoxContainer
# 3 memleket
var _map_clip: Control
var _map: Node2D
var _home_title: Label
var _home_body: Label
# 4 parti kimliği
var _name_edit: LineEdit
var _name_hint: Label
var _preview_bg: ColorRect
var _preview_icon: TextureRect
var _icon_grid: GridContainer
var _color_row: HFlowContainer
# 5 seçmen
var _core_grid: GridContainer
# sağ sütun
var _card_box: VBoxContainer
var _players_list: VBoxContainer

func _ready() -> void:
	theme = load("res://assets/ui/main_theme.tres")
	# Harita tıklamaları _unhandled_input ile gelir: kök düğüm yutmasın.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if GameMap.province_ids().is_empty():
		# Tek başına çalıştırılan sahne (oyun yok): örnek bir harita kur.
		GameMap.generate_new(GameMap.DEFAULT_SEED)
	_core = VoterGroups.random_core()
	_restore_own()
	_build_ui()
	_load_fields()
	MultiplayerManager.party_setup_finished.connect(_on_party_setup_finished)
	PartyManager.parties_updated.connect(_on_parties_updated)
	_show_step(_step)
	_push_party()

# --- Taslak yükleme ----------------------------------------------------------------

## Kendi önceki seçimlerim (geri dönüş, yeniden bağlanma): yoksa rastgele ad.
func _restore_own() -> void:
	var me := multiplayer.get_unique_id()
	var data: Dictionary = PartyManager.my_politician
	if data.is_empty():
		data = PartyManager.politicians.get(me, {})
	if data.is_empty():
		_first_name = PoliticianPresets.random_first_name(_gender, "", null, _name_lang)
		_surname = PoliticianPresets.random_surname(PoliticianPresets.used_surnames(me), null, _name_lang)
	else:
		_politician_from(data)
	var draft: Dictionary = PartyManager.parties.get(me, {})
	if PartyManager.is_valid_name(String(draft.get("name", ""))):
		_party_name = String(draft["name"])
		_icon_index = PartyPresets.clamp_icon_index(int(draft.get("icon_index", 0)))
		if VoterGroups.is_valid_core(draft.get("core", [])):
			_core = (draft["core"] as Array).duplicate()
	if draft.has("bg_color"):
		_bg_color = draft["bg_color"]
	_bg_color = _first_free_color(_bg_color)
	_is_locked = PartyManager.is_ready(me)

func _politician_from(data: Dictionary) -> void:
	_gender = String(data.get("gender", "m"))
	_first_name = String(data.get("first_name", ""))
	_surname = String(data.get("surname", ""))
	_background_id = String(data.get("background", ""))
	if not PoliticianPresets.is_valid_background(_background_id):
		_background_id = ""
	_trait_id = String(data.get("trait", ""))
	if not PoliticianPresets.is_valid_trait(_trait_id):
		_trait_id = ""
	_hometown = String(data.get("hometown", ""))
	_portrait = String(data.get("portrait", ""))

func _draft_politician() -> Dictionary:
	return PoliticianPresets.make(_first_name, _surname, _background_id, _hometown, _gender, _trait_id, _portrait)

func _editing_bot() -> bool:
	return _edit_target != -1 and _edit_target != multiplayer.get_unique_id()

# --- Kurulum -----------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top := VBoxContainer.new()
	top.position = Vector2(24, 12)
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_title = UiTheme.mono_label(L.t("YENİ BİR PARTİ"), 26, UiTheme.GOLD, true)
	top.add_child(_title)
	top.add_child(PopupKit.label(L.t("Siyasetçini yarat, partini kur, seçmenini seç."), 13, UiTheme.TEXT_MUTED))
	# Sağ üstte Menü düğmesi var: hazır sayısı onun solunda.
	_ready_count = UiTheme.mono_label("", 16, UiTheme.TEXT_MUTED, true)
	_ready_count.anchor_left = 1.0
	_ready_count.anchor_right = 1.0
	_ready_count.offset_left = -400
	_ready_count.offset_right = -190
	_ready_count.offset_top = 26
	_ready_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ready_count)

	var steps := HBoxContainer.new()
	steps.set_anchors_preset(Control.PRESET_TOP_WIDE)
	steps.offset_left = 16
	steps.offset_right = -16
	steps.offset_top = 72
	steps.offset_bottom = 110
	steps.add_theme_constant_override("separation", 6)
	add_child(steps)
	for i in STEP_COUNT:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_show_step.bind(i))
		steps.add_child(b)
		_step_buttons.append(b)

	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.offset_left = 16
	main.offset_top = 120
	main.offset_right = -16
	main.offset_bottom = -14
	main.add_theme_constant_override("separation", 12)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main)
	main.add_child(_build_step_panel())
	main.add_child(_build_side())

func _panel(width: float, accent: Color) -> Array:
	var built := PopupKit.frame(width, accent)
	var panel: PanelContainer = built[0]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return built

func _build_step_panel() -> Control:
	var built := _panel(0, UiTheme.GOLD)
	var panel: PanelContainer = built[0]
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Harita tıklamaları _unhandled_input ile gelir: paneller yutmasın.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body: VBoxContainer = built[1]
	_step_title = UiTheme.mono_label("", 20, UiTheme.TEXT, true)
	body.add_child(_step_title)
	_step_hint = PopupKit.note("", UiTheme.TEXT_MUTED)
	body.add_child(_step_hint)
	body.add_child(UiTheme.rule())

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stack)
	for page in [_build_politician_page(), _build_profile_page(), _build_home_page(),
			_build_identity_page(), _build_voters_page()]:
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)
		_pages.append(page)
	# Kilitliyken (hazır) adım içeriği tıklanamaz.
	_blocker = PanelContainer.new()
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(UiTheme.PANEL_DARK, 0.72)
	UiSkin.apply_style(_blocker, "panel", dim)
	var lock_note := UiTheme.mono_label(L.t("Hazırsın. Değiştirmek için hazırlığı iptal et."), 16, UiTheme.GREEN, true)
	lock_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_blocker.add_child(lock_note)
	stack.add_child(_blocker)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	body.add_child(nav)
	_back_button = Button.new()
	_back_button.text = L.t("← Geri")
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.custom_minimum_size = Vector2(130, 44)
	_back_button.pressed.connect(func(): _show_step(_step - 1))
	nav.add_child(_back_button)
	_status = PopupKit.note("", UiTheme.TEXT_MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_status)
	_next_button = Button.new()
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.custom_minimum_size = Vector2(220, 44)
	_next_button.add_theme_font_size_override("font_size", 17)
	_next_button.pressed.connect(_on_next_pressed)
	nav.add_child(_next_button)
	return panel

func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return page

func _scroll_page() -> Array:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _page()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	return [scroll, page]

# --- 1 · Siyasetçi -----------------------------------------------------------------

func _build_politician_page() -> Control:
	var built := _scroll_page()
	var page: VBoxContainer = built[1]
	page.add_child(PopupKit.section(L.t("Cinsiyet")))
	var gender_row := HBoxContainer.new()
	gender_row.add_theme_constant_override("separation", 10)
	page.add_child(gender_row)
	for g in ["m", "f"]:
		var gb := Button.new()
		gb.text = L.t(String(GENDER_STYLE[g]["text"]))
		gb.focus_mode = Control.FOCUS_NONE
		gb.custom_minimum_size = Vector2(130, 42)
		gb.add_theme_font_size_override("font_size", 16)
		gb.pressed.connect(_on_gender_pressed.bind(g))
		gender_row.add_child(gb)
		_gender_buttons[g] = gb

	page.add_child(PopupKit.section(L.t("Ad ve soyad"), L.t("zarla değiştir ya da kendin yaz")))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	page.add_child(name_row)
	_first_edit = _name_field(L.t("Ad"))
	name_row.add_child(_first_edit)
	_surname_edit = _name_field(L.t("Soyad"))
	name_row.add_child(_surname_edit)
	var dice_row := HBoxContainer.new()
	dice_row.add_theme_constant_override("separation", 8)
	page.add_child(dice_row)
	for spec in [[L.t("🎲 Ad"), L.t("Sadece adı değiştir"), true, false],
			[L.t("🎲 Soyad"), L.t("Sadece soyadı değiştir"), false, true],
			[L.t("🎲 İkisi de"), L.t("Ad ve soyadı birlikte değiştir"), true, true]]:
		var dice := Button.new()
		dice.text = spec[0]
		dice.focus_mode = Control.FOCUS_NONE
		dice.custom_minimum_size = Vector2(0, 40)
		dice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dice.pressed.connect(_reroll_name.bind(spec[2], spec[3]))
		dice_row.add_child(dice)
	# Dil düğmesi kendi dilinde yazar ("Türkçe", "English"); basınca sıradaki dil.
	_lang_button = Button.new()
	_lang_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_lang_button.focus_mode = Control.FOCUS_NONE
	_lang_button.custom_minimum_size = Vector2(0, 40)
	_lang_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_button.pressed.connect(_on_name_lang_pressed)
	dice_row.add_child(_lang_button)
	_bot_random_button = Button.new()
	_bot_random_button.text = L.t("🎲 Bot Profilini Rastgele Yap")
	_bot_random_button.focus_mode = Control.FOCUS_NONE
	_bot_random_button.custom_minimum_size = Vector2(0, 42)
	_bot_random_button.pressed.connect(_on_bot_random_pressed)
	page.add_child(_bot_random_button)
	return built[0]

func _name_field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = PoliticianPresets.PART_MAX_LENGTH
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 46)
	edit.add_theme_font_override("font", UiTheme.mono(true))
	edit.add_theme_font_size_override("font_size", 22)
	edit.text_changed.connect(_on_name_typed.bind(edit))
	return edit

# --- 2 · Meslek ve kişilik ---------------------------------------------------------

func _build_profile_page() -> Control:
	var built := _scroll_page()
	var page: VBoxContainer = built[1]
	page.add_child(PopupKit.section(L.t("Meslek")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	for id in PoliticianPresets.BACKGROUND_ORDER:
		var card := _choice_card(PoliticianPresets.background(String(id)), "b:" + String(id))
		card.pressed.connect(_on_background_pressed.bind(String(id)))
		grid.add_child(card)
		_profession_cards[id] = card
	page.add_child(PopupKit.section(L.t("Kişilik")))
	var trait_row := GridContainer.new()
	trait_row.columns = 3
	trait_row.add_theme_constant_override("h_separation", 8)
	page.add_child(trait_row)
	for id in PoliticianPresets.TRAIT_ORDER:
		var card := _choice_card(PoliticianPresets.trait_info(String(id)), "t:" + String(id))
		card.pressed.connect(_on_trait_pressed.bind(String(id)))
		trait_row.add_child(card)
		_trait_cards[id] = card
	_detail_box = HBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 14)
	page.add_child(_detail_box)
	return built[0]

## Seçim kartı: ad + kısa etiket; ayrıntı alttaki kutuda (üzerine gelince de).
func _choice_card(info: Dictionary, hover_key: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 62)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.clip_contents = true
	var frame := Panel.new()
	frame.name = "SelectedFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := StyleBoxFlat.new()
	# Zeminsiz: UiSkin zeminli kutuları dokuya çevirip çerçeveyi siler.
	ring.draw_center = false
	ring.border_color = UiTheme.GOLD
	ring.set_border_width_all(3)
	UiSkin.apply_style(frame, "panel", ring)
	frame.visible = false
	button.add_child(frame)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = -6
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)
	var t := UiTheme.mono_label(String(info.get("title", "")), 15, UiTheme.TEXT, true)
	t.clip_text = true
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(t)
	var tag := UiTheme.mono_label("★ " + String(info.get("tag", "")), 12, UiTheme.GREEN)
	tag.clip_text = true
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tag)
	button.mouse_entered.connect(func():
		_hovered_profile = hover_key
		_refresh_detail())
	button.mouse_exited.connect(func():
		if _hovered_profile == hover_key:
			_hovered_profile = ""
			_refresh_detail())
	return button

## Alttaki ayrıntı: solda meslek, sağda kişilik (üzerine gelinen kart öne çıkar).
func _refresh_detail() -> void:
	for child in _detail_box.get_children():
		_detail_box.remove_child(child)
		child.queue_free()
	var bg_id := _background_id
	var trait_id := _trait_id
	if _hovered_profile.begins_with("b:"):
		bg_id = _hovered_profile.substr(2)
	elif _hovered_profile.begins_with("t:"):
		trait_id = _hovered_profile.substr(2)
	_detail_box.add_child(_detail_column(L.t("Meslek"), PoliticianPresets.background(bg_id),
		PoliticianPresets.BACKGROUNDS.get(bg_id, {}).get("appeal", []), L.t("Bir meslek seç.")))
	_detail_box.add_child(_detail_column(L.t("Kişilik"), PoliticianPresets.trait_info(trait_id), [], L.t("Bir kişilik seç.")))

func _detail_column(heading: String, info: Dictionary, appeal: Array, empty_text: String) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(PopupKit.section(heading))
	if info.is_empty():
		col.add_child(PopupKit.note(empty_text, UiTheme.TEXT_DIM))
		return col
	col.add_child(UiTheme.mono_label(String(info.get("title", "")), 17, UiTheme.TEXT, true))
	if not appeal.is_empty():
		col.add_child(_appeal_row(appeal))
	col.add_child(PopupKit.note(String(info.get("blurb", "")), UiTheme.TEXT_MUTED))
	col.add_child(PopupKit.note("★ " + String(info.get("perk", "")), UiTheme.GREEN))
	return col

func _appeal_row(appeal: Array) -> Control:
	var row := HFlowContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", 4)
	for group in appeal:
		row.add_child(VoterGroupIcon.make(String(group), 16.0))
		row.add_child(PopupKit.chip(VoterGroups.title(String(group)), VoterGroups.color(String(group))))
	return row

# --- 3 · Memleket ------------------------------------------------------------------

func _build_home_page() -> Control:
	var page := _page()
	_map_clip = Control.new()
	_map_clip.clip_contents = true
	_map_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_map_clip)
	_map = MAP_SCENE.instantiate()
	_map_clip.add_child(_map)
	var markers := _map.get_node_or_null("SeatMarkers")
	if markers != null:
		markers.visible = false
	_map.province_clicked.connect(_on_province_clicked)
	_map.province_hovered.connect(_on_province_hovered)
	_map_clip.resized.connect(_fit_map)
	GameMap.map_changed.connect(_fit_map)
	_home_title = UiTheme.mono_label("", 17, UiTheme.TEXT, true)
	_home_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_home_title)
	_home_body = PopupKit.note("", UiTheme.TEXT_MUTED)
	page.add_child(_home_body)
	return page

## Haritayı kutuya sığdır ve ortala.
func _fit_map() -> void:
	if _map == null or _map_clip == null:
		return
	var native := GameMap.map_size()
	var space := _map_clip.size - Vector2(MAP_PADDING, MAP_PADDING) * 2.0
	if native.x <= 0.0 or native.y <= 0.0 or space.x <= 0.0 or space.y <= 0.0:
		return
	var s := minf(space.x / native.x, space.y / native.y)
	_map.scale = Vector2(s, s)
	_map.position = (_map_clip.size - native * s) * 0.5

# --- 4 · Parti kimliği -------------------------------------------------------------

func _build_identity_page() -> Control:
	var built := _scroll_page()
	var page: VBoxContainer = built[1]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	page.add_child(top)
	_preview_bg = ColorRect.new()
	_preview_bg.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_preview_bg.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_preview_bg)
	_preview_icon = TextureRect.new()
	_preview_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_icon.offset_left = 22
	_preview_icon.offset_top = 22
	_preview_icon.offset_right = -22
	_preview_icon.offset_bottom = -22
	_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_bg.add_child(_preview_icon)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 6)
	top.add_child(name_col)
	name_col.add_child(PopupKit.section(L.t("Parti adı")))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = L.t("Parti adını yaz")
	_name_edit.max_length = PartyManager.NAME_MAX_LENGTH
	_name_edit.custom_minimum_size = Vector2(0, 46)
	_name_edit.add_theme_font_override("font", UiTheme.mono(true))
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.text_changed.connect(_on_party_name_changed)
	name_col.add_child(_name_edit)
	_name_hint = PopupKit.note("", UiTheme.TEXT_MUTED)
	name_col.add_child(_name_hint)
	page.add_child(PopupKit.section(L.t("Renk")))
	_color_row = HFlowContainer.new()
	_color_row.add_theme_constant_override("h_separation", 6)
	_color_row.add_theme_constant_override("v_separation", 6)
	page.add_child(_color_row)
	page.add_child(PopupKit.section(L.t("Logo")))
	_icon_grid = GridContainer.new()
	_icon_grid.columns = 16
	_icon_grid.add_theme_constant_override("h_separation", 6)
	_icon_grid.add_theme_constant_override("v_separation", 6)
	page.add_child(_icon_grid)
	for i in PartyPresets.icon_count():
		var btn := TextureButton.new()
		btn.texture_normal = PartyPresets.get_icon_texture(i, GRID_ICON_PIXEL_SIZE)
		# ignore_texture_size olmadan düğme dokunun gerçek boyutuna büyür.
		btn.ignore_texture_size = true
		btn.custom_minimum_size = Vector2(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		btn.pressed.connect(_on_icon_selected.bind(i))
		_icon_grid.add_child(btn)
	return built[0]

## Renk başka bir OYUNCUDA mı? (Botun rengi alınabilir, bot başka renge geçer.)
func _is_taken(color: Color) -> bool:
	if _editing_bot():
		return PartyManager.color_owner(color, _edit_target) != -1
	var owner := PartyManager.color_owner(color, multiplayer.get_unique_id())
	return owner != -1 and not MultiplayerManager.is_bot(owner)

func _first_free_color(preferred: Color) -> Color:
	if not preferred.is_equal_approx(ICON_COLOR) and not _is_taken(preferred):
		return preferred
	for color in PartyPresets.COLORS:
		if not color.is_equal_approx(ICON_COLOR) and not _is_taken(color):
			return color
	return preferred

func _build_color_row() -> void:
	for child in _color_row.get_children():
		_color_row.remove_child(child)
		child.queue_free()
	for i in PartyPresets.COLORS.size():
		var color: Color = PartyPresets.COLORS[i]
		var taken := _is_taken(color)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		if taken:
			btn.text = "✕"
			btn.add_theme_font_size_override("font_size", 12)
		btn.disabled = taken
		btn.modulate = Color.WHITE if not taken else Color(0.55, 0.55, 0.55, 1.0)
		var selected := color.is_equal_approx(_bg_color)
		var style := UiSkin.color_box(color, UiSkin.BUTTON_TINT_HOVER if selected else UiSkin.BUTTON_TINT_NORMAL)
		for state in ["normal", "hover", "pressed", "disabled"]:
			UiSkin.apply_style(btn, state, style)
		if selected:
			var ring := UiSkin.color_surface(UiTheme.GOLD, UiSkin.TARGET)
			ring.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.add_child(ring)
		if not taken:
			btn.pressed.connect(_on_color_selected.bind(i))
		_color_row.add_child(btn)

# --- 5 · Seçmen --------------------------------------------------------------------

func _build_voters_page() -> Control:
	var built := _scroll_page()
	var page: VBoxContainer = built[1]
	_core_grid = GridContainer.new()
	_core_grid.columns = 2
	_core_grid.add_theme_constant_override("h_separation", 8)
	_core_grid.add_theme_constant_override("v_separation", 8)
	page.add_child(_core_grid)
	page.add_child(PopupKit.note(L.t("Çekirdek gruplarda %%%d, diğerlerinde %%%d hitapla başlarsın; çekirdek gruplarda kazancın %d katıdır. Hitap yasa, miting ve toplantıyla büyür, rakipler senden seçmen çalabilir.") % [
		int(VoterGroups.CORE_START), int(VoterGroups.AFFINITY_NEUTRAL), int(VoterGroups.CORE_GAIN_MULT)], UiTheme.TEXT_MUTED))
	page.add_child(PopupKit.note(L.t("Aynı çiftten iki grup birlikte seçilemez (ör. işçi ve işveren)."), UiTheme.TEXT_DIM))
	return built[0]

## SEKİZ SEÇMEN GRUBU (çiftler yan yana): 2 çekirdek grup. Aynı çiftten ikisi
## seçilemez: çiftin öbür tarafına basmak seçimi oraya taşır; 2 seçiliyken
## üçüncüye basmak en eski seçimi bırakır.
func _build_core_buttons() -> void:
	for child in _core_grid.get_children():
		_core_grid.remove_child(child)
		child.queue_free()
	for group in VoterGroups.GROUP_IDS:
		_core_grid.add_child(_core_button(String(group)))

func _core_button(group: String) -> Button:
	var selected := _core.has(group)
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 58)
	button.button_pressed = selected
	UiSkin.skin_color_button(button, VoterGroups.color(group).darkened(0.25) if selected else UiTheme.PANEL)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -8
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon := VoterGroupIcon.make(group, 28.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var t := UiTheme.mono_label(VoterGroups.title(group), 15, UiTheme.TEXT, true)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(t)
	var blurb := UiTheme.mono_label(String(VoterGroups.data(group).get("blurb", "")), 11,
		UiTheme.TEXT if selected else UiTheme.TEXT_MUTED)
	blurb.clip_text = true
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(blurb)
	if selected:
		var mark := UiTheme.mono_label("✔", 18, UiTheme.GOLD, true)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
	button.pressed.connect(_on_core_pressed.bind(group))
	return button

# --- Sağ sütun: aday kartı + oda -----------------------------------------------------

func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.add_theme_constant_override("separation", 12)
	var card := _panel(SIDE_WIDTH, UiTheme.GOLD)
	(card[0] as PanelContainer).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	side.add_child(card[0])
	_card_box = card[1]
	var room := _panel(SIDE_WIDTH, UiTheme.PANEL_LIGHT)
	side.add_child(room[0])
	var room_body: VBoxContainer = room[1]
	room_body.add_child(PopupKit.section(L.t("Oda")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	room_body.add_child(scroll)
	_players_list = VBoxContainer.new()
	_players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_players_list)
	return side

## ADAY KARTI: düzenlenen siyasetçi ve partisi, anlık.
func _refresh_card() -> void:
	for child in _card_box.get_children():
		_card_box.remove_child(child)
		child.queue_free()
	_card_box.add_child(PopupKit.section(L.t("Bot adayı") if _editing_bot() else L.t("Aday kartın")))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_card_box.add_child(head)
	head.add_child(PoliticianPortrait.make(_draft_politician(), _bg_color, PORTRAIT_SIZE))
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_theme_constant_override("separation", 2)
	head.add_child(who)
	var full := ("%s %s" % [_first_name, _surname]).strip_edges()
	var name_label := UiTheme.mono_label(full if full != "" else L.t("adsız"), 18, UiTheme.TEXT, true)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(name_label)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	who.add_child(chips)
	chips.add_child(PopupKit.chip(PoliticianPresets.title(_background_id) if _background_id != "" else L.t("meslek ?"),
		UiTheme.GOLD if _background_id != "" else UiTheme.TEXT_DIM))
	chips.add_child(PopupKit.chip(PoliticianPresets.trait_title(_trait_id) if _trait_id != "" else L.t("kişilik ?"),
		UiTheme.PURPLE if _trait_id != "" else UiTheme.TEXT_DIM))
	who.add_child(PopupKit.note(L.t("Memleket: %s") % GameMap.name_of(_hometown) if _hometown != "" else L.t("Memleket seçilmedi"),
		UiTheme.TEXT_MUTED))
	var perks: Array = []
	if _background_id != "":
		perks.append(String(PoliticianPresets.background(_background_id).get("perk", "")))
	if _trait_id != "":
		perks.append(String(PoliticianPresets.trait_info(_trait_id).get("perk", "")))
	if not perks.is_empty():
		_card_box.add_child(PopupKit.note("★ " + "\n★ ".join(perks), UiTheme.GREEN))
	_card_box.add_child(UiTheme.rule())
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 10)
	_card_box.add_child(party_row)
	party_row.add_child(_logo(_icon_index, _bg_color, LOGO_SIZE))
	var party_texts := VBoxContainer.new()
	party_texts.add_theme_constant_override("separation", 2)
	party_texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_row.add_child(party_texts)
	var pname := UiTheme.mono_label(_party_name if PartyManager.is_valid_name(_party_name) else L.t("parti adı yok"), 16,
		UiTheme.TEXT if PartyManager.is_valid_name(_party_name) else UiTheme.TEXT_DIM, true)
	pname.clip_text = true
	party_texts.add_child(pname)
	var core_row := HFlowContainer.new()
	core_row.add_theme_constant_override("h_separation", 4)
	party_texts.add_child(core_row)
	for group in _core:
		core_row.add_child(PopupKit.chip(VoterGroups.title(String(group)), VoterGroups.color(String(group))))

func _logo(icon_index: int, color: Color, side: float) -> Control:
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(side, side)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.color = color
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_index >= 0:
		var icon := TextureRect.new()
		icon.texture = PartyPresets.get_icon_texture(icon_index, GRID_ICON_PIXEL_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var pad := side * 0.14
		icon.offset_left = pad
		icon.offset_top = pad
		icon.offset_right = -pad
		icon.offset_bottom = -pad
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.add_child(icon)
	return swatch

func _refresh_players() -> void:
	if _players_list == null:
		return
	for child in _players_list.get_children():
		_players_list.remove_child(child)
		child.queue_free()
	var my_id := multiplayer.get_unique_id()
	var order: Array = MultiplayerManager.lobby_order() if not MultiplayerManager.players.is_empty() else [my_id]
	var live_target := _edit_target if _editing_bot() else my_id
	var ready_count := 0
	for peer_id in order:
		var party: Dictionary = PartyManager.parties.get(peer_id, {}).duplicate()
		var politician: Dictionary = PoliticianPresets.of(int(peer_id))
		# Düzenlenen satır anlık (ad boşken host'a hiç gitmez).
		if int(peer_id) == live_target:
			party["icon_index"] = _icon_index
			party["bg_color"] = _bg_color
			if _party_name.strip_edges() != "":
				party["name"] = _party_name
			politician = _draft_politician()
		if PartyManager.is_ready(peer_id):
			ready_count += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var color := Color(party.get("bg_color", Color(0.3, 0.3, 0.3)))
		row.add_child(PoliticianPortrait.make(politician, color, 40.0) if not politician.is_empty() \
			else _logo(int(party.get("icon_index", -1)), color, 40.0))
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		var player_name := String(MultiplayerManager.players.get(peer_id, {}).get("name", L.t("Sen")))
		var player_label := PopupKit.label(player_name + (L.t(" (sen)") if int(peer_id) == my_id else "") \
			+ ("  🤖" if MultiplayerManager.is_bot(peer_id) else ""), 12, UiTheme.TEXT_MUTED)
		player_label.clip_text = true
		texts.add_child(player_label)
		var party_label := UiTheme.mono_label(String(party.get("name", L.t("parti kuruyor…"))), 15, UiTheme.TEXT, true)
		party_label.clip_text = true
		texts.add_child(party_label)
		if not politician.is_empty():
			var bits: Array = [String(politician.get("name", ""))]
			if PoliticianPresets.is_valid_background(String(politician.get("background", ""))):
				bits.append(PoliticianPresets.title(String(politician["background"])))
			if PoliticianPresets.is_valid_trait(String(politician.get("trait", ""))):
				bits.append(PoliticianPresets.trait_title(String(politician["trait"])))
			var leader := PopupKit.label(" · ".join(bits), 11, UiTheme.GOLD)
			leader.clip_text = true
			texts.add_child(leader)
		row.add_child(texts)
		# Oda sahibi botları düzenleyebilir; düzenlenen satır vurgulu.
		if MultiplayerManager.is_local_owner() and (MultiplayerManager.is_bot(peer_id) or int(peer_id) == my_id) \
				and MultiplayerManager.players.size() > 1:
			var editing: bool = int(peer_id) == live_target
			var edit_button := Button.new()
			edit_button.text = "✎" if int(peer_id) != my_id else L.t("Ben")
			UiSkin.skin_button(edit_button)
			edit_button.focus_mode = Control.FOCUS_NONE
			edit_button.add_theme_font_size_override("font_size", 14)
			edit_button.custom_minimum_size = Vector2(40, 32)
			edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			edit_button.modulate = UiTheme.GOLD if editing else Color.WHITE
			edit_button.pressed.connect(_start_editing.bind(-1 if int(peer_id) == my_id else int(peer_id)))
			row.add_child(edit_button)
		var ready_label := UiTheme.mono_label("✔" if PartyManager.is_ready(peer_id) else "…", 18,
			UiTheme.GREEN if PartyManager.is_ready(peer_id) else UiTheme.TEXT_DIM, true)
		ready_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ready_label)
		_players_list.add_child(row)
	_ready_count.text = L.t("Hazır: %d / %d") % [ready_count, maxi(1, MultiplayerManager.players.size())]

# --- Adımlar -----------------------------------------------------------------------

func _show_step(index: int) -> void:
	_step = clampi(index, 0, STEP_COUNT - 1)
	_visited[_step] = true
	for i in _pages.size():
		(_pages[i] as Control).visible = i == _step
	_step_title.text = "%d · %s" % [_step + 1, L.t(STEP_TITLES[_step])]
	_step_hint.text = L.t(STEP_HINTS[_step])
	if _step == 2:
		_fit_map.call_deferred()
	_refresh()

## Adım tamam mı? (Seçmen adımı her zaman geçerli bir çiftle gelir: görülünce tamam.)
func _step_done(index: int) -> bool:
	match index:
		0: return _first_name != "" and _surname != ""
		1: return _background_id != "" and _trait_id != ""
		2: return _hometown != ""
		3: return PartyManager.is_valid_name(_party_name)
		4: return VoterGroups.is_valid_core(_core) and (_visited.has(4) or _editing_bot())
	return false

func _missing_steps() -> Array:
	var missing: Array = []
	for i in STEP_COUNT:
		if not _step_done(i):
			missing.append(L.t(STEP_TITLES[i]))
	return missing

func _refresh() -> void:
	for i in _step_buttons.size():
		var b: Button = _step_buttons[i]
		var done := _step_done(i)
		b.text = "%d · %s%s" % [i + 1, L.t(STEP_TITLES[i]), "  ✓" if done else ""]
		var color := UiTheme.GOLD if i == _step else (UiTheme.GREEN_DARK if done else UiTheme.PANEL)
		UiSkin.skin_color_button(b, color)
		var font_color := UiTheme.TEXT_ON_GOLD if i == _step else UiTheme.TEXT
		for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(prop, font_color)
	_style_gender_buttons()
	_lang_button.text = PoliticianPresets.name_lang_title(_name_lang)
	_bot_random_button.visible = _editing_bot()
	_mark_cards(_profession_cards, _background_id)
	_mark_cards(_trait_cards, _trait_id)
	_refresh_detail()
	_paint_map()
	_refresh_home_info()
	_refresh_identity()
	_build_core_buttons()
	_refresh_card()
	_refresh_players()
	_refresh_nav()

func _refresh_nav() -> void:
	_blocker.visible = _is_locked and not _editing_bot()
	_back_button.disabled = _step == 0
	var last := _step == STEP_COUNT - 1
	var missing := _missing_steps()
	if _editing_bot():
		_next_button.text = L.t("İleri →") if not last else L.t("Kendi partine dön")
		_next_button.disabled = false
		_status.text = L.t("Bot düzenleniyor: değişiklikler anında kaydedilir.")
		_status.add_theme_color_override("font_color", UiTheme.GOLD)
		return
	if _is_locked:
		_next_button.text = L.t("✕ İptal Et")
		_next_button.disabled = false
		_status.text = L.t("Herkesin hazır olması bekleniyor…")
		_status.add_theme_color_override("font_color", UiTheme.GREEN)
	elif last:
		_next_button.text = L.t("🔒 Hazırım")
		_next_button.disabled = not missing.is_empty()
		_status.text = L.t("Eksik: %s") % ", ".join(missing) if not missing.is_empty() else L.t("Her şey tamam. Hazır olduğunda bas.")
		_status.add_theme_color_override("font_color", UiTheme.TEXT_MUTED if missing.is_empty() else UiTheme.RED)
	else:
		_next_button.text = L.t("İleri →")
		_next_button.disabled = false
		_status.text = L.t("Eksik: %s") % ", ".join(missing) if not missing.is_empty() else ""
		_status.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)

func _on_next_pressed() -> void:
	var last := _step == STEP_COUNT - 1
	if _editing_bot():
		if last:
			_start_editing(-1)
		else:
			_show_step(_step + 1)
		return
	if _is_locked or last:
		_on_ready_pressed()
	else:
		_show_step(_step + 1)

## Hazır / iptal: siyasetçi ve parti hazır bayrağıyla birlikte gider (tek
## RPC: host "hazır"ı partinin son hâlinden önce görmesin).
func _on_ready_pressed() -> void:
	if _editing_bot():
		return
	if not _is_locked and not _missing_steps().is_empty():
		return
	_is_locked = not _is_locked
	if _is_locked:
		PartyManager.set_my_politician(_draft_politician())
		PartyManager.set_party_and_ready(_party_name, _icon_index, ICON_COLOR, _bg_color, _core, true)
	else:
		PartyManager.set_ready(false)
	_refresh()

# --- Etkileşim: siyasetçi ------------------------------------------------------------

func _on_gender_pressed(gender: String) -> void:
	if gender == _gender:
		return
	_gender = gender
	_reroll_name(true, false)

## Klasik düğme dokusu, cinsiyet renginde: seçili tam renk, diğeri koyu ve sönük.
func _style_gender_buttons() -> void:
	for g in _gender_buttons.keys():
		var gb: Button = _gender_buttons[g]
		var color: Color = GENDER_STYLE[g]["color"]
		var selected: bool = g == _gender
		UiSkin.skin_color_button(gb, color if selected else color.darkened(0.55))
		for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			gb.add_theme_color_override(prop, UiTheme.TEXT if selected else UiTheme.TEXT_MUTED)

func _on_name_lang_pressed() -> void:
	_name_lang = PoliticianPresets.next_name_lang(_name_lang)
	_reroll_name(true, true)

func _reroll_name(first: bool, last: bool) -> void:
	if first:
		_first_name = PoliticianPresets.random_first_name(_gender, _first_name, null, _name_lang)
	if last:
		var avoid := PoliticianPresets.used_surnames(_edit_target if _editing_bot() else multiplayer.get_unique_id())
		if _surname != "":
			avoid.append(_surname)  # her basışta farklı bir soyad
		_surname = PoliticianPresets.random_surname(avoid, null, _name_lang)
	_first_edit.text = _first_name
	_surname_edit.text = _surname
	_politician_changed()

func _on_name_typed(text: String, edit: LineEdit) -> void:
	var fixed := PoliticianPresets.normalize_name(text)
	if fixed != text:
		var caret := edit.caret_column
		edit.text = fixed
		edit.caret_column = mini(caret, fixed.length())
	if edit == _first_edit:
		_first_name = fixed.strip_edges()
	else:
		_surname = fixed.strip_edges()
	_politician_changed()

func _on_background_pressed(id: String) -> void:
	_background_id = id
	_politician_changed()

func _on_trait_pressed(id: String) -> void:
	_trait_id = id
	_politician_changed()

func _on_province_clicked(province_id: String) -> void:
	if _is_locked and not _editing_bot():
		return
	_hometown = province_id
	_politician_changed()

func _on_province_hovered(province_id: String) -> void:
	_hovered_province = province_id
	_refresh_home_info()

## Bot düzenlenirken siyasetçi anında gider; kendi siyasetçim hazır olunca
## (ya da tamamlanınca, oda listesinde görünsün diye) gönderilir.
func _politician_changed() -> void:
	var data := _draft_politician()
	if PoliticianPresets.is_valid(data) and _hometown != "":
		if _editing_bot():
			PartyManager.set_bot_politician(_edit_target, data)
		else:
			PartyManager.set_my_politician(data)
	_refresh()

func _on_bot_random_pressed() -> void:
	if not _editing_bot():
		return
	PartyManager.randomize_bot_politician(_edit_target)
	var fresh := VoterGroups.random_core()
	for i in 10:
		if _core.size() != 2 or not (fresh.has(_core[0]) and fresh.has(_core[1])):
			break
		fresh = VoterGroups.random_core()
	_core = fresh
	_push_party()
	_load_from_bot(_edit_target)
	_load_fields()
	_refresh()

func _mark_cards(cards: Dictionary, selected: String) -> void:
	for id in cards.keys():
		var card: Button = cards[id]
		card.button_pressed = id == selected
		card.modulate = Color.WHITE if (selected == "" or id == selected) else Color(1, 1, 1, 0.7)
		var frame := card.get_node_or_null("SelectedFrame")
		if frame != null:
			frame.visible = id == selected

func _paint_map() -> void:
	_map.clear_overlay()
	if _hometown != "":
		_map.set_province_colors({_hometown: HOME_COLOR})

func _refresh_home_info() -> void:
	var id := _hovered_province if _hovered_province != "" else _hometown
	if id == "":
		_home_title.text = L.t("Bir il seç")
		_home_body.text = L.t("Haritada bir ile tıkla: orası senin memleketin olur.")
		return
	_home_title.text = GameMap.name_of(id) + (L.t("  ★ memleket") if id == _hometown else "")
	_home_body.text = L.t("Memleketinde güçlü bir teşkilatla başlarsın; hemşehrilerin sana sahip çıkar.") \
		if id == _hometown else L.t("Seçmek için tıkla.")

# --- Etkileşim: parti ----------------------------------------------------------------

func _refresh_identity() -> void:
	_preview_bg.color = _bg_color
	_preview_icon.texture = PartyPresets.get_icon_texture(_icon_index, PREVIEW_ICON_PIXEL_SIZE)
	_preview_icon.modulate = ICON_COLOR
	var valid := PartyManager.is_valid_name(_party_name)
	_name_hint.text = L.t("%d-%d karakter") % [PartyManager.NAME_MIN_LENGTH, PartyManager.NAME_MAX_LENGTH]
	_name_hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED if valid else UiTheme.RED)
	for i in _icon_grid.get_child_count():
		var btn: TextureButton = _icon_grid.get_child(i)
		btn.self_modulate = UiTheme.GOLD if i == _icon_index else Color.WHITE
	_build_color_row()

func _on_party_name_changed(text: String) -> void:
	_party_name = text
	_push_party()
	_refresh()

func _on_icon_selected(index: int) -> void:
	_icon_index = index
	_push_party()
	_refresh()

func _on_color_selected(index: int) -> void:
	_bg_color = PartyPresets.COLORS[index]
	_push_party()
	_refresh()

func _on_core_pressed(group: String) -> void:
	if _core.has(group):
		return  # her zaman 2 grup seçili kalır: başka birine basarak değiştir
	var other := VoterGroups.opposite(group)
	if _core.has(other):
		_core[_core.find(other)] = group
	else:
		_core.append(group)
		while _core.size() > VoterGroups.CORE_COUNT:
			_core.pop_front()
	_push_party()
	_refresh()

func _push_party() -> void:
	if not PartyManager.is_valid_name(_party_name):
		if not _editing_bot():
			PartyManager.set_my_color(_bg_color)
		return
	if _editing_bot():
		PartyManager.set_bot_party(_edit_target, _party_name, _icon_index, _bg_color, _core)
		return
	PartyManager.set_my_party(_party_name, _icon_index, ICON_COLOR, _bg_color, _core)

## Parti verisi değişti: seçtiğim renk başka bir oyuncuya geçtiyse (aynı anda
## seçildi, host ilkini kabul etti) boş bir renge geçerim; düzenlenen botun
## gerçek (host'un kabul ettiği) hâli gösterilir.
func _on_parties_updated() -> void:
	if _editing_bot():
		var party: Dictionary = PartyManager.parties.get(_edit_target, {})
		if not party.is_empty():
			_bg_color = party.get("bg_color", _bg_color)
		if not _first_edit.has_focus() and not _surname_edit.has_focus():
			var data: Dictionary = PartyManager.politicians.get(_edit_target, {})
			if not data.is_empty():
				_politician_from(data)
				_load_fields()
	elif _is_taken(_bg_color):
		_bg_color = _first_free_color(_bg_color)
		if not _is_locked:
			_push_party()
	_refresh()

# --- Bot düzenleme -------------------------------------------------------------------

func _own_snapshot() -> Dictionary:
	return {"gender": _gender, "first_name": _first_name, "surname": _surname, "lang": _name_lang,
		"background": _background_id, "trait": _trait_id, "hometown": _hometown, "portrait": _portrait,
		"party": _party_name, "icon": _icon_index, "color": _bg_color, "core": _core.duplicate(),
		"step": _step, "visited": _visited.duplicate()}

## Oda sahibi: bir botu düzenlemeye başla ya da kendine dön (bot_id = -1).
func _start_editing(bot_id: int) -> void:
	var me := multiplayer.get_unique_id()
	if bot_id != -1 and (not MultiplayerManager.is_local_owner() or not MultiplayerManager.is_bot(bot_id)):
		return
	if not _editing_bot():
		_own_backup = _own_snapshot()
	if bot_id == -1 or bot_id == me:
		_edit_target = -1
		var b := _own_backup
		_politician_from(b)
		_name_lang = String(b.get("lang", _name_lang))
		_party_name = String(b.get("party", ""))
		_icon_index = int(b.get("icon", 0))
		_bg_color = b.get("color", _bg_color)
		_core = (b.get("core", _core) as Array).duplicate()
		_visited = b.get("visited", {0: true})
		_step = int(b.get("step", 0))
		_title.text = L.t("YENİ BİR PARTİ")
	else:
		_edit_target = bot_id
		_load_from_bot(bot_id)
		_title.text = L.t("BOT PARTİSİ: %s") % String(MultiplayerManager.players.get(bot_id, {}).get("name", L.t("Bot")))
		_step = 0
	_load_fields()
	_show_step(_step)

func _load_from_bot(bot_id: int) -> void:
	_politician_from(PartyManager.politicians.get(bot_id, {}))
	var party: Dictionary = PartyManager.parties.get(bot_id, {})
	_party_name = String(party.get("name", ""))
	_icon_index = PartyPresets.clamp_icon_index(int(party.get("icon_index", 0)))
	_bg_color = party.get("bg_color", _bg_color)
	var bot_core: Array = party.get("core", [])
	_core = bot_core.duplicate() if VoterGroups.is_valid_core(bot_core) else VoterGroups.random_core()

## Taslağı metin alanlarına yazar (yazılırken çağrılmaz: imleç kaçmasın).
func _load_fields() -> void:
	_first_edit.text = _first_name
	_surname_edit.text = _surname
	if _name_edit.text != _party_name:
		_name_edit.text = _party_name

func _on_party_setup_finished() -> void:
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")
