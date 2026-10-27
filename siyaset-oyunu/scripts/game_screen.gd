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
## SİMETRİ (0.0.250): bütün boşluklar 16 (kenarlar, sütunlar arası, bant ile
## paneller arası, paneller ile masa arası, masanın alt kenarı). Ekranda da
## eşit kalırlar: bkz. _r (boşluklar tek ölçekle, paneller kalan yeri doldurur).
const GAP := 16.0
## Boşluğun ekrandaki boyu (tasarım birimi): 0.0.251'de 16'dan 12'ye; kazanılan
## yeri paneller (en çok harita) alır.
const GAP_SCREEN := 12.0
## 0.0.265: paneller karton kalınlığı kadar (≈6) kısa; görünen boşluk bandın
## altında ve masanın üstünde eşit kalır.
const R_BOARD := Rect2(16, 80, 272, 434)
const R_MAP := Rect2(304, 80, 672, 434)
const R_SIDE := Rect2(992, 80, 272, 434)
const R_DESK := Rect2(0, 536, 1280, 184)
const R_HAND := Rect2(16, 568, 504, 136)
## 0.0.232: kart bozdurma yok; Turu Bitir hamleler alanında, para sağda.
const R_ACTIONS := Rect2(536, 568, 560, 136)
## Alt kenar hamle düğmelerinin alt kenarıyla aynı (568 + 64 + 6 + 64).
const R_FUNDS := Rect2(1112, 568, 152, 134)
## Stüdyo masasındaki meclis yuvasının yüksekliği (oylamada büyür).
const PARL_SLOT_HEIGHT := 150.0
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
## Sekme yüksekliği (konsept: 44 px).
const PLAYER_TAB_HEIGHT := 44.0 / 1.5
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
const CARD_TITLE_SIZE := 10
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
const MAP_LAYER_TITLES := ["Vekil", "Teşkilat", "Güç", "Seçmen"]
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
## Anayasa paketi: oyuncunun seçtiği baraj ve seçim aralığı.
var _constitution_threshold: float = 0.0
var _constitution_interval: float = GameRules.DEFAULT_ELECTION_INTERVAL
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
## Sürükleme sırasında el yeniden kurulmak istendi mi (bırakınca kurulur).
## Para levhasının ilk konumu (yerleşimde R_FUNDS'a oturtulur).
const FUNDS_PLATE_LEFT := -(RIGHT_COLUMN_WIDTH - 16.0)
const FUNDS_PLATE_HEIGHT := 44.0
const FUNDS_PLATE_TOP := -(CARD_BAR_HEIGHT + 12.0) - FUNDS_PLATE_HEIGHT
const FUNDS_ICON_SIZE := 34.0
## Parlamento diyagramının köşesinde duran "teklifi veren parti" rozeti.
var _proposer_chip: PanelContainer
var _proposer_row: HBoxContainer
## Kart barının zemini (ekranın altındaki tam genişlik şeridi).
var _card_bar_panel: Control
var _funds_plate: PanelContainer
var _funds_box: HBoxContainer
var _funds_label: Label
## Hamle ızgarası: artık parlamento diyagramının SAĞINDAKİ panelde, iki
## sütunlu. Butonlar paneli paylaşır, bu yüzden asgari ölçü küçük tutulur.
## 5 sütun (0.0.181, YARDIM eklendi): (392 - 4 × 8) / 5.
const ACTION_BUTTON_WIDTH := 72.0
## HAMLE VE MECLİS DÜĞMESİ RENKLERİ (0.0.215): parti kurma ekranındaki paletten.
const ACTION_COLOR_MITING := Color("F2132A")    # kırmızı
const ACTION_COLOR_AID := Color("D93636")       # kırmızı (konsept)
const ACTION_COLOR_ORG := Color("2569CF")       # koyu mavi
const ACTION_COLOR_INVEST := Color("31C440")    # yeşil
const ACTION_COLOR_LAW := Color("7B4FD6")       # mor (konsept MECLİS)
const ACTION_COLOR_CENSURE := Color("A6325A")   # bordo
const ACTION_COLOR_EARLY := Color("F0A824")     # sarı-turuncu
const ACTION_COLOR_CONGRESS := Color("AB39DB")  # mor
const ACTION_COLOR_ALLIANCE := Color("F08A24")  # turuncu (konsept)
const ACTION_COLOR_PASS := UiTheme.TEAL         # deniz yeşili (konsept TURU BİTİR)
const VOTE_COLOR_YES := Color("31C440")         # yeşil
const VOTE_COLOR_ABSTAIN := Color("FAD028")     # sarı
const VOTE_COLOR_NO := Color("F2132A")          # kırmızı
const ACTION_BUTTON_HEIGHT := 64.0
const ACTION_BUTTON_GAP := 8
var _action_grid: GridContainer
## Hamle alanındaki düğmeler (İTTİFAK, YARDIM; testler ortak görünümü sınar).
var _action_tab_of: Dictionary = {}
## MECLİS akışının tek giriş düğmesi (0.0.231) ve tur akışı sunumları.
var _parl_button: Button
var _parl_pulse: Tween
var _turn_intro: TurnIntro
var _parliament_flow: ParliamentFlow
var _province_actions: ProvinceActions
## Miting hamlesi için il seçme modu.
var _pending_miting: bool = false
## MİTİNG ODAĞI (0.0.213): ildeki teşkilat seviyesi kadar grup seçilir.
var _miting_focus: Array = []
var _focus_panel: PanelContainer
var _focus_box: VBoxContainer
var _focus_province := ""
var _pending_early: bool = false
var _congress_button: Button
var _pending_congress: bool = false
## YARDIM (0.0.260, kongrenin yerinde): afet sürerken tur içinde istendiği kadar.
var _aid_button: Button
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
var _law_points_label: Label
## Haritanın sağ üstünde gündem bandı.
var _agenda_banner: PanelContainer
var _agenda_label: Label
## EKONOMİ: sağ sütundaki özet (Hükümet sekmesi) ve Vergi Politikası paneli.
var _economy_panel: EconomyPanel
var _tax_panel: PanelContainer
var _tax_box: VBoxContainer
var _tax_selected: int = -1
## AFET YARDIMI paneli (YARDIM hamlesi).
var _aid_panel: AidPanel
## EVRENSEL PARTİ LİSTESİ (karalama hedefi, ittifak daveti...).
var _party_picker: PanelContainer
var _alliance_button: Button
var _alliance_panel: PanelContainer
var _alliance_list: VBoxContainer
var _alliance_name: LineEdit
var _alliance_color: Color = PartyPresets.COLORS[0]
var _alliance_swatches: Array[Button] = []
var _alliance_create_button: Button

func _ready() -> void:
	TableSurface.cover(self)
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
	GameSettings.province_view_changed.connect(_on_province_view_changed)

	UiSkin.skin_panel(left_panel, UiSkin.PANEL_DARK)
	# Yıl / sonraki seçim / baraj kendi levhasında dursun (ek UI katmanı).
	var info_plate := get_node_or_null("%InfoPlate") as PanelContainer
	if info_plate != null:
		var plate_style := UiSkin.stylebox(UiSkin.SLOT)
		plate_style.set_content_margin_all(UiTheme.PAD_S)
		UiSkin.apply_style(info_plate, "panel", plate_style)
	game_settings_label.add_theme_font_override("font", UiTheme.mono())
	game_settings_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	# Sıra göstergesi de aynı monospace ailede.
	turn_indicator_label.add_theme_font_override("font", UiTheme.mono())
	# Parlamento "tahtası": diyagram ekranın bir iki piksel üstünde duruyormuş
	# gibi kendi zemini ve sert gölgesi olan bir panelin içinde.
	var board := get_node_or_null("%ParliamentBoard") as PanelContainer
	if board != null:
		# Rozetin içinde ayrı bir çerçeve olmasın: diyagram rozet zeminine oturur.
		UiSkin.apply_style(board, "panel", StyleBoxEmpty.new())
	var actions_panel := get_node_or_null("%ActionsPanel") as PanelContainer
	if actions_panel != null:
		UiSkin.skin_panel(actions_panel, UiSkin.PANEL_DARK)
	# Monospace yazı geniş: panelin kendi genişliğini aşmasını engelle.
	# Kalınlık ve gölge panelin dışına taşar: kırpılmasın (içerik kendi kaydırıcısında).
	left_panel.clip_contents = false
	# custom_minimum_size ASGARİ ölçüdür, azami değil: eskiden panel içeriği
	# 260'ı aşınca sağa doğru büyüyüp diyagramın üstüne biniyordu. Artık düz
	# Panel olduğu için genişlik çapalarla sabit; burada bir şey zorlamıyoruz.
	left_panel.custom_minimum_size.x = 0.0
	_build_waiting_overlay()
	_build_event_log()
	_build_target_hint()
	_build_card_info()
	_build_action_buttons()
	_build_player_tabs()
	# Çöp kutusu destenin yanına otursun (yerleşim butonlar kurulduktan sonra).
	_place_right_column_controls()
	_build_law_designer()
	_build_alliance_panel()
	_build_tax_panel()
	_build_funding_ui()
	_build_agenda_banner()
	_build_propaganda_menu()
	_build_turn_flow_ui()
	vote_yes_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_YES))
	vote_no_button.pressed.connect(_on_vote_pressed.bind(GovernmentManager.VOTE_NO))
	_abstain_button = Button.new()
	# OY DÜĞMELERİ: simge üstte, ad altta; EVET yeşil, ÇEKİMSER sarı, HAYIR
	# kırmızı. DAR SÜTUNDA DA SIĞSIN: üçü satırı eşit paylaşır.
	_style_vote_button(vote_yes_button, L.t("EVET"), "", VOTE_COLOR_YES)
	_style_vote_button(_abstain_button, L.t("ÇEKİMSER"), "", VOTE_COLOR_ABSTAIN)
	_style_vote_button(vote_no_button, L.t("HAYIR"), "", VOTE_COLOR_NO)
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
		L.t("Sıran gelince önce kartını çekersin. Teşkilat, miting ve yatırım için haritada bir ile dokun. MECLİS düğmesi gensoru ve yasayı açar; istersen hiç girmeden turu bitirebilirsin."),
		func() -> Rect2: return _r(R_ACTIONS), mine)
	_tutorial.add_step("secmen", L.t("Seçmen grupları"),
		L.t("Oylar 8 seçmen grubundan gelir. Seçmen katmanı her grubun hangi illerde yoğun olduğunu gösterir; partin hangi gruplara yakınsa o illerde güçlüdür. Bir ile tıkla: oradaki durumunu görürsün."),
		func() -> Rect2: return (_layer_buttons[MapLayer.GROUPS] as Control).get_global_rect() if _layer_buttons.size() > MapLayer.GROUPS else _r(R_MAP),
		func() -> bool: return mine.call() and _tutorial.seen_count() >= 3)
	_tutorial.add_step("teskilat", L.t("Teşkilat"),
		L.t("Bir ile dokun, TEŞKİLAT'ı seç: ilde kalıcı oy, anket ve yerel bağış getirir; mitingte gruplara hitap etmeni sağlar. Beş ilden sonra her yeni teşkilat biraz daha pahalıdır: nerede kuracağını seç."),
		func() -> Rect2: return _r(R_MAP), func() -> bool: return mine.call() and _tutorial.seen_count() >= 4)
	_tutorial.add_step("kartlar", L.t("Kartlar"),
		L.t("Elindeki kartlar saklanabilir kartlardır: karta dokun, ne yaptığını oku; hedef isterse bir parti seç. Karalama kartı miting hazırlarken kullanılır. Kartların fiyatı yok."),
		func() -> Rect2: return _r(R_HAND),
		func() -> bool: return mine.call() and not CardManager.my_inventory().is_empty() and _tutorial.seen_count() >= 5)
	_tutorial.add_step("secim", L.t("Seçim yapıldı"),
		L.t("Vekil sayıları solda. En çok vekili olan parti hükümeti kurmaya çalışır; güvenoyu için meclisin çoğunluğu (251) gerekir. Gerekirse ortak bulunur."),
		func() -> Rect2: return _r(R_BOARD), func() -> bool: return CardManager.last_election_round > 0 and not CardManager.is_turn_blocked())
	_tutorial.add_step("hukumet", L.t("Hükümet ve koalisyon"),
		L.t("Hükümet kuruldu. Makamlar (başbakanlık, bakanlıklar) puan yazar; küçük ortak olmak da değerlidir. Muhalefet gensoruyla hükümeti düşürmeye, ortaklar koalisyondan çekilmeye karar verebilir."),
		func() -> Rect2: return _r(R_SIDE), func() -> bool: return GovernmentManager.has_government() and not CardManager.is_turn_blocked())
	_tutorial.add_step("ekonomi", L.t("Vergi ve yatırım"),
		L.t("Hükümettesin: vergi kademesini meclise sunabilir, devlet hazinesinden il yatırımı yapabilirsin. Vergi indirimi seçmene yavaş yansır, seçimden birkaç dönem önce yap. Hazineden payın bakanlıklarına göredir; miting ve yardım parti kasasından ödenir."),
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
		_card_bar_panel = TableSurface.wood("desk")
		# Ekranı boydan boya kaplayan masa: diğer paneller gibi konturlu, ama
		# kontur yalnız üst ve alt kenarda (0.0.260).
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
	# Kartların üst kenarı hamle düğmeleri ve kasa levhasıyla aynı hizada.
	hand_container.anchor_top = 0.0
	hand_container.anchor_bottom = 0.0
	hand_container.offset_top = 0.0
	hand_container.offset_bottom = CARD_DISPLAY_SIZE.y
	_fit_hand_width(CardManager.my_inventory().size())
	_place_desk_labels()

const DESK_COLOR := UiTheme.WOOD
const STRIP_BG := UiTheme.WOOD
var _desk_labels: Dictionary = {}
var _date_chip: PanelContainer
var _date_label: Label
var _map_bg: Panel
var _parl_bg: Panel
var _parl_title: Label
var _parl_summary: Label
## Oylama sürerken diyagramın altında EVET / HAYIR halat çubuğu (özet satırının yerine).
var _vote_bar: VoteTugBar
var _side_tabs: HBoxContainer
var _side_tab := 0
var _strip_bg: Control

## Tasarım ızgarasındaki bir dikdörtgeni ekran boyutuna ölçekler.
## Tasarım (1280x720) dikdörtgenini ekrana taşır. Eskiden x ve y ayrı
## oranlarla esniyordu: geniş ya da kısa pencerede yatay boşluklar dikeyden
## farklı çıkıyordu. Artık parçalı: tasarımdaki her 16'lık BOŞLUK ekranda aynı
## boyda (GAP × min ölçek); paneller ve masa kalan yeri orantılı doldurur.
const _X_MAIN := [0.0, 16.0, 288.0, 304.0, 976.0, 992.0, 1264.0, 1280.0]
const _X_DESK := [0.0, 16.0, 520.0, 536.0, 1096.0, 1112.0, 1264.0, 1280.0]
const _Y_ROWS := [0.0, 64.0, 80.0, 520.0, 536.0, 568.0, 704.0, 720.0]

func _r(rect: Rect2) -> Rect2:
	var view := get_viewport_rect().size
	var k := view / DESIGN
	var gap := GAP_SCREEN * minf(k.x, k.y)
	var xs: Array = _X_DESK if rect.position.y >= 536.0 - 0.5 else _X_MAIN
	var x0 := _remap(rect.position.x, xs, view.x, gap)
	var y0 := _remap(rect.position.y, _Y_ROWS, view.y, gap)
	var x1 := _remap(rect.end.x, xs, view.x, gap)
	var y1 := _remap(rect.end.y, _Y_ROWS, view.y, gap)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

## Parçalı eşleme: 16'lık parçalar "gap" piksel, diğerleri kalan alanı tasarım
## oranında paylaşır; parça içinde doğrusal.
static func _remap(v: float, stops: Array, total: float, gap: float) -> float:
	var gaps := 0
	var other := 0.0
	for i in range(1, stops.size()):
		var len := float(stops[i]) - float(stops[i - 1])
		if is_equal_approx(len, GAP):
			gaps += 1
		else:
			other += len
	var scale := maxf(0.0, total - gaps * gap) / maxf(1.0, other)
	var out := 0.0
	for i in range(1, stops.size()):
		var a := float(stops[i - 1])
		var b := float(stops[i])
		var seg := gap if is_equal_approx(b - a, GAP) else (b - a) * scale
		if v <= b or i == stops.size() - 1:
			return out + (v - a) / (b - a) * seg
		out += seg
	return out

## Boydan boya AHŞAP şerit (üst bant, alt masa): açık üst kenar çıtası ve
## koyu alt kenar; yanlar ekranın dışına taşar.
static func _edge_band_style(color: Color) -> StyleBox:
	var box := UiSkin.flat(color, 0)
	box.border_color = UiTheme.WOOD_DARK
	box.border_width_bottom = 4
	box.border_width_top = 3
	box.expand_margin_left = 16.0
	box.expand_margin_right = 16.0
	return box

## Bant kutusu: Menü düğmesinin boyunu aşmasın diye dikey boşluğu az.
static func _band_plate() -> BoardBox:
	var b := UiSkin.plate()
	b.content_margin_left = UiTheme.d(10)
	b.content_margin_right = UiTheme.d(14)
	b.content_margin_top = UiTheme.d(2)
	b.content_margin_bottom = UiTheme.d(2)
	return b

## Ahşap üstündeki yazının sert gölgesi (konsept: 0 Npx 0 #6a3b18).
static func _wood_text_shadow(label: Control, px: float) -> void:
	label.add_theme_color_override("font_shadow_color", UiTheme.WOOD_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(UiTheme.d(px)))))

## Panoların iç alanı (konsept: yanlarda 22, üstte 20, altta 22 px).
static func _panel_inner(rect: Rect2) -> Rect2:
	return Rect2(rect.position + Vector2(UiTheme.d(22), UiTheme.d(20)),
		rect.size - Vector2(UiTheme.d(44), UiTheme.d(42)))

func _board_inner() -> Rect2:
	return _panel_inner(_r(R_BOARD))

## HARİTA ALANI: orta panonun içinde, sekmelerin altında (konsept .mapwrap).
func _map_area() -> Rect2:
	var panel := _r(R_MAP)
	return Rect2(panel.position + Vector2(UiTheme.d(16), UiTheme.d(84)),
		panel.size - Vector2(UiTheme.d(32), UiTheme.d(84) + UiTheme.d(16)))

func _set_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size

