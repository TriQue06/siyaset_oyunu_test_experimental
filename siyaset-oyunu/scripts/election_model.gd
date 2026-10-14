class_name ElectionModel
extends RefCounted
## Seçim hesabı. Saf (durumsuz) fonksiyonlar — ağdan ve sahneden bağımsız,
## doğrudan test edilebilir (bkz. tools/smoke_test_rules.gd).
##
## MODEL (seçmen grupları, bkz. VoterGroups)
##   1. Her ilin bir SEÇMEN PROFİLİ var: 4 ikili dağılım (işçi/işveren,
##      genç/emekli, dindar/ilerici, özerkçi/milliyetçi). Profil oyun başında
##      üretilir (komşu iller benzer) ve oyun boyunca değişmez.
##   2. Her partinin 8 grupta ULUSAL YAKINLIĞI var (0..100) + grup toplantısının
##      geçici bonusu. Partinin ildeki UYUMU = 4 çiftte (pay × yakınlık)
##      toplamlarının ortalaması; ham destek = exp(SHARPNESS × (uyum − 50)).
##      Aynı gruplara hitap eden iki parti o gruptaki oyu BÖLER.
##   3. Ham destek KAMUOYU çarpanıyla (ulusal puan + il aktivitesi: miting,
##      yatırım, teşkilat, karalama) çarpılır, sonra partiler arasında
##      normalize edilir (il payları toplam %100, negatif olamaz).
##   4. Küçük rastgelelik: parti başına ulusal dalga + il başına sapma.
##   4b. ÜLKE GENELİ KARIŞIMI: il payı = NATIONAL_BLEND × ulusal pay +
##      (1 - NATIONAL_BLEND) × il payı. Ulusal pay aynı il paylarının vekil
##      ağırlıklı ortalamasıdır (ek bir grup etkisi DEĞİL): grup yakınlığı
##      bir kez sayılır, karışım sadece illerdeki uçları yumuşatır.
##   5. Ulusal oy oranı, il paylarının milletvekili sayısıyla ağırlıklı
##      ortalamasıdır (milletvekili sayısı nüfusun vekili).
##   6. BARAJ: ulusal oyu barajın altında kalan parti hiçbir ilde vekil
##      çıkaramaz (hiçbir parti geçemezse baraj uygulanmaz).
##   7. Vekiller her ilde, barajı geçenler arasında geçerli sayım yöntemiyle
##      (D'Hondt / Hare / kazanan hepsini alır) dağıtılır.
##
## parties: peer_id -> grup yakınlıkları {grup: 0..100} (bonuslar eklenmiş)
## voters : province_id -> il profili {çift: ilk grubun yüzdesi}

const PROVINCE_NOISE := 0.07
const NATIONAL_SWING := 0.04

static var _voters_cache: Dictionary = {}
static var _voters_cache_seed: int = -1

## Oyun kurulmamışken (menü, testler) kullanılan ÖRNEK il profilleri: o anki
## haritanın bölgeleri için sabit tohumla üretilir. Oyunda asıl profiller
## CardManager.province_profiles'tadır.
static func load_province_voters() -> Dictionary:
	var map = Engine.get_main_loop().root.get_node_or_null("GameMap") if Engine.get_main_loop() is SceneTree else null
	if map == null:
		return {}
	if _voters_cache_seed == map.seed_value() and not _voters_cache.is_empty():
		return _voters_cache
	var rng := RandomNumberGenerator.new()
	rng.seed = 1950
	_voters_cache = VoterGroups.generate_profiles(rng, map.province_ids())
	_voters_cache_seed = map.seed_value()
	return _voters_cache

## Bir partinin bir ildeki ham desteği (> 0): il uyumunun oy ağırlığı.
static func support(affinities: Dictionary, profile: Dictionary) -> float:
	return VoterGroups.vote_weight(VoterGroups.appeal(affinities, profile))

## GRUP BAZLI OY (0.0.186): ildeki her seçmen grubu (4 çiftin iki tarafı, ilin
## profiline göre büyüklük) oyunu partiler arasında KENDİ içinde paylaştırır:
## partinin o gruptaki ağırlığı exp(GROUP_SHARPNESS × (yakınlık − 50)) ×
## kamuoyu. Bir gruba çok yakın parti (ör. emeklilerde 85, rakipler 50-60) o
## grubun oylarının büyük kısmını alır; il payı grupların toplamıdır.
## weights: peer_id -> kamuoyu / dalgalanma çarpanı (> 0).
const GROUP_SHARPNESS := 0.09

