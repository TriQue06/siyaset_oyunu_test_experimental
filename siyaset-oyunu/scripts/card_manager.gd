extends Node
## Autoload. Kart envanteri, oynama sırası, tur/seçim döngüsü, seçim sonuçları
## ve oyun sonu. Host yetkili: host-olmayan istemcinin isteği önce host'a
## "any_peer" RPC ile gider, host doğrulayıp uygular ve herkese yayınlar.
##
## TUR AKIŞI (bir oyuncunun sırası)
##   1. İSTERSE desteden en fazla bir kart çeker (el sınırı MAX_HAND_SIZE).
##   2. Sonra bir kart oynar YA DA pas geçer; sıra sonrakine geçer.
##   3. GameRules.TURN_TIMEOUT içinde bir şey yapmazsa otomatik pas geçilir.
##   Hükümet kurulurken / meclis oylarken tur DURUR (is_turn_blocked).
##
## TUR SONU (herkes birer kez oynayınca) — bkz. GameRules
##   - görevdeki hükümet makam puanlarını alır, eksen keskinliği artar,
##   - son tursa oyun biter; seçim turuysa (ya da hükümet kurulamadıysa
##     ERKEN SEÇİM) seçim yapılır ve hükümet kurma aşaması başlar,
##   - tur sonu bir oylamanın ortasına denk gelirse oylama bitene kadar ertelenir.
##
## AĞ SENKRONU
##   Host her yetkili değişiklikte TÜM durumu bir "olay" ile birlikte yayınlar
##   (_receive_state) ve state_version'ı artırır. İl bazlı sonuçlar büyük
##   olduğu için sadece değiştiklerinde pakete eklenir. Host ayrıca
##   HEARTBEAT_INTERVAL'de bir sadece sürüm numaralarını yollar; sürümü farklı
##   olan istemci (bir mesajı kaçırmışsa) tam durumu kendisi ister. Eskiden
##   burada her 4 sn'de koşulsuz tam yayın vardı — asıl sebep röle peer'ının
##   64 KB'lık WebSocket tamponunun büyük paketlerde taşmasıydı (bkz.
##   relay_multiplayer_peer.gd BUFFER_SIZE).

signal inventories_updated
signal turn_order_updated
signal turn_changed(peer_id: int)
## Sadece animasyon için: state güncellenmeden HEMEN ÖNCE yayınlanır
## (my_inventory() hâlâ ESKİ eli verir).
signal card_drawn(peer_id: int, card_type: String)
## HERKESİN ekranında animasyon için: state güncellenmeden HEMEN ÖNCE yayınlanır.
signal card_played(peer_id: int, card_type: String)
## Seçimsiz bir tur bitti (hükümet puanlarını aldı, keskinlik arttı).
signal round_advanced
## Seçim yapıldı (last_vote_shares / last_seats / last_province_results güncel).
signal election_completed
## Milletvekili dağılımı seçim DIŞI bir sebeple değişti (vekil çalma, ayrılan oyuncu).
signal seats_changed
## Oyun bitti (bkz. final_ranking, game_end_reason).
signal game_over

const MAX_HAND_SIZE := 5
const HEARTBEAT_INTERVAL := 5.0
const PROVINCE_SEATS_PATH := "res://data/province_seats.json"

## Koltuk SAYILARI GERÇEK: TBMM'nin il bazlı milletvekili dağılımı (bkz.
## data/province_seats.json; İstanbul/İzmir/Ankara/Bursa'nın seçim bölgeleri
## tek il olarak birleştirildi). Bu değer dosyadaki sayıların toplamıdır.
var TOTAL_SEATS := 390

