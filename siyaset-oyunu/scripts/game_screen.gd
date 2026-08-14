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
const TOP_AREA_HEIGHT_RATIO := 0.62
const MAP_FILL_RATIO := 0.92
# Sağda oyuncu daireleri için ayrılan, PANELSİZ (tamamen boş) şerit genişliği.
const PLAYER_STRIP_WIDTH := 120.0
# Harita ile oyuncu şeridi arasında, deste butonu için ayrılan şerit.
const DECK_STRIP_WIDTH := 230.0
const AVATAR_SIZE := 56.0
const AVATAR_ICON_PIXEL_SIZE := 96
const BADGE_ICON_PIXEL_SIZE := 64

# Kartlar 72x96 piksel native boyutta; Nearest filtre ile piksel-sanat
# görünümü bozulmasın diye tam sayı katıyla büyütülüyor.
const CARD_DISPLAY_SCALE := 2.0
const CARD_DISPLAY_SIZE := Vector2(72, 96) * CARD_DISPLAY_SCALE
const CARD_HOVER_LIFT_SPEED := 12.0
## Parti profil kartının (politic_profile.png, 77x53) büyütme katı. TAM SAYI
## olmalı — pixel-art keskinliği ancak tam sayı katlarda korunur.
const PROFILE_CARD_SCALE := 4
const TAP_MAX_HOLD_MS := 250
const TAP_MAX_MOVE_PX := 10.0

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
@onready var player_panel_list: VBoxContainer = %PlayerPanelList
@onready var hand_container: HBoxContainer = %HandContainer
@onready var turn_indicator: PanelContainer = %TurnIndicator
@onready var turn_indicator_label: Label = %TurnIndicatorLabel
@onready var turn_indicator_badge_slot: Control = %TurnIndicatorBadgeSlot
@onready var hover_tooltip: Control = %HoverTooltip
@onready var hover_tooltip_image: TextureRect = %HoverTooltipImage
@onready var parliament_diagram: ParliamentDiagram = %ParliamentDiagram
@onready var vote_share_panel: VoteSharePanel = %VoteSharePanel
@onready var game_settings_label: Label = %GameSettingsLabel
@onready var bottom_area: Control = %BottomArea

var _hovered_peer_id: int = -1
var _hand_holders: Array = [] # Array[Control], hover-kaldirma animasyonu icin (her biri bir kartin "holder"i)
var _hovered_province_id: String = ""
# province_id -> Color (kazanan partinin rengi) — hover'dan çıkınca buna dönülür.
var _province_base_colors: Dictionary = {}
var _province_tooltip: PanelContainer

func _ready() -> void:
	map_holder.province_hovered.connect(_on_province_hovered)
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
	CardManager.round_completed.connect(_on_round_completed)
	_rebuild_player_panel()
	_rebuild_hand()
	_on_turn_changed(CardManager.current_turn_peer_id())
	_refresh_results_panels()

## Viewport boyutuna bağlı TÜM mutlak-piksel yerleşim hesapları burada — hem
## açılışta hem her yeniden boyutlanmada (tam ekran vb.) çağrılır.
func _apply_layout() -> void:
	if map_holder == null or map_holder.grid_width <= 0:
		return
	var viewport_size := get_viewport_rect().size
	# Harita SADECE üst bölgeye (TOP_AREA_HEIGHT_RATIO) ve sağdaki deste/
	# oyuncu şeridi hariç kalan genişliğe sığacak şekilde ölçekleniyor —
	# geniş, dikdörtgen bir alanı doldurması hedefleniyor.
	var reserved_width := PLAYER_STRIP_WIDTH + DECK_STRIP_WIDTH
	var available_width := viewport_size.x - reserved_width
	var available_height := viewport_size.y * TOP_AREA_HEIGHT_RATIO
	# Haritanın "doğal" (native) piksel boyutu sabit bir const DEĞİL —
	# pixel-art asset (assets/maps/turkey_map.png) her değiştiğinde boyutu
	# değişebiliyor, o yüzden province_map.gd'nin YÜKLEDİĞİ gerçek ızgara
	# boyutundan (grid_width/height * MAP_UNIT_SCALE) runtime'da hesaplanıyor.
	var map_native_size: Vector2 = Vector2(map_holder.grid_width, map_holder.grid_height) * map_holder.MAP_UNIT_SCALE
	var fit_scale: float = minf(available_width / map_native_size.x, available_height / map_native_size.y) * MAP_FILL_RATIO
	map_holder.scale = Vector2(fit_scale, fit_scale)
	map_holder.position = Vector2(
		available_width * 0.5 - map_native_size.x * 0.5 * fit_scale,
		available_height * 0.5 - map_native_size.y * 0.5 * fit_scale
	)

	# Alt haznenin (parlamento + oy oranları, aralarındaki boşluk dahil)
	# TOPLAM yatay genişliği, haritanın GERÇEKTEN kapladığı genişlikle
	# birebir aynı ve onunla hizalı olsun.
	var map_rendered_width: float = map_native_size.x * fit_scale
	bottom_area.offset_left = map_holder.position.x
	bottom_area.offset_right = map_holder.position.x + map_rendered_width - viewport_size.x

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
	_build_debug_label()

