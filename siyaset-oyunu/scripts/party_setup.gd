extends Control
## Parti Kurulum ekranı — HER OYUNCUYA ÖZEL, tam ekran, harita YOK. Solda
## partinin kocaman bir önizlemesi, sağda ayar paneli (isim, ikon, arka plan
## rengi). İkon rengi seçilmez, her zaman beyazdır.
##
## İDEOLOJİ SEÇİLMEZ: her parti nötr başlar, görüşü oyunda sunduğu yasalarla
## oluşur (bkz. IdeologyAxes). Sahnedeki ideoloji düğümleri gizlenir.
##
## Süre sınırsızdır (eski süre ayarı kaldırıldı); herkes hazır olunca
## HOST otomatik olarak herkesi Oyun Ekranı'na geçirir. Bir oyuncu
## "Kilitle ve Hazır Ver"e basarsa seçimleri kilitlenir ve hazır olarak
## işaretlenir; HERKES hazır olursa süre dolmamış olsa bile oyun hemen
## başlar. İptal ederse tekrar düzenleyebilir.
##
## Görsel yerleşim (panel/konteynerler) sahnede editörle düzenlenebilir;
## ikon/renk butonları ile eksen satırları, veri kataloğuna bağlı olduğundan
## çalışma zamanında üretilir.

const SWATCH_SIZE := 24.0
const ICON_BUTTON_SIZE := 30.0
const GRID_ICON_PIXEL_SIZE := 60       # ızgaradaki küçük ikonlar için raster boyutu
const PREVIEW_ICON_PIXEL_SIZE := 480   # kocaman önizleme için raster boyutu
## Parti ikonları her zaman beyaz. Beyaz arka plan bu yüzden seçilemez
## (ikon görünmez olurdu).
const ICON_COLOR := Color.WHITE
## Soldaki oyuncu listesi paneli (herkesin adı ve kurduğu parti, anlık).
const PLAYERS_PANEL_WIDTH := 270.0

# Eksen başına görünen başlık + uç etiketleri (- ve + yönü).
const AXIS_LABELS := {
	"economic": {"title": "Ekonomi", "neg": "Devletçi", "pos": "Piyasacı"},
	"social": {"title": "Toplum", "neg": "İlerici", "pos": "Muhafazakâr"},
	"administrative": {"title": "İdare", "neg": "Federal / Çoğulcu", "pos": "Üniter / Milliyetçi"},
}

@onready var countdown_label: Label = %CountdownLabel
@onready var ready_count_label: Label = %ReadyCountLabel
@onready var preview_bg: ColorRect = %PreviewBg
@onready var preview_icon: TextureRect = %PreviewIcon
@onready var name_edit: LineEdit = %NameEdit
@onready var name_hint_label: Label = %NameHintLabel
@onready var icon_grid: GridContainer = %IconGrid
var _icon_tabs: HBoxContainer
var _icon_category: int = PartyPresets.CATEGORY_FICTIONAL
@onready var bg_color_row: HFlowContainer = %BgColorRow
@onready var ideology_container: VBoxContainer = %IdeologyContainer
@onready var random_button: Button = %RandomButton
@onready var ready_button: Button = %ReadyButton

var _party_name: String = ""
var _selected_icon_index: int = 0
var _selected_bg_color: Color = PartyPresets.COLORS[0]     # kırmızı
var _ideology: Dictionary = {}
var _ideology_sliders: Dictionary = {}   # axis -> HSlider
var _ideology_value_labels: Dictionary = {}  # axis -> Label

var _time_left: float = 60.0
var _unlimited_time: bool = false
var _is_locked: bool = false
var _players_list: VBoxContainer
## Sağ paneldeki kontrollerin düzenlediği parti: kendi partim ya da (oda
## sahibiysem) bir bot. Bot düzenlenirken kendi seçimlerim burada saklanır.
var _edit_target: int = -1
var _own_backup: Dictionary = {}
@onready var title_label: Label = $TopBar/TitleLabel

