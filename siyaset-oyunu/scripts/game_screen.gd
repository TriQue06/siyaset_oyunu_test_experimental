extends Control
## Oyun ekranı: harita + sağdaki oyuncu paneli + kart destesi/el sistemi.
##
## Tur akışı: CardManager.turn_order'daki (oyun başında rastgele belirlenmiş)
## sıradaki oyuncu deste butonuna basıp kart çeker (fade animasyonuyla ekran
## ortasından elinin ortasına yerleşir), sonra elindeki kartlardan birini
## seçip oynar (HERKESİN ekranında görünen, ortada "puf" olup kaybolan bir
## animasyon), sıra bir sonraki oyuncuya geçer. Üstte geçici bir tur
## göstergesi var (kalıcı görseli kullanıcı sonra ekleyecek).

## Ekranın üst kısmı (harita + oyuncu şeridi + deste); geri kalanı BottomArea
## (parlamento diyagramı + oy oranı paneli) — bkz. GameScreen.tscn'deki
## BottomArea.anchor_top = 0.62 ile birebir eşleşmeli.
const TOP_AREA_HEIGHT_RATIO := 0.54
const MAP_FILL_RATIO := 0.98
## Sağ sütun: üstte parti logoları, altta deste + Pas Geç + sıra göstergesi.
## GameScreen.tscn'deki PlayerPanel/DeckButton/PassButton/TurnIndicator
## offset'leri bu genişliğe göre ayarlı.
const RIGHT_COLUMN_WIDTH := 200.0
## Alt haznede meclisin (sol) aldığı pay; kalan sağ kısım el kartlarına.
const PARLIAMENT_WIDTH_RATIO := 0.55
const AVATAR_SEPARATION := 6.0
const AVATAR_SIZE := 56.0
## Parti logoları (çerçeve dahil) party_badge.gd'de; sol paneller government_hud.gd'de.
const AVATAR_ICON_PIXEL_SIZE := 144
## Soldaki tam boy bilgi panelinin genişliği — GameScreen.tscn'deki
## LeftPanel.offset_right ile birebir eşleşmeli.
const LEFT_PANEL_WIDTH := 260.0
const BADGE_ICON_PIXEL_SIZE := 64

# Kartlar 72x96 piksel native boyutta; Nearest filtre ile piksel-sanat
# görünümü bozulmasın diye tam sayı katıyla büyütülüyor.
const CARD_DISPLAY_SCALE := 2.0
const CARD_DISPLAY_SIZE := Vector2(72, 96) * CARD_DISPLAY_SCALE
const CARD_HOVER_LIFT_SPEED := 12.0
const HAND_CARD_SEPARATION := 8
## Fare bu kadar kaydırılırsa tık değil SÜRÜKLEME başlar.
const TAP_MAX_MOVE_PX := 10.0
## Oylamada parlamento koltuklarının ve profil etiketlerinin rengi.
const VOTE_COLORS := {1: Color(0.32, 0.82, 0.38), 0: Color(0.92, 0.78, 0.3), -1: Color(0.92, 0.3, 0.3)}

## HARİTA KATMANLARI: aynı Türkiye haritasının üç ayrı görünümü; butonlarla
## geçilir, harita yan yana dizilmiş sayfalar gibi yana kayar.
##   SEATS        : son seçim (il kazananları + vekil daireleri)
##   ORGANIZATION : teşkilat seviyem (0 beyaz → 3 parti rengi)
##   STRENGTH     : tüm faktörlerle (ilin görüşü, bütün partilerin gücü) şimdi
##                  seçim olsa bu ilde durumum; her ilde, ilk turdan itibaren
enum MapLayer { SEATS, ORGANIZATION, STRENGTH }
const MAP_LAYER_TITLES := ["Vekiller", "Teşkilat", "Güç"]
const MAP_UNKNOWN_COLOR := Color(0.62, 0.62, 0.64)
const MAP_SLIDE_DURATION := 0.38
## Güç haritasında bu kadar il puanı en koyu renge denk gelir.
const STRENGTH_STOPS := [Color(0.42, 0.04, 0.05), Color(0.88, 0.2, 0.14), Color(0.96, 0.84, 0.24), Color(0.36, 0.76, 0.3), Color(0.04, 0.36, 0.13)]
const MAP_BLANK_COLOR := Color(0.97, 0.97, 0.95)
## Teşkilat hamlesinden sonra haritanın teşkilat katmanında kaldığı süre.
const ORG_RESULT_HOLD := 1.2
const SHADOW_OFFSET := Vector2(4, 5)
const SHADOW_COLOR := Color(0, 0, 0, 0.38)

const DRAW_FLY_DURATION := 0.16   # deste -> ekran ortası (hızlı)
const DRAW_SETTLE_DURATION := 0.16  # ekran ortası -> el'deki yeni yeri
const DRAW_HOLD_DURATION := 0.10
const PLAY_FLY_DURATION := 0.22   # el/avatar -> ekran ortası
const PLAY_POP_DURATION := 0.18   # ortada küçülüp "puf" kaybolma

@onready var map_holder: Node2D = %MapHolder
@onready var deck_button: TextureButton = %DeckButton
var _deck_shadow: TextureRect
@onready var pass_button: Button = %PassButton
@onready var player_panel_list: GridContainer = %PlayerPanelList
@onready var hand_container: HBoxContainer = %HandContainer
@onready var hand_area: Control = %HandArea
@onready var turn_indicator: PanelContainer = %TurnIndicator
@onready var turn_indicator_label: Label = %TurnIndicatorLabel
@onready var turn_indicator_badge_slot: Control = %TurnIndicatorBadgeSlot
@onready var hover_tooltip: Control = %HoverTooltip
@onready var hover_tooltip_image: TextureRect = %HoverTooltipImage
@onready var parliament_diagram: ParliamentDiagram = %ParliamentDiagram
@onready var vote_share_panel: VoteSharePanel = %VoteSharePanel
@onready var game_settings_label: Label = %GameSettingsLabel
@onready var bottom_area: Control = %BottomArea
@onready var vote_yes_button: TextureButton = %VoteYesButton
@onready var vote_no_button: TextureButton = %VoteNoButton
@onready var proposal_label: Label = %ProposalLabel
@onready var left_panel: PanelContainer = %LeftPanel
@onready var government_vbox: VBoxContainer = %GovernmentVBox
@onready var score_vbox: VBoxContainer = %ScoreVBox

## Hedef seçmeyi bekleyen "vekil çalma" kartının el içindeki sırası (-1 = yok).
var _pending_target_hand_index: int = -1
## Seçim sonucu animasyonuna geçilirken true olur; hükümet kurma ekranına
## erken atlamayı engeller (bkz. _on_election_completed).
var _leaving_for_results: bool = false
var _waiting_overlay: Control
var _waiting_label: Label
var _waiting_badge_slot: CenterContainer
var _waiting_badge_holder: int = -2

## Profil kartı açık olan parti (-1 = kapalı). Dokununca açılır/kapanır.
var _profile_peer_id: int = -1
## Seçili (kalkmış, açıklaması görünen) el kartı; -1 = yok.
var _selected_hand_index: int = -1
## Hedef seçerken ilk dokunuşla seçilen il (ikinci dokunuş onaylar).
var _selected_province: String = ""
var _hand_holders: Array = [] # Array[Control], hover-kaldirma animasyonu icin (her biri bir kartin "holder"i)
var _hovered_province_id: String = ""
# province_id -> Color (kazanan partinin rengi) — hover'dan çıkınca buna dönülür.
var _province_base_colors: Dictionary = {}
## Son seçimde illeri kazanan partilerin renkleri (Vekiller katmanı).
var _seat_layer_colors: Dictionary = {}
## Harita katmanı (bkz. MapLayer) ve katman geçişi.
var _map_layer: int = MapLayer.SEATS
var _layer_before_org: int = -1
var _org_view_token: int = 0
var _map_clip: Control
var _map_snapshot: TextureRect
var _map_slide_tween: Tween
var _layer_switching: bool = false
var _queued_layer: int = -1
var _layer_bar: HBoxContainer
var _layer_buttons: Array = []
var _layer_legend: Control
var _game_over_overlay: Control
## Ekranın üstünde kısa süre görünen bilgi yazısı (teklif sonucu, yeni tur…).
var _toast: Label
## Sayaç yazıları sadece gösterilen saniye değişince yenilensin diye.
var _last_countdown_key: int = -1
## Sağ sütundaki oyuncu kartlarının o anki yüksekliği (sütuna sığacak kadar).
var _avatar_height: float = 64.0
## İl seçmeyi bekleyen kartın (miting/yatırım) el içindeki sırası (-1 = yok).
var _pending_province_hand_index: int = -1
var _province_panel: ProvincePanel
## Hedef seçme modundayken üstte görünen yönerge ("... sağ tık: iptal").
var _target_hint: Label
## Eldeki bir kartın üstüne gelince çıkan açıklama kutusu.
var _card_info: PanelContainer
var _card_info_title: Label
var _card_info_desc: Label
var _abstain_button: Button
## Sürüklenen kart (el içindeki sırası; -1 = sürükleme yok) ve imleci izleyen kopyası.
var _drag_hand_index: int = -1
var _drag_card_type: String = ""
var _drag_ghost: TextureRect
## Sürükleme sırasında el yeniden kurulmak istendi mi (bırakınca kurulur).
var _hand_dirty: bool = false
## Hamle butonları ve mana göstergesi (sağ sütun, destenin yanında).
var _mana_box: HBoxContainer
var _mana_label: Label
var _law_button: Button
var _org_button: Button
var _miting_button: Button
## Miting hamlesi için il seçme modu.
var _pending_miting: bool = false
var _invest_button: Button
var _censure_button: Button
## Yatırım hamlesi için il seçme modu.
var _pending_invest: bool = false
## Gensoru: ilk dokunuş onay ister, ikincisi verir.
var _pending_censure: bool = false
var _last_turn_peer: int = -2
## Yasa tasarlama paneli (6 daire) ve karalama hedef menüsü.
var _law_designer: PanelContainer
var _propaganda_menu: PanelContainer
## Teşkilatlanma için il seçme modu (harita teşkilat katmanına geçer).
var _pending_org: bool = false
var _circle_textures: Dictionary = {}
## Mana göstergesine dokununca gösterilen kural özeti.
var _mana_rules: String = ""
## Yasa panelinde seçilen dairenin açıklaması (dokununca güncellenir).
var _law_info: Label
var _law_rows: VBoxContainer
var _law_agenda_label: Label
var _law_points_label: Label
## Haritanın sağ üstünde gündem bandı.
var _agenda_banner: PanelContainer
var _agenda_label: Label

func _ready() -> void:
	map_holder.province_clicked.connect(_on_province_clicked)
	_refresh_game_settings_label()
	MultiplayerManager.settings_updated.connect(_refresh_game_settings_label)

	_place_right_column_controls()
	deck_button.texture_normal = CardPresets.get_closed_texture()
	deck_button.pressed.connect(_on_deck_pressed)
	_deck_shadow = _add_shadow_behind(deck_button, CardPresets.get_closed_texture())
	pass_button.pressed.connect(_on_pass_pressed)

	await get_tree().process_frame
	_apply_layout()
	# Tam ekrana geçip çıkınca / pencere yeniden boyutlanınca yerleşimi TEKRAR
	# hesapla. Aksi hâlde anchor'a bağlı elemanlar (oyuncu paneli, deste, kart
	# eli) yeni boyuta göre kendiliğinden kayarken, aşağıda mutlak piksel
	# olarak hesaplanan harita ölçeği/konumu ve alt hazne kenarları ESKİ
	# viewport boyutunda kalıyordu — ikisi birbirinden kopup "UI elemanları
	# bazen birbirine yaklaşıyor/uzaklaşıyor" şikayetine yol açıyordu.
	get_viewport().size_changed.connect(_apply_layout)

	hover_tooltip.hide()
	PartyManager.parties_updated.connect(_on_parties_updated)
	CardManager.turn_order_updated.connect(_rebuild_player_panel)
	CardManager.turn_changed.connect(_on_turn_changed)
	CardManager.inventories_updated.connect(_rebuild_hand)
	CardManager.card_drawn.connect(_on_card_drawn)
	CardManager.card_played.connect(_on_card_played)
	CardManager.election_completed.connect(_on_election_completed)
	CardManager.round_advanced.connect(_on_round_advanced)
	CardManager.game_over.connect(_on_game_over)
	CardManager.seats_changed.connect(_on_seats_changed)
	GovernmentManager.proposal_resolved.connect(_on_proposal_resolved)
	CardManager.opinion_event.connect(_show_toast)
	GovernmentManager.coalition_changed.connect(_show_toast)
	CardManager.opinion_changed.connect(_on_opinion_changed)

	UiSkin.skin_panel(left_panel, UiSkin.PANEL_DARK)
	_build_waiting_overlay()
	_build_toast()
	_build_target_hint()
	_build_card_info()
	_build_action_buttons()
	_build_law_designer()
	_build_agenda_banner()
	_build_propaganda_menu()
	vote_yes_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_YES))
	vote_no_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_NO))
	_abstain_button = Button.new()
	_abstain_button.text = "Çekimser"
	_abstain_button.custom_minimum_size = Vector2(96, 48)
	UiSkin.skin_button(_abstain_button)
	_abstain_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_ABSTAIN))
	vote_yes_button.get_parent().add_child(_abstain_button)
	vote_yes_button.get_parent().move_child(_abstain_button, vote_yes_button.get_index() + 1)
	GovernmentManager.phase_changed.connect(_on_government_phase_changed)
	GovernmentManager.government_changed.connect(_refresh_government_panel)
	GovernmentManager.proposal_changed.connect(_refresh_vote_ui)
	GovernmentManager.proposal_changed.connect(_on_proposal_changed)
	GovernmentManager.scores_changed.connect(_refresh_score_panel)

	_rebuild_player_panel()
	_rebuild_hand()
	_on_turn_changed(CardManager.current_turn_peer_id())
	_refresh_results_panels()
	_refresh_government_panel()
	_refresh_score_panel()
	_refresh_vote_ui()
	_on_government_phase_changed()
	if CardManager.game_finished:
		_on_game_over()

