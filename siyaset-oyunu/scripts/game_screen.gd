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
## YENİ DÜZEN (üst parti şeridi): üstte bütün partilerin plaketleri, solda
## meclis, sağda oyun bilgisi/hükümet/log, altta benim bandım (kartlar,
## hamleler, para, Turu Bitir), ortada harita.
const RIGHT_COLUMN_WIDTH := 320.0
const TOP_STRIP_HEIGHT := 64.0
## "MECLİS SALONU" DÜZENİ (1280x720 tasarım ızgarası; ekran boyutuna ölçeklenir):
##   üst parti şeridi · ortada harita (sol altında meclis rozeti) · sağda
##   sekmeli inceleme sütunu · altta "benim masam" (kartlar, hamleler, para, bitir).
const DESIGN := Vector2(1280, 720)
## "HABER STÜDYOSU" (0.0.153): üstte canlı yayın bandı · solda skor tablosu
## (VEKİL / PUAN) · ortada harita · sağda sekmeli stüdyo masası (HÜKÜMET
## sekmesinde meclis diyagramı) · altta Meclis Salonu'nun masası.
const R_BAND := Rect2(0, 0, 1280, 64)
const R_BOARD := Rect2(16, 72, 272, 448)
const R_MAP := Rect2(304, 72, 672, 448)
const R_SIDE := Rect2(992, 72, 272, 448)
const R_DESK := Rect2(0, 528, 1280, 192)
const R_HAND := Rect2(16, 560, 504, 128)
const R_ACTIONS := Rect2(536, 560, 392, 136)
const R_FUNDS := Rect2(952, 560, 148, 64)
const R_TRASH := Rect2(1108, 560, 156, 64)
const R_PASS := Rect2(952, 632, 312, 72)
## Stüdyo masasındaki meclis yuvasının yüksekliği (oylamada büyür).
const PARL_SLOT_HEIGHT := 150.0
const PARL_SLOT_VOTE_HEIGHT := 286.0
## Sağ üstte Menü düğmesi: şerit oraya kadar uzanmaz.
const MENU_RESERVE := 140.0
## Alt bantta kartların, hamlelerin ve sağdaki kontrollerin payı.
const BAND_HAND_RATIO := 0.40
const BAND_ACTIONS_RATIO := 0.33
## EVRENSEL PARTİ TABLOSU: üstteki üç sekme ve her sekmenin sayı sütunları.
## Sütun başlıkları tablonun ilk satırında görünür, satırlarda tekrar etmez.
const PLAYER_TAB_TITLES := ["VEKİL", "PUAN"]
const PLAYER_TAB_TOOLTIPS := [
	"Partilerin vekil sayısı ve son seçimdeki oy oranı",
	"Siyasetçilerin puanı ve partilerinin ulusal durumu",
]
## Her sekme için [başlık, genişlik] sütunları (soldan sağa, sağa yaslı).
const PLAYER_TAB_COLUMNS := [
	[["KASA", 58.0]],
	[["OY", 56.0], ["VEKİL", 50.0]],
	[["VEKİL", 46.0], ["ULUSAL", 52.0], ["PUAN", 44.0]],
]
const PLAYER_TAB_HEIGHT := 30.0
## Sütun başlığı satırının yüksekliği ve iki satırlık kartın alt sınırı.
const PLAYER_HEADER_HEIGHT := 20.0
## Alt haznede meclisin (sol) aldığı pay; kalan sağ kısım el kartlarına.
## Alt haznenin (parlamento + hamleler) kullandığı genişlik payı. Kalanı
## el kartlarına gider. Hazne içeriğinden dar kalırsa HBox taşar; bu yüzden
## ChamberSplit yalnızca sağa büyüyecek şekilde ayarlıdır (bkz. sahne).
## KART BARI: ekranın en altında, TAM GENİŞLİKTE duran kart şeridi. Kartlar
## burada yan yana (bitişik değil) dizilir. Diğer her şey bunun üstünde kalır.
const CARD_BAR_HEIGHT := 192.0
const CARD_BAR_PADDING := 8.0
## Kartın barda görünen ÜST kısmı. Kalanı ekranın altında bekler; fare
## üstüne gelince (ya da dokunulup seçilince) kart bu kadar yukarı kalkıp
## tamamen görünür.
const CARD_PEEK_HEIGHT := 72.0 * 4.0 / 3.0 * 4.0 / 3.0
## Haritanın altındaki katman düğmelerine (Vekiller/Teşkilat/Güç) ayrılan yer.
const LAYER_BAR_RESERVE := 40.0
const AVATAR_SEPARATION := 6.0
const AVATAR_SIZE := 56.0
## Parti logoları (çerçeve dahil) party_badge.gd'de; sol paneller government_hud.gd'de.
const AVATAR_ICON_PIXEL_SIZE := 144
## Soldaki tam boy bilgi panelinin genişliği — GameScreen.tscn'deki
## LeftPanel.offset_right ile birebir eşleşmeli.
const LEFT_PANEL_WIDTH := 16.0
const BADGE_ICON_PIXEL_SIZE := 64

# Kartlar 72x96 piksel native boyutta; Nearest filtre ile piksel-sanat
# görünümü bozulmasın diye tam sayı katıyla büyütülüyor.
## Kartlar kart barında TAMAMEN görünür: eskiden 2 kat büyüktüler ve yarıları
## ekranın altından taşıyordu.
const CARD_DISPLAY_SCALE := 4.0 / 3.0
## Kart üstündeki bant/rozet ölçüleri 2 kat büyük karta göre yazılmıştı;
## hepsi bu oranla küçülüyor ki kartla orantılı kalsınlar.
const CARD_TITLE_SIZE := 12
const CARD_TITLE_MIN_SIZE := 8
const CARD_ART_RATIO := CARD_DISPLAY_SCALE / 2.0
const CARD_DISPLAY_SIZE := Vector2(72, 96) * CARD_DISPLAY_SCALE
const CARD_LIFT := -14.0
const CARD_HOVER_LIFT_SPEED := 12.0
const HAND_CARD_SEPARATION := 8
## Fare bu kadar kaydırılırsa tık değil SÜRÜKLEME başlar.
const TAP_MAX_MOVE_PX := 10.0
## Oylamada parlamento koltuklarının ve profil etiketlerinin rengi.
const VOTE_COLORS := {1: UiTheme.GREEN, 0: UiTheme.GOLD, -1: UiTheme.RED}

## HARİTA KATMANLARI: aynı Türkiye haritasının dört ayrı görünümü; butonlarla
## geçilir, harita yan yana dizilmiş sayfalar gibi yana kayar.
##   SEATS        : son seçim (il kazananları + vekil daireleri)
##   ORGANIZATION : teşkilat seviyem (0 beyaz → en üst seviyede parti rengi)
##   STRENGTH     : tüm faktörlerle (ilin seçmen profili, bütün partilerin gücü) şimdi
##                  seçim olsa bu ilde durumum; her ilde, ilk turdan itibaren
##   GROUPS       : seçilen SEÇMEN GRUBUNUN illerdeki yoğunluğu (soluk = az,
##                  grubun renginde koyu = çok); 8 grup simgesiyle seçilir.
enum MapLayer { SEATS, ORGANIZATION, STRENGTH, GROUPS }
const MAP_LAYER_TITLES := ["Vekiller", "Teşkilat", "Güç", "Seçmen"]
const MAP_UNKNOWN_COLOR := Color(0.62, 0.62, 0.64)
const MAP_SLIDE_DURATION := 0.38
## Olay logundan odaklanma: yakınlaşma, bekleme (parıltı) ve dönüş süreleri.
const FOCUS_MOVE := 0.3
const FOCUS_HOLD := 0.9
const FOCUS_ZOOM := 2.2
## Güç haritasında bu kadar il puanı en koyu renge denk gelir.
const STRENGTH_STOPS := [Color(0.42, 0.04, 0.05), Color(0.88, 0.2, 0.14), Color(0.96, 0.84, 0.24), Color(0.36, 0.76, 0.3), Color(0.04, 0.36, 0.13)]
const MAP_BLANK_COLOR := Color(0.97, 0.97, 0.95)
## Teşkilat hamlesinden sonra haritanın teşkilat katmanında kaldığı süre.
const SHADOW_OFFSET := Vector2(4, 5)
const SHADOW_COLOR := Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.6)

const DRAW_FLY_DURATION := 0.16   # deste -> ekran ortası (hızlı)
const DRAW_SETTLE_DURATION := 0.16  # ekran ortası -> el'deki yeni yeri
const DRAW_HOLD_DURATION := 0.10
const PLAY_FLY_DURATION := 0.22   # el/avatar -> ekran ortası
const PLAY_POP_DURATION := 0.18   # ortada küçülüp "puf" kaybolma

@onready var map_holder: Node2D = %MapHolder
## Kartı sürükleyip bırakınca atmaya yarayan çöp kutusu.
var _trash_panel: PanelContainer
## Anayasa paketi: oyuncunun seçtiği baraj ve seçim aralığı.
var _constitution_threshold: float = 0.0
var _constitution_interval: int = 4
var _constitution_threshold_label: Label
var _constitution_interval_label: Label
var _constitution_button: Button
var _constitution_alliances: CheckButton
var _constitution_method: String = "dhondt"
var _constitution_method_label: Label

var _constitution_info: Label
@onready var pass_button: Button = %PassButton
@onready var player_panel_list: GridContainer = %PlayerPanelList
@onready var player_tabs: HBoxContainer = %PlayerTabs
@onready var actions_vbox: VBoxContainer = %ActionsVBox
@onready var hand_container: HBoxContainer = %HandContainer
@onready var hand_area: Control = %HandArea
@onready var turn_indicator: PanelContainer = %TurnIndicator
@onready var turn_indicator_label: Label = %TurnIndicatorLabel
@onready var turn_indicator_badge_slot: Control = %TurnIndicatorBadgeSlot
@onready var hover_tooltip: Control = %HoverTooltip
@onready var hover_tooltip_image: TextureRect = %HoverTooltipImage
@onready var parliament_diagram: ParliamentDiagram = %ParliamentDiagram
@onready var game_settings_label: Label = %GameSettingsLabel
@onready var bottom_area: Control = %BottomArea
@onready var vote_yes_button: Button = %VoteYesButton
@onready var vote_no_button: Button = %VoteNoButton
@onready var proposal_label: Label = %ProposalLabel
## DÜZ Panel (PanelContainer değil): içeriği ne kadar büyürse büyüsün
## genişliği 260'ta SABİT kalsın, parlamento diyagramının üstüne binmesin.
@onready var left_panel: Panel = %LeftPanel
@onready var government_vbox: VBoxContainer = %GovernmentVBox

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
## Seçmen katmanında gösterilen grup ve grup seçici düğmeler.
var _map_group: String = "isci"
var _group_picker: HBoxContainer
var _game_over_overlay: Control
## Sol paneldeki canlı olay logu ve harita odak animasyonu.
var _event_log: EventLogPanel
var _focus_tween: Tween
var _map_fit_scale: float = 1.0
## Sayaç yazıları sadece gösterilen saniye değişince yenilensin diye.
var _last_countdown_key: int = -1
## Sağ sütundaki oyuncu kartlarının o anki yüksekliği (sütuna sığacak kadar).
var _avatar_height: float = 64.0
## Açık olan parti tablosu sekmesi (0 sıra/para, 1 seçim, 2 durum).
var _player_tab: int = 0
var _player_tab_buttons: Array = []
## İl seçmeyi bekleyen kartın (miting/yatırım) el içindeki sırası (-1 = yok).
var _pending_province_hand_index: int = -1
var _province_panel: ProvincePanel
## SOL PANEL DİNAMİK: il menüsü ve oyuncu profili, hükümet/log bölümünün
## yerine sol panelde açılır; ✕ ile kapanınca hükümet ve log geri gelir.
var _left_dock: Panel
var _profile_scroll: ScrollContainer
## Profil panelinde gösterilen parti (aynı parti tazelenirken kaydırma korunur).
var _profile_scroll_peer: int = -1
## Hedef seçme modundayken üstte görünen yönerge ("... sağ tık: iptal").
var _target_hint: Label
## Eldeki bir kartın üstüne gelince çıkan açıklama kutusu.
var _card_info: PanelContainer
var _abstain_button: Button
## Sürüklenen kart (el içindeki sırası; -1 = sürükleme yok) ve imleci izleyen kopyası.
var _drag_hand_index: int = -1
var _drag_card_type: String = ""
var _drag_ghost: TextureRect
## Sürükleme sırasında el yeniden kurulmak istendi mi (bırakınca kurulur).
var _hand_dirty: bool = false
## Hamle butonları ve para göstergesi (sağ sütun, destenin yanında).
## Para levhası: sağ sütunun altında, hamle butonlarının hemen üstünde.
## Sağ sütun aşağıdan yukarı: sıra göstergesi, Turu Bitir, kart bozdurma,
## para levhası. Hamle butonları buradan parlamentonun yanına taşındı.
const FUNDS_PLATE_LEFT := -(RIGHT_COLUMN_WIDTH - 16.0)
const FUNDS_PLATE_HEIGHT := 44.0
## Kart bozdurma ve Turu Bitir AYNI ÖLÇÜDE, alt alta.
const BOTTOM_BUTTON_HEIGHT := 46.0
## Sağ sütun aşağıdan yukarı dizilir ve KART BARININ ÜSTÜNDE biter.
const RIGHT_STACK_BOTTOM := -(CARD_BAR_HEIGHT + 12.0)
const PASS_TOP := RIGHT_STACK_BOTTOM - BOTTOM_BUTTON_HEIGHT
const TRASH_TOP := PASS_TOP - BOTTOM_BUTTON_HEIGHT - 6.0
const FUNDS_PLATE_TOP := TRASH_TOP - FUNDS_PLATE_HEIGHT - 6.0
const FUNDS_ICON_SIZE := 34.0
## Parlamento diyagramının köşesinde duran "teklifi veren parti" rozeti.
var _proposer_chip: PanelContainer
var _proposer_row: HBoxContainer
## Kart barının zemini (ekranın altındaki tam genişlik şeridi).
var _card_bar_panel: Panel
var _funds_plate: PanelContainer
var _funds_box: HBoxContainer
var _funds_label: Label
## Hamle ızgarası: artık parlamento diyagramının SAĞINDAKİ panelde, iki
## sütunlu. Butonlar paneli paylaşır, bu yüzden asgari ölçü küçük tutulur.
## 5 sütun (0.0.181, YARDIM eklendi): (392 - 4 × 8) / 5.
const ACTION_BUTTON_WIDTH := 72.0
const ACTION_BUTTON_HEIGHT := 64.0
const ACTION_BUTTON_GAP := 8
var _action_grid: GridContainer
## HAMLE SEKMELERİ (0.0.189): hamleler kategorilere ayrılır; ızgarada yalnız
## seçili sekmenin hamleleri görünür. Yeni hamle = _action_button(..., kategori).
enum ActionTab { SAHA, MECLIS, PARTI, SIYASET }
const ACTION_TAB_TITLES := ["SAHA", "MECLİS", "PARTİ", "SİYASET"]
var _action_tab := ActionTab.SAHA
var _action_tab_bar: HBoxContainer
var _action_tab_buttons: Array = []
## Buton -> sekme (ActionTab).
var _action_tab_of: Dictionary = {}
var _law_button: Button
var _org_button: Button
var _miting_button: Button
## Miting hamlesi için il seçme modu.
var _pending_miting: bool = false
var _invest_button: Button
var _censure_button: Button
var _early_button: Button
var _pending_early: bool = false
var _congress_button: Button
var _pending_congress: bool = false
## Yatırım hamlesi için il seçme modu.
var _pending_invest: bool = false
## Gensoru: ilk dokunuş onay ister, ikincisi verir.
var _pending_censure: bool = false
var _last_turn_peer: int = -2
## Yasa tasarlama paneli (6 daire) ve karalama hedef menüsü.
var _law_designer: PanelContainer
## YASA SEKMELERİ (0.0.190): GRUP YASASI · VERGİ · ANAYASA; her sekme ayrı sayfa.
enum LawTab { GROUP, TAX, CONSTITUTION }
const LAW_TAB_TITLES := ["GRUP YASASI", "VERGİ", "ANAYASA"]
var _law_tab := LawTab.GROUP
var _law_tab_buttons: Array = []
var _law_pages: Array = []
var _law_tax_box: VBoxContainer
var _law_tax_selected := -1
var _propaganda_menu: PanelContainer
## Teşkilatlanma için il seçme modu (harita teşkilat katmanına geçer).
var _pending_org: bool = false
var _circle_textures: Dictionary = {}
## Para göstergesine dokununca gösterilen kural özeti.
var _funds_rules: String = ""
## Yasa panelinde seçilen dairenin açıklaması (dokununca güncellenir).
var _law_rows: GridContainer
## Yasa panelinde seçili seçmen grubu ("" = seçim yok) ve ayrıntı kutusu.
var _law_group: String = ""
var _law_detail: VBoxContainer
var _law_agenda_label: Label
var _law_points_label: Label
## Haritanın sağ üstünde gündem bandı.
var _agenda_banner: PanelContainer
var _agenda_label: Label

## MECLİS KONUŞMASI paneli (sıra gelince, hamleden önce zorunlu).
## Eksen sütunu genişliği (panel = 3 sütun).
const SPEECH_COLUMN_WIDTH := 150.0
var _speech_panel: PanelContainer
var _speech_rows: GridContainer
var _speech_note: Label
var _speech_key: String = ""
## GRUP TOPLANTISI hamle düğmesiyle bu sırada (tur:sıra) açıldı mı?
var _speech_open_key: String = ""
var _speech_button: Button
## EKONOMİ: sağ sütundaki özet (Hükümet sekmesi) ve Vergi Politikası paneli.
var _economy_panel: EconomyPanel
var _tax_panel: PanelContainer
var _tax_box: VBoxContainer
var _tax_selected: int = -1
## FİNANSMAN: yatırım / miting için il seçilince açılan kaydırıcılı panel;
## finansman soruşturması paneli ve sonuç kartı.
var _funding_panel: FundingPanel
## AFET YARDIMI paneli (YARDIM hamlesi).
var _aid_panel: AidPanel
var _aid_button: Button
## FİNANSMAN SORUŞTURMASI hamlesi (eskiden sadece parti kartından) ve parti seçici.
var _inquiry_button: Button
var _inquiry_picker: PanelContainer
var _inquiry_panel: PanelContainer
var _inquiry_box: VBoxContainer
var _inquiry_target: int = -1
var _inquiry_card: Control
var _alliance_button: Button
var _alliance_panel: PanelContainer
var _alliance_list: VBoxContainer
var _alliance_name: LineEdit
var _alliance_color: ColorPickerButton
var _alliance_create_button: Button

func _ready() -> void:
	AudioManager.play_game_music()
	map_holder.province_clicked.connect(_on_province_clicked)
	_refresh_game_settings_label()
	MultiplayerManager.settings_updated.connect(_refresh_game_settings_label)

	_place_right_column_controls()
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
	# Profil, harita katman düğmelerinin (z 5) ve il menüsünün üstünde.
	hover_tooltip.z_index = 120
	PartyManager.parties_updated.connect(_on_parties_updated)
	CardManager.turn_order_updated.connect(_rebuild_player_panel)
	CardManager.turn_changed.connect(_on_turn_changed)
	CardManager.inventories_updated.connect(_rebuild_hand)
	CardManager.card_drawn.connect(_on_card_drawn)
	CardManager.card_played.connect(_on_card_played)
	CardManager.congress_started.connect(_on_congress_started)
	_build_event_fx()
	CardManager.event_logged.connect(_pulse_logged_province)
	CardManager.election_completed.connect(_on_election_completed)
	CardManager.round_advanced.connect(_on_round_advanced)
	CardManager.game_over.connect(_on_game_over)
	CardManager.seats_changed.connect(_on_seats_changed)
	GovernmentManager.proposal_resolved.connect(_on_proposal_resolved)
	CardManager.opinion_changed.connect(_on_opinion_changed)
	CardManager.economy_event.connect(_on_economy_event)
	CardManager.inquiry_resolved.connect(_show_inquiry_result)
	GameSettings.province_view_changed.connect(_on_province_view_changed)

	UiSkin.skin_panel(left_panel, UiSkin.PANEL_DARK)
	# Yıl / sonraki seçim / baraj kendi levhasında dursun (ek UI katmanı).
	var info_plate := get_node_or_null("%InfoPlate") as PanelContainer
	if info_plate != null:
		var plate_style := UiSkin.stylebox(UiSkin.SLOT)
		plate_style.set_content_margin_all(UiTheme.PAD_S)
		info_plate.add_theme_stylebox_override("panel", plate_style)
	game_settings_label.add_theme_font_override("font", UiTheme.mono())
	game_settings_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	# Sıra göstergesi de aynı monospace ailede.
	turn_indicator_label.add_theme_font_override("font", UiTheme.mono())
	# Parlamento "tahtası": diyagram ekranın bir iki piksel üstünde duruyormuş
	# gibi kendi zemini ve sert gölgesi olan bir panelin içinde.
	var board := get_node_or_null("%ParliamentBoard") as PanelContainer
	if board != null:
		# Rozetin içinde ayrı bir çerçeve olmasın: diyagram rozet zeminine oturur.
		board.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var actions_panel := get_node_or_null("%ActionsPanel") as PanelContainer
	if actions_panel != null:
		UiSkin.skin_panel(actions_panel, UiSkin.PANEL_DARK)
	# Monospace yazı geniş: panelin kendi genişliğini aşmasını engelle.
	left_panel.clip_contents = true
	# custom_minimum_size ASGARİ ölçüdür, azami değil: eskiden panel içeriği
	# 260'ı aşınca sağa doğru büyüyüp diyagramın üstüne biniyordu. Artık düz
	# Panel olduğu için genişlik çapalarla sabit; burada bir şey zorlamıyoruz.
	left_panel.custom_minimum_size.x = 0.0
	_build_waiting_overlay()
	_build_event_log()
	_build_target_hint()
	_build_card_info()
	_build_action_buttons()
	_build_trash_button()
	_build_player_tabs()
	# Çöp kutusu destenin yanına otursun (yerleşim butonlar kurulduktan sonra).
	_place_right_column_controls()
	_build_law_designer()
	_build_alliance_panel()
	_build_tax_panel()
	_build_funding_ui()
	_build_agenda_banner()
	_build_propaganda_menu()
	_build_speech_panel()
	vote_yes_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_YES))
	vote_no_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_NO))
	_abstain_button = Button.new()
	# OY DÜĞMELERİ: simge üstte, ad altta; EVET yeşil, ÇEKİMSER sarı, HAYIR
	# kırmızı. DAR SÜTUNDA DA SIĞSIN: üçü satırı eşit paylaşır.
	_style_vote_button(vote_yes_button, L.t("EVET"), "evet", UiTheme.GREEN_DARK)
	_style_vote_button(_abstain_button, L.t("ÇEKİMSER"), "cekimser", UiTheme.GOLD_DIM)
	_style_vote_button(vote_no_button, L.t("HAYIR"), "hayir", UiTheme.RED_DARK)
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
	_build_tutorial()

# --- İlk oyun rehberi -------------------------------------------------------------

var _tutorial: TutorialGuide

## Rehberin adımları: koşul (ne zaman anlamlı) ve hedef (ekranda hangi alan).
## Oyun akışını durdurmaz; görülenler cihazda saklanır (TutorialGuide).
func _build_tutorial() -> void:
	# Test / önizleme betiklerinde rehber açılmaz (ekran görüntülerini kapatmasın).
	if get_tree().get_script() != null and not TutorialGuide.allow_in_scripts:
		return
	_tutorial = TutorialGuide.new()
	add_child(_tutorial)
	var mine := func() -> bool: return CardManager.can_act() and not CardManager.game_finished
	var me := multiplayer.get_unique_id()
	_tutorial.add_step("ekran", L.t("Siyaset stüdyosuna hoş geldin"),
		L.t("Solda partiler ve vekilleri, ortada ülke haritası, sağda hükümet, haber akışı (LOG) ve seçtiğin il. Altta elindeki kartlar, hamleler ve parti kasan. Sıran gelince hamlelerini yap, sonra Turu Bitir'e bas."),
		func() -> Rect2: return _r(R_MAP), func() -> bool: return true)
	_tutorial.add_step("kasa", L.t("Parti kasası ve devlet hazinesi"),
		L.t("Bu senin partinin parası: sıran geldikçe dolar, hamleler buradan ödenir. Sağdaki EKONOMİ'de görünen DEVLET HAZİNESİ ayrıdır; onu sadece hükümet, yatırım için kullanır."),
		func() -> Rect2: return _r(R_FUNDS), mine)
	_tutorial.add_step("hamleler", L.t("Hamleler"),
		L.t("Bir hamle seç, sonra haritada il seç; aynı ile ikinci dokunuş onaylar. Soluk düğme şu an yapılamaz: üstüne gelince nedenini görürsün. Bedeller düğmelerin altında."),
		func() -> Rect2: return _r(R_ACTIONS), mine)
	_tutorial.add_step("secmen", L.t("Seçmen grupları"),
		L.t("Oylar 8 seçmen grubundan gelir. Seçmen katmanı her grubun hangi illerde yoğun olduğunu gösterir; partin hangi gruplara yakınsa o illerde güçlüdür. Bir ile tıkla: oradaki durumunu görürsün."),
		func() -> Rect2: return (_layer_buttons[MapLayer.GROUPS] as Control).get_global_rect() if _layer_buttons.size() > MapLayer.GROUPS else _r(R_MAP),
		func() -> bool: return mine.call() and _tutorial.seen_count() >= 3)
	_tutorial.add_step("teskilat", L.t("Teşkilat"),
		L.t("İlde teşkilat kalıcı oy, anket ve yerel bağış getirir; miting ve karalama ancak teşkilatlı ilde yapılır. Beş ilden sonra her yeni teşkilat biraz daha pahalıdır: nerede kuracağını seç."),
		func() -> Rect2: return _org_button.get_global_rect(), func() -> bool: return mine.call() and _tutorial.seen_count() >= 4)
	_tutorial.add_step("kartlar", L.t("Kartlar"),
		L.t("Karta dokun, ne yaptığını oku; hedef isterse bir parti ya da il seç. İstemediğin kartı KART BOZDUR yuvasına sürükle: bedelinin yarısı kasana döner."),
		func() -> Rect2: return _r(R_HAND),
		func() -> bool: return mine.call() and not CardManager.my_inventory().is_empty() and _tutorial.seen_count() >= 5)
	_tutorial.add_step("secim", L.t("Seçim yapıldı"),
		L.t("Vekil sayıları solda. En çok vekili olan parti hükümeti kurmaya çalışır; güvenoyu için meclisin çoğunluğu (251) gerekir. Gerekirse ortak bulunur."),
		func() -> Rect2: return _r(R_BOARD), func() -> bool: return CardManager.last_election_round > 0 and not CardManager.is_turn_blocked())
	_tutorial.add_step("hukumet", L.t("Hükümet ve koalisyon"),
		L.t("Hükümet kuruldu. Makamlar (başbakanlık, bakanlıklar) puan yazar; küçük ortak olmak da değerlidir. Muhalefet gensoruyla hükümeti düşürmeye, ortaklar koalisyondan çekilmeye karar verebilir."),
		func() -> Rect2: return _r(R_SIDE), func() -> bool: return GovernmentManager.has_government() and not CardManager.is_turn_blocked())
	_tutorial.add_step("ekonomi", L.t("Vergi ve yatırım"),
		L.t("Hükümettesin: vergi kademesini meclise sunabilir, devlet hazinesinden il yatırımı yapabilirsin. Vergi indirimi seçmene yavaş yansır, seçimden birkaç dönem önce yap. Devlet parasını partinin mitinginde kullanmak usulsüzlüktür ve soruşturmada ortaya çıkar."),
		func() -> Rect2: return _economy_panel.get_global_rect() if _economy_panel != null and _economy_panel.is_visible_in_tree() else _r(R_SIDE),
		func() -> bool: return mine.call() and CardManager.is_government_party(me))
	_tutorial.add_step("puan", L.t("Nasıl kazanılır?"),
		L.t("Kazanan oy oranıyla değil PUANLA belirlenir: hükümette makam, geçen yasa ve başarılı gensoru puan yazar. Sıralamayı PUAN sekmesinden izle."),
		func() -> Rect2: return (_player_tab_buttons[1] as Control).get_global_rect() if _player_tab_buttons.size() > 1 else _r(R_BOARD),
		func() -> bool: return GovernmentManager.has_government() and not CardManager.is_turn_blocked() and _tutorial.seen_count() >= 7)

