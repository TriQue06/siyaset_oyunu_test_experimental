class_name Disaster
## AFET (0.0.181): rastgele bir ilde ya da birkaç komşu ilden oluşan bir
## bölgede doğal afet. Durum CardManager.disaster'da; bu dosya kurallar ve
## yardımcılar (saf, durum tutmaz).
##   - Türler ve büyüklükleri: SEL, TOPRAK KAYMASI, ÇIĞ tek il; ORMAN YANGINI
##     küçük bölge (2-3 komşu il); DEPREM geniş bölge (3-5 komşu il).
##   - Afet bir TUR sürer: tur başında çıkar, tur bitince sona erer.
##   - Sıklık: tur başına round_chance() (dönem uzunluğuna göre, ortalama ~1); bir seçim döneminde en fazla TERM_MAX.
##     Bir dönem hiç afet olmadıysa sonraki dönemde en az bir tane garanti
##     (dönemin son turuna kadar çıkmadıysa o tur kesin çıkar).
##   - YARDIM GÖTÜR hamlesi: tutarı oyuncu belirler (en az AID_MIN, AID_STEP
##     adımlarla). Hükümet partileri devlet hazinesinden (kotası kadar) ve/veya
##     parti kasasından, diğerleri sadece kasadan öder. Etki yatırımdan çok
##     güçlüdür ve HEMEN gelir: afetteki her ilde yerel puan + küçük ulusal
##     puan. Seçmen grubu yakınlığına dokunmaz. Azalan getiri: aynı partinin
##     aynı afete yaptığı toplam yardımın karekökü (tekrar yardım daha az getirir).

const KINDS := ["sel", "heyelan", "cig", "yangin", "deprem"]
const KIND_WEIGHTS := {"sel": 3, "heyelan": 2, "cig": 1, "yangin": 2, "deprem": 2}
## [en az, en çok] il.
const SIZES := {"sel": [1, 1], "heyelan": [1, 1], "cig": [1, 1], "yangin": [2, 3], "deprem": [3, 5]}

## Varsayılan 4 turluk dönemde tur başına olasılık (dönem başına ~1 afet).
const ROUND_CHANCE := 0.25
const TERM_MAX := 2

const AID_MIN := 5.0
const AID_STEP := 5.0
## İl başına yerel puan = AID_LOCAL_K × √(o ile düşen milyon ₺).
## Örnek: tek ilde 20 milyon ₺ → +6,7 (miting +5 / 15 milyon; yatırım +10 / 100 milyon, yarısı sonra).
const AID_LOCAL_K := 1.5
## Ulusal puan = AID_NATIONAL_K × √(toplam milyon ₺).
const AID_NATIONAL_K := 0.2

## Seçim aralığı uzunsa (anayasa) tur başına olasılık düşer: dönemde ~1.
## Seçimden hemen sonraki tur afetsiz (0.0.188): zar dönemin kalan turlarına
## (aralık − 1) yayılır, ortalama yine ~1.
static func round_chance() -> float:
	return clampf(1.0 / float(maxi(1, GameRules.ELECTION_INTERVAL - 1)), 0.06, 0.6)

static func title(kind: String) -> String:
	match kind:
		"sel": return L.t("Sel")
		"heyelan": return L.t("Toprak Kayması")
		"cig": return L.t("Çığ")
		"yangin": return L.t("Orman Yangını")
		"deprem": return L.t("Deprem")
	return L.t("Afet")

static func headline(kind: String, count: int) -> String:
	match kind:
		"deprem": return L.t("DEPREM: %d İLDE YIKIM!") % count
		"yangin": return L.t("ORMANLAR YANIYOR: %d İL ALEV ALTINDA!") % count
		"sel": return L.t("SEL FELAKETİ!")
		"heyelan": return L.t("TOPRAK KAYDI, YOLLAR KAPANDI!")
		"cig": return L.t("ÇIĞ DÜŞTÜ, KÖYLER MAHSUR!")
	return L.t("AFET!")

## Gazetedeki resim (tools/make_disaster_art.py üretir).
static func art(kind: String) -> Texture2D:
	var path := "res://assets/disasters/%s.png" % kind
	return load(path) if ResourceLoader.exists(path) else null

static func color(kind: String) -> Color:
	match kind:
		"sel": return Color("3BA3FF")
		"heyelan": return Color("B07A3C")
		"cig": return Color("D8F0FF")
		"yangin": return Color("FF7A1F")
	return Color("FF3B30")

static func pick_kind(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in KINDS:
		total += int(KIND_WEIGHTS[k])
	var roll := rng.randi_range(1, total)
	for k in KINDS:
		roll -= int(KIND_WEIGHTS[k])
		if roll <= 0:
			return k
	return KINDS[0]

## Rastgele merkez ilden komşulara yayılan bölge (komşuluk GameMap'ten).
static func pick_region(kind: String, rng: RandomNumberGenerator, province_ids: Array) -> Array:
	if province_ids.is_empty():
		return []
	var size: Array = SIZES.get(kind, [1, 1])
	var want := rng.randi_range(int(size[0]), int(size[1]))
	var center := String(province_ids[rng.randi_range(0, province_ids.size() - 1)])
	var region: Array = [center]
	var neighbors: Dictionary = GameMap.neighbors()
	var frontier: Array = [center]
	while region.size() < want and not frontier.is_empty():
		var from := String(frontier.pop_front())
		var options: Array = (neighbors.get(from, []) as Array).duplicate()
		# Aynı tohumla her yerde aynı bölge çıksın: sıralı + rng ile karıştır.
		options.sort()
		for i in range(options.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = options[i]
			options[i] = options[j]
			options[j] = tmp
		for n in options:
			if region.size() >= want:
				break
			if province_ids.has(n) and not region.has(n):
				region.append(String(n))
				frontier.append(String(n))
	return region

## Toplam yardım prev → now olunca il başına yerel puan artışı.
static func local_gain(prev_total: float, new_total: float, province_count: int) -> float:
	var n := float(maxi(1, province_count))
	return AID_LOCAL_K * (sqrt(maxf(0.0, new_total) / n) - sqrt(maxf(0.0, prev_total) / n))

static func national_gain(prev_total: float, new_total: float) -> float:
	return AID_NATIONAL_K * (sqrt(maxf(0.0, new_total)) - sqrt(maxf(0.0, prev_total)))

static func snap_amount(value: float) -> float:
	return maxf(0.0, floorf(value / AID_STEP + 0.0001) * AID_STEP)
