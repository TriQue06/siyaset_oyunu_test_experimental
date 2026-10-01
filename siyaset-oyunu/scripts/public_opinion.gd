class_name PublicOpinion
extends RefCounted
## GÜÇ kuralları — saf fonksiyonlar, durum CardManager'da.
##
## Bir partinin bir ildeki seçim desteği iki YAKINLIKTAN oluşur:
##   - İDEOLOJİK yakınlık: partinin görüşü ile ilin görüşü arasındaki mesafe
##     (ElectionModel.support). İller oyuna NÖTRE YAKIN başlar (her eksen
##     −1..+1, bkz. ProvinceIdeology); teşkilat, miting ve yatırım ilin
##     görüşünü partiye ÇEKER. Partiler başta görüşünü seçer, meclis
##     konuşmaları ve yasalarla kayar; GÜÇLÜ olduğu iller onu kısmen takip eder.
##   - AKTİVİTE yakınlığı: o ilde yapılanlar — miting, yatırım, yasa etkileri,
##     karalama (il puanı, tur sonunda söner) + İL BAŞKANLIĞI (seviye başına
##     kalıcı puan).
## Seçimde ideolojik destek şu çarpanla çarpılır:
##   1 + EFFECT_PER_POINT * (ulusal + aktivite)    (MIN_MULT..MAX_MULT arasında)
##
## Dengeyi değiştirmek için sadece bu dosyadaki sabitleri düzenlemek yeterli.

## Denge simülasyonuyla ayarlandı (tools/balance_sim.gd): güç puanları seçimi
## şanstan daha çok belirlesin, son turların hamleleri ağır bassın.
const EFFECT_PER_POINT := 0.10
const MIN_MULT := 0.3
const MAX_MULT := 2.0
## Bir puanın mutlak değer olarak ulaşabileceği en yüksek seviye.
const LIMIT := 10.0
## Tur sonu sönme katsayıları (düşük = eski hamleler çabuk unutulur).
const NATIONAL_DECAY := 0.75
const LOCAL_DECAY := 0.62

# --- Miting -----------------------------------------------------------------
const MITING_LOCAL := 5.0
const MITING_NATIONAL := 0.8
const PROVOCATION_LOCAL := -2.5
const PROVOCATION_NATIONAL := -1.0
## Provokasyon riski: partinin ideolojisi ile ilin MEVCUT siyasi dengesi
## arasındaki mesafe SAFE_DISTANCE'tan küçükse risk yok; FULL_DISTANCE'a
## yaklaştıkça MAX_RISK'e çıkar. İl başkanlığı riski seviye başına azaltır.
const PROVOCATION_MAX_RISK := 0.5
const PROVOCATION_SAFE_DISTANCE := 1.5
const PROVOCATION_FULL_DISTANCE := 9.0
## İlin siyasi dengesinde: il görüşünün ağırlığı 1; bir partinin ağırlığı
## = oy payı (0..1) * SHARE_WEIGHT + pozitif aktivite * LOCAL_WEIGHT.
const BALANCE_SHARE_WEIGHT := 0.5
const BALANCE_LOCAL_WEIGHT := 0.25

# --- Yatırım (sadece hükümet partileri) ---------------------------------------
## Yatırım mitingden etkilidir (miting il +5, ulusal +0.8; üstelik risksiz).
const INVEST_LOCAL := 7.0
const INVEST_NATIONAL := 1.2
const INVEST_PARTNER_LOCAL := 2.5

# --- Popülizm bonusu -----------------------------------------------------------
## Popülizm süren partinin KENDİ hamlelerinin (miting, yatırım, yasa, oy,
## karalama kazancı, gensoru) iyi sonuçları bu çarpanla büyür, kötü sonuçları
## küçülür. Ayrıca karalamanın hasarı ve teşkilatın oy bonusu da bu çarpanla
## büyür, vekil çalma POPULISM_STEAL_MULT kat vekil getirir. Başkalarının ona
## yaptığı karalama etkilenmez.
const POPULISM_GOOD_MULT := 2.0
const POPULISM_BAD_MULT := 0.25
## Popülizm sürerken seçim yapılırsa partinin ulusal puanına eklenir.
const POPULISM_ELECTION_NATIONAL := 1.5
const POPULISM_STEAL_MULT := 1.5