## Ekranın kart barı DIŞINDA kalan yüksekliği. Harita, alt hazne ve sağ
## sütun hep bunun içinde yerleşir.
func _usable_height() -> float:
	return maxf(120.0, get_viewport_rect().size.y - CARD_BAR_HEIGHT)

## Üst bölgenin (harita + katman düğmeleri) yüksekliği.
func _top_area_height() -> float:
	return _usable_height()

## KART BARI: ekranın en altında tam genişlikte bir şerit. Kendi zemini var,
## kartlar içinde yan yana durur.
func _place_card_bar() -> void:
	if _card_bar_panel == null:
		_card_bar_panel = Panel.new()
		_card_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = DESK_COLOR
		style.border_color = UiTheme.INK
		style.border_width_top = 2
		_card_bar_panel.add_theme_stylebox_override("panel", style)
		add_child(_card_bar_panel)
		move_child(_card_bar_panel, 1)
	_set_rect(_card_bar_panel, _r(R_DESK))
	var hand := _r(R_HAND)
	var viewport_size := get_viewport_rect().size
	hand_area.offset_left = hand.position.x
	hand_area.offset_right = -(viewport_size.x - hand.end.x)
	hand_area.offset_top = hand.position.y
	hand_area.offset_bottom = -(viewport_size.y - hand.end.y)
	# Kartlar masada TAM görünür (ekranın altına taşmaz).
	hand_container.anchor_left = 0.0
	hand_container.anchor_right = 1.0
	hand_container.offset_left = 0.0
	hand_container.offset_right = 0.0
	hand_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	hand_container.grow_horizontal = Control.GROW_DIRECTION_END
	hand_area.clip_contents = false
	hand_container.offset_top = -CARD_DISPLAY_SIZE.y
	hand_container.offset_bottom = 0.0
	_fit_hand_width(CardManager.my_inventory().size())
	_place_desk_labels()

const DESK_COLOR := Color("130f27")
const STRIP_BG := Color("130f27")
var _desk_labels: Dictionary = {}
var _date_chip: PanelContainer
var _date_label: Label
var _map_bg: Panel
var _parl_bg: Panel
var _parl_title: Label
var _parl_summary: Label
var _side_tabs: HBoxContainer
var _side_tab := 0
var _strip_bg: Panel

## Tasarım ızgarasındaki bir dikdörtgeni ekran boyutuna ölçekler.
func _r(rect: Rect2) -> Rect2:
	var k := get_viewport_rect().size / DESIGN
	return Rect2(rect.position * k, rect.size * k)

func _set_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size

static func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true))
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiTheme.GOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Masanın bölüm başlıkları: ELİM · HAMLELER · SIRA.
func _place_desk_labels() -> void:
	for key in ["hand", "actions", "turn"]:
		if not _desk_labels.has(key):
			var label := _section_label("")
			add_child(label)
			_desk_labels[key] = label
	var k := get_viewport_rect().size / DESIGN
	(_desk_labels["hand"] as Label).position = Vector2(16, 538) * k
	(_desk_labels["actions"] as Label).position = Vector2(536, 538) * k
	(_desk_labels["turn"] as Label).position = Vector2(952, 538) * k
	(_desk_labels["actions"] as Label).text = L.t("HAMLELER")
	_refresh_desk_labels()

func _refresh_desk_labels() -> void:
	if _desk_labels.is_empty():
		return
	(_desk_labels["hand"] as Label).text = L.t("ELİM · %d KART") % CardManager.my_inventory().size()
	var peer_id := CardManager.current_turn_peer_id()
	var turn_text := ""
	if peer_id == multiplayer.get_unique_id():
		turn_text = L.t("SIRA SENDE")
	elif peer_id != -1:
		turn_text = L.t("SIRA: %s") % (L.t("Bağımsız") if PartyManager.is_independent(peer_id) else String(PartyManager.data_of(peer_id).get("name", "?")))
	if peer_id != -1 and not CardManager.is_turn_blocked():
		turn_text += "  ·  %s" % GameRules.format_seconds(CardManager.turn_seconds_left())
	(_desk_labels["turn"] as Label).text = turn_text
	_refresh_band_turn()

## Viewport boyutuna bağlı TÜM mutlak-piksel yerleşim hesapları burada — hem
## açılışta hem her yeniden boyutlanmada (tam ekran vb.) çağrılır.
func _apply_layout() -> void:
	if map_holder == null or map_holder.grid_width <= 0:
		return
	var viewport_size := get_viewport_rect().size
	# Harita SADECE üst bölgeye (TOP_AREA_HEIGHT_RATIO) ve sağdaki deste/
	# oyuncu şeridi hariç kalan genişliğe sığacak şekilde ölçekleniyor —
	# geniş, dikdörtgen bir alanı doldurması hedefleniyor.
	var map_rect := _r(R_MAP)
	_ensure_map_bg(map_rect)
	var map_native_size: Vector2 = Vector2(map_holder.grid_width, map_holder.grid_height) * map_holder.MAP_UNIT_SCALE
	var fit_scale: float = minf(map_rect.size.x / map_native_size.x, map_rect.size.y / map_native_size.y) * MAP_FILL_RATIO
	_map_fit_scale = fit_scale
	if _focus_tween == null or not _focus_tween.is_running():
		map_holder.scale = Vector2(fit_scale, fit_scale)
	var map_position := map_rect.position + (map_rect.size - map_native_size * fit_scale) * 0.5
	_ensure_map_clip()
	_map_clip.position = map_position
	_map_clip.size = map_native_size * fit_scale
	if (_map_slide_tween == null or not _map_slide_tween.is_running()) and (_focus_tween == null or not _focus_tween.is_running()):
		map_holder.position = Vector2.ZERO
	_place_layer_bar()

	# CANLI YAYIN BANDI: CANLI · başlık + tarih · sıra kimde (Menü sağda).
	if _strip_bg == null:
		_strip_bg = Panel.new()
		var strip_style := StyleBoxFlat.new()
		strip_style.bg_color = Color("1d1838")
		strip_style.border_color = UiTheme.INK
		strip_style.border_width_bottom = 2
		_strip_bg.add_theme_stylebox_override("panel", strip_style)
		_strip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_strip_bg)
		move_child(_strip_bg, 1)
	_set_rect(_strip_bg, _r(R_BAND))
	_place_date_chip(map_rect)

	# SKOR TABLOSU (sol): VEKİL ve PUAN sekmeleri.
	_ensure_board()
	_set_rect(_board_bg, _r(R_BOARD))
	var strip := get_node_or_null("PlayerPanel") as Control
	if strip != null:
		_set_rect(strip, _r(R_BOARD).grow(-8.0))

	_detach_actions_panel()

	# STÜDYO MASASI (sağ): Hükümet (meclis diyagramıyla) · Log · Seçili.
	_set_rect(left_panel, _r(R_SIDE))
	_setup_side_column()
	_place_parliament_badge()

	# BENİM MASAM: kartlar, hamleler, para, bozdurma, Turu Bitir.
	_place_card_bar()

	# Harita ölçeği değişti => vekil kareleri yeni ölçeğe göre yeniden piksel
	# hizalanmalı (bkz. seat_markers.gd _draw).
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.queue_redraw()
	_place_right_column_controls()
	_rebuild_player_panel()

## Hamle paneli alt banda, kartların sağına taşınır (sahnede meclisin yanındaydı).
func _detach_actions_panel() -> void:
	var panel := bottom_area.get_node_or_null("ChamberSplit/ActionsPanel") as Control
	if panel == null:
		panel = get_node_or_null("ActionsPanel") as Control
	else:
		panel.get_parent().remove_child(panel)
		add_child(panel)
		move_child(panel, hand_area.get_index())
		var title := panel.get_node_or_null("ActionsMargin/ActionsVBox/ActionsTitle")
		if title != null:
			title.hide()
		var margin := panel.get_node_or_null("ActionsMargin") as MarginContainer
		if margin != null:
			for side in ["left", "right", "top", "bottom"]:
				margin.add_theme_constant_override("margin_" + side, 6)
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin2 := panel.get_node_or_null("ActionsMargin") as MarginContainer
	if margin2 != null:
		for side in ["left", "right", "top", "bottom"]:
			margin2.add_theme_constant_override("margin_" + side, 0)
	_set_rect(panel, _r(R_ACTIONS))

## Harita alanının zemini (harita bunun ortasına oturur).
func _ensure_map_bg(rect: Rect2) -> void:
	if _map_bg == null:
		_map_bg = Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("141a36")
		style.border_color = UiTheme.INK
		style.set_border_width_all(2)
		_map_bg.add_theme_stylebox_override("panel", style)
		_map_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_map_bg)
		move_child(_map_bg, 1)
	_set_rect(_map_bg, rect)

## YAYIN BANDI: kırmızı CANLI rozeti, "SİYASET GÜNDEMİ" ve altında tarih /
## baraj / sonraki seçim; ortada sıranın kimde olduğu ve kalan süre.
var _band_live: Label
var _band_title: Label
var _band_turn: PanelContainer
var _band_turn_row: HBoxContainer
var _band_turn_key := ""

var _band_period: Label
var _band_crisis: PanelContainer
var _band_crisis_title: Label
var _band_crisis_text: Label
var _timer_bar_bg: ColorRect
var _timer_bar: ColorRect

func _place_date_chip(_map_rect: Rect2) -> void:
	if _date_label == null:
		_band_period = Label.new()
		_band_period.add_theme_font_override("font", UiTheme.mono(true))
		_band_period.add_theme_font_size_override("font_size", 18)
		_band_period.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_band_period)
		_date_label = Label.new()
		_date_label.add_theme_font_override("font", UiTheme.mono(true))
		_date_label.add_theme_font_size_override("font_size", 11)
		_date_label.add_theme_color_override("font_color", UiTheme.GOLD)
		_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_date_label)
		# KRİZ / GÜNDEM kutusu.
		_band_crisis = PanelContainer.new()
		_band_crisis.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_crisis.clip_contents = true
		var crisis_box := Control.new()
		crisis_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_crisis.add_child(crisis_box)
		_band_crisis_title = Label.new()
		_band_crisis_title.add_theme_font_override("font", UiTheme.mono(true))
		_band_crisis_title.add_theme_font_size_override("font_size", 13)
		_band_crisis_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crisis_box.add_child(_band_crisis_title)
		_band_crisis_text = Label.new()
		_band_crisis_text.add_theme_font_size_override("font_size", 10)
		_band_crisis_text.add_theme_color_override("font_color", UiTheme.TEXT)
		_band_crisis_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crisis_box.add_child(_band_crisis_text)
		_band_crisis_title.position = Vector2(0, 2)
		_band_crisis_text.position = Vector2(0, 24)
		add_child(_band_crisis)
		_band_turn = PanelContainer.new()
		var turn_style := StyleBoxFlat.new()
		turn_style.bg_color = Color("2a2350")
		turn_style.border_color = UiTheme.GOLD
		turn_style.set_border_width_all(2)
		turn_style.content_margin_left = 8
		turn_style.content_margin_right = 8
		_band_turn.add_theme_stylebox_override("panel", turn_style)
		_band_turn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_turn.clip_contents = true
		_band_turn_row = HBoxContainer.new()
		_band_turn_row.add_theme_constant_override("separation", 8)
		_band_turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_turn.add_child(_band_turn_row)
		add_child(_band_turn)
		# SÜRE ŞERİDİ: ekranın en üstünde, sırası gelenin renginde, süre
		# azaldıkça soldan sağa uzar (dolunca süre biter).
		_timer_bar_bg = ColorRect.new()
		_timer_bar_bg.color = Color("0a0816")
		_timer_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_timer_bar_bg.z_index = 7
		add_child(_timer_bar_bg)
		_timer_bar = ColorRect.new()
		_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_timer_bar.z_index = 8
		add_child(_timer_bar)
	_band_period.position = _r(Rect2(16, 12, 0, 0)).position
	_date_label.position = _r(Rect2(16, 38, 0, 0)).position
	_set_rect(_band_crisis, _r(Rect2(300, 11, 444, 46)))
	_set_rect(_band_turn, _r(Rect2(760, 16, 380, 38)))
	_set_rect(_timer_bar_bg, _r(Rect2(0, 0, 1280, TIMER_BAR_HEIGHT)))
	_refresh_band_date()
	_refresh_band_crisis()
	_band_turn_key = ""
	_refresh_band_turn()
	_refresh_timer_bar()

const TIMER_BAR_HEIGHT := 7.0

func _refresh_band_date() -> void:
	if _band_period == null:
		return
	var next_election := CardManager.next_election_round()
	_band_period.text = GameRules.period_label(mini(CardManager.round_number, GameRules.MAX_ROUNDS))
	var parts := [L.t("Baraj %%%s") % _format_threshold(MultiplayerManager.election_threshold),
		(L.t("Sonraki seçim %d") % GameRules.election_year(next_election)) if next_election != -1 else L.t("Başka seçim yok")]
	if MultiplayerManager.seat_method != MultiplayerManager.DEFAULT_SEAT_METHOD:
		parts.append(ElectionModel.method_title(MultiplayerManager.seat_method))
	_date_label.text = "  ·  ".join(PackedStringArray(parts))

## KRİZ (kırmızı) ya da sadece GÜNDEM (altın) bantta; ikisi de yoksa gizli.
func _refresh_band_crisis() -> void:
	if _band_crisis == null:
		return
	var crisis := CardManager.crisis_type()
	var agenda := CardManager.agenda_type()
	_band_crisis.visible = crisis != "" or agenda != ""
	if not _band_crisis.visible:
		return
	var style := StyleBoxFlat.new()
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.border_width_left = 6
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	if crisis != "":
		var data := CardPresets.crisis_data(crisis)
		style.bg_color = Color("4a1020")
		style.border_color = Color("ff3b4e")
		_band_crisis_title.text = L.t("⚠ KRİZ · %s") % data["title"]
		_band_crisis_title.add_theme_color_override("font_color", Color("ff8a94"))
		_band_crisis_text.text = L.t("%s için yasa / toplantı ulusal destek getirir") % data["group_title"]
	else:
		var data := CardPresets.agenda_data(agenda)
		style.bg_color = Color("2a2350")
		style.border_color = UiTheme.GOLD
		_band_crisis_title.text = L.t("GÜNDEM · %s") % data["title"]
		_band_crisis_title.add_theme_color_override("font_color", UiTheme.GOLD)
		_band_crisis_text.text = L.t("%s için yasa / toplantı ulusal destek getirir") % data["group_title"]
	_band_crisis.add_theme_stylebox_override("panel", style)

func _refresh_timer_bar() -> void:
	if _timer_bar == null:
		return
	var peer_id := CardManager.current_turn_peer_id()
	var full := _r(Rect2(0, 0, 1280, TIMER_BAR_HEIGHT))
	if peer_id == -1 or CardManager.is_turn_blocked() or CardManager.game_finished:
		_timer_bar.size = Vector2(0, full.size.y)
		return
	var elapsed := clampf(1.0 - CardManager.turn_seconds_left() / GameRules.TURN_TIMEOUT, 0.0, 1.0)
	_timer_bar.position = full.position
	_timer_bar.size = Vector2(full.size.x * elapsed, full.size.y)
	_timer_bar.color = PartyManager.data_of(CardManager.party_of(peer_id)).get("bg_color", UiTheme.GOLD)

## Banttaki sıra kutusu: logo · SIRA: PARTİ (siyasetçi) · süre.
func _refresh_band_turn() -> void:
	if _band_turn_row == null:
		return
	var peer_id := CardManager.current_turn_peer_id()
	var timer := "" if peer_id == -1 or CardManager.is_turn_blocked() else GameRules.format_seconds(CardManager.turn_seconds_left())
	var key := "%d|%s|%s" % [peer_id, timer, PartyManager.data_of(peer_id).get("name", "")]
	if key == _band_turn_key:
		return
	_band_turn_key = key
	for child in _band_turn_row.get_children():
		_band_turn_row.remove_child(child)
		child.queue_free()
	_band_turn.visible = peer_id != -1
	if peer_id == -1:
		return
	var badge := PartyBadge.build(PartyManager.data_of(peer_id), Vector2(22, 22), BADGE_ICON_PIXEL_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_band_turn_row.add_child(badge)
	var party_text := L.t("Bağımsız") if PartyManager.is_independent(peer_id) else String(PartyManager.data_of(peer_id).get("name", "?"))
	var text := L.t("SIRA SENDE") if peer_id == multiplayer.get_unique_id() else L.t("SIRA: %s · %s") % [party_text, PoliticianPresets.display_name(peer_id)]
	var label := _avatar_label(text, _fit_font_size(text, _r(Rect2(0, 0, 300, 0)).size.x, 14, 8), UiTheme.TEXT)
	label.add_theme_font_override("font", UiTheme.mono(true))
	label.clip_text = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_band_turn_row.add_child(label)
	var time_label := _avatar_label(timer, 14, UiTheme.GOLD)
	time_label.add_theme_font_override("font", UiTheme.mono(true))
	time_label.clip_text = false
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_band_turn_row.add_child(time_label)

## MECLİS: stüdyo masasının HÜKÜMET sekmesinde, sekmelerin hemen altındaki
## yuvada; oylama sürerken büyür, teklif metni ve EVET/ÇEKİMSER/HAYIR görünür (bkz. _parl_slot). Oylama başlayınca Hükümet sekmesi kendiliğinden açılır.
var _parl_slot: Control
var _was_voting := false

func _place_parliament_badge() -> void:
	var voting := GovernmentManager.is_voting()
	var just_started := voting and not _was_voting
	_was_voting = voting
	if _parl_bg == null:
		_parl_bg = Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("15112b")
		style.border_color = Color("3f3775")
		style.set_border_width_all(1)
		_parl_bg.add_theme_stylebox_override("panel", style)
		_parl_bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_parl_bg)
		move_child(_parl_bg, bottom_area.get_index())
		var vbox := bottom_area.get_node_or_null("ChamberSplit/ParliamentChamber/ParliamentVBox") as VBoxContainer
		if vbox != null:
			_parl_title = _section_label(L.t("MECLİS · %d") % CardManager.TOTAL_SEATS)
			vbox.add_child(_parl_title)
			vbox.move_child(_parl_title, 0)
			_parl_summary = Label.new()
			_parl_summary.add_theme_font_override("font", UiTheme.mono(true))
			_parl_summary.add_theme_font_size_override("font_size", 10)
			_parl_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_parl_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(_parl_summary)
			vbox.move_child(_parl_summary, 2)
			vbox.add_theme_constant_override("separation", 4)
		var chamber := bottom_area.get_node_or_null("ChamberSplit/ParliamentChamber") as MarginContainer
		if chamber != null:
			for side in ["left", "right", "top", "bottom"]:
				chamber.add_theme_constant_override("margin_" + side, 5)
		var split := bottom_area.get_node_or_null("ChamberSplit") as Control
		if split != null:
			split.offset_top = 0
			split.offset_bottom = 0
	# Meclis sağ panelin ÜSTÜNDE olmalı (sahne ağacında sonra gelmeli): yoksa
	# panel tıklamaları yutuyor, EVET/HAYIR düğmelerine basılamıyordu.
	if _parl_bg.get_index() < left_panel.get_index():
		move_child(_parl_bg, left_panel.get_index())
		move_child(bottom_area, _parl_bg.get_index() + 1)
	bottom_area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bottom_area.z_index = 4
	_parl_bg.z_index = 3
	if just_started and _side_tabs != null:
		# Oylama herkesin önüne gelsin: Seçili/Log açıksa Hükümet'e dön.
		_side_tab = 0
		if _left_dock != null and _left_dock.visible:
			_pinned = false
			_hide_profile()
			if _province_panel != null and _province_panel.embedded_mode:
				_province_panel.hide()
		_refresh_side_tabs()
	if _parl_slot != null:
		_parl_slot.custom_minimum_size.y = (PARL_SLOT_VOTE_HEIGHT if voting else PARL_SLOT_HEIGHT) * _r(R_SIDE).size.y / R_SIDE.size.y
	var vote_row := bottom_area.get_node_or_null("ChamberSplit/ParliamentChamber/ParliamentVBox/VoteButtonRow") as Control
	if vote_row != null:
		vote_row.visible = voting
	proposal_label.visible = voting
	_refresh_parliament_summary()
	_sync_parliament_to_slot()

## Meclis (zemin + diyagram) her kare yuvanın ekrandaki yerine oturur; yuva
## görünmüyorsa (Log / Seçili sekmesi) meclis de gizlenir.
func _sync_parliament_to_slot() -> void:
	if _parl_bg == null:
		return
	var shown := _parl_slot != null and _parl_slot.is_visible_in_tree()
	_parl_bg.visible = shown
	bottom_area.visible = shown
	if not shown:
		return
	var rect := _parl_slot.get_global_rect()
	if _parl_bg.position != rect.position or _parl_bg.size != rect.size:
		_set_rect(_parl_bg, rect)
		bottom_area.position = rect.position
		bottom_area.size = rect.size

func _refresh_parliament_summary() -> void:
	if _parl_summary == null:
		return
	var gov := 0
	for pid in GovernmentManager.government_party_ids():
		gov += int(CardManager.last_seats.get(pid, 0))
	var total := 0
	for k in CardManager.last_seats.keys():
		total += int(CardManager.last_seats[k])
	_parl_title.text = L.t("MECLİS · %d") % maxi(total, CardManager.TOTAL_SEATS)
	if total <= 0:
		_parl_summary.text = L.t("İlk seçimden önce meclis boş")
		_parl_summary.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		return
	var majority := total / 2 + 1
	_parl_summary.text = (L.t("Hük %d · çoğ %d · Muh %d") % [gov, majority, total - gov]) if GovernmentManager.has_government() \
		else L.t("Hükümet yok · çoğunluk %d") % majority
	_parl_summary.add_theme_color_override("font_color", UiTheme.TEXT)

## SAĞ SÜTUN: üstte sekmeler; Hükümet (hükümet + son olaylar), Log (sadece
## log), Seçili (dokunulan il / parti). Eski bilgi kutusu ve sıra göstergesi
## buradan kalktı (tarih haritada, sıra masada).
func _setup_side_column() -> void:
	var vbox := left_panel.get_node_or_null("LeftMargin/LeftScroll/LeftVBox") as VBoxContainer
	if vbox == null:
		return
	var margin := left_panel.get_node_or_null("LeftMargin") as MarginContainer
	if margin != null:
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
	for node_name in ["InfoPlate", L.t("Separator1"), L.t("TurnIndicator"), L.t("TurnSpacer")]:
		var node := vbox.get_node_or_null(node_name) as Control
		if node != null:
			node.hide()
	if _side_tabs == null:
		_side_tabs = HBoxContainer.new()
		_side_tabs.add_theme_constant_override("separation", 4)
		for i in SIDE_TAB_TITLES.size():
			var tab := Button.new()
			tab.text = SIDE_TAB_TITLES[i]
			tab.focus_mode = Control.FOCUS_NONE
			tab.add_theme_font_size_override("font_size", 11)
			tab.add_theme_font_override("font", UiTheme.mono(true))
			tab.custom_minimum_size = Vector2(0, 28)
			tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tab.pressed.connect(_on_side_tab.bind(i))
			_side_tabs.add_child(tab)
		vbox.add_child(_side_tabs)
		vbox.move_child(_side_tabs, 0)
		# Meclis diyagramının yeri (sadece Hükümet sekmesinde görünür).
		_parl_slot = Control.new()
		_parl_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(_parl_slot)
		vbox.move_child(_parl_slot, 1)
		# EKONOMİ ÖZETİ: meclisin hemen altında (sadece Hükümet sekmesinde).
		_economy_panel = EconomyPanel.new()
		_economy_panel.tax_policy_requested.connect(_open_tax_panel)
		vbox.add_child(_economy_panel)
		vbox.move_child(_economy_panel, 2)
		_economy_panel.refresh()
	_refresh_side_tabs()

var _score_scroll: ScrollContainer
var _score_box: VBoxContainer
const SIDE_TAB_TITLES := ["HÜKÜMET", "LOG", "SEÇİLİ"]
const SIDE_TAB_SELECTED := 2

## SKOR TABLOSU (sol sütun): zemin, sekmeler, VEKİL listesi (kaydırılabilir)
## ve PUAN tablosu.
var _board_bg: Panel
var _board_scroll: ScrollContainer

func _ensure_board() -> void:
	if _board_bg != null:
		return
	_board_bg = Panel.new()
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.skin_panel(_board_bg, UiSkin.PANEL_DARK)
	add_child(_board_bg)
	move_child(_board_bg, 1)
	var box := player_panel_list.get_parent() as VBoxContainer
	_board_scroll = ScrollContainer.new()
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_board_scroll)
	box.move_child(_board_scroll, player_panel_list.get_index())
	box.remove_child(player_panel_list)
	player_panel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scroll.add_child(player_panel_list)
	_score_scroll = ScrollContainer.new()
	_score_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_score_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_score_scroll.hide()
	_score_box = VBoxContainer.new()
	_score_box.add_theme_constant_override("separation", 4)
	_score_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_scroll.add_child(_score_box)
	box.add_child(_score_scroll)

## Puan tablosu: siyasetçiler puana göre sıralı; satırda sıra, parti rengi,
## siyasetçi ve partisi, puan, partinin ulusal puanı (kamuoyu).
## Bir durum güncellemesinde birkaç sinyal aynı paneli yeniden kuruyordu
## (kare başına 20-35 ms); artık kare sonunda BİR kez kurulur (performans).
func _refresh_score_table() -> void:
	if _deferred_ui.has("_refresh_score_table"):
		return
	_deferred_ui["_refresh_score_table"] = true
	_run_deferred_ui.call_deferred("_refresh_score_table")

