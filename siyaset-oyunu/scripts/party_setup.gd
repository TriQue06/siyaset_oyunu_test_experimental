extends Control
## Parti Kurulum ekranı — HER OYUNCUYA ÖZEL, tam ekran, harita YOK. Solda
## partinin kocaman bir önizlemesi, sağda ayar paneli (isim, ikon, arka plan
## rengi). İkon rengi seçilmez, her zaman beyazdır.
##
## ÇEKİRDEK SEÇMEN GRUPLARI: parti 8 seçmen grubundan 2'sini (aynı çiftten
## olmayan) çekirdek seçer; o gruplarda yüksek, karşıtlarında düşük, kalanlarda
## nötr destekle başlar (bkz. VoterGroups.start_affinities). Sahnedeki
## "CoreGroupContainer" düğümü bu seçim için kullanılır.
##
## Süre sınırsızdır (eski süre ayarı kaldırıldı); herkes hazır olunca
## HOST otomatik olarak herkesi Oyun Ekranı'na geçirir. Bir oyuncu
## "Kilitle ve Hazır Ver"e basarsa seçimleri kilitlenir ve hazır olarak
## işaretlenir; HERKES hazır olursa süre dolmamış olsa bile oyun hemen
## başlar. İptal ederse tekrar düzenleyebilir.
##
## Görsel yerleşim (panel/konteynerler) sahnede editörle düzenlenebilir;
## ikon/renk butonları ile seçmen grubu düğmeleri, veri kataloğuna bağlı olduğundan
## çalışma zamanında üretilir.

const SWATCH_SIZE := 24.0
const ICON_BUTTON_SIZE := 30.0
const GRID_ICON_PIXEL_SIZE := 60       # ızgaradaki küçük ikonlar için raster boyutu
const PREVIEW_ICON_PIXEL_SIZE := 480   # kocaman önizleme için raster boyutu
## Parti ikonları her zaman beyaz. Beyaz arka plan bu yüzden seçilemez
## (ikon görünmez olurdu).
const ICON_COLOR := Color.WHITE
## Soldaki oyuncu listesi paneli (herkesin adı ve kurduğu parti, anlık).
const PLAYERS_PANEL_WIDTH := 330.0
## Logo önizlemesi: kalan alana göre ölçeklenir, kenarlarda bu kadar boşluk kalır.
const PREVIEW_MARGIN := 32.0
const PREVIEW_MIN_SIDE := 160.0
const PREVIEW_MAX_SIDE := 420.0
## İkon, kare kenarının bu oranı kadar yer kaplar (0.68 = kenarda rahat pay).
const PREVIEW_ICON_RATIO := 0.68


@onready var countdown_label: Label = %CountdownLabel
@onready var ready_count_label: Label = %ReadyCountLabel
@onready var preview_bg: ColorRect = %PreviewBg
@onready var preview_icon: TextureRect = %PreviewIcon
@onready var name_edit: LineEdit = %NameEdit
@onready var name_hint_label: Label = %NameHintLabel
@onready var icon_grid: GridContainer = %IconGrid
@onready var bg_color_row: HFlowContainer = %BgColorRow
@onready var core_container: VBoxContainer = %CoreGroupContainer
@onready var ready_button: Button = %ReadyButton

var _party_name: String = ""
var _selected_icon_index: int = 0
var _selected_bg_color: Color = PartyPresets.COLORS[0]     # kırmızı
## Seçilen çekirdek gruplar (seçim sırasıyla; en fazla VoterGroups.CORE_COUNT).
var _core: Array = []
var _core_note: Label

var _time_left: float = 60.0
var _unlimited_time: bool = false
var _is_locked: bool = false
var _players_list: VBoxContainer
## Sağ paneldeki kontrollerin düzenlediği parti: kendi partim ya da (oda
## sahibiysem) bir bot. Bot düzenlenirken kendi seçimlerim burada saklanır.
var _edit_target: int = -1
## Bot düzenlenirken botun siyasetçisinin adı ve soyadı (0.0.193).
var _bot_name_row: HBoxContainer
var _bot_first_edit: LineEdit
var _bot_surname_edit: LineEdit
var _own_backup: Dictionary = {}
var _bot_profile_button: Button
@onready var title_label: Label = $TopBar/TitleLabel