# peer_id -> Array[String] (her biri CardPresets.CARD_TYPES'tan biri)
var inventories: Dictionary = {}
# Array[int]: oynama sırasına göre peer_id'ler.
var turn_order: Array = []
# turn_order içindeki index; sırası gelen oyuncu turn_order[current_turn_index].
var current_turn_index: int = 0
# Sırası gelen oyuncu bu turda ZATEN kart çekti mi (bir turda en fazla 1 çekiş).
var has_drawn_this_turn: bool = false
## Eksen keskinliği: il bazlı seçim sonuçlarının ne kadar keskin çıkacağını
## belirleyen üs (bkz. ElectionModel). MultiplayerManager.axis_sharpness_start'tan
## başlar, HER TUR SONUNDA axis_sharpness_increment kadar artar (lobi ayarında
## "sınırlı" seçildiyse axis_sharpness_max_value'da durur). Kartların ideoloji
## kaymasını ETKİLEMEZ — kartlar her zaman sabit ±1 kaydırır.
var current_axis_sharpness: float = 0.5

## Şu an oynanan tur (1'den başlar).
var round_number: int = 1
## Son seçimin yapıldığı tur (0 = henüz seçim yok) ve erken seçim olup olmadığı.
var last_election_round: int = 0
var last_election_was_early: bool = false
# peer_id -> float (yüzde, toplamı 100). Son seçimin sonucu.
var last_vote_shares: Dictionary = {}
# peer_id -> int. Son seçimden bu yana (vekil çalma dahil) milletvekili dağılımı.
var last_seats: Dictionary = {}
# province_id -> { peer_id -> {"percent": float, "seats": int} }
var last_province_results: Dictionary = {}
# Son seçimde barajı geçen peer_id'ler.
var passed_threshold: Array = []

var game_finished: bool = false
## [{peer_id, name, leader, color, score, seats}], kazanan başta.
var final_ranking: Array = []
var game_end_reason: String = ""

var state_version: int = 0

# Seçim hesabına giren iller ve koltuk sayıları (yetkili kaynak province_seats.json).
var _province_ids: Array = []
var _province_seat_counts: Dictionary = {}

var _turn_time_left: float = GameRules.TURN_TIMEOUT
var _turn_deadline_ms: int = 0
var _round_end_pending: bool = false
var _heartbeat_timer: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_load_province_seat_counts()

func _process(delta: float) -> void:
	if MultiplayerManager.room_code == "" or not MultiplayerManager.is_host:
		return
	tick(delta)

func _is_local_only() -> bool:
	return MultiplayerManager.room_code == ""

func _is_authority() -> bool:
	return _is_local_only() or MultiplayerManager.is_host

## Host'un zamanlayıcıları (tur süresi, heartbeat). _process çağırır; testler
## doğrudan çağırabilir.
func tick(delta: float) -> void:
	if not _is_authority():
		return
	if not turn_order.is_empty() and not game_finished and not is_turn_blocked():
		_turn_time_left -= delta
		if _turn_time_left <= 0.0:
			_apply_pass(current_turn_peer_id())
	if not _is_local_only():
		_heartbeat_timer += delta
		if _heartbeat_timer >= HEARTBEAT_INTERVAL:
			_heartbeat_timer = 0.0
			_heartbeat.rpc(state_version, GovernmentManager.state_version, PartyManager.state_version)

## Gerçek il bazlı milletvekili sayılarını yükler. İl eklemek/çıkarmak ya da
## koltuk sayısını değiştirmek için SADECE data/province_seats.json yeterli.
func _load_province_seat_counts() -> void:
	_province_seat_counts.clear()
	_province_ids.clear()
	if not FileAccess.file_exists(PROVINCE_SEATS_PATH):
		push_warning("data/province_seats.json bulunamadı — il bazlı seçim sonucu üretilemeyecek.")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PROVINCE_SEATS_PATH))
	if not (parsed is Dictionary):
		push_warning("data/province_seats.json okunamadı — il bazlı seçim sonucu üretilemeyecek.")
		return
	var sum := 0
	for province_id in parsed.keys():
		var seats := int(parsed[province_id])
		if seats <= 0:
			continue
		_province_seat_counts[province_id] = seats
		_province_ids.append(province_id)
		sum += seats
	if sum > 0:
		TOTAL_SEATS = sum

# --- Sorgular ---------------------------------------------------------------

func current_turn_peer_id() -> int:
	if turn_order.is_empty():
		return -1
	return turn_order[current_turn_index % turn_order.size()]