func _refresh_score_table_now() -> void:
	if _score_box == null or not _score_scroll.visible:
		return
	for child in _score_box.get_children():
		child.queue_free()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	var title := _section_label(L.t("SİYASETÇİ"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for column in ["PUAN", L.t("ULUSAL")]:
		var label := _section_label(column)
		label.custom_minimum_size = Vector2(46, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(label)
	_score_box.add_child(header)
	var ids: Array = _ordered_peer_ids().duplicate()
	ids.sort_custom(func(a, b): return GovernmentManager.score_of(int(a)) > GovernmentManager.score_of(int(b)))
	var me := multiplayer.get_unique_id()
	for i in ids.size():
		var peer_id := int(ids[i])
		var pid := CardManager.party_of(peer_id)
		var party: Dictionary = PartyManager.data_of(pid)
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("2a2350") if peer_id == me else Color("15112b")
		style.border_color = party.get("bg_color", Color.GRAY)
		style.border_width_left = 4
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		row.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		row.add_child(line)
		var rank := _table_value(str(i + 1), 16.0, UiTheme.TEXT_DIM, 11)
		line.add_child(rank)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", -3)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(names)
		var person := PoliticianPresets.display_name(peer_id)
		var name_label := _avatar_label(person, _fit_font_size(person, 150.0, 12, 8), UiTheme.GOLD if peer_id == me else UiTheme.TEXT)
		name_label.clip_text = false
		name_label.add_theme_font_override("font", UiTheme.mono(true))
		names.add_child(name_label)
		var party_text := L.t("Bağımsız") if PartyManager.is_independent(pid) else String(party.get("name", "?"))
		if CardManager.is_party_member(peer_id):
			party_text += L.t(" · üye")
		names.add_child(_avatar_label(party_text, 10, UiTheme.TEXT_MUTED))
		line.add_child(_table_value(str(GovernmentManager.score_of(peer_id)), 40.0, UiTheme.GOLD, 13))
		var national := CardManager.national_of(pid)
		var trend_value := _table_value(EffectWords.arrows(national), 46.0, ProvincePanel._opinion_color(national), 12)
		trend_value.tooltip_text = L.t("Ulusal kamuoyu: %s") % EffectWords.standing(national)
		trend_value.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(trend_value)
		_score_box.add_child(row)

func _on_side_tab(index: int) -> void:
	if index == SIDE_TAB_SELECTED:
		return  # "Seçili" bir il ya da partiye dokununca açılır
	_side_tab = index
	_hide_profile()
	if _province_panel != null and _province_panel.embedded_mode:
		_province_panel.hide()
	_refresh_side_tabs()

func _refresh_side_tabs() -> void:
	if _side_tabs == null:
		return
	var selected_open := _left_dock != null and _left_dock.visible
	var active := SIDE_TAB_SELECTED if selected_open else _side_tab
	for i in _side_tabs.get_child_count():
		var tab := _side_tabs.get_child(i) as Button
		UiSkin.skin_color_button(tab, UiTheme.GOLD if i == active else UiTheme.PANEL_LIGHT)
		tab.add_theme_color_override("font_color", UiTheme.INK if i == active else UiTheme.TEXT_MUTED)
		tab.disabled = i == SIDE_TAB_SELECTED and not selected_open
		# Pencere modunda il ve profil pencerede açılır: "Seçili" sekmesine gerek yok.
		tab.visible = i != SIDE_TAB_SELECTED or not _window_mode()
	if not selected_open:
		government_vbox.visible = _side_tab == 0
		# Log ayrı sekmede: Hükümet sekmesinde yok.
		if _event_log != null:
			_event_log.visible = _side_tab == 1
	if _parl_slot != null:
		_parl_slot.visible = not selected_open and _side_tab == 0
	if _economy_panel != null:
		# Oylamada meclis yuvası büyür: ekonomi kutusu yer açar (hükümet bilgisi
		# 720p'de de görünür kalsın), oylama bitince geri gelir.
		_economy_panel.visible = not selected_open and _side_tab == 0 			and GovernmentManager.phase != GovernmentManager.Phase.VOTING
	_sync_parliament_to_slot()

## İl inceleme ayarı: PENCERE ise il ve profil haritanın üstünde pencerede açılır.
func _window_mode() -> bool:
	return GameSettings.province_view == GameSettings.ProvinceView.WINDOW

func _on_province_view_changed(_mode: int) -> void:
	_hide_profile()
	if _province_panel != null:
		_province_panel.queue_free()
		_province_panel = null
	_update_left_dock()
	_refresh_side_tabs()

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
	# Ekran donar: kararma sürerken paneller yeni meclisi / hükümet görevini
	# gösterse de görünmez (seçimden önce sonucu ele veriyordu).
	SceneTransition.freeze_and_fade_to_scene("res://scenes/ElectionResults.tscn")

## Seçimsiz bir tur bitti: hükümet puanlarını aldı, yeni tur başladı.
func _on_round_advanced() -> void:
	_refresh_game_settings_label()
	_refresh_score_panel()
	_refresh_government_panel()

func _on_game_over() -> void:
	_refresh_score_panel()
	if _game_over_overlay != null and is_instance_valid(_game_over_overlay):
		return
	_game_over_overlay = GameOverOverlay.new()
	add_child(_game_over_overlay)
	# Puan tablosu geldiği an jenerik müziği başlar.
	AudioManager.play_music("credits")

func _on_proposal_resolved(accepted: bool, kind: String, proposer_id: int) -> void:
	# Sonuç metni olay loguna CardManager üzerinden düşer; büyük sonuçlar ayrıca
	# gazete manşeti olur.
	_headline_for_proposal(accepted, kind, proposer_id)
	if accepted and kind == GovernmentManager.KIND_CONSTITUTION and _constitution_alliances != null:
		_constitution_alliances.set_pressed_no_signal(CardManager.alliances_enabled)
		_refresh_constitution_section()

# --- OLAY GAZETESİ (EventFx, 0.0.179) -------------------------------------------
## Büyük olaylar gazete manşeti olarak sunulur. Sadece GÖSTERİM: veriler oyun
## durumundan okunur (olay zaten uygulanmıştır), hiçbir şey değiştirilmez.
var _event_fx: EventFx

func _build_event_fx() -> void:
	_event_fx = EventFx.new()
	add_child(_event_fx)
	CardManager.event_presented.connect(_headline_for_event)
	CardManager.event_presented.connect(func(_event: Dictionary, _version: int):
		if _alliance_panel != null and _alliance_panel.visible:
			_refresh_alliance_panel())
	GovernmentManager.coalition_changed.connect(_headline_for_coalition)
	tree_exiting.connect(_event_fx.skip_all)
	# Afet seçim gecesinde başladıysa gazetesi oyun ekranına dönünce oynar.
	if CardManager.has_disaster():
		get_tree().create_timer(0.8).timeout.connect(func(): _headline_for_disaster(CardManager.active_disaster()))
	_refresh_disaster.call_deferred()

func _fx_party_name(peer_id: int) -> String:
	return String(PartyManager.data_of(peer_id).get("name", "?"))

## Kart ve parti olayları (CardManager.event_presented).
func _headline_for_event(event: Dictionary, version: int) -> void:
	if event.has("disaster"):
		_headline_for_disaster(event["disaster"])
	var type := String(event.get("type", ""))
	var message := String(event.get("message", ""))
	var key := "cm|%d|%s" % [version, type]
	match type:
		"played":
			var card := String(event.get("card", ""))
			var target := int(event.get("target", -1))
			var actor := int(event.get("peer_id", -1))
			match card:
				CardPresets.REPUTATION_CARD_TYPE:
					_event_fx.present(key, {"headline": L.t("SİYASETİ SARSAN KASET!"), "subtitle": message,
						"art": CardPresets.get_card_texture(card), "party": target, "accent": UiTheme.RED,
						"style": "scandal", "status": L.t("İTİBAR SUİKASTI")})
				CardPresets.REBELLION_CARD_TYPE:
					_event_fx.present(key, {"headline": L.t("PARTİDE ÇATLAK BÜYÜYOR!"), "subtitle": message,
						"art": CardPresets.get_card_texture(card), "party": target,
						"accent": PartyManager.data_of(target).get("bg_color", UiTheme.GREEN_DARK),
						"style": "conflict", "status": L.t("İÇ KARIŞIKLIK")})
				CardPresets.STEAL_STRONG_CARD_TYPE:
					if bool(event.get("seats_changed", false)):
						_event_fx.present(key, {"headline": L.t("MECLİSTE DENGELER DEĞİŞTİ!"), "subtitle": message,
							"art": CardPresets.get_card_texture(card), "party": actor, "accent": UiTheme.GOLD,
							"status": L.t("VEKİL TRANSFERİ")})
				CardPresets.FUNDS_BONUS_STRONG_CARD_TYPE:
					_event_fx.present(key, {"headline": L.t("PARTİ KASASINA DEV DESTEK!"),
						"subtitle": message if message != "" else L.t("%s büyük bir bağış kampanyası düzenledi.") % _fx_party_name(actor),
						"art": CardPresets.get_card_texture(card), "party": actor, "accent": UiTheme.GREEN_DARK,
						"stamp": "+" + GameRules.cost_text(GameRules.FUNDS_BONUS_STRONG)})
		"party_split":
			var parent := int(event.get("peer_id", -1))
			_event_fx.present(key, {"headline": L.t("PARTİ İKİYE BÖLÜNDÜ!"), "subtitle": message,
				"art": CardPresets.get_card_texture(CardPresets.REBELLION_CARD_TYPE), "party": parent,
				"accent": PartyManager.data_of(parent).get("bg_color", UiTheme.RED), "style": "conflict",
				"stamp": L.t("BÖLÜNDÜ")})
		"alliance_created":
			var alliance: Dictionary = CardManager.alliances.get(int(event.get("alliance_id", -1)), {})
			_event_fx.present(key, {"headline": L.t("SANDIKTA GÜÇLER BİRLEŞİYOR!"), "subtitle": message,
				"party": int(event.get("peer_id", -1)), "accent": alliance.get("color", UiTheme.GOLD),
				"style": "conflict", "status": L.t("İTTİFAK KURULDU"), "stamp": String(alliance.get("name", ""))})
		"alliance_joined":
			var alliance: Dictionary = CardManager.alliances.get(int(event.get("alliance_id", -1)), {})
			_event_fx.present(key, {"headline": L.t("İTTİFAK GENİŞLİYOR!"), "subtitle": message,
				"party": int(event.get("peer_id", -1)), "accent": alliance.get("color", UiTheme.GOLD),
				"style": "conflict", "status": L.t("İTTİFAKA KATILDI"), "stamp": String(alliance.get("name", ""))})

## Meclis oylamalarının büyük sonuçları (gensoru, erken seçim, güvenoyu, anayasa).
func _headline_for_proposal(accepted: bool, kind: String, proposer_id: int) -> void:
	var reason := GovernmentManager.last_resolution_reason
	var key := "gm|%s|%d|%d|%d|%d" % [kind, proposer_id, int(accepted), CardManager.round_number, reason.hash()]
	match kind:
		GovernmentManager.KIND_CENSURE:
			if accepted:
				_event_fx.present(key, {"headline": L.t("HÜKÜMET GENSORUYLA DÜŞTÜ!"), "subtitle": reason,
					"party": proposer_id, "accent": UiTheme.RED, "stamp": L.t("DÜŞTÜ"), "sound": "vote_no",
					"status": L.t("GENSORU KABUL")})
			else:
				_event_fx.present(key, {"headline": L.t("HÜKÜMET GENSORUYU ATLATTI"), "subtitle": reason,
					"party": GovernmentManager.main_gov_peer_id, "accent": UiTheme.GREEN_DARK,
					"stamp": L.t("AYAKTA"), "sound": "vote_yes", "status": L.t("GENSORU REDDEDİLDİ")})
		GovernmentManager.KIND_EARLY:
			if accepted:
				_event_fx.present(key, {"headline": L.t("ÜLKE YENİDEN SANDIĞA GİDİYOR!"), "subtitle": reason,
					"art": CardPresets.get_card_texture(CardPresets.EARLY_ELECTION_CARD_TYPE), "party": proposer_id,
					"accent": UiTheme.GOLD_DIM, "stamp": L.t("ERKEN SEÇİM")})
		GovernmentManager.KIND_GOVERNMENT:
			if accepted:
				_event_fx.present(key, {"headline": L.t("YENİ HÜKÜMET GÜVENOYU ALDI!"), "subtitle": reason,
					"party": proposer_id, "accent": UiTheme.GREEN_DARK, "stamp": L.t("GÜVENOYU"),
					"sound": "law_passed"})
		GovernmentManager.KIND_CONSTITUTION:
			if accepted:
				_event_fx.present(key, {"headline": L.t("ANAYASA DEĞİŞTİ!"), "subtitle": reason,
					"party": proposer_id, "accent": UiTheme.PURPLE, "stamp": L.t("KABUL"), "sound": "law_passed"})

## Koalisyondan çekilme (GovernmentManager.coalition_changed). Aynı sinyal
## "ortaklar anlaştı" için de gelir; sadece çekilme manşet olur.
func _headline_for_coalition(text: String) -> void:
	if not _is_withdrawal_text(text):
		return
	_event_fx.present("co|%d|%d" % [CardManager.round_number, text.hash()], {
		"headline": L.t("KOALİSYONDA YOLUN SONU!"), "subtitle": text,
		"party": GovernmentManager.main_gov_peer_id, "accent": UiTheme.RED_DARK, "style": "conflict",
		"status": L.t("KOALİSYON")})

## Çekilme metni host'un dilinde gelir: bütün dillerdeki kalıpla karşılaştırılır.
static func _is_withdrawal_text(text: String) -> bool:
	var template := "%s koalisyondan çekildi: %s.%s%s%s"
	var fragments: Array = [template.split("%s")[1]]
	for locale in L.LOCALES:
		var translation := TranslationServer.get_translation_object(locale)
		if translation != null:
			var translated := String(translation.get_message(template))
			if translated != "" and translated.split("%s").size() > 1:
				fragments.append(translated.split("%s")[1])
	for fragment in fragments:
		if String(fragment).strip_edges() != "" and text.contains(String(fragment)):
			return true
	return false

## Seçim gecesinden dönünce: kesin sonuç manşeti (birinci parti, vekil, oy).
## OLAY LOGU: sol panelde hükümet bilgisi ile sıra göstergesi arasındaki boşluk.
## (Eski üst bant yazısı kaldırıldı; her olay ve uyarı buraya düşer.)
func _build_event_log() -> void:
	_event_log = EventLogPanel.new()
	_event_log.name = L.t("EventLog")
	_event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var spacer := left_panel.get_node_or_null("LeftMargin/LeftScroll/LeftVBox/TurnSpacer")
	if spacer != null:
		spacer.get_parent().add_child(_event_log)
		spacer.get_parent().move_child(_event_log, spacer.get_index())
		spacer.hide()
	else:
		add_child(_event_log)
	_event_log.focus_requested.connect(_focus_log_entry)

## Oyuncuya kişisel uyarı/ipucu: log'a sistem satırı olarak düşer.
func _show_toast(text: String) -> void:
	CardManager.log_event(text, -1, "", "hint")

## Log satırındaki odak düğmesi: harita ile yakınlaşır (FOCUS_MOVE), bölge
## hamleyi yapanın renginde parlar (FOCUS_HOLD), sonra harita eski yerine döner.
func _focus_log_entry(entry: Dictionary) -> void:
	var province_id := String(entry.get("province", ""))
	if province_id == "" or _map_clip == null or _layer_switching:
		return
	if _focus_tween != null and _focus_tween.is_running():
		_focus_tween.kill()
	var base_scale := _map_fit_scale
	var zoom := base_scale * FOCUS_ZOOM
	var target := _map_clip.size * 0.5 - GameMap.center_of(province_id) * zoom
	# Harita kutusunun dışına fazla taşmasın.
	var min_pos := _map_clip.size - GameMap.map_size() * zoom
	target = Vector2(clampf(target.x, min_pos.x, 0.0), clampf(target.y, min_pos.y, 0.0))
	var color: Color = PartyManager.data_of(int(entry.get("peer_id", -1))).get("bg_color", UiTheme.GOLD)
	_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.set_parallel(true)
	_focus_tween.tween_property(map_holder, "scale", Vector2(zoom, zoom), FOCUS_MOVE)
	_focus_tween.tween_property(map_holder, "position", target, FOCUS_MOVE)
	_focus_tween.chain().tween_callback(func():
		map_holder.pulse_province(province_id, color, _focus_icon(String(entry.get("kind", ""))), FOCUS_HOLD))
	_focus_tween.chain().tween_interval(FOCUS_HOLD)
	_focus_tween.chain().tween_property(map_holder, "scale", Vector2(base_scale, base_scale), FOCUS_MOVE)
	_focus_tween.parallel().tween_property(map_holder, "position", Vector2.ZERO, FOCUS_MOVE)

## KONGRE GECESİ: herkesin ekranında, seçim gecesi tarzında.
func _on_congress_started(data: Dictionary) -> void:
	var congress_view: Control = preload("res://scripts/congress_show.gd").new()
	congress_view.data = data
	add_child(congress_view)  # sonuç gazetesini kendisi oynatır

## Haritada bir hamle olunca (ili olan her log kaydı) ilin üstünde, log
## kaydına dokununca oynayan animasyonun YAKINLAŞTIRMASIZ hâli oynar.
func _pulse_logged_province(entry: Dictionary) -> void:
	var province_id := String(entry.get("province", ""))
	if province_id == "" or map_holder == null or _layer_switching:
		return
	var color: Color = PartyManager.data_of(int(entry.get("peer_id", -1))).get("bg_color", UiTheme.GOLD)
	map_holder.pulse_province(province_id, color, _focus_icon(String(entry.get("kind", ""))), FOCUS_HOLD)

static func _focus_icon(kind: String) -> String:
	match kind:
		"miting":
			return "mic"
		"karalama":
			return "megaphone"
		"kaset":
			return "tape"
		"invest":
			return "factory"
		"organization":
			return "flag"
	return "pin"

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

## Seçim sonuçları artık sağdaki EVRENSEL PARTİ TABLOSUNDA (sekmeler) —
## ayrı bir "son seçim" paneli yok.
func _refresh_results_panels() -> void:
	_rebuild_player_panel()
	_refresh_parliament_diagram()
	_refresh_map_seat_markers()
	_refresh_province_winner_colors()

## Parlamento diyagramı: koltuklar parti renginde; oylama sırasında oy vermiş
## partilerin koltukları verdikleri oyun rengine (EVET/ÇEKİMSER/HAYIR) bürünür.
## Parti sırası sabit kalır, koltuklar yer değiştirmez.
## Bir durum güncellemesinde birkaç sinyal aynı paneli yeniden kuruyordu
## (kare başına 20-35 ms); artık kare sonunda BİR kez kurulur (performans).
func _refresh_parliament_diagram() -> void:
	if _deferred_ui.has("_refresh_parliament_diagram"):
		return
	_deferred_ui["_refresh_parliament_diagram"] = true
	_run_deferred_ui.call_deferred("_refresh_parliament_diagram")

func _refresh_parliament_diagram_now() -> void:
	var ids: Array = CardManager.last_seats.keys()
	ids.sort_custom(func(a, b):
		return float(CardManager.last_vote_shares.get(a, 0.0)) > float(CardManager.last_vote_shares.get(b, 0.0)))
	var voting := GovernmentManager.is_voting()
	var entries: Array = []
	for peer_id in ids:
		var color: Color = PartyManager.data_of(peer_id).get("bg_color", Color(0.5, 0.5, 0.5))
		var seats := int(CardManager.last_seats[peer_id])
		# İki kişilik partide genel başkan 2/3'ünü, yardımcı 1/3'ünü yönetir:
		# her parça kendi verdiği oyun rengine bürünür.
		var deputy := PartyManager.deputy_of(int(peer_id))
		var parts: Array = [[int(peer_id), seats]]
		if voting and deputy != -1:
			var leader_part := GovernmentManager.vote_weight(int(peer_id))
			parts = [[int(peer_id), leader_part], [deputy, seats - leader_part]]
		for part in parts:
			var part_color := color
			if voting and GovernmentManager.votes.has(part[0]):
				part_color = VOTE_COLORS[int(GovernmentManager.votes[part[0]])]
			entries.append({"seats": int(part[1]), "color": part_color})
	if entries.is_empty():
		# İlk seçimden önce: bembeyaz, boş bir meclis (yasa dairesi buraya sürüklenir).
		entries.append({"seats": CardManager.TOTAL_SEATS, "color": EMPTY_SEAT_COLOR})
	parliament_diagram.set_results(entries)

## Oylar değişti: diyagram renkleri, profillerdeki oy etiketleri ve (oylanan
## hükümet için) sol panel güncellenir.
func _on_proposal_changed() -> void:
	_place_parliament_badge()
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
		# koltuğu alan partinin kendi rengi, tam opak.
		var party_color: Color = PartyManager.data_of(winner_id).get("bg_color", Color(0.5, 0.5, 0.5))
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
			var color: Color = PartyManager.data_of(peer_id).get("bg_color", Color(0.5, 0.5, 0.5))
			for i in seats:
				colors.append(color)
		if not colors.is_empty():
			seat_markers.set_seats(province_id, colors)

func _refresh_game_settings_label() -> void:
	var next_election := CardManager.next_election_round()
	game_settings_label.text = L.t("%s  ·  Baraj %%%s\n%s") % [
		GameRules.period_label(mini(CardManager.round_number, GameRules.MAX_ROUNDS)),
		_format_threshold(MultiplayerManager.election_threshold),
		(L.t("Sonraki seçim: %d") % GameRules.election_year(next_election)) if next_election != -1 else L.t("Başka seçim yok"),
	]
	if MultiplayerManager.seat_method != MultiplayerManager.DEFAULT_SEAT_METHOD:
		game_settings_label.text += L.t("\nSayım: ") + ElectionModel.method_title(MultiplayerManager.seat_method)
	_refresh_band_date()

func _format_threshold(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value

## Anayasa paketi meclise sunulur (2/3 gerekir).
func _on_constitution_pressed() -> void:
	CardManager.propose_constitution({"threshold": _constitution_threshold, "interval": _constitution_interval,
		"seat_method": _constitution_method,
		"alliances_enabled": _constitution_alliances.button_pressed if _constitution_alliances != null else CardManager.alliances_enabled})
	_law_designer.hide()

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
			map_holder.set_province_color(province_id, Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.6))

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

## ÜÇ SEKME: tablonun hangi sütunları göstereceğini seçen dikdörtgen butonlar.
func _build_player_tabs() -> void:
	_player_tab_buttons.clear()
	for child in player_tabs.get_children():
		child.queue_free()
	for i in PLAYER_TAB_TITLES.size():
		var button := Button.new()
		button.text = PLAYER_TAB_TITLES[i]
		button.tooltip_text = PLAYER_TAB_TOOLTIPS[i]
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", UiTheme.FS_TINY)
		button.pressed.connect(_on_player_tab_pressed.bind(i))
		player_tabs.add_child(button)
		_player_tab_buttons.append(button)
	_refresh_player_tabs()

func _on_player_tab_pressed(index: int) -> void:
	if _player_tab == index:
		return
	_player_tab = index
	_refresh_player_tabs()
	_rebuild_player_panel()

func _refresh_player_tabs() -> void:
	for i in _player_tab_buttons.size():
		var button := _player_tab_buttons[i] as Button
		UiSkin.skin_color_button(button, UiTheme.GOLD if i == _player_tab else UiTheme.PANEL_LIGHT)
		button.add_theme_color_override("font_color", UiTheme.INK if i == _player_tab else UiTheme.TEXT_MUTED)
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", 11)

## Tablonun sütun başlıkları: parti adının sağında, satırlarla aynı hizada.
func _build_player_header() -> Control:
	# Satır kartlarının iç boşluğuyla aynı hizada dursun diye kenar payı.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(1, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	for column in PLAYER_TAB_COLUMNS[_player_tab]:
		row.add_child(_table_value(String(column[0]), float(column[1]), UiTheme.TEXT_DIM, UiTheme.FS_TINY))
	return margin

## Tablodaki bir sayı hücresi: monospace, sağa yaslı, sabit genişlikte.
func _table_value(text: String, width: float, color: Color, size: int = UiTheme.FS_SMALL) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", UiTheme.mono())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Açık sekmeye göre bu partinin sayı hücreleri.
func _player_row_values(peer_id: int, is_self: bool) -> Array:
	match _player_tab:
		1:
			var pid := CardManager.party_of(peer_id)
			var percent: float = float(CardManager.last_vote_shares.get(pid, 0.0))
			var won: int = int(CardManager.election_seats.get(pid, CardManager.last_seats.get(pid, 0)))
			var below: bool = not CardManager.last_vote_shares.is_empty() 				and not CardManager.passed_threshold.has(pid)
			return [
				_table_value(L.t("%%%.1f") % percent, 56.0, UiTheme.RED if below else UiTheme.TEXT),
				_table_value(str(won), 50.0, UiTheme.TEXT_MUTED),
			]
		2:
			var now: int = int(CardManager.last_seats.get(CardManager.party_of(peer_id), 0))
			var national: float = CardManager.national_of(peer_id)
			return [
				_table_value(str(now), 46.0, UiTheme.TEXT_MUTED),
				_table_value(EffectWords.arrows(national), 52.0, ProvincePanel._opinion_color(national)),
				_table_value(str(GovernmentManager.score_of(peer_id)), 44.0, UiTheme.TEXT),
			]
		_:
			# PARA GİZLİ: kimse rakibinin kasasını göremez.
			if is_self:
				return [_table_value(CardManager.funds_text(CardManager.funds_of(peer_id)), 58.0, FUNDS_COLOR)]
			return [_table_value("·", 58.0, UiTheme.TEXT_DIM)]

## Bir durum güncellemesinde birkaç sinyal aynı paneli yeniden kuruyordu
## (kare başına 20-35 ms); artık kare sonunda BİR kez kurulur (performans).
func _rebuild_player_panel() -> void:
	if _deferred_ui.has("_rebuild_player_panel"):
		return
	_deferred_ui["_rebuild_player_panel"] = true
	_run_deferred_ui.call_deferred("_rebuild_player_panel")

func _rebuild_player_panel_now() -> void:
	if player_panel_list == null:
		return
	_ensure_board()
	for child in player_panel_list.get_children():
		player_panel_list.remove_child(child)
		child.queue_free()
	if player_tabs != null:
		player_tabs.show()
	var party_ids := _ordered_party_ids()
	player_panel_list.columns = 1
	player_panel_list.add_theme_constant_override("v_separation", 4)
	var panel := get_node_or_null("PlayerPanel") as Control
	if panel != null:
		panel.clip_contents = true
	var inner := _r(R_BOARD).grow(-8.0)
	var list_height: float = inner.size.y - PLAYER_TAB_HEIGHT - 6.0
	var plaque_height: float = clampf(list_height / maxf(1.0, party_ids.size()) - 4.0, 50.0, 60.0)
	for pid in party_ids:
		var plaque := _build_plaque(int(pid), inner.size.x)
		plaque.custom_minimum_size.y = plaque_height
		player_panel_list.add_child(plaque)
	_board_scroll.visible = _player_tab == 0
	_score_scroll.visible = _player_tab == 1
	_refresh_score_table()
	# Panel yeniden kuruldu: hedef seçme vurguları yeni düğümlere uygulanmalı.
	_refresh_target_highlights()

## Plaket sırası: oyun sırasına göre partiler (iki kişilik parti bir kez).
func _ordered_party_ids() -> Array:
	var ids: Array = []
	for peer_id in _ordered_peer_ids():
		var pid := CardManager.party_of(int(peer_id))
		if not ids.has(pid):
			ids.append(pid)
	return ids

## PARTİ PLAKETİ (üst şerit, tek satır): logo · parti adı (+ PM/HÜK, SEN,
## POP, oy etiketleri) ve genel başkan · sağda vekil ve oy oranı. Altında
## parti renginde çizgi; sırası gelen partide çizgi altın, zemin açık.
func _build_plaque(pid: int, width: float) -> Control:
	var me := multiplayer.get_unique_id()
	var party: Dictionary = PartyManager.data_of(pid)
	var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
	var members: Array = PartyManager.members_of(pid)
	if members.is_empty():
		members = [pid]
	var current := CardManager.current_turn_peer_id()
	var is_turn := not CardManager.turn_order.is_empty() and members.has(current)
	var mine := members.has(me)
	var independent := PartyManager.is_independent(pid)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Color("2a2350") if is_turn else Color("1d1838")
	style.border_color = color
	style.border_width_left = 5
	if is_turn:
		style.border_color = UiTheme.GOLD
		style.set_border_width_all(2)
		style.border_width_left = 5
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	# BÜYÜK LOGO.
	var badge := PartyBadge.build(party, Vector2(PLAQUE_BADGE, PLAQUE_BADGE), BADGE_ICON_PIXEL_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stack)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	var tags: Array = []
	var alliance_id := CardManager.alliance_of(pid)
	if alliance_id >= 0 and CardManager.alliances.has(alliance_id):
		var alliance: Dictionary = CardManager.alliances[alliance_id]
		tags.append([String(alliance.get("name", "")), alliance.get("color", UiTheme.GOLD), UiTheme.INK])
	if GovernmentManager.has_government() and CardManager.is_government_party(pid):
		tags.append([L.t("PM") if GovernmentManager.main_gov_peer_id == pid else L.t("HÜK"), UiTheme.GREEN, UiTheme.TEXT])
	if mine:
		tags.append([L.t("SEN"), UiTheme.GOLD, UiTheme.INK])
	var populism_left := CardManager.populism_rounds_left(pid)
	if populism_left > 0:
		tags.append([L.t("POP %d") % populism_left, UiTheme.PURPLE, UiTheme.TEXT])
	for member in members:
		if MultiplayerManager.is_away(int(member)):
			tags.append([L.t("BOT") if MultiplayerManager.away_mode == MultiplayerManager.AWAY_BOT else L.t("PASİF"), UiTheme.RED, UiTheme.TEXT])
	var vote_member := -1
	for member in members:
		if GovernmentManager.is_voting() and GovernmentManager.eligible_voter_ids().has(int(member)):
			vote_member = int(member)
	if vote_member != -1:
		var voted: bool = GovernmentManager.votes.has(vote_member)
		tags.append([GovernmentManager.vote_text(GovernmentManager.votes[vote_member]) if voted else "…",
			VOTE_COLORS[int(GovernmentManager.votes[vote_member])] if voted else UiTheme.PANEL_LIGHT, UiTheme.INK])
	var tags_width := 0.0
	for tag in tags:
		tags_width += String(tag[0]).length() * 6.0 + 10.0
	var has_seats: bool = CardManager.last_seats.has(pid)
	var seats_text := str(int(CardManager.last_seats.get(pid, 0))) if has_seats else "—"
	var name_text := L.t("Bağımsız") if independent else String(party.get("name", "?"))
	var inner: float = width - 12.0 - PLAQUE_BADGE - 7.0
	var name_label := _avatar_label(name_text, _fit_font_size(name_text, inner - tags_width - 34.0, 14, 8),
		UiTheme.GOLD if mine else UiTheme.TEXT)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = name_text
	name_label.add_theme_font_override("font", UiTheme.mono(true))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	for tag in tags:
		var tag_control := _avatar_tag(String(tag[0]), tag[1], tag[2])
		# Etiketler metnin doğal genişliğiyle plaketi büyütmesin; logo ve
		# parti adına yer bırakıp uzun ittifak adlarını üç noktayla göster.
		var tag_limit := minf(60.0, maxf(8.0, (inner - 50.0) / maxf(1.0, tags.size())))
		(tag_control as Label).clip_text = true
		(tag_control as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tag_control.custom_minimum_size.x = minf(tag_limit, String(tag[0]).length() * 6.0 + 6.0)
		tag_control.tooltip_text = String(tag[0])
		tag_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tag_control)
	var seats_label := _avatar_label(seats_text, 15, UiTheme.TEXT)
	seats_label.add_theme_font_override("font", UiTheme.mono(true))
	seats_label.clip_text = false
	head.add_child(seats_label)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(foot)
	var leader_text := PoliticianPresets.display_name(pid)
	if members.size() > 1:
		leader_text += L.t(" · üye ") + PoliticianPresets.display_name(int(members[1]))
	var share: float = float(CardManager.last_vote_shares.get(pid, 0.0))
	var share_text := (L.t("%%%.1f") % share) if has_seats else ""
	var leader := _avatar_label(leader_text, _fit_font_size(leader_text, inner - 44.0, 11, 7), UiTheme.TEXT_MUTED)
	leader.clip_text = true
	leader.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(leader)
	var share_label := _avatar_label(share_text, 12, UiTheme.TEXT)
	share_label.add_theme_font_override("font", UiTheme.mono(true))
	share_label.clip_text = false
	foot.add_child(share_label)
	# KALIN OY ÇUBUĞU: en çok oy alan parti tam dolu, diğerleri ona oranla.
	var top_share := 0.0
	for value in CardManager.last_vote_shares.values():
		top_share = maxf(top_share, float(value))
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, PLAQUE_BAR)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := ColorRect.new()
	bar_bg.color = Color("0a0816")
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bar_bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(share / top_share, 0.0, 1.0) if top_share > 0.0 else 0.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	stack.add_child(bar)

	card.set_meta("peer_id", pid)
	card.tooltip_text = L.t("%s · dokun: profil") % name_text
	var halo := Panel.new()
	halo.name = L.t("TargetHalo")
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.add_theme_stylebox_override("panel", UiSkin.color_box(UiTheme.GOLD, UiSkin.TARGET))
	halo.visible = false
	card.add_child(halo)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_target_party_clicked(pid)
	)
	return card

const PLAQUE_BADGE := 34.0
const PLAQUE_BAR := 9.0

# --- Tur göstergesi (geçici; kalıcı görseli kullanıcı sonra ekleyecek) -----

func _on_turn_changed(_peer_id: int) -> void:
	var current := CardManager.current_turn_peer_id()
	_maybe_autosave()
	if current != _last_turn_peer:
		_last_turn_peer = current
		if current == multiplayer.get_unique_id() and not CardManager.game_finished:
			var org_part := CardManager.org_income(current)
			_show_toast(L.t("Sıra sende: kasana +%s girdi%s (kasada %s).") % [GameRules.cost_text(CardManager.turn_income(current)),
				(L.t(", teşkilatlardan %s dahil") % GameRules.cost_text(org_part)) if org_part > 0 else "", GameRules.cost_text(CardManager.funds_of(current))])
			AudioManager.play("turn_start")
	_update_turn_indicator()
	_refresh_band_crisis()
	_refresh_speech_panel()
	_refresh_pass_button()
	_refresh_hand_interactivity()
	_refresh_action_buttons()
	_refresh_trash_button()
	# Oyuncu kartlarında para yazıyor: her hamlede güncellenir.
	_rebuild_player_panel()

func _update_turn_indicator() -> void:
	var peer_id := CardManager.current_turn_peer_id()
	for child in turn_indicator_badge_slot.get_children():
		child.queue_free()
	if peer_id == -1:
		turn_indicator.hide()
		return
	turn_indicator.hide()  # sıra artık masada ("SIRA SENDE · süre")
	var party: Dictionary = PartyManager.data_of(peer_id)
	_update_turn_indicator_text()
	var badge := PartyBadge.build(party, turn_indicator_badge_slot.custom_minimum_size, BADGE_ICON_PIXEL_SIZE)
	turn_indicator_badge_slot.add_child(badge)

func _update_turn_indicator_text() -> void:
	var peer_id := CardManager.current_turn_peer_id()
	if peer_id == -1:
		return
	var party: Dictionary = PartyManager.data_of(peer_id)
	var party_text := L.t("Bağımsız") if PartyManager.is_independent(peer_id) else String(party.get("name", "?"))
	var pname := "%s · %s" % [PoliticianPresets.display_name(peer_id), party_text]
	var suffix := L.t(" (Sen)") if peer_id == multiplayer.get_unique_id() else ""
	var timer := "" if CardManager.is_turn_blocked() else L.t("\nSüre: %s") % GameRules.format_seconds(CardManager.turn_seconds_left())
	turn_indicator_label.text = L.t("Sıra: %s%s%s") % [pname, suffix, timer]
	_refresh_desk_labels()

## Kart bozdurma yuvası sadece sıra sendeyken ve elinde kart varken belirgin.
func _refresh_trash_button() -> void:
	if _trash_panel == null:
		return
	var usable: bool = CardManager.can_act() and not CardManager.my_inventory().is_empty()
	_trash_panel.modulate.a = 1.0 if usable else 0.35

func _refresh_pass_button() -> void:
	if pass_button.icon == null:
		UiSkin.set_side_icon(pass_button, "turu_gec", 16)
	pass_button.disabled = not CardManager.can_act()
	pass_button.text = L.t("Turu Bitir")
	# Para bittiyse tur kendiliğinden geçmez; buton nabız gibi atarak hatırlatır.
	var should_pulse: bool = not pass_button.disabled and CardManager.funds_of(multiplayer.get_unique_id()) <= 0
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

## Kartlar ayrılan alana (sağ yarı) sığmıyorsa aralarındaki boşluk negatife
## çekilip üst üste bindirilir; sıra göstergesine ve meclis butonlarına taşmaz.
func _fit_hand_width(count: int) -> void:
	var separation := HAND_CARD_SEPARATION
	# Masadaki el alanının genişliği (düğüm boyu bir kare sonra kesinleşir;
	# bayat boyla hesaplanınca el iki yana taşıyordu).
	var available: float = _r(R_HAND).size.x
	if count > 1 and available > 0.0:
		var needed: float = count * CARD_DISPLAY_SIZE.x + (count - 1) * HAND_CARD_SEPARATION
		if needed > available:
			separation = int(floor((available - count * CARD_DISPLAY_SIZE.x) / float(count - 1)))
	hand_container.add_theme_constant_override("separation", separation)

var _live_mouse := Vector2(-1, -1)
var _deferred_ui: Dictionary = {}

func _run_deferred_ui(name: String) -> void:
	_deferred_ui.erase(name)
	if is_inside_tree():
		call(name + "_now")
var _live_wait := 0.0

func _process(delta: float) -> void:
	_refresh_countdowns()
	_sync_parliament_to_slot()
	_refresh_timer_bar()
	if _drag_ghost != null:
		_update_drag()
	else:
		# Fare kımıldamadıysa il / parti tespiti her karede yapılmaz (performans);
		# yine de arada bir tazelenir (altındaki içerik değişmiş olabilir).
		var mouse := get_viewport().get_mouse_position()
		_live_wait -= delta
		if mouse != _live_mouse or _live_wait <= 0.0:
			_live_mouse = mouse
			_live_wait = 0.25
			_update_live_province()

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
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.texture = CardPresets.get_card_texture(card_type)
	shadow.size = CARD_DISPLAY_SIZE
	shadow.position = SHADOW_OFFSET
	shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.modulate = SHADOW_COLOR
	holder.add_child(shadow)

	var card := TextureRect.new()
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.texture = CardPresets.get_card_texture(card_type)
	card.size = CARD_DISPLAY_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("is_click_target", true)
	holder.add_child(card)

	# TAM GÖRSELLİ KART: görsel kartı kaplar (2:3 görsel 3:4 karta kırpılır),
	# ad alttaki karartmada, bedel sol üstte, kenar görselin ortalama renginde.
	if CardPresets.has_full_art(card_type):
		for art: TextureRect in [card, shadow]:
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		holder.add_child(_card_art_title(card_type, CardManager.my_inventory().size() * CARD_DISPLAY_SIZE.x > _r(R_HAND).size.x))
		holder.add_child(_card_art_edge(CardPresets.art_edge_color(card_type)))
		var art_badge := _card_cost_badge(CardPresets.card_cost(card_type))
		art_badge.position = Vector2(4.0, 4.0)
		holder.add_child(art_badge)
		_wire_hand_card(wrapper, holder, card, card_type, hand_index)
		return wrapper

	# KART YÜZÜ: türün renginde zemin + büyük simge (gövdenin sol yarısında:
	# kartlar üst üste binince de görünür).
	var face := CardFace.new()
	face.card_type = card_type
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2(4.0, 56.0 * CARD_ART_RATIO)
	face.size = Vector2(CARD_DISPLAY_SIZE.x - 8.0, CARD_DISPLAY_SIZE.y - 56.0 * CARD_ART_RATIO - 4.0)
	holder.add_child(face)
	# Kartın ne olduğu her kartta görselin üstündeki bantta yazar.
	# Kartlar üst üste biniyorsa başlık sola yaslanır (görünen şeritte okunur).
	holder.add_child(_card_title_banner(card_type, CardManager.my_inventory().size() * CARD_DISPLAY_SIZE.x > _r(R_HAND).size.x))
	holder.add_child(_card_cost_badge(CardPresets.card_cost(card_type)))
	_wire_hand_card(wrapper, holder, card, card_type, hand_index)
	return wrapper

## El kartının tık / sürükleme / üstüne gelme davranışı (iki kart yüzü için ortak).
func _wire_hand_card(wrapper: Control, holder: Control, card: Control, card_type: String, hand_index: int) -> void:
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
		# SÜRÜKLEYEREK BOZDURMA: kart oynamak tıkla-seç ile; sürükleme sadece
		# KART BOZDUR yuvasına bırakmak içindir (başka yere bırakmak iptal).
		elif event is InputEventMouseMotion and card.get_meta("pressed", false) and _drag_hand_index == -1:
			if event.position.distance_to(card.get_meta("press_pos", Vector2.ZERO)) > TAP_MAX_MOVE_PX:
				_start_drag(hand_index, card_type, holder)
	)

	# FARE ÜSTÜNE GELİNCE kart tamamen görünür (dokunmatikte aynısını tek
	# dokunuş yapar: kart seçilince kalkar, tekrar dokununca çalışır).
	card.mouse_entered.connect(func():
		if _selected_hand_index != hand_index:
			holder.set_meta("lift_target", CARD_LIFT)
			holder.z_index = 3
	)
	card.mouse_exited.connect(func():
		if _selected_hand_index != hand_index:
			holder.set_meta("lift_target", 0.0)
			holder.z_index = 0
	)

	wrapper.add_child(holder)
	_hand_holders.append(holder)

