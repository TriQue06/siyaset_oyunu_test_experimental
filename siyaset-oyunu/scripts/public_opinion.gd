class_name PublicOpinion
extends RefCounted
## KAMUOYU kuralları. Her partinin seçimler arasında birikip eriyen iki tür
## desteği var (durum CardManager'da tutulur; buradaki fonksiyonlar saf):
##
##   - ULUSAL kamuoyu  : yasalar, iktidar icraatı, provokasyonlar.
##   - İL kamuoyu      : o ilde yapılan miting ve yatırımlar.
##
## Seçimde bir partinin bir ildeki ideolojik desteği şu çarpanla çarpılır:
##   1 + EFFECT_PER_POINT * (ulusal + il)    (MIN_MULT..MAX_MULT arasında)
## Yani +5 puan o ilde ~%30 daha fazla oy demek. Puanlar her tur sonunda
## sıfıra doğru söner (erken kazanılan avantaj sonsuza kadar sürmez,
## seçimden hemen önceki hamleler daha değerlidir).
##
## Dengeyi değiştirmek için sadece bu dosyadaki sabitleri düzenlemek yeterli.

const EFFECT_PER_POINT := 0.06
const MIN_MULT := 0.3
const MAX_MULT := 2.0
## Bir puanın mutlak değer olarak ulaşabileceği en yüksek seviye.
const LIMIT := 10.0
## Tur sonu sönme katsayıları.
const NATIONAL_DECAY := 0.9
const LOCAL_DECAY := 0.85

# --- Miting -----------------------------------------------------------------
const MITING_LOCAL := 3.0
const MITING_NATIONAL := 0.5
const PROVOCATION_LOCAL := -2.5
const PROVOCATION_NATIONAL := -1.0
## Provokasyon riski: partinin ideolojisi ile ilin MEVCUT siyasi dengesi
## arasındaki mesafe SAFE_DISTANCE'tan küçükse risk yok; FULL_DISTANCE'a
## (her eksende uç sağ vs uç sol, ~10.4) yaklaştıkça MAX_RISK'e çıkar.
const PROVOCATION_MAX_RISK := 0.5
const PROVOCATION_SAFE_DISTANCE := 1.5
const PROVOCATION_FULL_DISTANCE := 9.0
## İlin siyasi dengesinde: seçmen eğiliminin ağırlığı 1; bir partinin ağırlığı
## = oy payı (0..1) * SHARE_WEIGHT + pozitif il kamuoyu * LOCAL_WEIGHT.
## Böylece bir ilde güçlenen (oy alan, miting/yatırım yapan) parti o ilin
## dengesini kendi ideolojisine doğru çeker.
const BALANCE_SHARE_WEIGHT := 0.5
const BALANCE_LOCAL_WEIGHT := 0.25

# --- Yatırım (sadece hükümet partileri) ---------------------------------------
const INVEST_LOCAL := 3.0
const INVEST_NATIONAL := 0.5
const INVEST_PARTNER_LOCAL := 1.5

# --- İktidar yorgunluğu -------------------------------------------------------
## Seçim anında hükümette olan her parti bu kadar ulusal eksiyle seçime girer.
const GOVERNMENT_FATIGUE := -1.5

# --- Yasalar ------------------------------------------------------------------
## Tabanın beklediği yönde oy: küçük artı.
const LAW_BASE_REWARD := 0.5
## Tabana TERS oy: taban beklentisinin gücü (1..3) başına eksi.
const LAW_BASE_PENALTY_PER_POINT := 0.8
## Tabana ters oy veren parti, yasanın yönüne eğilimli illerde az da olsa
## yeni seçmen çeker (il başına en fazla bu kadar).
const LAW_NEW_VOTERS_LOCAL := 0.5
## Yasa geçerse getiren partiye: hükümetten / muhalefetten (iktidara rağmen).
const LAW_PASSED_GOVERNMENT := 1.5
const LAW_PASSED_OPPOSITION := 3.5
## Yasa reddedilirse getiren parti.
const LAW_REJECTED := -1.0
## Muhalefetin yasasına EVET diyen hükümet partisi ("gündemi muhalefete
## kaptırdı"). Kendi tabanı da o yasayı destekliyorsa ceza daha küçük.
const GOVERNMENT_YES_ON_OPPOSITION := -1.2
const GOVERNMENT_YES_ON_OPPOSITION_ALIGNED := -0.4

const AXES := ["economic", "social", "administrative"]

static func clamp_points(value: float) -> float:
	return clampf(value, -LIMIT, LIMIT)

static func multiplier(national: float, local: float) -> float:
	return clampf(1.0 + EFFECT_PER_POINT * (national + local), MIN_MULT, MAX_MULT)

## İlin mevcut siyasi dengesi (3 eksenli bir nokta).
##   voter_center : data/province_voters.json'daki seçmen eğilimi
##   shares       : peer_id -> o ildeki son seçim oy yüzdesi (0..100)
##   local        : peer_id -> o ildeki kamuoyu puanı
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
static func provocation_risk(party_ideology: Dictionary, center: Dictionary) -> float:
	var d := ElectionModel.distance(party_ideology, center)
	var t: float = clampf((d - PROVOCATION_SAFE_DISTANCE) / (PROVOCATION_FULL_DISTANCE - PROVOCATION_SAFE_DISTANCE), 0.0, 1.0)
	return PROVOCATION_MAX_RISK * t

## Parti tabanının bir yasadan beklentisi: partinin yasa eksenindeki değeri ×
## yasanın yönü. >0: EVET bekleniyor, <0: HAYIR bekleniyor, 0: taban kayıtsız.
static func law_expectation(party_ideology: Dictionary, law: Dictionary) -> int:
	return int(party_ideology.get(law["axis"], 0)) * int(law["dir"])

## Bir oyun sadece TABAN tepkisinden gelen ulusal kamuoyu değişimi.
static func vote_base_delta(expectation: int, yes: bool) -> float:
	if expectation == 0:
		return 0.0
	if (expectation > 0) == yes:
		return LAW_BASE_REWARD
	return -LAW_BASE_PENALTY_PER_POINT * absi(expectation)

## Tabana ters oy verince bir ilden çekilen yeni seçmen (0 ise etkisiz).
static func law_new_voters_local(voter_center: Dictionary, law: Dictionary, yes: bool) -> float:
	var lean: float = float(voter_center.get(law["axis"], 0.0)) * int(law["dir"]) * (1.0 if yes else -1.0)
	if lean <= 0.5:
		return 0.0
	return LAW_NEW_VOTERS_LOCAL * minf(lean, 2.0) / 2.0