## GEÇİCİ teşhis etiketi: sol alt köşede, bu istemcinin kendi peer id'sini ve
## CardManager'ın kimin sırası olduğunu düşündüğünü gösterir. "3. oyuncunun
## sırası gelince oynanamıyor" hatasının kaynağını bulmak için — sorun
## çözülünce kaldırılabilir.
func _build_debug_label() -> void:
	var label := Label.new()
	label.name = "DebugTurnLabel"
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	label.offset_left = 16.0
	label.offset_top = -100.0
	label.offset_right = 420.0
	label.offset_bottom = -70.0
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 0.4, 0.85)
	add_child(label)
	CardManager.turn_changed.connect(func(_p): _update_debug_label(label))
	_update_debug_label(label)

func _update_debug_label(label: Label) -> void:
	label.text = "[DEBUG] benim id: %d | CardManager sırası: %d | turn_order: %s | index: %d/%d | is_host: %s" % [
		multiplayer.get_unique_id(),
		CardManager.current_turn_peer_id(),
		str(CardManager.turn_order),
		CardManager.current_turn_index,
		CardManager.turn_order.size(),
		str(MultiplayerManager.is_host),
	]

## Bir tur/dönem tamamlanınca (herkes sırayla bir kez oynayınca) HERKESİN
## ekranında tetiklenir: ekran kararıp seçim sonuçları animasyon ekranına
## geçilir, oradan otomatik olarak buraya (yeni bir GameScreen örneğine) geri
## dönülür — dönüşte _ready() zaten en güncel sonuçları _refresh_results_panels
## ile gösterir.
func _on_round_completed() -> void:
	SceneTransition.fade_to_scene("res://scenes/ElectionResults.tscn")

func _refresh_results_panels() -> void:
	var ids: Array = CardManager.last_vote_shares.keys()
	ids.sort_custom(func(a, b): return CardManager.last_vote_shares[a] > CardManager.last_vote_shares[b])
	var vote_entries: Array = []
	var seat_entries: Array = []
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var pname: String = party.get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?"))
		var color: Color = party.get("bg_color", Color(0.5, 0.5, 0.5))
		vote_entries.append({"name": pname, "color": color, "percent": CardManager.last_vote_shares[peer_id], "seats": CardManager.last_seats.get(peer_id, 0)})
		seat_entries.append({"seats": CardManager.last_seats.get(peer_id, 0), "color": color})
	vote_share_panel.set_data(vote_entries)
	parliament_diagram.set_results(seat_entries)
	_refresh_map_seat_markers()
	_refresh_province_winner_colors()

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
	game_settings_label.text = "Baraj: %%%s" % _format_threshold(MultiplayerManager.election_threshold)

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
		child.queue_free()

	for peer_id in _ordered_peer_ids():
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var avatar := _build_avatar(peer_id, party)
		player_panel_list.add_child(avatar)

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
	var pname: String = party.get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?"))
	var suffix := " (Sen)" if peer_id == multiplayer.get_unique_id() else ""
	turn_indicator_label.text = "Sıra:\n%s%s" % [pname, suffix]
	var badge := _build_badge(party, turn_indicator_badge_slot.custom_minimum_size, BADGE_ICON_PIXEL_SIZE)
	turn_indicator_badge_slot.add_child(badge)

func _refresh_deck_button() -> void:
	deck_button.disabled = not CardManager.can_draw()
	deck_button.modulate.a = 1.0 if not deck_button.disabled else 0.5

func _refresh_pass_button() -> void:
	pass_button.disabled = not CardManager.is_my_turn()
	pass_button.modulate.a = 1.0 if not pass_button.disabled else 0.5

## Sıra sende değilken eldeki kartlar tıklanamaz + soluk görünür — kullanıcı
## "neden hiçbir şey olmuyor" diye şaşırmasın diye net bir görsel geri bildirim.
func _refresh_hand_interactivity() -> void:
	var interactive := CardManager.is_my_turn()
	for holder in _hand_holders:
		if not is_instance_valid(holder):
			continue
		holder.modulate.a = 1.0 if interactive else 0.55
		for child in holder.get_children():
			if child is TextureRect and child.get_meta("is_click_target", false):
				child.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE

