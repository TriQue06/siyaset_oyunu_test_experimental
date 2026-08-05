extends Node
## Autoload. Oyuncuların kart envanterini, oynama sırasını (turn order) ve
## kimin turu olduğunu tutar/senkronize eder. MultiplayerManager/PartyManager
## desenle aynı: host yetkili, host-olmayan bir istemcinin isteği önce host'a
## "any_peer" RPC ile gider, host uygulayıp herkese "authority" RPC ile yayınlar.
##
## Oynama sırası: oyun (GameScreen) başladığında host, o anki oyuncuları
## RASTGELE sıralayıp turn_order'a yazar. Sağ paneldeki oyuncu listesi bu
## sırayla (yukarıdan aşağıya) gösterilir; current_turn_index de aynı diziyi
## işaret eder.
##
## Tur akışı (KESİN kurallar):
##   1. Sırası gelen oyuncu İSTERSE deste butonuna basıp kart çeker — ama bir
##      turda EN FAZLA BİR KEZ (has_drawn_this_turn) VE envanterinde
##      MAX_HAND_SIZE'dan az kart varsa.
##      Bu, animasyon amaçlı sadece o oyuncunun ekranında görünen
##      card_drawn sinyalini tetikler.
##   2. Sonra oyuncu YA elindeki bir kartı oynar (play_card) YA DA pas geçer
##      (pass_turn) — ikisi de turu bir sonraki oyuncuya devreder.
##      play_card, HERKESİN ekranında görünen card_played sinyalini tetikler.

signal inventories_updated
signal turn_order_updated
signal turn_changed(peer_id: int)
## Sadece ÇEKEN oyuncunun kendi ekranında animasyon oynatması için: state
## güncellenmeden HEMEN ÖNCE yayınlanır (my_inventory() hâlâ ESKİ hali verir).
signal card_drawn(peer_id: int, card_type: String)
## HERKESİN ekranında animasyon oynatması için: state güncellenmeden HEMEN
## ÖNCE yayınlanır (my_inventory() hâlâ kartın SİLİNMEDEN ÖNCEKİ halini verir).
signal card_played(peer_id: int, card_type: String)
## Bir "tur" (herkes sırayla bir kez oynayınca) tamamlanınca HERKESİN
## ekranında yayınlanır — GameScreen bunu dinleyip seçim sonuçları
## animasyonuna geçer (bkz. last_vote_shares/last_seats).
signal round_completed

const MAX_HAND_SIZE := 5
## NOT: Gerçek bir oylama/sandık mekaniği henüz tasarlanmadı. Şimdilik her
## turun sonunda PLACEHOLDER bir oy oranı hesaplanıyor (ideolojinin
## merkezden uzaklığına hafif ağırlık + rastgelelik) — ileride gerçek
## mekanikle değiştirilecek, arayüz/akış şimdiden buna göre kuruldu.
## Koltuk SAYILARI (TOTAL_SEATS ve il başına dağılım) İSE GERÇEK: TBMM'nin
## il bazlı milletvekili dağılımından alınmış (bkz. data/province_seats.json;
## İstanbul/İzmir/Ankara/Bursa'nın seçim bölgeleri tek il olarak birleştirildi).
var TOTAL_SEATS := 390

var round_number: int = 1
# peer_id -> float (yüzde, toplamı 100). Son biten turun sonucu.
var last_vote_shares: Dictionary = {}
# peer_id -> int (TOTAL_SEATS'e göre dağıtılmış koltuk sayısı).
var last_seats: Dictionary = {}
# province_id -> { peer_id -> {"percent": float, "seats": int} }. Haritadaki
# milletvekili noktaları ve il hover kutusu bunu kullanır.
var last_province_results: Dictionary = {}

const PROVINCES_DATA_PATH := "res://data/provinces.json"
const PROVINCE_SEATS_PATH := "res://data/province_seats.json"
var _province_ids: Array = []
# province_id -> int (o ildeki GERÇEK milletvekili sayısı).
var _province_seat_counts: Dictionary = {}

## Ara sıra (nadiren) bir istemciye giden delta broadcast (_notify_played vb.)
## ağ katmanında kaybolabiliyor — o istemci o zaman eski tur durumunda takılı
## kalıyor. Bunu kendiliğinden düzeltmek için host, birkaç saniyede bir TÜM
## durumu (_sync_state) yeniden yayınlıyor; hiçbir şey değişmemişse zararsız,
## bir şey kaçmışsa birkaç saniye içinde kendini onarıyor.
const RESYNC_INTERVAL := 4.0
var _resync_timer := 0.0