## Viewport boyutuna bağlı TÜM mutlak-piksel yerleşim hesapları burada — hem
## açılışta hem her yeniden boyutlanmada (tam ekran vb.) çağrılır.
func _apply_layout() -> void:
	if map_holder == null or map_holder.grid_width <= 0:
		return
	var viewport_size := get_viewport_rect().size
	# Harita SADECE üst bölgeye (TOP_AREA_HEIGHT_RATIO) ve sağdaki deste/
	# oyuncu şeridi hariç kalan genişliğe sığacak şekilde ölçekleniyor —
	# geniş, dikdörtgen bir alanı doldurması hedefleniyor.
	var available_width := viewport_size.x - RIGHT_COLUMN_WIDTH - LEFT_PANEL_WIDTH
	var available_height := viewport_size.y * TOP_AREA_HEIGHT_RATIO
	# Haritanın "doğal" (native) piksel boyutu sabit bir const DEĞİL —
	# pixel-art asset (assets/maps/turkey_map.png) her değiştiğinde boyutu
	# değişebiliyor, o yüzden province_map.gd'nin YÜKLEDİĞİ gerçek ızgara
	# boyutundan (grid_width/height * MAP_UNIT_SCALE) runtime'da hesaplanıyor.
	var map_native_size: Vector2 = Vector2(map_holder.grid_width, map_holder.grid_height) * map_holder.MAP_UNIT_SCALE
	var fit_scale: float = minf(available_width / map_native_size.x, available_height / map_native_size.y) * MAP_FILL_RATIO
	map_holder.scale = Vector2(fit_scale, fit_scale)
	var map_position := Vector2(
		LEFT_PANEL_WIDTH + available_width * 0.5 - map_native_size.x * 0.5 * fit_scale,
		available_height * 0.5 - map_native_size.y * 0.5 * fit_scale
	)
	# Harita, katman geçişinde yana kayabilsin diye kırpan bir kutunun içinde.
	_ensure_map_clip()
	_map_clip.position = map_position
	_map_clip.size = map_native_size * fit_scale
	if _map_slide_tween == null or not _map_slide_tween.is_running():
		map_holder.position = Vector2.ZERO
	_place_layer_bar()

	# Alt hazne, sol panel ile sağ sütun arasındaki TÜM genişliği kullanır:
	# solda meclis diyagramı + oylama (PARLIAMENT_WIDTH_RATIO), sağında el
	# kartları. Kartlar böylece butonların ve teklif yazısının üstüne binmez.
	var parliament_right: float = LEFT_PANEL_WIDTH + available_width * PARLIAMENT_WIDTH_RATIO
	bottom_area.offset_left = LEFT_PANEL_WIDTH
	bottom_area.offset_right = parliament_right - viewport_size.x
	hand_area.offset_left = parliament_right
	hand_area.offset_right = -RIGHT_COLUMN_WIDTH
	_fit_hand_width(CardManager.my_inventory().size())

	# Elde bekleyen kartların satırı, yarısı ekranın altından taşacak şekilde
	# aşağı kaydırılıyor; hover eden tek kart kendi içinde yukarı çıkıp
	# tamamı görünür (bkz. _build_hand_card).
	hand_container.offset_top = CARD_DISPLAY_SIZE.y * 0.5
	hand_container.offset_bottom = CARD_DISPLAY_SIZE.y * 0.5

	# Harita ölçeği değişti => vekil kareleri yeni ölçeğe göre yeniden piksel
	# hizalanmalı (bkz. seat_markers.gd _draw).
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.queue_redraw()
	# Sağ sütunun yüksekliği değişti: logolar sığacak ölçekte yeniden kurulsun.
	_rebuild_player_panel()

## Seçim yapılınca HERKESİN ekranında tetiklenir: ekran kararıp seçim
## sonuçları animasyon ekranına geçilir, oradan otomatik olarak buraya (yeni
## bir GameScreen örneğine) geri dönülür — dönüşte _ready() en güncel
## sonuçları _refresh_results_panels ile gösterir.
func _on_election_completed() -> void:
	# Seçim sonucu animasyonuna geçiyoruz. Hükümet kurma görevi aynı anda
	# atandığı için (bkz. CardManager._finish_round_if_needed), aşağıdaki
	# bayrak olmadan _on_government_phase_changed hemen devreye girip görevli
	# oyuncuyu DOĞRUDAN hükümet kurma ekranına atıyordu — o oyuncu seçim
	# sonuçlarını hiç görmüyordu. Bayrak sayesinde önce sonuçlar oynuyor,
	# GameScreen'e dönüldüğünde _ready() içindeki kontrol görevi devralıyor.
	_leaving_for_results = true
	SceneTransition.fade_to_scene("res://scenes/ElectionResults.tscn")

## Seçimsiz bir tur bitti: hükümet puanlarını aldı, yeni tur başladı.
func _on_round_advanced() -> void:
	_refresh_game_settings_label()
	_refresh_score_panel()
	_refresh_government_panel()
	_show_toast("%d. tur başladı" % CardManager.round_number)

func _on_game_over() -> void:
	_refresh_score_panel()
	if _game_over_overlay != null and is_instance_valid(_game_over_overlay):
		return
	_game_over_overlay = GameOverOverlay.new()
	add_child(_game_over_overlay)

func _on_proposal_resolved(_accepted: bool, _kind: String, _proposer_id: int) -> void:
	if GovernmentManager.last_resolution_reason != "":
		_show_toast(GovernmentManager.last_resolution_reason)

func _build_toast() -> void:
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 16.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 110
	_toast.modulate.a = 0.0
	add_child(_toast)

func _show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

## Tur / kurma / oylama sayaçları. Yazılar sadece gösterilen saniye değişince
## yenilenir (her karede label yeniden yazılmasın).
func _refresh_countdowns() -> void:
	var key := int(ceil(CardManager.turn_seconds_left())) * 1000 + int(ceil(GovernmentManager.phase_seconds_left()))
	if key == _last_countdown_key:
		return
	_last_countdown_key = key
	_update_turn_indicator_text()
	proposal_label.text = GovernmentHud.proposal_status_text(multiplayer.get_unique_id())
	if _waiting_overlay != null and _waiting_overlay.visible:
		_refresh_waiting_overlay()

func _refresh_results_panels() -> void:
	var ids: Array = CardManager.last_vote_shares.keys()
	ids.sort_custom(func(a, b): return CardManager.last_vote_shares[a] > CardManager.last_vote_shares[b])
	var vote_entries: Array = []
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var pname: String = party.get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?"))
		var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
		vote_entries.append({
			"party": party,
			"name": pname,
			"leader": _leader_name_of(peer_id),
			"color": color,
			"percent": CardManager.last_vote_shares[peer_id],
			"seats": CardManager.last_seats.get(peer_id, 0),
			"below": not CardManager.passed_threshold.has(peer_id),
		})
	vote_share_panel.set_data(vote_entries)
	_refresh_parliament_diagram()
	_refresh_map_seat_markers()
	_refresh_province_winner_colors()

## Parlamento diyagramı: koltuklar parti renginde; oylama sırasında oy vermiş
## partilerin koltukları verdikleri oyun rengine (EVET/ÇEKİMSER/HAYIR) bürünür.
## Parti sırası sabit kalır, koltuklar yer değiştirmez.
func _refresh_parliament_diagram() -> void:
	var ids: Array = CardManager.last_seats.keys()
	ids.sort_custom(func(a, b):
		return float(CardManager.last_vote_shares.get(a, 0.0)) > float(CardManager.last_vote_shares.get(b, 0.0)))
	var voting := GovernmentManager.is_voting()
	var entries: Array = []
	for peer_id in ids:
		var color: Color = PartyManager.parties.get(peer_id, {}).get("bg_color", Color(0.5, 0.5, 0.5))
		if voting and GovernmentManager.votes.has(peer_id):
			color = VOTE_COLORS[int(GovernmentManager.votes[peer_id])]
		entries.append({"seats": int(CardManager.last_seats[peer_id]), "color": color})
	if entries.is_empty():
		# İlk seçimden önce: bembeyaz, boş bir meclis (yasa dairesi buraya sürüklenir).
		entries.append({"seats": CardManager.TOTAL_SEATS, "color": EMPTY_SEAT_COLOR})
	parliament_diagram.set_results(entries)

## Oylar değişti: diyagram renkleri, profillerdeki oy etiketleri ve (oylanan
## hükümet için) sol panel güncellenir.
func _on_proposal_changed() -> void:
	_refresh_parliament_diagram()
	_rebuild_player_panel()
	_refresh_government_panel()

## Her ili, o ildeki milletvekili SAYISINDA (eşitlikte oy oranında) birinci
## olan partinin rengiyle boyar — eksen_projeksiyon/index.html'deki
## updateMapColors() kazanan-parti mantığının birebir portu: parti "baskın"
## (o ildeki koltukların yarısından fazlasını almışsa) daha doygun (alfa
## 0.8), sadece "çoğunluk" (yarıdan az ama en yüksek) ise daha soluk (alfa
## 0.6) boyanır.
func _refresh_province_winner_colors() -> void:
	_seat_layer_colors.clear()
	for province_id in CardManager.last_province_results.keys():
		var entry: Dictionary = CardManager.last_province_results[province_id]
		if entry.is_empty():
			continue
		var winner_id := -1
		var winner_seats := -1
		var winner_percent := -1.0
		var total_seats_here := 0
		for peer_id in entry.keys():
			var seats: int = entry[peer_id]["seats"]
			var percent: float = entry[peer_id]["percent"]
			total_seats_here += seats
			if seats > winner_seats or (seats == winner_seats and percent > winner_percent):
				winner_seats = seats
				winner_percent = percent
				winner_id = peer_id
		if winner_id == -1:
			continue
		# İlin rengi, salt çoğunluk olsun olmasın, DOĞRUDAN o ilde en çok
		# koltuğu alan partinin kendi rengi — TAM OPAK (alfa 1.0). Önceden
		# 0.85 alfa kullanılıyordu; pixel-art haritada bu, ilin ORİJİNAL
		# (varsayılan) piksel-art renginin %15'inin altından sızıp "kısmen
		# boyanmış" gibi görünmesine yol açıyordu — kullanıcı isteğiyle o
		# ilin pikselleri artık TAMAMEN parti rengi oluyor, karışım yok.
		var party_color: Color = PartyManager.parties.get(winner_id, {}).get("bg_color", Color(0.5, 0.5, 0.5))
		party_color.a = 1.0
		_seat_layer_colors[province_id] = party_color
	_apply_map_layer_colors()

## Harita üzerindeki il başına milletvekili noktalarını (SeatMarkers, bkz.
## Map.tscn/seat_markers.gd) son il bazlı sonuçlara göre günceller.
func _refresh_map_seat_markers() -> void:
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers == null:
		return
	seat_markers.clear_all()
	for province_id in CardManager.last_province_results.keys():
		var entry: Dictionary = CardManager.last_province_results[province_id]
		var colors: Array = []
		for peer_id in entry.keys():
			var seats: int = entry[peer_id]["seats"]
			if seats <= 0:
				continue
			var color: Color = PartyManager.parties.get(peer_id, {}).get("bg_color", Color(0.5, 0.5, 0.5))
			for i in seats:
				colors.append(color)
		if not colors.is_empty():
			seat_markers.set_seats(province_id, colors)

func _refresh_game_settings_label() -> void:
	var next_election := GameRules.next_election_round(CardManager.round_number)
	game_settings_label.text = "Tur %d/%d  ·  Baraj %%%s\n%s" % [
		mini(CardManager.round_number, GameRules.MAX_ROUNDS), GameRules.MAX_ROUNDS,
		_format_threshold(MultiplayerManager.election_threshold),
		("Sonraki seçim: %d. tur sonunda" % next_election) if next_election != -1 else "Başka seçim yok",
	]