# --- İktidar dengesi ----------------------------------------------------------
## Seçim anında hükümette olan her partiye eklenen ulusal puan. İktidar zaten
## yapısal olarak kaybeder (en büyük parti olmak, saldırıların hedefi olmak):
## bu değer yokken iktidar bir sonraki seçimde ortalama 44 vekil, eski −1.6 ile
## 67 vekil kaybediyordu. +1.1 bu dezavantajı yarıya indirir (bot simülasyonu,
## 40 oyun: iktidar −32, muhalefet +25). İktidar yine dezavantajlıdır.
const GOVERNMENT_FATIGUE := 1.1

# --- Gensoru ------------------------------------------------------------------
## Reddedilen gensoruyu getiren parti bu kadar ulusal destek kaybeder.
const CENSURE_REJECTED_NATIONAL := -1.0

# --- Teşkilat ------------------------------------------------------------------
## Seviyeye göre KALICI aktivite (sönmez): 1 az, 2 orta, 3 yüksek oy bonusu.
## Seviye 0, 1, 2 (2 = tavan; eski 3. seviyenin bonusu buraya taşındı).
const ORG_ACTIVITY_BY_LEVEL := [0.0, 2.0, 6.0]
## MİTİNG ve KARALAMA artık teşkilat ister; izin kontrolü CardManager'da
## (can_miting / can_play_card) yapılır. Buradaki çarpan sadece ETKİ içindir:
## 2. seviye teşkilatın olduğu ilde miting ve karalama biraz daha vurur.
## (Seviye 0 zaten hamle yapamaz; çarpanı 1.0 bırakıyoruz ki kural tek yerde
## dursun ve yanlışlıkla "etkisiz miting" oluşmasın.)
const ORG_ACTION_MULT := [1.0, 1.0, 1.3]
## Seviye başına miting provokasyon riskinin azalma oranı.
const ORG_RISK_REDUCTION_PER_LEVEL := 0.35

# --- Yasalar ------------------------------------------------------------------
## UYUM: ilin yasa eksenindeki değeri × yasanın yönü / 3  (−1..+1).
## Getiren parti, il başına: PROPOSER_POINTS × uyum; kabul edilirse × PASSED_MULT.
## (Meclis yokken sunulan yasa = seçim vaadi: kabul edilmemiş gibi.)
const LAW_PROPOSER_POINTS := 2.0
## GÜNDEM ARTIK ETKİYİ BÜYÜTMEZ: sadece hangi eksende yasa sunulabileceğini
## belirler. Yasanın il etkisi her zaman tek kat (1.0). Partilerin ideolojisi
## zaten her yasada oylarla (sunan 1, evet/hayır 0.5 adım) kayıyor.
const AGENDA_AXIS_MULT := 1.0
const AGENDA_MATCH_MULT := 1.0
const LAW_PASSED_MULT := 2.0
## Oy veren parti (EVET +1 / HAYIR −1, çekimser etkisiz), il başına:
##   VOTE_IDEOLOGY × uyum × oy  (+ aşağıdaki duruş etkisi, sadece EVET'te)
const LAW_VOTE_IDEOLOGY := 1.5
## İktidar partisi muhalefetin yasasına EVET: her ilde (gündemi kaptırdı).
## Yasaya uyumlu illerde ideolojik artı bunu nötre/artıya çevirebilir.
const LAW_GOV_YES_ON_OPPOSITION := -1.0
## KOALİSYON UYUMU (ulusal puan, kısmi): başbakanın partisinin yasasına ortak
## EVET derse uyumlu görünür ve kazanır; HAYIR derse kendisi küçük, başbakanın
## partisi (ortağına yasa geçirtemedi) biraz daha fazla kaybeder.
const LAW_PARTNER_YES_NATIONAL := 0.5
const LAW_PARTNER_NO_NATIONAL := -0.4
const LAW_PM_PARTNER_NO_NATIONAL := -0.8

