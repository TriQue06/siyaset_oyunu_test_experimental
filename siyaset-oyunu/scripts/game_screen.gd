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
## Parti profil kartının (politic_profile.png, 77x53) büyütme katı. TAM SAYI
## olmalı — pixel-art keskinliği ancak tam sayı katlarda korunur.
const PROFILE_CARD_SCALE := 3
## Fare bu kadar kaydırılırsa tık değil SÜRÜKLEME başlar.
const TAP_MAX_MOVE_PX := 10.0
## Oylamada parlamento koltuklarının ve profil etiketlerinin rengi.
const VOTE_COLORS := {1: Color(0.32, 0.82, 0.38), 0: Color(0.92, 0.78, 0.3), -1: Color(0.92, 0.3, 0.3)}

const SHADOW_OFFSET := Vector2(4, 5)
const SHADOW_COLOR := Color(0, 0, 0, 0.38)

const DRAW_FLY_DURATION := 0.16   # deste -> ekran ortası (hızlı)
const DRAW_SETTLE_DURATION := 0.16  # ekran ortası -> el'deki yeni yeri
const DRAW_HOLD_DURATION := 0.10
const PLAY_FLY_DURATION := 0.22   # el/avatar -> ekran ortası
const PLAY_POP_DURATION := 0.18   # ortada küçülüp "puf" kaybolma

@onready var map_holder: Node2D = %MapHolder
@onready var deck_button: TextureButton = %DeckButton
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

var _hovered_peer_id: int = -1
var _hand_holders: Array = [] # Array[Control], hover-kaldirma animasyonu icin (her biri bir kartin "holder"i)
var _hovered_province_id: String = ""
# province_id -> Color (kazanan partinin rengi) — hover'dan çıkınca buna dönülür.
var _province_base_colors: Dictionary = {}
var _province_tooltip: PanelContainer
var _game_over_overlay: Control
## Ekranın üstünde kısa süre görünen bilgi yazısı (teklif sonucu, yeni tur…).
var _toast: Label
## Sayaç yazıları sadece gösterilen saniye değişince yenilensin diye.
var _last_countdown_key: int = -1
## Sağ sütundaki logoların o anki çerçeve ölçeği (bkz. _avatar_layout).
var _avatar_scale: int = PartyBadge.FRAME_SCALE
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

func _ready() -> void:
	map_holder.province_hovered.connect(_on_province_hovered)
	map_holder.province_clicked.connect(_on_province_clicked)
	_build_province_tooltip()
	_refresh_game_settings_label()
	MultiplayerManager.settings_updated.connect(_refresh_game_settings_label)

	deck_button.texture_normal = CardPresets.get_closed_texture()
	deck_button.pressed.connect(_on_deck_pressed)
	_add_shadow_behind(deck_button, CardPresets.get_closed_texture())
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
	CardManager.opinion_changed.connect(_on_opinion_changed)

	UiSkin.skin_panel(left_panel, UiSkin.PANEL_DARK)
	_build_waiting_overlay()
	_build_toast()
	_build_target_hint()
	_build_card_info()
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
	map_holder.position = Vector2(
		LEFT_PANEL_WIDTH + available_width * 0.5 - map_native_size.x * 0.5 * fit_scale,
		available_height * 0.5 - map_native_size.y * 0.5 * fit_scale
	)

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
			"name": pname,
			"leader": _leader_name_of(peer_id),
			"color": color,
			"percent": CardManager.last_vote_shares[peer_id],
			"seats": CardManager.last_seats.get(peer_id, 0),
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
	_province_base_colors.clear()
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
		_province_base_colors[province_id] = party_color
		map_holder.set_province_color(province_id, party_color)

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

## Haritada mouse ile gezinirken hover edilen ili hafifçe koyulaştırır ve
## o ildeki son seçim sonuçlarını (varsa) küçük bir kutuda gösterir.
## _province_base_colors'taki (kazanan parti rengi) ile ÇAKIŞMASIN diye,
## hover'dan çıkınca rastgele siyah yerine o ilin GERÇEK taban rengini
## geri yüklüyoruz.
func _on_province_hovered(province_id: String) -> void:
	if _hovered_province_id != "":
		map_holder.set_province_color(_hovered_province_id, _province_base_colors.get(_hovered_province_id, Color(0, 0, 0, 0)))
	_hovered_province_id = province_id
	if province_id != "":
		var base: Color = _province_base_colors.get(province_id, Color(0, 0, 0, 0))
		if base.a > 0.0:
			map_holder.set_province_color(province_id, base.darkened(0.25))
		else:
			map_holder.set_province_color(province_id, Color(0, 0, 0, 0.22))
	_show_province_tooltip(province_id)