func _format_threshold(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

func _on_deck_pressed() -> void:
	CardManager.draw_card()

func _on_pass_pressed() -> void:
	CardManager.pass_turn()

## Seçilen (ya da sürüklenen kartın altındaki) ili koyulaştırır; "" önceki
## vurguyu kaldırır. İlin taban rengi (_province_base_colors) geri yüklenir.
func _highlight_province(province_id: String) -> void:
	if _hovered_province_id != "":
		map_holder.set_province_color(_hovered_province_id, _province_base_colors.get(_hovered_province_id, Color(0, 0, 0, 0)))
	_hovered_province_id = province_id
	if province_id != "":
		var base: Color = _province_base_colors.get(province_id, Color(0, 0, 0, 0))
		# Dokunmatikte imleç yok: seçili il açıkça belli olsun.
		if base.a > 0.0:
			map_holder.set_province_color(province_id, base.darkened(0.45 if base.get_luminance() < 0.85 else 0.3))
		else:
			map_holder.set_province_color(province_id, Color(0.08, 0.08, 0.1, 0.6))

func _on_parties_updated() -> void:
	_rebuild_player_panel()
	_apply_map_layer_colors()
	_update_turn_indicator()
	if _profile_peer_id != -1:
		_show_tooltip_for(_profile_peer_id)

func _ordered_peer_ids() -> Array:
	# Oynama sırası CardManager.turn_order'da (oyun başında host tarafından
	# rastgele belirlenir); henüz gelmediyse (örn. tek başına test) katılma
	# sırasına düşer.
	if not CardManager.turn_order.is_empty():
		return CardManager.turn_order
	return MultiplayerManager.players.keys()

func _rebuild_player_panel() -> void:
	for child in player_panel_list.get_children():
		player_panel_list.remove_child(child)
		child.queue_free()
	var count: int = maxi(1, _ordered_peer_ids().size())
	# Panel boyutu ilk karede henüz hesaplanmamış olabilir: pencereden hesaplanır.
	var panel := player_panel_list.get_parent() as Control
	var available: float = get_viewport_rect().size.y - panel.offset_top + panel.offset_bottom
	_avatar_height = clampf((available - AVATAR_SEPARATION * (count - 1)) / count, 26.0, 72.0) if available > 0.0 else 64.0
	player_panel_list.columns = 1

	for peer_id in _ordered_peer_ids():
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var avatar := _build_avatar(peer_id, party)
		player_panel_list.add_child(avatar)

	# Panel yeniden kuruldu: hedef seçme vurguları yeni düğümlere uygulanmalı.
	_refresh_target_highlights()

# --- Tur göstergesi (geçici; kalıcı görseli kullanıcı sonra ekleyecek) -----

func _on_turn_changed(_peer_id: int) -> void:
	var current := CardManager.current_turn_peer_id()
	if current != _last_turn_peer:
		_last_turn_peer = current
		if current == multiplayer.get_unique_id() and not CardManager.game_finished:
			_show_toast("Sıra sende: +%d mana (toplam %d)" % [GameRules.MANA_PER_ROUND, CardManager.mana_of(current)])
	_update_turn_indicator()
	_refresh_deck_button()
	_refresh_pass_button()
	_refresh_hand_interactivity()
	_refresh_action_buttons()
	# Oyuncu kartlarında mana yazıyor: her hamlede güncellenir.
	_rebuild_player_panel()

func _update_turn_indicator() -> void:
	var peer_id := CardManager.current_turn_peer_id()
	for child in turn_indicator_badge_slot.get_children():
		child.queue_free()
	if peer_id == -1:
		turn_indicator.hide()
		return
	turn_indicator.show()
	var party: Dictionary = PartyManager.parties.get(peer_id, {})
	_update_turn_indicator_text()
	var badge := PartyBadge.build(party, turn_indicator_badge_slot.custom_minimum_size, BADGE_ICON_PIXEL_SIZE)
	turn_indicator_badge_slot.add_child(badge)

func _update_turn_indicator_text() -> void:
	var peer_id := CardManager.current_turn_peer_id()
	if peer_id == -1:
		return
	var party: Dictionary = PartyManager.parties.get(peer_id, {})
	var pname: String = party.get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?"))
	var suffix := " (Sen)" if peer_id == multiplayer.get_unique_id() else ""
	var timer := "" if CardManager.is_turn_blocked() else "\nSüre: %s" % GameRules.format_seconds(CardManager.turn_seconds_left())
	turn_indicator_label.text = "Sıra: %s%s%s" % [pname, suffix, timer]

func _refresh_deck_button() -> void:
	deck_button.disabled = not CardManager.can_draw()
	deck_button.modulate.a = 1.0 if not deck_button.disabled else 0.5
	deck_button.tooltip_text = "Kart çek (bedava, turda 1). Her seçimden sonra herkese 1 kart hediye."

func _refresh_pass_button() -> void:
	pass_button.disabled = not CardManager.can_act()
	pass_button.text = "Turu Bitir"
	# Mana bittiyse tur kendiliğinden geçmez; buton nabız gibi atarak hatırlatır.
	var should_pulse: bool = not pass_button.disabled and CardManager.mana_of(multiplayer.get_unique_id()) <= 0
	if should_pulse and _pass_pulse == null:
		pass_button.pivot_offset = pass_button.size * 0.5
		_pass_pulse = create_tween().set_loops()
		_pass_pulse.tween_property(pass_button, "scale", Vector2(1.08, 1.08), 0.45).set_trans(Tween.TRANS_SINE)
		_pass_pulse.parallel().tween_property(pass_button, "modulate", Color(1.35, 1.2, 0.6), 0.45).set_trans(Tween.TRANS_SINE)
		_pass_pulse.tween_property(pass_button, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		_pass_pulse.parallel().tween_property(pass_button, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
	elif not should_pulse and _pass_pulse != null:
		_pass_pulse.kill()
		_pass_pulse = null
		pass_button.scale = Vector2.ONE
		pass_button.modulate = Color.WHITE
	if _pass_pulse == null:
		pass_button.modulate.a = 1.0 if not pass_button.disabled else 0.5

var _pass_pulse: Tween

## Sıra sende değilken eldeki kartlar tıklanamaz + soluk görünür — kullanıcı
## "neden hiçbir şey olmuyor" diye şaşırmasın diye net bir görsel geri bildirim.
func _refresh_hand_interactivity() -> void:
	var interactive := CardManager.can_act()
	for holder in _hand_holders:
		if not is_instance_valid(holder):
			continue
		holder.modulate.a = 1.0 if interactive else 0.55
		for child in holder.get_children():
			if child is TextureRect and child.get_meta("is_click_target", false):
				child.mouse_filter = Control.MOUSE_FILTER_STOP

# --- El (envanter) ----------------------------------------------------------

func _rebuild_hand() -> void:
	# Kart sürüklenirken el yeniden kurulursa sürüklenen düğüm silinir ve
	# bırakma olayı hiç gelmez; bırakılınca kurulsun.
	if _drag_hand_index != -1:
		_hand_dirty = true
		return
	# El değişti: bekleyen hedef seçimi artık yanlış karta işaret edebilir.
	_cancel_targeting()
	_selected_hand_index = -1
	if _card_info != null:
		_card_info.hide()
	for child in hand_container.get_children():
		child.queue_free()
	_hand_holders.clear()
	var hand := CardManager.my_inventory()
	for i in hand.size():
		hand_container.add_child(_build_hand_card(hand[i], i))
	_fit_hand_width(hand.size())
	_refresh_hand_interactivity()
	_refresh_deck_button()

## Kartlar ayrılan alana (sağ yarı) sığmıyorsa aralarındaki boşluk negatife
## çekilip üst üste bindirilir; sıra göstergesine ve meclis butonlarına taşmaz.
func _fit_hand_width(count: int) -> void:
	var separation := HAND_CARD_SEPARATION
	var available: float = hand_area.size.x - 16.0
	if count > 1 and available > 0.0:
		var needed: float = count * CARD_DISPLAY_SIZE.x + (count - 1) * HAND_CARD_SEPARATION
		if needed > available:
			separation = int(floor((available - count * CARD_DISPLAY_SIZE.x) / float(count - 1)))
	hand_container.add_theme_constant_override("separation", separation)

func _process(delta: float) -> void:
	_refresh_countdowns()
	if _drag_ghost != null:
		_update_drag()

	var i := _hand_holders.size() - 1
	while i >= 0:
		var holder: Control = _hand_holders[i]
		if not is_instance_valid(holder):
			_hand_holders.remove_at(i)
			i -= 1
			continue
		var target: float = holder.get_meta("lift_target", 0.0)
		var current: float = holder.get_meta("lift_current", 0.0)
		if not is_equal_approx(current, target):
			current = lerpf(current, target, minf(1.0, CARD_HOVER_LIFT_SPEED * delta))
			if absf(current - target) < 0.5:
				current = target
			holder.set_meta("lift_current", current)
			holder.position.y = current
		i -= 1

## wrapper (HBox'un yonettigi sabit yer tutucu)
##   -> holder (hover-lift animasyonuyla Y ekseninde serbestce kayar)
##        -> shadow (kartin hafif golgesi, arkada)
##        -> card (asil kart gorseli, tiklama/hover algilayici)
func _build_hand_card(card_type: String, hand_index: int) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = CARD_DISPLAY_SIZE
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	var holder := Control.new()
	holder.custom_minimum_size = CARD_DISPLAY_SIZE
	holder.size = CARD_DISPLAY_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.set_meta("lift_target", 0.0)
	holder.set_meta("lift_current", 0.0)
	holder.set_meta("hand_index", hand_index)

	var shadow := TextureRect.new()
	shadow.texture = CardPresets.get_card_texture(card_type)
	shadow.size = CARD_DISPLAY_SIZE
	shadow.position = SHADOW_OFFSET
	shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.modulate = SHADOW_COLOR
	holder.add_child(shadow)

	var card := TextureRect.new()
	card.texture = CardPresets.get_card_texture(card_type)
	card.size = CARD_DISPLAY_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("is_click_target", true)
	holder.add_child(card)

	# Kartın ne olduğu her kartta görselin üstündeki bantta yazar.
	holder.add_child(_card_title_banner(card_type))
	holder.add_child(_card_cost_badge(CardPresets.card_cost(card_type)))

	# TIK ve SÜRÜKLEME: basılı tutup TAP_MAX_MOVE_PX'ten fazla kaydırınca
	# sürükleme başlar (kartın kopyası imleci izler, bırakınca hedefe göre
	# oynanır — bkz. _drop_target). Kaydırmadan bırakmak TIK sayılır.
	# Basılan kontrol fare odağını tuttuğu için hareket ve bırakma olayları
	# imleç kartın dışına çıksa da bu karta gelir.
	card.set_meta("pressed", false)
	card.set_meta("press_pos", Vector2.ZERO)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				card.set_meta("pressed", true)
				card.set_meta("press_pos", event.position)
			elif card.get_meta("pressed", false):
				card.set_meta("pressed", false)
				if _drag_hand_index == hand_index:
					_finish_drag()
				elif _drag_hand_index == -1:
					_on_hand_card_clicked(hand_index)
		elif event is InputEventMouseMotion and card.get_meta("pressed", false) and _drag_hand_index == -1:
			var press_pos: Vector2 = card.get_meta("press_pos", Vector2.ZERO)
			if press_pos.distance_to(event.position) > TAP_MAX_MOVE_PX:
				_start_drag(hand_index, card_type, holder)
	)

	wrapper.add_child(holder)
	_hand_holders.append(holder)
	return wrapper

## TEK DOKUNUŞ (hover yok, tablette de çalışır):
##   - karta dokunmak onu SEÇER: kalkar (üst üste binen kartların önüne çıkar),
##     açıklaması görünür; sıra sendeyse ve kart hedef istiyorsa hedef seçme
##     başlar (il / parti),
##   - seçili karta tekrar dokunmak seçimi kaldırır (iptal),
##   - sürüklemek her zaman doğrudan oynar.
func _on_hand_card_clicked(hand_index: int) -> void:
	var hand := CardManager.my_inventory()
	if hand_index < 0 or hand_index >= hand.size():
		return
	if _selected_hand_index == hand_index:
		var selected_type: String = hand[hand_index]
		# Bonus kart (hedefsiz): seçiliyken tekrar dokunmak kullanır.
		if CardPresets.is_self_card(selected_type) and CardManager.can_act():
			_deselect_hand_card()
			if CardManager.can_play_card(multiplayer.get_unique_id(), selected_type):
				CardManager.play_card(hand_index)
			else:
				_show_toast(_unplayable_reason(selected_type))
			return
		_deselect_hand_card()
		return
	_cancel_targeting()
	_select_hand_card(hand_index)
	if not CardManager.can_act():
		return  # sıra değil: sadece açıklama
	var card_type: String = hand[hand_index]
	var me := multiplayer.get_unique_id()
	if CardPresets.needs_party_target(card_type):
		_begin_targeting(hand_index)
		return
	if CardPresets.needs_province_target(card_type):
		if card_type == CardPresets.INVEST_CARD_TYPE and not CardManager.is_government_party(me):
			_show_toast("Yatırım kartını sadece hükümet partileri oynayabilir.")
			return
		_begin_province_targeting(hand_index)
		return
	if CardPresets.is_self_card(card_type):
		_set_target_hint("%s: kullanmak için karta tekrar dokun  ·  Başka yere dokun: vazgeç" % CardPresets.card_title(card_type))

func _select_hand_card(hand_index: int) -> void:
	_selected_hand_index = hand_index
	for holder in _hand_holders:
		if not is_instance_valid(holder):
			continue
		var selected: bool = int(holder.get_meta("hand_index", -1)) == hand_index
		holder.set_meta("lift_target", -CARD_DISPLAY_SIZE.y * 0.5 if selected else 0.0)
		holder.z_index = 5 if selected else 0
		if selected:
			_show_card_info(String(CardManager.my_inventory()[hand_index]), holder)

func _deselect_hand_card() -> void:
	_selected_hand_index = -1
	_cancel_targeting()
	if _card_info != null:
		_card_info.hide()
	for holder in _hand_holders:
		if is_instance_valid(holder):
			holder.set_meta("lift_target", 0.0)
			holder.z_index = 0

## Kart görselinin üstündeki isim bandı.
func _card_title_banner(card_type: String) -> Control:
	var banner := PanelContainer.new()
	banner.position = Vector2(6, 8)
	banner.size = Vector2(CARD_DISPLAY_SIZE.x - 12, 44)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.86)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(3)
	banner.add_theme_stylebox_override("panel", style)
	var title := Label.new()
	title.text = CardPresets.card_short_title(card_type)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(title)
	return banner

## Kartın sağ alt köşesindeki mana bedeli rozeti.
## Kartın üst kısmında mana bedeli: mana simgesi + sayı (bedava kartta 0).
func _card_cost_badge(cost: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.85)
	style.set_corner_radius_all(10)
	style.content_margin_left = 4
	style.content_margin_right = 7
	badge.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(row)
	var icon := TextureRect.new()
	icon.texture = MANA_ICON
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.text = str(cost)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", MANA_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	badge.reset_size()
	# Başlık bandının hemen altında, sağda: el kartlarının yarısı ekran dışında kaldığı için üstte.
	badge.position = Vector2(CARD_DISPLAY_SIZE.x - badge.get_combined_minimum_size().x - 8, 56)
	return badge

## Oynanamayan bir karta tıklanınca neden oynanamadığı.
func _unplayable_reason(card_type: String) -> String:
	if CardManager.mana_of(multiplayer.get_unique_id()) < CardPresets.card_cost(card_type):
		return "Manan yetmiyor (%d gerekli)." % CardPresets.card_cost(card_type)
	if CardPresets.is_law_card(card_type):
		return "Yasa şu an meclise getirilemez (meclis yok ya da hükümet kuruluyor)."
	if CardPresets.is_censure_card(card_type):
		return "Gensoruyu sadece muhalefet, hükümet görevdeyken verebilir."
	return "Bu kart şu an oynanamaz."

# --- Sürükle-bırak -----------------------------------------------------------

func _start_drag(hand_index: int, card_type: String, holder: Control) -> void:
	if not CardManager.can_act():
		return
	_deselect_hand_card()
	_drag_hand_index = hand_index
	_drag_card_type = card_type
	_card_info.hide()
	if holder != null:
		holder.modulate.a = 0.35
	_drag_ghost = TextureRect.new()
	# Yasa dairesi sürüklenirken kart yerine renkli bir daire imleci izler.
	var law := CardPresets.law_data(card_type)
	_drag_ghost.texture = _circle_texture(_law_color(law["axis"], int(law["dir"]))) if not law.is_empty() \
		else CardPresets.get_card_texture(card_type)
	_drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_ghost.size = Vector2(52, 52) if not law.is_empty() else CARD_DISPLAY_SIZE * 0.6
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 150
	add_child(_drag_ghost)
	# Hedef parti seçilen kartlarda geçerli partiler vurgulanır.
	if CardPresets.needs_party_target(card_type):
		_pending_target_hand_index = hand_index
		_refresh_target_highlights()
	_update_drag()

## Her kare: kopya imleci izler, imlecin altındaki hedef vurgulanır ve üstte
## "bırakırsan ne olur" yazar.
func _update_drag() -> void:
	var mouse := get_viewport().get_mouse_position()
	_drag_ghost.position = mouse - _drag_ghost.size * 0.5
	var target := _drop_target(_drag_card_type)
	_set_target_hint(String(target["label"]) + "  ·  Geçersiz yere bırak: iptal")
	var valid: bool = target["valid"]
	_drag_ghost.modulate = Color(1, 1, 1, 0.95) if valid else Color(1, 0.75, 0.75, 0.8)
	parliament_diagram.modulate = Color(1.3, 1.3, 1.05) if bool(target["parliament"]) else Color.WHITE
	if CardPresets.needs_province_target(_drag_card_type):
		var province_id: String = target["province"]
		if province_id != _hovered_province_id:
			_highlight_province(province_id)

func _finish_drag() -> void:
	var hand_index := _drag_hand_index
	var card_type := _drag_card_type
	var target := _drop_target(card_type)
	_end_drag()
	if not bool(target["valid"]):
		if String(target["error"]) != "":
			_show_toast(target["error"])
		return
	if hand_index == LAW_DRAG_INDEX:
		_law_designer.hide()
		CardManager.propose_law(card_type)
	elif card_type == CardPresets.PROPAGANDA_CARD_TYPE:
		_ask_propaganda_target(hand_index, String(target["province"]))
	else:
		CardManager.play_card(hand_index, int(target["peer"]), String(target["province"]))

func _end_drag() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	_drag_hand_index = -1
	_drag_card_type = ""
	parliament_diagram.modulate = Color.WHITE
	if _hovered_province_id != "":
		_highlight_province("")
	_cancel_targeting()
	if _hand_dirty:
		_hand_dirty = false
		_rebuild_hand()
	else:
		_refresh_hand_interactivity()

## İmlecin altındaki bırakma hedefi. Dönüş:
##   valid: bırakılırsa kart oynanır mı · peer / province: oynanacak hedef
##   label: üstte gösterilen yönerge · error: geçersiz bırakmada gösterilecek neden
##   parliament: imleç parlamento diyagramının üstünde mi (meclis kartları)
func _drop_target(card_type: String) -> Dictionary:
	var me := multiplayer.get_unique_id()
	var result := {"valid": false, "peer": -1, "province": "", "label": "", "error": "", "parliament": false}
	if CardPresets.needs_party_target(card_type) and not CardPresets.needs_target(card_type):
		# Kaset / parti içi isyan: hedef, kendisi dışında herhangi bir parti.
		var other := _party_under_mouse()
		result["peer"] = other
		var title := CardPresets.card_title(card_type)
		if other == -1:
			result["label"] = "%s için sağdaki bir partinin logosuna bırak" % title
		elif other == me:
			result["label"] = "Bu kartı kendi partine oynayamazsın"
			result["error"] = result["label"]
		elif card_type == CardPresets.REBELLION_CARD_TYPE and not CardManager.has_seats(other):
			result["label"] = "Meclis dışı partide isyan çıkmaz"
			result["error"] = result["label"]
		else:
			result["valid"] = true
			if card_type == CardPresets.REPUTATION_CARD_TYPE:
				result["label"] = "Bırak: %s hakkında kaset sızdır (ulusal −%.1f)" % [_party_name_of(other),
					PublicOpinion.REPUTATION_NATIONAL_DAMAGE]
			else:
				result["label"] = "Bırak: %s'da isyan çıkar (ilk yasa oylamasında çekimser)" % _party_name_of(other)
	elif CardPresets.needs_target(card_type):
		var peer := _party_under_mouse()
		result["peer"] = peer
		if peer == -1:
			result["label"] = "Vekil çalmak için sağdaki bir partinin logosuna bırak"
		elif CardManager.is_valid_steal_target(me, peer):
			result["valid"] = true
			var r := CardManager.steal_range(me, peer, card_type)
			result["label"] = "Bırak: %s partisinden %d-%d vekil çal (ideolojik yakınlık %%%d)" % [_party_name_of(peer),
				int(r["min"]), int(r["max"]), int(round(CardManager.ideological_closeness(me, peer) * 100.0))]
		else:
			result["label"] = "Bu partiden vekil çalınamaz"
			result["error"] = result["label"]
	elif CardPresets.needs_province_target(card_type):
		var province_id := _province_under_mouse()
		result["province"] = province_id
		var pname := ElectionNightSim.province_name(province_id)
		if province_id == "":
			result["label"] = "Haritada bir ilin üstüne bırak"
		elif card_type == CardPresets.INVEST_CARD_TYPE and not CardManager.is_government_party(me):
			result["label"] = "Yatırımı sadece hükümet partileri yapabilir"
			result["error"] = result["label"]
		else:
			result["valid"] = true
			if card_type == CardPresets.MITING_CARD_TYPE:
				result["label"] = "Bırak: %s'da miting · provokasyon riski %%%d" % [
					pname, int(round(CardManager.miting_risk(me, province_id) * 100.0))]
			elif card_type == CardPresets.INVEST_CARD_TYPE:
				result["label"] = "Bırak: %s'a yatırım" % pname
			else:
				result["label"] = "Bırak: %s'da karalama — sonra hedef partiyi seç" % pname
	elif CardPresets.is_law_card(card_type):
		var over_law := parliament_diagram.get_global_rect().has_point(get_viewport().get_mouse_position())
		result["parliament"] = over_law
		var law := CardPresets.law_data(card_type)
		if not over_law:
			result["label"] = "%s: parlamento diyagramının üstüne bırak" % law["title"]
		elif CardManager.can_propose_law(me, card_type):
			result["valid"] = true
			result["label"] = "Bırak: %s %s (bedava, turda 1)" % [law["title"],
				"seçim vaadi olarak açıklanır" if CardManager.last_seats.is_empty() else "meclise sunulur"]
		else:
			result["label"] = _action_block_reason(GameRules.LAW_MANA_COST, true)
			result["error"] = result["label"]
	elif CardPresets.is_self_card(card_type):
		var above_hand := get_viewport().get_mouse_position().y < hand_area.get_global_rect().position.y
		if not above_hand:
			result["label"] = "%s: kullanmak için yukarı sürükle" % CardPresets.card_title(card_type)
		elif CardManager.can_play_card(me, card_type):
			result["valid"] = true
			result["label"] = "Bırak: %s kullan" % CardPresets.card_title(card_type)
		else:
			result["label"] = _unplayable_reason(card_type)
			result["error"] = result["label"]
	elif CardPresets.is_censure_card(card_type):
		var over := parliament_diagram.get_global_rect().has_point(get_viewport().get_mouse_position())
		result["parliament"] = over
		if not over:
			result["label"] = "Gensoru için parlamento diyagramının üstüne bırak"
		elif CardManager.can_play_card(me, card_type):
			result["valid"] = true
			result["label"] = "Bırak: gensoru ver"
		else:
			result["label"] = _unplayable_reason(card_type)
			result["error"] = result["label"]
	return result

## İmleç haritada hangi ilin üstünde? (Paneller ve alt hazne hariç.)
func _province_under_mouse() -> String:
	var mouse := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	if mouse.x < LEFT_PANEL_WIDTH or mouse.x > viewport_size.x - RIGHT_COLUMN_WIDTH \
			or mouse.y >= bottom_area.get_global_rect().position.y:
		return ""
	return map_holder.get_province_id_at(map_holder.get_global_transform().affine_inverse() * mouse)

## Fare şu an sağdaki parti panelinde hangi partinin üstünde?
func _party_under_mouse() -> int:
	var mouse_pos := get_viewport().get_mouse_position()
	for child in player_panel_list.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var avatar := child as Control
		if avatar == null:
			continue
		if Rect2(avatar.global_position, avatar.size).has_point(mouse_pos):
			return avatar.get_meta("peer_id", -1)
	return -1

func _begin_targeting(hand_index: int) -> void:
	_pending_target_hand_index = hand_index
	_refresh_target_highlights()
	_hide_profile()
	_set_target_hint("Vekil çalmak için sağdan bir partiye dokun  ·  Karta tekrar dokun: iptal")

## Miting / yatırım: haritadan il seçilmesi beklenir (bkz. _on_province_clicked).
func _begin_province_targeting(hand_index: int) -> void:
	_pending_province_hand_index = hand_index
	# Harita tıklanabilir kalsın: açık il paneli haritanın üstünü kapatmasın.
	if _province_panel != null:
		_province_panel.hide()
	var card_type: String = CardManager.my_inventory()[hand_index]
	_set_target_hint("%s: haritada bir ile dokun (ayrıntı görünür), tekrar dokun: oyna  ·  Karta tekrar dokun: iptal" % CardPresets.card_title(card_type))

func _cancel_targeting() -> void:
	_pending_province_hand_index = -1
	if _pending_org:
		_pending_org = false
		_end_org_view()
		_refresh_action_buttons()
	if _pending_miting or _pending_invest or _pending_censure:
		_pending_miting = false
		_pending_invest = false
		_pending_censure = false
		_refresh_action_buttons()
	if _selected_province != "":
		_selected_province = ""
		if _drag_hand_index == -1:
			_highlight_province("")
	_set_target_hint("")
	if _pending_target_hand_index == -1:
		return
	_pending_target_hand_index = -1
	_refresh_target_highlights()

## Haritada bir ile tıklandı: il seçme modundaysa kart o ilde oynanır, değilse
## il detay paneli açılır/kapanır.
func _on_province_clicked(province_id: String) -> void:
	var me := multiplayer.get_unique_id()
	# Hedef seçerken ilk dokunuş ili seçip ayrıntıyı gösterir, ikinci onaylar.
	if (_pending_org or _pending_miting or _pending_invest or _pending_province_hand_index != -1) and _selected_province != province_id:
		_select_target_province(province_id)
		return
	if _pending_invest:
		_cancel_targeting()
		if CardManager.can_invest(me, province_id):
			CardManager.invest(province_id)
		else:
			_show_toast(_invest_block_reason())
		return
	if _pending_miting:
		_cancel_targeting()
		if CardManager.can_miting(me, province_id):
			CardManager.miting(province_id)
		else:
			_show_toast(_action_block_reason(GameRules.MITING_MANA_COST))
		return
	if _pending_org:
		if not CardManager.can_build_organization(me, province_id):
			_cancel_targeting()
			if CardManager.organization_level(province_id, me) >= GameRules.ORG_MAX_LEVEL:
				_show_toast("Bu ildeki teşkilatın zaten en üst seviyede.")
			else:
				_show_toast(_action_block_reason(GameRules.ORG_MANA_COST))
			return
		# Kuruldu: harita bir an teşkilat katmanında kalır (il boyansın), sonra döner.
		_pending_org = false
		_selected_province = ""
		_highlight_province("")
		_set_target_hint("")
		var level := CardManager.organization_level(province_id, me) + 1
		CardManager.build_organization(province_id)
		_show_toast("%s teşkilatı seviye %d: %s" % [ElectionNightSim.province_name(province_id), level, _org_level_text(level)])
		_refresh_action_buttons()
		var token := _org_view_token
		get_tree().create_timer(ORG_RESULT_HOLD).timeout.connect(func():
			if is_instance_valid(self) and token == _org_view_token and not _pending_org:
				_end_org_view())
		return
	if _pending_province_hand_index != -1:
		var hand_index := _pending_province_hand_index
		_cancel_targeting()
		var hand := CardManager.my_inventory()
		_deselect_hand_card()
		if hand_index >= hand.size():
			return
		var card_type: String = hand[hand_index]
		if card_type == CardPresets.PROPAGANDA_CARD_TYPE:
			_ask_propaganda_target(hand_index, province_id)
		else:
			CardManager.play_card(hand_index, -1, province_id)
		return
	if _province_panel == null:
		_province_panel = ProvincePanel.new()
		add_child(_province_panel)
	elif _province_panel.visible and _province_panel.province_id == province_id:
		_province_panel.hide()
		return
	_province_panel.position = Vector2(LEFT_PANEL_WIDTH + 12, 12)
	_province_panel.show_province(province_id)

## Hedef seçme modunda dokunulan il: vurgulanır, üstte ne olacağı yazar.
func _select_target_province(province_id: String) -> void:
	_selected_province = province_id
	_highlight_province(province_id)
	var me := multiplayer.get_unique_id()
	var pname := ElectionNightSim.province_name(province_id)
	var detail := ""
	if _pending_invest:
		detail = "%s: hükümet yatırımı (%d mana) · sen +%.0f, ortakların +%.1f güç" % [pname, GameRules.INVEST_MANA_COST,
			PublicOpinion.INVEST_LOCAL, PublicOpinion.INVEST_PARTNER_LOCAL]
	elif _pending_miting:
		detail = "%s: miting (%d mana) · provokasyon riski %%%d · gücün %+.1f" % [pname, GameRules.MITING_MANA_COST,
			int(round(CardManager.miting_risk(me, province_id) * 100.0)), CardManager.activity_of(province_id, me)]
	elif _pending_org:
		var level := CardManager.organization_level(province_id, me)
		detail = "%s: teşkilat zaten en üst seviyede" % pname if level >= GameRules.ORG_MAX_LEVEL \
			else "%s: teşkilat seviye %d → %d (%d mana) · %s" % [pname, level, level + 1, GameRules.ORG_MANA_COST, _org_level_text(level + 1)]
	else:
		var card_type: String = CardManager.my_inventory()[_pending_province_hand_index]
		if card_type == CardPresets.MITING_CARD_TYPE:
			detail = "%s: miting · provokasyon riski %%%d · gücün %+.1f" % [pname,
				int(round(CardManager.miting_risk(me, province_id) * 100.0)), CardManager.activity_of(province_id, me)]
		else:
			detail = "%s: %s" % [pname, CardPresets.card_title(card_type)]
	_set_target_hint("%s  ·  Onaylamak için tekrar dokun" % detail)

func _on_opinion_changed() -> void:
	_refresh_score_panel()
	_refresh_agenda_banner()
	if _map_layer != MapLayer.SEATS:
		_apply_map_layer_colors()
	if _province_panel != null and _province_panel.visible:
		_province_panel.refresh()

func _build_target_hint() -> void:
	_target_hint = Label.new()
	_target_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_hint.add_theme_font_size_override("font_size", 16)
	_target_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	_target_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_target_hint.add_theme_constant_override("outline_size", 6)
	_target_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_hint.z_index = 105
	_target_hint.hide()
	add_child(_target_hint)

func _set_target_hint(text: String) -> void:
	if _target_hint == null:
		return
	_target_hint.text = text
	_target_hint.visible = text != ""
	var viewport_size := get_viewport_rect().size
	_target_hint.position = Vector2(LEFT_PANEL_WIDTH, 44)
	_target_hint.size = Vector2(viewport_size.x - LEFT_PANEL_WIDTH - RIGHT_COLUMN_WIDTH, 24)

func _build_card_info() -> void:
	_card_info = PanelContainer.new()
	UiSkin.skin_panel(_card_info, UiSkin.PANEL_DARK)
	_card_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_info.z_index = 110
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_card_info.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	margin.add_child(box)
	_card_info_title = Label.new()
	_card_info_title.add_theme_font_size_override("font_size", 15)
	box.add_child(_card_info_title)
	_card_info_desc = Label.new()
	_card_info_desc.add_theme_font_size_override("font_size", 12)
	_card_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Sarma genişliği baştan bilinmezse otomatik sarmalı etiket minimum
	# yüksekliğini harf başına bir satır sanıp kutuyu ekran boyu şişiriyordu.
	_card_info_desc.custom_minimum_size = Vector2(280, 0)
	box.add_child(_card_info_desc)
	_card_info.hide()
	add_child(_card_info)

## Hover edilen kartın hemen üstünde adını ve ne yaptığını gösterir.
func _show_card_info(card_type: String, holder: Control) -> void:
	_card_info_title.text = CardPresets.card_title(card_type)
	_card_info_desc.text = CardPresets.card_description(card_type)
	_card_info.show()
	_card_info.reset_size()
	var viewport_size := get_viewport_rect().size
	var info_size := _card_info.get_combined_minimum_size()
	_card_info.size = info_size
	_card_info.position = Vector2(
		clampf(holder.global_position.x + CARD_DISPLAY_SIZE.x * 0.5 - info_size.x * 0.5,
			LEFT_PANEL_WIDTH, viewport_size.x - RIGHT_COLUMN_WIDTH - info_size.x),
		viewport_size.y - CARD_DISPLAY_SIZE.y - 12.0 - info_size.y
	)

## Hedef seçme modunda, çalınabilecek partileri vurgular; geçersiz olanları
## (kendi partin, tek vekili kalmış partiler) soluklaştırır.
func _refresh_target_highlights() -> void:
	var targeting: bool = _pending_target_hand_index != -1
	var me := multiplayer.get_unique_id()
	for child in player_panel_list.get_children():
		var avatar := child as Control
		if avatar == null:
			continue
		var peer_id: int = avatar.get_meta("peer_id", -1)
		var halo: Control = avatar.get_node_or_null("TargetHalo")
		var valid: bool = targeting and CardManager.is_valid_steal_target(me, peer_id)
		if halo != null:
			halo.visible = valid
		avatar.modulate = Color.WHITE if (not targeting or valid) else Color(1, 1, 1, 0.45)

## Hedef seçme modundayken sağdaki panelden bir partiye tıklanması.
func _on_target_party_clicked(peer_id: int) -> void:
	if _pending_target_hand_index == -1:
		_toggle_profile(peer_id)
		return
	if not CardManager.is_valid_steal_target(multiplayer.get_unique_id(), peer_id):
		return
	var hand_index := _pending_target_hand_index
	_deselect_hand_card()
	CardManager.play_card(hand_index, peer_id)

# --- Kart çekme animasyonu (sadece çeken oyuncunun kendi ekranında) --------

func _on_card_drawn(peer_id: int, card_type: String) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	var old_hand_size: int = CardManager.my_inventory().size() # state henuz guncellenmedi (eski hal)
	_play_draw_animation(card_type, old_hand_size)

func _play_draw_animation(card_type: String, old_hand_size: int) -> void:
	var flying := TextureRect.new()
	flying.texture = CardPresets.get_card_texture(card_type)
	flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flying.z_index = 100
	flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying.modulate.a = 0.0
	add_child(flying)

	var deck_rect := deck_button.get_global_rect()
	flying.size = deck_rect.size
	flying.global_position = deck_rect.position

	var viewport_center := get_viewport_rect().size / 2.0
	var center_pos := viewport_center - CARD_DISPLAY_SIZE / 2.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flying, "global_position", center_pos, DRAW_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(flying, "size", CARD_DISPLAY_SIZE, DRAW_FLY_DURATION)
	tw.tween_property(flying, "modulate:a", 1.0, DRAW_FLY_DURATION * 0.7)
	await tw.finished
	await get_tree().create_timer(DRAW_HOLD_DURATION).timeout

	# Eldeki kartlari (yeni kart dahil) normal (anisiz) diz; ucan kopya bunun
	# UZERINDE, hedef yuvaya inerek "yerlesme" hissi verir.
	_rebuild_hand()
	var insert_index: int = old_hand_size / 2
	if insert_index < hand_container.get_child_count():
		var slot: Control = hand_container.get_child(insert_index)
		var tw2 := create_tween()
		tw2.tween_property(flying, "global_position", slot.global_position, DRAW_SETTLE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		await tw2.finished

	flying.queue_free()

# --- Kart oynama animasyonu (HERKESİN ekranında) ---------------------------

func _on_card_played(peer_id: int, card_type: String) -> void:
	var origin_pos: Vector2
	var origin_size: Vector2 = CARD_DISPLAY_SIZE
	if peer_id == multiplayer.get_unique_id() and hand_container.get_child_count() > 0:
		# Kendi kartimizsa, elin ortasindan cikiyormus gibi baslat.
		var mid: Control = hand_container.get_child(hand_container.get_child_count() / 2)
		origin_pos = mid.global_position
	else:
		origin_pos = _avatar_global_position(peer_id, origin_size)
	_play_card_animation(card_type, origin_pos, origin_size)

func _avatar_global_position(peer_id: int, out_size: Vector2) -> Vector2:
	var idx := _ordered_peer_ids().find(peer_id)
	if idx != -1 and idx < player_panel_list.get_child_count():
		var avatar: Control = player_panel_list.get_child(idx)
		return avatar.global_position - (out_size - avatar.size) * 0.5
	return get_viewport_rect().size / 2.0 - out_size / 2.0

func _play_card_animation(card_type: String, origin_pos: Vector2, origin_size: Vector2) -> void:
	var flying := TextureRect.new()
	flying.texture = CardPresets.get_card_texture(card_type)
	flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flying.z_index = 100
	flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying.size = origin_size
	flying.global_position = origin_pos
	add_child(flying)

	var viewport_center := get_viewport_rect().size / 2.0
	var center_pos := viewport_center - CARD_DISPLAY_SIZE / 2.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flying, "global_position", center_pos, PLAY_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(flying, "size", CARD_DISPLAY_SIZE, PLAY_FLY_DURATION)
	await tw.finished

	_spawn_puf_particles(viewport_center)

	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(flying, "scale", Vector2(1.4, 1.4), PLAY_POP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(flying, "modulate:a", 0.0, PLAY_POP_DURATION)
	flying.pivot_offset = CARD_DISPLAY_SIZE / 2.0
	await tw2.finished
	flying.queue_free()

func _spawn_puf_particles(center_pos: Vector2) -> void:
	var particles := CPUParticles2D.new()
	add_child(particles)
	particles.position = center_pos
	particles.z_index = 101
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 18
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 160.0
	particles.gravity = Vector2(0, 200)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.0, 0.9, 0.6, 0.9)
	particles.emitting = true
	await get_tree().create_timer(particles.lifetime + 0.2).timeout
	if is_instance_valid(particles):
		particles.queue_free()

# --- Gölge yardımcıları (hafif estetik derinlik) ---------------------------

func _add_shadow_behind(control: Control, texture: Texture2D) -> TextureRect:
	var shadow := TextureRect.new()
	shadow.texture = texture
	# Dokunun kendi boyutu kontrolü büyütmesin: gölge tam control kadar olsun.
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.modulate = SHADOW_COLOR
	# PRESET_FULL_RECT üst container'a göre hesaplanır (ekranı kaplar!) — bunun
	# yerine control'ün KENDİ anchor/offset'lerini birebir kopyalayıp sadece
	# birkaç piksel kaydırıyoruz, ki gölge tam control'ün boyutunda kalsın.
	shadow.anchor_left = control.anchor_left
	shadow.anchor_top = control.anchor_top
	shadow.anchor_right = control.anchor_right
	shadow.anchor_bottom = control.anchor_bottom
	shadow.grow_horizontal = control.grow_horizontal
	shadow.grow_vertical = control.grow_vertical
	shadow.offset_left = control.offset_left + SHADOW_OFFSET.x
	shadow.offset_top = control.offset_top + SHADOW_OFFSET.y
	shadow.offset_right = control.offset_right + SHADOW_OFFSET.x
	shadow.offset_bottom = control.offset_bottom + SHADOW_OFFSET.y
	var parent := control.get_parent()
	parent.add_child(shadow)
	parent.move_child(shadow, control.get_index())
	return shadow

## Gölgeyi control'ün güncel yerine taşır (control sonradan yeniden
## konumlandırılınca gölge eski, büyük yerinde kalmasın).
func _sync_shadow(shadow: Control, control: Control) -> void:
	if shadow == null:
		return
	shadow.offset_left = control.offset_left + SHADOW_OFFSET.x
	shadow.offset_top = control.offset_top + SHADOW_OFFSET.y
	shadow.offset_right = control.offset_right + SHADOW_OFFSET.x
	shadow.offset_bottom = control.offset_bottom + SHADOW_OFFSET.y


## Sağ sütundaki oyuncu kartı: parti rengi şeridi, logo, parti ve oyuncu adı,
## yer varsa vekil / oy oranı; oylamada partinin oyu. Kendi kartın altın
## rengi parıltıyla ayrışır.
func _build_avatar(peer_id: int, party: Dictionary) -> Control:
	var is_self := peer_id == multiplayer.get_unique_id()
	var is_turn := not CardManager.turn_order.is_empty() and peer_id == CardManager.current_turn_peer_id()
	var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(RIGHT_COLUMN_WIDTH - 16.0, _avatar_height)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	# SIRA KİMDE: açık zemin + beyaz çerçeve + "SIRADA" etiketi (nabız gibi atar).
	# BEN: altın rengi isim + altın parıltı + "SEN" etiketi. İkisi birlikte olabilir.
	style.bg_color = Color(0.2, 0.22, 0.3, 0.98) if is_turn else Color(0.09, 0.1, 0.14, 0.94)
	style.set_corner_radius_all(8)
	style.border_width_left = 6
	style.border_color = color
	style.content_margin_left = 12
	style.content_margin_right = 8
	# Çok oyunculu ve alçak ekranda kart sıkışır: tek satır (sadece parti adı).
	var compact := _avatar_height < 42.0
	style.content_margin_top = 1 if compact else 4
	style.content_margin_bottom = 1 if compact else 4
	if is_self:
		style.shadow_color = Color(1.0, 0.82, 0.15, 0.55)
		style.shadow_size = 5
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var badge_size: float = clampf(_avatar_height - (6.0 if compact else 16.0), 18.0, 44.0)
	var badge := PartyBadge.build(party, Vector2(badge_size, badge_size), BADGE_ICON_PIXEL_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	info.add_child(_avatar_label(String(party.get("name", "?")), 14, Color(1.0, 0.85, 0.35) if is_self else Color.WHITE))
	if not compact:
		info.add_child(_avatar_label(_leader_name_of(peer_id) + ("  (Sen)" if is_self else ""), 11, Color(0.68, 0.72, 0.8)))
	if _avatar_height >= 58.0:
		var seats_text := ("%d vekil · " % int(CardManager.last_seats[peer_id])) if CardManager.last_seats.has(peer_id) else ""
		info.add_child(_avatar_label("%s%d mana" % [seats_text, CardManager.mana_of(peer_id)], 11, Color(0.6, 0.65, 0.75)))

	var populism_left := CardManager.populism_rounds_left(peer_id)
	if is_self or is_turn or populism_left > 0:
		var tags := VBoxContainer.new()
		tags.add_theme_constant_override("separation", 2)
		tags.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_turn:
			tags.add_child(_avatar_tag("SIRADA", Color(1, 1, 1), Color(0.1, 0.1, 0.12)))
		if is_self and not (is_turn and compact):
			tags.add_child(_avatar_tag("SEN", Color(1.0, 0.82, 0.2), Color(0.15, 0.1, 0.0)))
		if populism_left > 0 and not (compact and tags.get_child_count() >= 2):
			tags.add_child(_avatar_tag("POPÜLİZM %d" % populism_left, Color(0.85, 0.35, 0.75), Color.WHITE))
		row.add_child(tags)
	# Hangi oyuncuya ait olduğu düğümün ÜSTÜNDE saklanıyor: hover tespiti ve
	# tooltip konumu panelin çocuk SIRASINA güvenmez (bkz. _party_under_mouse).
	card.set_meta("peer_id", peer_id)
	# Oylama sırasında kartın sağında partinin oyu (ya da beklendiği) yazar.
	if GovernmentManager.is_voting() and GovernmentManager.eligible_voter_ids().has(peer_id):
		var voted: bool = GovernmentManager.votes.has(peer_id)
		var tag := _avatar_label(GovernmentManager.vote_text(GovernmentManager.votes[peer_id]) if voted else "…", 11,
			VOTE_COLORS[int(GovernmentManager.votes[peer_id])] if voted else Color(1, 1, 1, 0.6))
		tag.clip_text = false
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	# Vekil çalma hedefi vurgusu (bkz. _refresh_target_highlights).
	var halo := Panel.new()
	halo.name = "TargetHalo"
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var halo_style := StyleBoxFlat.new()
	halo_style.draw_center = false
	halo_style.set_border_width_all(3)
	halo_style.border_color = Color(1.0, 0.85, 0.3)
	halo_style.set_corner_radius_all(8)
	halo.add_theme_stylebox_override("panel", halo_style)
	halo.visible = false
	card.add_child(halo)
	if is_turn:
		var frame := Panel.new()
		frame.name = "TurnFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frame_style := StyleBoxFlat.new()
		frame_style.draw_center = false
		frame_style.set_border_width_all(2)
		frame_style.border_color = Color(1, 1, 1, 0.95)
		frame_style.set_corner_radius_all(8)
		frame.add_theme_stylebox_override("panel", frame_style)
		card.add_child(frame)
		var pulse := frame.create_tween().set_loops()
		pulse.tween_property(frame, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(frame, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	var wrap := card
	# Hedef seçme modunda (vekil çalma kartı) bu partiye tıklanabilir.
	wrap.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_target_party_clicked(peer_id)
	)
	return wrap

## peer_id'ye ait avatar düğümünü bulur (yoksa null). Silinmek üzere işaretli
## düğümleri atlar.
func _find_avatar_node(peer_id: int) -> Control:
	for child in player_panel_list.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var control := child as Control
		if control != null and control.get_meta("peer_id", -1) == peer_id:
			return control
	return null

## Parti kartına dokununca profil açılır; aynı karta tekrar dokununca kapanır.
func _toggle_profile(peer_id: int) -> void:
	if _profile_peer_id == peer_id:
		_hide_profile()
		return
	_profile_peer_id = peer_id
	_show_tooltip_for(peer_id)

func _hide_profile() -> void:
	_profile_peer_id = -1
	if hover_tooltip != null:
		hover_tooltip.hide()

func _avatar_tag(text: String, bg: Color, fg: Color) -> Control:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", fg)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	tag.add_theme_stylebox_override("normal", style)
	return tag

func _avatar_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Parti profili (bkz. PartyInfoCard): dokunulan oyuncu kartının soluna.
func _show_tooltip_for(peer_id: int) -> void:
	hover_tooltip_image.hide()
	for child in hover_tooltip.get_children():
		if child != hover_tooltip_image:
			child.queue_free()
	var card := PartyInfoCard.build(peer_id, multiplayer.get_unique_id())
	card.modulate.a = 0.0
	hover_tooltip.add_child(card)
	hover_tooltip.show()
	# Kapsayıcıların boyutu bir kare sonra kesinleşir; o zamana kadar görünmez.
	await get_tree().process_frame
	if _profile_peer_id != peer_id or not is_instance_valid(card):
		return
	card.reset_size()
	hover_tooltip.size = card.size
	card.modulate.a = 1.0

	# Profili, dokunulan kartın hemen soluna yerleştir.
	var avatar := _find_avatar_node(peer_id)
	if avatar != null:
		# Dikeyde avatarla ORTALA, yatayda avatarın soluna koy. Ekranın
		# üstünden/altından taşmasın diye viewport içine sıkıştırılıyor.
		var viewport_size := get_viewport_rect().size
		hover_tooltip.global_position = Vector2(
			avatar.global_position.x - hover_tooltip.size.x - 12.0,
			clampf(
				avatar.global_position.y + avatar.size.y * 0.5 - hover_tooltip.size.y * 0.5,
				8.0,
				maxf(8.0, viewport_size.y - hover_tooltip.size.y - 8.0)
			)
		)
	hover_tooltip.show()

# --- Hükümet / meclis oylaması ---------------------------------------------

## Vekil çalma kartıyla sandalye dağılımı değişti: parlamento, oy paneli,
## puan tablosu ve hükümet paneli hepsi bundan etkilenir.
func _on_seats_changed() -> void:
	_refresh_results_panels()
	_refresh_government_panel()
	_refresh_score_panel()

## Hükümet kurma görevi BENDEYSE görev dağıtım ekranına geçiyoruz; diğer
## oyuncular "Hükümet kuruluyor…" bekleme perdesini görüyor.
func _on_government_phase_changed() -> void:
	_refresh_vote_ui()
	_refresh_action_buttons()
	_refresh_government_panel()
	_refresh_waiting_overlay()
	_refresh_deck_button()
	_refresh_pass_button()
	_rebuild_hand()
	if _leaving_for_results:
		return  # önce seçim sonuçları oynasın (bkz. _on_election_completed)
	if GovernmentManager.phase == GovernmentManager.Phase.FORMING and GovernmentManager.is_my_mandate() \
			and not CardManager.game_finished:
		SceneTransition.fade_to_scene("res://scenes/GovernmentFormation.tscn")

## Görevli olmayan herkes, teklif meclise gelene kadar bu perdeyi görür.
func _refresh_waiting_overlay() -> void:
	var forming: bool = GovernmentManager.phase == GovernmentManager.Phase.FORMING
	# Seçim sonucu henüz gösterilmediyse (sonuç ekranına geçiliyor ya da seçim
	# gecesi payı sürüyor) perde görevli partiyi açık etmesin: spoiler.
	var results_pending: bool = _leaving_for_results 		or GovernmentManager.phase_seconds_left() > GameRules.FORMATION_TIMEOUT + 0.5
	_waiting_overlay.visible = forming and not GovernmentManager.is_my_mandate() and not results_pending
	if not _waiting_overlay.visible:
		return
	var holder: int = GovernmentManager.mandate_peer_id()
	if holder != _waiting_badge_holder:
		_waiting_badge_holder = holder
		for child in _waiting_badge_slot.get_children():
			child.queue_free()
		var badge := PartyBadge.build(PartyManager.parties.get(holder, {}), Vector2(96, 96), 192)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_waiting_badge_slot.add_child(badge)
		_waiting_badge_slot.position = Vector2(get_viewport_rect().size.x * 0.5 - 48.0, get_viewport_rect().size.y * 0.5 - 190.0)
	_waiting_label.text = "HÜKÜMET KURULUYOR\n\n%s (%s)\ngörev dağılımını hazırlıyor…\n\n%d. teklif hakkı  ·  Süre: %s" % [
		_party_name_of(holder),
		_leader_name_of(holder),
		GovernmentManager.current_attempt_number(),
		GameRules.format_seconds(GovernmentManager.phase_seconds_left()),
	]

func _build_waiting_overlay() -> void:
	_waiting_overlay = Control.new()
	_waiting_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_waiting_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_waiting_overlay.z_index = 120
	_waiting_overlay.hide()

	var backdrop := UiSkin.panel_background(UiSkin.PANEL_DARK)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.modulate = Color(1, 1, 1, 0.93)
	_waiting_overlay.add_child(backdrop)

	_waiting_badge_slot = CenterContainer.new()
	_waiting_badge_slot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_waiting_badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_waiting_overlay.add_child(_waiting_badge_slot)

	_waiting_label = Label.new()
	_waiting_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_waiting_label.add_theme_font_size_override("font_size", 20)
	_waiting_overlay.add_child(_waiting_label)

	add_child(_waiting_overlay)

func _on_vote_pressed(choice: int) -> void:
	GovernmentManager.cast_vote(choice)

## Oylama butonları: teklif yokken (ya da oyumu kullandıysam) GRİ ve
## tıklanamaz, oylama açıkken yeşil/kırmızı ve hover'lı. Hepsi PNG.
func _refresh_vote_ui() -> void:
	var can_vote: bool = GovernmentManager.is_voting() \
		and GovernmentManager.eligible_voter_ids().has(multiplayer.get_unique_id()) \
		and not GovernmentManager.has_voted(multiplayer.get_unique_id())

	vote_yes_button.disabled = not can_vote
	vote_no_button.disabled = not can_vote
	# Koalisyon teklifinde ortak çekimser kalamaz: ya EVET ya HAYIR.
	_abstain_button.disabled = not can_vote or GovernmentManager.is_coalition_stage()

	if can_vote:
		vote_yes_button.texture_normal = load("res://assets/ui/vote_yes_normal.png")
		vote_yes_button.texture_hover = load("res://assets/ui/vote_yes_hover.png")
		vote_yes_button.texture_pressed = load("res://assets/ui/vote_yes_pressed.png")
		vote_no_button.texture_normal = load("res://assets/ui/vote_no_normal.png")
		vote_no_button.texture_hover = load("res://assets/ui/vote_no_hover.png")
		vote_no_button.texture_pressed = load("res://assets/ui/vote_no_pressed.png")
	else:
		vote_yes_button.texture_normal = load("res://assets/ui/vote_yes_disabled.png")
		vote_yes_button.texture_hover = null
		vote_yes_button.texture_pressed = null
		vote_no_button.texture_normal = load("res://assets/ui/vote_no_disabled.png")
		vote_no_button.texture_hover = null
		vote_no_button.texture_pressed = null

	proposal_label.text = GovernmentHud.proposal_status_text(multiplayer.get_unique_id())

func _party_name_of(peer_id: int) -> String:
	return GovernmentHud.party_name_of(peer_id)

func _leader_name_of(peer_id: int) -> String:
	return GovernmentHud.leader_name_of(peer_id)

func _refresh_government_panel() -> void:
	GovernmentHud.fill_government_panel(government_vbox)

func _refresh_score_panel() -> void:
	GovernmentHud.fill_score_panel(score_vbox, _ordered_peer_ids(), multiplayer.get_unique_id())

# --- Hamleler: yasa tasarla, teşkilat, karalama hedefi -------------------

## Yasa dairesi sürüklenirken _drag_hand_index bu değeri alır (elde kart yok).
const LAW_DRAG_INDEX := -2
const MANA_COLOR := Color(0.55, 0.8, 1.0)
const MANA_ICON := preload("res://assets/icons/mana_icon.png")
const EMPTY_SEAT_COLOR := Color(0.95, 0.95, 0.95)
const LAW_AXIS_COLORS := {
	"economic": Color(0.85, 0.58, 0.14),
	"social": Color(0.6, 0.32, 0.78),
	"administrative": Color(0.16, 0.58, 0.64),
}

## Sağ sütunun alt kısmı (aşağıdan yukarı): sıra göstergesi, pas, deste ve
## yanında YASA TASARLA / İL BAŞKANLIĞI butonları, mana. Parti kartları üstte
## kalan alana sığar.
func _place_right_column_controls() -> void:
	# Alt sağ: 6 hamle butonu (2 sütun x 3 satır), altında küçük deste + mana + Turu Bitir.
	deck_button.ignore_texture_size = true
	deck_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	deck_button.offset_left = -196.0
	deck_button.offset_right = -140.0
	deck_button.offset_top = -182.0
	deck_button.offset_bottom = -106.0
	_sync_shadow(_deck_shadow, deck_button)
	pass_button.add_theme_font_size_override("font_size", 14)
	var panel := player_panel_list.get_parent() as Control
	if panel != null:
		panel.offset_top = 72.0  # sağ üstte Menü butonu var
		panel.offset_bottom = -302.0  # altında deste ve hamle butonları
	pass_button.offset_left = -134.0
	pass_button.offset_top = -140.0

func _build_action_buttons() -> void:
	# Mana göstergesi: pas butonunun solunda simge + sayı. Dokununca kurallar.
	_mana_box = HBoxContainer.new()
	_mana_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mana_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_mana_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mana_box.offset_left = -134.0
	_mana_box.offset_right = -16.0
	_mana_box.offset_top = -182.0
	_mana_box.offset_bottom = -146.0
	_mana_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_mana_box.add_theme_constant_override("separation", 4)
	_mana_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_mana_box.tooltip_text = "Mana"
	var mana_icon := TextureRect.new()
	mana_icon.texture = MANA_ICON
	mana_icon.custom_minimum_size = Vector2(28, 28)
	mana_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mana_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mana_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mana_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mana_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mana_box.add_child(mana_icon)
	_mana_label = Label.new()
	_mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mana_label.add_theme_font_size_override("font_size", 22)
	_mana_label.add_theme_color_override("font_color", MANA_COLOR)
	_mana_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_mana_label.add_theme_constant_override("outline_size", 5)
	_mana_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mana_box.add_child(_mana_label)
	_mana_box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_toast(_mana_rules))
	_mana_rules = "Sıran gelince +%d mana; manan yettikçe istediğin kadar hamle yap, biriken mana kalır.\nHamleler: yasa BEDAVA (turda 1), miting %d, teşkilat %d (seviye başına), yatırım %d, gensoru %d mana.\nKart çekmek bedava (turda 1), kart oynamak sınırsız. Kartlar bonus: karalama %d, vekil çalma %d/%d, kaset %d, isyan %d, popülizm %d, mana bonusu %d.\nTur kendiliğinden bitmez: \"Turu Bitir\"e bas. Seçimden sonra herkese +%d kart ve +%d mana, yeni hükümete +%d mana." % [
		GameRules.MANA_PER_ROUND, GameRules.MITING_MANA_COST, GameRules.ORG_MANA_COST,
		GameRules.INVEST_MANA_COST, GameRules.CENSURE_MANA_COST,
		CardPresets.card_cost("karalama"), CardPresets.card_cost("steal_weak"), CardPresets.card_cost("steal_strong"),
		CardPresets.card_cost("kaset"), CardPresets.card_cost("isyan"),
		CardPresets.card_cost("populizm"), CardPresets.card_cost("mana_bonusu"),
		1, GameRules.ELECTION_MANA_BONUS, GameRules.GOVERNMENT_MANA_BONUS]
	add_child(_mana_box)
	# HAMLELER (sağ sütun, destenin yanında alt alta). Kartlar bonus niteliğinde.
	_law_button = _action_button("YASA", "bedava", Color(0.42, 0.26, 0.62), -292.0, 0)
	_law_button.pressed.connect(_on_law_button_pressed)
	_miting_button = _action_button("MİTİNG", "%d mana" % GameRules.MITING_MANA_COST, Color(0.72, 0.3, 0.14), -292.0, 1)
	_miting_button.pressed.connect(_on_miting_button_pressed)
	_org_button = _action_button("TEŞKİLATLANMA", "%d mana" % GameRules.ORG_MANA_COST, Color(0.1, 0.44, 0.48), -256.0, 0)
	_org_button.pressed.connect(_on_org_button_pressed)
	_invest_button = _action_button("YATIRIM", "%d mana" % GameRules.INVEST_MANA_COST, Color(0.2, 0.5, 0.22), -256.0, 1)
	_invest_button.pressed.connect(_on_invest_button_pressed)
	_censure_button = _action_button("GENSORU", "%d mana" % GameRules.CENSURE_MANA_COST, Color(0.6, 0.16, 0.2), -220.0, 0)
	_censure_button.pressed.connect(_on_censure_button_pressed)

## column: 0 sol, 1 sağ (sağ sütunda iki sütunlu ızgara).
func _action_button(title: String, cost_text: String, color: Color, top: float, column: int) -> Button:
	var button := Button.new()
	button.text = "%s\n%s" % [title, cost_text]
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_left = -196.0 if column == 0 else -104.0
	button.offset_right = -108.0 if column == 0 else -16.0
	button.offset_top = top
	button.offset_bottom = top + 32.0
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_constant_override("line_spacing", -3)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.set_border_width_all(2)
		style.bg_color = color
		style.border_color = Color(1, 1, 1, 0.3)
		if state == "hover" or state == "focus":
			style.bg_color = color.lightened(0.15)
		elif state == "pressed":
			style.bg_color = color.darkened(0.2)
		elif state == "disabled":
			style.bg_color = Color(0.18, 0.19, 0.23)
			style.border_color = Color(1, 1, 1, 0.08)
		button.add_theme_stylebox_override(state, style)
	add_child(button)
	return button

## Neden şu an bu hamle yapılamıyor? (Buton ipucu ve uyarı yazısı.)
func _action_block_reason(cost: int, is_law: bool = false) -> String:
	var me := multiplayer.get_unique_id()
	if is_law and CardManager.last_seats.is_empty():
		return "İlk seçime kadar meclis yok: yasa yapılamaz."
	if is_law and not CardManager.has_seats(me):
		return "Mecliste vekilin yok: yasa teklif edemezsin."
	if is_law and CardManager.agenda_type() == "":
		return "Gündem yok: yasa sadece gündemdeki eksende sunulabilir."
	if not CardManager.can_act():
		return "Sıran değil."
	if is_law and CardManager.has_proposed_law_this_round(me):
		return "Bu tur zaten bir yasa sundun (turda 1 yasa)."
	if CardManager.mana_of(me) < cost:
		return "Manan yetmiyor (%d gerekli)." % cost
	return "Şu an yapılamaz."

func _refresh_action_buttons() -> void:
	if _law_button == null:
		return
	var me := multiplayer.get_unique_id()
	var mana_now := CardManager.mana_of(me)
	_mana_label.text = str(mana_now)
	var law_ok := CardManager.can_propose_law(me)
	var org_ok := CardManager.can_choose_main_action(me) and mana_now >= GameRules.ORG_MANA_COST
	var miting_ok := CardManager.can_miting(me)
	_miting_button.modulate.a = 1.0 if miting_ok or _pending_miting else 0.45
	_invest_button.modulate.a = 1.0 if CardManager.can_invest(me) or _pending_invest else 0.45
	_censure_button.modulate.a = 1.0 if CardManager.can_censure(me) or _pending_censure else 0.45
	# disabled kullanılmıyor: pasif butona dokununca neden olmadığı uyarı olarak çıksın.
	_law_button.modulate.a = 1.0 if law_ok else 0.45
	_org_button.modulate.a = 1.0 if org_ok or _pending_org else 0.45

func _build_agenda_banner() -> void:
	_agenda_banner = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.14, 0.05, 0.92)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.7, 0.3, 0.9)
	style.set_content_margin_all(8)
	_agenda_banner.add_theme_stylebox_override("panel", style)
	_agenda_banner.z_index = 6
	_agenda_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_agenda_label = Label.new()
	_agenda_label.add_theme_font_size_override("font_size", 13)
	_agenda_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_agenda_banner.add_child(_agenda_label)
	add_child(_agenda_banner)
	_refresh_agenda_banner()

## Gündem varken haritanın sağ üstünde konu, etkisi ve kalan tur yazar.
func _refresh_agenda_banner() -> void:
	if _agenda_banner == null:
		return
	var current := CardManager.agenda_type()
	_agenda_banner.visible = current != ""
	if current == "":
		return
	var data := CardPresets.agenda_data(current)
	_agenda_label.text = "GÜNDEM %d/%d  ·  %s\n%s" % [int(CardManager.agenda.get("index", 1)), GameRules.AGENDA_ROUNDS,
		data["title"], CardPresets.agenda_effect_text(current)]
	_agenda_banner.reset_size()
	var viewport_size := get_viewport_rect().size
	_agenda_banner.position = Vector2(viewport_size.x - RIGHT_COLUMN_WIDTH - _agenda_banner.size.x - 24.0, 16.0)

func _build_law_designer() -> void:
	_law_designer = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.62, 0.45, 0.9, 0.8)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	_law_designer.add_theme_stylebox_override("panel", style)
	_law_designer.z_index = 108
	_law_designer.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_law_designer.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "YASA TEKLİFİ"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "Kapat"
	UiSkin.skin_button(close)
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(func(): _law_designer.hide())
	header.add_child(close)
	# Kazanç satırı: kabul edilirse puan, bedel.
	_law_points_label = Label.new()
	_law_points_label.add_theme_font_size_override("font_size", 11)
	_law_points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_law_points_label.custom_minimum_size = Vector2(240, 0)
	_law_points_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	box.add_child(_law_points_label)
	# Gündem şeridi.
	_law_agenda_label = Label.new()
	_law_agenda_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_law_agenda_label.custom_minimum_size = Vector2(240, 0)
	_law_agenda_label.add_theme_font_size_override("font_size", 11)
	_law_agenda_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
	box.add_child(_law_agenda_label)
	_law_rows = VBoxContainer.new()
	_law_rows.add_theme_constant_override("separation", 3)
	box.add_child(_law_rows)
	var hint := Label.new()
	hint.text = "Daireyi meclise sürükle. Yakın illerde güç kazandırır, zıt illerde kaybettirir."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(240, 0)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	box.add_child(hint)
	_law_info = Label.new()
	_law_info.text = "Bir daireye dokun: ne yaptığı burada yazar."
	_law_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_law_info.custom_minimum_size = Vector2(240, 0)
	_law_info.add_theme_font_size_override("font_size", 10)
	_law_info.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(_law_info)
	_law_designer.hide()
	add_child(_law_designer)