# --- Koalisyondan çekilme ---------------------------------------------------
## Çekilmek PUAN TABLOSUNA dokunmaz; sadece sonraki seçime yansıyan ulusal
## puanı düşürür. Etki kısmî: taban + bıraktığın bakanlık başına küçük bir ek
## (ne kadar çok görev aldıysan sözünden dönmen o kadar göze batar).
const WITHDRAW_NATIONAL_BASE := -0.5
const WITHDRAW_NATIONAL_PER_POST := -0.25
const WITHDRAW_NATIONAL_LIMIT := -2.0
## Hükümetin sandalyelerinin en az bu kadarını taşıyan ortak çekilirse koalisyon
## fiilen çöker: kalan ortaklar da dağınık görünür ve çekilenin cezasının bu
## oranı kadar (daha az) ulusal puan kaybeder.
const WITHDRAW_BIG_PARTNER_SEAT_SHARE := 0.4
const WITHDRAW_ALLY_SHARE := 0.4

## Koalisyondan çekilen ortağın ulusal puan kaybı (bıraktığı görev sayısına bağlı).
static func withdraw_national(posts: int) -> float:
	var posts_f := float(maxi(posts, 0))
	return maxf(WITHDRAW_NATIONAL_LIMIT, WITHDRAW_NATIONAL_BASE + WITHDRAW_NATIONAL_PER_POST * posts_f)

## Büyük ortak çekilince koalisyonda KALAN ortakların kaybı (daha küçük).
static func withdraw_ally_national(leaver_penalty: float) -> float:
	return leaver_penalty * WITHDRAW_ALLY_SHARE

# --- Kaset / itibar suikastı ------------------------------------------------------
## Hedefin ULUSAL desteğinden doğrudan düşer (il puanlarına dokunmaz).
const REPUTATION_NATIONAL_DAMAGE := 4.0
## İÇ KARIŞIKLIK: hedefin ulusal desteğini düşürür ve partide (gizli)
## karışıklık çıkarır (bkz. TURMOIL_REBELLION).
const REBELLION_NATIONAL_DAMAGE := 1.5
# --- Karalama -----------------------------------------------------------------
## Hedefin kaybı = DAMAGE / (1 + DEFENSE_FACTOR × hedefin il gücü)
## Karalayanın kazancı = GAIN × (1 + ATTACK_FACTOR × karalayanın il gücü)
const PROPAGANDA_DAMAGE := 5.0
## Karalama bir partinin il puanını bunun altına İTEMEZ: parti sarsılır ama o
## ilden silinmez, karşı kampanyayla toparlanabilir.
const PROPAGANDA_FLOOR := -3.0
const PROPAGANDA_GAIN := 1.5
const PROPAGANDA_DEFENSE_FACTOR := 0.5
const PROPAGANDA_ATTACK_FACTOR := 0.3
## Bir partinin bir ildeki GÜCÜ = IDEOLOGY_WEIGHT × ideolojik yakınlık (0..1)
## + ACTIVITY_WEIGHT × pozitif aktivite.
const STRENGTH_IDEOLOGY_WEIGHT := 3.0
const STRENGTH_ACTIVITY_WEIGHT := 0.4

# --- Anket --------------------------------------------------------------------
## Anket sonucundaki her oy payı en fazla bu oranda sapar (%80 doğruluk).
const POLL_ERROR := 0.2

