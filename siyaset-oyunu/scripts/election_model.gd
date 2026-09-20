class_name ElectionModel
extends RefCounted
## Seçim hesabı. Saf (durumsuz) fonksiyonlar — ağdan ve sahneden bağımsız,
## doğrudan test edilebilir (bkz. tools/smoke_test_rules.gd).
##
## MODEL
##   1. Her ilin bir SEÇMEN MERKEZİ var: 3 eksende ortalama eğilim
##      (data/province_voters.json — oyun tasarımı soyutlamasıdır, gerçek
##      anket verisi değildir; dengeyi ayarlamak için dosyayı düzenlemek yeter).
##   2. Bir partinin o ildeki desteği, ideolojisinin seçmen merkezine
##      MESAFESİYLE düşer: exp(-d² / 2σ²). Seçmene yakın parti oy toplar;
##      aynı noktada duran iki parti oyu BÖLER — konumlanma stratejisi buradan
##      doğar. İdeoloji kartlarının seçime etkisi de böyle ortaya çıkar.
##   3. Küçük rastgelelik: parti başına ulusal dalga + il başına sapma.
##   4. Eksen keskinliği: il payları bu üsse yükseltilip yeniden normalize
##      edilir (>1 öndekini abartır, <1 payları birbirine yaklaştırır).
##   4b. ÜLKE GENELİ KARIŞIMI: il payı = NATIONAL_BLEND × ulusal pay +
##      (1 - NATIONAL_BLEND) × il payı. Bir yerde %70 alıp başka yerde %0
##      almak olmasın: partinin illerdeki oyu ülke genelindeki oyu etrafında
##      dalgalanır (ağırlıklı ortalama, yani ulusal oy, değişmez).
##   5. Ulusal oy oranı, il paylarının milletvekili sayısıyla ağırlıklı
##      ortalamasıdır (milletvekili sayısı nüfusun vekili).
##   6. BARAJ: ulusal oyu barajın altında kalan parti hiçbir ilde vekil
##      çıkaramaz (hiçbir parti geçemezse baraj uygulanmaz).
##   7. Vekiller her ilde, barajı geçenler arasında D'HONDT ile dağıtılır.

const VOTERS_PATH := "res://data/province_voters.json"
const AXES := ["economic", "social", "administrative"]

const SUPPORT_SIGMA := 2.0
## Ne kadar uzak olursa olsun her partinin il başına alabileceği asgari destek.
const SUPPORT_FLOOR := 0.03
## Şans "yemeğin tuzu" kadar: denge simülasyonuyla kısıldı (0.15 / 0.10'dan).
const PROVINCE_NOISE := 0.07
const NATIONAL_SWING := 0.04

static var _voters_cache: Dictionary = {}

static func load_province_voters() -> Dictionary:
	if not _voters_cache.is_empty():
		return _voters_cache
	if not FileAccess.file_exists(VOTERS_PATH):
		push_warning("%s bulunamadı — tüm iller merkezde (0,0,0) varsayılacak." % VOTERS_PATH)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(VOTERS_PATH))
	if parsed is Dictionary:
		_voters_cache = parsed
	else:
		push_warning("%s okunamadı." % VOTERS_PATH)
	return _voters_cache

static func distance(a: Dictionary, b: Dictionary) -> float:
	var sum_sq := 0.0
	for axis in AXES:
		var diff: float = float(a.get(axis, 0.0)) - float(b.get(axis, 0.0))
		sum_sq += diff * diff
	return sqrt(sum_sq)

## Bir partinin bir seçmen merkezindeki ham desteği (0..1].
static func support(party_ideology: Dictionary, voter_center: Dictionary) -> float:
	var d := distance(party_ideology, voter_center)
	return SUPPORT_FLOOR + exp(-(d * d) / (2.0 * SUPPORT_SIGMA * SUPPORT_SIGMA))

## Rastgelelik OLMADAN beklenen ulusal paylar (karışımdan önce; toplam 1).
## centers: province_id -> seçmen merkezi, local_mod: province_id -> {peer -> puan}.
static func expected_national(parties: Dictionary, centers: Dictionary, province_seats: Dictionary,
		sharpness: float, national_mod: Dictionary = {}, local_mod: Dictionary = {}) -> Dictionary:
	var national := {}
	var total := 0.0
	for province_id in province_seats.keys():
		var n := float(province_seats[province_id])
		if n <= 0.0:
			continue
		var shares := expected_shares(parties, centers.get(province_id, {}), sharpness, national_mod, local_mod.get(province_id, {}))
		for peer_id in shares.keys():
			national[peer_id] = float(national.get(peer_id, 0.0)) + float(shares[peer_id]) / 100.0 * n
		total += n
	if total > 0.0:
		for peer_id in national.keys():
			national[peer_id] = float(national[peer_id]) / total
	return national