## Hükümet kurulurken, mecliste bir teklif oylanırken ya da oyun bittiyse
## TUR DURUR: kimse kart çekemez, oynayamaz, pas geçemez.
func is_turn_blocked() -> bool:
	return game_finished \
		or GovernmentManager.phase == GovernmentManager.Phase.FORMING \
		or GovernmentManager.phase == GovernmentManager.Phase.VOTING

func is_my_turn() -> bool:
	return current_turn_peer_id() == multiplayer.get_unique_id()

func can_draw() -> bool:
	if is_turn_blocked():
		return false
	if not is_my_turn() or has_drawn_this_turn:
		return false
	return my_inventory().size() < MAX_HAND_SIZE

## Sıra bende VE tur akışı engellenmemiş mi? (UI bunu kullanmalı.)
func can_act() -> bool:
	return is_my_turn() and not is_turn_blocked()

func my_inventory() -> Array:
	return inventories.get(multiplayer.get_unique_id(), [])

## Sıradaki oyuncunun kalan süresi (saniye).
func turn_seconds_left() -> float:
	if is_turn_blocked():
		return GameRules.TURN_TIMEOUT
	if _is_authority():
		return maxf(0.0, _turn_time_left)
	return maxf(0.0, float(_turn_deadline_ms - Time.get_ticks_msec()) / 1000.0)

## Bir partiden vekil çalınabilir mi? Kendinden çalınamaz, meclis dışı partiden
## çalınamaz ve hedefin en az 2 vekili olmalı (1'in altına DÜŞÜRÜLEMEZ).
func is_valid_steal_target(peer_id: int, target_peer_id: int) -> bool:
	if target_peer_id == -1 or target_peer_id == peer_id:
		return false
	if not last_seats.has(target_peer_id):
		return false
	return int(last_seats[target_peer_id]) > 1

## İdeoloji kartı bir RAKİBE oynanabilir mi? (-1 / kendisi = kendi partisi.)
func is_valid_ideology_target(peer_id: int, target_peer_id: int) -> bool:
	if target_peer_id == -1 or target_peer_id == peer_id:
		return true
	return turn_order.has(target_peer_id)

# --- Oyun başlangıcı --------------------------------------------------------

## Sadece host çağırır (Parti Kurulum bitip GameScreen'e geçilirken): tüm oyun
## durumunu sıfırlar, oynama sırasını rastgele belirler, herkese yayınlar.
func init_game() -> void:
	if not _is_authority():
		return
	inventories.clear()
	for peer_id in MultiplayerManager.players.keys():
		inventories[peer_id] = []
	turn_order = MultiplayerManager.players.keys().duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	has_drawn_this_turn = false
	current_axis_sharpness = MultiplayerManager.axis_sharpness_start
	round_number = 1
	last_election_round = 0
	last_election_was_early = false
	last_vote_shares = {}
	last_seats = {}
	last_province_results = {}
	passed_threshold = []
	game_finished = false
	final_ranking = []
	game_end_reason = ""
	_turn_time_left = GameRules.TURN_TIMEOUT
	_round_end_pending = false
	GovernmentManager.reset()
	_push_state({"type": "full"}, true)

# --- Oyuncu eylemleri -------------------------------------------------------

## Sırası gelen oyuncu, deste butonuna basınca çağırır.
func draw_card() -> void:
	if _is_local_only() and turn_order.is_empty():
		# Aktif oyun yok (örn. sahne editörde tek başına test) — yerel önizleme.
		var id := multiplayer.get_unique_id()
		if not inventories.has(id):
			inventories[id] = []
		if inventories[id].size() >= MAX_HAND_SIZE:
			return
		var card_type := CardPresets.random_from(_draw_pool())
		card_drawn.emit(id, card_type)
		inventories[id].insert(inventories[id].size() / 2, card_type)
		inventories_updated.emit()
		return
	if not can_draw():
		return
	if _is_authority():
		_apply_draw(multiplayer.get_unique_id())
	else:
		_request_draw.rpc_id(1)