static func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.mono(true))
	label.add_theme_font_size_override("font_size", UiTheme.fs(18))
	label.add_theme_color_override("font_color", UiTheme.HEAD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Masanın bölüm başlıkları: ELİM · HAMLELER · SIRA.
func _place_desk_labels() -> void:
	for key in ["hand", "actions", "turn"]:
		if not _desk_labels.has(key) or not _desk_labels[key] is Label:
			var label := _section_label("")
			add_child(label)
			_desk_labels[key] = label
	# Masa başlıkları masanın üst kenarıyla içeriğin arasında, sütunlara hizalı.
	for key in ["hand", "actions"]:
		var label := _desk_labels[key] as Label
		label.add_theme_color_override("font_color", UiTheme.WOOD_TEXT)
		label.add_theme_font_size_override("font_size", UiTheme.fs(19))
		_wood_text_shadow(label, 2.0)
	if not _desk_labels.has("hint"):
		var hint := Label.new()
		hint.add_theme_font_override("font", UiTheme.mono_regular())
		hint.add_theme_font_size_override("font_size", UiTheme.fs(16))
		hint.add_theme_color_override("font_color", UiTheme.WOOD_TEXT_MUTED)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hint)
		_desk_labels["hint"] = hint
	(_desk_labels["hand"] as Label).position = _r(Rect2(16, 546, 0, 0)).position
	(_desk_labels["actions"] as Label).position = _r(Rect2(536, 546, 0, 0)).position
	(_desk_labels["turn"] as Label).position = _r(Rect2(1112, 546, 0, 0)).position
	# 0.0.260: sıra göstergesi yalnız üst bantta (para levhasının üstünde yok).
	(_desk_labels["turn"] as Label).visible = false
	# İpucu başlığın yanında (masanın alt kenarına taşmasın).
	(_desk_labels["actions"] as Label).text = L.t("HAMLELER")
	var hint := _desk_labels["hint"] as Label
	hint.text = "·  " + L.t("teşkilat, miting, yatırım: haritada bir ile dokun")
	var actions_label := _desk_labels["actions"] as Label
	actions_label.reset_size()
	hint.reset_size()
	hint.position = actions_label.position + Vector2(actions_label.size.x + UiTheme.d(10),
		(actions_label.size.y - hint.size.y) * 0.5)
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
	var map_rect := _map_area()
	_ensure_center_board()
	if _swap_engaged:
		_place_map(_swap_map_rect)
	else:
		_place_map(map_rect)
	_place_layer_bar()

	# CANLI YAYIN BANDI: CANLI · başlık + tarih · sıra kimde (Menü sağda).
	if _strip_bg == null:
		_strip_bg = TableSurface.wood("band")
		# Boydan boya bant: kontur üst ve alt kenarda, yanlarda yok (0.0.260).
		add_child(_strip_bg)
		move_child(_strip_bg, 1)
	# 0.0.255: bant sayaç şeridinin ALTINDAN başlar (ikisi üst üste binmez).
	_set_rect(_strip_bg, _r(Rect2(0, 0, 1280, R_BAND.size.y)))
	_place_date_chip(map_rect)

	# SKOR TABLOSU (sol): VEKİL ve PUAN sekmeleri.
	_ensure_board()
	_set_rect(_board_bg, _r(R_BOARD))
	var strip := get_node_or_null("PlayerPanel") as Control
	if strip != null:
		_set_rect(strip, _board_inner())

	_detach_actions_panel()

	# STÜDYO MASASI (sağ): Hükümet (meclis diyagramıyla) · Log · Seçili.
	_set_rect(left_panel, _r(R_SIDE))
	_setup_side_column()
	_place_parliament_badge()

	# BENİM MASAM: kartlar, hamleler (Turu Bitir dahil), para.
	_place_card_bar()

	# Harita ölçeği değişti => vekil kareleri yeni ölçeğe göre yeniden piksel
	# hizalanmalı (bkz. seat_markers.gd _draw).
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.queue_redraw()
	_place_right_column_controls()
	_rebuild_player_panel()

## Haritayı (zemin + kırpma kutusu + ölçek) verilen dikdörtgene sığdırır.
func _place_map(map_rect: Rect2) -> void:
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
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.queue_redraw()
	if map_holder.isolated_id != "":
		_fit_isolated_province(map_rect)

## Bölünmüş görünüm: sol yarıyı yalnız tıklanan il doldurur (il tamamen görünür).
func _fit_isolated_province(map_rect: Rect2) -> void:
	_map_clip.position = map_rect.position
	_map_clip.size = map_rect.size
	var box: Rect2 = map_holder.region_bounds(map_holder.isolated_id)
	var fit := minf(map_rect.size.x / maxf(box.size.x, 1.0), map_rect.size.y / maxf(box.size.y, 1.0)) * 0.8
	map_holder.scale = Vector2(fit, fit)
	map_holder.position = map_rect.size * 0.5 - box.get_center() * fit

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
	UiSkin.apply_style(panel, "panel", StyleBoxEmpty.new())
	var margin2 := panel.get_node_or_null("ActionsMargin") as MarginContainer
	if margin2 != null:
		for side in ["left", "right", "top", "bottom"]:
			margin2.add_theme_constant_override("margin_" + side, 0)
	_set_rect(panel, _r(R_ACTIONS))

## Harita alanının zemini (harita bunun ortasına oturur).
func _ensure_map_bg(rect: Rect2) -> void:
	if _map_bg == null:
		# Deniz (dalgalı) haritanın arkasında; haritanın kendi denizi çizilmez.
		_map_bg = TableSurface.sea()
		add_child(_map_bg)
		move_child(_map_bg, _center_bg.get_index() + 1 if _center_bg != null else 1)
		map_holder.set("draw_sea", false)
	_set_rect(_map_bg, rect)

## ORTA PANO: harita sekmeleri ve haritanın oturduğu karton pano.
var _center_bg: Panel

func _ensure_center_board() -> void:
	if _center_bg == null:
		_center_bg = Panel.new()
		_center_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_center_bg.add_theme_stylebox_override("panel", UiSkin.board())
		add_child(_center_bg)
		move_child(_center_bg, 1)
	_set_rect(_center_bg, _r(R_MAP))

## YAYIN BANDI: kırmızı CANLI rozeti, "SİYASET GÜNDEMİ" ve altında tarih /
## baraj / sonraki seçim; ortada sıranın kimde olduğu ve kalan süre.
var _band_live: Label
var _band_title: Label
var _band_turn: PanelContainer
var _band_turn_row: HBoxContainer
var _band_turn_key := ""

var _band_period: Label
var _band_crisis: PanelContainer
var _band_crisis_title: RichTextLabel
var _band_crisis_text: Label
## Krizin seçmen grubu simgesi (kutunun solunda).
var _band_crisis_icon: VoterGroupIcon
var _timer_bar_bg: ColorRect
var _timer_bar: ColorRect

func _place_date_chip(_map_rect: Rect2) -> void:
	if _date_label == null:
		_band_period = Label.new()
		_band_period.add_theme_font_override("font", UiTheme.mono(true))
		# Konsept: dönem 34 px, ahşap üstünde açık krem ve sert koyu gölge.
		_band_period.add_theme_font_size_override("font_size", UiTheme.fs(34))
		_band_period.add_theme_color_override("font_color", UiTheme.WOOD_TEXT)
		_wood_text_shadow(_band_period, 3.0)
		_band_period.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_band_period)
		_date_label = Label.new()
		_date_label.add_theme_font_override("font", UiTheme.mono_regular())
		_date_label.add_theme_font_size_override("font_size", UiTheme.fs(16))
		_date_label.add_theme_color_override("font_color", UiTheme.WOOD_TEXT_MUTED)
		_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_date_label)
		# KRİZ / GÜNDEM kutusu.
		# KRİZ kutusu (konsept .box.crisis): koyu pul + hardal simge, başlıkta
		# kırmızı "KRİZ", altında tek satır etki.
		_band_crisis = PanelContainer.new()
		_band_crisis.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_crisis.add_theme_stylebox_override("panel", _band_plate())
		var crisis_row := HBoxContainer.new()
		crisis_row.add_theme_constant_override("separation", int(UiTheme.d(14)))
		crisis_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_crisis.add_child(crisis_row)
		_band_crisis_icon = VoterGroupIcon.make("isci", UiTheme.d(44))
		# 0.0.268: sıra kutusundaki parti logosu gibi grubun renginde 3B pul.
		_band_crisis_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crisis_row.add_child(_band_crisis_icon)
		var crisis_texts := VBoxContainer.new()
		crisis_texts.alignment = BoxContainer.ALIGNMENT_CENTER
		crisis_texts.add_theme_constant_override("separation", int(UiTheme.d(4)))
		crisis_texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crisis_texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crisis_row.add_child(crisis_texts)
		_band_crisis_title = RichTextLabel.new()
		_band_crisis_title.bbcode_enabled = true
		_band_crisis_title.fit_content = true
		_band_crisis_title.autowrap_mode = TextServer.AUTOWRAP_OFF
		_band_crisis_title.scroll_active = false
		_band_crisis_title.clip_contents = false
		_band_crisis_title.add_theme_font_override("normal_font", UiTheme.mono(true))
		_band_crisis_title.add_theme_font_size_override("normal_font_size", UiTheme.fs(22))
		_band_crisis_title.add_theme_color_override("default_color", UiTheme.TEXT)
		_band_crisis_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crisis_texts.add_child(_band_crisis_title)
		_band_crisis_text = Label.new()
		_band_crisis_text.add_theme_font_size_override("font_size", UiTheme.fs(15))
		_band_crisis_text.add_theme_color_override("font_color", UiTheme.TEXT_MUTED2)
		_band_crisis_text.clip_text = true
		_band_crisis_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crisis_texts.add_child(_band_crisis_text)
		add_child(_band_crisis)
		_band_turn = PanelContainer.new()
		_band_turn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_turn.add_theme_stylebox_override("panel", _band_plate())
		_band_turn_row = HBoxContainer.new()
		_band_turn_row.add_theme_constant_override("separation", int(UiTheme.d(14)))
		_band_turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_band_turn.add_child(_band_turn_row)
		add_child(_band_turn)
		# SÜRE ŞERİDİ: ekranın en üstünde, sırası gelenin renginde, süre
		# azaldıkça soldan sağa uzar (dolunca süre biter).
		_timer_bar_bg = ColorRect.new()
		_timer_bar_bg.color = Color(0, 0, 0, 0.22)
		_timer_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_timer_bar_bg.z_index = 7
		add_child(_timer_bar_bg)
		_timer_bar = ColorRect.new()
		_timer_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_timer_bar.z_index = 8
		add_child(_timer_bar)
	_band_period.position = _r(Rect2(16, 16, 0, 0)).position
	_date_label.position = _r(Rect2(16, 42, 0, 0)).position
	# Üst banttaki kutular (kriz, sıra) sağdaki Menü düğmesiyle AYNI üst ve
	# alt kenarda durur (Menü SettingsOverlay'de, ölçeklenmeyen piksellerle).
	# 0.0.260: aralarındaki boşluk Menü'nün bantla üst/alt boşluğu kadar;
	# kutular Menü'den sola doğru dizilir.
	var menu := _menu_button_rect()
	var band := _r(Rect2(0, 0, 1280, R_BAND.size.y))
	var gap := maxf(2.0, ((menu.position.y - band.position.y) + (band.end.y - menu.end.y)) * 0.5)
	var turn_w := _r(Rect2(760, 0, 380, 0)).size.x
	var crisis_w := _r(Rect2(300, 0, 444, 0)).size.x
	var turn_x := menu.position.x - gap - turn_w
	var crisis_x := turn_x - gap - crisis_w
	_set_rect(_band_crisis, Rect2(crisis_x, menu.position.y, crisis_w, menu.size.y))
	_set_rect(_band_turn, Rect2(turn_x, menu.position.y, turn_w, menu.size.y))
	_set_rect(_timer_bar_bg, _r(Rect2(0, 0, 1280, TIMER_BAR_HEIGHT)))
	_refresh_band_date()
	_refresh_band_crisis()
	_band_turn_key = ""
	_refresh_band_turn()
	_refresh_timer_bar()

## Sayaç şeridi ekranın en üstünde kendi satırında (bant 8–64 arası).
const TIMER_BAR_HEIGHT := 8.0

## Sağ üstteki Menü düğmesinin ekrandaki dikdörtgeni (yoksa tasarım değeri).
func _menu_button_rect() -> Rect2:
	var overlay := get_node_or_null("/root/SettingsOverlay")
	var button: Control = overlay.get_node_or_null("%OpenSettingsButton") if overlay != null else null
	if button != null and button.size.y > 0.0:
		return button.get_global_rect()
	return Rect2(get_viewport_rect().size.x - 124.0, 14.0, 108.0, 44.0)

func _refresh_band_date() -> void:
	if _band_period == null:
		return
	var next_election := CardManager.next_election_round()
	_band_period.text = GameRules.period_label(mini(CardManager.round_number, GameRules.MAX_ROUNDS))
	var parts := [L.t("Baraj %%%s") % _format_threshold(MultiplayerManager.election_threshold),
		_next_election_text(next_election, false)]
	if MultiplayerManager.seat_method != MultiplayerManager.DEFAULT_SEAT_METHOD:
		parts.append(ElectionModel.method_title(MultiplayerManager.seat_method))
	_date_label.text = "  ·  ".join(PackedStringArray(parts))

## KRİZ (kırmızı) ya da sadece GÜNDEM (altın) bantta; ikisi de yoksa gizli.
## SİYASİ KRİZ KUTUSU (0.0.259): kırmızı çerçeve, solda krizin seçmen grubu
## simgesi, başlık "KRİZ · ..." ve tek satır etki. Kriz yoksa gizli.
func _refresh_band_crisis() -> void:
	if _band_crisis == null:
		return
	var agenda := CardManager.agenda_type()
	_band_crisis.visible = agenda != ""
	if not _band_crisis.visible:
		return
	var data := CardPresets.agenda_data(agenda)
	_band_crisis_icon.set_group(String(data.get("group", "")))
	_band_crisis_title.text = "[color=#%s]%s[/color] · %s" % [UiTheme.CRISIS.to_html(false), L.t("KRİZ"), data["title"]]
	_band_crisis_text.text = L.t("%s için yasa çok daha etkili") % data["group_title"]

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

## SIRA KUTUSU (0.0.260, kriz kutusuyla aynı tarz): sırası gelen partinin
## renginde zemin, solda logosu, başlık "SIRA · PARTİ" ve altında siyasetçi ·
## kalan süre.
func _refresh_band_turn() -> void:
	if _band_turn_row == null:
		return
	var peer_id := CardManager.current_turn_peer_id()
	var timer := "" if peer_id == -1 or CardManager.is_turn_blocked() else GameRules.format_seconds(CardManager.turn_seconds_left())
	var key := "%d|%s|%s|%.0f" % [peer_id, timer, PartyManager.data_of(peer_id).get("name", ""), _band_turn.size.y]
	if key == _band_turn_key:
		return
	_band_turn_key = key
	for child in _band_turn_row.get_children():
		_band_turn_row.remove_child(child)
		child.queue_free()
	_band_turn.visible = peer_id != -1
	if peer_id == -1:
		return
	var data := PartyManager.data_of(CardManager.party_of(peer_id))
	var color: Color = data.get("bg_color", UiTheme.GOLD)
	var side := UiTheme.d(44)
	var badge := PartyBadge.build(PartyManager.data_of(peer_id), Vector2(side, side), BADGE_ICON_PIXEL_SIZE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_band_turn_row.add_child(badge)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", int(UiTheme.d(4)))
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band_turn_row.add_child(texts)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(UiTheme.d(6)))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(head)
	var party_text := L.t("Bağımsız") if PartyManager.is_independent(peer_id) else String(PartyManager.data_of(peer_id).get("name", "?"))
	# Konsept: "SIRA SENDE" parti renginde, köşesi 8 px, altı koyu kalın hap.
	var pill := Label.new()
	pill.text = L.t("SIRA SENDE") if peer_id == multiplayer.get_unique_id() else L.t("SIRA")
	pill.add_theme_font_override("font", UiTheme.mono(true))
	pill.add_theme_font_size_override("font_size", UiTheme.fs(22))
	pill.add_theme_color_override("font_color", UiSkin.text_on(color))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_box := BoardBox.new()
	pill_box.fill = color
	pill_box.set_radius(UiTheme.d(8))
	pill_box.lips = [[UiTheme.d(2), color.lerp(Color.BLACK, 0.4)]]
	pill_box.content_margin_left = UiTheme.d(8)
	pill_box.content_margin_right = UiTheme.d(8)
	pill.add_theme_stylebox_override("normal", pill_box)
	head.add_child(pill)
	var title := _avatar_label("· " + party_text, UiTheme.fs(22), UiTheme.TEXT)
	title.add_theme_font_override("font", UiTheme.mono(true))
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var sub := RichTextLabel.new()
	sub.bbcode_enabled = true
	sub.fit_content = true
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.scroll_active = false
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_font_size_override("normal_font_size", UiTheme.fs(15))
	sub.add_theme_font_size_override("bold_font_size", UiTheme.fs(15))
	sub.add_theme_font_override("bold_font", UiTheme.body_black())
	sub.add_theme_color_override("default_color", UiTheme.TEXT_MUTED2)
	sub.text = PoliticianPresets.display_name(peer_id) + ((" · [b][color=#%s]%s[/color][/b]" % [UiTheme.TEAL.to_html(false), timer]) if timer != "" else "")
	texts.add_child(sub)

## MECLİS: stüdyo masasının HÜKÜMET sekmesinde, sekmelerin hemen altındaki
## yuvada; oylama sürerken büyür, teklif metni ve EVET/ÇEKİMSER/HAYIR görünür (bkz. _parl_slot). Oylama başlayınca Hükümet sekmesi kendiliğinden açılır.
var _parl_slot: Control
var _was_voting := false

## OYLAMA KAMERASI (0.0.213): meclis oylaması sürerken harita ile meclis
## diyagramı yer değiştirir (seçim gecesi kamerası gibi: pencereler üstel
## yumuşamayla kayar, geçişte TV flaşı, büyük pencerede altın çerçeve).
## Oylama bittikten VOTE_SWAP_RETURN_DELAY saniye sonra eski yerlerine döner.
const VOTE_SWAP_RETURN_DELAY := 0.5
const VOTE_SWAP_SPEED := 9.0
var _vote_swapped := false
var _vote_end_wait := 0.0
var _swap_engaged := false
var _swap_map_rect := Rect2()
var _swap_parl_rect := Rect2()
var _swap_home_parl := Rect2()
var _swap_flash: ColorRect
var _swap_frame: Panel