func _ready() -> void:
	# Parti kurma süresi her zaman sınırsız (lobi ayarı kaldırıldı).
	_unlimited_time = true
	_time_left = 0.0
	# Parti adı BOŞ gelir; ad yazılmadan hazır verilemez.
	_party_name = ""
	_core = VoterGroups.random_core()

	name_edit.text = _party_name
	name_edit.placeholder_text = L.t("Parti adını yaz")
	name_edit.max_length = PartyManager.NAME_MAX_LENGTH
	name_edit.text_changed.connect(_on_name_changed)

	# Profile dönüp geri gelindiyse taslak parti yerinde kalır.
	var draft: Dictionary = PartyManager.parties.get(multiplayer.get_unique_id(), {})
	if PartyManager.is_valid_name(String(draft.get("name", ""))):
		_party_name = String(draft["name"])
		name_edit.text = _party_name
		_selected_icon_index = int(draft.get("icon_index", _selected_icon_index))
		if VoterGroups.is_valid_core(draft.get("core", [])):
			_core = (draft["core"] as Array).duplicate()
	if draft.has("bg_color"):
		_selected_bg_color = draft["bg_color"]
	_selected_bg_color = _first_free_color(_selected_bg_color)
	_build_back_to_profile_button()
	_build_players_panel()
	_build_icon_grid()
	_build_color_row()
	# Çekirdek seçmen grupları: 8 gruptan 2'si.
	var core_title := core_container.get_parent().get_node_or_null("CoreGroupLabel")
	if core_title is Label:
		core_title.text = L.t("Çekirdek seçmen grupları (2 seç)")
	_build_core_buttons()
	_build_bot_profile_button()
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
	countdown_label.text = L.t("Süre: %02d:%02d") % [seconds / 60, seconds % 60]

func _refresh_ready_count() -> void:
	var total := MultiplayerManager.players.size()
	var ready_count := 0
	for peer_id in MultiplayerManager.players.keys():
		if PartyManager.is_ready(peer_id):
			ready_count += 1
	ready_count_label.text = L.t("Hazır: %d / %d") % [ready_count, total]

func _on_name_changed(new_text: String) -> void:
	_party_name = new_text
	_update_name_hint()
	if PartyManager.is_valid_name(_party_name):
		_push_party()
	_refresh_players_panel()

func _update_name_hint() -> void:
	var valid := PartyManager.is_valid_name(_party_name)
	name_hint_label.text = L.t("%d-%d karakter") % [PartyManager.NAME_MIN_LENGTH, PartyManager.NAME_MAX_LENGTH]
	name_hint_label.modulate = UiTheme.TEXT_MUTED if valid else UiTheme.RED
	_refresh_ready_button()

## Hazır düğmesi: bot düzenlenirken ya da parti adı boş/geçersizken basılamaz
## (kilitliyken "İptal Et" her zaman basılabilir).
func _refresh_ready_button() -> void:
	ready_button.disabled = _editing_bot() or (not _is_locked and not PartyManager.is_valid_name(_party_name))
	if _bot_profile_button != null:
		_bot_profile_button.visible = _editing_bot()
	if _bot_name_row != null:
		_bot_name_row.visible = _editing_bot()

## Oda sahibi bot düzenlerken: botun siyasetçisini (cinsiyet, ad, soyad,
## geçmiş, memleket) rastgele yeniden üretir. Sınırsız basılabilir.
func _build_bot_profile_button() -> void:
	_bot_profile_button = Button.new()
	_bot_profile_button.text = L.t("🎲 Bot Profilini Rastgele Yap")
	_bot_profile_button.tooltip_text = L.t("Botun adını, soyadını, geçmişini, memleketini ve çekirdek seçmen gruplarını rastgele değiştir")
	_bot_profile_button.focus_mode = Control.FOCUS_NONE
	_bot_profile_button.custom_minimum_size = Vector2(0, 40)
	_bot_profile_button.visible = false
	_bot_profile_button.pressed.connect(func():
		if _editing_bot():
			PartyManager.randomize_bot_politician(_edit_target)
			_randomize_bot_core())
	ready_button.get_parent().add_child(_bot_profile_button)
	ready_button.get_parent().move_child(_bot_profile_button, ready_button.get_index())
	# Botun genel başkanının adı ve soyadı: Enter ya da alandan çıkınca kaydedilir.
	_bot_name_row = HBoxContainer.new()
	_bot_name_row.add_theme_constant_override("separation", 6)
	_bot_name_row.visible = false
	var leader := Label.new()
	leader.text = L.t("Genel başkan")
	leader.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_bot_name_row.add_child(leader)
	_bot_first_edit = _bot_name_edit(L.t("Ad"))
	_bot_surname_edit = _bot_name_edit(L.t("Soyad"))
	_bot_name_row.add_child(_bot_first_edit)
	_bot_name_row.add_child(_bot_surname_edit)
	# Parti adının hemen altında: bot düzenlenirken kaydırmadan görünsün.
	name_hint_label.get_parent().add_child(_bot_name_row)
	name_hint_label.get_parent().move_child(_bot_name_row, name_hint_label.get_index() + 1)