## Yasa panelinin değişen kısımları: puan, gündem, her eksende partinin yeri
## ve gündem çarpanı rozetleri. Panel her açılışta tazelenir.
func _refresh_law_designer() -> void:
	var me := multiplayer.get_unique_id()
	var in_gov := CardManager.is_government_party(me)
	_law_points_label.text = "Kabul: +%d puan%s · %d mana" % [
		CardManager.law_pass_score(in_gov), "" if in_gov else " (hükümette +%d)" % GameRules.LAW_PASS_SCORE_GOV,
		GameRules.LAW_MANA_COST]
	var current := CardManager.agenda_type()
	if current == "":
		_law_agenda_label.text = "Gündem yok: bu tur yasa sunulamaz."
	else:
		var data := CardPresets.agenda_data(current)
		_law_agenda_label.text = "Gündem: %s — sadece %s yasaları" % [data["title"], data["axis_title"]]
	for child in _law_rows.get_children():
		child.queue_free()
	var ideology: Dictionary = PartyManager.parties.get(me, {}).get("ideology", {})
	for axis in IdeologyAxes.AXES:
		var info: Dictionary = CardPresets.AXIS_TITLES[axis]
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		row.add_child(_law_circle(axis, -1))
		var middle := VBoxContainer.new()
		middle.alignment = BoxContainer.ALIGNMENT_CENTER
		middle.add_theme_constant_override("separation", 0)
		middle.custom_minimum_size = Vector2(110, 0)
		var axis_label := Label.new()
		axis_label.text = String(info["title"]).to_upper()
		axis_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		axis_label.add_theme_font_size_override("font_size", 10)
		axis_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		middle.add_child(axis_label)
		middle.add_child(_ideology_bar(axis, float(ideology.get(axis, 0))))
		var pos_label := Label.new()
		pos_label.text = "partin: %s" % IdeologyAxes.format_value(float(ideology.get(axis, 0)))
		pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pos_label.add_theme_font_size_override("font_size", 9)
		pos_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		middle.add_child(pos_label)
		row.add_child(middle)
		row.add_child(_law_circle(axis, 1))
		_law_rows.add_child(row)