func _place_parliament_badge() -> void:
	var voting := GovernmentManager.is_voting()
	var just_started := voting and not _was_voting
	_was_voting = voting
	if _parl_bg == null:
		_parl_bg = Panel.new()
		_parl_bg.add_theme_stylebox_override("panel", UiSkin.card())
		_parl_bg.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_parl_bg)
		move_child(_parl_bg, bottom_area.get_index())
		var vbox := bottom_area.get_node_or_null("ChamberSplit/ParliamentChamber/ParliamentVBox") as VBoxContainer
		if vbox != null:
			_parl_title = _section_label(L.t("MECLİS · %d") % CardManager.TOTAL_SEATS)
			vbox.add_child(_parl_title)
			vbox.move_child(_parl_title, 0)
			_parl_summary = Label.new()
			_parl_summary.add_theme_font_override("font", UiTheme.mono_regular())
			_parl_summary.add_theme_font_size_override("font_size", UiTheme.fs(15))
			_parl_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_parl_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(_parl_summary)
			vbox.move_child(_parl_summary, 2)
			_vote_bar = VoteTugBar.new()
			_vote_bar.diagram = parliament_diagram
			_vote_bar.hide()
			vbox.add_child(_vote_bar)
			vbox.move_child(_vote_bar, 3)
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
		# 0.0.258: oylamada meclis ortaya, harita bu yuvaya geçer; yuva büyümez
		# (eskiden 286'ya çıkıp haritayı uzatıyor, altındaki ekonomiyi itiyordu).
		_parl_slot.custom_minimum_size.y = PARL_SLOT_HEIGHT * _r(R_SIDE).size.y / R_SIDE.size.y
	var vote_row := bottom_area.get_node_or_null("ChamberSplit/ParliamentChamber/ParliamentVBox/VoteButtonRow") as Control
	if vote_row != null:
		vote_row.visible = voting
	# 0.0.268: yasa oylamasında alt metin yok (getiren ve grup diyagramın köşesinde).
	proposal_label.visible = voting and GovernmentManager.proposal_kind != GovernmentManager.KIND_LAW
	_refresh_parliament_summary()
	_sync_parliament_to_slot()

## Meclis (zemin + diyagram) her kare yuvanın ekrandaki yerine oturur; yuva
## görünmüyorsa (Log / Seçili sekmesi) meclis de gizlenir.
func _sync_parliament_to_slot() -> void:
	if _parl_bg == null:
		return
	var shown := _swap_engaged or (_parl_slot != null and _parl_slot.is_visible_in_tree())
	_parl_bg.visible = shown
	bottom_area.visible = shown
	if not shown:
		return
	var rect := _swap_parl_rect if _swap_engaged else _parl_slot.get_global_rect()
	if _parl_bg.position != rect.position or _parl_bg.size != rect.size:
		_set_rect(_parl_bg, rect)
		bottom_area.position = rect.position
		bottom_area.size = rect.size

## Her kare: oylama varsa harita meclisin yuvasına, meclis haritanın yerine
## kayar; bitince (gecikmeyle) geri döner.
func _update_vote_swap(delta: float) -> void:
	if _parl_bg == null or _parl_slot == null or map_holder == null or map_holder.grid_width <= 0:
		return
	# Meclisin yuvası: sekme açıkken gerçek yeri; Log / Seçili açıkken son bilinen yeri
	# (fareyle parti incelemek oylama kamerasını bozmasın).
	if _parl_slot.is_visible_in_tree() and _parl_slot.size.y > 0.0:
		_swap_home_parl = _parl_slot.get_global_rect()
	elif not _swap_home_parl.has_area():
		var side := _r(R_SIDE)
		_swap_home_parl = Rect2(side.position + Vector2(0.0, 48.0), Vector2(side.size.x, PARL_SLOT_HEIGHT * side.size.y / R_SIDE.size.y))
	var voting := GovernmentManager.is_voting()
	if voting:
		_vote_end_wait = VOTE_SWAP_RETURN_DELAY
	else:
		_vote_end_wait = maxf(0.0, _vote_end_wait - delta)
	var want := voting or _vote_end_wait > 0.0
	var home_map := _map_area()
	if not _swap_engaged:
		_swap_map_rect = home_map
		_swap_parl_rect = _swap_home_parl
	if want != _vote_swapped:
		_vote_swapped = want
		_ensure_swap_fx()
		_swap_flash.color.a = 0.6
	if _swap_flash != null:
		_swap_flash.color.a = move_toward(_swap_flash.color.a, 0.0, delta * 2.4)
	var map_to: Rect2 = _swap_home_parl if _vote_swapped else home_map
	var parl_to: Rect2 = home_map if _vote_swapped else _swap_home_parl
	var k := 1.0 - exp(-VOTE_SWAP_SPEED * delta)
	var arrived := true
	for which in 2:
		var now: Rect2 = _swap_map_rect if which == 0 else _swap_parl_rect
		var to: Rect2 = map_to if which == 0 else parl_to
		if now.position.distance_to(to.position) + now.size.distance_to(to.size) < 0.6:
			now = to
		else:
			now = Rect2(now.position.lerp(to.position, k), now.size.lerp(to.size, k))
			arrived = false
		if which == 0:
			_swap_map_rect = now
		else:
			_swap_parl_rect = now
	var engaged := _vote_swapped or not arrived
	if not engaged and not _swap_engaged:
		return
	_swap_engaged = engaged
	_place_map(_swap_map_rect if engaged else home_map)
	# Küçük harita sağ sütunun üstünde çizilsin; katman düğmeleri geçişte gizli.
	var z := 5 if engaged else 0
	_map_bg.z_index = z
	_map_clip.z_index = z
	if _layer_bar != null:
		_layer_bar.visible = not engaged
	if _layer_legend != null:
		if engaged:
			_layer_legend.visible = false
		else:
			_rebuild_layer_legend()
	if _group_picker != null:
		_group_picker.visible = not engaged and _map_layer == MapLayer.GROUPS
	_ensure_swap_fx()
	_swap_frame.visible = engaged
	var big: Rect2 = _swap_parl_rect if _vote_swapped else _swap_map_rect
	_swap_frame.position = big.position
	_swap_frame.size = big.size
	_sync_parliament_to_slot()

## Flaş (harita + sağ sütun alanı) ve büyük pencerenin altın çerçevesi.
func _ensure_swap_fx() -> void:
	if _swap_flash == null:
		_swap_flash = ColorRect.new()
		_swap_flash.color = Color(1, 1, 1, 0)
		_swap_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_swap_flash.z_index = 8
		add_child(_swap_flash)
		_swap_frame = Panel.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.set_border_width_all(3)
		box.border_color = UiTheme.GOLD
		_swap_frame.add_theme_stylebox_override("panel", box)
		_swap_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_swap_frame.z_index = 7
		_swap_frame.visible = false
		add_child(_swap_frame)
	var area := _r(R_MAP).merge(_r(R_SIDE))
	_swap_flash.position = area.position
	_swap_flash.size = area.size

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
	_parl_summary.add_theme_color_override("font_color", UiTheme.TEXT_MUTED2)

## SAĞ SÜTUN: üstte sekmeler; Hükümet (hükümet + son olaylar), Log (sadece
## log), Seçili (dokunulan il / parti). Eski bilgi kutusu ve sıra göstergesi
## buradan kalktı (tarih haritada, sıra masada).
func _setup_side_column() -> void:
	var vbox := left_panel.get_node_or_null("LeftMargin/LeftScroll/LeftVBox") as VBoxContainer
	if vbox == null:
		return
	var margin := left_panel.get_node_or_null("LeftMargin") as MarginContainer
	if margin != null:
		margin.add_theme_constant_override("margin_left", int(UiTheme.d(22)))
		margin.add_theme_constant_override("margin_right", int(UiTheme.d(22)))
		margin.add_theme_constant_override("margin_top", int(UiTheme.d(20)))
		margin.add_theme_constant_override("margin_bottom", int(UiTheme.d(22)))
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
			tab.custom_minimum_size = Vector2(0, PLAYER_TAB_HEIGHT)
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
		style.bg_color = Color("FFF1CC") if peer_id == me else UiTheme.PANEL_DARK
		style.border_color = party.get("bg_color", Color.GRAY)
		style.border_width_left = 4
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		UiSkin.apply_style(row, "panel", style)
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
		var name_label := _avatar_label(person, _fit_font_size(person, 150.0, 12, 8), UiTheme.HEAD if peer_id == me else UiTheme.TEXT)
		name_label.clip_text = false
		name_label.add_theme_font_override("font", UiTheme.mono(true))
		names.add_child(name_label)
		var party_text := L.t("Bağımsız") if PartyManager.is_independent(pid) else String(party.get("name", "?"))
		if CardManager.is_party_member(peer_id):
			party_text += L.t(" · üye")
		names.add_child(_avatar_label(party_text, 10, UiTheme.TEXT_MUTED))
		line.add_child(_table_value(str(GovernmentManager.score_of(peer_id)), 40.0, UiTheme.HEAD, 13))
		var national := CardManager.visible_national_of(pid)
		var trend_value := _table_value(EffectWords.arrows(national), 46.0, ProvincePanel._opinion_color(national), 12)
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
		_style_tab_button(tab, i == active, true)
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
	if _event_fx != null and _event_fx.is_playing():
		await _event_fx.drained
	if is_inside_tree():
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
	CardManager.event_presented.connect(_on_alliance_event)
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
	var key := "cm|%s|%s" % [str(event.get("news_id", version)), type]
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

## Açık kongre gecesi (tur başı sunumu onun bitmesini bekler).
var _congress_view: Control

## KONGRE GECESİ: herkesin ekranında, seçim gecesi tarzında.
func _on_congress_started(data: Dictionary) -> void:
	var congress_view: Control = preload("res://scripts/congress_show.gd").new()
	congress_view.data = data
	add_child(congress_view)  # sonuç gazetesini kendisi oynatır
	_congress_view = congress_view

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
	if _leaving_for_results:
		return
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
		# Konsept: il dolgusu parti renginin %82'si + beyaz (basılı tahta tonu).
		_seat_layer_colors[province_id] = party_color.lerp(Color.WHITE, 0.18)
	_apply_map_layer_colors()

## Harita üzerindeki il başına milletvekili noktalarını (SeatMarkers, bkz.
## Map.tscn/seat_markers.gd) son il bazlı sonuçlara göre günceller.
func _refresh_map_seat_markers() -> void:
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers == null:
		return
	seat_markers.clear_all()
	# İlk seçimden önce de her ilin çıkaracağı vekiller sayılabilmeli.
	if CardManager.last_province_results.is_empty():
		var neutral := {}
		for province_id in GameMap.province_ids():
			var colors: Array = []
			colors.resize(GameMap.seat_counts().get(province_id, 0))
			colors.fill(Color.WHITE)
			neutral[province_id] = colors
		seat_markers.set_all(neutral)
		return
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

## "Sonraki seçim" yazısı. Seçim BU turun sonundaysa bunu açıkça söyler:
## erken seçim takvimi 1. yarı sonlarına kaydırınca "2010 1. yarı · Sonraki
## seçim 2010" seçimin bitmiş bir yılda olduğu gibi okunuyordu (0.0.224).
func _next_election_text(next_election: int, colon: bool) -> String:
	if next_election == -1:
		return L.t("Başka seçim yok")
	if next_election <= CardManager.round_number:
		return L.t("Seçim bu dönemin sonunda")
	return (L.t("Sonraki seçim: %s") if colon else L.t("Sonraki seçim %s")) % GameRules.election_label(next_election)

func _refresh_game_settings_label() -> void:
	var next_election := CardManager.next_election_round()
	game_settings_label.text = L.t("%s  ·  Baraj %%%s\n%s") % [
		GameRules.period_label(mini(CardManager.round_number, GameRules.MAX_ROUNDS)),
		_format_threshold(MultiplayerManager.election_threshold),
		_next_election_text(next_election, true),
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
	_close_law_page()

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
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.custom_minimum_size = Vector2(0, PLAYER_TAB_HEIGHT)
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
		_style_tab_button(button, i == _player_tab, true)

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
			var national: float = CardManager.visible_national_of(peer_id)
			return [
				_table_value(str(now), 46.0, UiTheme.TEXT_MUTED),
				_table_value(EffectWords.arrows(national), 52.0, ProvincePanel._opinion_color(national)),
				_table_value(str(GovernmentManager.score_of(peer_id)), 44.0, UiTheme.TEXT),
			]
		_:
			# PARA GİZLİ: kimse rakibinin kasasını göremez.
			if is_self:
				return [_table_value(GameRules.money(CardManager.funds_of(peer_id)), 58.0, FUNDS_COLOR)]
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
	if player_tabs != null:
		player_tabs.show()
	var party_ids := _ordered_party_ids()
	player_panel_list.columns = 1
	player_panel_list.add_theme_constant_override("v_separation", int(PLAQUE_GAP))
	var panel := get_node_or_null("PlayerPanel") as Control
	if panel != null:
		panel.clip_contents = true
	var inner := _board_inner()
	var list_height: float = inner.size.y - PLAYER_TAB_HEIGHT - PLAQUE_GAP * 2.0
	var plaque_height: float = clampf(list_height / maxf(1.0, party_ids.size()) - PLAQUE_GAP, 44.0, PLAQUE_HEIGHT)
	var existing := {}
	for child in player_panel_list.get_children():
		existing[child.get_meta("peer_id", -1)] = child
	for index in party_ids.size():
		var pid: int = party_ids[index]
		var key := _plaque_key(pid, inner.size.x)
		var plaque: Control = existing.get(pid)
		if plaque == null or plaque.get_meta("plaque_key", []) != key:
			if plaque != null:
				player_panel_list.remove_child(plaque)
				plaque.queue_free()
			plaque = _build_plaque(pid, inner.size.x)
			plaque.set_meta("plaque_key", key)
			player_panel_list.add_child(plaque)
		plaque.custom_minimum_size.y = plaque_height
		player_panel_list.move_child(plaque, index)
		existing.erase(pid)
	for child in existing.values():
		player_panel_list.remove_child(child)
		child.queue_free()
	_board_scroll.visible = _player_tab == 0
	_score_scroll.visible = _player_tab == 1
	_refresh_score_table()
	# Panel yeniden kuruldu: hedef seçme vurguları yeni düğümlere uygulanmalı.
	_refresh_target_highlights()

## Only inputs used by _build_plaque; snapshots must survive in-place mutations.
func _plaque_key(pid: int, width: float) -> Array:
	var party := PartyManager.data_of(pid)
	var members := PartyManager.members_of(pid)
	var people := []
	for member in members:
		people.append([PoliticianPresets.display_name(int(member)), MultiplayerManager.is_away(int(member))])
	var alliance_id := CardManager.alliance_of(pid)
	return [width, multiplayer.get_unique_id(), TranslationServer.get_locale(),
		party.get("name"), party.get("bg_color"), party.get("icon_index"), party.get("icon_color"),
		PartyManager.is_independent(pid), members.duplicate(), people,
		CardManager.current_turn_peer_id(), CardManager.last_seats.get(pid),
		CardManager.last_vote_shares.duplicate(), CardManager.populism_rounds_left(pid),
		CardManager.alliances.get(alliance_id, {}).duplicate(true), MultiplayerManager.away_mode,
		GovernmentManager.has_government(), CardManager.is_government_party(pid),
		GovernmentManager.main_gov_peer_id, GovernmentManager.is_voting(),
		GovernmentManager.eligible_voter_ids(), GovernmentManager.votes.duplicate(),
		PoliticianPresets.display_name(pid)]

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
	# KONSEPT .prow: beyaz kart, parti renginde (%45) kenar ve kalınlık,
	# hafif gölge. Sırası gelen partide kenar hardal.
	var style := UiSkin.card(UiTheme.PANEL_DARK, color.lerp(UiTheme.PANEL_DARK, 0.55), color.lerp(UiTheme.CARD_LIP, 0.55))
	if is_turn:
		style.rings = [[0.0, UiTheme.d(3), UiTheme.GOLD]]
		style.lips = [[UiTheme.d(4), UiTheme.GOLD_DIM]]
	style.shadow_color = Color(0, 0, 0, 0.12)
	style.shadow_offset = Vector2(0, UiTheme.d(6))
	style.shadow_size = UiTheme.d(6)
	style.content_margin_left = UiTheme.d(8)
	style.content_margin_right = UiTheme.d(12)
	style.content_margin_top = UiTheme.d(8)
	style.content_margin_bottom = UiTheme.d(8)
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiTheme.d(12)))
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
		tags.append([L.t("PM") if GovernmentManager.main_gov_peer_id == pid else L.t("HÜK"), UiTheme.GOLD, UiTheme.TEXT_ON_GOLD])
	if mine:
		tags.append([L.t("SEN"), UiTheme.TEAL, UiTheme.ON_COLOR])
	var populism_left := CardManager.populism_rounds_left(pid)
	if populism_left > 0:
		tags.append([L.t("POP"), UiTheme.PURPLE, UiTheme.ON_COLOR])
	for member in members:
		if MultiplayerManager.is_away(int(member)):
			tags.append([L.t("BOT") if MultiplayerManager.away_mode == MultiplayerManager.AWAY_BOT else L.t("PASİF"), UiTheme.RED, UiTheme.ON_COLOR])
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
		tags_width += String(tag[0]).length() * 7.5 + 12.0
	var has_seats: bool = CardManager.last_seats.has(pid)
	var seats_text := str(int(CardManager.last_seats.get(pid, 0))) if has_seats else "—"
	var name_text := L.t("Bağımsız") if independent else String(party.get("name", "?"))
	var inner: float = width - 12.0 - PLAQUE_BADGE - 7.0
	var name_label := _avatar_label(name_text, _fit_font_size(name_text, inner - tags_width - 34.0, UiTheme.fs(23), 9),
		UiTheme.TEXT)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_override("font", UiTheme.mono(true))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	for tag in tags:
		var tag_control := _avatar_tag(String(tag[0]), tag[1], tag[2])
		# Etiketler metnin doğal genişliğiyle plaketi büyütmesin; logo ve
		# parti adına yer bırakıp uzun ittifak adlarını üç noktayla göster.
		var tag_limit := minf(64.0, maxf(22.0, (inner - 50.0) / maxf(1.0, tags.size())))
		(tag_control as Label).clip_text = true
		(tag_control as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tag_control.custom_minimum_size.x = minf(tag_limit, String(tag[0]).length() * 9.0 + 10.0)
		tag_control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tag_control)
	# Vekil sayısı parti renginde, altında koyu sert gölge (konsept .pseats).
	var seats_label := _avatar_label(seats_text, UiTheme.fs(28), color)
	seats_label.add_theme_font_override("font", UiTheme.mono(true))
	seats_label.add_theme_color_override("font_shadow_color", color.lerp(Color.BLACK, 0.55))
	seats_label.add_theme_constant_override("shadow_offset_x", 0)
	seats_label.add_theme_constant_override("shadow_offset_y", int(round(UiTheme.d(2))))
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
	var share_text := (L.t("%%%.1f") % share) if CardManager.last_vote_shares.has(pid) else ""
	var leader := _avatar_label(leader_text, _fit_font_size(leader_text, inner - 44.0, UiTheme.fs(15), 8), UiTheme.TEXT_MUTED)
	leader.clip_text = true
	leader.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	leader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(leader)
	var share_label := _avatar_label(share_text, UiTheme.fs(15), UiTheme.TEXT_MUTED)
	share_label.add_theme_font_override("font", UiTheme.mono_regular())
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
	# Konsept .pbar: içe basık oyuk ve parti renginde, 14+2 px çizgili dolgu.
	var ratio := clampf(share / top_share, 0.0, 1.0) if top_share > 0.0 else 0.0
	bar.draw.connect(func():
		var r := Rect2(Vector2.ZERO, bar.size)
		var rad := r.size.y * 0.5
		var groove := UiSkin.flat(UiTheme.SLOT, int(rad))
		groove.border_color = UiTheme.SLOT.darkened(0.08)
		groove.border_width_top = int(maxf(1.0, UiTheme.d(2)))
		bar.draw_style_box(groove, r)
		if ratio <= 0.0:
			return
		var w := maxf(r.size.y, r.size.x * ratio)
		bar.draw_style_box(UiSkin.flat(color, int(rad)), Rect2(r.position, Vector2(w, r.size.y)))
		var step := UiTheme.d(16)
		var x := step - UiTheme.d(2)
		while x < w - rad:
			bar.draw_rect(Rect2(x, 0, UiTheme.d(2), r.size.y), color.lerp(Color.WHITE, 0.2))
			x += step)
	stack.add_child(bar)

	card.set_meta("peer_id", pid)
	var halo := Panel.new()
	halo.name = L.t("TargetHalo")
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiSkin.apply_style(halo, "panel", UiSkin.color_box(UiTheme.GOLD, UiSkin.TARGET))
	halo.visible = false
	card.add_child(halo)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_target_party_clicked(pid)
	)
	return card