func _bot_name_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.max_length = PoliticianPresets.PART_MAX_LENGTH
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 36)
	edit.tooltip_text = L.t("Botun genel başkanının adı")
	edit.text_submitted.connect(func(_t): _push_bot_name())
	edit.focus_exited.connect(_push_bot_name)
	return edit

func _push_bot_name() -> void:
	if _editing_bot():
		PartyManager.set_bot_politician_name(_edit_target, _bot_first_edit.text, _bot_surname_edit.text)

## Düzenlenen botun güncel adını alanlara yazar (yazılırken üzerine yazmaz).
func _refresh_bot_name_fields() -> void:
	if _bot_first_edit == null or not _editing_bot():
		return
	var data: Dictionary = PartyManager.politicians.get(_edit_target, {})
	if not _bot_first_edit.has_focus():
		_bot_first_edit.text = String(data.get("first_name", ""))
	if not _bot_surname_edit.has_focus():
		_bot_surname_edit.text = String(data.get("surname", ""))

## Düzenlenen botun çekirdek seçmen gruplarını rastgele yenile (öncekinden
## farklı bir çift gelsin diye birkaç kez dener).
func _randomize_bot_core() -> void:
	var fresh := VoterGroups.random_core()
	for i in 10:
		if _core.size() != 2 or not (fresh.has(_core[0]) and fresh.has(_core[1])):
			break
		fresh = VoterGroups.random_core()
	_core = fresh
	_build_core_buttons()
	_push_party()