func _ready() -> void:
	# Parti kurma süresi her zaman sınırsız (lobi ayarı kaldırıldı).
	_unlimited_time = true
	_time_left = 0.0
	_party_name = "Parti%d" % randi_range(1, 99)
	_ideology = IdeologyAxes.default_values()

	name_edit.text = _party_name
	name_edit.max_length = PartyManager.NAME_MAX_LENGTH
	name_edit.text_changed.connect(_on_name_changed)

	_selected_bg_color = _first_free_color(_selected_bg_color)
	_build_players_panel()
	_build_icon_grid()
	_build_color_row()
	# İdeoloji seçimi yok: sahnedeki başlık, kaydırıcı kutusu ve ayırıcı gizlenir.
	ideology_container.hide()
	for node_name in ["IdeologyLabel", "HSeparator3b"]:
		var node := ideology_container.get_parent().get_node_or_null(node_name)
		if node != null:
			node.hide()
	random_button.pressed.connect(_on_random_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	MultiplayerManager.party_setup_finished.connect(_on_party_setup_finished)
	PartyManager.parties_updated.connect(_refresh_ready_count)
	PartyManager.parties_updated.connect(_on_parties_updated)

	_update_preview()
	_update_name_hint()
	_push_party()
	_update_countdown_label()
	_refresh_ready_count()

func _process(delta: float) -> void:
	if _unlimited_time:
		return
	_time_left = max(0.0, _time_left - delta)
	_update_countdown_label()
	if MultiplayerManager.is_host and _time_left <= 0.0:
		set_process(false)
		MultiplayerManager.finish_party_setup()

func _update_countdown_label() -> void:
	if _unlimited_time:
		countdown_label.visible = false
		return
	countdown_label.visible = true
	var seconds := int(ceil(_time_left))
	countdown_label.text = "Süre: %02d:%02d" % [seconds / 60, seconds % 60]

func _refresh_ready_count() -> void:
	var total := MultiplayerManager.players.size()
	var ready_count := 0
	for peer_id in MultiplayerManager.players.keys():
		if PartyManager.is_ready(peer_id):
			ready_count += 1
	ready_count_label.text = "Hazır: %d / %d" % [ready_count, total]

func _on_name_changed(new_text: String) -> void:
	_party_name = new_text
	_update_name_hint()
	if PartyManager.is_valid_name(_party_name):
		_push_party()

func _update_name_hint() -> void:
	var valid := PartyManager.is_valid_name(_party_name)
	name_hint_label.text = "%d-%d karakter" % [PartyManager.NAME_MIN_LENGTH, PartyManager.NAME_MAX_LENGTH]
	name_hint_label.modulate = UiTheme.TEXT_MUTED if valid else UiTheme.RED

## İkon kategorisi sekmeleri (Kurgusal / Türkiye) ızgaranın üstünde.
func _build_icon_tabs() -> void:
	_icon_tabs = HBoxContainer.new()
	_icon_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_icon_tabs.add_theme_constant_override("separation", 6)
	var parent := icon_grid.get_parent()
	parent.add_child(_icon_tabs)
	parent.move_child(_icon_tabs, icon_grid.get_index())
	for category in PartyPresets.CATEGORY_TITLES.size():
		var tab := Button.new()
		tab.text = PartyPresets.CATEGORY_TITLES[category]
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(110, 30)
		tab.pressed.connect(_on_icon_tab_pressed.bind(category))
		_icon_tabs.add_child(tab)

func _on_icon_tab_pressed(category: int) -> void:
	_icon_category = category
	_refresh_icon_grid_selection()

func _build_icon_grid() -> void:
	_icon_category = PartyPresets.icon_category(_selected_icon_index)
	_build_icon_tabs()
	for i in PartyPresets.icon_count():
		var btn := TextureButton.new()
		btn.texture_normal = PartyPresets.get_icon_texture(i, GRID_ICON_PIXEL_SIZE)
		# ÖNEMLİ: ignore_texture_size olmadan TextureButton kendini dokunun
		# GERÇEK piksel boyutuna göre büyütür (custom_minimum_size'ı yok sayar)
		# — bu yüzden ızgara panelin dışına taşıyordu. Bunu kapatınca doku,
		# aşağıdaki sabit kutunun içine (küçülterek) sığdırılıyor.
		btn.ignore_texture_size = true
		btn.custom_minimum_size = Vector2(ICON_BUTTON_SIZE, ICON_BUTTON_SIZE)
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.modulate = Color.WHITE
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		btn.pressed.connect(_on_icon_selected.bind(i))
		icon_grid.add_child(btn)
	_refresh_icon_grid_selection()

func _refresh_icon_grid_selection() -> void:
	for i in icon_grid.get_child_count():
		var btn: TextureButton = icon_grid.get_child(i)
		btn.self_modulate = UiTheme.GOLD if i == _selected_icon_index else Color.WHITE
		btn.visible = PartyPresets.icon_category(i) == _icon_category
	if _icon_tabs != null:
		for category in _icon_tabs.get_child_count():
			var tab := _icon_tabs.get_child(category) as Button
			tab.button_pressed = category == _icon_category
			tab.modulate = Color.WHITE if category == _icon_category else Color(0.7, 0.7, 0.7, 1.0)

## Renk başka bir OYUNCUDA mı? (Botun rengi alınabilir, bot başka renge geçer.)
func _is_taken_by_player(color: Color) -> bool:
	if _editing_bot():
		# Bot, başka hiçbir partinin rengini alamaz.
		return PartyManager.color_owner(color, _edit_target) != -1
	var owner := PartyManager.color_owner(color, multiplayer.get_unique_id())
	return owner != -1 and not MultiplayerManager.is_bot(owner)

func _editing_bot() -> bool:
	return _edit_target != -1 and _edit_target != multiplayer.get_unique_id()

func _first_free_color(preferred: Color) -> Color:
	if _is_allowed_bg_color(preferred) and not _is_taken_by_player(preferred):
		return preferred
	for color in PartyPresets.COLORS:
		if _is_allowed_bg_color(color) and not _is_taken_by_player(color):
			return color
	return preferred

## Parti verisi değişti: renkler güncellenir. Seçtiğim renk bu arada başka bir
## oyuncuya geçtiyse (aynı anda seçildi, host ilkini kabul etti) boş bir renge geçerim.
func _on_parties_updated() -> void:
	_refresh_players_panel()
	if _editing_bot():
		# Düzenlenen botun gerçek (host'un kabul ettiği) hâli gösterilir.
		var party: Dictionary = PartyManager.parties.get(_edit_target, {})
		if not party.is_empty() and not Color(party.get("bg_color")).is_equal_approx(_selected_bg_color):
			_selected_bg_color = party["bg_color"]
			_update_preview()
		_build_color_row()
		return
	if _is_taken_by_player(_selected_bg_color):
		_selected_bg_color = _first_free_color(_selected_bg_color)
		_update_preview()
		if not _is_locked:
			_push_party()
	_build_color_row()

# --- Soldaki oyuncu paneli ---------------------------------------------------

func _build_players_panel() -> void:
	var left_preview := get_node_or_null("LeftPreview") as Control
	if left_preview != null:
		left_preview.offset_left = PLAYERS_PANEL_WIDTH
		preview_bg.custom_minimum_size = Vector2(280, 280)
		preview_bg.offset_left = -140
		preview_bg.offset_top = -140
		preview_bg.offset_right = 140
		preview_bg.offset_bottom = 140
		preview_icon.offset_left = -95
		preview_icon.offset_top = -95
		preview_icon.offset_right = 95
		preview_icon.offset_bottom = 95
	var panel := PanelContainer.new()
	panel.name = "PlayersPanel"
	panel.anchor_bottom = 1.0
	panel.offset_left = 12
	panel.offset_top = 86
	panel.offset_right = PLAYERS_PANEL_WIDTH - 6
	panel.offset_bottom = -12
	var style := UiSkin.stylebox(UiSkin.PANEL_DARK)
	style.set_content_margin_all(UiTheme.PAD_M)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "OYUNCULAR"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(UiTheme.rule())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_players_list = VBoxContainer.new()
	_players_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_players_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_players_list)
	_refresh_players_panel()