## Tam görselli kartın adı: alttaki koyu geçişin üstünde, iki satıra kadar.
## Kartlar üst üste binince sola yaslanır (görünen şeritte okunur).
func _card_art_title(card_type: String, crowded: bool) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var height := CARD_DISPLAY_SIZE.y * 0.42
	box.position = Vector2(0.0, CARD_DISPLAY_SIZE.y - height)
	box.size = Vector2(CARD_DISPLAY_SIZE.x, height)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.03, 0.02, 0.08, 0.0))
	grad.set_color(1, Color(0.03, 0.02, 0.08, 0.92))
	grad.add_point(0.5, Color(0.03, 0.02, 0.08, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(shade)
	var title := Label.new()
	title.text = CardPresets.card_short_title(card_type)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if crowded else HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	# AYNI BOYUT: eldeki bütün kartların adları tek bir yazı boyutunda; boyut,
	# eldeki en uzun sözcük görünen şeride sığana kadar küçülür (kısaltılmaz).
	var room := CARD_DISPLAY_SIZE.x - 10.0
	if crowded:
		# Kalabalık elde komşu kart sağ yanı örter: görünen şerit kadar yer var.
		var count := maxi(2, CardManager.my_inventory().size())
		var step := (_r(R_HAND).size.x - CARD_DISPLAY_SIZE.x) / float(count - 1)
		room = clampf(step, 30.0, CARD_DISPLAY_SIZE.x) - 8.0
	var font_size := _hand_title_font_size(room)
	title.add_theme_font_override("font", _card_title_font())
	title.add_theme_font_size_override("font_size", font_size)
	title.add_theme_constant_override("line_spacing", -2)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 3)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_left = 5.0
	# Satır kaydırma görünen alana göre yapılsın (kalabalık elde dar şerit).
	title.offset_right = -maxf(5.0, CARD_DISPLAY_SIZE.x - 5.0 - room)
	title.offset_bottom = -4.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	return box

## Eldeki tam görselli kartların ortak ad boyutu (en uzun sözcük sığar).
func _hand_title_font_size(room: float) -> int:
	var font := _card_title_font()
	var longest := 0.0
	for card_type in CardManager.my_inventory():
		if not CardPresets.has_full_art(card_type):
			continue
		for word in CardPresets.card_short_title(card_type).split(" "):
			longest = maxf(longest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, CARD_TITLE_SIZE).x)
	if longest <= room or longest <= 0.0:
		return CARD_TITLE_SIZE
	return maxi(CARD_TITLE_MIN_SIZE, int(floor(CARD_TITLE_SIZE * room / longest)))

## Kart adı yazı tipi: oyunun başlık fontu (IBM Plex Mono Bold).
func _card_title_font() -> Font:
	return UiTheme.mono(true)

## Tam görselli kartın kenar çizgisi.
func _card_art_edge(color: Color) -> Control:
	var edge := Panel.new()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.position = Vector2.ZERO
	edge.size = CARD_DISPLAY_SIZE
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(2)
	style.border_color = color
	style.set_corner_radius_all(0)
	edge.add_theme_stylebox_override("panel", style)
	return edge

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
			_show_toast(L.t("Yatırım kartını sadece hükümet partileri oynayabilir."))
			return
		_begin_province_targeting(hand_index)
		return
	if CardPresets.is_self_card(card_type):
		_set_target_hint(L.t("%s: kullanmak için karta tekrar dokun  ·  Başka yere dokun: vazgeç") % CardPresets.card_title(card_type))

func _select_hand_card(hand_index: int) -> void:
	_selected_hand_index = hand_index
	for holder in _hand_holders:
		if not is_instance_valid(holder):
			continue
		var selected: bool = int(holder.get_meta("hand_index", -1)) == hand_index
		holder.set_meta("lift_target", CARD_LIFT if selected else 0.0)
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
func _card_title_banner(card_type: String, crowded: bool = false) -> Control:
	var banner := PanelContainer.new()
	banner.position = Vector2(6.0 * CARD_ART_RATIO, 8.0 * CARD_ART_RATIO)
	banner.size = Vector2(CARD_DISPLAY_SIZE.x - 12.0 * CARD_ART_RATIO, 44.0 * CARD_ART_RATIO)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiSkin.stylebox(UiSkin.PANEL_DARK)
	style.set_content_margin_all(4)
	banner.add_theme_stylebox_override("panel", style)
	var title := Label.new()
	title.text = CardPresets.card_short_title(card_type)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if crowded else HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", int(roundf(14.0 * CARD_ART_RATIO)))
	title.add_theme_color_override("font_color", Color.WHITE)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(title)
	return banner