## Eksende partinin yeri: −3..+3 çubuğu ve üstünde işaret.
func _ideology_bar(axis: String, value: float) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(110, 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := _law_color(axis, -1)
	var right := _law_color(axis, 1)
	var mine: Color = PartyManager.parties.get(multiplayer.get_unique_id(), {}).get("bg_color", Color.WHITE)
	bar.draw.connect(func():
		var w := bar.size.x
		var y := bar.size.y * 0.5
		var steps := 24
		for i in steps:
			var x0 := w * i / steps
			var x1 := w * (i + 1) / steps
			bar.draw_rect(Rect2(x0, y - 2.0, x1 - x0 + 0.5, 4.0), left.lerp(right, float(i) / (steps - 1)))
		bar.draw_line(Vector2(w * 0.5, y - 6.0), Vector2(w * 0.5, y + 6.0), Color(1, 1, 1, 0.5), 1.0)
		var x := w * (clampf(value, IdeologyAxes.AXIS_MIN, IdeologyAxes.AXIS_MAX) - IdeologyAxes.AXIS_MIN) \
			/ (IdeologyAxes.AXIS_MAX - IdeologyAxes.AXIS_MIN)
		bar.draw_circle(Vector2(x, y), 5.5, Color.BLACK, true, -1.0, true)
		bar.draw_circle(Vector2(x, y), 4.0, mine, true, -1.0, true))
	return bar

func _law_color(axis: String, dir: int) -> Color:
	var base: Color = LAW_AXIS_COLORS.get(axis, Color.GRAY)
	return base.darkened(0.3) if dir < 0 else base.lightened(0.08)

## Sürüklenebilir yasa dairesi (bir eksenin bir ucu).
func _law_circle(axis: String, dir: int) -> Control:
	var law_type := CardPresets.law_type(axis, dir)
	var law := CardPresets.law_data(law_type)
	var circle := Panel.new()
	circle.custom_minimum_size = Vector2(54, 54)
	var on_agenda := CardManager.law_on_agenda(law_type)
	if not on_agenda:
		circle.modulate = Color(1, 1, 1, 0.3)  # gündemde değil: sunulamaz
	var style := StyleBoxFlat.new()
	style.bg_color = _law_color(axis, dir)
	style.set_corner_radius_all(27)
	style.set_border_width_all(3 if on_agenda else 2)
	style.border_color = Color(1.0, 0.72, 0.3) if on_agenda else Color(1, 1, 1, 0.55)
	circle.add_theme_stylebox_override("panel", style)
	circle.mouse_filter = Control.MOUSE_FILTER_STOP
	circle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var label := Label.new()
	label.text = String(law["side"])
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.add_child(label)
	if on_agenda:
		label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	circle.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_law_info.text = "%s (%s)%s" % [law["title"], CardPresets.law_direction_text(law_type),
					"  ·  gündemde: sunulabilir" if on_agenda else "  ·  gündemde değil"]
				_start_law_drag(law_type)
			elif _drag_hand_index == LAW_DRAG_INDEX:
				_finish_drag()
	)
	return circle