## Rastgelelik OLMADAN bir ildeki beklenen oy payları (peer_id -> yüzde).
## Anket kartı kullanır (hata payını CardManager ekler).
## national: ulusal paylar (bkz. expected_national); verilirse il payı onunla karışır.
static func expected_shares(parties: Dictionary, center: Dictionary, sharpness: float,
		national_mod: Dictionary = {}, local_here: Dictionary = {}, national: Dictionary = {}) -> Dictionary:
	var peer_ids: Array = parties.keys()
	peer_ids.sort()
	var raw := {}
	var raw_total := 0.0
	for peer_id in peer_ids:
		var opinion: float = PublicOpinion.multiplier(float(national_mod.get(peer_id, 0.0)), float(local_here.get(peer_id, 0.0)))
		var w: float = support(parties[peer_id], center) * opinion
		raw[peer_id] = w
		raw_total += w
	var result := {}
	if raw_total <= 0.0:
		return result
	var power: float = maxf(sharpness, 0.01)
	var sharp_total := 0.0
	for peer_id in peer_ids:
		var s: float = pow(maxf(float(raw[peer_id]) / raw_total, 0.0001), power)
		result[peer_id] = s
		sharp_total += s
	for peer_id in peer_ids:
		result[peer_id] = float(result[peer_id]) / sharp_total
	result = cap_shares(blend_national(result, national))
	for peer_id in peer_ids:
		result[peer_id] = float(result[peer_id]) * 100.0
	return result

## parties: peer_id -> ideoloji sözlüğü
## province_seats: province_id -> milletvekili sayısı
## voters: province_id -> seçmen merkezi (ideoloji sözlüğü)
## Dönüş:
##   "vote_shares":      peer_id -> ulusal oy yüzdesi (toplam 100)
##   "seats":            peer_id -> toplam milletvekili
##   "province_results": province_id -> { peer_id -> {"percent", "seats"} }
##   "passed_threshold": barajı geçen peer_id'ler
##   modifiers: {"national": {peer_id -> puan}, "local": {province_id -> {peer_id -> puan}}}
##              — KAMUOYU (bkz. PublicOpinion.multiplier). Boşsa etkisiz.
## ULUSAL LİSTE: bu kadar milletvekili illerden değil, barajı geçen partiler
## arasında ULUSAL oy oranına göre (D'Hondt) dağıtılır.
const NATIONAL_LIST_SEATS := 10
## Bir partinin bir ildeki oy payı en fazla bu kadar olabilir: keskinlik
## arttıkça iller %90'ları görmesin. Fazlası diğer partilere oranla dağılır.
const PROVINCE_MAX_SHARE := 0.68
## İl payının ne kadarı ülke genelindeki paydan gelir (bkz. model 4b).
const NATIONAL_BLEND := 0.4

## national: peer_id -> ulusal pay (toplam 1). İl payını onunla karıştırır.
static func blend_national(shares: Dictionary, national: Dictionary) -> Dictionary:
	if national.is_empty():
		return shares
	for peer_id in shares.keys():
		shares[peer_id] = NATIONAL_BLEND * float(national.get(peer_id, 0.0)) + (1.0 - NATIONAL_BLEND) * float(shares[peer_id])
	return shares

## shares: peer_id -> pay (toplam 1). Tavanı aşan payı diğerlerine dağıtır.
static func cap_shares(shares: Dictionary, cap: float = PROVINCE_MAX_SHARE) -> Dictionary:
	if shares.size() < 2:
		return shares
	for _i in 4:
		var excess := 0.0
		var free_total := 0.0
		for peer_id in shares.keys():
			var v: float = shares[peer_id]
			if v > cap:
				excess += v - cap
				shares[peer_id] = cap
			elif v < cap:
				free_total += v
		if excess <= 0.0 or free_total <= 0.0:
			break
		for peer_id in shares.keys():
			var v: float = shares[peer_id]
			if v < cap:
				shares[peer_id] = v + excess * v / free_total
	return shares

