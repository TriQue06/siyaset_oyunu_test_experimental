class_name Economy
extends RefCounted
## EKONOMİ ve VERGİ kuralları — saf fonksiyonlar, durum CardManager.economy'de.
## Dengeyi değiştirmek için sadece bu dosyadaki sabitleri düzenlemek yeterli.
##
## DÖNGÜ (stratejik soru: "parayı ne zaman biriktirip vergiyi ne zaman
## indireyim, seçime kadar o parayı oya çevirecek zamanım var mı?"):
##   yüksek vergi → DEVLET HAZİNESİ hızlı dolar → vergiye duyarlı seçmen
##   grupları hükümetten soğur → vergi indirimi → memnuniyet YAVAŞ YAVAŞ döner
##   → hazineyle yatırım → ek siyasi kazanç. Erken seçim bu döngüyü yarıda
##   kesebilir: o ana kadar GERÇEKLEŞMİŞ etkiler sandığa yansır.
##
## DURUM (CardManager.economy, ağda gider):
##   tax       : vergi kademesi (TAX_LOW / TAX_NORMAL / TAX_HIGH)
##   pressure  : seçmenin HİSSETTİĞİ vergi baskısı (−1 düşük .. +1 yüksek).
##               Vergi değişince hedefe TAX_IMMEDIATE kadar hemen, kalanın
##               TAX_ADJUST'ü her tur sonunda yaklaşır (indirim bir anda seçim
##               kazandırmaz; yüksek vergi de bir anda patlamaz).
##   index     : EKONOMİ (0..100, 50 = olağan). Her tur hedefine ECONOMY_ADJUST
##               kadar yaklaşır; hedef = 50 + vergi etkisi + yatırım ivmesi.
##   boost     : yatırım ivmesi (her yatırım +INVEST_ECONOMY, tur sonunda söner)
##   treasury  : DEVLET HAZİNESİ (milyon ₺). Tur sonunda vergi geliri girer,
##               yatırım hazineden ödenir. Parti manasından AYRIDIR.
##   enflasyon ve işsizlik ayrı durum değildir: ekonomiden, vergiden ve
##   yatırım ivmesinden hesaplanır (tek kaynak, tutarsızlık olmaz).
##
## OYA ETKİSİ — TEK KANAL: hükümet partilerinin seçmen grubu yakınlığına
## GEÇİCİ bir katman (bkz. group_mood, CardManager.effective_groups). Kalıcı
## yakınlığa yazılmaz, ulusal puana ayrıca eklenmez: aynı etki iki kez sayılmaz.
## Başbakanın partisi tam, ortaklar PARTNER_SHARE kadar taşır.

const TAX_LOW := 0
const TAX_NORMAL := 1
const TAX_HIGH := 2
const TAX_LEVELS := [TAX_LOW, TAX_NORMAL, TAX_HIGH]
const TAX_TITLES := ["Düşük", "Normal", "Yüksek"]
const TAX_IDS := ["dusuk", "normal", "yuksek"]
const START_TAX := TAX_NORMAL

# --- Hazine -----------------------------------------------------------------------
## Oyun başında devlet hazinesi (milyon ₺).
const START_TREASURY := 200.0
## Tur sonu vergi geliri (milyon ₺), ekonomi 50 iken. Ekonomi büyüdükçe artar:
## gelir × (REVENUE_ECONOMY_BASE + REVENUE_ECONOMY_SLOPE × ekonomi / 100).
const TAX_REVENUE := [70.0, 100.0, 140.0]
const REVENUE_ECONOMY_BASE := 0.6
const REVENUE_ECONOMY_SLOPE := 0.8

# --- Vergi baskısı ----------------------------------------------------------------
## Kademenin seçmene hedef baskısı.
const TAX_PRESSURE := [-1.0, 0.0, 1.0]
## Yasa kabul edilince farkın bu kadarı HEMEN hissedilir...
const TAX_IMMEDIATE := 0.35
## ...kalanın bu oranı her tur sonunda kapanır (≈ 4 tur = 2 yılda %90).
const TAX_ADJUST := 0.4
## Baskı hedefe bu kadar yakınsa "yerleşti" sayılır.
const SETTLED := 0.03
## Tam YÜKSEK vergi baskısında hükümet partisinin grup yakınlığı kaybı.
## Gruplara göre farklı (vergi yükü işverenin, yaşam maliyeti işçinin ve
## emeklinin talebi; bkz. VoterGroups.GROUPS["issues"]).
const TAX_SENSITIVITY := {
	"isci": 2.0, "isveren": 3.5, "genc": 1.0, "emekli": 1.5,
	"dindar": 0.5, "ilerici": 0.5, "ozerkci": 0.5, "milliyetci": 0.5,
}
## Düşük vergi memnuniyeti, yüksek verginin öfkesinden küçüktür.
const LOW_TAX_GAIN := 0.6