func _start_law_drag(law_type: String) -> void:
	var current := CardManager.agenda_type()
	if current != "" and CardPresets.law_data(law_type)["axis"] != CardPresets.agenda_data(current)["axis"]:
		_show_toast("Bu eksen gündemde değil: bu tur sadece %s yasaları sunulabilir." % CardPresets.agenda_data(current)["axis_title"])
		return
	if not CardManager.can_propose_law(multiplayer.get_unique_id(), law_type):
		_show_toast(_action_block_reason(GameRules.LAW_MANA_COST, true))
		return
	_start_drag(LAW_DRAG_INDEX, law_type, null)

func _circle_texture(color: Color) -> Texture2D:
	var key := color.to_html()
	if _circle_textures.has(key):
		return _circle_textures[key]
	var size := 64
	var radius := size * 0.5
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			if d <= radius - 1.0:
				image.set_pixel(x, y, color if d < radius - 4.0 else Color(1, 1, 1, 0.8))
	var texture := ImageTexture.create_from_image(image)
	_circle_textures[key] = texture
	return texture

func _on_law_button_pressed() -> void:
	_deselect_hand_card()
	if not _law_designer.visible and not CardManager.can_propose_law(multiplayer.get_unique_id()):
		_show_toast(_action_block_reason(GameRules.LAW_MANA_COST, true) + " (Panel yine de açılır: yasaları incele.)")
	if _law_designer.visible:
		_law_designer.hide()
		return
	_refresh_law_designer()
	_law_designer.show()
	_law_designer.reset_size()
	await get_tree().process_frame
	var viewport_size := get_viewport_rect().size
	_law_designer.position = Vector2(
		viewport_size.x - RIGHT_COLUMN_WIDTH - _law_designer.size.x - 12.0,
		maxf(12.0, viewport_size.y * TOP_AREA_HEIGHT_RATIO - _law_designer.size.y))