## Kartın sağ alt köşesindeki para bedeli rozeti.
## Kartın üst kısmında para bedeli: para simgesi + sayı (bedelsiz kartta 0).
func _card_cost_badge(cost: int) -> Control:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiSkin.stylebox(UiSkin.SLOT, 3)
	style.content_margin_left = 6
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(row)
	row.add_child(CoinIcon.make(22.0 * CARD_ART_RATIO, FUNDS_COLOR))
	var label := Label.new()
	label.text = str(cost)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(roundf(18.0 * CARD_ART_RATIO)))
	label.add_theme_color_override("font_color", FUNDS_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	badge.reset_size()
	# Sol altta: kartlar üst üste binince de görünen şeritte kalır.
	badge.position = Vector2(6.0, CARD_DISPLAY_SIZE.y - badge.get_combined_minimum_size().y - 6.0)
	return badge

## OTOMATİK KAYIT: çevrim dışı oyunda her yeni dönemin başında (tur akışı
## engellenmemişken) bir kez. Elle kayıttan ayrı yuvaya yazılır.
var _autosaved_round := -1
func _maybe_autosave() -> void:
	# Test / önizleme betikleri (özel SceneTree) oyuncunun kayıtlarına yazmasın.
	if get_tree().get_script() != null:
		return
	if not MultiplayerManager.offline_mode or CardManager.round_number == _autosaved_round \
			or CardManager.is_turn_blocked() or SaveGame.block_reason() != "":
		return
	_autosaved_round = CardManager.round_number
	(func(): SaveGame.save(SaveGame.AUTOSAVE_SLOT)).call_deferred()

## Oynanamayan bir karta tıklanınca neden oynanamadığı.
func _unplayable_reason(card_type: String) -> String:
	if CardManager.funds_of(multiplayer.get_unique_id()) < CardPresets.card_cost(card_type):
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(CardPresets.card_cost(card_type))
	if CardPresets.is_law_card(card_type):
		return L.t("Yasa şu an meclise getirilemez (meclis yok ya da hükümet kuruluyor).")
	if CardPresets.is_censure_card(card_type):
		return L.t("Gensoruyu sadece muhalefet, hükümet görevdeyken verebilir.")
	return L.t("Bu kart şu an oynanamaz.")

# --- Sürükle-bırak -----------------------------------------------------------

func _start_drag(hand_index: int, card_type: String, holder: Control) -> void:
	if _player_tab != 0:
		_on_player_tab_pressed(0)  # parti hedefleri VEKİL sekmesinde
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
	_drag_ghost.texture = _circle_texture(VoterGroups.color(String(law["group"]))) if not law.is_empty() \
		else CardPresets.get_card_texture(card_type)
	_drag_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if CardPresets.has_full_art(card_type) \
		else CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_ghost.size = Vector2(52, 52) if not law.is_empty() else CARD_DISPLAY_SIZE * 0.6
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 150
	add_child(_drag_ghost)
	_update_drag()

## Her kare: kopya imleci izler, imlecin altındaki hedef vurgulanır ve üstte
## "bırakırsan ne olur" yazar.
func _update_drag() -> void:
	var mouse := get_viewport().get_mouse_position()
	_drag_ghost.position = mouse - _drag_ghost.size * 0.5
	var target := _drop_target(_drag_card_type)
	_set_target_hint(String(target["label"]) + L.t("  ·  Geçersiz yere bırak: iptal"))
	var valid: bool = target["valid"]
	_drag_ghost.modulate = Color(1, 1, 1, 0.95) if valid else Color(1, 0.6, 0.6, 0.85)
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
	if bool(target.get("discard", false)):
		CardManager.discard_card(hand_index)
	elif hand_index == LAW_DRAG_INDEX:
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
	var result := {"valid": false, "peer": -1, "province": "", "label": "", "error": "",
		"parliament": false, "discard": false}
	# ÇÖP her kartı kabul eder (yasa tasarımı hariç): bedelin yarısı geri gelir.
	if _trash_panel != null and card_type != "" and not CardPresets.is_law_card(card_type) 			and _trash_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		result["valid"] = true
		result["discard"] = true
		result["label"] = L.t("Bırak: kartı bozdur (+%s)") % GameRules.cost_text(CardManager.discard_refund(card_type))
		return result
	if _drag_hand_index >= 0:
		# Eldeki kart sürükleniyor: tek geçerli hedef KART BOZDUR yuvası.
		result["label"] = L.t("Bozdurmak için KART BOZDUR yuvasına bırak")
		return result
	if CardPresets.needs_party_target(card_type) and not CardPresets.needs_target(card_type):
		# Kaset / parti içi isyan: hedef, kendisi dışında herhangi bir parti.
		var other := _party_under_mouse()
		result["peer"] = other
		var title := CardPresets.card_title(card_type)
		if other == -1:
			result["label"] = L.t("%s için sağdaki bir partinin logosuna bırak") % title
		elif other == me:
			result["label"] = L.t("Bu kartı kendi partine oynayamazsın")
			result["error"] = result["label"]
		elif card_type == CardPresets.REBELLION_CARD_TYPE and not CardManager.has_seats(other):
			result["label"] = L.t("Meclis dışı partide iç karışıklık çıkarılamaz")
			result["error"] = result["label"]
		else:
			result["valid"] = true
			if card_type == CardPresets.REPUTATION_CARD_TYPE:
				result["label"] = L.t("Bırak: %s hakkında kaset sızdır (%s)") % [_party_name_of(other),
					EffectWords.change(-PublicOpinion.REPUTATION_NATIONAL_DAMAGE)]
			elif card_type == CardPresets.CARD_THEFT_CARD_TYPE:
				result["label"] = L.t("Bırak: %s'ın elinden rastgele 1 kart çal") % _party_name_of(other)
			else:
				result["label"] = L.t("Bırak: %s'da iç karışıklık çıkar (%s)") % [_party_name_of(other),
					EffectWords.change(-PublicOpinion.REBELLION_NATIONAL_DAMAGE)]
	elif CardPresets.needs_target(card_type):
		var peer := _party_under_mouse()
		result["peer"] = peer
		if peer == -1:
			result["label"] = L.t("Vekil çalmak için sağdaki bir partinin logosuna bırak")
		elif CardManager.is_valid_steal_target(me, peer):
			result["valid"] = true
			var r := CardManager.steal_range(me, peer, card_type)
			var closeness := CardManager.group_closeness(me, peer)
			result["label"] = L.t("Bırak: %s partisinden %d-%d vekil çal (seçmenleriniz %s)") % [_party_name_of(peer),
				int(r["min"]), int(r["max"]), L.t("yakın") if closeness >= 0.6 else (L.t("kısmen yakın") if closeness >= 0.3 else L.t("uzak"))]
		else:
			result["label"] = L.t("Bu partiden vekil çalınamaz")
			result["error"] = result["label"]
	elif CardPresets.needs_province_target(card_type):
		var province_id := _province_under_mouse()
		result["province"] = province_id
		var pname := ElectionNightSim.province_name(province_id)
		if province_id == "":
			result["label"] = L.t("Haritada bir ilin üstüne bırak")
		elif card_type == CardPresets.INVEST_CARD_TYPE and not CardManager.is_government_party(me):
			result["label"] = L.t("Yatırımı sadece hükümet partileri yapabilir")
			result["error"] = result["label"]
		elif card_type != CardPresets.INVEST_CARD_TYPE and CardManager.organization_level(province_id, me) < 1 \
				and not PartyManager.is_independent(me):
			result["label"] = L.t("%s'da teşkilatın yok — önce teşkilatlan") % pname
			result["error"] = result["label"]
		else:
			result["valid"] = true
			if card_type == CardPresets.MITING_CARD_TYPE:
				result["label"] = L.t("Bırak: %s'da miting · provokasyon: %s") % [pname, EffectWords.risk(CardManager.miting_risk(me, province_id))]
			elif card_type == CardPresets.INVEST_CARD_TYPE:
				result["label"] = L.t("Bırak: %s'a yatırım") % pname
			else:
				result["label"] = L.t("Bırak: %s'da karalama — sonra hedef partiyi seç") % pname
	elif CardPresets.is_law_card(card_type):
		var over_law := parliament_diagram.get_global_rect().has_point(get_viewport().get_mouse_position())
		result["parliament"] = over_law
		var law := CardPresets.law_data(card_type)
		if not over_law:
			result["label"] = L.t("%s: parlamento diyagramının üstüne bırak") % law["title"]
		elif CardManager.can_propose_law(me, card_type):
			result["valid"] = true
			result["label"] = L.t("Bırak: %s %s (bedelsiz, dönemde 1)") % [law["title"],
				L.t("seçim vaadi olarak açıklanır") if CardManager.last_seats.is_empty() else L.t("meclise sunulur")]
		else:
			result["label"] = _action_block_reason(GameRules.LAW_FUNDS_COST, true)
			result["error"] = result["label"]
	elif card_type == CardPresets.EARLY_ELECTION_CARD_TYPE:
		var over_parliament := parliament_diagram.get_global_rect().has_point(get_viewport().get_mouse_position())
		result["parliament"] = over_parliament
		if not over_parliament:
			result["label"] = L.t("Erken seçim önergesi: parlamento diyagramının üstüne bırak")
		elif CardManager.can_play_card(me, card_type):
			result["valid"] = true
			result["label"] = L.t("Bırak: erken seçim önergesi sun (meclis oylar)")
		else:
			result["label"] = _unplayable_reason(card_type)
			result["error"] = result["label"]
	elif CardPresets.is_self_card(card_type):
		var above_hand := get_viewport().get_mouse_position().y < hand_area.get_global_rect().position.y
		if not above_hand:
			result["label"] = L.t("%s: kullanmak için yukarı sürükle") % CardPresets.card_title(card_type)
		elif CardManager.can_play_card(me, card_type):
			result["valid"] = true
			result["label"] = L.t("Bırak: %s kullan") % CardPresets.card_title(card_type)
		else:
			result["label"] = _unplayable_reason(card_type)
			result["error"] = result["label"]
	elif CardPresets.is_censure_card(card_type):
		var over := parliament_diagram.get_global_rect().has_point(get_viewport().get_mouse_position())
		result["parliament"] = over
		if not over:
			result["label"] = L.t("Gensoru için parlamento diyagramının üstüne bırak")
		elif CardManager.can_play_card(me, card_type):
			result["valid"] = true
			result["label"] = L.t("Bırak: gensoru ver")
		else:
			result["label"] = _unplayable_reason(card_type)
			result["error"] = result["label"]
	return result

## İmleç haritada hangi ilin üstünde? (Paneller ve alt hazne hariç.)
func _province_under_mouse() -> String:
	var mouse := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	if mouse.x < LEFT_PANEL_WIDTH or mouse.x > viewport_size.x - RIGHT_COLUMN_WIDTH \
			or mouse.y < TOP_STRIP_HEIGHT or mouse.y >= viewport_size.y - CARD_BAR_HEIGHT:
		return ""
	return map_holder.get_province_id_at(map_holder.get_global_transform().affine_inverse() * mouse)

## Fare şu an sağdaki parti panelinde hangi partinin üstünde?
func _party_under_mouse() -> int:
	var mouse_pos := get_viewport().get_mouse_position()
	if _board_scroll != null and not _board_scroll.get_global_rect().has_point(mouse_pos):
		return -1
	for child in player_panel_list.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var avatar := child as Control
		if avatar == null or not avatar.is_visible_in_tree():
			continue
		if Rect2(avatar.global_position, avatar.size).has_point(mouse_pos):
			return avatar.get_meta("peer_id", -1)
	return -1

func _begin_targeting(hand_index: int) -> void:
	_pending_target_hand_index = hand_index
	if _player_tab != 0:
		_on_player_tab_pressed(0)  # hedef plaketler VEKİL sekmesinde
	_refresh_target_highlights()
	_hide_profile()
	_set_target_hint(L.t("%s: soldan bir partiye dokun  ·  Karta tekrar dokun: iptal") % CardPresets.card_title(
		String(CardManager.my_inventory()[hand_index])))

## Hedef seçilen kart bu partiye oynanabilir mi?
func _valid_party_target(peer_id: int) -> bool:
	var hand := CardManager.my_inventory()
	if _pending_target_hand_index < 0 or _pending_target_hand_index >= hand.size():
		return false
	return CardManager.can_play_card(multiplayer.get_unique_id(), String(hand[_pending_target_hand_index]), peer_id)

## Miting / yatırım: haritadan il seçilmesi beklenir (bkz. _on_province_clicked).
func _begin_province_targeting(hand_index: int) -> void:
	_pending_province_hand_index = hand_index
	# Harita tıklanabilir kalsın: açık il paneli haritanın üstünü kapatmasın.
	if _province_panel != null:
		_province_panel.hide()
	var card_type: String = CardManager.my_inventory()[hand_index]
	_set_target_hint(L.t("%s: haritada bir ile dokun (ayrıntı görünür), tekrar dokun: oyna  ·  Karta tekrar dokun: iptal") % CardPresets.card_title(card_type))

func _cancel_targeting() -> void:
	_pending_province_hand_index = -1
	if _funding_panel != null:
		_funding_panel.hide()
	if _pending_org:
		# Harita teşkilat katmanında KALIR (oyuncu isterse kendisi değiştirir).
		_pending_org = false
		_layer_before_org = -1
		_refresh_action_buttons()
	if _pending_miting or _pending_invest or _pending_censure or _pending_early or _pending_congress:
		_pending_congress = false
		_pending_miting = false
		_pending_invest = false
		_pending_censure = false
		_pending_early = false
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
	if (_pending_org or _pending_miting or _pending_invest) and _selected_province != province_id:
		_select_target_province(province_id)
		return
	if _pending_invest or (_pending_miting and _funding_panel.visible):
		_on_funding_confirmed(_funding_panel.current_share())
		return
	if _pending_miting:
		_cancel_targeting()
		if CardManager.can_miting(me, province_id):
			CardManager.miting(province_id)
		elif CardManager.organization_level(province_id, me) < 1 and not PartyManager.is_independent(me):
			_show_toast(L.t("Bu ilde teşkilatın yok. Önce teşkilatlanmalısın."))
		else:
			_show_toast(_action_block_reason(GameRules.MITING_FUNDS_COST))
		return
	if _pending_org:
		if not CardManager.can_build_organization(me, province_id):
			_cancel_targeting()
			if CardManager.organization_level(province_id, me) >= GameRules.ORG_MAX_LEVEL:
				_show_toast(L.t("Bu ildeki teşkilatın zaten en üst seviyede."))
			else:
				_show_toast(_action_block_reason(CardManager.org_cost_for(multiplayer.get_unique_id())))
			return
		# Kuruldu: harita teşkilat katmanında kalır (geri dönmez).
		_layer_before_org = -1
		_pending_org = false
		_selected_province = ""
		_highlight_province("")
		_set_target_hint("")
		var level := CardManager.organization_level(province_id, me) + 1
		CardManager.build_organization(province_id)
		_show_toast(L.t("%s teşkilatı seviye %d: %s") % [ElectionNightSim.province_name(province_id), level, _org_level_text(level)])
		_refresh_action_buttons()
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
	_show_province_info(province_id)
	_pinned = true

## İL BİLGİSİ sağ sütunda ("Seçili"). Fare haritada dolaşırken canlı olarak
## değişir (bkz. _update_live_province); tıklamak da aynı bilgiyi gösterir.
var _live_province := ""

## Fare haritada bir ilin üstündeyse (hedef seçme yokken) o ilin bilgisi
## tıklamadan sağda gösterilir. Haritadan çıkınca son il ekranda kalır.
## FAREYLE İNCELEME (panel modu): ilin ya da parti plaketinin üstüne gelince
## bilgisi sağ panelde GEÇİCİ açılır, fare çekilince kapanır ve en son
## açık sekmeye dönülür. TIKLAMA kalıcı açar (_pinned): fare gezinse de değişmez.
var _pinned := false

func _update_live_province() -> void:
	if _window_mode() or _pinned:
		return
	if _pending_org or _pending_miting or _pending_invest or _pending_province_hand_index != -1 			or _pending_target_hand_index != -1 or _layer_switching or not is_visible_in_tree():
		return
	var mouse := get_viewport().get_mouse_position()
	# Fare sağ paneldeyse açık olan bilgi kalır (kaydırılabilsin).
	if left_panel.get_global_rect().has_point(mouse):
		return
	var party := _party_under_mouse()
	if party != -1:
		if _profile_peer_id != party:
			_profile_peer_id = party
			_show_tooltip_for(party)
		return
	var province_id := _province_under_mouse()
	if province_id != "":
		if not (province_id == _live_province and _province_panel != null and _province_panel.visible):
			_show_province_info(province_id)
		return
	# Hiçbir şeyin üstünde değil: geçici bilgi kapanır, en son açık olan
	# sekmeye (Hükümet ya da Log) dönülür.
	if _left_dock != null and _left_dock.visible:
		if _profile_peer_id != -1:
			_hide_profile()
		if _province_panel != null and _province_panel.embedded_mode and _province_panel.visible:
			_province_panel.hide()

func _show_province_info(province_id: String) -> void:
	# Ayar değiştiyse eski türdeki il paneli atılır.
	if _province_panel != null and _province_panel.embedded_mode == _window_mode():
		_province_panel.queue_free()
		_province_panel = null
	if _window_mode():
		_show_province_window(province_id)
		return
	_live_province = province_id
	_ensure_left_dock()
	if _province_panel == null:
		_province_panel = ProvincePanel.new()
		_province_panel.embedded_mode = true
		_left_dock.add_child(_province_panel)
		_province_panel.visibility_changed.connect(_update_left_dock)
	elif _province_panel.visible and _province_panel.province_id == province_id:
		return
	_hide_profile()
	ProvincePanel.panel_width = _dock_width()
	_province_panel.position = Vector2.ZERO
	PopupKit.embedded = true
	_province_panel.show_province(province_id)
	PopupKit.embedded = false
	await get_tree().process_frame
	if _province_panel.visible:
		_province_panel.clamp_to_height(_left_dock.size.y)

## PENCERE MODU (eski mantık): ile tıklayınca haritanın sol üstünde il
## penceresi açılır; aynı ile tekrar tıklamak kapatır.
func _show_province_window(province_id: String) -> void:
	if _province_panel == null:
		_province_panel = ProvincePanel.new()
		add_child(_province_panel)
	elif _province_panel.visible and _province_panel.province_id == province_id:
		_province_panel.hide()
		return
	_hide_profile()
	ProvincePanel.panel_width = ProvincePanel.PANEL_WIDTH
	var map_rect := _r(R_MAP)
	_province_panel.position = map_rect.position + Vector2(12.0, 52.0)
	_province_panel.show_province(province_id)
	_province_panel.clamp_to_height(map_rect.size.y - 64.0)

## Mitingin bu ildeki seçmen grubu etkisinin kısa özeti (gerçek kuralla,
## yorgunluk ve azalan getiri dahil; büyüklük nitel): " · hitap: İşçiler ve
## Sendikalar (hafif), ...".
func _miting_group_preview(me: int, province_id: String) -> String:
	var groups := PartyManager.groups_of(CardManager.party_of(me))
	var fatigue: Dictionary = CardManager.miting_fatigue.get(CardManager.party_of(me), {})
	var mult := PublicOpinion.org_action_mult(CardManager.organization_level(province_id, me))
	var parts: PackedStringArray = []
	for effect in PublicOpinion.miting_positioning(CardManager.province_profile(province_id), mult):
		var damp := PublicOpinion.miting_fatigue_mult(float(fatigue.get(String(effect["group"]), 0.0)))
		var delta := VoterGroups.effective_delta(groups, String(effect["group"]), float(effect["gain"]) * damp)
		if absf(delta) < EffectWords.NEGLIGIBLE:
			continue
		parts.append("%s %s" % [VoterGroups.title(String(effect["group"])),
			"(%s)" % EffectWords.adjective(delta, "group") if delta > 0.0 else L.t("(%s kayıp)") % EffectWords.adjective(delta, "group")])
	if parts.is_empty():
		return L.t(" · grup desteğine etkisi yok")
	return L.t(" · hitap: ") + ", ".join(parts)

## Hedef seçme modunda dokunulan il: vurgulanır, üstte ne olacağı yazar.
func _select_target_province(province_id: String) -> void:
	_selected_province = province_id
	_highlight_province(province_id)
	var me := multiplayer.get_unique_id()
	var pname := ElectionNightSim.province_name(province_id)
	var detail := ""
	if _pending_invest or (_pending_miting and _miting_has_choice()):
		_open_funding(province_id)
		_set_target_hint(L.t("%s: finansmanı aşağıdan ayarla, ONAYLA'ya bas (ya da ile tekrar dokun)  ·  Butona tekrar dokun: iptal") % pname)
		return
	if _pending_invest:
		detail = _invest_preview(pname)
	elif _pending_miting:
		detail = L.t("%s: miting (%s) · provokasyon: %s%s") % [pname, GameRules.cost_text(GameRules.MITING_FUNDS_COST),
			EffectWords.risk(CardManager.miting_risk(me, province_id)), _miting_group_preview(me, province_id)]
	elif _pending_org:
		var level := CardManager.organization_level(province_id, me)
		detail = L.t("%s: teşkilat zaten en üst seviyede") % pname if level >= GameRules.ORG_MAX_LEVEL \
			else L.t("%s: teşkilat seviye %d → %d (%s) · %s") % [pname, level, level + 1, GameRules.cost_text(CardManager.org_cost_for(me, province_id)), _org_level_text(level + 1)]
	else:
		var card_type: String = CardManager.my_inventory()[_pending_province_hand_index]
		if card_type == CardPresets.MITING_CARD_TYPE:
			detail = L.t("%s: miting · provokasyon: %s") % [pname, EffectWords.risk(CardManager.miting_risk(me, province_id))]
		else:
			detail = "%s: %s" % [pname, CardPresets.card_title(card_type)]
	_set_target_hint(L.t("%s  ·  Onaylamak için tekrar dokun") % detail)

# --- Davet / başvuru şeridi ------------------------------------------------------

func _on_opinion_changed() -> void:
	_refresh_disaster()
	# Erken seçim kararı / takvim kayması üst şeritte hemen görünsün.
	_refresh_band_date()
	_refresh_economy()
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
	_target_hint.add_theme_color_override("font_color", UiTheme.GOLD)
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
	_target_hint.position = Vector2(LEFT_PANEL_WIDTH, TOP_STRIP_HEIGHT + 4.0)
	_target_hint.size = Vector2(viewport_size.x - LEFT_PANEL_WIDTH - RIGHT_COLUMN_WIDTH, 24.0 * (text.count("\n") + 1))

func _build_card_info() -> void:
	_card_info = PanelContainer.new()
	_card_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_info.z_index = 110
	_card_info.hide()
	add_child(_card_info)

## Hover edilen kartın hemen üstünde adını ve ne yaptığını gösterir.
func _show_card_info(card_type: String, holder: Control) -> void:
	for child in _card_info.get_children():
		_card_info.remove_child(child)
		child.queue_free()
	# Açıklama satırlarını ayır: etki (tek paragraf), nasıl kullanılır, bedel.
	var effect: PackedStringArray = []
	var usage: PackedStringArray = []
	for line in CardPresets.card_description(card_type).split("\n", false):
		var lower := line.to_lower()
		if line.begins_with("Bedel:"):
			continue
		if "sürükle" in lower or "dokun" in lower:
			usage.append(line.strip_edges())
		else:
			effect.append(line.strip_edges())
	var cost := CardPresets.card_cost(card_type)
	var accent := UiTheme.RED if CardPresets.needs_target(card_type) else UiTheme.BLUE
	var parts := PopupKit.frame(300.0, accent, _card_info)
	var box: VBoxContainer = parts[1]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiTheme.mono_label(CardPresets.card_title(card_type), PopupKit.FS_TITLE - 2, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not CardPresets.is_law_card(card_type):
		head.add_child(PopupKit.chip(GameRules.cost_text(cost), UiTheme.BLUE.lightened(0.2)))
	box.add_child(head)
	if not effect.is_empty():
		box.add_child(PopupKit.note(" ".join(effect), UiTheme.TEXT, 276.0))
	if not usage.is_empty():
		box.add_child(PopupKit.note(" ".join(usage), UiTheme.GOLD, 276.0))
	_card_info.show()
	_card_info.reset_size()
	var viewport_size := get_viewport_rect().size
	var info_size := _card_info.get_combined_minimum_size()
	_card_info.size = info_size
	_card_info.position = Vector2(
		clampf(holder.global_position.x + CARD_DISPLAY_SIZE.x * 0.5 - info_size.x * 0.5,
			LEFT_PANEL_WIDTH, viewport_size.x - RIGHT_COLUMN_WIDTH - info_size.x),
		viewport_size.y - CARD_PEEK_HEIGHT + CARD_LIFT - 8.0 - info_size.y
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
		var valid: bool = targeting and peer_id != me and _valid_party_target(peer_id)
		if halo != null:
			halo.visible = valid
		avatar.modulate = Color.WHITE if (not targeting or valid) else Color(0.55, 0.55, 0.55, 1.0)

## Hedef seçme modundayken sağdaki panelden bir partiye tıklanması.
func _on_target_party_clicked(peer_id: int) -> void:
	if _pending_target_hand_index == -1:
		_toggle_profile(peer_id)
		return
	if not _valid_party_target(peer_id):
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
	if CardPresets.has_full_art(card_type):
		flying.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		flying.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flying.z_index = 100
	flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying.modulate.a = 0.0
	add_child(flying)

	# Deste yok: kart sağ alttaki bozdurma kutusunun üstünden gelir.
	var deck_rect := _trash_panel.get_global_rect() if _trash_panel != null else Rect2(get_viewport_rect().size - Vector2(180, 180), CARD_DISPLAY_SIZE)
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
	var avatar := _find_avatar_node(peer_id)
	if avatar != null:
		return avatar.global_position - (out_size - avatar.size) * 0.5
	return get_viewport_rect().size / 2.0 - out_size / 2.0

func _play_card_animation(card_type: String, origin_pos: Vector2, origin_size: Vector2) -> void:
	var flying := TextureRect.new()
	flying.texture = CardPresets.get_card_texture(card_type)
	flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if CardPresets.has_full_art(card_type):
		flying.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		flying.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	particles.color = UiTheme.GOLD
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
	# Genişliği IZGARA belirler (tek sütun): sabit bir asgari genişlik panelden
	# taşıp satırları sola kaydırıyordu.
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# SIRA KİMDE: açık zemin + altın çerçeve + "SIRADA" etiketi (nabız gibi atar).
	# BEN: altın rengi isim + "SEN" etiketi. İkisi birlikte olabilir.
	var style := UiSkin.stylebox(UiSkin.PANEL if is_turn else UiSkin.PANEL_DARK)
	style.content_margin_left = 6
	# Sıra/hedef çerçevesi kartın üstüne çiziliyor: sayılar kenara değmesin.
	style.content_margin_right = 14
	# SABİT DÜZEN: oyuncu sayısı ne olursa olsun her satır İKİ SATIRDIR ve hiçbir
	# bilgi atılmaz; siyasetçinin adı kısaltılmaz (gerekirse yazısı küçülür).
	#   1. satır: siyasetçinin adı + etiketler (SIRA / SEN / POP / GB / YRD)
	#   2. satır: partisi + açık sekmenin sayı sütunları (başlıklarla hizalı)
	style.content_margin_top = 1 if _avatar_height < 40.0 else 3
	style.content_margin_bottom = 1 if _avatar_height < 40.0 else 3
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	# Solda parti renginde şerit: kartın kime ait olduğu ilk bakışta belli.
	row.add_child(UiTheme.stripe(color))
	var badge_size: float = clampf(_avatar_height - 12.0, 22.0, 40.0)
	var badge := PartyBadge.build(party, Vector2(badge_size, badge_size), BADGE_ICON_PIXEL_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	# YAZI BOYUTU satır yüksekliğine göre biraz küçülür (bilgi atılmaz): 8 oyuncuda
	# ad 12, parti 10; az oyuncuda ad 14, parti 12.
	var name_size: int = clampi(int((_avatar_height - 6.0) * 0.42), 10, UiTheme.FS_SMALL)
	var party_size: int = maxi(9, name_size - 2)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -4 if _avatar_height < 40.0 else -2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var independent := PartyManager.is_independent(peer_id)
	var party_text := L.t("Bağımsız") if independent else String(party.get("name", "?"))
	var party_color: Color = UiTheme.TEXT_MUTED if independent else color.lightened(0.45)
	var populism_left := CardManager.populism_rounds_left(peer_id)

	# 1. SATIR: ad + etiketler.
	var first := HBoxContainer.new()
	first.add_theme_constant_override("separation", 3)
	first.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(first)
	var tags: Array = []
	if is_turn:
		tags.append([L.t("SIRA"), UiTheme.TEXT, UiTheme.INK])
	if is_self:
		tags.append([L.t("SEN"), UiTheme.GOLD, UiTheme.INK])
	if populism_left > 0:
		tags.append([L.t("POP %d") % populism_left, UiTheme.PURPLE, UiTheme.TEXT])
	if PartyManager.is_deputy(peer_id):
		tags.append([L.t("YRD"), color, UiTheme.TEXT])
	elif PartyManager.deputy_of(peer_id) != -1:
		tags.append([L.t("GB"), color, UiTheme.TEXT])
	var tags_width := 0.0
	for tag in tags:
		tags_width += String(tag[0]).length() * 6.0 + 10.0
	var name_text := PoliticianPresets.display_name(peer_id)
	var name_width := _row_text_width(badge_size) - tags_width
	var name_label := _avatar_label(name_text, _fit_font_size(name_text, name_width, name_size, 9),
		UiTheme.GOLD if is_self else UiTheme.TEXT)
	name_label.clip_text = false
	name_label.add_theme_font_override("font", UiTheme.mono(true))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first.add_child(name_label)
	for tag in tags:
		var tag_control := _avatar_tag(String(tag[0]), tag[1], tag[2])
		tag_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		first.add_child(tag_control)

	# 2. SATIR: parti + sayı sütunları.
	var second := HBoxContainer.new()
	second.add_theme_constant_override("separation", 5)
	second.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(second)
	var party_label := _avatar_label(party_text, party_size, party_color)
	party_label.add_theme_font_override("font", UiTheme.mono(true))
	party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.add_child(party_label)
	# AÇIK SEKMENİN SAYI SÜTUNLARI (başlıkları tablonun ilk satırında).
	for cell in _player_row_values(peer_id, is_self):
		second.add_child(cell)
	# Hangi oyuncuya ait olduğu düğümün ÜSTÜNDE saklanıyor: hover tespiti ve
	# tooltip konumu panelin çocuk SIRASINA güvenmez (bkz. _party_under_mouse).
	card.set_meta("peer_id", peer_id)
	# Oylama sırasında kartın sağında partinin oyu (ya da beklendiği) yazar.
	if GovernmentManager.is_voting() and GovernmentManager.eligible_voter_ids().has(peer_id):
		var voted: bool = GovernmentManager.votes.has(peer_id)
		var tag := _avatar_label(GovernmentManager.vote_text(GovernmentManager.votes[peer_id]) if voted else "…", 11,
			VOTE_COLORS[int(GovernmentManager.votes[peer_id])] if voted else UiTheme.TEXT_MUTED)
		tag.clip_text = false
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		first.add_child(tag)
	# Vekil çalma hedefi vurgusu (bkz. _refresh_target_highlights).
	var halo := Panel.new()
	halo.name = L.t("TargetHalo")
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	halo.add_theme_stylebox_override("panel", UiSkin.color_box(UiTheme.GOLD, UiSkin.TARGET))
	halo.visible = false
	card.add_child(halo)
	if is_turn:
		var frame := Panel.new()
		frame.name = L.t("TurnFrame")
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", UiSkin.color_box(UiTheme.TEXT, UiSkin.TARGET))
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
	peer_id = CardManager.party_of(peer_id)  # plaketler parti başına
	for child in player_panel_list.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var control := child as Control
		if control != null and control.get_meta("peer_id", -1) == peer_id:
			return control
	return null

## Parti kartına dokununca profil açılır; aynı karta tekrar dokununca kapanır.
func _toggle_profile(peer_id: int) -> void:
	if _profile_peer_id == peer_id and (_pinned or _window_mode()):
		_hide_profile()
		return
	if _profile_peer_id != peer_id:
		_profile_peer_id = peer_id
		_show_tooltip_for(peer_id)
	# Tıklayınca KALICI: fare çekilince kapanmaz (✕, sekme ya da tekrar tıklama kapatır).
	_pinned = true

## Profil kartındaki parti işlemleri (bkz. PartyInfoCard._actions).
func _on_party_action(kind: String, peer_id: int) -> void:
	_hide_profile()
	match kind:
		"dissolve":
			CardManager.dissolve_party()
		"congress":
			CardManager.request_congress()
		"resign":
			CardManager.resign_from_party()
		"found":
			add_child(FoundPartyDialog.new())
		"inquiry":
			_open_inquiry_panel(peer_id)

func _hide_profile() -> void:
	_profile_peer_id = -1
	if hover_tooltip != null:
		hover_tooltip.hide()
	if _profile_scroll != null:
		_profile_scroll.queue_free()
		_profile_scroll = null
	_update_left_dock()

## Sol paneli kaplayan yuva (hükümet ve log bunun altında kalır).
func _ensure_left_dock() -> void:
	if _left_dock != null:
		return
	_left_dock = Panel.new()
	_left_dock.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_left_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	_left_dock.clip_contents = true
	_left_dock.hide()
	# Sıra göstergesi ve oyun bilgisi yerinde kalır; sadece hükümet + log alanı.
	government_vbox.get_parent().add_child(_left_dock)
	government_vbox.get_parent().move_child(_left_dock, government_vbox.get_index())

func _dock_width() -> float:
	var parent := government_vbox.get_parent() as Control
	return parent.size.x if parent.size.x > 0.0 else LEFT_PANEL_WIDTH - 28.0

## Sol paneldeki kartların doğal genişliği; panele sığacak kadar ölçeklenir.
const DOCK_CONTENT_WIDTH := 300.0
func _dock_scale() -> float:
	return minf(1.0, _dock_width() / DOCK_CONTENT_WIDTH)

func _update_left_dock() -> void:
	if _left_dock == null:
		return
	var showing := (_province_panel != null and _province_panel.embedded_mode and _province_panel.visible) or _profile_scroll != null
	if not showing:
		_pinned = false
	_left_dock.visible = showing
	for node in [government_vbox, _event_log]:
		if node != null:
			node.visible = not showing
	_refresh_side_tabs()

## Satırdaki metin alanının genişliği (şerit, rozet ve kenar payları hariç).
func _row_text_width(badge_size: float) -> float:
	var width: float = player_panel_list.size.x if player_panel_list != null and player_panel_list.size.x > 0.0 \
		else RIGHT_COLUMN_WIDTH - 24.0
	return width - 6.0 - 14.0 - 6.0 - badge_size - 10.0

## Metin bu genişliğe sığana kadar yazı boyutunu küçültür (isim kısaltılmaz).
func _fit_font_size(text: String, width: float, largest: int, smallest: int) -> int:
	var font := UiTheme.mono(true)
	for size in range(largest, smallest - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			return size
	return smallest

func _avatar_tag(text: String, bg: Color, fg: Color) -> Control:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_override("font", UiTheme.mono())
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", fg)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Düz ve ince kutu: dokulu kutu satırı yükseltiyordu (8 oyuncuda taşma).
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	tag.add_theme_stylebox_override("normal", style)
	tag.add_theme_constant_override("line_spacing", 0)
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
	if _window_mode():
		_show_profile_window(peer_id)
		return
	_ensure_left_dock()
	if _province_panel != null:
		_province_panel.hide()
	var keep_scroll := 0
	if _profile_scroll != null:
		# Aynı partinin profili tazeleniyorsa kaydırılan yer korunur; başka
		# partiye geçince en üstten başlar.
		if _profile_scroll_peer == peer_id:
			keep_scroll = _profile_scroll.scroll_vertical
		_profile_scroll.queue_free()
	_profile_scroll_peer = peer_id
	_profile_scroll = ScrollContainer.new()
	_profile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_dock.add_child(_profile_scroll)
	_fit_profile_scroll()
	PopupKit.embedded = true
	var card := PartyInfoCard.build(peer_id, multiplayer.get_unique_id(), _on_party_action,
		_dock_width() - 10.0, _hide_profile)
	PopupKit.embedded = false
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_scroll.add_child(card)
	_update_left_dock()
	await get_tree().process_frame
	if is_instance_valid(_profile_scroll):
		_fit_profile_scroll()
		_profile_scroll.scroll_vertical = keep_scroll

## PENCERE MODU: parti profili skor tablosunun hemen sağında, plaketle aynı
## hizada açılır (eski açılır kart).
func _show_profile_window(peer_id: int) -> void:
	if _province_panel != null and not _province_panel.embedded_mode:
		_province_panel.hide()
	hover_tooltip_image.hide()
	for child in hover_tooltip.get_children():
		if child != hover_tooltip_image:
			child.queue_free()
	var card := PartyInfoCard.build(peer_id, multiplayer.get_unique_id(), _on_party_action)
	card.modulate.a = 0.0
	hover_tooltip.add_child(card)
	hover_tooltip.show()
	await get_tree().process_frame
	if _profile_peer_id != peer_id or not is_instance_valid(card):
		return
	card.reset_size()
	hover_tooltip.size = card.size
	card.modulate.a = 1.0
	var viewport_size := get_viewport_rect().size
	var anchor_y := _r(R_BOARD).position.y
	var plaque := _find_avatar_node(peer_id)
	if plaque != null:
		anchor_y = plaque.global_position.y + plaque.size.y * 0.5 - hover_tooltip.size.y * 0.5
	hover_tooltip.global_position = Vector2(_r(R_BOARD).end.x + 12.0,
		clampf(anchor_y, _r(R_BOARD).position.y, maxf(_r(R_BOARD).position.y, viewport_size.y - hover_tooltip.size.y - 8.0)))

## Profil, doğal genişliğinde çizilip sol panele sığacak kadar küçültülür.
func _fit_profile_scroll() -> void:
	_profile_scroll.position = Vector2.ZERO
	_profile_scroll.size = _left_dock.size

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
	_refresh_side_tabs()
	_refresh_economy()
	_refresh_vote_ui()
	_refresh_action_buttons()
	_refresh_government_panel()
	_refresh_waiting_overlay()
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
		var badge := PartyBadge.build(PartyManager.data_of(holder), Vector2(96, 96), 192)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_waiting_badge_slot.add_child(badge)
		_waiting_badge_slot.position = Vector2(get_viewport_rect().size.x * 0.5 - 48.0, get_viewport_rect().size.y * 0.5 - 190.0)
	_waiting_label.text = L.t("HÜKÜMET KURULUYOR\n\n%s (%s)\ngörev dağılımını hazırlıyor…\n\n%d. teklif hakkı  ·  Süre: %s") % [
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
	_waiting_label.add_theme_font_override("font", UiTheme.mono())
	_waiting_label.add_theme_font_size_override("font_size", UiTheme.FS_HEAD)
	_waiting_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_waiting_overlay.add_child(_waiting_label)

	add_child(_waiting_overlay)

func _on_vote_pressed(choice: int) -> void:
	GovernmentManager.cast_vote(choice)

## Oy düğmesi: simge üstte, ad altta, kendi renginde (kapalıyken koyulaşır).
func _style_vote_button(button: Button, title: String, icon_name: String, color: Color) -> void:
	button.text = title
	button.custom_minimum_size = Vector2(44, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 10)
	UiSkin.skin_color_button(button, color)
	UiSkin.set_top_icon(button, icon_name, 20)

## Oylama butonları: teklif yokken (ya da oyumu kullandıysam) koyu ve
## tıklanamaz, oylama açıkken renkli.
func _refresh_vote_ui() -> void:
	var can_vote: bool = GovernmentManager.is_voting() \
		and GovernmentManager.eligible_voter_ids().has(multiplayer.get_unique_id()) \
		and not GovernmentManager.has_voted(multiplayer.get_unique_id())

	vote_yes_button.disabled = not can_vote
	vote_no_button.disabled = not can_vote
	# Koalisyon teklifinde ortak çekimser kalamaz: ya EVET ya HAYIR.
	_abstain_button.disabled = not can_vote or GovernmentManager.is_coalition_stage()

	proposal_label.text = GovernmentHud.proposal_status_text(multiplayer.get_unique_id())
	_refresh_proposer_chip()

## TEKLİFİ VEREN PARTİ: yasa/gensoru/hükümet oylamasında meclis diyagramının
## köşesinde logosu ve adıyla durur. Eskiden bu bilgi diyagramın altındaki
## uzun ipucu satırındaydı.
func _refresh_proposer_chip() -> void:
	if _proposer_chip == null:
		_proposer_chip = PanelContainer.new()
		_proposer_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := UiSkin.stylebox(UiSkin.SLOT)
		style.set_content_margin_all(6)
		_proposer_chip.add_theme_stylebox_override("panel", style)
		_proposer_row = HBoxContainer.new()
		_proposer_row.add_theme_constant_override("separation", 6)
		_proposer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_proposer_chip.add_child(_proposer_row)
		_proposer_chip.position = Vector2(6, 6)
		parliament_diagram.add_child(_proposer_chip)
	var peer_id := GovernmentManager.proposal_peer_id
	var active: bool = GovernmentManager.is_voting() and peer_id != -1
	_proposer_chip.visible = active
	if not active:
		return
	for child in _proposer_row.get_children():
		_proposer_row.remove_child(child)
		child.queue_free()
	# TEK SATIR ve DAR: yarım dairenin üstünde kalan boş şerit ancak bu kadar
	# yer bırakıyor, daha yükseği koltukların üstüne biniyor.
	_proposer_row.add_child(PartyBadge.build(PartyManager.data_of(peer_id),
		Vector2(22, 22), BADGE_ICON_PIXEL_SIZE))
	var who := Label.new()
	who.text = _party_name_of(peer_id)
	who.add_theme_font_size_override("font_size", 11)
	who.clip_text = true
	who.custom_minimum_size = Vector2(72, 22)
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_proposer_row.add_child(who)
	_proposer_chip.tooltip_text = "%s: %s" % [_proposal_kind_title(), _party_name_of(peer_id)]
	_proposer_chip.reset_size()

## Oylanan teklifin kısa türü (rozetin üst satırı).
func _proposal_kind_title() -> String:
	match GovernmentManager.proposal_kind:
		GovernmentManager.KIND_LAW: return L.t("YASAYI GETİREN")
		GovernmentManager.KIND_GOVERNMENT: return L.t("HÜKÜMETİ KURAN")
		GovernmentManager.KIND_CENSURE: return L.t("GENSORUYU VEREN")
		GovernmentManager.KIND_EARLY: return L.t("ÖNERGEYİ VEREN")
		GovernmentManager.KIND_CONSTITUTION: return L.t("DEĞİŞİKLİĞİ GETİREN")
	return L.t("TEKLİFİ VEREN")

func _party_name_of(peer_id: int) -> String:
	return GovernmentHud.party_name_of(peer_id)

func _leader_name_of(peer_id: int) -> String:
	return GovernmentHud.leader_name_of(peer_id)

func _refresh_government_panel() -> void:
	GovernmentHud.fill_government_panel(government_vbox)

## Puan tablosu da aynı evrensel tabloda (DURUM sekmesi).
func _refresh_score_panel() -> void:
	_rebuild_player_panel()
	_refresh_score_table()

# --- Hamleler: yasa tasarla, teşkilat, karalama hedefi -------------------

## Yasa dairesi sürüklenirken _drag_hand_index bu değeri alır (elde kart yok).
const LAW_DRAG_INDEX := -2
const FUNDS_COLOR := UiTheme.BLUE
const EMPTY_SEAT_COLOR := UiTheme.TEXT

## Sağ sütunun alt kısmı (aşağıdan yukarı): sıra göstergesi, pas, deste ve
## yanında YASA TASARLA / İL BAŞKANLIĞI butonları, para. Parti kartları üstte
## kalan alana sığar.
func _place_right_column_controls() -> void:
	# MASANIN SAĞI: para ve kart bozdurma yan yana, altında Turu Bitir.
	if _funds_plate != null:
		_set_rect(_funds_plate, _r(R_FUNDS))
	if _trash_panel != null:
		_set_rect(_trash_panel, _r(R_TRASH))
	pass_button.add_theme_font_size_override("font_size", 20)
	_set_rect(pass_button, _r(R_PASS))

## Seçili kart bozdurulur (sıra sendeyse).
func _on_trash_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var hand := CardManager.my_inventory()
	if _selected_hand_index < 0 or _selected_hand_index >= hand.size():
		_show_toast(L.t("Önce bozdurmak istediğin kartı seç."))
		return
	if not CardManager.can_act():
		_show_toast(L.t("Sıra sende değil."))
		return
	var index := _selected_hand_index
	_deselect_hand_card()
	_cancel_targeting()
	CardManager.discard_card(index)

## KART BOZDURMA: istemediğin kartı buraya sürükle, bedelinin yarısı para
## olarak geri gelir. Tıklanabilir bir buton değil, BIRAKMA HEDEFİ — bu yüzden
## buton değil, kendi başlığı ve para simgesi olan bir yuva paneli.
func _build_trash_button() -> void:
	_trash_panel = PanelContainer.new()
	_trash_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_trash_panel.gui_input.connect(_on_trash_input)
	_trash_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_trash_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_trash_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_trash_panel.tooltip_text = L.t("Bir kart seç, sonra buraya tıkla: kart bozulur, bedelinin yarısı kasaya döner.")
	var style := UiSkin.stylebox(UiSkin.SLOT)
	style.set_content_margin_all(UiTheme.PAD_S)
	_trash_panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trash_panel.add_child(row)
	var icon := CoinIcon.make(26.0, FUNDS_COLOR)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(box)
	box.add_child(_trash_label(L.t("KART BOZDUR"), 11, UiTheme.TEXT_MUTED))
	box.add_child(_trash_label(L.t("kartı seç, tıkla"), 10, UiTheme.TEXT_DIM))
	add_child(_trash_panel)

func _trash_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.mono())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build_action_buttons() -> void:
	# PARA LEVHASI: eskiden destenin yanında küçük bir simge+sayı ikilisiydi
	# ve gözden kaçıyordu. Artık sağ sütunun tamamı kadar geniş, kendi zemini
	# olan, hamle butonlarının hemen üstünde duran BÜYÜK bir gösterge.
	_funds_plate = PanelContainer.new()
	_funds_plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_funds_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_funds_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_funds_plate.offset_left = FUNDS_PLATE_LEFT
	_funds_plate.offset_right = -16.0
	_funds_plate.offset_top = FUNDS_PLATE_TOP
	_funds_plate.offset_bottom = FUNDS_PLATE_TOP + FUNDS_PLATE_HEIGHT
	_funds_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	_funds_plate.tooltip_text = L.t("Parti kasası")
	var funds_style := UiSkin.color_box(FUNDS_COLOR.darkened(0.62), UiSkin.SLOT)
	funds_style.content_margin_left = UiTheme.PAD_S
	funds_style.content_margin_right = UiTheme.PAD_S
	funds_style.content_margin_top = 2
	funds_style.content_margin_bottom = 2
	_funds_plate.add_theme_stylebox_override("panel", funds_style)
	add_child(_funds_plate)
	_funds_box = HBoxContainer.new()
	_funds_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_funds_box.add_theme_constant_override("separation", 8)
	_funds_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_funds_plate.add_child(_funds_box)
	var funds_icon := CoinIcon.make(FUNDS_ICON_SIZE, FUNDS_COLOR)
	funds_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_funds_box.add_child(funds_icon)
	_funds_label = Label.new()
	_funds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_funds_label.add_theme_font_override("font", UiTheme.mono(true))
	_funds_label.add_theme_font_size_override("font_size", 26)
	_funds_label.add_theme_color_override("font_color", FUNDS_COLOR)
	_funds_label.add_theme_color_override("font_outline_color", UiTheme.INK)
	_funds_label.add_theme_constant_override("outline_size", 6)
	_funds_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Tutar ve altında küçük birim: plaka eski genişliğinde kalır.
	var amount_box := VBoxContainer.new()
	amount_box.add_theme_constant_override("separation", -8)
	amount_box.alignment = BoxContainer.ALIGNMENT_CENTER
	amount_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_funds_box.add_child(amount_box)
	_funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_box.add_child(_funds_label)
	var unit := Label.new()
	unit.text = L.t("milyon ₺")
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.add_theme_font_override("font", UiTheme.mono(true))
	unit.add_theme_font_size_override("font_size", 10)
	unit.add_theme_color_override("font_color", FUNDS_COLOR.lightened(0.25))
	unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_box.add_child(unit)
	_funds_plate.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_toast(_funds_rules))
	_funds_rules = L.t("PARTİ KASASI: bağış ve aidatlar her sıranda %s (hükümetteysen %s), teşkilatların yerel bağışları ve seçim sonrası hazine yardımı. Kasan yettikçe istediğin kadar hamle yap; para birikir.\nDEVLET HAZİNESİ ayrıdır: onu sadece hükümet, yatırım için kullanır.") % [
		GameRules.cost_text(GameRules.FUNDS_PER_ROUND), GameRules.cost_text(GameRules.FUNDS_PER_ROUND_GOVERNMENT)]
	# HAMLELER: 3 sütun x 2 satır IZGARA. Eskiden her buton tek tek mutlak
	# konuma oturtuluyordu; uzun bir yazı (TEŞKİLATLANMA) butonun asgari
	# genişliğini büyütünce komşusunun üstüne biniyordu. Izgara bunu yapısal
	# olarak önler.
	_build_action_tabs()
	_action_grid = GridContainer.new()
	_action_grid.columns = 4
	_action_grid.add_theme_constant_override("h_separation", ACTION_BUTTON_GAP)
	_action_grid.add_theme_constant_override("v_separation", ACTION_BUTTON_GAP)
	# Izgara panelin ÜSTÜNE oturur; altındaki boşluğu esnek bir ayraç doldurur.
	# Dikey olarak esnetilince butonlar upuzun dikdörtgenlere dönüşüyordu.
	actions_vbox.add_child(_action_grid)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions_vbox.add_child(filler)
	_law_button = _action_button(L.t("YASA"), GameRules.cost_text(GameRules.LAW_FUNDS_COST), UiTheme.PURPLE, "", ActionTab.MECLIS)
	_law_button.pressed.connect(_on_law_button_pressed)
	_law_button.tooltip_text = L.t("Bir seçmen grubu için yasa sun: o grupta destek kazanırsın, karşıt grup biraz soğur. Geçerse puan. Dönemde bir kez.")
	_miting_button = _action_button(L.t("MİTİNG"), GameRules.cost_text(GameRules.MITING_FUNDS_COST), UiTheme.RED, "miting", ActionTab.SAHA)
	_miting_button.pressed.connect(_on_miting_button_pressed)
	_miting_button.tooltip_text = L.t("İlde oy kazandırır ve partini ilin kalabalık seçmen gruplarına yaklaştırır. Teşkilat ister; provokasyon riski vardır.")
	_org_button = _action_button(L.t("TEŞKİLAT"), GameRules.cost_text(GameRules.ORG_FUNDS_COST), UiTheme.BLUE, "teskilat", ActionTab.SAHA)
	_org_button.pressed.connect(_on_org_button_pressed)
	_org_button.tooltip_text = L.t("İlde kalıcı güç ve anket; yerel bağışlarla kasana düzenli para getirir.")
	_invest_button = _action_button(L.t("YATIRIM"), GameRules.cost_text(Economy.INVEST_COST), UiTheme.GREEN_DARK, "yatirim", ActionTab.SAHA)
	_invest_button.pressed.connect(_on_invest_button_pressed)
	_invest_button.tooltip_text = L.t("Güçlü yerel etki: ildeki bütün seçmen memnun olur. Devlet hazinesinden (gerekirse parti kasasından) ödenir; sadece hükümet partileri.")
	_censure_button = _action_button(L.t("GENSORU"), GameRules.cost_text(GameRules.CENSURE_FUNDS_COST), UiTheme.RED_DARK, "gensoru", ActionTab.MECLIS)
	_censure_button.pressed.connect(_on_censure_button_pressed)
	_censure_button.tooltip_text = L.t("Hükümeti düşürmeye çalış: meclis oylar. Reddedilirse küçük bir itibar kaybı.")
	_early_button = _action_button(L.t("ERKEN SEÇİM"), GameRules.cost_text(GameRules.EARLY_ELECTION_FUNDS_COST), UiTheme.GOLD, "erken_secim", ActionTab.MECLIS)
	_early_button.pressed.connect(_on_early_button_pressed)
	_early_button.tooltip_text = L.t("Erken seçim önergesi: kabul edilirse dönem sonunda sandık kurulur.")
	# GRUP TOPLANTISI: sıra sendeyken açık, sırada bir kez.
	_speech_button = _action_button(L.t("TOPLANTI"), GameRules.cost_text(GameRules.SPEECH_FUNDS_COST), UiTheme.GOLD_DIM, "grup_toplantisi", ActionTab.PARTI)
	_speech_button.tooltip_text = L.t("Grup toplantısı: bir seçmen grubunun sorunlarını konuş. O grupta kısa süreli destek (bu dönem güçlü, sonra hızla söner). Dönemde bir kez, isteğe bağlı.")
	_speech_button.pressed.connect(_on_speech_button_pressed)
	# KONGRE: genel başkan kendi sırasında (en az bir seçim geçtiyse) kongreye
	# gider; partide üye kalan eski başkan kongre ister.
	_congress_button = _action_button(L.t("KONGRE"), _congress_cost_text(), UiTheme.PURPLE.darkened(0.3), "kongre", ActionTab.PARTI)
	_congress_button.pressed.connect(_on_congress_button_pressed)
	_congress_button.tooltip_text = L.t("Genel başkan: partini kongreye götür, liderliğini tazele. Üye: kongre iste, başkanlığı geri almaya çalış.")
	# AFET YARDIMI: sadece bir afet sürerken; tutarı oyuncu belirler.
	_aid_button = _action_button(L.t("YARDIM"), L.t("tutar serbest"), UiTheme.RED.darkened(0.15), "yardim", ActionTab.SAHA)
	_aid_button.pressed.connect(_on_aid_button_pressed)
	_aid_button.tooltip_text = L.t("Afet bölgesine yardım götür: tutarı sen belirlersin. Hükümetsen devlet hazinesinden de ödeyebilirsin. Yatırımdan çok daha güçlü ve hemen etki eder; seçmen gruplarına dokunmaz.")
	_inquiry_button = _action_button(L.t("SORUŞTURMA"), GameRules.cost_text(Economy.INQUIRY_FUNDS_COST), UiTheme.PURPLE.darkened(0.1), "sorusturma", ActionTab.SIYASET)
	_inquiry_button.pressed.connect(_on_inquiry_button_pressed)
	_inquiry_button.tooltip_text = L.t("Bir partinin harcamalarına finansman soruşturması aç: devlet parasıyla miting usulsüzlüktür, kendi kasasından ödeyen itibar kazanır.")
	_alliance_button = _action_button(L.t("İTTİFAK"), L.t("görüntüle"), UiTheme.GOLD, "", ActionTab.SIYASET)
	_alliance_button.pressed.connect(_on_alliance_button_pressed)
	_alliance_button.tooltip_text = L.t("İttifakları görüntüle, kur veya partileri davet et ve katıl.")

## Kongre bedeli oyuncunun yerine göre: genel başkan 10, üye 20.
func _congress_cost_text() -> String:
	var me := multiplayer.get_unique_id()
	var cost := CardManager.CONGRESS_REQUEST_COST if CardManager.is_party_member(me) else CardManager.CONGRESS_COST
	return GameRules.cost_text(cost)

## Hamle butonu: ızgaraya eklenir, sabit kutu boyutunda kalır ve yazı taşarsa
## kırpılır — böylece hiçbir buton komşusunu itemez.
func _action_button(title: String, cost_text: String, color: Color, icon_name: String = "", tab: int = ActionTab.SAHA) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_constant_override("line_spacing", -1)
	_set_action_text(button, title, cost_text)
	UiSkin.skin_color_button(button, color)
	UiSkin.set_top_icon(button, icon_name, 18)
	_action_grid.add_child(button)
	_action_tab_of[button] = tab
	button.visible = tab == _action_tab
	return button

## Sekme şeridi: harita katman düğmeleriyle aynı dil (kare, seçili olan altın).
## Düğmede, o sekmede şu an yapılabilir hamle sayısı yazar.
func _build_action_tabs() -> void:
	_action_tab_bar = HBoxContainer.new()
	_action_tab_bar.add_theme_constant_override("separation", 0)
	actions_vbox.add_child(_action_tab_bar)
	for i in ACTION_TAB_TITLES.size():
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 30)
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_select_action_tab.bind(i))
		_action_tab_bar.add_child(button)
		_action_tab_buttons.append(button)

func _select_action_tab(tab: int) -> void:
	_action_tab = tab
	for button in _action_tab_of:
		(button as Control).visible = int(_action_tab_of[button]) == tab
	_refresh_action_tabs()

func _refresh_action_tabs() -> void:
	var ready := {}
	for button in _action_tab_of:
		if (button as Control).modulate.a > 0.9:
			var t := int(_action_tab_of[button])
			ready[t] = int(ready.get(t, 0)) + 1
	for i in _action_tab_buttons.size():
		var button: Button = _action_tab_buttons[i]
		var active := i == _action_tab
		var count := int(ready.get(i, 0))
		button.text = "%s %d" % [L.t(ACTION_TAB_TITLES[i]), count] if count > 0 else L.t(ACTION_TAB_TITLES[i])
		_style_tab_button(button, active, count > 0)

## Sekme düğmesi (hamle ve yasa sekmeleri): harita katman düğmeleri gibi kare,
## seçili olan altın; lit false ise yazı sönük.
func _style_tab_button(button: Button, active: bool, lit: bool) -> void:
	var color := UiTheme.GOLD if active else UiTheme.PANEL
	for state in ["normal", "hover", "pressed", "focus"]:
		var c := color.lightened(0.08) if state == "hover" and not active else color
		button.add_theme_stylebox_override(state, _layer_button_style(c, false, false))
	var font := UiTheme.INK if active else (UiTheme.TEXT if lit else UiTheme.TEXT.darkened(0.4))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, font)

## Hamle düğmesinin iki satırı (ad + bedel). DAR KUTUYA SIĞSIN: en uzun satır
## düğmeye sığana kadar yazı küçülür (İngilizce "EARLY ELECTION" gibi; ad
## kısaltılmaz).
func _set_action_text(button: Button, title: String, cost_text: String) -> void:
	button.text = "%s\n%s" % [title, cost_text]
	# İki satır ayrı ölçülür, düğmenin yazı tipiyle (5 sütunda kutu dar).
	var width := ACTION_BUTTON_WIDTH - 10.0
	var font := UiTheme.mono()
	var size := UiTheme.FS_TINY - 2
	while size > 6 and (font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width
			or font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width):
		size -= 1
	button.add_theme_font_size_override("font_size", size)

## Neden şu an bu hamle yapılamıyor? (Buton ipucu ve uyarı yazısı.)
func _action_block_reason(cost: float, is_law: bool = false) -> String:
	var me := multiplayer.get_unique_id()
	if CardManager.is_party_member(me):
		return L.t("Partinin genel başkanı değilsin: sadece miting yapabilirsin (partine ve güvenilirliğine yazar).")
	if is_law and CardManager.last_seats.is_empty():
		return L.t("İlk seçime kadar meclis yok: yasa yapılamaz.")
	if is_law and not CardManager.has_seats(me):
		return L.t("Mecliste vekilin yok: yasa teklif edemezsin.")
	if not CardManager.can_act():
		return L.t("Sıran değil.")
	if is_law and CardManager.has_proposed_law_this_round(me, "group"):
		return L.t("Bu dönem zaten bir seçmen grubu yasası sundun (vergi yasası ve anayasa ayrı haklardır).")
	if CardManager.funds_of(me) < cost:
		return L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(cost)
	return L.t("Şu an yapılamaz.")

func _refresh_action_buttons() -> void:
	if _law_button == null:
		return
	var me := multiplayer.get_unique_id()
	var funds_now := CardManager.funds_of(me)
	_funds_label.text = CardManager.funds_text(funds_now)
	var law_ok := CardManager.can_propose_law(me) or CardManager.can_propose_constitution(me)
	var org_ok := CardManager.can_choose_main_action(me) and funds_now >= CardManager.org_cost_for(me)
	_set_action_text(_org_button, L.t("TEŞKİLAT"), GameRules.cost_text(CardManager.org_cost_for(me)))
	var miting_ok := CardManager.can_miting(me)
	_miting_button.modulate.a = 1.0 if miting_ok or _pending_miting else 0.45
	_invest_button.modulate.a = 1.0 if CardManager.can_invest(me) or _pending_invest else 0.45
	_censure_button.modulate.a = 1.0 if CardManager.can_censure(me) or _pending_censure else 0.45
	_early_button.modulate.a = 1.0 if CardManager.can_early_election(me) or _pending_early else 0.45
	_congress_button.modulate.a = 1.0 if CardManager.can_call_congress(me) or _pending_congress else 0.45
	if _aid_button != null:
		_aid_button.modulate.a = 1.0 if CardManager.can_aid(me) else 0.45
	if _inquiry_button != null:
		_inquiry_button.modulate.a = 1.0 if CardManager.can_open_inquiry(me) else 0.45
	if _alliance_button != null:
		_alliance_button.modulate.a = 1.0 if CardManager.alliances_enabled else 0.45
	# disabled kullanılmıyor: pasif butona dokununca neden olmadığı uyarı olarak çıksın.
	_law_button.modulate.a = 1.0 if law_ok else 0.45
	_org_button.modulate.a = 1.0 if org_ok or _pending_org else 0.45
	_set_action_text(_congress_button, L.t("KONGRE"), _congress_cost_text())
	# TOPLANTI: sıra sendeyken açık; sırada bir kez (konuşunca söner).
	if _speech_button != null:
		_speech_button.modulate.a = 1.0 if CardManager.can_act() and CardManager.needs_speech(me) else 0.45
	if _alliance_panel != null and _alliance_panel.visible:
		_refresh_alliance_panel()
	_refresh_action_tabs()

func _build_agenda_banner() -> void:
	_agenda_banner = PanelContainer.new()
	var style := UiSkin.color_box(UiTheme.GOLD.darkened(0.45), UiSkin.BUTTON_TINT_NORMAL)
	style.set_content_margin_all(UiTheme.PAD_S)
	_agenda_banner.add_theme_stylebox_override("panel", style)
	_agenda_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_agenda_label = Label.new()
	_agenda_label.add_theme_font_override("font", UiTheme.mono())
	_agenda_label.add_theme_font_size_override("font_size", UiTheme.FS_TINY)
	_agenda_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_agenda_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_agenda_banner.add_child(_agenda_label)
	# Haritayı kapatmasın: sol panelde tarih/baraj levhasının hemen altında durur.
	var plate := get_node_or_null("%InfoPlate")
	if plate != null:
		plate.get_parent().add_child(_agenda_banner)
		plate.get_parent().move_child(_agenda_banner, plate.get_index() + 1)
	else:
		add_child(_agenda_banner)
	_refresh_agenda_banner()

func _refresh_agenda_banner() -> void:
	_refresh_band_crisis()
	if _agenda_banner == null:
		return
	var current := CardManager.agenda_type()
	# Gündem ve kriz artık üst bantta.
	_agenda_banner.visible = false
	if current == "":
		return
	var data := CardPresets.agenda_data(current)
	# Kısa tut: sol panelde olay loguna yer kalsın.
	_agenda_label.text = L.t("GÜNDEM: %s\n%s") % [data["title"], CardPresets.agenda_effect_text(current)]

func _build_alliance_panel() -> void:
	_alliance_panel = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	_alliance_panel.add_theme_stylebox_override("panel", style)
	_alliance_panel.z_index = 108
	_alliance_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_alliance_panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := UiTheme.mono_label(L.t("SEÇİM İTTİFAKLARI"), 14, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = L.t("Kapat")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): _alliance_panel.hide())
	UiSkin.skin_button(close)
	header.add_child(close)
	box.add_child(PopupKit.note(L.t("Barajda ortak oy sayılır. Her ilde ittifakın vekilleri, üyelerin oy oranına göre paylaşılır."), UiTheme.TEXT_DIM, 360))
	_alliance_list = VBoxContainer.new()
	_alliance_list.add_theme_constant_override("separation", 5)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 220)
	scroll.add_child(_alliance_list)
	box.add_child(scroll)
	var divider := HSeparator.new()
	box.add_child(divider)
	box.add_child(UiTheme.section_label(L.t("YENİ İTTİFAK KUR")))
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 5)
	box.add_child(create_row)
	_alliance_name = LineEdit.new()
	_alliance_name.placeholder_text = L.t("İttifak adı")
	_alliance_name.max_length = 28
	_alliance_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_alliance_name)
	_alliance_color = ColorPickerButton.new()
	_alliance_color.color = UiTheme.GOLD
	_alliance_color.custom_minimum_size = Vector2(42, 34)
	_alliance_color.tooltip_text = L.t("İttifak rengini seç")
	create_row.add_child(_alliance_color)
	_alliance_create_button = Button.new()
	_alliance_create_button.text = L.t("KUR")
	_alliance_create_button.focus_mode = Control.FOCUS_NONE
	UiSkin.skin_color_button(_alliance_create_button, UiTheme.GOLD.darkened(0.25))
	_alliance_create_button.pressed.connect(_on_alliance_create_pressed)
	box.add_child(_alliance_create_button)
	_alliance_panel.hide()
	add_child(_alliance_panel)

