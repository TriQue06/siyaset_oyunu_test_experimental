class_name PublicOpinion
extends RefCounted
## GÜÇ kuralları — saf fonksiyonlar, durum CardManager'da.
##
## Bir partinin bir ildeki seçim desteği iki YAKINLIKTAN oluşur:
##   - İDEOLOJİK yakınlık: partinin görüşü ile ilin görüşü arasındaki mesafe
##     (ElectionModel.support). İllerin görüşü oyun başında belirlenir ve
##     değişmez (bkz. ProvinceIdeology); partiler NÖTR başlar, görüşleri
##     sadece sundukları yasalarla kayar.
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
const CENSURE_REJECTED_NATIONAL := -2.0

# --- Teşkilat ------------------------------------------------------------------
## Seviyeye göre KALICI aktivite (sönmez): 1 az, 2 orta, 3 yüksek oy bonusu.
const ORG_ACTIVITY_BY_LEVEL := [0.0, 1.5, 3.5, 6.0]
## Seviye başına miting provokasyon riskinin azalma oranı.
const ORG_RISK_REDUCTION_PER_LEVEL := 0.25

# --- Yasalar ------------------------------------------------------------------
## UYUM: ilin yasa eksenindeki değeri × yasanın yönü / 3  (−1..+1).
## Getiren parti, il başına: PROPOSER_POINTS × uyum; kabul edilirse × PASSED_MULT.
## (Meclis yokken sunulan yasa = seçim vaadi: kabul edilmemiş gibi.)
const LAW_PROPOSER_POINTS := 2.0
const LAW_PASSED_MULT := 2.0
## Oy veren parti (EVET +1 / HAYIR −1, çekimser etkisiz), il başına:
##   VOTE_IDEOLOGY × uyum × oy  (+ aşağıdaki duruş etkisi, sadece EVET'te)
const LAW_VOTE_IDEOLOGY := 1.5
## İktidar partisi muhalefetin yasasına EVET: her ilde (gündemi kaptırdı).
## Yasaya uyumlu illerde ideolojik artı bunu nötre/artıya çevirebilir.
const LAW_GOV_YES_ON_OPPOSITION := -1.0

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

# --- Vekil momentumu ------------------------------------------------------------
## Seçimden bu yana vekil payındaki değişim (yüzde puan) başına ulusal puan:
## vekil çalarak büyüyen parti bir sonraki seçime artıyla girer.
const SEAT_MOMENTUM_PER_POINT := 0.6
const SEAT_MOMENTUM_LIMIT := 4.0

const AXES := ["economic", "social", "administrative"]

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
static func seat_momentum(share_change_points: float) -> float:
	return clampf(share_change_points * SEAT_MOMENTUM_PER_POINT, -SEAT_MOMENTUM_LIMIT, SEAT_MOMENTUM_LIMIT)