func _invest_block_reason() -> String:
	if CardManager.can_act() and not CardManager.is_government_party(multiplayer.get_unique_id()):
		return "Yatırımı sadece hükümet partileri yapabilir."
	return _action_block_reason(GameRules.INVEST_MANA_COST)

## Yatırım hamlesi: haritadan il seçilir (ilk dokunuş ayrıntı, ikincisi yapar).
func _on_invest_button_pressed() -> void:
	if _pending_invest:
		_cancel_targeting()
		return
	var me := multiplayer.get_unique_id()
	_deselect_hand_card()
	_law_designer.hide()
	_cancel_targeting()
	if not CardManager.can_invest(me):
		_show_toast(_invest_block_reason())
		return
	_pending_invest = true
	if _province_panel != null:
		_province_panel.hide()
	_refresh_action_buttons()
	_set_target_hint("Yatırım: haritada bir ile dokun, tekrar dokun: yatırım yap (%d mana)  ·  Butona tekrar dokun: iptal" % GameRules.INVEST_MANA_COST)

## Gensoru hamlesi: sadece hükümet azınlıktayken muhalefete açık. İlk dokunuş
## onay ister, ikinci dokunuş meclis oylamasını başlatır.
func _on_censure_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if _pending_censure:
		_cancel_targeting()
		if CardManager.can_censure(me):
			CardManager.censure()
		return
	_deselect_hand_card()
	_law_designer.hide()
	_cancel_targeting()
	if not CardManager.can_censure(me):
		if not CardManager.can_act():
			_show_toast("Sıran değil.")
		elif not GovernmentManager.has_government():
			_show_toast("Görevde bir hükümet yok.")
		elif not CardManager.has_seats(me):
			_show_toast("Mecliste vekilin yok: gensoru veremezsin.")
		elif CardManager.is_government_party(me):
			_show_toast("Hükümetteki parti gensoru veremez.")
		elif GovernmentManager.has_majority():
			_show_toast("Gensoru sadece hükümet azınlıktayken verilebilir (salt çoğunluğu yok).")
		else:
			_show_toast(_action_block_reason(GameRules.CENSURE_MANA_COST))
		return
	_pending_censure = true
	_refresh_action_buttons()
	_set_target_hint("Gensoru: hükümeti düşürmek için meclis oylaması (%d mana). Reddedilirse ulusal destek kaybedersin. Onay: butona tekrar dokun" % GameRules.CENSURE_MANA_COST)

## Miting hamlesi: haritadan il seçilir (ilk dokunuş riski gösterir, ikincisi yapar).
func _on_miting_button_pressed() -> void:
	if _pending_miting:
		_cancel_targeting()
		return
	var me := multiplayer.get_unique_id()
	_deselect_hand_card()
	_law_designer.hide()
	if _pending_org or _pending_invest or _pending_censure or _pending_province_hand_index != -1:
		_cancel_targeting()
	if not CardManager.can_miting(me):
		_show_toast(_action_block_reason(GameRules.MITING_MANA_COST))
		return
	_pending_miting = true
	if _province_panel != null:
		_province_panel.hide()
	_refresh_action_buttons()
	_set_target_hint("Miting: haritada bir ile dokun (risk görünür), tekrar dokun: miting yap (%d mana)  ·  Butona tekrar dokun: iptal" % GameRules.MITING_MANA_COST)