# --- Ekonomi ----------------------------------------------------------------------
const START_INDEX := 50.0
const INDEX_MIN := 5.0
const INDEX_MAX := 95.0
## Vergi kademesinin ekonomi hedefine etkisi (düşük vergi büyütür).
const TAX_GROWTH := [5.0, 0.0, -7.0]
const ECONOMY_ADJUST := 0.35
## Ekonominin (50'den sapma / 50) hükümetin grup yakınlığına etkisi.
const ECONOMY_SENSITIVITY := {
	"isci": 2.0, "isveren": 2.0, "genc": 2.0, "emekli": 1.0,
	"dindar": 0.5, "ilerici": 0.5, "ozerkci": 0.5, "milliyetci": 0.5,
}
## Enflasyon INFLATION_BASE'i her 10 puan aştığında (aylık ve maaşı eriyen)
## gruplardaki kayıp.
const INFLATION_SENSITIVITY := {"emekli": 1.5, "isci": 1.0}
const INFLATION_BASE := 8.0
const INFLATION_PER_INDEX := 0.1
const INFLATION_TAX := [3.0, 0.0, -2.0]
const INFLATION_PER_BOOST := 0.15
const UNEMPLOYMENT_BASE := 10.0
const UNEMPLOYMENT_PER_INDEX := 0.15

# --- Yatırım ----------------------------------------------------------------------
## Yatırım DEVLET HAZİNESİNDEN ödenir (+ partiden GameRules.INVEST_MANA_COST).
const INVEST_COST := 100.0
## Yerel etkinin bu payı hemen, kalanı INVEST_DELAY_ROUNDS tur sonunda eşit
## dilimlerle gelir (yatırım açılışı: tamamlanmadan başarı sayılmaz).
const INVEST_IMMEDIATE := 0.5
const INVEST_DELAY_ROUNDS := 2
## Her yatırım ekonomi ivmesini artırır; ivme her tur BOOST_DECAY ile söner.
const INVEST_ECONOMY := 5.0
const BOOST_DECAY := 0.7
const BOOST_MAX := 25.0

# --- Koalisyon --------------------------------------------------------------------
## Hükümet ortakları ekonomik memnuniyetin bu kadarını taşır (başbakan 1).
const PARTNER_SHARE := 0.6

static func start_state() -> Dictionary:
	return {"tax": START_TAX, "pressure": float(TAX_PRESSURE[START_TAX]), "index": START_INDEX, "boost": 0.0,
		"treasury": START_TREASURY, "revenue": 0.0, "prev": {}, "tax_round": 0, "tax_from": START_TAX,
		"pressure_from": float(TAX_PRESSURE[START_TAX]), "investments": []}

## Eski sürüm durumunda eksik alanlar güvenli varsayılanla doldurulur.
static func normalized(state) -> Dictionary:
	var result := start_state()
	if state is Dictionary:
		for key in result.keys():
			if (state as Dictionary).has(key):
				result[key] = state[key]
	result["tax"] = clampi(int(result["tax"]), TAX_LOW, TAX_HIGH)
	return result

static func tax_title(level: int) -> String:
	return String(TAX_TITLES[clampi(level, TAX_LOW, TAX_HIGH)])

static func tax_id(level: int) -> String:
	return String(TAX_IDS[clampi(level, TAX_LOW, TAX_HIGH)])

static func tax_level_of_id(id: String) -> int:
	return TAX_IDS.find(id)

## Bu kademede, bu ekonomide bir turun vergi geliri.
static func revenue(level: int, index: float) -> float:
	return float(TAX_REVENUE[clampi(level, TAX_LOW, TAX_HIGH)]) \
		* (REVENUE_ECONOMY_BASE + REVENUE_ECONOMY_SLOPE * clampf(index, 0.0, 100.0) / 100.0)

static func target_pressure(level: int) -> float:
	return float(TAX_PRESSURE[clampi(level, TAX_LOW, TAX_HIGH)])

## Vergi değişince hemen hissedilen baskı.
static func pressure_after_change(pressure: float, level: int) -> float:
	return pressure + (target_pressure(level) - pressure) * TAX_IMMEDIATE

## Bir tur sonra hissedilen baskı.
static func pressure_step(pressure: float, level: int) -> float:
	var target := target_pressure(level)
	var next := pressure + (target - pressure) * TAX_ADJUST
	return target if absf(target - next) < SETTLED else next