static func compute(parties: Dictionary, province_seats: Dictionary, voters: Dictionary,
		threshold_percent: float, sharpness: float, rng: RandomNumberGenerator,
		modifiers: Dictionary = {}) -> Dictionary:
	var national_mod: Dictionary = modifiers.get("national", {})
	var local_mod: Dictionary = modifiers.get("local", {})
	var vote_shares: Dictionary = {}
	var seats: Dictionary = {}
	var province_results: Dictionary = {}
	var result := {
		"vote_shares": vote_shares, "seats": seats,
		"province_results": province_results, "passed_threshold": [], "national_list": {},
	}
	var peer_ids: Array = parties.keys()
	peer_ids.sort()
	var province_ids: Array = []
	var total_seats := 0
	for province_id in province_seats.keys():
		var n: int = int(province_seats[province_id])
		if n > 0:
			province_ids.append(province_id)
			total_seats += n
	province_ids.sort()
	if peer_ids.is_empty() or total_seats <= 0:
		return result

	var swing: Dictionary = {}
	for peer_id in peer_ids:
		swing[peer_id] = rng.randf_range(1.0 - NATIONAL_SWING, 1.0 + NATIONAL_SWING)

	var national: Dictionary = {}
	for peer_id in peer_ids:
		national[peer_id] = 0.0
	var province_shares: Dictionary = {}
	var power: float = maxf(sharpness, 0.01)

	for province_id in province_ids:
		var seats_here: int = int(province_seats[province_id])
		var center: Dictionary = voters.get(province_id, {})
		var local_here: Dictionary = local_mod.get(province_id, {})
		var raw: Dictionary = {}
		var raw_total := 0.0
		for peer_id in peer_ids:
			var opinion: float = PublicOpinion.multiplier(float(national_mod.get(peer_id, 0.0)), float(local_here.get(peer_id, 0.0)))
			var w: float = support(parties[peer_id], center) * float(swing[peer_id]) * opinion \
				* rng.randf_range(1.0 - PROVINCE_NOISE, 1.0 + PROVINCE_NOISE)
			raw[peer_id] = w
			raw_total += w
		var sharpened: Dictionary = {}
		var sharp_total := 0.0
		for peer_id in peer_ids:
			var s: float = pow(maxf(float(raw[peer_id]) / raw_total, 0.0001), power)
			sharpened[peer_id] = s
			sharp_total += s
		var shares: Dictionary = {}
		for peer_id in peer_ids:
			shares[peer_id] = float(sharpened[peer_id]) / sharp_total
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) + float(shares[peer_id]) * seats_here
		province_shares[province_id] = shares

	# Ülke geneli karışımı (model 4b), sonra il tavanı; ulusal oy yeniden toplanır.
	var national_share := {}
	for peer_id in peer_ids:
		national_share[peer_id] = float(national[peer_id]) / float(total_seats)
		national[peer_id] = 0.0
	for province_id in province_ids:
		var shares: Dictionary = cap_shares(blend_national(province_shares[province_id], national_share))
		province_shares[province_id] = shares
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) + float(shares[peer_id]) * int(province_seats[province_id])

	var eligible: Array = []
	for peer_id in peer_ids:
		var percent: float = float(national[peer_id]) / float(total_seats) * 100.0
		vote_shares[peer_id] = percent
		seats[peer_id] = 0
		if percent >= threshold_percent:
			eligible.append(peer_id)
	if eligible.is_empty():
		eligible = peer_ids.duplicate()
	result["passed_threshold"] = eligible

	for province_id in province_ids:
		var shares: Dictionary = province_shares[province_id]
		var alloc := dhondt(shares, eligible, int(province_seats[province_id]))
		var entry: Dictionary = {}
		for peer_id in peer_ids:
			var won: int = int(alloc.get(peer_id, 0))
			entry[peer_id] = {"percent": float(shares[peer_id]) * 100.0, "seats": won}
			seats[peer_id] = int(seats[peer_id]) + won
		province_results[province_id] = entry
	var list_alloc := dhondt(vote_shares, eligible, NATIONAL_LIST_SEATS)
	var national_list := {}
	for peer_id in peer_ids:
		national_list[peer_id] = int(list_alloc.get(peer_id, 0))
		seats[peer_id] = int(seats[peer_id]) + int(national_list[peer_id])
	result["national_list"] = national_list
	return result

## D'Hondt: her koltuk, oy / (aldığı koltuk + 1) oranı en yüksek partiye gider.
## Eşitlikte küçük peer_id kazanır (her istemcide aynı sonuç).
static func dhondt(votes: Dictionary, eligible: Array, seat_count: int) -> Dictionary:
	var alloc: Dictionary = {}
	for peer_id in eligible:
		alloc[peer_id] = 0
	if eligible.is_empty():
		return alloc
	for i in seat_count:
		var best = eligible[0]
		var best_quotient := -1.0
		for peer_id in eligible:
			var q: float = float(votes.get(peer_id, 0.0)) / float(int(alloc[peer_id]) + 1)
			if q > best_quotient + 1e-12 or (absf(q - best_quotient) <= 1e-12 and peer_id < best):
				best_quotient = q
				best = peer_id
		alloc[best] = int(alloc[best]) + 1
	return alloc