func _build_province_tooltip() -> void:
	_province_tooltip = PanelContainer.new()
	_province_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_province_tooltip.z_index = 90
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.11, 0.95)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	style.shadow_size = 6
	style.shadow_color = SHADOW_COLOR
	_province_tooltip.add_theme_stylebox_override("panel", style)
	_province_tooltip.hide()
	add_child(_province_tooltip)

func _show_province_tooltip(province_id: String) -> void:
	if province_id == "":
		_province_tooltip.hide()
		return

	for child in _province_tooltip.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = province_id.capitalize()
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	var results: Dictionary = CardManager.last_province_results.get(province_id, {})
	if results.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Henüz sonuç yok"
		empty_label.modulate.a = 0.6
		empty_label.add_theme_font_size_override("font_size", 12)
		vbox.add_child(empty_label)
	else:
		var ids: Array = results.keys()
		ids.sort_custom(func(a, b): return results[a]["percent"] > results[b]["percent"])
		for peer_id in ids:
			var party: Dictionary = PartyManager.parties.get(peer_id, {})
			var pname: String = party.get("name", "?")
			var row := Label.new()
			row.text = "%s: %%%.1f (%d mv)" % [pname, results[peer_id]["percent"], results[peer_id]["seats"]]
			row.add_theme_font_size_override("font_size", 12)
			row.modulate = party.get("bg_color", Color.WHITE)
			vbox.add_child(row)

	var me := multiplayer.get_unique_id()
	if PartyManager.parties.has(me):
		var mine := Label.new()
		mine.text = "Senin il kamuoyun: %+.1f  ·  Miting riski: %%%d" % [
			CardManager.local_of(province_id, me), int(round(CardManager.miting_risk(me, province_id) * 100.0))]
		mine.add_theme_font_size_override("font_size", 12)
		vbox.add_child(mine)
	var hint := Label.new()
	hint.text = "Tıkla: kartı bu ilde oyna" if _pending_province_hand_index != -1 else "Tıkla: il detayları"
	hint.modulate.a = 0.6
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	_province_tooltip.add_child(vbox)
	_province_tooltip.show()
	await get_tree().process_frame
	var mouse_pos := get_viewport().get_mouse_position()
	_province_tooltip.global_position = mouse_pos + Vector2(18, 18)

func _on_parties_updated() -> void:
	_rebuild_player_panel()
	_update_turn_indicator()
	if _hovered_peer_id != -1:
		_show_tooltip_for(_hovered_peer_id)

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
	var layout := _avatar_layout()
	player_panel_list.columns = layout.x
	_avatar_scale = layout.y

	for peer_id in _ordered_peer_ids():
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var avatar := _build_avatar(peer_id, party)
		player_panel_list.add_child(avatar)

	# Panel yeniden kuruldu: hedef seçme vurguları yeni düğümlere uygulanmalı.
	_refresh_target_highlights()

# --- Tur göstergesi (geçici; kalıcı görseli kullanıcı sonra ekleyecek) -----

func _on_turn_changed(_peer_id: int) -> void:
	_update_turn_indicator()
	_refresh_deck_button()
	_refresh_pass_button()
	_refresh_hand_interactivity()

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

func _refresh_pass_button() -> void:
	pass_button.disabled = not CardManager.can_act()
	pass_button.modulate.a = 1.0 if not pass_button.disabled else 0.5

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
				child.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

# --- El (envanter) ----------------------------------------------------------

