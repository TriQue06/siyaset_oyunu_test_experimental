class_name Economy
extends RefCounted
## EKONOMİ ve VERGİ kuralları — saf fonksiyonlar, durum CardManager.economy'de.
## Dengeyi değiştirmek için sadece bu dosyadaki sabitleri düzenlemek yeterli.
##
## DÖNGÜ (0.0.259): yüksek vergi → DEVLET HAZİNESİ hızlı dolar ama hükümet
## her sırada ulusal puan kaybeder; düşük vergi her sırada puan kazandırır ama
## hazine yavaş dolar. Etki seçime yaklaştıkça artar (döngünün n. turu ×n).
## Enflasyon, işsizlik ve ekonomi göstergesi şimdilik yok.
##
## DURUM (CardManager.economy, ağda gider):
##   tax       : vergi kademesi (TAX_LOW / TAX_NORMAL / TAX_HIGH)
##   treasury  : DEVLET HAZİNESİ (milyon ¤). Tur sonunda vergi geliri girer,
##               yatırım hazineden ödenir. Parti kasalarından AYRIDIR.
##
## OYA ETKİSİ: her sıranın başında hükümet partilerine TAX_TURN_NATIONAL ×
## döngü çarpanı, bakanlık puanı payına göre bölünerek ulusal puan yazılır.

const TAX_LOW := 0
const TAX_NORMAL := 1
const TAX_HIGH := 2
const TAX_LEVELS := [TAX_LOW, TAX_NORMAL, TAX_HIGH]
const TAX_TITLES := ["Düşük", "Normal", "Yüksek"]
const TAX_IDS := ["dusuk", "normal", "yuksek"]
const START_TAX := TAX_NORMAL

# --- Hazine -----------------------------------------------------------------------
## Oyun başında devlet hazinesi (milyon ¤).
const START_TREASURY := 200.0
## Tur sonu vergi geliri (milyon ¤), kademeye göre (0.0.259: ekonomi
## göstergesi kalktı, gelir sabit).
const TAX_REVENUE := [70.0, 100.0, 140.0]

# --- Vergi ve seçmen (0.0.259) ------------------------------------------------------
## Her SIRADA (her oyuncunun sırası başında) hükümete yazılan ulusal puan:
## düşük vergi artı, normal yok, yüksek eksi. Seçim döngüsündeki tur sırasıyla
## çarpılır (1., 2., 3., 4. tur: 1x..4x) ve hükümet partileri arasında
## bakanlık puanı payına göre bölünür (CardManager._apply_tax_tick).
const TAX_TURN_NATIONAL := [0.06, 0.0, -0.06]

# --- Yatırım ----------------------------------------------------------------------
## Yatırım DEVLET HAZİNESİNDEN ödenir (+ partiden GameRules.INVEST_FUNDS_COST).
const INVEST_COST := 100.0

## Seçmen etkisinin bu payı hemen, kalanı INVEST_DELAY_ROUNDS tur sonunda
## eşit dilimlerle gelir. 0.0.286: yatırımın tamamı HEMEN gelir (dilim yok).
const INVEST_IMMEDIATE := 1.0
const INVEST_DELAY_ROUNDS := 2
## YATIRIM GÜCÜ: etki = (tutar / INVEST_COST) ^ INVEST_SCALE_POWER; büyük
## yatırım orantıdan fazla güçlüdür (50 M ≈ 0,44, 100 M = 1, 150 M ≈ 1,63).
const INVEST_SCALE_POWER := 1.2

## Yatırım tutarının seçmen etkisi ölçeği (bkz. INVEST_SCALE_POWER).
static func invest_scale(amount: float) -> float:
	return pow(maxf(0.0, amount) / INVEST_COST, INVEST_SCALE_POWER)

static func start_state() -> Dictionary:
	return {"tax": START_TAX, "treasury": START_TREASURY, "revenue": 0.0, "prev": {}, "tax_round": 0,
		"tax_from": START_TAX, "investments": [],
		# HAZİNE KOTASI (CardManager.state_quota): dönem, dönem başı hazine, parti -> harcanan.
		"quota_round": -1, "quota_base": 0.0, "quota_spent": {}}

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
	return L.t(String(TAX_TITLES[clampi(level, TAX_LOW, TAX_HIGH)]))

static func tax_id(level: int) -> String:
	return String(TAX_IDS[clampi(level, TAX_LOW, TAX_HIGH)])

static func tax_level_of_id(id: String) -> int:
	return TAX_IDS.find(id)

## Bu kademede bir turun vergi geliri.
static func revenue(level: int) -> float:
	return float(TAX_REVENUE[clampi(level, TAX_LOW, TAX_HIGH)])

## Bir önceki turla kıyas için hazine kopyası (eğilim oku).
static func snapshot(state: Dictionary) -> Dictionary:
	return {"treasury": float(state["treasury"])}

## TUR SONU (tek sefer): vergi geliri hazineye. Yatırım dilimleri CardManager'da.
static func advance(state: Dictionary) -> void:
	state["prev"] = snapshot(state)
	var income := revenue(int(state["tax"]))
	state["revenue"] = income
	state["treasury"] = float(state["treasury"]) + income

## Bir sırada hükümete toplam vergi etkisi (ulusal puan), döngü çarpanıyla.
static func tax_turn_effect(level: int, cycle_mult: int) -> float:
	return float(TAX_TURN_NATIONAL[clampi(level, TAX_LOW, TAX_HIGH)]) * float(cycle_mult)

# --- Finansman paylaşımı ----------------------------------------------------------
## İki AYRI kaynak, aynı birim (milyon ¤): PARTİ KASASI (partinin parası) ve
## DEVLET HAZİNESİ (kamu parası, sadece hükümet yetkisiyle).
## Kaydırıcı %5'lik adımlarla durur (0/100 ve 100/0 dahil).
const FUND_STEP := 0.05

## state: devletin payı (0..1) → {"share", "state": milyon ¤, "party": milyon ¤}.
static func split_cost(total: float, state: float) -> Dictionary:
	var s := snap_share(state)
	var state_million := total * s
	var party_million := total - state_million
	return {"share": s, "state": state_million, "party": party_million}

static func snap_share(state: float) -> float:
	return clampf(snappedf(state, FUND_STEP), 0.0, 1.0)

## "1.240" gibi binlik ayraçlı tam sayı.
static func money_text(value: float) -> String:
	return L.thousands(value)

## "¤ 1.240 M" (simge başta; bkz. GameRules.money)
static func money_full(value: float) -> String:
	return GameRules.money(value)

## "%8,4"
static func percent_text(value: float) -> String:
	return L.pct(value, 1)