## Desteden çekilebilecek kartlar. İdeoloji kartları her zaman vardır; özel
## kartlar ancak KOŞULLARI oluşunca girer:
##   - vekil çalma: ilk seçim yapıldıktan sonra (meclis oluştuktan sonra)
##   - gensoru: kurulu bir hükümet salt çoğunluğun ALTINA düştüğünde
func _draw_pool() -> Array:
	var pool: Array = CardPresets.IDEOLOGY_CARD_TYPES.duplicate()
	if not last_seats.is_empty():
		for card_type in CardPresets.STEAL_CARD_TYPES:
			pool.append(card_type)
	if GovernmentManager.has_government() and not GovernmentManager.has_majority():
		pool.append(CardPresets.CENSURE_CARD_TYPE)
	return pool

## Sırası gelen oyuncu elindeki bir kartı oynar (hand_index: my_inventory()
## içindeki sırası).
##
## target_peer_id:
##   - vekil çalma kartlarında ZORUNLU hedef parti,
##   - ideoloji kartlarında İSTEĞE BAĞLI: -1 ise kendi partisine, bir rakip
##     verilirse O PARTİNİN eksenini kaydırır (rakibi seçmenden uzaklaştırma).
func play_card(hand_index: int, target_peer_id: int = -1) -> void:
	if _is_local_only() and turn_order.is_empty():
		var id := multiplayer.get_unique_id()
		var hand: Array = inventories.get(id, [])
		if hand_index < 0 or hand_index >= hand.size():
			return
		var card_type: String = hand[hand_index]
		card_played.emit(id, card_type)
		hand.remove_at(hand_index)
		_apply_card_effect(id, card_type, target_peer_id)
		inventories_updated.emit()
		return
	if not can_act():
		return
	if _is_authority():
		_apply_play(multiplayer.get_unique_id(), hand_index, target_peer_id)
	else:
		_request_play.rpc_id(1, hand_index, target_peer_id)

## Kart oynamadan turu bir sonraki oyuncuya devreder.
func pass_turn() -> void:
	if turn_order.is_empty() or not can_act():
		return
	if _is_authority():
		_apply_pass(multiplayer.get_unique_id())
	else:
		_request_pass.rpc_id(1)

## İstemci: tam durumu host'tan ister (heartbeat sürüm uyuşmazlığında).
func request_full_sync() -> void:
	if _is_authority():
		return
	_request_full_sync.rpc_id(1)

# --- Host tarafı: uygulama --------------------------------------------------

func _apply_draw(peer_id: int) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id() or has_drawn_this_turn:
		return
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	if inventories[peer_id].size() >= MAX_HAND_SIZE:
		return
	var card_type := CardPresets.random_from(_draw_pool())
	card_drawn.emit(peer_id, card_type)
	# Yeni kart elin ORTASINA yerleşir.
	inventories[peer_id].insert(inventories[peer_id].size() / 2, card_type)
	has_drawn_this_turn = true
	_push_state({"type": "drawn", "peer_id": peer_id, "card": card_type})

func _apply_play(peer_id: int, hand_index: int, target_peer_id: int = -1) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
		return
	var hand: Array = inventories.get(peer_id, [])
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_type: String = hand[hand_index]
	# Geçersiz hedefle oynanan kart elde kalır, boşa harcanmaz.
	if CardPresets.needs_target(card_type) and not is_valid_steal_target(peer_id, target_peer_id):
		return
	if CardPresets.is_ideology_card(card_type) and not is_valid_ideology_target(peer_id, target_peer_id):
		return
	card_played.emit(peer_id, card_type)
	hand.remove_at(hand_index)
	var seats_changed_now := _apply_card_effect(peer_id, card_type, target_peer_id)
	var wrapped := _advance_turn()
	_push_state({"type": "played", "peer_id": peer_id, "card": card_type,
		"target": target_peer_id, "seats_changed": seats_changed_now}, seats_changed_now)
	_finish_round_if_needed(wrapped)

func _apply_pass(peer_id: int) -> void:
	if is_turn_blocked() or peer_id != current_turn_peer_id():
		return
	var wrapped := _advance_turn()
	_push_state({"type": "passed", "peer_id": peer_id})
	_finish_round_if_needed(wrapped)