static func group_vote_shares(parties: Dictionary, profile: Dictionary, weights: Dictionary) -> Dictionary:
	var peer_ids: Array = parties.keys()
	var result := {}
	for peer_id in peer_ids:
		result[peer_id] = 0.0
	if peer_ids.is_empty():
		return result
	for pair in VoterGroups.PAIR_IDS:
		var groups: Array = VoterGroups.PAIRS[pair]
		var first := VoterGroups.share(profile, groups[0])
		for k in 2:
			var counts: Dictionary = profile.get("_counts", {})
			var population := float(profile.get("_electorate", 0))
			var fraction := float(counts.get(groups[k], 0)) / population if population > 0 else (first if k == 0 else 1.0 - first)
			var size := fraction / float(VoterGroups.PAIR_IDS.size())
			if size <= 0.0:
				continue
			var in_group := shares_in_group(parties, String(groups[k]), weights)
			for peer_id in peer_ids:
				result[peer_id] = float(result[peer_id]) + size * float(in_group[peer_id])
	return result

## Bir grubun oylarının partiler arasındaki dağılımı (0..1).
static func shares_in_group(parties: Dictionary, group: String, weights: Dictionary = {}) -> Dictionary:
	var raw := {}
	var total := 0.0
	for peer_id in parties.keys():
		var aff := float((parties[peer_id] as Dictionary).get(group, VoterGroups.AFFINITY_NEUTRAL))
		raw[peer_id] = exp(GROUP_SHARPNESS * (aff - VoterGroups.AFFINITY_NEUTRAL)) * float(weights.get(peer_id, 1.0))
		total += float(raw[peer_id])
	for peer_id in raw.keys():
		raw[peer_id] = float(raw[peer_id]) / maxf(total, 0.0001)
	return raw

## Rastgelelik OLMADAN beklenen ulusal paylar (karışımdan önce; toplam 1).
## profiles: province_id -> il profili, local_mod: province_id -> {peer -> puan}.
static func expected_national(parties: Dictionary, profiles: Dictionary, province_seats: Dictionary,
		national_mod: Dictionary = {}, local_mod: Dictionary = {}) -> Dictionary:
	var national := {}
	var total := 0.0
	for province_id in province_seats.keys():
		var n := float(profiles.get(province_id, {}).get("_electorate", province_seats[province_id]))
		if n <= 0.0:
			continue
		var shares := expected_shares(parties, profiles.get(province_id, {}), national_mod, local_mod.get(province_id, {}))
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
static func expected_shares(parties: Dictionary, profile: Dictionary,
		national_mod: Dictionary = {}, local_here: Dictionary = {}, national: Dictionary = {}) -> Dictionary:
	var peer_ids: Array = parties.keys()
	peer_ids.sort()
	var weights := {}
	for peer_id in peer_ids:
		weights[peer_id] = PublicOpinion.multiplier(float(national_mod.get(peer_id, 0.0)), float(local_here.get(peer_id, 0.0)))
	var result := group_vote_shares(parties, profile, weights)
	if result.is_empty():
		return result
	result = cap_shares(blend_national(result, national))
	for peer_id in peer_ids:
		result[peer_id] = float(result[peer_id]) * 100.0
	return result