func _rebuild_hand() -> void:
	# Kart sürüklenirken el yeniden kurulursa sürüklenen düğüm silinir ve
	# bırakma olayı hiç gelmez; bırakılınca kurulsun.
	if _drag_hand_index != -1:
		_hand_dirty = true
		return
	# El değişti: bekleyen hedef seçimi artık yanlış karta işaret edebilir.
	_cancel_targeting()
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
	_update_avatar_hover()
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

	# Görseli henüz çizilmemiş (placeholder) kartlarda adı kartın gövdesine yaz.
	if not CardPresets.has_baked_title(card_type):
		var title := Label.new()
		title.text = CardPresets.card_short_title(card_type)
		title.position = Vector2(10, CARD_DISPLAY_SIZE.y * 0.36)
		title.size = Vector2(CARD_DISPLAY_SIZE.x - 20, CARD_DISPLAY_SIZE.y * 0.55)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color(0.16, 0.13, 0.11))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(title)

	# Kartlar üst üste binmiş olabilir (bkz. _fit_hand_width): hover edilen
	# kart komşularının ÖNÜNE çıksın ve ne işe yaradığı gösterilsin.
	card.mouse_entered.connect(func():
		holder.set_meta("lift_target", -CARD_DISPLAY_SIZE.y * 0.5)
		holder.z_index = 5
		_show_card_info(card_type, holder)
	)
	card.mouse_exited.connect(func():
		holder.set_meta("lift_target", 0.0)
		holder.z_index = 0
		_card_info.hide()
	)
	# TIK ve SÜRÜKLEME: basılı tutup TAP_MAX_MOVE_PX'ten fazla kaydırınca
	# sürükleme başlar (kartın kopyası imleci izler, bırakınca hedefe göre
	# oynanır — bkz. _drop_target). Kaydırmadan bırakmak TIK sayılır.
	# Basılan kontrol fare odağını tuttuğu için hareket ve bırakma olayları
	# imleç kartın dışına çıksa da bu karta gelir.
	card.set_meta("pressed", false)
	card.set_meta("press_pos", Vector2.ZERO)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _drag_hand_index != -1:
				card.set_meta("pressed", false)
				_end_drag()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
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

## TEK TIK. İdeoloji kartları doğrudan kendi partine oynanır. Meclis kartları
## (yasa, gensoru) parlamento diyagramına sürüklenmeli. Vekil çalma ve
## miting/yatırımda sürüklemenin yanında tık + hedef seçme de çalışır.
func _on_hand_card_clicked(hand_index: int) -> void:
	if not CardManager.can_act():
		return
	var hand := CardManager.my_inventory()
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_type: String = hand[hand_index]
	_cancel_targeting()
	var me := multiplayer.get_unique_id()
	if CardPresets.needs_target(card_type):
		_begin_targeting(hand_index)
		return
	if CardPresets.needs_province_target(card_type):
		if card_type == CardPresets.INVEST_CARD_TYPE and not CardManager.is_government_party(me):
			_show_toast("Yatırım kartını sadece hükümet partileri oynayabilir.")
			return
		_begin_province_targeting(hand_index)
		return
	if CardPresets.is_law_card(card_type) or CardPresets.is_censure_card(card_type):
		_show_toast("Kartı parlamento diyagramının üstüne sürükle." if CardManager.can_play_card(me, card_type) \
			else _unplayable_reason(card_type))
		return
	if not CardManager.can_play_card(me, card_type):
		_show_toast(_unplayable_reason(card_type))
		return
	CardManager.play_card(hand_index)

## Oynanamayan bir karta tıklanınca neden oynanamadığı.
func _unplayable_reason(card_type: String) -> String:
	if CardPresets.is_law_card(card_type):
		return "Yasa şu an meclise getirilemez (meclis yok ya da hükümet kuruluyor)."
	if CardPresets.is_censure_card(card_type):
		return "Gensoruyu sadece muhalefet, hükümet görevdeyken verebilir."
	return "Bu kart şu an oynanamaz."

# --- Sürükle-bırak -----------------------------------------------------------

func _start_drag(hand_index: int, card_type: String, holder: Control) -> void:
	if not CardManager.can_act():
		return
	_cancel_targeting()
	_drag_hand_index = hand_index
	_drag_card_type = card_type
	_card_info.hide()
	holder.modulate.a = 0.35
	_drag_ghost = TextureRect.new()
	_drag_ghost.texture = CardPresets.get_card_texture(card_type)
	_drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_ghost.size = CARD_DISPLAY_SIZE * 0.6
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 150
	add_child(_drag_ghost)
	# Vekil çalmada geçerli hedef partiler vurgulanır.
	if CardPresets.needs_target(card_type):
		_pending_target_hand_index = hand_index
		_refresh_target_highlights()
	_update_drag()