## Kartın etkisini uygular. Milletvekili dağılımı değiştiyse true döner.
func _apply_card_effect(peer_id: int, card_type: String, target_peer_id: int = -1) -> bool:
	if CardPresets.needs_target(card_type):
		return _apply_steal(peer_id, target_peer_id, card_type)
	if CardPresets.is_censure_card(card_type):
		GovernmentManager.submit_censure(peer_id)
		return false
	var effect: Dictionary = CardPresets.CARD_EFFECTS.get(card_type, {})
	if effect.is_empty():
		return false
	var affected := peer_id
	if target_peer_id != -1 and target_peer_id != peer_id and turn_order.has(target_peer_id):
		affected = target_peer_id
	PartyManager.apply_ideology_delta(affected, effect["axis"], int(effect["delta"]))
	return false

## Hedef partiden rastgele sayıda milletvekilini çalıp kartı oynayana aktarır.
## Aralık kartın gücüne göre (CardPresets.STEAL_RANGES). Vekiller RASTGELE
## SEÇİM ÇEVRELERİNDEN alınır (büyük illerden çalınma olasılığı vekil sayısıyla
## orantılı); il bazlı ve ulusal toplamlar HER ZAMAN birlikte değişir.
func _apply_steal(peer_id: int, target_peer_id: int, card_type: String) -> bool:
	if not is_valid_steal_target(peer_id, target_peer_id):
		return false
	var range_info: Dictionary = CardPresets.STEAL_RANGES.get(card_type, {})
	if range_info.is_empty():
		return false
	var wanted: int = _rng.randi_range(int(range_info["min"]), int(range_info["max"]))
	var amount: int = mini(wanted, maxi(0, int(last_seats[target_peer_id]) - 1))
	if amount <= 0:
		return false

	var bag: Array = []
	for province_id in last_province_results.keys():
		var here: int = int(last_province_results[province_id].get(target_peer_id, {}).get("seats", 0))
		for i in here:
			bag.append(province_id)
	bag.shuffle()

	var moved := 0
	for province_id in bag:
		if moved >= amount:
			break
		var entry: Dictionary = last_province_results[province_id]
		var target_entry: Dictionary = entry.get(target_peer_id, {})
		if int(target_entry.get("seats", 0)) <= 0:
			continue
		target_entry["seats"] = int(target_entry["seats"]) - 1
		entry[target_peer_id] = target_entry
		var thief_entry: Dictionary = entry.get(peer_id, {"percent": 0.0, "seats": 0})
		thief_entry["seats"] = int(thief_entry.get("seats", 0)) + 1
		entry[peer_id] = thief_entry
		moved += 1

	# İl bazlı veri yoksa hiçbir şey taşınmaz: harita ile meclisin ayrışmasına
	# (eski "ulusal toplamdan düş" yedeği) izin vermiyoruz.
	if moved == 0:
		return false
	last_seats[target_peer_id] = int(last_seats[target_peer_id]) - moved
	last_seats[peer_id] = int(last_seats.get(peer_id, 0)) + moved
	return true

## Sırayı bir sonrakine devreder; index başa sardıysa (tur bitti) true döner.
func _advance_turn() -> bool:
	var size: int = maxi(1, turn_order.size())
	var wrapped: bool = (current_turn_index + 1) >= size
	current_turn_index = (current_turn_index + 1) % size
	has_drawn_this_turn = false
	_turn_time_left = GameRules.TURN_TIMEOUT
	return wrapped

# --- Tur sonu / seçim / oyun sonu -------------------------------------------

func _finish_round_if_needed(wrapped: bool) -> void:
	if not wrapped or game_finished:
		return
	if is_turn_blocked():
		# Örn. turun son kartı gensoruydu: oylama bitince tur kapanacak.
		_round_end_pending = true
		return
	_finish_round()