# --- El (envanter) ----------------------------------------------------------

func _rebuild_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	_hand_holders.clear()
	var hand := CardManager.my_inventory()
	for i in hand.size():
		hand_container.add_child(_build_hand_card(hand[i], i))
	_refresh_hand_interactivity()
	_refresh_deck_button()

func _process(delta: float) -> void:
	_update_avatar_hover()

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

	card.mouse_entered.connect(func(): holder.set_meta("lift_target", -CARD_DISPLAY_SIZE.y * 0.5))
	card.mouse_exited.connect(func(): holder.set_meta("lift_target", 0.0))
	# İleride bu kartlar başka partilere/illere/parlamentoya SÜRÜKLENEBİLECEK
	# (drag & drop) — o yüzden basılı tutmak TEK BAŞINA kartı oynatmamalı,
	# sadece "bas ve hemen bırak" (gerçek bir tık) kart kullanmalı. Bunu
	# ayırt etmek için basma anının zamanını/konumunu kaydedip, bırakma
	# anında hem kısa sürede (TAP_MAX_HOLD_MS) hem de neredeyse aynı yerde
	# (TAP_MAX_MOVE_PX) bırakılmışsa "tık" sayıyoruz; aksi halde (uzun
	# basılı tutma) hiçbir şey yapmıyoruz — bu, ileride sürükleme
	# mekaniğinin devreye gireceği dal.
	card.set_meta("press_time_ms", -1)
	card.set_meta("press_pos", Vector2.ZERO)
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				card.set_meta("press_time_ms", Time.get_ticks_msec())
				card.set_meta("press_pos", event.position)
			else:
				var press_time_ms: int = card.get_meta("press_time_ms", -1)
				if press_time_ms < 0:
					return
				card.set_meta("press_time_ms", -1)
				var elapsed: int = Time.get_ticks_msec() - press_time_ms
				var press_pos: Vector2 = card.get_meta("press_pos", Vector2.ZERO)
				var moved: float = press_pos.distance_to(event.position)
				if elapsed <= TAP_MAX_HOLD_MS and moved <= TAP_MAX_MOVE_PX:
					_on_hand_card_clicked(hand_index)
	)

	wrapper.add_child(holder)
	_hand_holders.append(holder)
	return wrapper

func _on_hand_card_clicked(hand_index: int) -> void:
	if not CardManager.is_my_turn():
		return
	CardManager.play_card(hand_index)

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


func _build_avatar(peer_id: int, party: Dictionary) -> Control:
	var is_self := peer_id == multiplayer.get_unique_id()
	var wrap := _build_badge(party, Vector2(AVATAR_SIZE, AVATAR_SIZE), AVATAR_ICON_PIXEL_SIZE, is_self)
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

## Bir partinin "logosu": arka plan renkli yuvarlak + ikon. Avatar panelinde
## ve tur göstergesinde (daha küçük) aynı görsel kullanılıyor. is_self=true
## ise (sağdaki oyuncu panelinde kendi partin) parlak altın bir kenarlıkla
## belirgin şekilde vurgulanır — herkes kendi avatarını hemen ayırt edebilsin.
func _build_badge(party: Dictionary, size: Vector2, icon_pixel_size: int, is_self: bool = false) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = size
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_color: Color = party.get("bg_color", Color(0.3, 0.3, 0.3))
	var circle := Panel.new()
	# Rozetin içindekiler tamamen DEKORATİF — fare girdisini yutmasınlar
	# (Panel varsayılanı STOP, TextureRect varsayılanı PASS'tir).
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(int(size.y / 2.0))
	if is_self:
		style.border_width_bottom = 4
		style.border_width_top = 4
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_color = Color(1.0, 0.82, 0.15, 1.0)
		style.shadow_size = 10
		style.shadow_color = Color(1.0, 0.82, 0.15, 0.45)
		style.shadow_offset = Vector2.ZERO
	else:
		style.border_width_bottom = 2
		style.border_width_top = 2
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_color = Color(1, 1, 1, 0.5)
		style.shadow_size = 6
		style.shadow_color = SHADOW_COLOR
		style.shadow_offset = Vector2(2, 3)
	circle.add_theme_stylebox_override("panel", style)
	wrap.add_child(circle)

	if party.has("icon_index"):
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = PartyPresets.get_icon_texture(party["icon_index"], icon_pixel_size)
		icon.modulate = party.get("icon_color", Color.WHITE)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var margin := size.y * 0.22
		icon.offset_left = margin
		icon.offset_top = margin
		icon.offset_right = -margin
		icon.offset_bottom = -margin
		wrap.add_child(icon)

	return wrap

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