# --- Vekil çalmanın bedeli -------------------------------------------------------
## Vekil transferi seçmene meşru görünmez: ÇALAN parti çalınan vekil başına
## küçük bir ulusal destek kaybeder, ÇALINAN parti "mağduriyet" olarak küçük bir
## destek kazanır. İkisi de kısmidir: hamleyi caydırmaz, bedava da bırakmaz.
## MECLİS DIŞI PARTİ (son seçimde baraj altı) vekil çalarken yarı verimlidir.
## Kartla meclise girse bile ceza sonraki seçime kadar sürer.
const STEAL_OUTSIDER_EFFICIENCY := 0.5

## Vekil çalmanın ulusal bedeli neredeyse simgesel: oyuncular çalmaktan
## caymasın, sadece "bedava değil" hissi kalsın.
const STEAL_THIEF_NATIONAL_PER_SEAT := -0.008
const STEAL_THIEF_NATIONAL_LIMIT := -0.25
const STEAL_VICTIM_NATIONAL_PER_SEAT := 0.012
const STEAL_VICTIM_NATIONAL_LIMIT := 0.35

# --- İllerin ideolojik dönüşümü (Siyasi Kale) ---------------------------------
## Teşkilat, miting, yatırım ve yasa ilin SEÇMEN MERKEZİNİ hamleyi yapan partinin
## görüşüne doğru çeker: merkez += (parti − merkez) × oran (eksen başına).
## Miting ve teşkilat hem görüşü çeker hem oy getirir; yatırım KISMEN çeker ama
## daha çok oy getirir (bkz. INVEST_LOCAL).
const MITING_PULL := 0.10
const INVEST_PULL := 0.05
## Teşkilat kurulunca/geliştirilince bir kez, sonra her tur seviye başına.
const ORG_PULL := 0.06
const ORG_ROUND_PULL := 0.012
## İLİN PARTİYİ TAKİBİ: parti görüş değiştirince il, partinin oradaki oy payı ×
## bu oran kadar aynı yöne kayar (%100 oy alan partinin dönüşünün yarısı).
const PROVINCE_FOLLOW := 0.5
## Partinin kendi kalesi onu daha sadık takip eder.
const STRONGHOLD_FOLLOW_MULT := 1.4
## Yasa bütün illerde SADECE kendi ekseninde, sunanın o eksendeki görüşüne çeker.
const LAW_PULL_PASSED := 0.04
const LAW_PULL_REJECTED := 0.015
## GERİ DÖNÜŞ: çekilmeyen il her tur sonunda kendi DOĞAL görüşüne (oyun
## başındaki merkez) bu oranda geri döner. Dönüşümü kalıcı kılmak sürekli
## emek ister; yoksa tek bir iktidar partisi bütün ülkeyi kendine çekerdi.
const PROVINCE_REVERSION := 0.03