func _finish_round() -> void:
	_round_end_pending = false
	# Biten turda görevde olan hükümet görev puanlarını KAZANIR (birikimli).
	GovernmentManager.award_round_scores()
	var finished_round := round_number
	round_number += 1
	current_axis_sharpness += MultiplayerManager.axis_sharpness_increment
	if MultiplayerManager.axis_sharpness_max_enabled:
		current_axis_sharpness = minf(current_axis_sharpness, MultiplayerManager.axis_sharpness_max_value)

	if finished_round >= GameRules.MAX_ROUNDS:
		_end_game("%d tur tamamlandı." % GameRules.MAX_ROUNDS)
		return

	var scheduled := GameRules.is_election_round(finished_round)
	var no_government := not last_seats.is_empty() \
		and not GovernmentManager.has_government() \
		and GovernmentManager.phase == GovernmentManager.Phase.IDLE
	if last_seats.is_empty() or scheduled or no_government:
		_hold_election(finished_round, no_government and not scheduled)
	else:
		_push_state({"type": "round"})

func _hold_election(finished_round: int, early: bool) -> void:
	var ideologies: Dictionary = {}
	for peer_id in turn_order:
		ideologies[peer_id] = PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())
	var result := ElectionModel.compute(ideologies, _province_seat_counts, ElectionModel.load_province_voters(),
		MultiplayerManager.election_threshold, current_axis_sharpness, _rng)
	last_vote_shares = result["vote_shares"]
	last_seats = result["seats"]
	last_province_results = result["province_results"]
	passed_threshold = result["passed_threshold"]
	last_election_round = finished_round
	last_election_was_early = early
	_push_state({"type": "election"}, true)
	# Yeni meclis: hükümet kurma görevi en çok vekili olan partiye verilir.
	GovernmentManager.start_formation()

func _end_game(reason: String) -> void:
	game_finished = true
	game_end_reason = reason
	final_ranking = []
	var ids: Array = turn_order.duplicate()
	ids.sort_custom(func(a, b):
		var sa := GovernmentManager.score_of(a)
		var sb := GovernmentManager.score_of(b)
		if sa != sb:
			return sa > sb
		var va := int(last_seats.get(a, 0))
		var vb := int(last_seats.get(b, 0))
		if va != vb:
			return va > vb
		return a < b
	)
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		final_ranking.append({
			"peer_id": peer_id,
			"name": party.get("name", "?"),
			"leader": MultiplayerManager.players.get(peer_id, {}).get("name", "?"),
			"color": party.get("bg_color", Color(0.5, 0.5, 0.5)),
			"score": GovernmentManager.score_of(peer_id),
			"seats": int(last_seats.get(peer_id, 0)),
		})
	GovernmentManager.end_game()
	_push_state({"type": "game_over"})

## GovernmentManager, tur akışını engelleyen bir aşamadan (kurma/oylama)
## çıkıldığında çağırır: sıradaki oyuncunun süresi baştan başlar ve ertelenmiş
## bir tur sonu varsa şimdi işlenir.
func on_block_state_changed() -> void:
	if not _is_authority() or turn_order.is_empty() or game_finished or is_turn_blocked():
		return
	_turn_time_left = GameRules.TURN_TIMEOUT
	if _round_end_pending:
		_finish_round()
	else:
		_push_state({"type": "timer"})

## Host: oyun sırasında ayrılan oyuncuyu sıradan, envanterden, meclisten ve
## hükümet süreçlerinden çıkarır. Onsuz sırası gelen/oy bekleyen oyun kilitlenirdi.
func remove_player(peer_id: int) -> void:
	if not _is_authority():
		return
	var idx := turn_order.find(peer_id)
	if idx == -1:
		return
	var was_current := idx == current_turn_index
	turn_order.remove_at(idx)
	inventories.erase(peer_id)
	last_seats.erase(peer_id)
	last_vote_shares.erase(peer_id)
	passed_threshold.erase(peer_id)
	for province_id in last_province_results.keys():
		last_province_results[province_id].erase(peer_id)

	var wrapped := false
	if idx < current_turn_index:
		current_turn_index -= 1
	elif was_current:
		has_drawn_this_turn = false
		_turn_time_left = GameRules.TURN_TIMEOUT
		if current_turn_index >= turn_order.size():
			current_turn_index = 0
			wrapped = true

	if game_finished:
		_push_state({"type": "player_left", "peer_id": peer_id}, true)
		return
	GovernmentManager.remove_player(peer_id)
	_push_state({"type": "player_left", "peer_id": peer_id}, true)
	if turn_order.size() < GameRules.MIN_PLAYERS_TO_CONTINUE:
		_end_game("Yeterli oyuncu kalmadı.")
		return
	_finish_round_if_needed(wrapped)