func _refresh_players_panel() -> void:
	if _players_list == null:
		return
	for child in _players_list.get_children():
		child.queue_free()
	var my_id := multiplayer.get_unique_id()
	var order: Array = MultiplayerManager.lobby_order() if not MultiplayerManager.players.is_empty() else [my_id]
	for peer_id in order:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.color = Color(party.get("bg_color", Color(0.3, 0.3, 0.3)))
		if party.has("icon_index"):
			var icon := TextureRect.new()
			icon.texture = PartyPresets.get_icon_texture(int(party["icon_index"]), GRID_ICON_PIXEL_SIZE)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 5
			icon.offset_top = 5
			icon.offset_right = -5
			icon.offset_bottom = -5
			swatch.add_child(icon)
		row.add_child(swatch)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		var player_label := Label.new()
		var player_name := String(MultiplayerManager.players.get(peer_id, {}).get("name", "Sen"))
		player_label.text = player_name + (" (sen)" if int(peer_id) == my_id else "") + ("  🤖" if MultiplayerManager.is_bot(peer_id) else "")
		player_label.add_theme_font_size_override("font_size", 13)
		player_label.modulate = UiTheme.TEXT_MUTED
		player_label.clip_text = true
		texts.add_child(player_label)
		var party_label := Label.new()
		party_label.text = String(party.get("name", "parti kuruyor…"))
		party_label.add_theme_font_size_override("font_size", 17)
		party_label.clip_text = true
		texts.add_child(party_label)
		row.add_child(texts)
		# Oda sahibi botların partisini düzenleyebilir; düzenlenen satır vurgulu.
		if MultiplayerManager.is_local_owner() and (MultiplayerManager.is_bot(peer_id) or int(peer_id) == my_id) \
				and MultiplayerManager.players.size() > 0:
			var editing: bool = (int(peer_id) == _edit_target) or (int(peer_id) == my_id and not _editing_bot())
			var edit_button := Button.new()
			edit_button.text = "✎" if int(peer_id) != my_id else "Ben"
			edit_button.tooltip_text = "Bu botun adını, logosunu ve rengini düzenle" if int(peer_id) != my_id else "Kendi partine dön"
			edit_button.custom_minimum_size = Vector2(34, 30)
			edit_button.modulate = UiTheme.GOLD if editing else Color.WHITE
			edit_button.pressed.connect(_start_editing.bind(-1 if int(peer_id) == my_id else int(peer_id)))
			row.add_child(edit_button)
		var ready_label := Label.new()
		ready_label.text = "✔" if PartyManager.is_ready(peer_id) else "…"
		ready_label.modulate = UiTheme.GREEN if PartyManager.is_ready(peer_id) else UiTheme.TEXT_DIM
		ready_label.add_theme_font_size_override("font_size", 18)
		row.add_child(ready_label)
		_players_list.add_child(row)