func _build_icon_grid() -> void:
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
		_refresh_bot_name_fields()
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
		left_preview.resized.connect(_layout_preview)
		_layout_preview()
	var panel := PanelContainer.new()
	panel.name = L.t("PlayersPanel")
	panel.anchor_bottom = 1.0
	panel.offset_left = 12
	panel.offset_top = 86
	panel.offset_right = PLAYERS_PANEL_WIDTH - 6
	panel.offset_bottom = -12
	var style := UiSkin.stylebox(UiSkin.PANEL_DARK)
	style.set_content_margin_all(UiTheme.PAD_M)
	UiSkin.apply_style(panel, "panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = L.t("OYUNCULAR")
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
	# Hemen çıkar: aynı karede birkaç kez yenilenince eski satırlar birikmesin.
	for child in _players_list.get_children():
		_players_list.remove_child(child)
		child.queue_free()
	var my_id := multiplayer.get_unique_id()
	var order: Array = MultiplayerManager.lobby_order() if not MultiplayerManager.players.is_empty() else [my_id]
	for peer_id in order:
		var party: Dictionary = PartyManager.parties.get(peer_id, {}).duplicate()
		# KENDİ SATIRIM ve DÜZENLENEN BOT anlık: seçimler (ad boşken host'a hiç
		# gitmez) beklemeden panelde görünsün.
		var live_target := _edit_target if _editing_bot() else my_id
		if int(peer_id) == live_target:
			party["icon_index"] = _selected_icon_index
			party["bg_color"] = _selected_bg_color
			if _party_name.strip_edges() != "":
				party["name"] = _party_name
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		# KARE KALSIN: satır (ad + parti + siyasetçi) 40'tan yüksek, gerilmesin.
		swatch.size_flags_vertical = SIZE_SHRINK_CENTER
		swatch.size_flags_horizontal = SIZE_SHRINK_CENTER
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
		var player_name := String(MultiplayerManager.players.get(peer_id, {}).get("name", L.t("Sen")))
		player_label.text = player_name + (L.t(" (sen)") if int(peer_id) == my_id else "") + ("  🤖" if MultiplayerManager.is_bot(peer_id) else "")
		player_label.add_theme_font_size_override("font_size", 13)
		player_label.modulate = UiTheme.TEXT_MUTED
		player_label.clip_text = true
		texts.add_child(player_label)
		var party_label := Label.new()
		party_label.text = String(party.get("name", L.t("parti kuruyor…")))
		party_label.add_theme_font_size_override("font_size", 17)
		party_label.clip_text = true
		texts.add_child(party_label)
		var politician: Dictionary = PoliticianPresets.of(int(peer_id))
		if not politician.is_empty():
			var leader_label := Label.new()
			leader_label.text = "%s · %s · %s" % [String(politician.get("name", "")),
				PoliticianPresets.title(String(politician.get("background", ""))),
				GameMap.name_of(String(politician.get("hometown", "")))]
			leader_label.add_theme_font_size_override("font_size", 11)
			leader_label.modulate = UiTheme.GOLD
			leader_label.clip_text = true
			texts.add_child(leader_label)
		row.add_child(texts)
		# Oda sahibi botların partisini düzenleyebilir; düzenlenen satır vurgulu.
		if MultiplayerManager.is_local_owner() and (MultiplayerManager.is_bot(peer_id) or int(peer_id) == my_id) \
				and MultiplayerManager.players.size() > 0:
			var editing: bool = (int(peer_id) == _edit_target) or (int(peer_id) == my_id and not _editing_bot())
			var edit_button := Button.new()
			edit_button.text = "✎" if int(peer_id) != my_id else L.t("Ben")
			edit_button.tooltip_text = L.t("Bu botun adını, logosunu ve rengini düzenle") if int(peer_id) != my_id else L.t("Kendi partine dön")
			# Tema butonu 18px iç boşlukla gelir ve dar satırda adı eziyordu;
			# UiSkin zemini iç boşluksuz olduğu için burada kompakt kalıyor.
			UiSkin.skin_button(edit_button)
			edit_button.add_theme_font_size_override("font_size", 14)
			edit_button.custom_minimum_size = Vector2(38, 32)
			edit_button.size_flags_vertical = SIZE_SHRINK_CENTER
			edit_button.modulate = UiTheme.GOLD if editing else Color.WHITE
			edit_button.pressed.connect(_start_editing.bind(-1 if int(peer_id) == my_id else int(peer_id)))
			row.add_child(edit_button)
		var ready_label := Label.new()
		ready_label.text = "✔" if PartyManager.is_ready(peer_id) else "…"
		ready_label.modulate = UiTheme.GREEN if PartyManager.is_ready(peer_id) else UiTheme.TEXT_DIM
		ready_label.add_theme_font_size_override("font_size", 18)
		row.add_child(ready_label)
		_players_list.add_child(row)

## LOGO ÖNİZLEMESİ: eskiden 280x280 sabitti; oyuncu paneli ile ekranın
## ortası arasındaki boşluk bundan darsa kare kenarlara yapışıp sıkışık
## duruyordu. Artık kalan alana göre ölçekleniyor ve hep kare kalıyor.
func _layout_preview() -> void:
	var left_preview := get_node_or_null("LeftPreview") as Control
	if left_preview == null or preview_bg == null:
		return
	var space := left_preview.size
	if space.x <= 0.0 or space.y <= 0.0:
		return
	var side := clampf(minf(space.x - PREVIEW_MARGIN * 2.0, space.y - PREVIEW_MARGIN * 2.0),
		PREVIEW_MIN_SIDE, PREVIEW_MAX_SIDE)
	var half := side * 0.5
	preview_bg.custom_minimum_size = Vector2(side, side)
	preview_bg.offset_left = -half
	preview_bg.offset_top = -half
	preview_bg.offset_right = half
	preview_bg.offset_bottom = half
	var icon_half := half * PREVIEW_ICON_RATIO
	preview_icon.offset_left = -icon_half
	preview_icon.offset_top = -icon_half
	preview_icon.offset_right = icon_half
	preview_icon.offset_bottom = icon_half

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
		# KARE KALSIN: HFlowContainer çocukları satırın yüksekliğine geriyordu;
		# "✕" yazılı bir kutu satırı yükseltince bütün renkler dikdörtgen
		# oluyordu. Shrink ile her kutu kendi kare ölçüsünde kalır.
		btn.size_flags_horizontal = SIZE_SHRINK_CENTER
		btn.size_flags_vertical = SIZE_SHRINK_CENTER
		btn.clip_text = true
		if taken:
			btn.text = "✕"
			btn.add_theme_font_size_override("font_size", 12)
			btn.tooltip_text = L.t("Bu renk başka bir oyuncuda")
		btn.disabled = not allowed or (_is_locked and not _editing_bot())
		btn.modulate = Color.WHITE if allowed else Color(0.55, 0.55, 0.55, 1.0)
		# Seçili renk altın çerçeveyle ayrılır (pixel tarz: kare, kalın kenar).
		var selected := color.is_equal_approx(_selected_bg_color)
		var style := UiSkin.color_box(color, UiSkin.BUTTON_TINT_HOVER if selected else UiSkin.BUTTON_TINT_NORMAL)
		for state in ["normal", "hover", "pressed", "disabled"]:
			UiSkin.apply_style(btn, state, style)
		if selected:
			var ring := UiSkin.color_surface(UiTheme.GOLD, UiSkin.TARGET)
			ring.set_anchors_preset(Control.PRESET_FULL_RECT)
			btn.add_child(ring)
		if allowed:
			btn.pressed.connect(_on_bg_color_selected.bind(i))
		bg_color_row.add_child(btn)

## OYUN BAŞI: parti kurulumundan siyasetçi profiline geri dönülebilir.
var _profile_button: Button

func _build_back_to_profile_button() -> void:
	_profile_button = Button.new()
	_profile_button.text = L.t("← Profilim")
	_profile_button.tooltip_text = L.t("Siyasetçi profiline dön (ad, geçmiş, memleket)")
	_profile_button.focus_mode = Control.FOCUS_NONE
	_profile_button.custom_minimum_size = Vector2(150, 40)
	# Sağ üstte, Menü düğmesinin solunda (başlığı kapatmasın).
	_profile_button.anchor_left = 1.0
	_profile_button.anchor_right = 1.0
	_profile_button.offset_left = -330.0
	_profile_button.offset_right = -170.0
	_profile_button.offset_top = 18.0
	_profile_button.offset_bottom = 58.0
	_profile_button.z_index = 50
	_profile_button.pressed.connect(func():
		if _is_locked:
			return
		SceneTransition.fade_to_scene("res://scenes/PoliticianSetup.tscn"))
	add_child(_profile_button)

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

## SEKİZ SEÇMEN GRUBU (iki sütun, çiftler yan yana): partinin 2 çekirdek grubu
## seçilir. Aynı çiftten iki grup seçilemez (ör. işçi + işveren): çiftin öbür
## tarafına basmak seçimi o tarafa taşır; 2 seçiliyken üçüncüye basmak en eski
## seçimi bırakır.
func _build_core_buttons() -> void:
	for child in core_container.get_children():
		core_container.remove_child(child)
		child.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	core_container.add_child(grid)
	for group in VoterGroups.GROUP_IDS:
		grid.add_child(_core_button(group))
	_core_note = Label.new()
	_core_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_core_note.add_theme_font_size_override("font_size", 10)
	_core_note.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_core_note.text = L.t("Çekirdek gruplarda %%%d, diğerlerinde %%%d hitapla başlarsın; çekirdek gruplarda kazancın %d katıdır. Hitap yasa, miting ve toplantıyla büyür, rakipler senden seçmen çalabilir.") % [
		int(VoterGroups.CORE_START), int(VoterGroups.AFFINITY_NEUTRAL), int(VoterGroups.CORE_GAIN_MULT)]
	core_container.add_child(_core_note)

func _core_button(group: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 30)
	button.button_pressed = _core.has(group)
	button.disabled = _is_locked and not _editing_bot()
	button.tooltip_text = L.t("%s\n%s\nTalepler: %s") % [VoterGroups.title(group), String(VoterGroups.data(group).get("blurb", "")),
		VoterGroups.issues_text(group)]
	UiSkin.skin_color_button(button, VoterGroups.color(group).darkened(0.2) if _core.has(group) else UiTheme.PANEL)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon := VoterGroupIcon.make(group, 18.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Label.new()
	label.text = VoterGroups.title(group)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UiTheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	button.pressed.connect(_on_core_pressed.bind(group))
	return button

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
	_build_core_buttons()
	_push_party()

func _update_preview() -> void:
	preview_bg.color = _selected_bg_color
	preview_icon.texture = PartyPresets.get_icon_texture(_selected_icon_index, PREVIEW_ICON_PIXEL_SIZE)
	preview_icon.modulate = ICON_COLOR
	preview_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_refresh_players_panel()

func _push_party() -> void:
	if not PartyManager.is_valid_name(_party_name):
		if not _editing_bot():
			PartyManager.set_my_color(_selected_bg_color)
		return
	if _editing_bot():
		PartyManager.set_bot_party(_edit_target, _party_name, _selected_icon_index, _selected_bg_color, _core)
		return
	PartyManager.set_my_party(_party_name, _selected_icon_index, ICON_COLOR, _selected_bg_color, _core)

## Oda sahibi: bir botun partisini düzenlemeye başla ya da kendi partine dön
## (bot_id = -1). Kendi seçimlerin saklanır, geri dönünce yerine konur.
func _start_editing(bot_id: int) -> void:
	var me := multiplayer.get_unique_id()
	if bot_id != -1 and (not MultiplayerManager.is_local_owner() or not MultiplayerManager.is_bot(bot_id)):
		return
	if not _editing_bot():
		_own_backup = {"name": _party_name, "icon": _selected_icon_index, "color": _selected_bg_color,
			"core": _core.duplicate()}
	if bot_id == -1 or bot_id == me:
		_edit_target = -1
		_party_name = String(_own_backup.get("name", _party_name))
		_selected_icon_index = int(_own_backup.get("icon", _selected_icon_index))
		_selected_bg_color = _own_backup.get("color", _selected_bg_color)
		_core = (_own_backup.get("core", _core) as Array).duplicate()
		title_label.text = L.t("PARTİNİ KUR")
		_set_controls_disabled(_is_locked)
		_refresh_ready_button()
	else:
		_edit_target = bot_id
		var party: Dictionary = PartyManager.parties.get(bot_id, {})
		_party_name = String(party.get("name", ""))
		_selected_icon_index = int(party.get("icon_index", 0))
		_selected_bg_color = party.get("bg_color", _selected_bg_color)
		var bot_core: Array = party.get("core", [])
		_core = bot_core.duplicate() if VoterGroups.is_valid_core(bot_core) else VoterGroups.random_core()
		title_label.text = L.t("BOT PARTİSİ: %s") % MultiplayerManager.players.get(bot_id, {}).get("name", L.t("Bot"))
		_set_controls_disabled(false)
		ready_button.disabled = true  # hazır butonu sadece kendi partin için
	name_edit.text = _party_name
	_update_name_hint()
	_selected_icon_index = PartyPresets.clamp_icon_index(_selected_icon_index)
	_refresh_icon_grid_selection()
	_build_color_row()
	_build_core_buttons()
	_update_preview()
	_refresh_players_panel()
	_refresh_bot_name_fields()

## "Kilitle ve Hazır Ver" / iptal: kilitliyken tüm seçim kontrolleri
## devre dışı kalır (yanlışlıkla değiştirilemesin diye), tekrar basınca açılır.
## Kilitlerken parti verisi + hazır bayrağı TEK bir atomik çağrıyla
## (set_party_and_ready) birlikte gönderiliyor — hızlıca art arda
## seç+kilitle yapılırsa host'un "hazır"ı partinin SON hâli ulaşmadan
## uygulayıp oyunu erken/varsayılan veriyle başlatma riski bu şekilde
## tamamen ortadan kalkıyor (bkz. PartyManager.set_party_and_ready).
func _on_ready_pressed() -> void:
	if _editing_bot() or (not _is_locked and not PartyManager.is_valid_name(_party_name)):
		return
	_is_locked = not _is_locked
	_set_controls_disabled(_is_locked)
	ready_button.text = L.t("✕ İptal Et") if _is_locked else L.t("🔒 Kilitle ve Hazır Ver")
	if _is_locked:
		if PartyManager.is_valid_name(_party_name):
			PartyManager.set_party_and_ready(_party_name, _selected_icon_index, ICON_COLOR, _selected_bg_color, _core, true)
	else:
		PartyManager.set_ready(false)

func _set_controls_disabled(disabled: bool) -> void:
	name_edit.editable = not disabled
	for btn in icon_grid.get_children():
		btn.disabled = disabled
	_build_color_row()
	_build_core_buttons()

func _on_party_setup_finished() -> void:
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")