## Son vergi değişikliğinin ne kadarının yerleştiği (0..1): değişiklik
## anındaki baskıdan (pressure_from) hedefe.
static func settle_ratio(state: Dictionary) -> float:
	var target := target_pressure(int(state["tax"]))
	var start := float(state.get("pressure_from", target))
	if is_equal_approx(start, target):
		return 1.0
	return clampf((float(state["pressure"]) - start) / (target - start), 0.0, 1.0)

static func is_settled(state: Dictionary) -> bool:
	return absf(target_pressure(int(state["tax"])) - float(state["pressure"])) < SETTLED

## Tamamen yerleşmesine kalan yaklaşık tur sayısı.
static func rounds_to_settle(state: Dictionary) -> int:
	var pressure := float(state["pressure"])
	var level := int(state["tax"])
	var rounds := 0
	while absf(target_pressure(level) - pressure) >= SETTLED and rounds < 20:
		pressure = pressure_step(pressure, level)
		rounds += 1
	return rounds

static func index_target(state: Dictionary) -> float:
	return clampf(START_INDEX + float(TAX_GROWTH[int(state["tax"])]) + float(state["boost"]), INDEX_MIN, INDEX_MAX)

static func inflation(state: Dictionary) -> float:
	return clampf(INFLATION_BASE + (float(state["index"]) - START_INDEX) * INFLATION_PER_INDEX
		+ float(INFLATION_TAX[int(state["tax"])]) + float(state["boost"]) * INFLATION_PER_BOOST, 1.0, 40.0)

static func unemployment(state: Dictionary) -> float:
	return clampf(UNEMPLOYMENT_BASE - (float(state["index"]) - START_INDEX) * UNEMPLOYMENT_PER_INDEX, 2.0, 25.0)

## Göstergelerin anlık kopyası (eğilim okları bir önceki turla kıyaslar).
static func snapshot(state: Dictionary) -> Dictionary:
	return {"index": float(state["index"]), "inflation": inflation(state), "unemployment": unemployment(state),
		"treasury": float(state["treasury"])}

## TUR SONU (tek sefer): vergi geliri, baskının yerleşmesi, ekonominin hedefe
## yaklaşması, ivmenin sönmesi. Yatırım dilimleri CardManager'da (il puanı).
static func advance(state: Dictionary) -> void:
	state["prev"] = snapshot(state)
	var income := revenue(int(state["tax"]), float(state["index"]))
	state["revenue"] = income
	state["treasury"] = float(state["treasury"]) + income
	state["pressure"] = pressure_step(float(state["pressure"]), int(state["tax"]))
	var index := float(state["index"])
	state["index"] = clampf(index + (index_target(state) - index) * ECONOMY_ADJUST, INDEX_MIN, INDEX_MAX)
	state["boost"] = minf(BOOST_MAX, float(state["boost"]) * BOOST_DECAY)

## Hükümet partisinin ekonomiden dolayı gruplardaki GEÇİCİ yakınlık değişimi
## (share = 1 başbakan, PARTNER_SHARE ortak). Vergi + ekonomi + enflasyon.
static func group_mood(state: Dictionary, share: float = 1.0) -> Dictionary:
	var result := {}
	if share <= 0.0:
		return result
	var pressure := float(state["pressure"])
	var tax_factor := -pressure if pressure > 0.0 else -pressure * LOW_TAX_GAIN
	var econ := (float(state["index"]) - START_INDEX) / 50.0
	var infl := maxf(0.0, inflation(state) - INFLATION_BASE) / 10.0
	for group in VoterGroups.GROUP_IDS:
		var value := float(TAX_SENSITIVITY.get(group, 0.0)) * tax_factor \
			+ float(ECONOMY_SENSITIVITY.get(group, 0.0)) * econ \
			- float(INFLATION_SENSITIVITY.get(group, 0.0)) * infl
		value *= share
		if absf(value) >= 0.05:
			result[group] = value
	return result

## Sadece vergi baskısının grup etkisi (arayüz önizlemesi için): kademe
## tamamen yerleşince başbakanın partisinde ne olur.
static func tax_mood_at(level: int) -> Dictionary:
	var pressure := target_pressure(level)
	var tax_factor := -pressure if pressure > 0.0 else -pressure * LOW_TAX_GAIN
	var result := {}
	for group in VoterGroups.GROUP_IDS:
		var value := float(TAX_SENSITIVITY.get(group, 0.0)) * tax_factor
		if absf(value) >= 0.05:
			result[group] = value
	return result

## "1.240" gibi binlik ayraçlı tam sayı.
static func money_text(value: float) -> String:
	var negative := value < 0.0
	var digits := str(int(round(absf(value))))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("−" if negative else "") + digits + out

## "1.240 milyon ₺"
static func money_full(value: float) -> String:
	return "%s milyon ₺" % money_text(value)

## "%8,4"
static func percent_text(value: float) -> String:
	return "%" + String.num(value, 1).replace(".", ",")