## Arka plan rengi seçilebilir mi? İkonla aynı renk (beyaz) olamaz.
static func _is_allowed_bg_color(color: Color) -> bool:
	return not color.is_equal_approx(ICON_COLOR)

func _build_color_row() -> void:
	for child in bg_color_row.get_children():
		child.queue_free()
	for i in PartyPresets.COLORS.size():
		var color: Color = PartyPresets.COLORS[i]
		var taken := _is_taken_by_player(color)
		var allowed := _is_allowed_bg_color(color) and not taken
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		btn.disabled = not allowed or (_is_locked and not _editing_bot())
		btn.modulate = Color.WHITE if allowed else Color(0.55, 0.55, 0.55, 1.0)
		if taken:
			btn.text = "✕"
			btn.tooltip_text = "Bu renk başka bir oyuncuda"
		# Seçili renk altın çerçeveyle ayrılır (pixel tarz: kare, kalın kenar).
		var selected := color.is_equal_approx(_selected_bg_color)
		var style := UiSkin.color_box(color, UiSkin.BUTTON_TINT_HOVER if selected else UiSkin.BUTTON_TINT_NORMAL)
		for state in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(state, style)
		if selected:
			var ring := UiSkin.color_surface(UiTheme.GOLD, UiSkin.TARGET)
			ring.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.add_child(ring)
		if allowed:
			btn.pressed.connect(_on_bg_color_selected.bind(i))
		bg_color_row.add_child(btn)