## Her kare: kopya imleci izler, imlecin altındaki hedef vurgulanır ve üstte
## "bırakırsan ne olur" yazar.
func _update_drag() -> void:
	var mouse := get_viewport().get_mouse_position()
	_drag_ghost.position = mouse - _drag_ghost.size * 0.5
	var target := _drop_target(_drag_card_type)
	_set_target_hint(String(target["label"]) + "  ·  Sağ tık: iptal")
	var valid: bool = target["valid"]
	_drag_ghost.modulate = Color(1, 1, 1, 0.95) if valid else Color(1, 0.75, 0.75, 0.8)
	parliament_diagram.modulate = Color(1.3, 1.3, 1.05) if bool(target["parliament"]) else Color.WHITE
	if CardPresets.needs_province_target(_drag_card_type):
		var province_id: String = target["province"]
		if province_id != _hovered_province_id:
			_on_province_hovered(province_id)

func _finish_drag() -> void:
	var hand_index := _drag_hand_index
	var target := _drop_target(_drag_card_type)
	_end_drag()
	if bool(target["valid"]):
		CardManager.play_card(hand_index, int(target["peer"]), String(target["province"]))
	elif String(target["error"]) != "":
		_show_toast(target["error"])

func _end_drag() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	_drag_hand_index = -1
	_drag_card_type = ""
	parliament_diagram.modulate = Color.WHITE
	if _hovered_province_id != "":
		_on_province_hovered("")
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
	if CardPresets.needs_target(card_type):
		var peer := _party_under_mouse()
		result["peer"] = peer
		if peer == -1:
			result["label"] = "Vekil çalmak için sağdaki bir partinin logosuna bırak"
		elif CardManager.is_valid_steal_target(me, peer):
			result["valid"] = true
			result["label"] = "Bırak: %s partisinden vekil çal" % _party_name_of(peer)
		else:
			result["label"] = "Bu partiden vekil çalınamaz"
			result["error"] = result["label"]
	elif CardPresets.is_ideology_card(card_type):
		# İdeoloji kartı sadece kendi partine: kendi logona bırakmak da tıklamak gibi.
		var peer := _party_under_mouse()
		if peer == me:
			result["valid"] = true
			result["label"] = "Bırak: partinin ekseni kayar"
		else:
			result["label"] = "İdeoloji kartı sadece kendi partine oynanır — karta tıkla"
			if peer != -1:
				result["error"] = "Başka bir partinin ideolojisini değiştiremezsin."
	elif CardPresets.needs_province_target(card_type):
		var province_id := _province_under_mouse()
		result["province"] = province_id
		if province_id == "":
			result["label"] = "Haritada bir ilin üstüne bırak"
		elif card_type == CardPresets.INVEST_CARD_TYPE and not CardManager.is_government_party(me):
			result["label"] = "Yatırımı sadece hükümet partileri yapabilir"
			result["error"] = result["label"]
		else:
			result["valid"] = true
			if card_type == CardPresets.MITING_CARD_TYPE:
				result["label"] = "Bırak: %s'da miting · provokasyon riski %%%d" % [
					province_id.capitalize(), int(round(CardManager.miting_risk(me, province_id) * 100.0))]
			else:
				result["label"] = "Bırak: %s'a yatırım" % province_id.capitalize()
	elif CardPresets.is_law_card(card_type) or CardPresets.is_censure_card(card_type):
		var over := parliament_diagram.get_global_rect().has_point(get_viewport().get_mouse_position())
		result["parliament"] = over
		if not over:
			result["label"] = "Meclise getirmek için parlamento diyagramının üstüne bırak"
		elif CardManager.can_play_card(me, card_type):
			result["valid"] = true
			result["label"] = "Bırak: meclise getir"
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
	_set_target_hint("Vekil çalmak için sağdan bir parti seç  ·  Sağ tık: iptal")

## Miting / yatırım: haritadan il seçilmesi beklenir (bkz. _on_province_clicked).
func _begin_province_targeting(hand_index: int) -> void:
	_pending_province_hand_index = hand_index
	# Harita tıklanabilir kalsın: açık il paneli haritanın üstünü kapatmasın.
	if _province_panel != null:
		_province_panel.hide()
	var card_type: String = CardManager.my_inventory()[hand_index]
	_set_target_hint("%s için haritadan bir il seç (risk il üstünde yazar)  ·  Sağ tık: iptal" % CardPresets.card_title(card_type))