func _ready() -> void:
	_load_province_ids()
	_load_province_seat_counts()
	set_process(true)

func _process(delta: float) -> void:
	if not MultiplayerManager.is_host or MultiplayerManager.room_code == "":
		return
	_resync_timer += delta
	if _resync_timer < RESYNC_INTERVAL:
		return
	_resync_timer = 0.0
	_sync_state.rpc(inventories, turn_order, current_turn_index, has_drawn_this_turn, current_axis_sharpness)

func _load_province_ids() -> void:
	if not FileAccess.file_exists(PROVINCES_DATA_PATH):
		return
	var file := FileAccess.open(PROVINCES_DATA_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		return
	_province_ids = parsed.keys()

## Gerçek il bazlı milletvekili sayılarını yükler (bkz. data/province_seats.json).
## Bulunamazsa TOTAL_SEATS, illere eşit/yaklaşık dağıtılmış bir yedek listeye düşer.
func _load_province_seat_counts() -> void:
	_province_seat_counts.clear()
	if FileAccess.file_exists(PROVINCE_SEATS_PATH):
		var file := FileAccess.open(PROVINCE_SEATS_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			for province_id in parsed.keys():
				_province_seat_counts[province_id] = int(parsed[province_id])
			var sum := 0
			for v in _province_seat_counts.values():
				sum += v
			if sum > 0:
				TOTAL_SEATS = sum
			return
	push_warning("data/province_seats.json bulunamadı, illere yaklaşık eşit dağıtılıyor.")
	if _province_ids.is_empty():
		return
	var per_province: int = maxi(1, TOTAL_SEATS / _province_ids.size())
	for province_id in _province_ids:
		_province_seat_counts[province_id] = per_province

# peer_id -> Array[String] (her biri CardPresets.CARD_TYPES'tan biri)
var inventories: Dictionary = {}
# Array[int]: oynama sırasına göre peer_id'ler.
var turn_order: Array = []
# turn_order içindeki index; sırası gelen oyuncu turn_order[current_turn_index].
var current_turn_index: int = 0
# Sırası gelen oyuncu bu turda ZATEN kart çekti mi (bir turda en fazla 1 çekiş).
var has_drawn_this_turn: bool = false
## Eksen keskinliği: her kart oynanışında ideoloji kayma miktarını çarpan bir
## katsayı. MultiplayerManager.axis_sharpness_start'tan başlar, her kart
## oynanışında axis_sharpness_increment kadar artar (lobi ayarında "sınırlı"
## seçildiyse axis_sharpness_max_value'da durur).
var current_axis_sharpness: float = 0.5

func current_turn_peer_id() -> int:
	if turn_order.is_empty():
		return -1
	return turn_order[current_turn_index % turn_order.size()]

func is_my_turn() -> bool:
	return current_turn_peer_id() == multiplayer.get_unique_id()

func can_draw() -> bool:
	if not is_my_turn() or has_drawn_this_turn:
		return false
	return my_inventory().size() < MAX_HAND_SIZE

## Sadece host çağırır (Parti Kurulum bitip GameScreen'e geçilirken):
## envanterleri sıfırlar, oynama sırasını rastgele belirler, herkese yayınlar.
func init_game() -> void:
	if not MultiplayerManager.is_host:
		return
	inventories.clear()
	for peer_id in MultiplayerManager.players.keys():
		inventories[peer_id] = []
	turn_order = MultiplayerManager.players.keys().duplicate()
	turn_order.shuffle()
	current_turn_index = 0
	has_drawn_this_turn = false
	current_axis_sharpness = MultiplayerManager.axis_sharpness_start
	_sync_state.rpc(inventories, turn_order, current_turn_index, has_drawn_this_turn, current_axis_sharpness)
	inventories_updated.emit()
	turn_order_updated.emit()
	turn_changed.emit(current_turn_peer_id())

func my_inventory() -> Array:
	return inventories.get(multiplayer.get_unique_id(), [])

## Sırası gelen oyuncu, deste butonuna basınca çağırır: envanterine rastgele
## bir kart ekler. Sırası değilse, bu turda zaten çektiyse ya da eli
## MAX_HAND_SIZE'a ulaştıysa hiçbir şey yapmaz.
func draw_card() -> void:
	if MultiplayerManager.room_code == "":
		# Aktif oda yok (örn. sahne editörde tek başına test) — yerel önizleme.
		var id := multiplayer.get_unique_id()
		if not inventories.has(id):
			inventories[id] = []
		if inventories[id].size() >= MAX_HAND_SIZE:
			return
		var card_type := CardPresets.random_card_type()
		card_drawn.emit(id, card_type)
		inventories[id].insert(inventories[id].size() / 2, card_type)
		inventories_updated.emit()
		return
	if not can_draw():
		return
	if MultiplayerManager.is_host:
		_apply_draw(multiplayer.get_unique_id())
	else:
		_request_draw.rpc_id(1)

## Sırası gelen oyuncu, elindeki bir kartı oynayınca çağırır (hand_index:
## my_inventory() içindeki sırası). Sıra kendisinde değilse hiçbir şey yapmaz.
## Turu bir sonraki oyuncuya devreder.
func play_card(hand_index: int) -> void:
	if MultiplayerManager.room_code == "":
		var id := multiplayer.get_unique_id()
		var hand: Array = inventories.get(id, [])
		if hand_index < 0 or hand_index >= hand.size():
			return
		var card_type: String = hand[hand_index]
		card_played.emit(id, card_type)
		hand.remove_at(hand_index)
		if current_axis_sharpness <= 0.0:
			current_axis_sharpness = MultiplayerManager.axis_sharpness_start
		_apply_card_effect(id, card_type)
		inventories_updated.emit()
		return
	if not is_my_turn():
		return
	if MultiplayerManager.is_host:
		_apply_play(multiplayer.get_unique_id(), hand_index)
	else:
		_request_play.rpc_id(1, hand_index)

## Sırası gelen oyuncu, kart çekmek/oynamak istemeden turu bir sonraki
## oyuncuya devretmek için çağırır (kart oynamadan geçer).
func pass_turn() -> void:
	if MultiplayerManager.room_code == "":
		return
	if not is_my_turn():
		return
	if MultiplayerManager.is_host:
		_apply_pass(multiplayer.get_unique_id())
	else:
		_request_pass.rpc_id(1)

## Sırayı bir sonrakine devreder; herkes bu "lap"ta bir kez oynadıysa
## (index başa sardıysa) true döner — tur/dönem tamamlandı demektir.
func _advance_turn() -> bool:
	var size: int = maxi(1, turn_order.size())
	var wrapped: bool = (current_turn_index + 1) >= size
	current_turn_index = (current_turn_index + 1) % size
	has_drawn_this_turn = false
	return wrapped

## PLACEHOLDER: gerçek oylama mekaniği gelene kadar, her partinin ideoloji
## "aşırılığına" (merkezden uzaklığına) hafif bir ağırlık + rastgelelik
## katarak oy oranı üretir, TOTAL_SEATS'e en büyük kalan yöntemiyle
## (largest remainder) koltuk olarak dağıtır.
func _compute_placeholder_results() -> void:
	var weights: Dictionary = {}
	var total_weight := 0.0
	for peer_id in turn_order:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var ideology: Dictionary = party.get("ideology", IdeologyAxes.default_values())
		var extremeness := 0.0
		for axis in IdeologyAxes.AXES:
			extremeness += absf(float(ideology.get(axis, 0)))
		var weight: float = 1.0 + extremeness * 0.15 + randf() * 1.5
		weights[peer_id] = weight
		total_weight += weight

	last_vote_shares.clear()
	last_seats.clear()
	if total_weight <= 0.0:
		return

	var seat_floats: Dictionary = {}
	var assigned_seats := 0
	for peer_id in weights.keys():
		var percent: float = (weights[peer_id] / total_weight) * 100.0
		last_vote_shares[peer_id] = percent
		var raw_seats: float = (weights[peer_id] / total_weight) * TOTAL_SEATS
		seat_floats[peer_id] = raw_seats
		last_seats[peer_id] = int(floor(raw_seats))
		assigned_seats += last_seats[peer_id]

	# Kalan koltukları (yuvarlama artıkları) en büyük ondalık kısmı olanlara sırayla dağıt.
	var remaining: int = TOTAL_SEATS - assigned_seats
	var by_remainder: Array = weights.keys()
	by_remainder.sort_custom(func(a, b): return (seat_floats[a] - floor(seat_floats[a])) > (seat_floats[b] - floor(seat_floats[b])))
	for i in remaining:
		if i >= by_remainder.size():
			break
		last_seats[by_remainder[i]] += 1

	_compute_placeholder_province_results(weights, total_weight)

## İl bazlı GERÇEK milletvekili sayılarını (bkz. _province_seat_counts,
## data/province_seats.json) kullanır; sadece o koltukların PARTİLER ARASI
## dağılımı hâlâ placeholder (ulusal ağırlıklara il-özel rastgele sapma
## katıp largest-remainder ile paylaştırma). Harita üzerindeki milletvekili
## noktaları ve il hover kutusu bunu kullanıyor.
func _compute_placeholder_province_results(national_weights: Dictionary, national_total_weight: float) -> void:
	last_province_results.clear()
	if _province_ids.is_empty() or national_total_weight <= 0.0:
		return

	# Her il icin parti oy orani/koltugu: ulusal agirliga il-ozel rastgele sapma katip normalize et.
	for province_id in _province_ids:
		var seats_here: int = _province_seat_counts.get(province_id, 0)
		if seats_here <= 0:
			continue
		var local_weights: Dictionary = {}
		var local_total := 0.0
		for peer_id in national_weights.keys():
			var w: float = float(national_weights[peer_id]) * randf_range(0.6, 1.4)
			local_weights[peer_id] = w
			local_total += w
		if local_total <= 0.0:
			continue

		var entry: Dictionary = {}
		var local_seat_floats: Dictionary = {}
		var local_assigned := 0
		for peer_id in local_weights.keys():
			var percent: float = (local_weights[peer_id] / local_total) * 100.0
			var raw_seats: float = (local_weights[peer_id] / local_total) * seats_here
			local_seat_floats[peer_id] = raw_seats
			var s: int = int(floor(raw_seats))
			entry[peer_id] = {"percent": percent, "seats": s}
			local_assigned += s
		var local_remaining: int = seats_here - local_assigned
		var local_by_remainder: Array = local_weights.keys()
		local_by_remainder.sort_custom(func(a, b): return (local_seat_floats[a] - floor(local_seat_floats[a])) > (local_seat_floats[b] - floor(local_seat_floats[b])))
		for i in local_remaining:
			if i >= local_by_remainder.size():
				break
			entry[local_by_remainder[i]]["seats"] += 1
		last_province_results[province_id] = entry

func _finish_round_if_needed(wrapped: bool) -> void:
	if not wrapped:
		return
	round_number += 1
	_compute_placeholder_results()
	_notify_round_completed.rpc(last_vote_shares, last_seats, last_province_results, round_number)
	# Host RPC'nin kendi yerel çağrısına GÜVENMİYOR (bkz. _apply_play'deki not) —
	# sinyali burada da doğrudan yayınlıyoruz ki host'un ekranı da geçsin.
	round_completed.emit()

func _apply_draw(peer_id: int) -> void:
	if peer_id != current_turn_peer_id() or has_drawn_this_turn:
		return
	if not inventories.has(peer_id):
		inventories[peer_id] = []
	if inventories[peer_id].size() >= MAX_HAND_SIZE:
		return
	var card_type := CardPresets.random_card_type()
	# Yeni kart, elin ORTASINA yerleşir (envanter ortadan ikiye ayrılıp
	# arasına girer). İlk turda el boşsa zaten tek başına ortada kalır.
	var insert_index: int = inventories[peer_id].size() / 2
	inventories[peer_id].insert(insert_index, card_type)
	has_drawn_this_turn = true
	_notify_drawn.rpc(peer_id, card_type, inventories, turn_order, current_turn_index, has_drawn_this_turn)
	# Host bu fonksiyonu KENDİ eylemi için de çağırıyor (bkz. draw_card()) ve
	# .rpc()'nin göndericide de otomatik çalışacağına GÜVENMİYORUZ — PartyManager
	# ile aynı desen: state'i zaten doğrudan değiştirdik, sinyali de doğrudan
	# yayınlıyoruz ki host'un kendi ekranı da her zaman güncellensin.
	card_drawn.emit(peer_id, card_type)
	inventories_updated.emit()
	turn_changed.emit(current_turn_peer_id())

func _apply_play(peer_id: int, hand_index: int) -> void:
	if peer_id != current_turn_peer_id():
		return
	var hand: Array = inventories.get(peer_id, [])
	if hand_index < 0 or hand_index >= hand.size():
		return
	var card_type: String = hand[hand_index]
	hand.remove_at(hand_index)
	_apply_card_effect(peer_id, card_type)
	var wrapped := _advance_turn()
	_notify_played.rpc(peer_id, card_type, inventories, turn_order, current_turn_index, has_drawn_this_turn, current_axis_sharpness)
	card_played.emit(peer_id, card_type)
	inventories_updated.emit()
	turn_changed.emit(current_turn_peer_id())
	_finish_round_if_needed(wrapped)

## Kartın etkisini ilgili partinin ideoloji eksenine uygular (bkz.
## CardPresets.CARD_EFFECTS). Etkinin büyüklüğü current_axis_sharpness ile
## ölçeklenir (eksen keskinliği) — sonra keskinlik bir artış payı kadar
## büyür (lobi ayarında "sınırlı" seçildiyse bir tavanda durur). Sadece host
## tarafında (any_peer istekleri de dahil, host doğrulayıp uyguladıktan
## sonra) çağrılır.
func _apply_card_effect(peer_id: int, card_type: String) -> void:
	var effect: Dictionary = CardPresets.CARD_EFFECTS.get(card_type, {})
	if effect.is_empty():
		return
	var scaled_delta: int = int(round(float(effect["delta"]) * current_axis_sharpness))
	if scaled_delta == 0:
		scaled_delta = signi(effect["delta"])
	PartyManager.apply_ideology_delta(peer_id, effect["axis"], scaled_delta)

	current_axis_sharpness += MultiplayerManager.axis_sharpness_increment
	if MultiplayerManager.axis_sharpness_max_enabled:
		current_axis_sharpness = minf(current_axis_sharpness, MultiplayerManager.axis_sharpness_max_value)

func _apply_pass(peer_id: int) -> void:
	if peer_id != current_turn_peer_id():
		return
	var wrapped := _advance_turn()
	_notify_passed.rpc(inventories, turn_order, current_turn_index, has_drawn_this_turn)
	inventories_updated.emit()
	turn_changed.emit(current_turn_peer_id())
	_finish_round_if_needed(wrapped)

@rpc("any_peer", "reliable")
func _request_draw() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_draw(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _request_play(hand_index: int) -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_play(multiplayer.get_remote_sender_id(), hand_index)

@rpc("any_peer", "reliable")
func _request_pass() -> void:
	if not MultiplayerManager.is_host:
		return
	_apply_pass(multiplayer.get_remote_sender_id())

@rpc("authority", "reliable")
func _sync_state(new_inventories: Dictionary, new_turn_order: Array, new_turn_index: int, new_has_drawn: bool, new_axis_sharpness: float) -> void:
	inventories = new_inventories
	turn_order = new_turn_order
	current_turn_index = new_turn_index
	has_drawn_this_turn = new_has_drawn
	current_axis_sharpness = new_axis_sharpness
	inventories_updated.emit()
	turn_order_updated.emit()
	turn_changed.emit(current_turn_peer_id())

@rpc("authority", "reliable")
func _notify_drawn(peer_id: int, card_type: String, new_inventories: Dictionary, new_turn_order: Array, new_turn_index: int, new_has_drawn: bool) -> void:
	# Sinyal, state GÜNCELLENMEDEN önce yayınlanır ki dinleyen taraf (sadece
	# çeken oyuncunun kendi ekranı) "eski" eli görüp animasyonu ona göre kursun.
	card_drawn.emit(peer_id, card_type)
	inventories = new_inventories
	turn_order = new_turn_order
	current_turn_index = new_turn_index
	has_drawn_this_turn = new_has_drawn
	inventories_updated.emit()
	turn_changed.emit(current_turn_peer_id())

@rpc("authority", "reliable")
func _notify_played(peer_id: int, card_type: String, new_inventories: Dictionary, new_turn_order: Array, new_turn_index: int, new_has_drawn: bool, new_axis_sharpness: float) -> void:
	card_played.emit(peer_id, card_type)
	inventories = new_inventories
	turn_order = new_turn_order
	current_turn_index = new_turn_index
	has_drawn_this_turn = new_has_drawn
	current_axis_sharpness = new_axis_sharpness
	inventories_updated.emit()
	turn_changed.emit(current_turn_peer_id())

@rpc("authority", "reliable")
func _notify_passed(new_inventories: Dictionary, new_turn_order: Array, new_turn_index: int, new_has_drawn: bool) -> void:
	inventories = new_inventories
	turn_order = new_turn_order
	current_turn_index = new_turn_index
	has_drawn_this_turn = new_has_drawn
	inventories_updated.emit()
	turn_changed.emit(current_turn_peer_id())

@rpc("authority", "reliable")
func _notify_round_completed(new_vote_shares: Dictionary, new_seats: Dictionary, new_province_results: Dictionary, new_round_number: int) -> void:
	last_vote_shares = new_vote_shares
	last_seats = new_seats
	last_province_results = new_province_results
	round_number = new_round_number
	round_completed.emit()