func _on_icon_selected(index: int) -> void:
	_selected_icon_index = index
	_refresh_icon_grid_selection()
	_update_preview()
	_push_party()

func _on_bg_color_selected(index: int) -> void:
	_selected_bg_color = PartyPresets.COLORS[index]
	_build_color_row()
	_update_preview()
	_push_party()

## Her eksen için: başlık + (sol uç etiketi - kaydırıcı - sağ uç etiketi) +
## anlık değer. Kaydırıcı 0-3 İNDEKS tutar; gerçek değer her zaman
## IdeologyAxes.ALLOWED_START_VALUES[indeks] üzerinden okunur, böylece uç/nötr
## seçimi arayüz seviyesinde imkansız kalır.
func _build_ideology_rows() -> void:
	for axis in IdeologyAxes.AXES:
		var info: Dictionary = AXIS_LABELS.get(axis, {"title": axis, "neg": "-", "pos": "+"})

		var title := Label.new()
		title.text = info["title"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ideology_container.add_child(title)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var neg_label := Label.new()
		neg_label.text = info["neg"]
		neg_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(neg_label)

		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = IdeologyAxes.ALLOWED_START_VALUES.size() - 1
		slider.step = 1
		slider.tick_count = IdeologyAxes.ALLOWED_START_VALUES.size()
		slider.ticks_on_borders = true
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		var start_value: int = _ideology.get(axis, IdeologyAxes.ALLOWED_START_VALUES[0])
		slider.value = IdeologyAxes.ALLOWED_START_VALUES.find(start_value)
		slider.value_changed.connect(_on_ideology_slider_changed.bind(axis))
		row.add_child(slider)

		var pos_label := Label.new()
		pos_label.text = info["pos"]
		pos_label.custom_minimum_size = Vector2(90, 0)
		pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pos_label)

		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.text = "%+d" % start_value
		row.add_child(value_label)

		ideology_container.add_child(row)

		_ideology_sliders[axis] = slider
		_ideology_value_labels[axis] = value_label

func _on_ideology_slider_changed(index: float, axis: String) -> void:
	var value: int = IdeologyAxes.ALLOWED_START_VALUES[int(index)]
	_ideology[axis] = value
	_ideology_value_labels[axis].text = "%+d" % value
	_push_party()

## Sadece ikon ve arka plan rengini rastgeleler — İDEOLOJİYE DOKUNMAZ. İdeoloji
## daha stratejik bir seçim olduğu için kazara "rastgele" ile karışmasın diye
## kasıtlı olarak buraya dahil edilmedi.
func _on_random_pressed() -> void:
	_selected_icon_index = PartyPresets.random_icon_index()
	var free: Array = []
	for color in PartyPresets.COLORS:
		if _is_allowed_bg_color(color) and not _is_taken_by_player(color):
			free.append(color)
	if not free.is_empty():
		_selected_bg_color = free[randi_range(0, free.size() - 1)]
	_refresh_icon_grid_selection()
	_build_color_row()
	_update_preview()
	_push_party()