## parties: peer_id -> grup yakınlıkları
## province_seats: province_id -> milletvekili sayısı
## voters: province_id -> il profili
## Dönüş:
##   "vote_shares":      peer_id -> ulusal oy yüzdesi (toplam 100)
##   "seats":            peer_id -> toplam milletvekili
##   "province_results": province_id -> { peer_id -> {"percent", "seats"} }
##   "passed_threshold": barajı geçen peer_id'ler
##   modifiers: {"national": {peer_id -> puan}, "local": {province_id -> {peer_id -> puan}}}
##              — KAMUOYU (bkz. PublicOpinion.multiplier). Boşsa etkisiz.
## ULUSAL LİSTE: bu kadar milletvekili illerden değil, barajı geçen partiler
## arasında ULUSAL oy oranına göre (D'Hondt) dağıtılır.
## ULUSAL LİSTE: il seçim çevrelerinin dışında, ülke geneli oy oranına göre
## D'Hondt ile dağıtılan vekiller. Vekil çalma bunlara da erişir
## (bkz. CardManager._apply_steal — torbada "" ulusal listeyi temsil eder).
static var NATIONAL_LIST_SEATS := 200
## Bir partinin bir ildeki oy payı en fazla bu kadar olabilir. Fazlası diğer
## partilere oranla dağılır.
const PROVINCE_MAX_SHARE := 0.92
## İl payının ne kadarı ülke genelindeki paydan gelir (bkz. model 4b).
const NATIONAL_BLEND := 0.08

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
		threshold_percent: float, rng: RandomNumberGenerator,
		modifiers: Dictionary = {}, alliance_membership: Dictionary = {}) -> Dictionary:
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
	var electorate_total := 0.0
	for province_id in province_seats.keys():
		var n: int = int(province_seats[province_id])
		if n > 0:
			province_ids.append(province_id)
			total_seats += n
			electorate_total += float(voters.get(province_id, {}).get("_electorate", n))
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

	for province_id in province_ids:
		var seats_here: float = float(voters.get(province_id, {}).get("_electorate", province_seats[province_id]))
		var profile: Dictionary = voters.get(province_id, {})
		var local_here: Dictionary = local_mod.get(province_id, {})
		var weights: Dictionary = {}
		for peer_id in peer_ids:
			var opinion: float = PublicOpinion.multiplier(float(national_mod.get(peer_id, 0.0)), float(local_here.get(peer_id, 0.0)))
			weights[peer_id] = float(swing[peer_id]) * opinion * rng.randf_range(1.0 - PROVINCE_NOISE, 1.0 + PROVINCE_NOISE)
		var shares: Dictionary = group_vote_shares(parties, profile, weights)
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) + float(shares[peer_id]) * seats_here
		province_shares[province_id] = shares

	# Ülke geneli karışımı (model 4b), sonra il tavanı; ulusal oy yeniden toplanır.
	var national_share := {}
	for peer_id in peer_ids:
		national_share[peer_id] = float(national[peer_id]) / electorate_total
		national[peer_id] = 0.0
	for province_id in province_ids:
		var shares: Dictionary = cap_shares(blend_national(province_shares[province_id], national_share))
		province_shares[province_id] = shares
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) + float(shares[peer_id]) * float(voters.get(province_id, {}).get("_electorate", province_seats[province_id]))

	var eligible: Array = []
	var alliance_totals := {}
	for peer_id in peer_ids:
		var percent: float = float(national[peer_id]) / electorate_total * 100.0
		vote_shares[peer_id] = percent
		seats[peer_id] = 0
		var alliance_id := int(alliance_membership.get(peer_id, 0))
		if alliance_id != 0:
			alliance_totals[alliance_id] = float(alliance_totals.get(alliance_id, 0.0)) + percent
		elif percent >= threshold_percent:
			eligible.append(peer_id)
	for peer_id in peer_ids:
		var alliance_id := int(alliance_membership.get(peer_id, 0))
		if alliance_id != 0 and float(alliance_totals.get(alliance_id, 0.0)) >= threshold_percent:
			eligible.append(peer_id)
	if eligible.is_empty():
		eligible = peer_ids.duplicate()
	result["passed_threshold"] = eligible

	for province_id in province_ids:
		var shares: Dictionary = province_shares[province_id]
		var groups := _alliance_vote_groups(shares, eligible, alliance_membership)
		var group_eligible := groups.keys()
		var group_alloc := allocate(groups, group_eligible, int(province_seats[province_id]))
		var alloc := {}
		for peer_id in peer_ids:
			alloc[peer_id] = 0
		for entity in group_eligible:
			var won := int(group_alloc.get(entity, 0))
			if int(entity) < 0:
				var alliance_id := -int(entity) - 1
				var members: Array = []
				for member in eligible:
					if int(alliance_membership.get(member, 0)) == alliance_id:
						members.append(member)
				var inner := allocate(shares, members, won)
				for member in members:
					alloc[member] = int(inner.get(member, 0))
			else:
				alloc[entity] = won
		var entry: Dictionary = {}
		for peer_id in peer_ids:
			var won: int = int(alloc.get(peer_id, 0))
			entry[peer_id] = {"percent": float(shares[peer_id]) * 100.0, "seats": won}
			seats[peer_id] = int(seats[peer_id]) + won
		province_results[province_id] = entry
	var national_groups := _alliance_vote_groups(vote_shares, eligible, alliance_membership)
	var national_group_alloc := allocate(national_groups, national_groups.keys(), NATIONAL_LIST_SEATS, true)
	var national_list := {}
	for peer_id in peer_ids:
		national_list[peer_id] = 0
	for entity in national_groups.keys():
		var won := int(national_group_alloc.get(entity, 0))
		if int(entity) < 0:
			var alliance_id := -int(entity) - 1
			var members: Array = []
			for member in eligible:
				if int(alliance_membership.get(member, 0)) == alliance_id:
					members.append(member)
			var inner := allocate(vote_shares, members, won, true)
			for member in members:
				national_list[member] = int(inner.get(member, 0))
		else:
			national_list[entity] = won
	for peer_id in peer_ids:
		seats[peer_id] = int(seats[peer_id]) + int(national_list[peer_id])
	result["national_list"] = national_list
	return result