func _cancel_targeting() -> void:
	_pending_province_hand_index = -1
	_set_target_hint("")
	if _pending_target_hand_index == -1:
		return
	_pending_target_hand_index = -1
	_refresh_target_highlights()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _pending_target_hand_index != -1 or _pending_province_hand_index != -1:
			_cancel_targeting()
			get_viewport().set_input_as_handled()

## Haritada bir ile tıklandı: il seçme modundaysa kart o ilde oynanır, değilse
## il detay paneli açılır/kapanır.
func _on_province_clicked(province_id: String) -> void:
	if _pending_province_hand_index != -1:
		var hand_index := _pending_province_hand_index
		_cancel_targeting()
		if hand_index < CardManager.my_inventory().size():
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

func _on_opinion_changed() -> void:
	_refresh_score_panel()
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
		return
	if not CardManager.is_valid_steal_target(multiplayer.get_unique_id(), peer_id):
		return
	var hand_index := _pending_target_hand_index
	_cancel_targeting()
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

func _add_shadow_behind(control: Control, texture: Texture2D) -> void:
	var shadow := TextureRect.new()
	shadow.texture = texture
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


## Sağ sütundaki logoların (sütun sayısı, çerçeve ölçeği). Önce tek sütunda
## PartyBadge.FRAME_SCALE (3x) denenir; sığmazsa iki sütun, o da sığmazsa
## pixel-art keskin kalsın diye TAM SAYI bir alt ölçek (2x).
func _avatar_layout() -> Vector2i:
	var count: int = maxi(1, _ordered_peer_ids().size())
	var available: Vector2 = player_panel_list.get_parent().size
	if available.y <= 0.0:
		return Vector2i(1, PartyBadge.FRAME_SCALE)
	for s in [PartyBadge.FRAME_SCALE, 2]:
		for cols in [1, 2]:
			var rows: int = int(ceil(float(count) / cols))
			var h: float = rows * PartyBadge.frame_height(s) + (rows - 1) * AVATAR_SEPARATION
			var w: float = cols * PartyBadge.frame_width(s) + (cols - 1) * AVATAR_SEPARATION
			if h <= available.y and w <= available.x:
				return Vector2i(cols, s)
	return Vector2i(2, 2)

func _build_avatar(peer_id: int, party: Dictionary) -> Control:
	var is_self := peer_id == multiplayer.get_unique_id()
	# use_frame=true: sağdaki oyuncu panelindeki logolar pixel-art çerçeveli.
	# (Tur göstergesindeki küçük rozet, istendiği gibi eski prosedürel
	# görünümünde bırakıldı — orası çerçeve istenmedi.)
	var wrap := PartyBadge.build(party, Vector2(AVATAR_SIZE, AVATAR_SIZE), AVATAR_ICON_PIXEL_SIZE, is_self, true, _avatar_scale)
	# VBoxContainer içindeki çocukları yatayda gerebilir; bu olmadan daire
	# oval'a dönüşürdü. SHRINK_CENTER ile hep AVATAR_SIZE genişliğinde,
	# sütunda ortalanmış kalır.
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Hangi oyuncuya ait olduğu düğümün ÜSTÜNDE saklanıyor: hover tespiti
	# (bkz. _update_avatar_hover) ve tooltip konumlandırma, panelin çocuk
	# SIRASINA güvenmek yerine bunu okuyor. Panel yeniden kurulurken eski
	# (queue_free edilmiş ama henüz silinmemiş) düğümler listede bir süre
	# daha durabildiği için index bazlı eşleme güvenilir değil.
	wrap.set_meta("peer_id", peer_id)
	# Oylama sırasında logonun altında partinin oyu (ya da beklendiği) yazar.
	if GovernmentManager.is_voting() and GovernmentManager.voter_ids().has(peer_id):
		var voted: bool = GovernmentManager.votes.has(peer_id)
		var tag := Label.new()
		tag.text = GovernmentManager.vote_text(GovernmentManager.votes[peer_id]) if voted else "…"
		tag.add_theme_font_size_override("font_size", 12)
		tag.add_theme_color_override("font_color", VOTE_COLORS[int(GovernmentManager.votes[peer_id])] if voted else Color(1, 1, 1, 0.6))
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.add_theme_constant_override("outline_size", 5)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrap_size: Vector2 = wrap.size if wrap.size != Vector2.ZERO else wrap.custom_minimum_size
		tag.position = Vector2(-10, wrap_size.y - 18)
		tag.size = Vector2(wrap_size.x + 20, 18)
		wrap.add_child(tag)
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