func _on_alliance_button_pressed() -> void:
	_deselect_hand_card()
	if _alliance_panel.visible:
		_alliance_panel.hide()
		return
	if _law_designer != null:
		_law_designer.hide()
	if _inquiry_panel != null:
		_inquiry_panel.hide()
	_refresh_alliance_panel()
	_alliance_panel.show()
	_place_alliance_panel.call_deferred()

func _on_alliance_create_pressed() -> void:
	var me := multiplayer.get_unique_id()
	var reason := _alliance_action_reason(me)
	if reason != "":
		_show_toast(reason)
		return
	if _alliance_name.text.strip_edges() == "":
		_show_toast(L.t("İttifaka bir ad ver."))
		return
	CardManager.create_alliance(me, _alliance_name.text, _alliance_color.color)
	_alliance_name.clear()

func _alliance_action_reason(peer_id: int) -> String:
	if not CardManager.alliances_enabled:
		return L.t("Anayasa seçim ittifaklarını devre dışı bıraktı.")
	if PartyManager.is_independent(peer_id):
		return L.t("Bağımsız siyasetçiler ittifaka katılamaz.")
	if CardManager.is_party_member(peer_id):
		return L.t("İttifak kararını partinin genel başkanı verir.")
	if not CardManager.can_choose_main_action(peer_id):
		return L.t("İttifaka katılmak veya davet göndermek için sıranı bekle.")
	return ""

func _refresh_alliance_panel() -> void:
	if _alliance_list == null or not is_instance_valid(_alliance_list):
		return
	for child in _alliance_list.get_children():
		child.free()
	var me := multiplayer.get_unique_id()
	var my_party := CardManager.party_of(me)
	var my_alliance := CardManager.alliance_of(me)
	var action_reason := _alliance_action_reason(me)
	_alliance_create_button.modulate.a = 1.0 if action_reason == "" and my_alliance < 0 else 0.45
	if not CardManager.alliances_enabled:
		_alliance_list.add_child(PopupKit.note(L.t("Anayasa ittifakları devre dışı bıraktı. Yeni seçim ittifakı kurulamaz ve ittifak hesabı yapılmaz."), UiTheme.RED, 340))
	elif CardManager.alliances.is_empty():
		_alliance_list.add_child(PopupKit.note(L.t("Henüz kurulmuş bir seçim ittifakı yok."), UiTheme.TEXT_DIM, 340))
	for alliance_id in CardManager.alliances:
		var alliance: Dictionary = CardManager.alliances[alliance_id]
		var members: Array = alliance.get("members", [])
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var heading := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.color = alliance.get("color", UiTheme.GOLD)
		heading.add_child(swatch)
		var name_label := UiTheme.mono_label(String(alliance.get("name", L.t("İttifak"))), UiTheme.FS_SMALL, UiTheme.TEXT, true)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(name_label)
		row.add_child(heading)
		var names: Array[String] = []
		for pid in members:
			names.append(String(PartyManager.data_of(int(pid)).get("name", "?")))
		row.add_child(PopupKit.note(L.t("Üyeler: %s") % (", ".join(PackedStringArray(names)) if not names.is_empty() else L.t("yok")), UiTheme.TEXT_DIM, 350))
		var invitations: Array = alliance.get("invitations", [])
		for target in invitations:
			var target_name := String(PartyManager.data_of(int(target)).get("name", "?"))
			row.add_child(PopupKit.note(L.t("Davet bekliyor: %s") % target_name, UiTheme.GOLD, 350))
		var action := Button.new()
		action.focus_mode = Control.FOCUS_NONE
		if my_alliance == int(alliance_id):
			action.text = L.t("DAVET ET")
			UiSkin.skin_color_button(action, Color(alliance.get("color", UiTheme.GOLD)).darkened(0.25))
			action.pressed.connect(_on_alliance_invite_pressed.bind(int(alliance_id)))
			var can_invite := action_reason == "" and not PartyManager.is_independent(me)
			var has_targets := false
			for pid in CardManager.party_ids():
				if not PartyManager.is_independent(int(pid)) and CardManager.alliance_of(int(pid)) < 0 and int(pid) != my_party:
					has_targets = true
			action.modulate.a = 1.0 if can_invite and has_targets else 0.45
			row.add_child(action)
		elif my_alliance < 0:
			action.text = L.t("KATIL") if invitations.has(my_party) else L.t("KATIL")
			UiSkin.skin_color_button(action, Color(alliance.get("color", UiTheme.GOLD)).darkened(0.25))
			action.pressed.connect(_on_alliance_join_pressed.bind(int(alliance_id)))
			action.modulate.a = 1.0 if action_reason == "" else 0.45
			row.add_child(action)
		_alliance_list.add_child(row)
		var divider := HSeparator.new()
		_alliance_list.add_child(divider)