func _update_preview() -> void:
	preview_bg.color = _selected_bg_color
	preview_icon.texture = PartyPresets.get_icon_texture(_selected_icon_index, PREVIEW_ICON_PIXEL_SIZE)
	preview_icon.modulate = ICON_COLOR
	preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _push_party() -> void:
	if not PartyManager.is_valid_name(_party_name):
		return
	if _editing_bot():
		PartyManager.set_bot_party(_edit_target, _party_name, _selected_icon_index, _selected_bg_color)
		return
	PartyManager.set_my_party(_party_name, _selected_icon_index, ICON_COLOR, _selected_bg_color, _ideology)

## Oda sahibi: bir botun partisini düzenlemeye başla ya da kendi partine dön
## (bot_id = -1). Kendi seçimlerin saklanır, geri dönünce yerine konur.
func _start_editing(bot_id: int) -> void:
	var me := multiplayer.get_unique_id()
	if bot_id != -1 and (not MultiplayerManager.is_local_owner() or not MultiplayerManager.is_bot(bot_id)):
		return
	if not _editing_bot():
		_own_backup = {"name": _party_name, "icon": _selected_icon_index, "color": _selected_bg_color}
	if bot_id == -1 or bot_id == me:
		_edit_target = -1
		_party_name = String(_own_backup.get("name", _party_name))
		_selected_icon_index = int(_own_backup.get("icon", _selected_icon_index))
		_selected_bg_color = _own_backup.get("color", _selected_bg_color)
		title_label.text = "PARTİNİ KUR"
		_set_controls_disabled(_is_locked)
		ready_button.disabled = false
	else:
		_edit_target = bot_id
		var party: Dictionary = PartyManager.parties.get(bot_id, {})
		_party_name = String(party.get("name", ""))
		_selected_icon_index = int(party.get("icon_index", 0))
		_selected_bg_color = party.get("bg_color", _selected_bg_color)
		title_label.text = "BOT PARTİSİ: %s" % MultiplayerManager.players.get(bot_id, {}).get("name", "Bot")
		_set_controls_disabled(false)
		ready_button.disabled = true  # hazır butonu sadece kendi partin için
	name_edit.text = _party_name
	_update_name_hint()
	_icon_category = PartyPresets.icon_category(_selected_icon_index)
	_refresh_icon_grid_selection()
	_build_color_row()
	_update_preview()
	_refresh_players_panel()

## "Kilitle ve Hazır Ver" / iptal: kilitliyken tüm seçim kontrolleri
## devre dışı kalır (yanlışlıkla değiştirilemesin diye), tekrar basınca açılır.
## Kilitlerken parti verisi + hazır bayrağı TEK bir atomik çağrıyla
## (set_party_and_ready) birlikte gönderiliyor — hızlıca art arda
## seç+kilitle yapılırsa host'un "hazır"ı partinin SON hâli ulaşmadan
## uygulayıp oyunu erken/varsayılan veriyle başlatma riski bu şekilde
## tamamen ortadan kalkıyor (bkz. PartyManager.set_party_and_ready).
func _on_ready_pressed() -> void:
	if _editing_bot():
		return
	_is_locked = not _is_locked
	_set_controls_disabled(_is_locked)
	ready_button.text = "✕ İptal Et" if _is_locked else "🔒 Kilitle ve Hazır Ver"
	if _is_locked:
		if PartyManager.is_valid_name(_party_name):
			PartyManager.set_party_and_ready(_party_name, _selected_icon_index, ICON_COLOR, _selected_bg_color, _ideology, true)
	else:
		PartyManager.set_ready(false)

func _set_controls_disabled(disabled: bool) -> void:
	name_edit.editable = not disabled
	random_button.disabled = disabled
	for btn in icon_grid.get_children():
		btn.disabled = disabled
	_build_color_row()
	for axis in _ideology_sliders.keys():
		_ideology_sliders[axis].editable = not disabled

func _on_party_setup_finished() -> void:
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")