## SİYASİ KALE = o ilde teşkilatı TAM (2. seviye) + kale emeği (o ilde yaptığı
## miting/yatırım sayısı) STRONGHOLD_EFFORT + seçmen yakınlığı THRESHOLD.
## Kale yakınlığı = 1 − mesafe / STRONGHOLD_DISTANCE_SCALE (0..1).
const STRONGHOLD_DISTANCE_SCALE := 6.0
const STRONGHOLD_THRESHOLD := 0.6
const STRONGHOLD_EFFORT := 6.0
## KALE BAKIM İSTER: kale emeği her tur EFFORT_DECAY azalır; sahibinin emeği
## STRONGHOLD_KEEP_EFFORT'un altına inerse (uzun süre o ile uğramadıysa) kale
## düşer. Tur sonunda ilde beklenen oyda sahibini GEÇEN bir parti varsa da düşer.
const STRONGHOLD_EFFORT_DECAY := 0.25
const STRONGHOLD_KEEP_EFFORT := 3.0
## Kale sahibi görüşünü ilden çok uzaklaştırırsa kaleyi kendiliğinden kaybeder.
const STRONGHOLD_LOSS_THRESHOLD := 0.4
## İdeolojik değişim kalkanı: RAKİPLERİN bir kale ili çekme hızı %70 yavaşlar.
const STRONGHOLD_RESISTANCE := 0.7
## Kale sahibine kalıcı aktivite (oy) bonusu; kalesinde karalanan partinin
## kaybı bu çarpanla küçülür. Kale düşünce sahibinin il puanı düşer.
const STRONGHOLD_ACTIVITY := 2.0
const STRONGHOLD_DAMAGE_MULT := 0.5
const STRONGHOLD_FALL_LOCAL := -2.5
## KUŞATMA: kale ilinde rakip mitingi 1 + benzerlik, karalama yarısı kadar puan
## yazar. Bir partinin katkısı en fazla SIEGE_PARTY_CAP + SIEGE_SIMILAR_CAP ×
## benzerlik olur; toplam SIEGE_BREAK'e ulaşınca kale düşer. Böylece tek parti
## kaleyi düşüremez: farklı görüşte 3 parti ya da kale sahibine benzer 2 parti
## gerekir. Sahibinin kendi mitingi kuşatmayı SIEGE_DEFENSE kadar geriletir;
## kuşatma her tur SIEGE_DECAY oranında dağılır.
const SIEGE_BREAK := 6.0
const SIEGE_PARTY_CAP := 2.0
const SIEGE_SIMILAR_CAP := 2.0
const SIEGE_PROPAGANDA := 0.5
const SIEGE_DEFENSE := 2.0
const SIEGE_DECAY := 0.75
## Benzerlik ölçeği: başlangıçtaki zıt köşeler (her eksende ±1,5) arası mesafe.
const SIEGE_SIMILARITY_SCALE := 5.2

## Kuşatan ile kale sahibinin görüş benzerliği (0 zıt köşe .. 1 aynı görüş).
static func siege_similarity(attacker: Dictionary, owner: Dictionary) -> float:
	return clampf(1.0 - ElectionModel.distance(attacker, owner) / SIEGE_SIMILARITY_SCALE, 0.0, 1.0)

# --- Karışıklık ve bölünme ------------------------------------------------------
## GİZLİ KARIŞIKLIK: iç karışıklık kartı çok, kaset biraz yazar. Her tur
## TURMOIL_DECAY ile söner, olumlu hamleler (miting, teşkilat, yatırım, kabul
## edilen yasa, hükümete girmek) toparlar.
const TURMOIL_REBELLION := 3.5
const TURMOIL_REPUTATION := 1.5
const TURMOIL_DECAY := 0.85
const TURMOIL_EASE_MITING := 0.3
const TURMOIL_EASE_ORG := 0.2
const TURMOIL_EASE_INVEST := 0.5
const TURMOIL_EASE_LAW := 0.8
const TURMOIL_EASE_GOVERNMENT := 1.5
## Karışıklık bunu aşan (ve en az SPLIT_MIN_SEATS vekili olan) parti tur sonunda
## BÖLÜNÜR: vekillerinin SPLIT_SEAT_SHARE_MIN..MAX'ı aynı görüşte yeni partiye
## geçer, teşkilatlarının bir kısmı (SPLIT_ORG_CHANCE) onunla gider.
const SPLIT_TURMOIL := 7.0
const SPLIT_MIN_SEATS := 8
const SPLIT_SEAT_SHARE_MIN := 0.35
const SPLIT_SEAT_SHARE_MAX := 0.5
const SPLIT_ORG_CHANCE := 0.4
const SPLIT_NATIONAL_DAMAGE := -1.0
const SPLIT_AFTER_TURMOIL := 4.0
## Ayrılan parti en erken SPLIT_MIN, en geç SPLIT_MAX seçim atlattıktan sonra
## döner; erken dönüş için ana partinin karışıklığı REUNION_TURMOIL'e inmeli.
const SPLIT_MIN_ELECTIONS := 1
const SPLIT_MAX_ELECTIONS := 4
const REUNION_TURMOIL := 2.0