# --- Harita katmanları ---------------------------------------------------------

func _ensure_map_clip() -> void:
	if _map_clip != null:
		return
	_map_clip = Control.new()
	_map_clip.name = "MapClip"
	_map_clip.clip_contents = true
	_map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_clip)
	move_child(_map_clip, map_holder.get_index())
	map_holder.reparent(_map_clip, false)
	_map_snapshot = TextureRect.new()
	_map_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_snapshot.stretch_mode = TextureRect.STRETCH_SCALE
	_map_snapshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_snapshot.hide()
	_map_clip.add_child(_map_snapshot)
	_build_layer_bar()

func _build_layer_bar() -> void:
	_layer_bar = HBoxContainer.new()
	_layer_bar.add_theme_constant_override("separation", 0)
	_layer_bar.z_index = 5
	add_child(_layer_bar)
	for i in MAP_LAYER_TITLES.size():
		var button := Button.new()
		button.text = MAP_LAYER_TITLES[i]
		button.custom_minimum_size = Vector2(84, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_layer_button_pressed.bind(i))
		_layer_bar.add_child(button)
		_layer_buttons.append(button)
	_layer_legend = HBoxContainer.new()
	_layer_legend.z_index = 5
	(_layer_legend as HBoxContainer).add_theme_constant_override("separation", 4)
	_layer_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer_legend)
	_refresh_layer_bar()

func _place_layer_bar() -> void:
	if _layer_bar == null:
		return
	_layer_bar.reset_size()
	var rect := Rect2(_map_clip.position, _map_clip.size)
	_layer_bar.position = Vector2(rect.position.x + 18.0, rect.end.y - _layer_bar.size.y - 16.0)
	_layer_legend.reset_size()
	_layer_legend.position = Vector2(_layer_bar.position.x + 4.0, _layer_bar.position.y - _layer_legend.size.y - 6.0)

func _layer_button_style(color: Color, left: bool, right: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_border_width_all(1)
	style.border_color = Color(0, 0, 0, 0.55)
	style.corner_radius_top_left = 9 if left else 0
	style.corner_radius_bottom_left = 9 if left else 0
	style.corner_radius_top_right = 9 if right else 0
	style.corner_radius_bottom_right = 9 if right else 0
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style

func _refresh_layer_bar() -> void:
	for i in _layer_buttons.size():
		var button: Button = _layer_buttons[i]
		var active := i == _map_layer
		var color := Color(0.95, 0.8, 0.3) if active else Color(0.1, 0.11, 0.15, 0.9)
		var first := i == 0
		var last := i == _layer_buttons.size() - 1
		for state in ["normal", "hover", "pressed", "focus"]:
			var c := color.lightened(0.08) if state == "hover" and not active else color
			button.add_theme_stylebox_override(state, _layer_button_style(c, first, last))
		button.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02) if active else Color(1, 1, 1, 0.85))
		button.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02) if active else Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color(0.1, 0.08, 0.02))
	_rebuild_layer_legend()

## Katmanın küçük açıklaması (renk anahtarı), butonların hemen üstünde.
func _rebuild_layer_legend() -> void:
	for child in _layer_legend.get_children():
		child.queue_free()
	var mine: Color = PartyManager.parties.get(multiplayer.get_unique_id(), {}).get("bg_color", Color(0.5, 0.5, 0.5))
	var swatches: Array = []
	match _map_layer:
		MapLayer.ORGANIZATION:
			for level in GameRules.ORG_MAX_LEVEL + 1:
				swatches.append([MAP_BLANK_COLOR.lerp(mine, float(level) / GameRules.ORG_MAX_LEVEL), str(level)])
			swatches.append([null, "teşkilat seviyem"])
		MapLayer.STRENGTH:
			swatches.append([null, "vekil yok"])
			for i in STRENGTH_STOPS.size():
				swatches.append([STRENGTH_STOPS[i], ""])
			swatches.append([null, "ilin yarısı"])
	_layer_legend.visible = not swatches.is_empty()
	for entry in swatches:
		if entry[0] == null:
			var label := Label.new()
			label.text = String(entry[1])
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 4)
			_layer_legend.add_child(label)
			continue
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(22, 16)
		var style := StyleBoxFlat.new()
		style.bg_color = entry[0]
		style.set_corner_radius_all(3)
		style.set_border_width_all(1)
		style.border_color = Color(0, 0, 0, 0.6)
		swatch.add_theme_stylebox_override("panel", style)
		if String(entry[1]) != "":
			var num := Label.new()
			num.text = String(entry[1])
			num.set_anchors_preset(Control.PRESET_FULL_RECT)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			num.add_theme_font_size_override("font_size", 11)
			num.add_theme_color_override("font_color", Color.BLACK if (entry[0] as Color).get_luminance() > 0.5 else Color.WHITE)
			swatch.add_child(num)
		_layer_legend.add_child(swatch)
	if _map_clip != null:
		_place_layer_bar.call_deferred()

func _on_layer_button_pressed(layer: int) -> void:
	if _pending_org:
		# Teşkilat seçimi sürerken başka katmana geçmek seçimi iptal eder.
		_pending_org = false
		_layer_before_org = -1
		_selected_province = ""
		_highlight_province("")
		_set_target_hint("")
		_refresh_action_buttons()
	_org_view_token += 1
	_layer_before_org = -1
	_set_map_layer(layer)

## Katmana göre il renkleri. Vurgulu il (seçim modu) koyulaştırılmış kalır.
func _apply_map_layer_colors() -> void:
	if map_holder == null:
		return
	var me := multiplayer.get_unique_id()
	var mine: Color = PartyManager.parties.get(me, {}).get("bg_color", Color(0.5, 0.5, 0.5))
	mine.a = 1.0
	var colors := {}
	if _map_layer == MapLayer.SEATS:
		colors = _seat_layer_colors.duplicate()
	else:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		gradient.colors = PackedColorArray(STRENGTH_STOPS)
		var projection: Dictionary = CardManager.projection_all() if _map_layer == MapLayer.STRENGTH else {}
		for province_id in map_holder.get_all_province_ids():
			match _map_layer:
				MapLayer.ORGANIZATION:
					colors[province_id] = MAP_BLANK_COLOR.lerp(mine, float(CardManager.organization_level(province_id, me)) / GameRules.ORG_MAX_LEVEL)
				MapLayer.STRENGTH:
					if projection.has(province_id):
						colors[province_id] = gradient.sample((_strength_t(projection[province_id], me) + 1.0) * 0.5)
					else:
						colors[province_id] = MAP_UNKNOWN_COLOR
	_province_base_colors = colors
	map_holder.clear_overlay()
	map_holder.set_province_colors(colors)
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.visible = _map_layer == MapLayer.SEATS
	if _hovered_province_id != "":
		var selected := _hovered_province_id
		_hovered_province_id = ""
		_highlight_province(selected)

## Güç katmanı: TÜM partilerin gücüyle, şimdi seçim olsa bu ilde durumum.
## −1 (kırmızı) .. +1 (koyu yeşil). Vekil çıkaramıyorsam en fazla sarıya yakın
## turuncu (bir vekile ne kadar yakın olduğuma göre); vekil çıkarıyorsam sarı
## yeşilden, ilin vekillerinin yarısını alıyorsam koyu yeşile.
func _strength_t(entry: Dictionary, me: int) -> float:
	if entry.is_empty() or not entry.has(me):
		return -1.0
	var mine: Dictionary = entry[me]
	var seat_count := maxi(1, int(entry.get("seat_count", 1)))
	var won := int(mine["seats"])
	var quotient := float(mine["quotient"])
	# Sürekli ölçü: oy / son kazanan bölüm ≈ "kesirli vekil". Böylece miting,
	# yatırım gibi her hamle vekil sayısı değişmese de rengi kaydırır.
	var fractional := float(mine["percent"]) / quotient if quotient > 0.0 and quotient < INF else 0.0
	if won <= 0:
		return -1.0 + 0.85 * clampf(fractional, 0.0, 1.0)
	return 0.2 + 0.8 * clampf(maxf(float(won), fractional) / float(seat_count) / 0.5, 0.0, 1.0)

## Katmanı değiştirir: eski görünümün anlık görüntüsü bir yana, yeni katman
## öbür yandan kayarak gelir (sağdaki katman sağdan, soldaki soldan).
func _set_map_layer(layer: int, animate: bool = true) -> void:
	if layer == _map_layer or _layer_switching:
		if _layer_switching:
			_queued_layer = layer
		return
	var direction := 1.0 if layer > _map_layer else -1.0
	var snapshot: Image = null
	if animate and _map_clip != null and DisplayServer.get_name() != "headless":
		# Anlık görüntüde katman butonları ve açıklama olmasın (onlar kaymaz):
		# bir kare gizlenip çizim bitince yakalanır.
		_layer_switching = true
		_layer_bar.modulate.a = 0.0
		_layer_legend.modulate.a = 0.0
		if _map_snapshot.visible:
			map_holder.position = Vector2.ZERO
			_map_snapshot.hide()
		# İki kare bekle: gizli butonlarla en az bir kare çizilmiş olsun.
		await get_tree().process_frame
		await get_tree().process_frame
		_layer_bar.modulate.a = 1.0
		_layer_legend.modulate.a = 1.0
		_layer_switching = false
		if not is_inside_tree():
			return
		var full := get_viewport().get_texture().get_image()
		if full != null:
			var to_pixels := get_viewport().get_final_transform()
			var pixel_rect := Rect2i((to_pixels * Rect2(_map_clip.global_position, _map_clip.size)).abs())
			pixel_rect = pixel_rect.intersection(Rect2i(Vector2i.ZERO, full.get_size()))
			if pixel_rect.has_area():
				snapshot = full.get_region(pixel_rect)
	_map_layer = layer
	_apply_map_layer_colors()
	_refresh_layer_bar()
	if snapshot == null:
		return
	if _map_slide_tween != null and _map_slide_tween.is_running():
		_map_slide_tween.kill()
	var width := _map_clip.size.x
	_map_snapshot.texture = ImageTexture.create_from_image(snapshot)
	_map_snapshot.position = Vector2.ZERO
	_map_snapshot.size = _map_clip.size
	_map_snapshot.show()
	_map_clip.move_child(_map_snapshot, _map_clip.get_child_count() - 1)
	map_holder.position = Vector2(width * direction, 0.0)
	_map_slide_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_map_slide_tween.tween_property(_map_snapshot, "position:x", -width * direction, MAP_SLIDE_DURATION)
	_map_slide_tween.tween_property(map_holder, "position:x", 0.0, MAP_SLIDE_DURATION)
	_map_slide_tween.chain().tween_callback(func():
		_map_snapshot.hide()
		_map_snapshot.texture = null
		map_holder.position = Vector2.ZERO)
	if _queued_layer != -1:
		var queued := _queued_layer
		_queued_layer = -1
		_set_map_layer(queued)

func _begin_org_view() -> void:
	_org_view_token += 1
	if _layer_before_org == -1:
		_layer_before_org = _map_layer
	_set_map_layer(MapLayer.ORGANIZATION)

func _end_org_view() -> void:
	if _layer_before_org == -1:
		return
	var previous := _layer_before_org
	_layer_before_org = -1
	_set_map_layer(previous)

## Teşkilatlanma: harita anında teşkilat katmanına geçer, il seçilir. Butona
## tekrar basmak iptal eder (mana harcanmaz); her iki durumda da harita önceki
## katmanına döner.
func _on_org_button_pressed() -> void:
	if _pending_org:
		_cancel_targeting()
		return
	var me := multiplayer.get_unique_id()
	_deselect_hand_card()
	_law_designer.hide()
	if _pending_miting or _pending_invest or _pending_censure or _pending_province_hand_index != -1:
		_cancel_targeting()
	if not CardManager.can_choose_main_action(me) or CardManager.mana_of(me) < GameRules.ORG_MANA_COST:
		_show_toast(_action_block_reason(GameRules.ORG_MANA_COST))
		return
	_pending_org = true
	if _province_panel != null:
		_province_panel.hide()
	_begin_org_view()
	_refresh_action_buttons()
	_set_target_hint("Teşkilatlanma: bir ile dokun, tekrar dokun: kur / geliştir (%d mana)  ·  Butona tekrar dokun: iptal" % GameRules.ORG_MANA_COST)

## Teşkilat seviyesinin getirdikleri (kısa).
static func _org_level_text(level: int) -> String:
	match level:
		1:
			return "az oy bonusu, ilin görüşü"
		2:
			return "orta oy bonusu, orta isabetli anket"
		3:
			return "yüksek oy bonusu, yüksek isabetli anket"
	return ""

func _build_propaganda_menu() -> void:
	_propaganda_menu = PanelContainer.new()
	UiSkin.skin_panel(_propaganda_menu, UiSkin.PANEL_DARK)
	_propaganda_menu.z_index = 112
	_propaganda_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_propaganda_menu.hide()
	add_child(_propaganda_menu)

## Karalama kartı bir ile bırakıldı: hedef parti seçtirilir, sonra oynanır.
func _ask_propaganda_target(hand_index: int, province_id: String) -> void:
	for child in _propaganda_menu.get_children():
		child.queue_free()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_propaganda_menu.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := Label.new()
	title.text = "%s: kimi karalayacaksın?" % ElectionNightSim.province_name(province_id)
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	var me := multiplayer.get_unique_id()
	for peer_id in _ordered_peer_ids():
		if peer_id == me:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var badge := PartyBadge.build(PartyManager.parties.get(peer_id, {}), Vector2(34, 34), BADGE_ICON_PIXEL_SIZE)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var button := Button.new()
		UiSkin.skin_button(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s  (%s)" % [_party_name_of(peer_id), _leader_name_of(peer_id)]
		button.pressed.connect(func():
			_propaganda_menu.hide()
			CardManager.play_card(hand_index, peer_id, province_id))
		row.add_child(button)
		box.add_child(row)
	var cancel := Button.new()
	UiSkin.skin_button(cancel)
	cancel.text = "İptal"
	cancel.pressed.connect(func(): _propaganda_menu.hide())
	box.add_child(cancel)
	var mouse := get_viewport().get_mouse_position()
	_propaganda_menu.show()
	await get_tree().process_frame
	_propaganda_menu.reset_size()
	var viewport_size := get_viewport_rect().size
	_propaganda_menu.position = Vector2(
		clampf(mouse.x + 12.0, 8.0, maxf(8.0, viewport_size.x - _propaganda_menu.size.x - 8.0)),
		clampf(mouse.y + 12.0, 8.0, maxf(8.0, viewport_size.y - _propaganda_menu.size.y - 8.0)))