## Konsept .prow: satır 82, aralık 12, pul 46, çubuk 10 (px).
const PLAQUE_BADGE := 46.0 / 1.5
const PLAQUE_BAR := 10.0 / 1.5
const PLAQUE_HEIGHT := 82.0 / 1.5
const PLAQUE_GAP := 12.0 / 1.5

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
	_refresh_pass_button()
	_refresh_hand_interactivity()
	_refresh_action_buttons()
	_refresh_turn_flow_ui()
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

func _refresh_pass_button() -> void:
	var active := CardManager.can_act()
	pass_button.disabled = not active
	UiSkin.skin_action_button(pass_button, ACTION_COLOR_PASS, active)
	_set_action_text(pass_button, L.t("TURU BİTİR"), "")
	# Para bittiyse tur kendiliğinden geçmez; düğme nabız gibi atarak hatırlatır.
	var should_pulse: bool = active and CardManager.funds_of(multiplayer.get_unique_id()) <= 0
	if should_pulse and _pass_pulse == null:
		_pass_pulse = create_tween().set_loops()
		_pass_pulse.tween_property(pass_button, "modulate", Color(1.35, 1.2, 0.6), 0.45).set_trans(Tween.TRANS_SINE)
		_pass_pulse.tween_property(pass_button, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_SINE)
	elif not should_pulse and _pass_pulse != null:
		_pass_pulse.kill()
		_pass_pulse = null
		pass_button.modulate = Color.WHITE

var _pass_pulse: Tween

## Sıra sende değilken eldeki kartlar tıklanamaz + soluk görünür — kullanıcı
## "neden hiçbir şey olmuyor" diye şaşırmasın diye net bir görsel geri bildirim.
func _refresh_hand_interactivity() -> void:
	var interactive := CardManager.can_act()
	for holder in _hand_holders:
		if not is_instance_valid(holder):
			continue
		holder.modulate.a = 1.0 if interactive else 0.55
		for child in holder.find_children("*", "TextureRect", true, false):
			if child.get_meta("is_click_target", false):
				child.mouse_filter = Control.MOUSE_FILTER_STOP

# --- El (envanter) ----------------------------------------------------------

var _built_hand: Array = []
var _hand_built := false
var _built_hand_locale := ""

func _rebuild_hand() -> void:
	# El değişti: bekleyen hedef seçimi artık yanlış karta işaret edebilir.
	_cancel_targeting()
	_selected_hand_index = -1
	if _card_info != null:
		_card_info.hide()
	var hand := CardManager.my_inventory()
	if _hand_built and hand == _built_hand and _built_hand_locale == TranslationServer.get_locale():
		_fit_hand_width(hand.size())
		_refresh_hand_interactivity()
		return
	_built_hand = hand.duplicate()
	_hand_built = true
	_built_hand_locale = TranslationServer.get_locale()
	for child in hand_container.get_children():
		child.queue_free()
	_hand_holders.clear()
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
	# Seçim sonucu ekranına geçilirken paneller DONAR: soldaki liste yeni oy
	# oranına göre sıralanıp sonucu animasyondan önce ele vermesin.
	if _leaving_for_results:
		return
	if is_inside_tree():
		call(name + "_now")
var _live_wait := 0.0

func _process(delta: float) -> void:
	_refresh_countdowns()
	_update_vote_swap(delta)
	_sync_parliament_to_slot()
	_refresh_timer_bar()
	if _smear_ghost != null:
		_update_smear_drag()
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
		# KONSEPT KARTI (.card): krem kart, içte kartın renginde ince çizgi,
		# altında kalınlık ve gölge; görsel üstte yuvarlak köşeli pencerede,
		# adı altta koyu yazıyla. Elde hafif yelpaze açısı.
		holder.remove_child(shadow)
		shadow.queue_free()
		var edge_color := CardPresets.art_edge_color(card_type)
		var face_box := BoardBox.new()
		face_box.fill = UiTheme.PANEL_DARK
		face_box.set_radius(UiTheme.d(12))
		face_box.rings = [[UiTheme.d(5), UiTheme.d(2), edge_color]]
		face_box.lips = [[UiTheme.d(4), Color("D8CAA6")]]
		face_box.shadow_color = Color(0, 0, 0, 0.4)
		face_box.shadow_offset = Vector2(0, UiTheme.d(10))
		face_box.shadow_size = UiTheme.d(9)
		var face_panel := Panel.new()
		face_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face_panel.size = CARD_DISPLAY_SIZE
		face_panel.add_theme_stylebox_override("panel", face_box)
		holder.add_child(face_panel)
		holder.move_child(face_panel, 0)
		var art_rect := Rect2(Vector2(UiTheme.d(12), UiTheme.d(12)),
			CARD_DISPLAY_SIZE - Vector2(UiTheme.d(24), UiTheme.d(66)))
		var clip := Panel.new()
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.position = art_rect.position
		clip.size = art_rect.size
		clip.add_theme_stylebox_override("panel", UiSkin.flat(UiTheme.INK, int(UiTheme.d(6))))
		clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		face_panel.add_child(clip)
		var art := TextureRect.new()
		art.texture = card.texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		clip.add_child(art)
		var title := Label.new()
		title.text = CardPresets.card_short_title(card_type)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		title.add_theme_font_override("font", UiTheme.mono(true))
		title.add_theme_font_size_override("font_size", _hand_title_font_size(CARD_DISPLAY_SIZE.x - UiTheme.d(20)))
		title.add_theme_constant_override("line_spacing", -2)
		title.add_theme_color_override("font_color", UiTheme.INK)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.position = Vector2(UiTheme.d(8), art_rect.end.y + UiTheme.d(2))
		title.size = Vector2(CARD_DISPLAY_SIZE.x - UiTheme.d(16), CARD_DISPLAY_SIZE.y - art_rect.end.y - UiTheme.d(8))
		face_panel.add_child(title)
		# Tıklama yüzeyi kartın tamamı (görselsiz, görünmez).
		card.texture = null
		card.self_modulate = Color(1, 1, 1, 0)
		holder.move_child(card, -1)
		var fan := [-4.0, 3.0, -2.0, 2.5, -3.0, 2.0, -1.5, 3.5]
		holder.pivot_offset = CARD_DISPLAY_SIZE * Vector2(0.5, 1.0)
		holder.rotation_degrees = fan[hand_index % fan.size()]
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
				if _smear_drag_index == hand_index:
					_finish_smear_drag()
				else:
					_on_hand_card_clicked(hand_index)
		elif event is InputEventMouseMotion and card.get_meta("pressed", false) and _smear_drag_index == -1 \
				and card_type == CardPresets.PROPAGANDA_CARD_TYPE and CardManager.can_act():
			if event.position.distance_to(card.get_meta("press_pos", Vector2.ZERO)) > TAP_MAX_MOVE_PX:
				_start_smear_drag(hand_index, card_type, holder)
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

const CARD_RADIUS := 10
## Tam görselli kartın kenar çizgisi.
func _card_art_edge(color: Color) -> Control:
	var edge := Panel.new()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.position = Vector2.ZERO
	edge.size = CARD_DISPLAY_SIZE
	# Krem kart kenarı, içte görselin renginde ince çizgi hissi için kalın kenar.
	var style := UiSkin.ring(UiTheme.PANEL_DARK, 4, CARD_RADIUS)
	style.border_width_bottom = 6
	edge.add_theme_stylebox_override("panel", style)
	var inner := Panel.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.position = Vector2(4, 4)
	inner.size = CARD_DISPLAY_SIZE - Vector2(8, 10)
	inner.add_theme_stylebox_override("panel", UiSkin.ring(Color(color, 0.9), 2, CARD_RADIUS - 4))
	edge.add_child(inner)
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
	if card_type == CardPresets.PROPAGANDA_CARD_TYPE:
		_begin_province_targeting(hand_index)
		_set_target_hint(L.t("Karalama: teşkilatın olan bir ile dokun, sonra rakip partiyi seç  ·  Karta tekrar dokun: iptal"))
		return
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
	UiSkin.apply_style(banner, "panel", style)
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
	if card_type == CardPresets.PROPAGANDA_CARD_TYPE:
		return L.t("Karalama kartını bir ile sürükle ya da karta dokunup ili seç.")
	if CardPresets.is_law_card(card_type):
		return L.t("Yasa şu an meclise getirilemez (meclis yok ya da hükümet kuruluyor).")
	if CardPresets.is_censure_card(card_type):
		return L.t("Gensoruyu sadece muhalefet, hükümet görevdeyken verebilir.")
	return L.t("Bu kart şu an oynanamaz.")

# --- Sürükle-bırak -----------------------------------------------------------

## İmleç haritada hangi ilin üstünde? (Paneller ve alt hazne hariç.)
func _province_under_mouse(mouse: Vector2 = Vector2.INF) -> String:
	if mouse == Vector2.INF:
		mouse = get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	if mouse.x < LEFT_PANEL_WIDTH or mouse.x > viewport_size.x - RIGHT_COLUMN_WIDTH \
			or mouse.y < TOP_STRIP_HEIGHT or mouse.y >= viewport_size.y - CARD_BAR_HEIGHT:
		return ""
	return map_holder.get_province_id_at(map_holder.get_global_transform().affine_inverse() * mouse)

## Fare şu an sağdaki parti panelinde hangi partinin üstünde?
func _party_under_mouse(mouse_pos: Vector2 = Vector2.INF) -> int:
	if mouse_pos == Vector2.INF:
		mouse_pos = get_viewport().get_mouse_position()
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
# --- KARALAMA SÜRÜKLEME (0.0.237): kart bir ile bırakılır, parti listesi açılır ---
var _smear_drag_index := -1
var _smear_ghost: TextureRect

func _start_smear_drag(hand_index: int, card_type: String, holder: Control) -> void:
	_deselect_hand_card()
	_cancel_targeting()
	_smear_drag_index = hand_index
	if holder != null:
		holder.modulate.a = 0.35
	_smear_ghost = TextureRect.new()
	_smear_ghost.texture = CardPresets.get_card_texture(card_type)
	_smear_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_smear_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_smear_ghost.size = CARD_DISPLAY_SIZE * 0.6
	_smear_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_smear_ghost.z_index = 150
	add_child(_smear_ghost)
	_update_smear_drag()

func _update_smear_drag() -> void:
	var mouse := get_viewport().get_mouse_position()
	_smear_ghost.position = mouse - _smear_ghost.size * 0.5
	var province_id := _province_under_mouse()
	var me := multiplayer.get_unique_id()
	var ok := province_id != "" and (CardManager.organization_level(province_id, me) > 0 or PartyManager.is_independent(me))
	_smear_ghost.modulate = Color(1, 1, 1, 0.95) if ok else Color(1, 0.6, 0.6, 0.85)
	if province_id != _hovered_province_id:
		_highlight_province(province_id)
	if province_id == "":
		_set_target_hint(L.t("Karalama: haritada bir ilin üstüne bırak  ·  Başka yere bırak: iptal"))
	elif ok:
		_set_target_hint(L.t("Bırak: %s'da karalama (sonra rakip partiyi seç)") % ElectionNightSim.province_name(province_id))
	else:
		_set_target_hint(L.t("%s'da teşkilatın yok: karalama teşkilat ister") % ElectionNightSim.province_name(province_id))

func _finish_smear_drag() -> void:
	var hand_index := _smear_drag_index
	var province_id := _province_under_mouse()
	_smear_drag_index = -1
	if _smear_ghost != null:
		_smear_ghost.queue_free()
		_smear_ghost = null
	_set_target_hint("")
	_highlight_province("")
	_rebuild_hand()
	if province_id != "":
		_ask_propaganda_target(hand_index, province_id)

func _begin_province_targeting(hand_index: int) -> void:
	_pending_province_hand_index = hand_index
	# Harita tıklanabilir kalsın: açık il paneli haritanın üstünü kapatmasın.
	if _province_panel != null:
		_province_panel.hide()
	var card_type: String = CardManager.my_inventory()[hand_index]
	_set_target_hint(L.t("%s: haritada bir ile dokun (ayrıntı görünür), tekrar dokun: oyna  ·  Karta tekrar dokun: iptal") % CardPresets.card_title(card_type))

func _cancel_targeting() -> void:
	_pending_province_hand_index = -1
	if _focus_panel != null:
		_focus_panel.hide()
	_miting_focus = []
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
	if _pending_miting and _focus_panel != null and _focus_panel.visible:
		_on_focus_confirmed()
		return
	if _pending_invest:
		_on_funding_confirmed()
		return
	if _pending_miting:
		var focus := _miting_focus.duplicate()
		_cancel_targeting()
		if CardManager.can_miting(me, province_id):
			CardManager.miting(province_id, 0.0, focus)
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
	if _pending_province_hand_index == -1 and _pending_target_hand_index == -1 and _can_open_province_actions():
		_open_province_actions(province_id)
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
var _hover_info_drag_scroll: ScrollContainer