## İlin merkezinin partiye yakınlığı (kale ölçüsü, 0..1).
static func stronghold_closeness(party_ideology: Dictionary, center: Dictionary) -> float:
	return clampf(1.0 - ElectionModel.distance(party_ideology, center) / STRONGHOLD_DISTANCE_SCALE, 0.0, 1.0)

## Bir çekim adımı: yeni merkez (eksen −3..+3 içinde kalır). axis_only verilirse
## sadece o eksen çekilir. Kalesi başkasına ait ilde oran kalkan kadar azalır.
static func pull_center(center: Dictionary, target: Dictionary, rate: float, shielded: bool, axis_only: String = "") -> Dictionary:
	var effective := rate * ((1.0 - STRONGHOLD_RESISTANCE) if shielded else 1.0)
	var result := center.duplicate()
	for axis in AXES:
		if axis_only != "" and axis != axis_only:
			continue
		var c := float(center.get(axis, 0.0))
		result[axis] = clampf(c + (float(target.get(axis, 0.0)) - c) * effective, -3.0, 3.0)
	return result

# --- Parti ideolojisinin esnekliği ---------------------------------------------------
## Merkeze yakın kaymak serbesttir. Radikalleşmek (|görüş| RADICAL_FREE'yi aşınca)
## ve yerleşik bir görüşten ZIT YÖNE dönmek taban güvenini sarsar (ulusal puan).
const RADICAL_FREE := 1.5
const RADICAL_STEP_COST := 0.3     # RADICAL_FREE'nin ötesindeki her yarım adım
const REVERSAL_FREE := 0.5         # bu kadar merkezdeyken dönmek bedava
const REVERSAL_BASE_COST := 0.2
const REVERSAL_PER_POINT_COST := 0.15

## Bir eksendeki kaymanın ulusal puan bedeli (≤ 0).
static func ideology_shift_national(old_value: float, new_value: float) -> float:
	var delta := new_value - old_value
	if is_zero_approx(delta):
		return 0.0
	var penalty := 0.0
	if absf(new_value) > absf(old_value) and absf(new_value) > RADICAL_FREE:
		penalty += RADICAL_STEP_COST * (absf(new_value) - maxf(absf(old_value), RADICAL_FREE)) / 0.5
	if absf(old_value) > REVERSAL_FREE and signf(delta) != signf(old_value):
		penalty += REVERSAL_BASE_COST + REVERSAL_PER_POINT_COST * absf(old_value)
	return -penalty

const AXES := ["economic", "social", "administrative"]

static func org_action_mult(level: int) -> float:
	return float(ORG_ACTION_MULT[clampi(level, 0, ORG_ACTION_MULT.size() - 1)])

static func org_activity(level: int) -> float:
	return float(ORG_ACTIVITY_BY_LEVEL[clampi(level, 0, ORG_ACTIVITY_BY_LEVEL.size() - 1)])

static func clamp_points(value: float) -> float:
	return clampf(value, -LIMIT, LIMIT)

static func multiplier(national: float, local: float) -> float:
	return clampf(1.0 + EFFECT_PER_POINT * (national + local), MIN_MULT, MAX_MULT)