func _on_alliance_join_pressed(alliance_id: int) -> void:
	var reason := _alliance_action_reason(multiplayer.get_unique_id())
	if reason != "":
		_show_toast(reason)
		return
	CardManager.join_alliance(multiplayer.get_unique_id(), alliance_id)
	_refresh_alliance_panel()

func _on_alliance_invite_pressed(alliance_id: int) -> void:
	var reason := _alliance_action_reason(multiplayer.get_unique_id())
	if reason != "":
		_show_toast(reason)
		return
	var picker := PopupMenu.new()
	for pid in CardManager.party_ids():
		if PartyManager.is_independent(int(pid)) or CardManager.alliance_of(int(pid)) >= 0 or int(pid) == CardManager.party_of(multiplayer.get_unique_id()):
			continue
		picker.add_item(String(PartyManager.data_of(int(pid)).get("name", "?")), int(pid))
	if picker.item_count == 0:
		_show_toast(L.t("Davet edilebilecek başka parti yok."))
		return
	add_child(picker)
	picker.id_pressed.connect(func(pid: int):
		CardManager.invite_alliance_party(multiplayer.get_unique_id(), alliance_id, pid)
		_refresh_alliance_panel()
		picker.queue_free())
	picker.popup()

func _place_alliance_panel() -> void:
	if not _alliance_panel.visible:
		return
	_alliance_panel.reset_size()
	await get_tree().process_frame
	_alliance_panel.reset_size()
	var viewport_size := get_viewport_rect().size
	_alliance_panel.position = Vector2(viewport_size.x - RIGHT_COLUMN_WIDTH - _alliance_panel.size.x - 12.0,
		clampf(_top_area_height() - _alliance_panel.size.y, 12.0, maxf(12.0, viewport_size.y - _alliance_panel.size.y - 12.0)))

func _build_law_designer() -> void:
	_law_designer = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	_law_designer.add_theme_stylebox_override("panel", style)
	_law_designer.z_index = 108
	_law_designer.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_law_designer.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = L.t("YASA TEKLİFİ")
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = L.t("Kapat")
	UiSkin.skin_button(close)
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(func(): _law_designer.hide())
	header.add_child(close)
	# Kazanç satırı: kabul edilirse puan, bedel.
	_law_points_label = Label.new()
	_law_points_label.add_theme_font_size_override("font_size", 11)
	_law_points_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_law_points_label.custom_minimum_size = Vector2(240, 0)
	_law_points_label.add_theme_color_override("font_color", UiTheme.GREEN)
	box.add_child(_law_points_label)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	box.add_child(tabs)
	for i in LAW_TAB_TITLES.size():
		var tab_button := Button.new()
		tab_button.focus_mode = Control.FOCUS_NONE
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.custom_minimum_size = Vector2(0, 30)
		tab_button.add_theme_font_size_override("font_size", 12)
		tab_button.text = L.t(LAW_TAB_TITLES[i])
		tab_button.pressed.connect(_select_law_tab.bind(i))
		tabs.add_child(tab_button)
		_law_tab_buttons.append(tab_button)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4)
		box.add_child(page)
		_law_pages.append(page)
	var group_page: VBoxContainer = _law_pages[LawTab.GROUP]
	_law_tax_box = _law_pages[LawTab.TAX]
	_law_tax_box.add_theme_constant_override("separation", 6)
	_law_tax_box.custom_minimum_size = Vector2(404, 0)
	# Gündem şeridi.
	_law_agenda_label = Label.new()
	_law_agenda_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_law_agenda_label.custom_minimum_size = Vector2(240, 0)
	_law_agenda_label.add_theme_font_size_override("font_size", 11)
	_law_agenda_label.add_theme_color_override("font_color", UiTheme.GOLD)
	group_page.add_child(_law_agenda_label)
	# SEKİZ SEÇMEN GRUBU (iki sütun): gündemdeki çiftin grupları seçilebilir.
	_law_rows = GridContainer.new()
	_law_rows.columns = 2
	_law_rows.add_theme_constant_override("h_separation", 4)
	_law_rows.add_theme_constant_override("v_separation", 4)
	group_page.add_child(_law_rows)
	_law_detail = VBoxContainer.new()
	_law_detail.add_theme_constant_override("separation", 3)
	_law_detail.custom_minimum_size = Vector2(300, 0)
	group_page.add_child(_law_detail)
	_build_constitution_section(_law_pages[LawTab.CONSTITUTION])
	_law_designer.hide()
	add_child(_law_designer)

## ANAYASA DEĞİŞİKLİĞİ paneli (yasa panelinin altında). Gündeme bağlı değil,
## ama meclisin 2/3'ü gerekir. Oyuncu barajı ve seçim aralığını seçip paket
## halinde sunar.
func _build_constitution_section(box: VBoxContainer) -> void:
	box.add_child(UiTheme.section_label(L.t("Anayasa değişikliği")))
	_constitution_threshold = MultiplayerManager.election_threshold
	_constitution_interval = MultiplayerManager.election_interval
	# Altı ayar iki sütunlu ızgarada: panel ekrandan taşmasın.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)

	var threshold_row := HBoxContainer.new()
	threshold_row.add_theme_constant_override("separation", 6)
	var threshold_row_title := UiTheme.body_label(L.t("Baraj"), UiTheme.FS_TINY, UiTheme.TEXT_MUTED)
	threshold_row_title.custom_minimum_size.x = 58
	threshold_row.add_child(threshold_row_title)
	_constitution_threshold_label = UiTheme.mono_label("", UiTheme.FS_SMALL)
	_constitution_threshold_label.custom_minimum_size.x = 48
	_constitution_threshold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	threshold_row.add_child(_stepper_button("−", func(): _change_constitution(-0.5, 0)))
	threshold_row.add_child(_constitution_threshold_label)
	threshold_row.add_child(_stepper_button("+", func(): _change_constitution(0.5, 0)))
	grid.add_child(threshold_row)

	var interval_row := HBoxContainer.new()
	interval_row.add_theme_constant_override("separation", 6)
	var interval_row_title := UiTheme.body_label(L.t("Seçim"), UiTheme.FS_TINY, UiTheme.TEXT_MUTED)
	interval_row_title.custom_minimum_size.x = 58
	interval_row.add_child(interval_row_title)
	_constitution_interval_label = UiTheme.mono_label("", UiTheme.FS_SMALL)
	_constitution_interval_label.custom_minimum_size.x = 48
	_constitution_interval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interval_row.add_child(_stepper_button("−", func(): _change_constitution(0.0, -1)))
	interval_row.add_child(_constitution_interval_label)
	interval_row.add_child(_stepper_button("+", func(): _change_constitution(0.0, 1)))
	grid.add_child(interval_row)

	# Sayım yöntemi: D'Hondt / Hare / Kazanan hepsini alır.
	_constitution_method = MultiplayerManager.seat_method
	var method_row := HBoxContainer.new()
	method_row.add_theme_constant_override("separation", 6)
	var method_title := UiTheme.body_label(L.t("Sayım"), UiTheme.FS_TINY, UiTheme.TEXT_MUTED)
	method_title.custom_minimum_size.x = 58
	method_row.add_child(method_title)
	_constitution_method_label = UiTheme.mono_label("", UiTheme.FS_TINY)
	_constitution_method_label.custom_minimum_size.x = 150
	_constitution_method_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	method_row.add_child(_stepper_button("−", func(): _change_constitution_method(-1)))
	method_row.add_child(_constitution_method_label)
	method_row.add_child(_stepper_button("+", func(): _change_constitution_method(1)))
	box.add_child(method_row)

	_constitution_button = Button.new()
	_constitution_button.text = L.t("ANAYASAYI DEĞİŞTİR")
	_constitution_button.add_theme_font_size_override("font_size", UiTheme.FS_TINY)
	UiSkin.skin_color_button(_constitution_button, UiTheme.GOLD.darkened(0.25))
	_constitution_button.pressed.connect(_on_constitution_pressed)
	box.add_child(_constitution_button)
	_constitution_alliances = CheckButton.new()
	_constitution_alliances.text = L.t("Seçim ittifakları açık")
	_constitution_alliances.button_pressed = CardManager.alliances_enabled
	_constitution_alliances.add_theme_font_size_override("font_size", UiTheme.FS_TINY)
	_constitution_alliances.toggled.connect(func(_pressed: bool): _refresh_constitution_section())
	box.add_child(_constitution_alliances)

	_constitution_info = Label.new()
	_constitution_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_constitution_info.custom_minimum_size = Vector2(240, 0)
	_constitution_info.add_theme_font_size_override("font_size", 10)
	_constitution_info.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	box.add_child(_constitution_info)

func _change_constitution_method(step: int) -> void:
	var methods: Array = ElectionModel.SEAT_METHODS
	var i := methods.find(_constitution_method)
	_constitution_method = methods[clampi(i + step, 0, methods.size() - 1)]
	_refresh_constitution_section()

func _stepper_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(28, 24)
	button.add_theme_font_size_override("font_size", UiTheme.FS_SMALL)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button

func _change_constitution(threshold_delta: float, interval_delta: int) -> void:
	_constitution_threshold = clampf(_constitution_threshold + threshold_delta, 0.0, 10.0)
	_constitution_interval = clampi(_constitution_interval + interval_delta,
		GameRules.ELECTION_INTERVAL_MIN, GameRules.ELECTION_INTERVAL_MAX)
	_refresh_constitution_section()

func _refresh_constitution_section() -> void:
	if _constitution_threshold_label == null:
		return
	_constitution_threshold_label.text = L.t("%%%s") % String.num(_constitution_threshold, 1)
	_constitution_interval_label.text = L.t("%d yıl") % _constitution_interval
	_constitution_method_label.text = ElectionModel.method_title(_constitution_method)
	var me := multiplayer.get_unique_id()
	var can := CardManager.can_propose_constitution(me)
	_constitution_button.disabled = not can
	var needed := GovernmentManager.constitution_threshold_seats()
	var changed: bool = not is_equal_approx(_constitution_threshold, MultiplayerManager.election_threshold) 		or _constitution_interval != MultiplayerManager.election_interval \
		or _constitution_method != MultiplayerManager.seat_method \
		or _constitution_alliances.button_pressed != CardManager.alliances_enabled
	if not changed:
		_constitution_info.text = L.t("Şu anki kuralları değiştirmiyor. Bir ayarı değiştir.")
		_constitution_button.disabled = true
	elif can:
		_constitution_info.text = L.t("Meclisin 2/3'ü (%d vekil) EVET derse yürürlüğe girer, yoksa reddedilir. İttifaklar baraj için ortak sayılır; seçim çevresinde vekiller önce ittifaka, sonra üyelere dağıtılır.") % needed
	else:
		_constitution_info.text = _action_block_reason(0, true)

## Yasa panelinin değişen kısımları: puan, gündem, seçmen grupları, seçili grubun etkisi
## ve gündem çarpanı rozetleri. Panel her açılışta tazelenir.
func _refresh_law_designer() -> void:
	_refresh_law_tabs()
	_refresh_constitution_section()
	if _law_tab == LawTab.TAX:
		EconomyPanel.fill_policy(_law_tax_box, multiplayer.get_unique_id(), _law_tax_selected,
			_on_law_tax_selected, _propose_tax, _law_designer.hide, false)
	var me := multiplayer.get_unique_id()
	var in_gov := CardManager.is_government_party(me)
	_law_points_label.text = L.t("Kabul: +%d puan · %s") % [CardManager.law_pass_score(in_gov), GameRules.cost_text(GameRules.LAW_FUNDS_COST)]
	var current := CardManager.agenda_type()
	if current == "":
		_law_agenda_label.text = L.t("Gündem yok: her grup için yasa sunulabilir.")
	else:
		var data := CardPresets.agenda_data(current)
		_law_agenda_label.text = L.t("Gündem: %s — %s.") % [data["title"], CardPresets.agenda_effect_text(current)]
	for child in _law_rows.get_children():
		child.queue_free()
	var groups_on_agenda := CardManager.agenda_groups()
	if _law_group == "":
		_law_group = String(groups_on_agenda[0]) if not groups_on_agenda.is_empty() else String(VoterGroups.GROUP_IDS[0])
	for group in VoterGroups.GROUP_IDS:
		_law_rows.add_child(_law_group_button(group, groups_on_agenda.has(group)))
	_refresh_law_detail()

func _select_law_tab(tab: int) -> void:
	_law_tab = tab
	_law_tax_selected = -1
	_refresh_law_designer()
	_place_law_designer()

func _on_law_tax_selected(level: int) -> void:
	_law_tax_selected = level
	_refresh_law_designer()
	_place_law_designer()

## Sekme düğmeleri hamle sekmeleriyle aynı stilde; yalnız seçili sayfa görünür.
func _refresh_law_tabs() -> void:
	for i in _law_tab_buttons.size():
		(_law_pages[i] as Control).visible = i == _law_tab
		_style_tab_button(_law_tab_buttons[i], i == _law_tab, true)

## Yasa panelinde bir seçmen grubu düğmesi: simge + tam ad. Gündemde değilse
## sönük ve seçilemez; seçiliyse altın çerçeve.
func _law_group_button(group: String, on_agenda: bool) -> Control:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(150, 30)
	button.clip_text = false
	var tint := VoterGroups.color(group)
	UiSkin.skin_color_button(button, tint.darkened(0.45) if group != _law_group else tint.darkened(0.15))
	button.tooltip_text = L.t("%s\nTalepler: %s%s") % [VoterGroups.title(group), VoterGroups.issues_text(group),
		L.t("\nGÜNDEMDE: yasa daha güçlü ve ulusal destek getirir.") if on_agenda else ""]
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
	label.text = ("★ " if on_agenda else "") + VoterGroups.title(group)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", UiTheme.GOLD if group == _law_group or on_agenda else UiTheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	button.pressed.connect(func():
		_law_group = group
		_refresh_law_designer())
	return button

## "+3,9" / "−2,5" gibi işaretli kısa sayı.
static func _signed(value: float) -> String:
	return ("+" if value >= 0.0 else "−") + String.num(snappedf(absf(value), 0.1), 1).replace(".", ",")