# --- Senkronizasyon ---------------------------------------------------------

func _pack_state(include_results: bool) -> Dictionary:
	var state := {
		"version": state_version,
		"inventories": inventories,
		"turn_order": turn_order,
		"turn_index": current_turn_index,
		"has_drawn": has_drawn_this_turn,
		"sharpness": current_axis_sharpness,
		"round": round_number,
		"turn_time_left": _turn_time_left,
		"last_election_round": last_election_round,
		"early": last_election_was_early,
		"vote_shares": last_vote_shares,
		"seats": last_seats,
		"passed": passed_threshold,
		"game_finished": game_finished,
		"final_ranking": final_ranking,
		"end_reason": game_end_reason,
	}
	if include_results:
		state["province_results"] = last_province_results
	return state

func _apply_state(state: Dictionary) -> void:
	state_version = int(state["version"])
	inventories = state["inventories"]
	turn_order = state["turn_order"]
	current_turn_index = int(state["turn_index"])
	has_drawn_this_turn = bool(state["has_drawn"])
	current_axis_sharpness = float(state["sharpness"])
	round_number = int(state["round"])
	_turn_deadline_ms = Time.get_ticks_msec() + int(float(state["turn_time_left"]) * 1000.0)
	last_election_round = int(state["last_election_round"])
	last_election_was_early = bool(state["early"])
	last_vote_shares = state["vote_shares"]
	last_seats = state["seats"]
	passed_threshold = state["passed"]
	game_finished = bool(state["game_finished"])
	final_ranking = state["final_ranking"]
	game_end_reason = str(state["end_reason"])
	if state.has("province_results"):
		last_province_results = state["province_results"]

## Host: durumu (sürümü artırarak) herkese yayınlar ve olayın sinyallerini
## kendi tarafında da doğrudan atar (.rpc() göndericide çalışmaz).
func _push_state(event: Dictionary, include_results: bool = false) -> void:
	state_version += 1
	if not _is_local_only():
		_receive_state.rpc(_pack_state(include_results or event.get("type", "") in ["full", "election", "player_left"]), event)
	_emit_post_event(event)

func _emit_post_event(event: Dictionary) -> void:
	var type: String = event.get("type", "")
	inventories_updated.emit()
	if type in ["full", "player_left"]:
		turn_order_updated.emit()
	turn_changed.emit(current_turn_peer_id())
	match type:
		"election":
			election_completed.emit()
		"round":
			round_advanced.emit()
		"game_over":
			game_over.emit()
		"full", "player_left":
			seats_changed.emit()
		"played":
			if bool(event.get("seats_changed", false)):
				seats_changed.emit()

@rpc("authority", "reliable")
func _receive_state(state: Dictionary, event: Dictionary) -> void:
	# Animasyon sinyalleri ESKİ state üzerinden kurulsun diye önce bunlar.
	match str(event.get("type", "")):
		"drawn":
			card_drawn.emit(int(event["peer_id"]), str(event["card"]))
		"played":
			card_played.emit(int(event["peer_id"]), str(event["card"]))
	_apply_state(state)
	_emit_post_event(event)

@rpc("authority", "reliable")
func _heartbeat(card_version: int, gov_version: int, party_version: int) -> void:
	if card_version != state_version:
		request_full_sync()
	if gov_version != GovernmentManager.state_version:
		GovernmentManager.request_full_sync()
	if party_version != PartyManager.state_version:
		PartyManager.request_full_sync()

@rpc("any_peer", "reliable")
func _request_full_sync() -> void:
	if not MultiplayerManager.is_host:
		return
	_receive_state.rpc_id(multiplayer.get_remote_sender_id(), _pack_state(true), {"type": "full"})

@rpc("any_peer", "reliable")
func _request_draw() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_draw(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_play(hand_index: int, target_peer_id: int = -1) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_play(multiplayer.get_remote_sender_id(), hand_index, target_peer_id)

@rpc("any_peer", "reliable")
func _request_pass() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_pass(multiplayer.get_remote_sender_id())