## Hovering a province or party scrolls its inspector, before the source list
## can consume the wheel. Direct scrolling over the inspector stays native.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			if _hover_info_drag_scroll != null:
				_hover_info_drag_scroll = null
				get_viewport().set_input_as_handled()
			return
		if event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_MIDDLE]:
			return
		var scroll := _hover_info_scroll_target(event.position)
		if scroll == null:
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_hover_info_drag_scroll = scroll
		elif event.pressed:
			_scroll_hover_info(scroll, 0.0, event.factor * (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _hover_info_drag_scroll != null:
		if _hover_info_scroll_valid(_hover_info_drag_scroll):
			_scroll_hover_info(_hover_info_drag_scroll, -event.relative.y)
			get_viewport().set_input_as_handled()
		else:
			_hover_info_drag_scroll = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_hover_info_drag_scroll = null

func _hover_info_scroll_valid(scroll: ScrollContainer) -> bool:
	return is_instance_valid(scroll) and not scroll.is_queued_for_deletion() and scroll.is_visible_in_tree()

func _hover_info_scroll_target(mouse: Vector2 = Vector2.INF) -> ScrollContainer:
	if _window_mode() or not is_visible_in_tree() or _leaving_for_results or _layer_switching \
			or _pending_org or _pending_miting or _pending_invest or _pending_province_hand_index != -1 \
			or _pending_target_hand_index != -1 or _smear_ghost != null:
		return null
	if mouse == Vector2.INF:
		mouse = get_viewport().get_mouse_position()
	# Respect menus, modal overlays and other controls covering the source.
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != self and hovered.get_global_rect().has_point(mouse) \
			and not (_board_scroll != null and (hovered == _board_scroll or _board_scroll.is_ancestor_of(hovered))):
		return null
	_update_live_province(mouse)
	var party := _party_under_mouse(mouse)
	if party != -1 and party == _profile_peer_id and _hover_info_scroll_valid(_profile_scroll):
		return _profile_scroll
	var province := _province_under_mouse(mouse)
	if province != "" and _province_panel != null and _province_panel.embedded_mode \
			and _province_panel.visible and _province_panel.province_id == province \
			and _hover_info_scroll_valid(_province_panel._scroll):
		return _province_panel._scroll
	return null

func _scroll_hover_info(scroll: ScrollContainer, amount: float, wheel_factor: float = 0.0) -> void:
	if not _hover_info_scroll_valid(scroll):
		return
	# A wheel event may open the inspector before its first layout is complete.
	if scroll.get_v_scroll_bar().page <= 0.0:
		await get_tree().process_frame
		if not _hover_info_scroll_valid(scroll):
			return
	var bar := scroll.get_v_scroll_bar()
	if wheel_factor != 0.0:
		var step := bar.custom_step if bar.custom_step > 0.0 else maxf(1.0, bar.page / 8.0)
		amount = step * wheel_factor
	bar.value = clampf(bar.value + amount, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))

func _update_live_province(mouse: Vector2 = Vector2.INF) -> void:
	if _hover_info_scroll_valid(_hover_info_drag_scroll):
		return  # Middle-button dragging keeps the original inspector under control.
	if _window_mode() or _pinned:
		return
	if _pending_org or _pending_miting or _pending_invest or _pending_province_hand_index != -1 			or _pending_target_hand_index != -1 or _layer_switching or not is_visible_in_tree():
		return
	if mouse == Vector2.INF:
		mouse = get_viewport().get_mouse_position()
	# Fare sağ paneldeyse açık olan bilgi kalır (kaydırılabilsin).
	if left_panel.get_global_rect().has_point(mouse):
		return
	var party := _party_under_mouse(mouse)
	if party != -1:
		if _profile_peer_id != party:
			_profile_peer_id = party
			_show_tooltip_for(party)
		return
	var province_id := _province_under_mouse(mouse)
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

## Mitingin bu ildeki en büyük üç grup hitap kazancı (gerçek kuralla:
## yorgunluk, odak, çekirdek çarpanı ve azalan getiri dahil): " · hitap: Emekliler +%1,2, ...".
func _miting_group_preview(me: int, province_id: String, focus: Array = []) -> String:
	var gains := _miting_gain_list(me, province_id, focus)
	var parts: PackedStringArray = []
	for item in gains.slice(0, 3):
		parts.append("%s +%%%s" % [VoterGroups.title(String(item["group"])), _one_decimal(float(item["delta"]))])
	if parts.is_empty():
		return L.t(" · grup desteğine etkisi yok")
	return L.t(" · hitap: ") + ", ".join(parts)

## [{"group", "delta"}] büyükten küçüğe: mitingin gerçekleşecek hitap kazançları.
func _miting_gain_list(me: int, province_id: String, focus: Array = []) -> Array:
	var pid := CardManager.party_of(me)
	var groups := PartyManager.groups_of(pid)
	var core: Array = PartyManager.data_of(pid).get("core", [])
	var result: Array = []
	for effect in CardManager.miting_group_gains(me, province_id, focus):
		var delta := VoterGroups.effective_delta(groups, String(effect["group"]), float(effect["gain"]), core)
		if delta >= 0.05:
			result.append({"group": String(effect["group"]), "delta": delta})
	result.sort_custom(func(a, b): return float(a["delta"]) > float(b["delta"]))
	return result

## MİTİNG ODAĞI paneli: ildeki teşkilat seviyesi kadar grup seçilir; her grupta
## ildeki seçmen payı ve mitingin o gruba hitap kazancı görünür.
func _open_focus_panel(province_id: String) -> void:
	if _focus_panel == null:
		_focus_panel = PanelContainer.new()
		var style := UiSkin.stylebox(UiSkin.PANEL)
		style.set_content_margin_all(UiTheme.PAD_M)
		_focus_panel.add_theme_stylebox_override("panel", style)
		_focus_panel.z_index = 108
		_focus_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_focus_box = VBoxContainer.new()
		_focus_box.add_theme_constant_override("separation", 6)
		_focus_box.custom_minimum_size = Vector2(404, 0)
		_focus_panel.add_child(_focus_box)
		add_child(_focus_panel)
	_focus_province = province_id
	_fill_focus_panel()
	_focus_panel.show()
	_place_focus_panel.call_deferred()

func _fill_focus_panel() -> void:
	for child in _focus_box.get_children():
		_focus_box.remove_child(child)
		child.queue_free()
	var me := multiplayer.get_unique_id()
	var province_id := _focus_province
	var slots := CardManager.miting_focus_slots(me, province_id)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_focus_box.add_child(header)
	var title := UiTheme.mono_label(L.t("MİTİNG ODAĞI · %s") % ElectionNightSim.province_name(province_id), 14, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(PopupKit.chip(L.t("%d / %d grup") % [_miting_focus.size(), slots], UiTheme.GOLD))
	_focus_box.add_child(PopupKit.note(L.t("Teşkilat seviyesi %d: en çok %d gruba odaklanabilirsin. Odak gruplarda kazanç %s kat; seçmezsen odaksız miting.") % [
		slots, slots, _one_decimal(PublicOpinion.MITING_FOCUS_MULT)], UiTheme.TEXT_MUTED, 380))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_focus_box.add_child(grid)
	var profile := CardManager.province_profile(province_id)
	for group in VoterGroups.GROUP_IDS:
		grid.add_child(_focus_group_button(group, VoterGroups.share(profile, group), slots))
	_focus_box.add_child(PopupKit.note(L.t("Beklenen hitap:%s") % _miting_group_preview(me, province_id, _miting_focus).trim_prefix(L.t(" · hitap:")), UiTheme.GREEN, 380))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_focus_box.add_child(buttons)
	var ok := Button.new()
	ok.focus_mode = Control.FOCUS_NONE
	ok.text = L.t("ONAYLA · %s") % GameRules.cost_text(GameRules.MITING_FUNDS_COST)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.custom_minimum_size = Vector2(0, 32)
	UiSkin.skin_color_button(ok, UiTheme.GREEN_DARK)
	ok.pressed.connect(_on_focus_confirmed)
	buttons.add_child(ok)
	var cancel := Button.new()
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.text = L.t("İptal")
	cancel.custom_minimum_size = Vector2(0, 32)
	UiSkin.skin_button(cancel)
	cancel.pressed.connect(_cancel_targeting)
	buttons.add_child(cancel)

## Odak paneli düğmesi: simge + tam ad + ildeki pay; seçiliyse altın yazı ve
## parlak zemin. Odak dolduysa seçili olmayanlar sönük.
func _focus_group_button(group: String, share: float, slots: int) -> Control:
	var selected := _miting_focus.has(group)
	var full := _miting_focus.size() >= slots and not selected
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(196, 30)
	var tint := VoterGroups.color(group)
	UiSkin.skin_color_button(button, tint.darkened(0.15) if selected else tint.darkened(0.45))
	button.modulate.a = 0.45 if full else 1.0
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -6
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon := VoterGroupIcon.make(group, 18.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Label.new()
	label.text = ("• " if selected else "") + VoterGroups.title(group)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", UiTheme.HEAD if selected else UiTheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var pct := Label.new()
	pct.text = "%" + str(int(roundf(share * 100.0)))
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pct.add_theme_font_size_override("font_size", 9)
	pct.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pct)
	button.pressed.connect(func():
		if _miting_focus.has(group):
			_miting_focus.erase(group)
		elif _miting_focus.size() < slots:
			_miting_focus.append(group)
		_fill_focus_panel()
		_place_focus_panel.call_deferred())
	return button

func _place_focus_panel() -> void:
	if _focus_panel == null or not _focus_panel.visible:
		return
	_focus_panel.reset_size()
	var map := _r(R_MAP)
	var panel_size := _focus_panel.size
	_focus_panel.position = Vector2(map.position.x + (map.size.x - panel_size.x) * 0.5,
		maxf(map.position.y + 40.0, map.end.y - panel_size.y - 8.0))

## Odak onaylandı: hükümet partisi devlet payı seçebiliyorsa finansman paneli
## açılır, değilse miting hemen yapılır.
func _on_focus_confirmed() -> void:
	var me := multiplayer.get_unique_id()
	var province_id := _selected_province
	_focus_panel.hide()
	if province_id == "":
		_cancel_targeting()
		return
	var focus := _miting_focus.duplicate()
	_cancel_targeting()
	if CardManager.can_miting(me, province_id):
		CardManager.miting(province_id, 0.0, focus)
	else:
		_show_toast(_action_block_reason(GameRules.MITING_FUNDS_COST))

## Hedef seçme modunda dokunulan il: vurgulanır, üstte ne olacağı yazar.
func _select_target_province(province_id: String) -> void:
	_selected_province = province_id
	_highlight_province(province_id)
	var me := multiplayer.get_unique_id()
	var pname := ElectionNightSim.province_name(province_id)
	var detail := ""
	if _pending_miting:
		_miting_focus = []
		if CardManager.miting_focus_slots(me, province_id) > 0:
			_open_focus_panel(province_id)
			_set_target_hint(L.t("%s: odak gruplarını seç, ONAYLA'ya bas (ya da ile tekrar dokun)  ·  Butona tekrar dokun: iptal") % pname)
			return
		if _focus_panel != null:
			_focus_panel.hide()
	if _pending_invest:
		detail = _invest_preview(pname)
	elif _pending_miting:
		detail = L.t("%s: miting (%s) · provokasyon: %s%s") % [pname, GameRules.cost_text(GameRules.MITING_FUNDS_COST),
			EffectWords.risk(CardManager.miting_risk(me, province_id)), _miting_group_preview(me, province_id)]
	elif _pending_org:
		var level := CardManager.organization_level(province_id, me)
		detail = L.t("%s: teşkilat zaten en üst seviyede") % pname if level >= GameRules.ORG_MAX_LEVEL \
			else L.t("%s: teşkilat seviye %d » %d (%s) · %s") % [pname, level, level + 1, GameRules.cost_text(CardManager.org_cost_for(me, province_id)), _org_level_text(level + 1)]
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
	_target_hint.add_theme_color_override("font_color", UiTheme.HEAD)
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
	var accent := UiTheme.RED if CardPresets.needs_target(card_type) else UiTheme.BLUE
	var parts := PopupKit.frame(300.0, accent, _card_info)
	var box: VBoxContainer = parts[1]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiTheme.mono_label(CardPresets.card_title(card_type), PopupKit.FS_TITLE - 2, UiTheme.TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	box.add_child(head)
	if not effect.is_empty():
		box.add_child(PopupKit.note(" ".join(effect), UiTheme.TEXT, 276.0))
	if not usage.is_empty():
		box.add_child(PopupKit.note(" ".join(usage), UiTheme.HEAD, 276.0))
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

	# Deste yok: kart sağ alttaki para levhasının üstünden gelir.
	var deck_rect := _funds_plate.get_global_rect() if _funds_plate != null else Rect2(get_viewport_rect().size - Vector2(180, 180), CARD_DISPLAY_SIZE)
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
	if CardManager.is_anonymous_card(card_type):
		if peer_id == multiplayer.get_unique_id():
			_show_toast(L.t("Gizli hamle uygulandı. Haber tur sonunda yayınlanacak."))
		return
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
	UiSkin.apply_style(card, "panel", style)

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
		tags.append([L.t("POP"), UiTheme.PURPLE, UiTheme.ON_COLOR])
	if PartyManager.is_deputy(peer_id):
		tags.append([L.t("YRD"), color, UiTheme.TEXT])
	elif PartyManager.deputy_of(peer_id) != -1:
		tags.append([L.t("GB"), color, UiTheme.TEXT])
	var tags_width := 0.0
	for tag in tags:
		tags_width += String(tag[0]).length() * 7.5 + 12.0
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
	UiSkin.apply_style(halo, "panel", UiSkin.color_box(UiTheme.GOLD, UiSkin.TARGET))
	halo.visible = false
	card.add_child(halo)
	if is_turn:
		var frame := Panel.new()
		frame.name = L.t("TurnFrame")
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiSkin.apply_style(frame, "panel", UiSkin.color_box(UiTheme.TEXT, UiSkin.TARGET))
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
	UiSkin.apply_style(_left_dock, "panel", StyleBoxEmpty.new())
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

func _avatar_tag(text: String, bg: Color, _fg: Color) -> Control:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_override("font", UiTheme.mono(true))
	tag.add_theme_font_size_override("font_size", UiTheme.fs(13))
	# Yazı rengi zemine göre (açık zeminde koyu, koyu zeminde beyaz).
	tag.add_theme_color_override("font_color", UiSkin.text_on(bg))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Konsept .tagx: köşesi 6 px hap, altında 2 px koyu kalınlık.
	var style := BoardBox.new()
	style.fill = bg
	style.set_radius(UiTheme.d(6))
	style.lips = [[UiTheme.d(2), bg.lerp(Color.BLACK, 0.3)]]
	style.content_margin_left = UiTheme.d(6)
	style.content_margin_right = UiTheme.d(6)
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
## Meclis oy düğmesi hamle düğmesiyle aynı: iki satır (ad + kısa açıklama),
## aynı yazı ölçümü, aynı renkli zemin; simge yok.
func _style_vote_button(button: Button, title: String, subtitle: String, color: Color) -> void:
	button.icon = null
	button.custom_minimum_size = Vector2(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_constant_override("line_spacing", -1)
	_set_action_text(button, title, subtitle)
	button.set_meta("action_color", color)
	UiSkin.skin_action_button(button, color, true)

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
	proposal_label.visible = GovernmentManager.is_voting() and GovernmentManager.proposal_kind != GovernmentManager.KIND_LAW
	_refresh_proposer_chip()
	# Oylama sürerken özet satırının yerinde EVET / HAYIR çubuğu.
	if _vote_bar != null:
		var voting := GovernmentManager.is_voting()
		_vote_bar.visible = voting
		if _parl_summary != null:
			_parl_summary.visible = not voting
		if voting:
			_vote_bar.refresh()

## TEKLİFİ VEREN PARTİ: yasa/gensoru/hükümet oylamasında meclis diyagramının
## köşesinde logosu ve adıyla durur. Eskiden bu bilgi diyagramın altındaki
## uzun ipucu satırındaydı.
func _refresh_proposer_chip() -> void:
	if _proposer_chip == null:
		_proposer_stack = VBoxContainer.new()
		_proposer_stack.add_theme_constant_override("separation", 4)
		_proposer_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_proposer_stack.position = Vector2(6, 6)
		parliament_diagram.add_child(_proposer_stack)
		_proposer_chip = _corner_chip()
		_proposer_row = _proposer_chip.get_child(0)
		_proposer_stack.add_child(_proposer_chip)
		# 0.0.268: yasanın seçmen grubu, getiren partinin kartının altında
		# birebir aynı kartta.
		_law_group_chip = _corner_chip()
		_proposer_stack.add_child(_law_group_chip)
	var peer_id := GovernmentManager.proposal_peer_id
	var active: bool = GovernmentManager.is_voting() and peer_id != -1
	_proposer_stack.visible = active
	if not active:
		return
	# TEK SATIR ve DAR: yarım dairenin üstünde kalan boş şerit ancak bu kadar
	# yer bırakıyor, daha yükseği koltukların üstüne biniyor.
	_fill_corner_chip(_proposer_chip, PartyBadge.build(PartyManager.data_of(peer_id),
		Vector2(22, 22), BADGE_ICON_PIXEL_SIZE), _party_name_of(peer_id))
	var law := CardPresets.law_data(GovernmentManager.proposal_law) 		if GovernmentManager.proposal_kind == GovernmentManager.KIND_LAW else {}
	_law_group_chip.visible = not law.is_empty()
	if not law.is_empty():
		_fill_corner_chip(_law_group_chip, VoterGroupIcon.make(String(law["group"]), 22.0), String(law["group_title"]))
	_proposer_stack.reset_size()

var _proposer_stack: VBoxContainer
var _law_group_chip: PanelContainer

func _corner_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiSkin.stylebox(UiSkin.SLOT)
	style.set_content_margin_all(6)
	UiSkin.apply_style(chip, "panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	return chip

func _fill_corner_chip(chip: PanelContainer, icon: Control, text: String) -> void:
	var row := chip.get_child(0)
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.clip_text = true
	label.custom_minimum_size = Vector2(72, 22)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	chip.reset_size()

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

## Hamle düğmelerinin ortak puntosu (MECLİS, İTTİFAK, KONGRE, TURU BİTİR).
## Konsept .act: 32 px.
const ACTION_FONT_SIZE := 21
## Kasa rengi: dolar banknotunun koyu yeşili (0.0.242).
const FUNDS_COLOR := UiTheme.GREEN_DARK
const EMPTY_SEAT_COLOR := UiTheme.TEXT

## Sağ sütunun alt kısmı (aşağıdan yukarı): sıra göstergesi, pas, deste ve
## yanında YASA TASARLA / İL BAŞKANLIĞI butonları, para. Parti kartları üstte
## kalan alana sığar.
func _place_right_column_controls() -> void:
	# MASANIN SAĞI: parti kasası (Turu Bitir hamleler alanında).
	if _funds_plate != null:
		_set_rect(_funds_plate, _r(R_FUNDS))

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
	# Konsept .money: karton pano (çift kalınlık, içte deniz yeşili çizgi),
	# büyük yeşil tutar ve altında "PARTİ KASASI".
	var funds_style := UiSkin.board()
	funds_style.rings = [[UiTheme.d(5), UiTheme.d(2), UiTheme.TEAL]]
	funds_style.dot_radius = 0.0
	funds_style.set_content_margin_all(UiTheme.d(10))
	_funds_plate.add_theme_stylebox_override("panel", funds_style)
	add_child(_funds_plate)
	var funds_column := VBoxContainer.new()
	funds_column.alignment = BoxContainer.ALIGNMENT_CENTER
	funds_column.add_theme_constant_override("separation", int(UiTheme.d(2)))
	funds_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_funds_plate.add_child(funds_column)
	_funds_box = HBoxContainer.new()
	_funds_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_funds_box.add_theme_constant_override("separation", int(UiTheme.d(8)))
	_funds_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	funds_column.add_child(_funds_box)
	var dollar := Label.new()
	dollar.text = "$"
	dollar.add_theme_font_override("font", UiTheme.mono(true))
	dollar.add_theme_font_size_override("font_size", UiTheme.fs(50))
	dollar.add_theme_color_override("font_color", FUNDS_COLOR)
	dollar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_funds_box.add_child(dollar)
	_funds_label = Label.new()
	_funds_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_funds_label.add_theme_font_override("font", UiTheme.mono(true))
	_funds_label.add_theme_font_size_override("font_size", UiTheme.fs(50))
	_funds_label.add_theme_color_override("font_color", FUNDS_COLOR)
	_funds_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_funds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_funds_box.add_child(_funds_label)
	var caption := Label.new()
	caption.text = L.t("PARTİ KASASI")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_override("font", UiTheme.mono_regular())
	caption.add_theme_font_size_override("font_size", UiTheme.fs(13))
	caption.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	funds_column.add_child(caption)
	_funds_plate.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_toast(_funds_rules))
	_funds_rules = L.t("PARTİ KASASI: bağış ve aidatlar her sıranda %s (hükümetteysen %s), teşkilatların yerel bağışları ve seçim sonrası hazine yardımı. Kasan yettikçe istediğin kadar hamle yap; para birikir.\nDEVLET HAZİNESİ ayrıdır: onu sadece hükümet, yatırım için kullanır.") % [
		GameRules.cost_text(GameRules.FUNDS_PER_ROUND), GameRules.cost_text(GameRules.FUNDS_PER_ROUND_GOVERNMENT)]
	# HAMLELER: 3 sütun x 2 satır IZGARA. Eskiden her buton tek tek mutlak
	# konuma oturtuluyordu; uzun bir yazı (TEŞKİLATLANMA) butonun asgari
	# genişliğini büyütünce komşusunun üstüne biniyordu. Izgara bunu yapısal
	# olarak önler.
	# HAMLELER (0.0.231): eski SAHA / MECLİS / PARTİ / SİYASET sekmeleri yok.
	# MECLİS tek giriş (gensoru, yasa); İTTİFAK ve
	# KONGRE yerinde. Teşkilat, miting ve yatırım haritadaki il panelinden,
	# afet yardımı tur başındaki sahneden yapılır.
	_parl_button = Button.new()
	_parl_button.focus_mode = Control.FOCUS_NONE
	_parl_button.custom_minimum_size = Vector2(0, ACTION_BUTTON_HEIGHT)
	_parl_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parl_button.clip_text = true
	_parl_button.set_meta("action_color", ACTION_COLOR_LAW)
	_parl_button.add_theme_font_override("font", UiTheme.mono(true))
	_parl_button.add_theme_font_size_override("font_size", ACTION_FONT_SIZE)
	_parl_button.pressed.connect(_on_parliament_button_pressed)
	actions_vbox.add_child(_parl_button)
	_action_grid = GridContainer.new()
	_action_grid.columns = 3
	_action_grid.add_theme_constant_override("h_separation", ACTION_BUTTON_GAP)
	_action_grid.add_theme_constant_override("v_separation", ACTION_BUTTON_GAP)
	actions_vbox.add_child(_action_grid)
	_alliance_button = _action_button(L.t("İTTİFAK"), "", ACTION_COLOR_ALLIANCE)
	_alliance_button.pressed.connect(_on_alliance_button_pressed)
	# YARDIM (0.0.260): kongre şimdilik kapalı, yerinde afet yardımı. Afet
	# sürerken sıranda istediğin kadar (üst üste de) yardım götürebilirsin.
	# KONGRE düğmesi CardManager.congress_enabled açıkken geri gelir.
	if CardManager.congress_enabled:
		_congress_button = _action_button(L.t("KONGRE"), _congress_cost_text(), ACTION_COLOR_CONGRESS)
		_congress_button.pressed.connect(_on_congress_button_pressed)
	else:
		_aid_button = _action_button(L.t("YARDIM"), "", ACTION_COLOR_AID)
		_aid_button.pressed.connect(_on_aid_button_pressed)
	# TURU BİTİR: sahnedeki düğme hamle ızgarasına taşınır, hamle düğmesi görünümünde.
	pass_button.get_parent().remove_child(pass_button)
	pass_button.custom_minimum_size = Vector2(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
	pass_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_button.clip_text = true
	pass_button.icon = null
	pass_button.set_meta("action_color", ACTION_COLOR_PASS)
	_action_grid.add_child(pass_button)
	_action_tab_of[pass_button] = 0
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions_vbox.add_child(filler)

## Kongre bedeli oyuncunun yerine göre: genel başkan 10, üye 20.
func _congress_cost_text() -> String:
	var me := multiplayer.get_unique_id()
	var cost := CardManager.CONGRESS_REQUEST_COST if CardManager.is_party_member(me) else CardManager.CONGRESS_COST
	return GameRules.cost_text(cost)

## Hamle butonu: ızgaraya eklenir, sabit kutu boyutunda kalır ve yazı taşarsa
## kırpılır — böylece hiçbir buton komşusunu itemez.
func _action_button(title: String, cost_text: String, color: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_constant_override("line_spacing", -1)
	_set_action_text(button, title, cost_text)
	button.set_meta("action_color", color)
	UiSkin.skin_action_button(button, color, true)
	_action_grid.add_child(button)
	_action_tab_of[button] = 0
	return button

## Sekme düğmesi (hamle ve yasa sekmeleri): harita katman düğmeleri gibi kare,
## seçili olan altın; lit false ise yazı sönük.
func _style_tab_button(button: Button, active: bool, lit: bool) -> void:
	var style_key := [active, lit]
	if button.get_meta("game_tab_key", []) == style_key:
		return
	button.set_meta("game_tab_key", style_key)
	UiSkin.skin_tab(button, active)
	button.add_theme_font_size_override("font_size", UiTheme.fs(19))
	button.custom_minimum_size.y = PLAYER_TAB_HEIGHT
	if not lit and not active:
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(key, UiTheme.TEXT_DIM)

## Hamle düğmesinin iki satırı (ad + bedel). DAR KUTUYA SIĞSIN: en uzun satır
## düğmeye sığana kadar yazı küçülür (İngilizce "EARLY ELECTION" gibi; ad
## kısaltılmaz).
func _set_action_text(button: Button, title: String, cost_text: String) -> void:
	var text_key := [title, cost_text, button.size.x, _r(R_ACTIONS).size.x, TranslationServer.get_locale()]
	if button.get_meta("action_text_key", []) == text_key:
		_sync_action_text(button)
		return
	button.set_meta("action_text_key", text_key)
	# Konsept .act: başlık Siyaset Display 32 px, alt satır Nunito 800 18 px;
	# ikisi de yüzün ortasında, basınca yüzle birlikte iner.
	button.text = ""
	var box := button.get_node_or_null("ActionText") as VBoxContainer
	if box == null:
		box = VBoxContainer.new()
		box.name = "ActionText"
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(box)
		for key in ["Title", "Sub"]:
			var label := Label.new()
			label.name = key
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_override("font", UiTheme.mono(true) if key == "Title" else UiTheme.mono_regular())
			box.add_child(label)
		var shift := func(y: float): box.position.y = y
		button.button_down.connect(shift.bind(UiTheme.d(7)))
		button.button_up.connect(func(): box.position.y = -UiTheme.d(2) if button.is_hovered() else 0.0)
		button.mouse_entered.connect(func(): box.position.y = UiTheme.d(7) if button.button_pressed else -UiTheme.d(2))
		button.mouse_exited.connect(shift.bind(0.0))
	var head := box.get_node("Title") as Label
	var sub := box.get_node("Sub") as Label
	head.text = title
	sub.text = cost_text
	sub.visible = cost_text != ""
	var cell := (_r(R_ACTIONS).size.x - ACTION_BUTTON_GAP * 2.0) / 3.0
	var width := maxf(button.size.x, maxf(ACTION_BUTTON_WIDTH, cell)) - UiTheme.d(20)
	var font := UiTheme.mono(true)
	var size := ACTION_FONT_SIZE
	while size > 8 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	head.add_theme_font_size_override("font_size", size)
	var sub_size := UiTheme.fs(18)
	while sub_size > 7 and UiTheme.mono_regular().get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x > width:
		sub_size -= 1
	sub.add_theme_font_size_override("font_size", sub_size)
	_sync_action_text(button)

## Düğmenin yazı rengi ve sert gölgesi alt etiketlere de geçer.
func _sync_action_text(button: Button) -> void:
	var box := button.get_node_or_null("ActionText")
	if box == null:
		return
	var ink := button.get_theme_color("font_color")
	var shadow := button.get_theme_color("font_shadow_color")
	for label in box.get_children():
		(label as Label).add_theme_color_override("font_color", ink)
		(label as Label).add_theme_color_override("font_shadow_color", shadow if label.name == "Title" else Color(0, 0, 0, 0))
		(label as Label).add_theme_constant_override("shadow_offset_y", int(round(UiTheme.d(3))))
		(label as Label).add_theme_constant_override("shadow_offset_x", 0)

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
	if _parl_button == null:
		return
	var me := multiplayer.get_unique_id()
	# "190 M": simge levhanın solunda (CoinIcon), yazıda tekrar etmez.
	_funds_label.text = GameRules.amount(CardManager.funds_of(me))
	# disabled kullanılmıyor: pasif butona dokununca neden olmadığı uyarı olarak çıksın.
	if _congress_button != null:
		_set_action_available(_congress_button, CardManager.can_call_congress(me) or _pending_congress)
		_set_action_text(_congress_button, L.t("KONGRE"), _congress_cost_text())
	if _aid_button != null:
		_set_action_available(_aid_button, CardManager.can_aid(me))
		_set_action_text(_aid_button, L.t("YARDIM"), L.t("afet var") if CardManager.has_disaster() else "")
	if _alliance_button != null:
		_set_action_available(_alliance_button, CardManager.alliances_enabled)
		var decisions := CardManager.alliance_requests_for(me).size()
		_set_action_text(_alliance_button, L.t("İTTİFAK"), (L.t("%d karar bekliyor") % decisions) if decisions > 0 else "")
	if _alliance_panel != null and _alliance_panel.visible:
		_refresh_alliance_panel()
	_refresh_parliament_button()

func _build_agenda_banner() -> void:
	_agenda_banner = PanelContainer.new()
	var style := UiSkin.color_box(UiTheme.GOLD.darkened(0.45), UiSkin.BUTTON_TINT_NORMAL)
	style.set_content_margin_all(UiTheme.PAD_S)
	UiSkin.apply_style(_agenda_banner, "panel", style)
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
	_agenda_label.text = L.t("KRİZ: %s\n%s") % [data["title"], CardPresets.agenda_effect_text(current)]

## İTTİFAK PENCERESİ (0.0.249): MECLİS penceresiyle aynı dil — ortada,
## karartılmış zemin üstünde, aynı çerçeve ve gölge; üstte sekmeler
## (İTTİFAKLAR · YENİ İTTİFAK), altta "Haritaya dön".
const ALLIANCE_WIDTH := 640.0
var _alliance_dim: ColorRect
var _alliance_tab := 0
var _alliance_tab_buttons: Array = []
var _alliance_pages: Array = []

func _build_alliance_panel() -> void:
	_alliance_dim = ColorRect.new()
	_alliance_dim.color = Color(0.03, 0.02, 0.08, 0.4)
	_alliance_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_alliance_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_alliance_dim.z_index = 114
	_alliance_dim.hide()
	_alliance_dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_alliance_panel.hide())
	add_child(_alliance_dim)
	_alliance_panel = PanelContainer.new()
	var style := UiSkin.board()
	style.set_content_margin_all(UiTheme.PAD_L)
	_alliance_panel.add_theme_stylebox_override("panel", style)
	_alliance_panel.z_index = 115
	_alliance_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_alliance_panel.visibility_changed.connect(func(): _alliance_dim.visible = _alliance_panel.visible)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(ALLIANCE_WIDTH, 0)
	_alliance_panel.add_child(box)
	# SEKMELER (meclis penceresindeki gibi).
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	_alliance_tab_buttons.clear()
	_alliance_pages.clear()
	for i in 2:
		var tab := Button.new()
		tab.text = [L.t("İTTİFAKLAR"), L.t("YENİ İTTİFAK")][i]
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 38)
		tab.add_theme_font_override("font", UiTheme.mono(true))
		tab.add_theme_font_size_override("font_size", 14)
		tab.pressed.connect(func():
			_alliance_tab = i
			_refresh_alliance_panel()
			_place_alliance_panel.call_deferred())
		tabs.add_child(tab)
		_alliance_tab_buttons.append(tab)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		box.add_child(page)
		_alliance_pages.append(page)
	# 1) İTTİFAKLAR: kurallar ve kart kart ittifaklar (kararlarım en üstte).
	var list_page: VBoxContainer = _alliance_pages[0]
	list_page.add_child(_alliance_note(L.t("Barajda ortak oy sayılır; her ilde ittifakın vekilleri üyelerin oyuna göre paylaşılır. Katılmak için bütün üyeler onaylamalı, davet yalnız liderden (•) gelir. İttifaklar seçimden sonra dağılır."), UiTheme.TEXT_MUTED))
	_alliance_list = VBoxContainer.new()
	_alliance_list.add_theme_constant_override("separation", 8)
	_alliance_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(ALLIANCE_WIDTH, 300)
	scroll.add_child(_alliance_list)
	list_page.add_child(scroll)
	# 2) YENİ İTTİFAK: ad, renk, KUR.
	var create_page: VBoxContainer = _alliance_pages[1]
	create_page.add_child(_alliance_note(L.t("İttifakı sen kurarsan lideri olursun: diğer partileri sen davet edersin."), UiTheme.TEXT_MUTED))
	create_page.add_child(UiTheme.mono_label(L.t("İTTİFAK ADI"), 13, UiTheme.HEAD, true))
	_alliance_name = LineEdit.new()
	_alliance_name.placeholder_text = L.t("İttifak adı")
	_alliance_name.max_length = 28
	_alliance_name.custom_minimum_size = Vector2(0, 46)
	_alliance_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_page.add_child(_alliance_name)
	create_page.add_child(UiTheme.mono_label(L.t("RENK"), 13, UiTheme.HEAD, true))
	var palette := GridContainer.new()
	var color_count: int = PartyPresets.COLORS.size()
	palette.columns = int(ceil(color_count / 2.0))
	palette.add_theme_constant_override("h_separation", 6)
	palette.add_theme_constant_override("v_separation", 6)
	create_page.add_child(palette)
	var swatch_side := floorf((ALLIANCE_WIDTH - 6.0 * (palette.columns - 1)) / palette.columns)
	for color in PartyPresets.COLORS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(swatch_side, 40)
		swatch.toggle_mode = true
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.set_meta("color", color)
		UiSkin.skin_color_button(swatch, color)
		swatch.pressed.connect(func():
			_alliance_color = color
			_refresh_alliance_palette())
		palette.add_child(swatch)
		_alliance_swatches.append(swatch)
	_alliance_create_button = Button.new()
	_alliance_create_button.text = L.t("İTTİFAKI KUR")
	_alliance_create_button.focus_mode = Control.FOCUS_NONE
	_alliance_create_button.custom_minimum_size = Vector2(0, 56)
	_alliance_create_button.add_theme_font_override("font", UiTheme.mono(true))
	_alliance_create_button.add_theme_font_size_override("font_size", 17)
	UiSkin.skin_color_button(_alliance_create_button, UiTheme.GREEN_DARK)
	_alliance_create_button.pressed.connect(_on_alliance_create_pressed)
	create_page.add_child(_alliance_create_button)
	# Alt: meclis penceresindeki gibi.
	box.add_child(UiTheme.rule())
	var away := Button.new()
	away.text = L.t("Haritaya dön")
	away.focus_mode = Control.FOCUS_NONE
	away.custom_minimum_size = Vector2(170, 46)
	UiSkin.skin_button(away)
	away.pressed.connect(func(): _alliance_panel.hide())
	box.add_child(away)
	_alliance_panel.hide()
	add_child(_alliance_panel)

## Pencere genişliğinde, ortalı açıklama (meclis penceresiyle aynı punto).
func _alliance_note(text: String, color: Color = UiTheme.TEXT) -> Label:
	var label := PopupKit.note(text, color, ALLIANCE_WIDTH)
	label.add_theme_font_size_override("font_size", 14)
	return label

func _on_alliance_button_pressed() -> void:
	_deselect_hand_card()
	if _alliance_panel.visible:
		_alliance_panel.hide()
		return
	if _law_designer != null:
		_close_law_page()
	# Bekleyen kararım ya da ittifak varsa listeyle, yoksa "yeni ittifak"la açılır.
	var me := multiplayer.get_unique_id()
	_alliance_tab = 0 if not CardManager.alliances.is_empty() or not CardManager.alliance_requests_for(me).is_empty() else 1
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
	CardManager.create_alliance(me, _alliance_name.text, _alliance_color)
	_alliance_name.clear()

func _alliance_action_reason(peer_id: int) -> String:
	if not CardManager.alliances_enabled:
		return L.t("Anayasa seçim ittifaklarını devre dışı bıraktı.")
	if PartyManager.is_independent(peer_id):
		return L.t("Bağımsız siyasetçiler ittifaka katılamaz.")
	if CardManager.is_party_member(peer_id):
		return L.t("İttifak kararını partinin genel başkanı verir.")
	if not CardManager.can_choose_main_action(peer_id):
		return L.t("İttifak kurmak, davet etmek, katılmak istemek ya da ayrılmak için sıranı bekle. Onay ve davet yanıtları her an verilebilir.")
	return ""

func _refresh_alliance_palette() -> void:
	var available: Array[Color] = []
	for button in _alliance_swatches:
		var color: Color = button.get_meta("color")
		var used := false
		for alliance in CardManager.alliances.values():
			if color.is_equal_approx(Color(alliance.get("color", Color.WHITE))):
				used = true
		button.disabled = used
		button.modulate.a = 0.25 if used else 1.0
		if not used:
			available.append(color)
	if not available.has(_alliance_color) and not available.is_empty():
		_alliance_color = available[0]
	for button in _alliance_swatches:
		var chosen: bool = not button.disabled and Color(button.get_meta("color")).is_equal_approx(_alliance_color)
		button.set_pressed_no_signal(chosen)
		# Seçili renk ✓ ile belli (rengin üstünde okunur: açık renkte koyu, koyuda beyaz).
		button.text = "•" if chosen else ""
		var ink := UiTheme.INK if Color(button.get_meta("color")).get_luminance() > 0.55 else Color.WHITE
		for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(prop, ink)
		button.add_theme_font_override("font", UiTheme.mono(true))
		button.add_theme_font_size_override("font_size", 22)

func _refresh_alliance_panel() -> void:
	_refresh_alliance_palette()
	for i in _alliance_tab_buttons.size():
		var tab: Button = _alliance_tab_buttons[i]
		var selected := i == _alliance_tab
		UiSkin.skin_color_button(tab, UiTheme.GOLD if selected else UiTheme.PANEL_LIGHT)
		for prop in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			tab.add_theme_color_override(prop, UiTheme.TEXT_ON_GOLD if selected else UiTheme.TEXT)
		(_alliance_pages[i] as Control).visible = selected
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
		_alliance_list.add_child(PopupKit.note(L.t("Anayasa ittifakları devre dışı bıraktı. Yeni seçim ittifakı kurulamaz ve ittifak hesabı yapılmaz."), UiTheme.RED, ALLIANCE_WIDTH))
	elif CardManager.alliances.is_empty():
		_alliance_list.add_child(PopupKit.note(L.t("Henüz kurulmuş bir seçim ittifakı yok."), UiTheme.TEXT_DIM, ALLIANCE_WIDTH))
	# Önce yanıt bekleyen kararlarım (davet / onay).
	for rid in CardManager.alliance_requests_for(me):
		_alliance_list.add_child(_alliance_decision_row(int(rid)))
	for alliance_id in CardManager.alliances:
		var alliance: Dictionary = CardManager.alliances[alliance_id]
		var members: Array = alliance.get("members", [])
		var leader := int(alliance.get("leader", -1))
		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = UiTheme.PANEL
		card_style.border_color = Color(alliance.get("color", UiTheme.GOLD))
		card_style.border_width_left = 6
		card_style.set_content_margin_all(UiTheme.PAD_M)
		card.add_theme_stylebox_override("panel", card_style)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		card.add_child(row)
		var heading := HBoxContainer.new()
		heading.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = alliance.get("color", UiTheme.GOLD)
		heading.add_child(swatch)
		var name_label := UiTheme.mono_label(String(alliance.get("name", L.t("İttifak"))), 16, UiTheme.TEXT, true)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(name_label)
		row.add_child(heading)
		var names: Array[String] = []
		for pid in members:
			names.append(("• " if int(pid) == leader else "") + String(PartyManager.data_of(int(pid)).get("name", "?")))
		row.add_child(PopupKit.note(L.t("Üyeler: %s") % ", ".join(PackedStringArray(names)), UiTheme.TEXT_DIM, ALLIANCE_WIDTH - 24.0))
		if my_alliance == int(alliance_id) and members.size() > 1:
			var shift := _my_alliance_shift()
			if shift != "":
				row.add_child(PopupKit.note(L.t("İttifak hitabını şekillendiriyor: %s") % shift, UiTheme.TEXT, ALLIANCE_WIDTH - 24.0))
		# Açık başvurular ve üye üye onay durumu.
		for rid in CardManager.alliance_requests:
			var req: Dictionary = CardManager.alliance_requests[rid]
			if int(req.get("alliance", -1)) != int(alliance_id):
				continue
			row.add_child(PopupKit.note(_alliance_request_status(req), UiTheme.HEAD, ALLIANCE_WIDTH - 24.0))
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		if my_alliance == int(alliance_id):
			if leader == my_party:
				var invite := _alliance_action(L.t("DAVET ET"), Color(alliance.get("color", UiTheme.GOLD)).darkened(0.25))
				invite.pressed.connect(_on_alliance_invite_pressed.bind(int(alliance_id)))
				invite.modulate.a = 1.0 if action_reason == "" and not _alliance_invite_targets(int(alliance_id)).is_empty() else 0.45
				buttons.add_child(invite)
			var leave := _alliance_action(L.t("AYRIL"), UiTheme.RED.darkened(0.35))
			leave.pressed.connect(_on_alliance_leave_pressed)
			leave.modulate.a = 1.0 if action_reason == "" else 0.45
			buttons.add_child(leave)
		elif my_alliance < 0 and not _invited_to(int(alliance_id), my_party):
			var pending := CardManager.pending_alliance_request(int(alliance_id), my_party) >= 0
			var ask := _alliance_action(L.t("BAŞVURU BEKLİYOR") if pending else L.t("KATILMAK İSTE"), Color(alliance.get("color", UiTheme.GOLD)).darkened(0.25))
			var my_preview := CardManager.alliance_preview_text(my_party, int(alliance_id))
			if my_preview != "":
				row.add_child(PopupKit.note(L.t("Katılırsan: %s") % my_preview, UiTheme.TEXT, ALLIANCE_WIDTH - 24.0))
			ask.pressed.connect(_on_alliance_request_pressed.bind(int(alliance_id)))
			ask.modulate.a = 1.0 if action_reason == "" and not pending else 0.45
			buttons.add_child(ask)
		if buttons.get_child_count() > 0:
			row.add_child(buttons)
		_alliance_list.add_child(card)

## Bu ittifaktan bana gelmiş (yanıt bekleyen) bir davet var mı? Varsa karar
## satırı yukarıda; ayrıca "katılmak iste" düğmesi gösterilmez.
func _invited_to(alliance_id: int, party_id: int) -> bool:
	var rid := CardManager.pending_alliance_request(alliance_id, party_id)
	return rid >= 0 and String(CardManager.alliance_requests[rid].get("kind", "")) == "invite"

## Ben ittifaktayken taban → etkin hitap farkı (en büyük üç).
func _my_alliance_shift() -> String:
	var me := multiplayer.get_unique_id()
	var base := PartyManager.groups_of(CardManager.party_of(me))
	var blended := VoterGroups.alliance_blend(base, CardManager._alliance_blend_members(CardManager.alliances[CardManager.alliance_of(me)]["members"]))
	var rows: Array = []
	for group in VoterGroups.GROUP_IDS:
		rows.append([group, float(base.get(group, 0.0)), float(blended.get(group, 0.0))])
	rows.sort_custom(func(a, b): return absf(a[2] - a[1]) > absf(b[2] - b[1]))
	var parts: Array[String] = []
	for row in rows:
		if parts.size() >= 3 or absf(float(row[2]) - float(row[1])) < 0.5:
			break
		parts.append("%s %d » %d" % [VoterGroups.title(String(row[0])), roundi(float(row[1])), roundi(float(row[2]))])
	return ", ".join(PackedStringArray(parts))

func _alliance_action(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_override("font", UiTheme.mono(true))
	button.add_theme_font_size_override("font_size", 14)
	UiSkin.skin_color_button(button, color)
	return button

## "Davet: X · Kabul ✓ · Üyeler: A ✓, B …" gibi tek satır durum.
func _alliance_request_status(req: Dictionary) -> String:
	var target := _fx_party_name(int(req.get("party", -1)))
	var votes: Dictionary = req.get("votes", {})
	var parts: Array[String] = []
	for voter in req.get("voters", []):
		var mark := "…"
		if votes.has(int(voter)):
			mark = "+" if bool(votes[int(voter)]) else "−"
		parts.append("%s %s" % [_fx_party_name(int(voter)), mark])
	var head := L.t("Davet: %s") % target if String(req.get("kind", "")) == "invite" else L.t("Katılma isteği: %s") % target
	if String(req.get("kind", "")) == "invite":
		head += " · " + (L.t("kabul etti") if bool(req.get("accepted", false)) else L.t("yanıt bekleniyor …"))
	if not parts.is_empty():
		head += " · " + L.t("onaylar: %s") % ", ".join(PackedStringArray(parts))
	return head

## Bana gelen karar: davet (kabul / ret) ya da üye onayı (onayla / reddet).
func _alliance_decision_row(rid: int) -> Control:
	var req: Dictionary = CardManager.alliance_requests.get(rid, {})
	var alliance: Dictionary = CardManager.alliances.get(int(req.get("alliance", -1)), {})
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = UiTheme.PANEL
	card_style.border_color = UiTheme.GOLD
	card_style.set_border_width_all(2)
	card_style.set_content_margin_all(UiTheme.PAD_M)
	card.add_theme_stylebox_override("panel", card_style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var me_target := int(req.get("party", -1)) == CardManager.party_of(multiplayer.get_unique_id())
	var text := ""
	if me_target:
		text = L.t("%s ittifakı seni davet ediyor. Katılman için diğer üyelerin de onayı gerekir.") % String(alliance.get("name", "?"))
	elif String(req.get("kind", "")) == "invite":
		text = L.t("Lider %s partisini %s ittifakına davet etti. Onayın gerekiyor.") % [_fx_party_name(int(req["party"])), String(alliance.get("name", "?"))]
	else:
		text = L.t("%s, %s ittifakına katılmak istiyor. Onayın gerekiyor.") % [_fx_party_name(int(req["party"])), String(alliance.get("name", "?"))]
	box.add_child(PopupKit.note(text, UiTheme.HEAD, ALLIANCE_WIDTH - 24.0))
	# İdeoloji önizlemesi: katılan partinin hitabı nasıl değişir (bana davetse benim).
	var preview := CardManager.alliance_preview_text(int(req.get("party", -1)), int(req.get("alliance", -1)))
	if preview != "":
		box.add_child(PopupKit.note(L.t("%s ittifakta: %s") % [_fx_party_name(int(req.get("party", -1))), preview], UiTheme.TEXT, ALLIANCE_WIDTH - 24.0))
	box.add_child(PopupKit.note(L.t("Yanıt vermezsen %d tur sonra ret sayılır.") % CardManager.ALLIANCE_REQUEST_ROUNDS, UiTheme.TEXT_DIM, ALLIANCE_WIDTH - 24.0))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var yes := _alliance_action(L.t("KABUL ET") if me_target else L.t("ONAYLA"), UiTheme.GREEN.darkened(0.35))
	yes.pressed.connect(_on_alliance_answer_pressed.bind(rid, true))
	buttons.add_child(yes)
	var no := _alliance_action(L.t("REDDET"), UiTheme.RED.darkened(0.35))
	no.pressed.connect(_on_alliance_answer_pressed.bind(rid, false))
	buttons.add_child(no)
	box.add_child(buttons)
	return card

func _on_alliance_answer_pressed(rid: int, yes: bool) -> void:
	CardManager.answer_alliance_request(multiplayer.get_unique_id(), rid, yes)
	_refresh_alliance_panel.call_deferred()

func _on_alliance_request_pressed(alliance_id: int) -> void:
	var me := multiplayer.get_unique_id()
	var reason := _alliance_action_reason(me)
	if reason != "":
		_show_toast(reason)
		return
	if CardManager.pending_alliance_request(alliance_id, me) >= 0:
		_show_toast(L.t("Başvurun zaten onay bekliyor."))
		return
	CardManager.request_alliance(me, alliance_id)
	_refresh_alliance_panel.call_deferred()

func _on_alliance_leave_pressed() -> void:
	var me := multiplayer.get_unique_id()
	var reason := _alliance_action_reason(me)
	if reason != "":
		_show_toast(reason)
		return
	CardManager.leave_alliance(me)
	_refresh_alliance_panel.call_deferred()

func _alliance_invite_targets(alliance_id: int) -> Array:
	var targets: Array = []
	for pid in CardManager.party_ids():
		if not PartyManager.is_independent(int(pid)) and CardManager.alliance_of(int(pid)) < 0 \
				and CardManager.pending_alliance_request(alliance_id, int(pid)) < 0:
			targets.append(int(pid))
	return targets

func _on_alliance_invite_pressed(alliance_id: int) -> void:
	var reason := _alliance_action_reason(multiplayer.get_unique_id())
	if reason != "":
		_show_toast(reason)
		return
	var targets := _alliance_invite_targets(alliance_id)
	if targets.is_empty():
		_show_toast(L.t("Davet edilebilecek parti yok."))
		return
	_show_party_picker(L.t("İTTİFAKA DAVET ET"), targets, func(pid: int):
		CardManager.invite_alliance_party(multiplayer.get_unique_id(), alliance_id, pid)
		_refresh_alliance_panel())

## Bana bir karar düştüyse (davet ya da onay) ittifak paneli açılır.
func _on_alliance_event(event: Dictionary, _version: int) -> void:
	var type := String(event.get("type", ""))
	if type in ["alliance_invited", "alliance_requested"] and CardManager.alliance_requests_for(multiplayer.get_unique_id()).has(int(event.get("request", -1))):
		_show_toast(L.t("İttifak kararı bekleniyor: İTTİFAK panelinden yanıtla."))
		if _alliance_panel != null and not _alliance_panel.visible:
			_on_alliance_button_pressed()
	elif _alliance_panel != null and _alliance_panel.visible:
		_refresh_alliance_panel()

func _place_alliance_panel() -> void:
	if not _alliance_panel.visible:
		return
	_alliance_panel.reset_size()
	await get_tree().process_frame
	_alliance_panel.reset_size()
	var view := get_viewport_rect().size
	var size := _alliance_panel.size
	_alliance_panel.position = Vector2((view.x - size.x) * 0.5, clampf((view.y - size.y) * 0.5 - 40.0, 8.0, maxf(8.0, view.y - size.y - 8.0)))

func _build_law_designer() -> void:
	_law_designer = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	UiSkin.apply_style(_law_designer, "panel", style)
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
	close.pressed.connect(_close_law_page)
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
	# 0.0.268: GRUP YASASI: açıklama, sekiz grup düğmesi; gruba basmak
	# yasayı sunar.
	group_page.add_theme_constant_override("separation", 10)
	_law_detail = VBoxContainer.new()
	_law_detail.add_theme_constant_override("separation", 10)
	group_page.add_child(_law_detail)
	_law_rows = GridContainer.new()
	group_page.add_child(_law_rows)
	_build_constitution_section(_law_pages[LawTab.CONSTITUTION])
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
	interval_row.add_child(_stepper_button("−", func(): _change_constitution(0.0, -GameRules.ELECTION_INTERVAL_STEP)))
	interval_row.add_child(_constitution_interval_label)
	interval_row.add_child(_stepper_button("+", func(): _change_constitution(0.0, GameRules.ELECTION_INTERVAL_STEP)))
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
	_constitution_alliances = VectorSwitch.new()
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

func _change_constitution(threshold_delta: float, interval_delta: float) -> void:
	_constitution_threshold = clampf(_constitution_threshold + threshold_delta, 0.0, 10.0)
	_constitution_interval = GameRules.snap_interval(_constitution_interval + interval_delta)
	_refresh_constitution_section()

func _refresh_constitution_section() -> void:
	if _constitution_threshold_label == null:
		return
	_constitution_threshold_label.text = L.t("%%%s") % String.num(_constitution_threshold, 1)
	_constitution_interval_label.text = L.t("%s yıl") % GameRules.years_text(_constitution_interval)
	_constitution_method_label.text = ElectionModel.method_title(_constitution_method)
	var me := multiplayer.get_unique_id()
	var can := CardManager.can_propose_constitution(me)
	_constitution_button.disabled = not can
	var needed := GovernmentManager.constitution_threshold_seats()
	var changed: bool = not is_equal_approx(_constitution_threshold, MultiplayerManager.election_threshold) 		or not is_equal_approx(_constitution_interval, MultiplayerManager.election_interval) \
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
			_on_law_tax_selected, _propose_tax, _close_law_page, false)
	_law_points_label.hide()
	var me := multiplayer.get_unique_id()
	var grid := ParliamentFlow.group_grid(_propose_law_clicked_group,
		func(group: String) -> bool: return CardManager.can_propose_law(me, CardPresets.law_type(group)))
	# Eski ızgara silinip yerine yenisi konur (replace_by eski düğmeleri yeniye
	# taşıyordu: sekmeler arasında gidip gelince gruplar çoğalıyordu).
	var parent := _law_rows.get_parent()
	var index := _law_rows.get_index()
	parent.remove_child(_law_rows)
	_law_rows.queue_free()
	parent.add_child(grid)
	parent.move_child(grid, index)
	_law_rows = grid
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

## "+3,9" / "−2,5" gibi işaretli kısa sayı.
static func _signed(value: float) -> String:
	return ("+" if value >= 0.0 else "−") + String.num(snappedf(absf(value), 0.1), 1).replace(".", ",")

## Grup yasası açıklaması (kısa): ne olur, bedeli,
## kriz varsa krizin grubu.
func _refresh_law_detail() -> void:
	if _law_detail == null:
		return
	for child in _law_detail.get_children():
		child.queue_free()
	var me := multiplayer.get_unique_id()
	_law_detail.add_child(ParliamentFlow.explain_label(L.t("Bir seçmen grubu için yasa getir: kabul edilirse o grup sana ısınır, karşıt grup aynı ölçüde soğur. Meclis çoğunluğu gerekir.")))
	var cost := L.t("Bedelsiz") if GameRules.LAW_FUNDS_COST <= 0.0 else L.t("Bedel %s") % GameRules.cost_text(GameRules.LAW_FUNDS_COST)
	_law_detail.add_child(ParliamentFlow.explain_label(L.t("%s · kabul edilirse +%d puan") % [
		cost, CardManager.law_pass_score(CardManager.is_government_party(me))], UiTheme.TEXT_MUTED))
	var crisis := CardManager.crisis_group()
	if crisis != "":
		_law_detail.add_child(ParliamentFlow.explain_label(L.t("Siyasi kriz: %s. Bu grup için yasa çok daha etkili.") % VoterGroups.title(crisis), UiTheme.HEAD))

func _propose_law_clicked_group(group: String) -> void:
	_propose_law_clicked(CardPresets.law_type(group))

## Eksen ucuna TIKLAMAK yasayı doğrudan meclise sunar (sürükleme yok).
func _propose_law_clicked(law_type: String) -> void:
	if not CardManager.can_propose_law(multiplayer.get_unique_id(), law_type):
		_show_toast(_action_block_reason(CardManager.law_funds_cost(multiplayer.get_unique_id(), law_type), true))
		return
	_close_law_page()
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
	return L.t("%s yatırımı · devlet hazinesi %s » %s\nGüçlü yerel etki: yarısı hemen, kalanı %d dönemde · ekonomi canlanır") % [
		pname, Economy.money_full(before), Economy.money_full(before - Economy.INVEST_COST), Economy.INVEST_DELAY_ROUNDS]

static func _one_decimal(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 1).replace(".", ",")

func _build_tax_panel() -> void:
	_tax_panel = PanelContainer.new()
	var style := UiSkin.stylebox(UiSkin.PANEL)
	style.set_content_margin_all(UiTheme.PAD_M)
	UiSkin.apply_style(_tax_panel, "panel", style)
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
	_close_law_page()
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
	_close_law_page()
	CardManager.propose_law(law_type)

# --- Afet yardım paneli --------------------------------------------------------

func _build_funding_ui() -> void:
	_aid_panel = AidPanel.new()
	_aid_panel.hide()
	_aid_panel.confirmed.connect(_on_aid_confirmed)
	_aid_panel.cancelled.connect(func(): _aid_panel.hide())
	add_child(_aid_panel)

## 0.0.238: miting parti kasasından, yatırım devlet hazinesinden (paylaşım yok).
func _on_funding_confirmed() -> void:
	var me := multiplayer.get_unique_id()
	var province_id := _selected_province
	var investing := _pending_invest
	var focus := _miting_focus.duplicate()
	_cancel_targeting()
	if province_id == "":
		return
	if investing:
		if CardManager.can_invest(me, province_id, 1.0):
			CardManager.invest(province_id, 1.0)
		else:
			_show_toast(CardManager.funding_block_reason(me, "invest", 1.0) if CardManager.is_government_party(me) else _invest_block_reason())
	else:
		if CardManager.can_miting(me, province_id, 0.0):
			CardManager.miting(province_id, 0.0, focus)
		else:
			_show_toast(CardManager.funding_block_reason(me, "miting", 0.0))

func _place_party_picker() -> void:
	if _party_picker == null or not is_instance_valid(_party_picker):
		return
	_party_picker.reset_size()
	var map := _r(R_MAP)
	_party_picker.position = Vector2(map.position.x + (map.size.x - _party_picker.size.x) * 0.5,
		maxf(map.position.y + 40.0, map.end.y - _party_picker.size.y - 8.0))

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

## Yasa alanını doğrudan açar (önizleme betikleri): meclis penceresinin yasa sayfası.
func _on_law_button_pressed() -> void:
	_deselect_hand_card()
	if _tax_panel != null:
		_tax_panel.hide()
	_law_tax_selected = -1
	_parliament_flow.open_law_page(_law_tab)

## 0.0.246: yasa alanı meclis penceresinin içinde; pencere yeniden ortalanır.
func _place_law_designer() -> void:
	if _parliament_flow != null:
		_parliament_flow.relayout()

## YASA ALANI MECLİS PENCERESİNE GÖMÜLÜR (0.0.246): kendi başlığı (Kapat) ve
## Grup / Vergi / Anayasa sekmeleri gizlenir; hangi sayfanın açık olduğunu
## meclis penceresinin YASA seçenekleri belirler, "Geri" sekmelere döner.
func _embed_law_designer() -> void:
	_law_designer.get_parent().remove_child(_law_designer)
	_parliament_flow.law_host.add_child(_law_designer)
	_law_designer.z_index = 0
	UiSkin.apply_style(_law_designer, "panel", StyleBoxEmpty.new())
	var box := _law_designer.get_child(0) as VBoxContainer
	(box.get_child(0) as Control).hide()  # başlık + Kapat
	if not _law_tab_buttons.is_empty():
		(_law_tab_buttons[0] as Control).get_parent().hide()  # iç sekmeler
	_law_designer.show()

## Yasa sayfası kapanır (teklif sunuldu ya da vazgeçildi): meclis sekmelerine dönülür.
func _close_law_page() -> void:
	if _parliament_flow != null:
		_parliament_flow.leave_law_page()

# --- AFET (0.0.181) --------------------------------------------------------------

## Haritadaki afet işareti ve açık yardım paneli güncel durumla eşlenir.
func _refresh_disaster() -> void:
	var active := CardManager.active_disaster()
	if map_holder != null and map_holder.has_method("set_disaster"):
		map_holder.set_disaster(active.get("provinces", []), String(active.get("kind", "")))
	if _aid_panel != null and _aid_panel.visible:
		if active.is_empty() or not CardManager.can_choose_main_action(multiplayer.get_unique_id()):
			_aid_panel.hide()

func _place_aid_panel() -> void:
	if not _aid_panel.visible:
		return
	_aid_panel.reset_size()
	var map := _r(R_MAP)
	var panel_size := _aid_panel.size
	_aid_panel.position = Vector2(map.position.x + (map.size.x - panel_size.x) * 0.5,
		maxf(map.position.y + 40.0, map.end.y - panel_size.y - 8.0))

## YARDIM hamlesi: afet sürerken yardım paneli haritanın üstünde açılır.
func _on_aid_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if _aid_panel.visible:
		_aid_panel.hide()
		return
	if not CardManager.has_disaster():
		_show_toast(L.t("Şu an yardım bekleyen bir afet yok. Afet çıkınca buradan yardım götürebilirsin."))
		return
	var reason := CardManager.aid_block_reason(me)
	if reason != "":
		_show_toast(reason)
		return
	_aid_panel.open(me)
	_aid_panel.show()
	_place_aid_panel()
	_place_aid_panel.call_deferred()

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
	_close_law_page()
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
	_layer_bar.add_theme_constant_override("separation", int(UiTheme.d(8)))
	_layer_bar.z_index = 5
	add_child(_layer_bar)
	for i in MAP_LAYER_TITLES.size():
		var button := Button.new()
		button.text = MAP_LAYER_TITLES[i]
		button.custom_minimum_size = Vector2(UiTheme.d(120), PLAYER_TAB_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
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
	_group_picker.add_theme_constant_override("separation", 6)
	_group_picker.z_index = 6
	add_child(_group_picker)
	for group in VoterGroups.GROUP_IDS:
		# Kare düğme: yalnız grup simgesi (seçili olan grubun renginde).
		var pick := Button.new()
		pick.focus_mode = Control.FOCUS_NONE
		pick.custom_minimum_size = Vector2(34, 34)
		var icon := VoterGroupIcon.make(group, 28.0)
		icon.position = Vector2(3, 3)
		icon.size = Vector2(28, 28)
		pick.add_child(icon)
		var name_label := Label.new()
		name_label.name = L.t("Title")
		name_label.text = VoterGroups.title(group)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		name_label.add_theme_constant_override("outline_size", 3)
		name_label.position = Vector2(36, 0)
		name_label.size = Vector2(0, 34)
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
	# Orta panonun sol üstünde (konsept: 22, 20).
	_layer_bar.position = rect.position + Vector2(UiTheme.d(22), UiTheme.d(20))
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
func _layer_button_style(color: Color, _left: bool, _right: bool) -> StyleBox:
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
		_style_tab_button(button, active, true)
	if _group_picker != null:
		_group_picker.visible = _map_layer == MapLayer.GROUPS
		for pick in _group_picker.get_children():
			var group := String(pick.get_meta("group"))
			var selected := group == _map_group
			var color := VoterGroups.color(group)
			# 0.0.244: seçili olsa da yalnız simge (ad genişlemesi yok; ad ipucunda).
			var title: Label = pick.get_node("Title")
			title.visible = false
			var width := 34.0
			(pick as Button).custom_minimum_size = Vector2(width, 34)
			(pick as Button).size = Vector2(width, 34)
			for state in ["normal", "hover", "pressed", "focus"]:
				var pill := StyleBoxFlat.new()
				pill.set_corner_radius_all(UiTheme.RADIUS_S)
				pill.anti_aliasing = true
				if selected:
					pill.bg_color = color.darkened(0.1)
					pill.border_color = color.lightened(0.25)
				else:
					pill.bg_color = UiTheme.PANEL_LIGHT if state != "hover" else UiTheme.PANEL_DARK
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
				swatches.append([_map_tint(mine, float(level) / GameRules.ORG_MAX_LEVEL), str(level)])
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
				swatches.append([_group_layer_tint(float(i) / 3.0), ""])
			swatches.append([null, L.t("%%%d") % int(span.y)])
	_layer_legend.visible = not swatches.is_empty()
	for entry in swatches:
		if entry[0] == null:
			# 0.0.268: krem pano üstünde okunaklı gövde yazısı (kontursuz).
			var label := Label.new()
			label.text = String(entry[1])
			label.add_theme_font_override("font", UiTheme.body())
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED.lerp(UiTheme.TEXT, 0.35))
			label.add_theme_constant_override("outline_size", 0)
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_layer_legend.add_child(label)
			continue
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(maxf(22.0, 8.0 + 7.0 * String(entry[1]).length()), 16)
		var chip := BoardBox.new()
		chip.fill = entry[0]
		chip.set_radius(UiTheme.d(6))
		chip.lips = [[UiTheme.d(3), (entry[0] as Color).darkened(0.35)]]
		UiSkin.apply_style(swatch, "panel", chip)
		if String(entry[1]) != "":
			var num := Label.new()
			num.text = String(entry[1])
			num.set_anchors_preset(Control.PRESET_FULL_RECT)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			num.add_theme_font_override("font", UiTheme.body())
			num.add_theme_font_size_override("font_size", 11)
			num.add_theme_constant_override("outline_size", 0)
			num.add_theme_color_override("font_color", UiTheme.INK if (entry[0] as Color).get_luminance() > 0.55 else UiTheme.ON_COLOR)
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
	map_holder.set_dark_borders(false)
	map_holder.set_white_borders(_map_layer in [MapLayer.GROUPS, MapLayer.ORGANIZATION])
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
					colors[province_id] = _group_layer_tint(t)
				MapLayer.ORGANIZATION:
					colors[province_id] = _map_tint(mine, float(CardManager.organization_level(province_id, me)) / GameRules.ORG_MAX_LEVEL)
				MapLayer.STRENGTH:
					if projection.has(province_id):
						colors[province_id] = gradient.sample((_strength_t(projection[province_id], me) + 1.0) * 0.5)
					else:
						colors[province_id] = MAP_UNKNOWN_COLOR
	_province_base_colors = colors
	map_holder.replace_province_colors(colors)
	var seat_markers := map_holder.get_node_or_null("SeatMarkers")
	if seat_markers != null:
		seat_markers.visible = _map_layer == MapLayer.SEATS
	if _hovered_province_id != "":
		var selected := _hovered_province_id
		_hovered_province_id = ""
		_highlight_province(selected)

## Seçmen katmanı: şeffaflık yok. En az yoğun il grubun kendi rengi; yoğunluk
## arttıkça renk koyulaşır, en yoğun uç grubun koyu, lacivertle karışmış hali.
const GROUP_LAYER_DEEP := Color(0.12, 0.14, 0.26)

func _group_layer_tint(t: float) -> Color:
	var base := VoterGroups.color(_map_group)
	base.a = 1.0
	return base.lerp(GROUP_LAYER_DEEP, 0.6 * clampf(t, 0.0, 1.0))

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
	# Kayma mesafesi desen hücresinin katı: denizin dalgaları haritayla birlikte
	# kayarken anlık görüntüdeki dalgalarla hep çakışık kalır.
	var width := ceilf(_map_clip.size.x / TableSurface.Sea.CELL_W) * TableSurface.Sea.CELL_W
	_map_snapshot.texture = ImageTexture.create_from_image(snapshot)
	_map_snapshot.position = Vector2.ZERO
	_map_snapshot.size = _map_clip.size
	_map_snapshot.show()
	_map_clip.move_child(_map_snapshot, _map_clip.get_child_count() - 1)
	# İl incelenirken harita yakınlaştırılmış konumuna kayar.
	var home := map_holder.position if map_holder.isolated_id != "" else Vector2.ZERO
	map_holder.position = home + Vector2(width * direction, 0.0)
	var sea := _map_bg as TableSurface.Sea
	if sea != null:
		sea.scroll = 0.0
	# Görüntü yakalama (GPU'dan okuma) o kareyi uzatır; kayma bir kare sonra
	# başlar ki uzun kare animasyonda sıçrama yapmasın.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_map_slide_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Kayma tam ekran pikseline yuvarlanır: vekil pulları yeniden çizilmeden kayar.
	var pixel := 1.0 / maxf(0.0001, get_viewport().get_final_transform().get_scale().x)
	_map_slide_tween.tween_method(func(t: float):
		var shift := roundf(width * direction * t / pixel) * pixel
		_map_snapshot.position.x = -shift
		map_holder.position.x = home.x + width * direction - shift
		if sea != null:
			sea.scroll = -shift, 0.0, 1.0, MAP_SLIDE_DURATION)
	_map_slide_tween.tween_callback(func():
		_map_snapshot.hide()
		_map_snapshot.texture = null
		if sea != null:
			sea.scroll = 0.0
		map_holder.position = home)
	if _queued_layer != -1:
		var queued := _queued_layer
		_queued_layer = -1
		_set_map_layer(queued)

func _begin_org_view() -> void:
	_org_view_token += 1
	if _layer_before_org == -1:
		_layer_before_org = _map_layer
	_set_map_layer(MapLayer.ORGANIZATION)

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

func _build_propaganda_menu() -> void:
	_propaganda_menu = PanelContainer.new()
	UiSkin.skin_panel(_propaganda_menu, UiSkin.PANEL_DARK)
	_propaganda_menu.z_index = 112
	_propaganda_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_propaganda_menu.hide()
	add_child(_propaganda_menu)

## Karalama kartı bir ile bırakıldı: hedef parti seçtirilir, sonra oynanır.
func _ask_propaganda_target(hand_index: int, province_id: String) -> void:
	var me := multiplayer.get_unique_id()
	if CardManager.organization_level(province_id, me) < 1 and not PartyManager.is_independent(me):
		_show_toast(L.t("%s'da teşkilatın yok: karalama teşkilat ister.") % ElectionNightSim.province_name(province_id))
		return
	var targets: Array = CardManager.smear_targets(me, province_id)
	_show_party_picker(L.t("%s: kimi karalayacaksın?") % ElectionNightSim.province_name(province_id), targets,
		func(pid: int): CardManager.play_card(hand_index, pid, province_id))

## Evrensel parti listesinde satır (logo = düğme) yüksekliği ve ad düğmesi genişliği.
const PICKER_ROW := 40.0
const PICKER_FONT := 15
const PICKER_NAME_MIN := 120.0
const PICKER_NAME_MAX := 280.0

func _show_party_picker(title: String, targets: Array, selected: Callable) -> void:
	if _party_picker != null and is_instance_valid(_party_picker):
		_party_picker.queue_free()
	if targets.is_empty():
		_show_toast(L.t("Seçilebilecek parti yok."))
		return
	_party_picker = PanelContainer.new()
	UiSkin.skin_panel(_party_picker, UiSkin.PANEL)
	_party_picker.z_index = 120
	# EVRENSEL PARTİ LİSTESİ: logo ve düğme AYNI yükseklikte (PICKER_ROW);
	# düğme genişliği en uzun parti adına göre (gereğinden geniş değil).
	var font: Font = ThemeDB.fallback_font
	var name_width := PICKER_NAME_MIN
	for pid in targets:
		var text := String(PartyManager.data_of(int(pid)).get("name", "?"))
		name_width = maxf(name_width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PICKER_FONT).x + 28.0)
	name_width = minf(name_width, PICKER_NAME_MAX)
	var row_width := PICKER_ROW + 6.0 + name_width
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_party_picker.add_child(box)
	var heading := UiTheme.mono_label(title, 14, UiTheme.TEXT, true)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size.x = row_width
	box.add_child(heading)
	var scroll := ScrollContainer.new()
	var rows_height := targets.size() * PICKER_ROW + maxf(0.0, targets.size() - 1) * 6.0
	scroll.custom_minimum_size = Vector2(row_width, minf(rows_height, PICKER_ROW * 6.0 + 30.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for pid in targets:
		var party: Dictionary = PartyManager.data_of(int(pid))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var badge := PartyBadge.build(party, Vector2(PICKER_ROW, PICKER_ROW), BADGE_ICON_PIXEL_SIZE)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var button := Button.new()
		button.text = String(party.get("name", "?"))
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(name_width, PICKER_ROW)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_size_override("font_size", PICKER_FONT)
		UiSkin.skin_color_button(button, Color(party.get("bg_color", UiTheme.PANEL_DARK)).darkened(0.35))
		button.pressed.connect(func():
			_party_picker.queue_free()
			_party_picker = null
			selected.call(int(pid)))
		row.add_child(button)
		list.add_child(row)
	var close := Button.new()
	close.text = L.t("İptal")
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(row_width, PICKER_ROW)
	close.add_theme_font_size_override("font_size", PICKER_FONT)
	UiSkin.skin_button(close)
	close.pressed.connect(func():
		_party_picker.queue_free()
		_party_picker = null)
	box.add_child(close)
	add_child(_party_picker)
	_place_party_picker.call_deferred()

func _map_tint(color: Color, strength: float) -> Color:
	return Color(color, clampf(strength, 0.0, 1.0))

func _set_action_available(button: Button, available: bool) -> void:
	button.modulate = Color.WHITE
	UiSkin.skin_action_button(button, button.get_meta("action_color", UiTheme.PANEL_LIGHT), available)
	_sync_action_text(button)

# --- TUR AKIŞI ARAYÜZÜ (0.0.231) -------------------------------------------------------
## KART ÇEK + afet sahnesi (TurnIntro), MECLİS akışı (ParliamentFlow) ve il işlem
## paneli (ProvinceActions). Üçü de durumu CardManager'dan okur; bu ekran
## yalnız yerleştirir ve yeniler.

func _build_turn_flow_ui() -> void:
	_province_actions = ProvinceActions.new()
	_province_actions.closed.connect(_on_province_actions_closed)
	_province_actions.info_requested.connect(func(id: String):
		_pinned = false
		_show_province_info(id)
		_pinned = true)
	_province_actions.toast_requested.connect(_show_toast)
	add_child(_province_actions)
	_parliament_flow = ParliamentFlow.new()
	_parliament_flow.law_tab_requested.connect(_on_flow_law_tab)
	_parliament_flow.toast_requested.connect(_show_toast)
	add_child(_parliament_flow)
	_embed_law_designer()
	_turn_intro = TurnIntro.new()
	_turn_intro.hand_rect = func() -> Rect2: return _r(R_HAND)
	# Gazeteler (seçim sonucu, hükümet kuruldu...) ve kongre gecesi önce; şans kartı sonra.
	_turn_intro.hold = func() -> bool: return (_event_fx != null and _event_fx.is_playing()) 		or (_congress_view != null and is_instance_valid(_congress_view))
	_turn_intro.finished.connect(_refresh_turn_flow_ui)
	add_child(_turn_intro)
	CardManager.event_presented.connect(_on_flow_event)
	# Ekran açılırken sıradaki gazeteler (seçim sonucu, hükümet) kuyruğa girsin, sonra bakılır.
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_inside_tree():
			_refresh_turn_flow_ui())

## Kendi kart çekimimin olayı: kartlar ortada açılır.
func _on_flow_event(event: Dictionary, _version: int) -> void:
	if String(event.get("type", "")) == "draw" and int(event.get("peer_id", -1)) == multiplayer.get_unique_id():
		_turn_intro.present(event.get("draws", []))

func _refresh_turn_flow_ui() -> void:
	if _turn_intro == null:
		return
	_turn_intro.refresh()
	_parliament_flow.refresh()
	if _province_actions.visible:
		if not _can_open_province_actions():
			_province_actions.close()
		else:
			_province_actions.refresh()
	_refresh_parliament_button()

## İl işlem paneli: sıra bende, tur başı sunumu bitti, oylama yok.
func _can_open_province_actions() -> bool:
	return CardManager.can_act() and not CardManager.game_finished and (_turn_intro == null or not _turn_intro.is_busy())

## İL TIKLAMASI (0.0.232): harita paneli ikiye bölünür; harita sol yarıya
## küçülür, il hamleleri aynı alanın sağ yarısında açılır. Aynı ile tekrar
## dokunmak ya da paneldeki ✕ eski görünüme döndürür.
func _open_province_actions(province_id: String) -> void:
	if _province_actions.visible and _province_actions.province_id == province_id:
		_province_actions.close()
		return
	_parliament_flow.close_flow()
	_close_law_page()
	# 0.0.269: harita bölünmez; tıklanan yerin yanında bağlam menüsü açılır
	# (orta panonun içinde kalır).
	var board := _r(R_MAP).grow(-UiTheme.d(10))
	_province_actions.place_at(get_viewport().get_mouse_position(), board)
	_province_actions.open(province_id)
	_highlight_province(province_id)
	_pinned = false
	_show_province_info(province_id)
	_pinned = true
	# İl bilgisi odak yakınlaşması başlatır; menü açıkken harita yerinde kalır.
	if _focus_tween != null and _focus_tween.is_running():
		_focus_tween.kill()
	map_holder.scale = Vector2(_map_fit_scale, _map_fit_scale)
	map_holder.position = Vector2.ZERO

func _on_province_actions_closed() -> void:
	_highlight_province("")

## MECLİS düğmesi: açık aşamayı gösterir, yapılacak iş varken nabız gibi parlar.
func _refresh_parliament_button() -> void:
	if _parl_button == null:
		return
	var me := multiplayer.get_unique_id()
	var stage := CardManager.parliament_stage(me) if CardManager.can_act() else ""
	var sub := ""
	if stage != "":
		# Sekmeler sırasız: açık olanların hepsi yazar.
		var open: PackedStringArray = []
		for id in CardManager.PARL_STAGES:
			if CardManager.parliament_stage_available(me, String(id)):
				open.append({"censure": L.t("gensoru"), "law": L.t("yasa")}[id])
		sub = L.t("açık: %s") % ", ".join(open)
	elif not CardManager.can_act():
		sub = L.t("sıra sende değil")
	elif not CardManager.parliament_closed_stages(me).is_empty():
		sub = L.t("bu tur tamamlandı")
	elif CardManager.last_seats.is_empty():
		sub = L.t("ilk seçimden sonra açılır")
	elif not CardManager.has_seats(me):
		sub = L.t("mecliste vekilin yok")
	elif CardManager.is_party_member(me):
		sub = L.t("genel başkan yürütür")
	else:
		sub = L.t("bu tur yapılacak iş yok")
	var live := stage != ""
	UiSkin.skin_action_button(_parl_button, ACTION_COLOR_LAW, live)
	_set_action_text(_parl_button, L.t("MECLİS"), sub)
	if live and _parl_pulse == null:
		_parl_pulse = create_tween().set_loops()
		_parl_pulse.tween_property(_parl_button, "modulate", Color(1.35, 1.25, 1.6), 0.6).set_trans(Tween.TRANS_SINE)
		_parl_pulse.tween_property(_parl_button, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	elif not live and _parl_pulse != null:
		_parl_pulse.kill()
		_parl_pulse = null
		_parl_button.modulate = Color.WHITE

func _on_parliament_button_pressed() -> void:
	var me := multiplayer.get_unique_id()
	if not CardManager.can_act():
		_show_toast(L.t("Sıran değil."))
		return
	if _turn_intro != null and _turn_intro.is_busy():
		return
	if CardManager.parliament_stage(me) == "":
		_show_toast(_parl_button.text.get_slice("\n", 1).capitalize())
		return
	if _province_actions.visible:
		_province_actions.close()
	_deselect_hand_card()
	_parliament_flow.open_flow()

## YASA sekmesinden grup / vergi / anayasa: gömülü yasa alanında o sayfa açılır.
func _on_flow_law_tab(tab: int) -> void:
	if _tax_panel != null:
		_tax_panel.hide()
	_law_tax_selected = -1
	_law_tab = tab
	_select_law_tab(tab)