## İttifaklı partiler seçim çevresinde önce ortak toplam oyla vekil kazanır;
## bu vekiller sonra aynı çevrede ittifak üyelerinin kendi oylarına göre dağılır.
static func _alliance_vote_groups(shares: Dictionary, eligible: Array, membership: Dictionary) -> Dictionary:
	var grouped := {}
	for peer_id in eligible:
		var alliance_id := int(membership.get(peer_id, 0))
		var entity: int = -(alliance_id + 1) if alliance_id != 0 else int(peer_id)
		grouped[entity] = float(grouped.get(entity, 0.0)) + float(shares.get(peer_id, 0.0))
	return grouped

## SAYIM YÖNTEMİ (anayasayla değişir, bkz. MultiplayerManager.seat_method):
##   "dhondt" : D'Hondt (büyük partiye hafif avantaj)
##   "hare"   : Hare kotası + en büyük kalan (en orantılı, küçük partiye iyi)
##   "wta"    : Kazanan hepsini alır (ildeki birinci bütün vekilleri alır)
## Ulusal liste "wta"da D'Hondt ile dağılır (200 vekilin tek partiye gitmesi
## meclisi anlamsızlaştırırdı).
const METHOD_DHONDT := "dhondt"
const METHOD_HARE := "hare"
const METHOD_WTA := "wta"
const SEAT_METHODS := [METHOD_DHONDT, METHOD_HARE, METHOD_WTA]
static var seat_method: String = METHOD_DHONDT

static func method_title(method: String) -> String:
	match method:
		METHOD_HARE:
			return L.t("Hare kotası")
		METHOD_WTA:
			return L.t("Kazanan hepsini alır")
	return L.t("D'Hondt")

## Geçerli sayım yöntemiyle vekil dağıtımı. national_list=true: ulusal liste.
static func allocate(votes: Dictionary, eligible: Array, seat_count: int, national_list: bool = false) -> Dictionary:
	match seat_method:
		METHOD_HARE:
			return hare(votes, eligible, seat_count)
		METHOD_WTA:
			return dhondt(votes, eligible, seat_count) if national_list else winner_takes_all(votes, eligible, seat_count)
	return dhondt(votes, eligible, seat_count)

## Hare kotası + en büyük kalan: kota = toplam oy / koltuk; herkes kotası kadar
## tam koltuk alır, kalan koltuklar en büyük kalana gider (eşitlikte küçük peer_id).
static func hare(votes: Dictionary, eligible: Array, seat_count: int) -> Dictionary:
	var alloc: Dictionary = {}
	for peer_id in eligible:
		alloc[peer_id] = 0
	if eligible.is_empty() or seat_count <= 0:
		return alloc
	var total := 0.0
	for peer_id in eligible:
		total += maxf(0.0, float(votes.get(peer_id, 0.0)))
	if total <= 0.0:
		return dhondt(votes, eligible, seat_count)
	var given := 0
	var remainders: Array = []
	for peer_id in eligible:
		var exact: float = maxf(0.0, float(votes.get(peer_id, 0.0))) / total * seat_count
		var whole := int(floor(exact))
		alloc[peer_id] = whole
		given += whole
		remainders.append([exact - whole, peer_id])
	remainders.sort_custom(func(a, b): return a[0] > b[0] + 1e-12 or (absf(a[0] - b[0]) <= 1e-12 and a[1] < b[1]))
	var k := 0
	while given < seat_count:
		var peer_id = remainders[k % remainders.size()][1]
		alloc[peer_id] = int(alloc[peer_id]) + 1
		given += 1
		k += 1
	return alloc

## Kazanan hepsini alır: en çok oyu alan bütün koltukları alır (eşitlikte küçük peer_id).
static func winner_takes_all(votes: Dictionary, eligible: Array, seat_count: int) -> Dictionary:
	var alloc: Dictionary = {}
	for peer_id in eligible:
		alloc[peer_id] = 0
	if eligible.is_empty():
		return alloc
	var best = eligible[0]
	for peer_id in eligible:
		var v := float(votes.get(peer_id, 0.0))
		var b := float(votes.get(best, 0.0))
		if v > b + 1e-12 or (absf(v - b) <= 1e-12 and peer_id < best):
			best = peer_id
	alloc[best] = seat_count
	return alloc

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