## Avatar hover'ı, Control'ün mouse_entered/mouse_exited sinyalleriyle DEĞİL,
## her karede gerçek fare konumuna bakarak belirleniyor. Sinyal yaklaşımı iki
## ayrı nedenle güvenilmezdi:
##   1) Rozetin içindeki renkli daire (Panel) varsayılan olarak STOP filtreli
##      ve tüm alanı kaplıyor; fare daire ile ikon arasında geçerken hover
##      hedefi değişip dıştaki kapsayıcıya mouse_exited attırıyordu — yani
##      imleç logonun üstünden hiç çıkmadığı hâlde profil kartı kayboluyordu.
##   2) Parti verisi güncellenince panel komple yeniden kuruluyor; silinen
##      eski avatarlar da mouse_exited yayınlayıp kartı kapatıyordu.
## Konumdan hesaplayınca ikisi de tamamen ortadan kalkıyor.
func _update_avatar_hover() -> void:
	if hover_tooltip == null:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var found := -1
	for child in player_panel_list.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var avatar := child as Control
		if avatar == null:
			continue
		if Rect2(avatar.global_position, avatar.size).has_point(mouse_pos):
			found = avatar.get_meta("peer_id", -1)
			break
	if found == _hovered_peer_id:
		return
	_hovered_peer_id = found
	if found == -1:
		hover_tooltip.hide()
	else:
		_show_tooltip_for(found)

func _show_tooltip_for(peer_id: int) -> void:
	var party: Dictionary = PartyManager.parties.get(peer_id, {})
	var ideology: Dictionary = party.get("ideology", IdeologyAxes.default_values())

	# Kartın TAMAMI tek bir pixel-art görsel: politic_profile.png'in üstüne
	# partinin ideolojisine karşılık gelen üç eksen görseli yapıştırılmış hâli
	# (bkz. party_profile.gd).
	hover_tooltip_image.texture = PartyProfile.build_texture(ideology)

	# Pixel-art keskin kalsın diye TAM SAYI katıyla büyütülüyor.
	var native_size := PartyProfile.get_native_size()
	if native_size == Vector2i.ZERO:
		return
	hover_tooltip.size = Vector2(native_size) * PROFILE_CARD_SCALE

	# Tooltip'i, hover edilen avatarın hemen soluna yerleştir.
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
	_waiting_overlay.visible = forming and not GovernmentManager.is_my_mandate()
	if not _waiting_overlay.visible:
		return
	var holder: int = GovernmentManager.mandate_peer_id()
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
		and GovernmentManager.voter_ids().has(multiplayer.get_unique_id()) \
		and not GovernmentManager.has_voted(multiplayer.get_unique_id())

	vote_yes_button.disabled = not can_vote
	vote_no_button.disabled = not can_vote
	_abstain_button.disabled = not can_vote

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

	# Yasa oylamasında butonların üstüne gelince kamuoyu etkisi görünsün.
	var me := multiplayer.get_unique_id()
	if can_vote and GovernmentManager.proposal_kind == GovernmentManager.KIND_LAW:
		vote_yes_button.tooltip_text = "EVET: kamuoyun %+.1f" % CardManager.preview_law_vote(me, GovernmentManager.VOTE_YES)
		_abstain_button.tooltip_text = "ÇEKİMSER: kamuoyun %+.1f" % CardManager.preview_law_vote(me, GovernmentManager.VOTE_ABSTAIN)
		vote_no_button.tooltip_text = "HAYIR: kamuoyun %+.1f" % CardManager.preview_law_vote(me, GovernmentManager.VOTE_NO)
	else:
		vote_yes_button.tooltip_text = ""
		_abstain_button.tooltip_text = ""
		vote_no_button.tooltip_text = ""

	proposal_label.text = GovernmentHud.proposal_status_text(multiplayer.get_unique_id())

func _party_name_of(peer_id: int) -> String:
	return GovernmentHud.party_name_of(peer_id)

func _leader_name_of(peer_id: int) -> String:
	return GovernmentHud.leader_name_of(peer_id)

func _refresh_government_panel() -> void:
	GovernmentHud.fill_government_panel(government_vbox)

func _refresh_score_panel() -> void:
	GovernmentHud.fill_score_panel(score_vbox, _ordered_peer_ids(), multiplayer.get_unique_id())