## Seçili grubun ayrıntısı: talepler, sorun, gerçek kurallarla hesaplanan
## beklenen etkiler (kabul / ret), kapsam, kabul koşulu ve SUN düğmesi.
func _refresh_law_detail() -> void:
	if _law_detail == null:
		return
	for child in _law_detail.get_children():
		child.queue_free()
	if _law_group == "":
		return
	var me := multiplayer.get_unique_id()
	var law_type := CardPresets.law_type(_law_group)
	var law := CardPresets.law_data(law_type)
	var groups := PartyManager.groups_of(CardManager.party_of(me))
	var opposite := String(law["opposite"])
	var backlash := float(VoterGroups.data(_law_group).get("law_backlash", 0.4))
	var mult := PoliticianPresets.ACADEMIC_LAW_MULT if PoliticianPresets.has_background(me, "akademisyen") else 1.0
	if CardManager.crisis_group() == _law_group:
		mult *= PublicOpinion.AGENDA_LAW_MULT
	_law_detail.add_child(VoterGroupUI.name_row(_law_group, "", UiTheme.TEXT, 13, 20.0))
	var title := PopupKit.label(String(law["title"]), 12, UiTheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(300, 0)
	_law_detail.add_child(title)
	_law_detail.add_child(PopupKit.note(L.t("Sorun: %s. Talepler: %s.") % [law["problem"], VoterGroups.issues_text(_law_group)], UiTheme.TEXT_MUTED, 300))
	# Etki tablosu: her grup tek satır, "kabul / ret" (kalıcı, ulusal; gerçek kuralla).
	var passed := PublicOpinion.LAW_GROUP_GAIN_PASSED * mult
	var rejected := PublicOpinion.LAW_GROUP_GAIN_REJECTED * mult
	_law_detail.add_child(PopupKit.note(L.t("Kalıcı etki (kabul edilirse / edilmezse):"), UiTheme.TEXT, 300))
	_law_detail.add_child(VoterGroupUI.name_row(_law_group, "%s / %s" % [EffectWords.adjective(VoterGroups.effective_delta(groups, _law_group, passed), "group"),
		EffectWords.adjective(VoterGroups.effective_delta(groups, _law_group, rejected), "group")], UiTheme.GREEN, VoterGroupUI.FS_NAME, 16.0, true))
	_law_detail.add_child(VoterGroupUI.name_row(opposite, L.t("%s / %s kayıp") % [EffectWords.adjective(VoterGroups.effective_delta(groups, opposite, -passed * backlash), "group"),
		EffectWords.adjective(VoterGroups.effective_delta(groups, opposite, -rejected * backlash), "group")], UiTheme.RED, VoterGroupUI.FS_NAME, 16.0, true))
	var crisis_note := L.t(" Gündemde: etki daha güçlü, ulusal destek de kazandırır.") if CardManager.crisis_group() == _law_group else ""
	_law_detail.add_child(PopupKit.note(L.t("Meclis çoğunluğu gerekir.%s") % crisis_note, UiTheme.TEXT_DIM, 300))
	var submit := Button.new()
	submit.focus_mode = Control.FOCUS_NONE
	submit.custom_minimum_size = Vector2(0, 32)
	submit.text = L.t("TEKLİFİ SUN · %s") % GameRules.cost_text(CardManager.law_funds_cost(me, law_type))
	UiSkin.skin_color_button(submit, UiTheme.GREEN_DARK)
	submit.disabled = not CardManager.can_propose_law(me, law_type)
	submit.pressed.connect(func(): _propose_law_clicked(law_type))
	_law_detail.add_child(submit)

## Eksen ucuna TIKLAMAK yasayı doğrudan meclise sunar (sürükleme yok).
func _propose_law_clicked(law_type: String) -> void:
	if not CardManager.can_propose_law(multiplayer.get_unique_id(), law_type):
		_show_toast(_action_block_reason(CardManager.law_funds_cost(multiplayer.get_unique_id(), law_type), true))
		return
	_law_designer.hide()
	CardManager.propose_law(law_type)

# --- Ekonomi ve vergi ---------------------------------------------------------

func _refresh_economy() -> void:
	if _economy_panel != null:
		_economy_panel.refresh()
	if _tax_panel != null and _tax_panel.visible:
		_fill_tax_panel()

## Para hareketi / vergi değişikliği: ekonomi kutusu animasyonu oynatır; vergi
## değişince açık vergi paneli yeni duruma göre yenilenir.
func _on_economy_event(data: Dictionary) -> void:
	if _economy_panel != null:
		_economy_panel.play_event(data)
	if String(data.get("kind", "")) == "tax":
		_tax_selected = -1
		_refresh_economy()

## Yatırım önizlemesi (onaydan önce): bedel ve kaynağı, hazinenin önce/sonra
## bakiyesi, etkinin zamanlaması.
func _invest_preview(pname: String) -> String:
	var before := CardManager.state_treasury()
	return L.t("%s yatırımı · devlet hazinesi %s → %s milyon ₺\nGüçlü yerel etki: yarısı hemen, kalanı %d dönemde · ekonomi canlanır") % [
		pname, Economy.money_text(before), Economy.money_text(before - Economy.INVEST_COST), Economy.INVEST_DELAY_ROUNDS]

static func _one_decimal(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 1).replace(".", ",")

func _build_tax_panel() -> void:
	_tax_panel = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	_tax_panel.add_theme_stylebox_override("panel", style)
	_tax_panel.z_index = 108
	_tax_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_tax_box = VBoxContainer.new()
	_tax_box.add_theme_constant_override("separation", 6)
	_tax_box.custom_minimum_size = Vector2(404, 0)
	_tax_panel.add_child(_tax_box)
	_tax_panel.hide()
	add_child(_tax_panel)

## VERGİ POLİTİKASI: ekonomi şeridine ya da yasa panelindeki bağlantıya
## dokununca açılır (tekrar dokununca kapanır).
func _open_tax_panel() -> void:
	if _tax_panel.visible:
		_tax_panel.hide()
		return
	_deselect_hand_card()
	_law_designer.hide()
	_cancel_targeting()
	_tax_selected = -1
	_fill_tax_panel()
	_tax_panel.show()
	_place_tax_panel.call_deferred()

func _fill_tax_panel() -> void:
	EconomyPanel.fill_policy(_tax_box, multiplayer.get_unique_id(), _tax_selected, _on_tax_selected, _propose_tax, _tax_panel.hide)

func _on_tax_selected(level: int) -> void:
	_tax_selected = level
	_fill_tax_panel()
	_place_tax_panel.call_deferred()

func _place_tax_panel() -> void:
	if _tax_panel == null or not _tax_panel.visible:
		return
	_tax_panel.reset_size()
	var viewport_size := get_viewport_rect().size
	_tax_panel.position = Vector2(
		viewport_size.x - RIGHT_COLUMN_WIDTH - _tax_panel.size.x - 12.0,
		clampf(_top_area_height() - _tax_panel.size.y, 12.0, maxf(12.0, viewport_size.y - _tax_panel.size.y - 12.0)))

func _propose_tax(law_type: String) -> void:
	var me := multiplayer.get_unique_id()
	if not CardManager.can_propose_law(me, law_type):
		_show_toast(CardManager.tax_law_block_reason(me, CardPresets.tax_law_level(law_type)))
		return
	_tax_panel.hide()
	_law_designer.hide()
	CardManager.propose_law(law_type)

# --- Finansman paylaşımı ve soruşturma ----------------------------------------

func _build_funding_ui() -> void:
	_funding_panel = FundingPanel.new()
	_funding_panel.hide()
	_funding_panel.confirmed.connect(_on_funding_confirmed)
	_funding_panel.cancelled.connect(_cancel_targeting)
	add_child(_funding_panel)
	_aid_panel = AidPanel.new()
	_aid_panel.hide()
	_aid_panel.confirmed.connect(_on_aid_confirmed)
	_aid_panel.cancelled.connect(func(): _aid_panel.hide())
	add_child(_aid_panel)
	_inquiry_panel = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	_inquiry_panel.add_theme_stylebox_override("panel", style)
	_inquiry_panel.z_index = 108
	_inquiry_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inquiry_box = VBoxContainer.new()
	_inquiry_box.add_theme_constant_override("separation", 5)
	_inquiry_box.custom_minimum_size = Vector2(404, 0)
	_inquiry_panel.add_child(_inquiry_box)
	_inquiry_panel.hide()
	add_child(_inquiry_panel)

## Hükümetteki parti mitingini devlet parasıyla da yapabilir: seçim varsa panel açılır.
func _miting_has_choice() -> bool:
	return bool(CardManager.funding_range(multiplayer.get_unique_id(), "miting")["state_allowed"])

func _open_funding(province_id: String) -> void:
	_funding_panel.open(multiplayer.get_unique_id(), "invest" if _pending_invest else "miting", province_id)
	_place_funding_panel.call_deferred()

## Haritanın alt kenarına ortalı; haritanın dışına taşmaz.
func _place_funding_panel() -> void:
	if not _funding_panel.visible:
		return
	_funding_panel.reset_size()
	var map := _r(R_MAP)
	var panel_size := _funding_panel.size
	_funding_panel.position = Vector2(map.position.x + (map.size.x - panel_size.x) * 0.5,
		maxf(map.position.y + 40.0, map.end.y - panel_size.y - 8.0))

func _on_funding_confirmed(share: float) -> void:
	var me := multiplayer.get_unique_id()
	var province_id := _selected_province
	var investing := _pending_invest
	_cancel_targeting()
	if province_id == "":
		return
	if investing:
		if CardManager.can_invest(me, province_id, share):
			CardManager.invest(province_id, share)
		else:
			_show_toast(CardManager.funding_block_reason(me, "invest", share) if CardManager.can_invest(me, province_id) else _invest_block_reason())
	else:
		if CardManager.can_miting(me, province_id, share):
			CardManager.miting(province_id, share)
		else:
			_show_toast(CardManager.funding_block_reason(me, "miting", share))

## SORUŞTURMA hamlesi: önce hedef parti seçilir, sonra soruşturma paneli açılır.
func _on_inquiry_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if _inquiry_picker != null and is_instance_valid(_inquiry_picker):
		_inquiry_picker.queue_free()
		_inquiry_picker = null
		return
	var reason := CardManager.inquiry_block_reason(me)
	if reason != "":
		_show_toast(reason)
		return
	_law_designer.hide()
	_cancel_targeting()
	_inquiry_panel.hide()
	_inquiry_picker = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	_inquiry_picker.add_theme_stylebox_override("panel", style)
	_inquiry_picker.z_index = 108
	_inquiry_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	_inquiry_picker.add_child(box)
	box.add_child(UiTheme.mono_label(L.t("SORUŞTURMA: HEDEF PARTİ"), 14, UiTheme.TEXT, true))
	box.add_child(PopupKit.note(L.t("Harcamaları incelenecek partiyi seç (kendi partin de olabilir: bağımsız denetim)."), UiTheme.TEXT_DIM, 300))
	for pid in CardManager.party_ids():
		if PartyManager.is_independent(int(pid)):
			continue
		var party: Dictionary = PartyManager.data_of(int(pid))
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(300, 32)
		button.text = "%s · %d" % [String(party.get("name", "?")), CardManager.inquiry_records(int(pid)).size()]
		button.tooltip_text = L.t("İncelenebilecek işlem sayısı: %d") % CardManager.inquiry_records(int(pid)).size()
		UiSkin.skin_color_button(button, Color(party.get("bg_color", UiTheme.PANEL_DARK)).darkened(0.35))
		var target := int(pid)
		button.pressed.connect(func():
			if _inquiry_picker != null and is_instance_valid(_inquiry_picker):
				_inquiry_picker.queue_free()
				_inquiry_picker = null
			_open_inquiry_panel(target))
		box.add_child(button)
	var close := Button.new()
	close.text = L.t("Kapat")
	UiSkin.skin_button(close)
	close.pressed.connect(func():
		if _inquiry_picker != null and is_instance_valid(_inquiry_picker):
			_inquiry_picker.queue_free()
			_inquiry_picker = null)
	box.add_child(close)
	add_child(_inquiry_picker)
	_place_inquiry_picker.call_deferred()

func _place_inquiry_picker() -> void:
	if _inquiry_picker == null or not is_instance_valid(_inquiry_picker):
		return
	_inquiry_picker.reset_size()
	var map := _r(R_MAP)
	_inquiry_picker.position = Vector2(map.position.x + (map.size.x - _inquiry_picker.size.x) * 0.5,
		maxf(map.position.y + 40.0, map.end.y - _inquiry_picker.size.y - 8.0))

func _open_inquiry_panel(target: int) -> void:
	_inquiry_target = CardManager.party_of(target)
	_law_designer.hide()
	_tax_panel.hide()
	_cancel_targeting()
	_fill_inquiry_panel()
	_inquiry_panel.show()
	_place_inquiry_panel.call_deferred()

func _fill_inquiry_panel() -> void:
	EconomyPanel.fill_inquiry(_inquiry_box, multiplayer.get_unique_id(), _inquiry_target, _on_inquiry_open, _inquiry_panel.hide)

func _place_inquiry_panel() -> void:
	_inquiry_panel.reset_size()
	var viewport_size := get_viewport_rect().size
	_inquiry_panel.position = Vector2(viewport_size.x - RIGHT_COLUMN_WIDTH - _inquiry_panel.size.x - 12.0,
		clampf(_top_area_height() - _inquiry_panel.size.y, 12.0, maxf(12.0, viewport_size.y - _inquiry_panel.size.y - 12.0)))

func _on_inquiry_open(target: int) -> void:
	var me := multiplayer.get_unique_id()
	if not CardManager.can_open_inquiry(me, target):
		_show_toast(CardManager.inquiry_block_reason(me, target))
		return
	_inquiry_panel.hide()
	CardManager.open_inquiry(target)

## SONUÇ KARTI: haritanın üstünde ortada belirir, birkaç saniye kalır (dokununca
## kapanır). Ton etiketle (✓ ŞEFFAF / ! USULSÜZLÜK / — KANIT YOK) ve renkle.
func _show_inquiry_result(data: Dictionary) -> void:
	if _inquiry_card != null and is_instance_valid(_inquiry_card):
		_inquiry_card.queue_free()
	if _inquiry_panel != null and _inquiry_panel.visible:
		_fill_inquiry_panel()
	var card := EconomyPanel.inquiry_result_card(data)
	card.z_index = 109
	add_child(card)
	_inquiry_card = card
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and is_instance_valid(card):
			card.queue_free())
	card.reset_size()
	var map := _r(R_MAP)
	var target := Vector2(map.position.x + (map.size.x - card.size.x) * 0.5, map.position.y + 46.0)
	card.position = target + Vector2(0, -16)
	card.modulate.a = 0.0
	var tween := card.create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position", target, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate:a", 1.0, 0.2)
	tween.chain().tween_interval(6.0)
	tween.chain().tween_property(card, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(card.queue_free)

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
	var law_me := multiplayer.get_unique_id()
	if not _law_designer.visible and not CardManager.can_propose_law(law_me) and not CardManager.can_propose_constitution(law_me):
		_show_toast(_action_block_reason(GameRules.LAW_FUNDS_COST, true) + L.t(" (Panel yine de açılır: yasaları incele.)"))
	if _law_designer.visible:
		_law_designer.hide()
		return
	if _tax_panel != null:
		_tax_panel.hide()
	_law_tax_selected = -1
	_refresh_law_designer()
	_law_designer.show()
	_place_law_designer()

func _place_law_designer() -> void:
	_law_designer.reset_size()
	await get_tree().process_frame
	_law_designer.reset_size()
	var viewport_size := get_viewport_rect().size
	_law_designer.position = Vector2(
		viewport_size.x - RIGHT_COLUMN_WIDTH - _law_designer.size.x - 12.0,
		maxf(12.0, _top_area_height() - _law_designer.size.y))

# --- AFET (0.0.181) --------------------------------------------------------------

## Haritadaki afet işareti ve açık yardım paneli güncel durumla eşlenir.
func _refresh_disaster() -> void:
	var active := CardManager.active_disaster()
	if map_holder != null and map_holder.has_method("set_disaster"):
		map_holder.set_disaster(active.get("provinces", []), String(active.get("kind", "")))
	if _aid_panel != null and _aid_panel.visible:
		if active.is_empty() or not CardManager.can_choose_main_action(multiplayer.get_unique_id()):
			_aid_panel.hide()

func _on_aid_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if _aid_panel.visible:
		_aid_panel.hide()
		return
	_deselect_hand_card()
	_law_designer.hide()
	_cancel_targeting()
	var reason := CardManager.aid_block_reason(me)
	if reason != "":
		_show_toast(reason)
		return
	_aid_panel.open(me)
	_place_aid_panel.call_deferred()

func _place_aid_panel() -> void:
	if not _aid_panel.visible:
		return
	_aid_panel.reset_size()
	var map := _r(R_MAP)
	var panel_size := _aid_panel.size
	_aid_panel.position = Vector2(map.position.x + (map.size.x - panel_size.x) * 0.5,
		maxf(map.position.y + 40.0, map.end.y - panel_size.y - 8.0))

func _on_aid_confirmed(party_m: float, state_m: float) -> void:
	var me := multiplayer.get_unique_id()
	var reason := CardManager.aid_block_reason(me, party_m, state_m)
	_aid_panel.hide()
	if reason != "":
		_show_toast(reason)
		return
	CardManager.aid(party_m, state_m)

## Afetin gazetesi (tur başında; seçim gecesinden dönünce de bir kez).
func _headline_for_disaster(info: Dictionary) -> void:
	if not is_inside_tree() or info.is_empty() or _event_fx == null:
		return
	var kind := String(info.get("kind", ""))
	var provinces: Array = info.get("provinces", [])
	var names: Array = []
	for province_id in provinces:
		names.append(ElectionNightSim.province_name(String(province_id)))
	_event_fx.present("ds|%d" % int(info.get("id", 0)), {
		"headline": Disaster.headline(kind, provinces.size()),
		"subtitle": L.t("%s: %s. Partiler bu tur bölgeye yardım götürebilir.") % [Disaster.title(kind), ", ".join(PackedStringArray(names))],
		"art": Disaster.art(kind), "accent": Disaster.color(kind), "style": "scandal",
		"status": L.t("AFET BÖLGESİ"), "sound": "paper_slap"})

func _invest_block_reason() -> String:
	if CardManager.can_act() and not CardManager.is_government_party(multiplayer.get_unique_id()):
		return L.t("Yatırımı sadece hükümet partileri yapabilir.")
	if CardManager.can_act() and not CardManager.can_invest(multiplayer.get_unique_id()):
		return L.t("Yatırım ödenemiyor: hazinede %s, kasanda %s; ikisi birlikte %s etmeli.") % [
			Economy.money_full(CardManager.state_treasury()), GameRules.cost_text(CardManager.funds_of(multiplayer.get_unique_id())),
			Economy.money_full(Economy.INVEST_COST)]
	return _action_block_reason(0)

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
	_set_target_hint(L.t("Yatırım (%s, parti kasası ve devlet hazinesi arasında bölünebilir): haritada bir ile dokun  ·  Butona tekrar dokun: iptal") %
		Economy.money_full(Economy.INVEST_COST))

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
			_show_toast(L.t("Sıran değil."))
		elif not GovernmentManager.has_government():
			_show_toast(L.t("Görevde bir hükümet yok."))
		elif not CardManager.has_seats(me):
			_show_toast(L.t("Mecliste vekilin yok: gensoru veremezsin."))
		elif CardManager.is_government_party(me):
			_show_toast(L.t("Hükümetteki parti gensoru veremez."))
		elif GovernmentManager.has_majority():
			_show_toast(L.t("Gensoru sadece hükümet azınlıktayken verilebilir (salt çoğunluğu yok)."))
		else:
			_show_toast(_action_block_reason(GameRules.CENSURE_FUNDS_COST))
		return
	_pending_censure = true
	_refresh_action_buttons()
	_set_target_hint(L.t("Gensoru: hükümeti düşürmek için meclis oylaması (%s). Reddedilirse küçük bir itibar kaybı. Onay: butona tekrar dokun") % GameRules.cost_text(GameRules.CENSURE_FUNDS_COST))

## Erken seçim hamlesi: ilk dokunuş onay ister, ikincisi önergeyi meclise getirir.
## Kongre hamlesi: ilk dokunuş açıklama ve onay, ikincisi kongreyi başlatır.
func _on_congress_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if _pending_congress:
		_pending_congress = false
		_cancel_targeting()
		if CardManager.can_call_congress(me):
			CardManager.request_congress()
		_refresh_action_buttons()
		return
	_deselect_hand_card()
	_law_designer.hide()
	_cancel_targeting()
	if PartyManager.is_independent(me):
		_show_toast(L.t("Bağımsızsın: kongre yok. Önce parti kur."))
		return
	if not CardManager.can_call_congress(me):
		_show_toast(CardManager.congress_block_reason(me))
		return
	_pending_congress = true
	_refresh_action_buttons()
	var pid := CardManager.party_of(me)
	if CardManager.is_party_member(me):
		_set_target_hint(L.t("Kongre iste (%s): genel başkanlığa aday olursun; parti oy kaybettiği için şansın var. Onay: butona tekrar dokun") % GameRules.cost_text(CardManager.CONGRESS_REQUEST_COST))
	else:
		_set_target_hint(L.t("Kongreye git (%s): partideki gücün %s; ne kadar güçlüysen o kadar az rakip çıkar. Onay: butona tekrar dokun") % [
			GameRules.cost_text(CardManager.CONGRESS_COST), EffectWords.strength(CardManager.congress_strength(pid))])

func _on_early_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if _pending_early:
		_pending_early = false
		_cancel_targeting()
		if CardManager.can_early_election(me):
			CardManager.early_election()
		_refresh_action_buttons()
		return
	_deselect_hand_card()
	_law_designer.hide()
	_cancel_targeting()
	if not CardManager.can_early_election(me):
		if not CardManager.can_act():
			_show_toast(L.t("Sıran değil."))
		elif not CardManager.has_seats(me):
			_show_toast(L.t("Mecliste vekilin yok: erken seçim önergesi veremezsin."))
		elif CardManager.early_election_pending:
			_show_toast(L.t("Erken seçim kararı zaten alındı."))
		elif CardManager.election_this_round():
			_show_toast(L.t("Seçim zaten bu turun sonunda: erken seçim önergesine gerek yok."))
		elif CardManager.early_request_used(me):
			_show_toast(L.t("Partin bu seçim döneminde zaten erken seçim önergesi verdi."))
		elif not GovernmentManager.can_submit_law():
			_show_toast(L.t("Meclis şu an meşgul (oylama ya da hükümet kurma sürüyor)."))
		else:
			_show_toast(_action_block_reason(GameRules.EARLY_ELECTION_FUNDS_COST))
		return
	_pending_early = true
	_refresh_action_buttons()
	_set_target_hint(L.t("Erken seçim: meclis oylaması (%s). Kabul edilirse dönem sonunda sandığa gidilir. Onay: butona tekrar dokun") % GameRules.cost_text(GameRules.EARLY_ELECTION_FUNDS_COST))

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
		_show_toast(_action_block_reason(GameRules.MITING_FUNDS_COST))
		return
	_pending_miting = true
	if _province_panel != null:
		_province_panel.hide()
	_refresh_action_buttons()
	_set_target_hint(L.t("Miting: haritada bir ile dokun, tekrar dokun: miting yap (%s)  ·  Butona tekrar dokun: iptal") % GameRules.cost_text(GameRules.MITING_FUNDS_COST))

# --- Harita katmanları ---------------------------------------------------------

func _ensure_map_clip() -> void:
	if _map_clip != null:
		return
	_map_clip = Control.new()
	_map_clip.name = L.t("MapClip")
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
	# Seçmen katmanı: 8 grup simgesi (katman açıkken düğmelerin altında).
	_group_picker = HBoxContainer.new()
	_group_picker.add_theme_constant_override("separation", 2)
	_group_picker.z_index = 6
	add_child(_group_picker)
	for group in VoterGroups.GROUP_IDS:
		# Hap düğme: madalyon + (seçiliyse) grubun tam adı.
		var pick := Button.new()
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(44, 44)
		pick.tooltip_text = VoterGroups.title(group)
		var icon := VoterGroupIcon.make(group, 38.0)
		icon.position = Vector2(3, 3)
		icon.size = Vector2(38, 38)
		pick.add_child(icon)
		var name_label := Label.new()
		name_label.name = L.t("Title")
		name_label.text = VoterGroups.title(group)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		name_label.add_theme_constant_override("outline_size", 3)
		name_label.position = Vector2(46, 0)
		name_label.size = Vector2(0, 44)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pick.add_child(name_label)
		pick.set_meta("group", group)
		pick.pressed.connect(func():
			_map_group = group
			_refresh_layer_bar()
			_apply_map_layer_colors())
		_group_picker.add_child(pick)
	_refresh_layer_bar()

func _place_layer_bar() -> void:
	if _layer_bar == null:
		return
	_layer_bar.reset_size()
	var rect := _r(R_MAP)
	# Harita alanının sol üst köşesinde (maketteki sekmeler gibi).
	_layer_bar.position = rect.position + Vector2(8.0, 8.0)
	_layer_bar.z_index = 6
	_layer_legend.reset_size()
	# Gösterge düğmelerin sağında, aynı satırda ortalı.
	_layer_legend.position = Vector2(_layer_bar.position.x + _layer_bar.size.x + 12.0,
		_layer_bar.position.y + _layer_bar.size.y * 0.5 - _layer_legend.size.y * 0.5)
	if _group_picker != null:
		_group_picker.reset_size()
		_group_picker.position = _layer_bar.position + Vector2(0.0, _layer_bar.size.y + 4.0)
		# Gösterge (grup adı + ölçek) seçicinin sağına, ikinci satıra iner.
		if _map_layer == MapLayer.GROUPS:
			_layer_legend.position = Vector2(_group_picker.position.x + _group_picker.size.x + 10.0,
				_group_picker.position.y + _group_picker.size.y * 0.5 - _layer_legend.size.y * 0.5)

## Harita katman düğmesi (Vekiller / Teşkilat / Güç). Köşe yarıçapı yok:
## pixel tarzda hepsi kare, seçili olan altın.
func _layer_button_style(color: Color, _left: bool, _right: bool) -> StyleBoxTexture:
	var style := UiSkin.color_box(color, UiSkin.BUTTON_TINT_NORMAL)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _refresh_layer_bar() -> void:
	for i in _layer_buttons.size():
		var button: Button = _layer_buttons[i]
		var active := i == _map_layer
		var color := UiTheme.GOLD if active else UiTheme.PANEL
		var first := i == 0
		var last := i == _layer_buttons.size() - 1
		for state in ["normal", "hover", "pressed", "focus"]:
			var c := color.lightened(0.08) if state == "hover" and not active else color
			button.add_theme_stylebox_override(state, _layer_button_style(c, first, last))
		button.add_theme_color_override("font_color", UiTheme.INK if active else UiTheme.TEXT)
		button.add_theme_color_override("font_hover_color", UiTheme.INK if active else UiTheme.TEXT)
		button.add_theme_color_override("font_pressed_color", UiTheme.INK)
	if _group_picker != null:
		_group_picker.visible = _map_layer == MapLayer.GROUPS
		for pick in _group_picker.get_children():
			var group := String(pick.get_meta("group"))
			var selected := group == _map_group
			var color := VoterGroups.color(group)
			var title: Label = pick.get_node("Title")
			title.visible = selected
			var width := 44.0
			if selected:
				width = 46.0 + title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
			(pick as Button).custom_minimum_size = Vector2(width, 44)
			(pick as Button).size = Vector2(width, 44)
			for state in ["normal", "hover", "pressed", "focus"]:
				var pill := StyleBoxFlat.new()
				pill.set_corner_radius_all(0)
				pill.anti_aliasing = true
				if selected:
					pill.bg_color = color.darkened(0.1)
					pill.border_color = color.lightened(0.25)
				else:
					pill.bg_color = Color("#222a38") if state != "hover" else Color("#2c3648")
					pill.border_color = Color(color, 0.0 if state != "hover" else 0.6)
				pill.set_border_width_all(1)
				(pick as Button).add_theme_stylebox_override(state, pill)
	_rebuild_layer_legend()

## Katmanın küçük açıklaması (renk anahtarı), butonların hemen üstünde.
func _rebuild_layer_legend() -> void:
	for child in _layer_legend.get_children():
		child.queue_free()
	var mine: Color = PartyManager.data_of(multiplayer.get_unique_id()).get("bg_color", Color(0.5, 0.5, 0.5))
	var swatches: Array = []
	match _map_layer:
		MapLayer.ORGANIZATION:
			for level in GameRules.ORG_MAX_LEVEL + 1:
				swatches.append([MAP_BLANK_COLOR.lerp(mine, float(level) / GameRules.ORG_MAX_LEVEL), str(level)])
			swatches.append([null, L.t("teşkilat seviyem")])
		MapLayer.STRENGTH:
			swatches.append([null, L.t("vekil yok")])
			for i in STRENGTH_STOPS.size():
				swatches.append([STRENGTH_STOPS[i], ""])
			swatches.append([null, L.t("ilin yarısı")])
		MapLayer.GROUPS:
			var span := _group_layer_span()
			swatches.append([null, L.t("%%%d") % int(span.x)])
			for i in 4:
				swatches.append([MAP_BLANK_COLOR.lerp(_group_layer_color(), float(i) / 3.0), ""])
			swatches.append([null, L.t("%%%d") % int(span.y)])
	_layer_legend.visible = not swatches.is_empty()
	for entry in swatches:
		if entry[0] == null:
			var label := Label.new()
			label.text = String(entry[1])
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_outline_color", UiTheme.INK)
			label.add_theme_constant_override("outline_size", 4)
			_layer_legend.add_child(label)
			continue
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(maxf(22.0, 8.0 + 7.0 * String(entry[1]).length()), 16)
		swatch.add_theme_stylebox_override("panel", UiSkin.color_box(entry[0], UiSkin.BUTTON_TINT_NORMAL))
		if String(entry[1]) != "":
			var num := Label.new()
			num.text = String(entry[1])
			num.set_anchors_preset(Control.PRESET_FULL_RECT)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			num.add_theme_font_size_override("font_size", 11)
			num.add_theme_color_override("font_color", UiTheme.INK if (entry[0] as Color).get_luminance() > 0.5 else UiTheme.TEXT)
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
	var mine: Color = PartyManager.data_of(me).get("bg_color", Color(0.5, 0.5, 0.5))
	mine.a = 1.0
	var colors := {}
	map_holder.set_dark_borders(_map_layer == MapLayer.ORGANIZATION)
	if _map_layer == MapLayer.SEATS:
		colors = _seat_layer_colors.duplicate()
	else:
		# GÜÇ: her ilde, teşkilattan bağımsız, KESİN tahmin (şimdi seçim olsa).
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		gradient.colors = PackedColorArray(STRENGTH_STOPS)
		var projection: Dictionary = CardManager.projection_all() if _map_layer == MapLayer.STRENGTH else {}
		var span := _group_layer_span()
		for province_id in map_holder.get_all_province_ids():
			match _map_layer:
				MapLayer.GROUPS:
					var pct := float(VoterGroups.percent(CardManager.province_profile(province_id), _map_group))
					var t := clampf((pct - span.x) / maxf(1.0, span.y - span.x), 0.0, 1.0)
					colors[province_id] = MAP_BLANK_COLOR.lerp(_group_layer_color(), t)
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

## Seçmen katmanının en yoğun ucu: grubun rengi, biraz koyu (soluk illerden belirgin ayrılsın).
func _group_layer_color() -> Color:
	return VoterGroups.color(_map_group).darkened(0.25)

## Seçmen katmanında seçili grubun illerdeki en düşük ve en yüksek yüzdesi
## (renk ölçeği bu aralığa yayılır, gösterge de bu sayıları yazar).
func _group_layer_span() -> Vector2:
	var low := 100.0
	var high := 0.0
	for province_id in CardManager.province_voters().keys():
		var pct := float(VoterGroups.percent(CardManager.province_profile(province_id), _map_group))
		low = minf(low, pct)
		high = maxf(high, pct)
	if high < low:
		return Vector2(0, 100)
	return Vector2(low, high)

## Güç katmanı: TÜM partilerin gücüyle, şimdi seçim olsa bu ilde durumum.
## −1 (koyu kırmızı) .. +1 (koyu yeşil). Vekil çıkaramıyorsam en fazla sarıya
## yakın turuncu (bir vekile ne kadar yakın olduğuma göre); vekil çıkarıyorsam
## sarı yeşilden, ilin vekillerinin yarısını alıyorsam koyu yeşile.
func _strength_t(entry: Dictionary, me: int) -> float:
	me = CardManager.party_of(me)
	if entry.is_empty() or not entry.has(me):
		return -1.0
	var mine: Dictionary = entry[me]
	var seat_count := maxi(1, int(entry.get("seat_count", 1)))
	var won := int(mine["seats"])
	var quotient := float(mine["quotient"])
	# Sürekli ölçü: oy / son kazanan bölüm ≈ "kesirli vekil": her hamle rengi kaydırır.
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

## Teşkilatlanma: harita anında teşkilat katmanına geçer, il seçilir. Butona
## tekrar basmak iptal eder (para harcanmaz). Harita teşkilat katmanında KALIR.
func _on_org_button_pressed() -> void:
	if _pending_org:
		_cancel_targeting()
		return
	var me := multiplayer.get_unique_id()
	_deselect_hand_card()
	_law_designer.hide()
	if _pending_miting or _pending_invest or _pending_censure or _pending_province_hand_index != -1:
		_cancel_targeting()
	if not CardManager.can_choose_main_action(me) or CardManager.funds_of(me) < CardManager.org_cost_for(me):
		_show_toast(_action_block_reason(CardManager.org_cost_for(me)))
		return
	_pending_org = true
	if _province_panel != null:
		_province_panel.hide()
	_begin_org_view()
	_refresh_action_buttons()
	_set_target_hint(L.t("Teşkilatlanma: bir ile dokun, tekrar dokun: kur ya da geliştir (%s)  ·  Butona tekrar dokun: iptal") % GameRules.cost_text(CardManager.org_cost_for(me)))

## Teşkilat seviyesinin getirdikleri (kısa).
static func _org_level_text(level: int) -> String:
	match level:
		1:
			return L.t("az oy bonusu, yaklaşık oy")
		2:
			return L.t("yüksek oy bonusu, %90 doğru oy")
		3:
			return L.t("yüksek oy bonusu, yüksek isabetli anket")
	return ""

# --- Grup toplantısı -----------------------------------------------------------------

## GRUP TOPLANTISI paneli (TOPLANTI düğmesiyle açılır): haritanın üst
## kenarında 8 seçmen grubu (4 × 2). Bir gruba basınca toplantı yapılır.
func _build_speech_panel() -> void:
	_speech_panel = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_S)
	_speech_panel.add_theme_stylebox_override("panel", style)
	_speech_panel.z_index = 109
	_speech_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_speech_panel.add_child(box)
	var title := Label.new()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	title.text = L.t("GRUP TOPLANTISI · bir seçmen grubunun sorunlarını gündeme getir")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	header.add_child(title)
	# Kapat: şerit gizlenir; hamle düğmesiyle yeniden açılır.
	var skip := Button.new()
	skip.text = L.t("Kapat")
	skip.tooltip_text = L.t("Toplantıyı kapat (TOPLANTI düğmesiyle yeniden açılır).")
	skip.add_theme_font_size_override("font_size", 11)
	UiSkin.skin_button(skip)
	skip.pressed.connect(func():
		_speech_open_key = ""
		_speech_panel.hide())
	header.add_child(skip)
	_speech_note = Label.new()
	_speech_note.add_theme_font_size_override("font_size", 10)
	_speech_note.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	box.add_child(_speech_note)
	_speech_rows = GridContainer.new()
	_speech_rows.columns = 4
	_speech_rows.add_theme_constant_override("h_separation", 4)
	_speech_rows.add_theme_constant_override("v_separation", 4)
	box.add_child(_speech_rows)
	_speech_panel.hide()
	add_child(_speech_panel)

func _on_speech_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if not CardManager.can_act():
		_show_toast(L.t("Sıran değil."))
		return
	if not CardManager.needs_speech(me):
		_show_toast(L.t("Partin bu dönem grup toplantısını zaten yaptı."))
		return
	var key := "%d:%d" % [CardManager.round_number, CardManager.current_turn_index]
	_speech_open_key = "" if _speech_open_key == key else key
	_refresh_speech_panel()

func _refresh_speech_panel() -> void:
	if _speech_panel == null:
		return
	var me := multiplayer.get_unique_id()
	var wanted := CardManager.needs_speech(me) and not CardManager.is_turn_blocked() and not CardManager.game_finished \
		and _speech_open_key == "%d:%d" % [CardManager.round_number, CardManager.current_turn_index]
	if not wanted:
		_speech_panel.hide()
		_speech_key = ""
		return
	var groups := CardManager.effective_groups(me)
	var key := "%d:%d:%s:%s" % [CardManager.round_number, CardManager.current_turn_index, str(groups), CardManager.crisis_group()]
	if key != _speech_key:
		_speech_key = key
		# Eski sütunlar HEMEN çıkarılır: queue_free kare sonuna kadar beklerken panel
		# eski + yeni sütunlarla (6 sütun) ölçülüp gereksiz genişliyordu.
		for child in _speech_rows.get_children():
			_speech_rows.remove_child(child)
			child.queue_free()
		_speech_note.text = _meeting_timing_text()
		for group in VoterGroups.GROUP_IDS:
			_speech_rows.add_child(_speech_row(group, float(groups.get(group, VoterGroups.AFFINITY_NEUTRAL))))
	if not _speech_panel.visible:
		_speech_panel.show()
		if _province_panel != null:
			_province_panel.hide()
		_law_designer.hide()
	_place_speech_panel.call_deferred()

func _place_speech_panel() -> void:
	if _speech_panel == null or not _speech_panel.visible:
		return
	_speech_panel.reset_size()
	var viewport_size := get_viewport_rect().size
	var left := LEFT_PANEL_WIDTH
	var right := viewport_size.x - RIGHT_COLUMN_WIDTH
	# Haritanın üst kenarı: harita görünür kalsın.
	_speech_panel.position = Vector2((left + right - _speech_panel.size.x) * 0.5, 8.0)

## Toplantının seçime göre zamanlaması: bonus seçimde ne kadar olur?
func _meeting_timing_text() -> String:
	var next := GameRules.next_election_round(CardManager.round_number)
	var bonus_text := L.t("Geçici destek: bu dönem %s, sonra hızla söner.") % EffectWords.adjective(PublicOpinion.MEETING_BONUS[0], "group")
	if next == -1:
		return bonus_text
	var age := next - CardManager.round_number
	var at_election := PublicOpinion.meeting_bonus(age)
	if at_election > 0.0:
		return bonus_text + L.t(" Seçimde hâlâ %s etkisi olur.") % EffectWords.adjective(at_election, "group")
	return bonus_text + L.t(" Seçime %d dönem var: seçime kadar söner.") % age

## Bir seçmen grubu düğmesi: simge + tam ad + partinin şu anki desteği.
## Gündem bu grubu istiyorsa altın not.
func _speech_row(group: String, value: float) -> Control:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(SPEECH_COLUMN_WIDTH, 38)
	button.clip_text = false
	UiSkin.skin_color_button(button, VoterGroups.color(group).darkened(0.4))
	var crisis := CardManager.crisis_group() == group
	button.tooltip_text = L.t("%s\nKonu: %s\nPartinin bu gruptaki desteği %s; toplantı bu dönem %s.%s") % [
		VoterGroups.title(group), String(VoterGroups.data(group).get("meeting", "")), VoterGroups.percent_text(value),
		EffectWords.change(PublicOpinion.MEETING_BONUS[0], "group"),
		L.t("\nGÜNDEMDE: toplantı ulusal destek de kazandırır.") if crisis else ""]
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -2
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon := VoterGroupIcon.make(group, 20.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var name := Label.new()
	name.text = VoterGroups.title(group)
	name.add_theme_font_size_override("font_size", 9)
	name.add_theme_color_override("font_color", UiTheme.TEXT)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name)
	var sub := Label.new()
	sub.text = L.t("destek %s%s") % [VoterGroups.percent_text(value), L.t(" · GÜNDEM") if crisis else ""]
	sub.add_theme_font_size_override("font_size", 9)
	sub.add_theme_color_override("font_color", UiTheme.GOLD if crisis else UiTheme.TEXT_MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(sub)
	button.pressed.connect(func():
		_speech_panel.hide()
		CardManager.make_speech(group))
	return button

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
	title.text = L.t("%s: kimi karalayacaksın?") % ElectionNightSim.province_name(province_id)
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	var me := multiplayer.get_unique_id()
	for peer_id in _ordered_peer_ids():
		if peer_id == me:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var badge := PartyBadge.build(PartyManager.data_of(peer_id), Vector2(34, 34), BADGE_ICON_PIXEL_SIZE)
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
	cancel.text = L.t("İptal")
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