## İlin mevcut siyasi dengesi (3 eksenli bir nokta).
##   voter_center : ilin görüşü
##   shares       : peer_id -> o ildeki son seçim oy yüzdesi (0..100)
##   local        : peer_id -> o ildeki aktivite
##   ideologies   : peer_id -> parti ideolojisi
static func balance_center(voter_center: Dictionary, shares: Dictionary, local: Dictionary, ideologies: Dictionary) -> Dictionary:
	var sum := {}
	for axis in AXES:
		sum[axis] = float(voter_center.get(axis, 0.0))
	var total_weight := 1.0
	for peer_id in ideologies.keys():
		var weight: float = float(shares.get(peer_id, 0.0)) / 100.0 * BALANCE_SHARE_WEIGHT \
			+ maxf(0.0, float(local.get(peer_id, 0.0))) * BALANCE_LOCAL_WEIGHT
		if weight <= 0.0:
			continue
		var ideology: Dictionary = ideologies[peer_id]
		for axis in AXES:
			sum[axis] = float(sum[axis]) + float(ideology.get(axis, 0)) * weight
		total_weight += weight
	var center := {}
	for axis in AXES:
		center[axis] = float(sum[axis]) / total_weight
	return center

## 0..PROVOCATION_MAX_RISK arası provokasyon olasılığı.
static func provocation_risk(party_ideology: Dictionary, center: Dictionary, org_level: int = 0) -> float:
	var d := ElectionModel.distance(party_ideology, center)
	var t: float = clampf((d - PROVOCATION_SAFE_DISTANCE) / (PROVOCATION_FULL_DISTANCE - PROVOCATION_SAFE_DISTANCE), 0.0, 1.0)
	return PROVOCATION_MAX_RISK * t * maxf(0.0, 1.0 - ORG_RISK_REDUCTION_PER_LEVEL * org_level)

## Yasanın bir ille uyumu: −1 (tam zıt) .. +1 (tam uyumlu).
static func law_alignment(center: Dictionary, axis: String, dir: int) -> float:
	return clampf(float(center.get(axis, 0.0)) * dir / 3.0, -1.0, 1.0)

## Yasayı getiren partinin bir ildeki güç değişimi.
static func law_proposer_delta(alignment: float, passed: bool) -> float:
	return LAW_PROPOSER_POINTS * alignment * (LAW_PASSED_MULT if passed else 1.0)

## Oy veren partinin bir ildeki güç değişimi. choice: +1 EVET, 0 ÇEKİMSER, −1 HAYIR.
static func law_vote_delta(alignment: float, choice: int, voter_in_gov: bool, proposer_in_gov: bool) -> float:
	if choice == 0:
		return 0.0
	var delta := LAW_VOTE_IDEOLOGY * alignment * float(choice)
	if choice > 0:
		if voter_in_gov and not proposer_in_gov:
			delta += LAW_GOV_YES_ON_OPPOSITION
	return delta

## Bir partinin bir ildeki gücü (karalamada saldırı/savunma).
static func party_strength(party_ideology: Dictionary, center: Dictionary, activity: float) -> float:
	var closeness := clampf(ElectionModel.support(party_ideology, center) - ElectionModel.SUPPORT_FLOOR, 0.0, 1.0)
	return STRENGTH_IDEOLOGY_WEIGHT * closeness + STRENGTH_ACTIVITY_WEIGHT * maxf(0.0, activity)

static func propaganda_damage(defender_strength: float) -> float:
	return PROPAGANDA_DAMAGE / (1.0 + PROPAGANDA_DEFENSE_FACTOR * maxf(0.0, defender_strength))

static func propaganda_gain(attacker_strength: float) -> float:
	return PROPAGANDA_GAIN * (1.0 + PROPAGANDA_ATTACK_FACTOR * maxf(0.0, attacker_strength))

## Vekil payı değişimi (yüzde puan) -> ulusal puan.
## Çalınan vekil sayısına göre ulusal puan (çalan için eksi, çalınan için artı).
static func steal_thief_national(seats: int) -> float:
	return maxf(float(seats) * STEAL_THIEF_NATIONAL_PER_SEAT, STEAL_THIEF_NATIONAL_LIMIT)

static func steal_victim_national(seats: int) -> float:
	return minf(float(seats) * STEAL_VICTIM_NATIONAL_PER_SEAT, STEAL_VICTIM_NATIONAL_LIMIT)
