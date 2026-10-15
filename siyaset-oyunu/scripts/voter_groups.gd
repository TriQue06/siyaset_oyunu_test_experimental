class_name VoterGroups
extends RefCounted
## SEÇMEN GRUPLARI — oyunun siyasi modelinin TEK tanım kaynağı (ad, renk,
## simge, talepler, karşıt grup, yasa adı, tepki oranları hep burada).
##
## İKİ AYRI VERİ KATMANI (asla karıştırılmaz):
##   1. İL PROFİLİ (demografi): her ilde 4 İKİLİ dağılım. Bir çiftin iki
##      tarafı toplam %100'dür (işçi %65 → işveren %35); sekiz grubun toplamı
##      %100 DEĞİLDİR, çünkü aynı seçmen dört çiftte de bir tarafa düşer.
##      Profil oyun başında üretilir ve OYUN BOYUNCA DEĞİŞMEZ: miting, yatırım,
##      yasa ilin nüfusunu değil partilerin desteğini etkiler.
##      Saklama: {çift_id: ilk grubun yüzdesi (TAM SAYI 0..100)} — ikinci grup
##      her zaman 100 − ilk; kayan nokta hatası oluşamaz.
##   2. PARTİ YAKINLIĞI: her partinin 8 grubun her birindeki ULUSAL desteği
##      (0..100, 50 nötr). PartyManager.parties[peer]["groups"] içinde durur.
##      Yasa ve miting kalıcı olarak bunu değiştirir; grup toplantısı ise
##      üstüne GEÇİCİ bir bonus ekler (bkz. CardManager.group_meetings).
##
## OY HESABI (ElectionModel.support):
##   çift puanı  = pay_A × yakınlık_A + pay_B × yakınlık_B        (0..100)
##   il uyumu    = 4 çift puanının ORTALAMASI                      (0..100)
##   oy ağırlığı = exp(SHARPNESS × (uyum − 50))
## Dört çift aynı seçmen kitlesinin dört farklı yüzüdür: ortalaması alınır,
## seçmen dört kez sayılmaz. Ağırlıklar partiler arasında normalize edilir
## (ElectionModel), kamuoyu çarpanı (ulusal + il aktivitesi) ayrıca uygulanır.

## Gruplar (sıra arayüzde de bu sıra: çiftler yan yana).
const GROUP_IDS := ["isci", "isveren", "genc", "emekli", "dindar", "ilerici", "ozerkci", "milliyetci"]

## Dört ikili çift: [ilk grup, ikinci grup]. Çift adları sadece geliştirici
## içindir; oyuncu her yerde grupların kendisini görür.
const PAIRS := {
	"emek": ["isci", "isveren"],
	"kusak": ["genc", "emekli"],
	"inanc": ["dindar", "ilerici"],
	"yonetim": ["ozerkci", "milliyetci"],
}
const PAIR_IDS := ["emek", "kusak", "inanc", "yonetim"]

## icon: VoterGroupIcon'un çizdiği simge adı.
## law_backlash: grup yasası kabul edilince karşıt gruptaki kaybın kazanca oranı.
## (0.0.182: ideolojik keskinlik için ikisi de ×1,2.)
## miting_backlash: mitingle bu gruba yaklaşınca karşıt gruptaki kayıp oranı.
const GROUPS := {
	"isci": {
		"title": "İşçiler ve Sendikalar", "color": Color("#E85D75"), "icon": "hardhat",
		"opposite": "isveren", "pair": "emek",
		"blurb": "Ücretli çalışanlar, fabrika ve sendika tabanı.",
		"issues": ["ücretler", "iş güvencesi", "sendikal haklar"],
		"law_title": "Asgari Ücret ve Sendika Hakları Yasası",
		"law_problem": "Düşük ücretler ve güvencesiz çalışma",
		"meeting": "Ücretler, iş güvencesi ve sendikal haklar",
		"law_backlash": 0.54, "miting_backlash": 0.42,
	},
	"isveren": {
		"title": "İşverenler ve İşletmeler", "color": Color("#3D8BDB"), "icon": "briefcase",
		"opposite": "isci", "pair": "emek",
		"blurb": "Esnaf, sanayici ve şirket sahipleri.",
		"issues": ["yatırım ortamı", "vergi yükü", "bürokrasi"],
		"law_title": "Vergi İndirimi ve Yatırım Teşvik Yasası",
		"law_problem": "Ağır vergi yükü ve yatırım önündeki engeller",
		"meeting": "Yatırım ortamı, vergi yükü ve işletmelerin sorunları",
		"law_backlash": 0.54, "miting_backlash": 0.42,
	},
	"genc": {
		"title": "Gençler ve Öğrenciler", "color": Color("#F2B632"), "icon": "gradcap",
		"opposite": "emekli", "pair": "kusak",
		"blurb": "Öğrenciler ve iş hayatına yeni atılanlar.",
		"issues": ["eğitim", "barınma", "istihdam"],
		"law_title": "Burs, Yurt ve Genç İstihdamı Yasası",
		"law_problem": "Pahalı eğitim, barınma sorunu ve genç işsizliği",
		"meeting": "Eğitim, barınma ve genç istihdamı",
		"law_backlash": 0.36, "miting_backlash": 0.3,
	},
	"emekli": {
		"title": "Emekliler", "color": Color("#8B70D6"), "icon": "heart",
		"opposite": "genc", "pair": "kusak",
		"blurb": "Çalışma hayatını tamamlamış yaşlı seçmenler.",
		"issues": ["emekli aylıkları", "sağlık", "yaşam maliyeti"],
		"law_title": "Emekli Aylığı ve Sağlık Güvencesi Yasası",
		"law_problem": "Düşük aylıklar ve yükselen sağlık giderleri",
		"meeting": "Emekli aylıkları, sağlık ve yaşam maliyeti",
		"law_backlash": 0.36, "miting_backlash": 0.3,
	},
	"dindar": {
		"title": "Dindar Topluluklar", "color": Color("#2EAA79"), "icon": "dome",
		"opposite": "ilerici", "pair": "inanc",
		"blurb": "İnancını gündelik hayatının merkezine koyan topluluklar.",
		"issues": ["inanç özgürlüğü", "din eğitimi", "aile değerleri"],
		"law_title": "İnanç Özgürlüğü ve Din Eğitimi Yasası",
		"law_problem": "İnanç pratiklerine yönelik kısıtlamalar",
		"meeting": "İnanç özgürlüğü ve din eğitimi",
		"law_backlash": 0.6, "miting_backlash": 0.48,
	},
	"ilerici": {
		"title": "LGBT ve Ateist İlericiler", "color": Color("#E65AB7"), "icon": "rainbow",
		"opposite": "dindar", "pair": "inanc",
		"blurb": "Laik, ilerici ve LGBT topluluklar.",
		"issues": ["ayrımcılık", "eşit yurttaşlık", "bireysel özgürlükler"],
		"law_title": "Ayrımcılık Karşıtı Eşit Yurttaşlık Yasası",
		"law_problem": "Ayrımcılık ve eşit olmayan yurttaşlık",
		"meeting": "Ayrımcılık, eşit yurttaşlık ve bireysel özgürlükler",
		"law_backlash": 0.6, "miting_backlash": 0.48,
	},
	"ozerkci": {
		"title": "Özerkçiler", "color": Color("#16A6A1"), "icon": "pin",
		"opposite": "milliyetci", "pair": "yonetim",
		"blurb": "Kararların yerelde alınmasını isteyen bölgesel seçmen.",
		"issues": ["yerel yetkiler", "bölgesel temsil", "yerinden yönetim"],
		"law_title": "Yerel Yönetimler ve Bölgesel Temsil Yasası",
		"law_problem": "Merkezde toplanan yetkiler ve zayıf yerel temsil",
		"meeting": "Yerel yetkiler ve bölgesel temsil",
		"law_backlash": 0.48, "miting_backlash": 0.36,
	},
	"milliyetci": {
		"title": "Milliyetçiler", "color": Color("#E87532"), "icon": "flag",
		"opposite": "ozerkci", "pair": "yonetim",
		"blurb": "Ulusal birliği ve güçlü devleti önceleyen seçmen.",
		"issues": ["ulusal egemenlik", "güvenlik", "ulusal birlik"],
		"law_title": "Ulusal Güvenlik ve Birlik Yasası",
		"law_problem": "Güvenlik kaygıları ve bölünme korkusu",
		"meeting": "Ulusal egemenlik ve güvenlik",
		"law_backlash": 0.48, "miting_backlash": 0.36,
	},
}

# --- Oy hesabı ---------------------------------------------------------------------
## İl uyumundaki 1 puanlık farkın oy ağırlığına etkisi (exp). 0,14: uyumu
## 5 puan yüksek parti, aynı ilde yaklaşık 2 kat ağırlık alır.
const SHARPNESS := 0.14

# --- Parti yakınlığı -----------------------------------------------------------------
## HİTAP (0.0.213): bir partinin bir gruptaki değeri o grubun YÜZDE KAÇINA
## hitap ettiğidir (0..100). Bütün partilerin toplamı en çok 100: %100 hitap
## eden parti o grubun bütün oyunu alır, diğerleri o gruptan 0 oy alır. Kimsenin
## hitap etmediği pay (100 − toplam) partiler arasında EŞİT dağılır (kamuoyu
## çarpanı hariç). Bir parti kazandıkça bu payı diğerlerinden ve kararsızlardan
## orantılı alır (bkz. PartyManager.apply_group_deltas: seçmen çalma).
const AFFINITY_MIN := 0.0
const AFFINITY_MAX := 100.0
## Varsayılan hitap: hiç.
const AFFINITY_NEUTRAL := 0.0
## Parti kurulurken 2 ÇEKİRDEK grup seçilir (aynı çiftten olamaz): bu gruplarda
## CORE_START hitapla başlar ve kalıcı kazançları CORE_GAIN_MULT katıdır.
const CORE_COUNT := 2
const CORE_START := 10.0
const CORE_GAIN_MULT := 2.0

## Parti yakınlık profilleri arasındaki mesafe ölçeği (bkz. party_distance):
## ölçek, eski 3 eksenli modeldeki mesafe eşiklerine denk düşecek şekilde.
const DISTANCE_SCALE := 11.3
## Yakınlık 0..1 için en büyük mesafe.
const MAX_DISTANCE := 10.4

# --- İl profili üretimi ----------------------------------------------------------------
const SMOOTHING_PASSES := 1
const SELF_WEIGHT := 0.4
## Her çiftin ülke ortalaması 50 ± bu kadar (her oyunda farklı).
const PAIR_CENTER_JITTER := 8.0
## Ortalamadan en uç sapma (yüzde puanı). 0.0.214: ortalama il ~%70/%30.
const PROFILE_SPREAD := 48.0
## Bir çiftin bir tarafı bundan az / çok olamaz.
const PROFILE_MIN := 6
const PROFILE_MAX := 94
## Her çiftte birkaç BÖLGESEL ODAK: grubun belirgin yoğunlaştığı kümeler.
const HOTSPOTS_MIN := 1
const HOTSPOTS_MAX := 2
const HOTSPOT_STRENGTH := 2.6
## Büyük seçim çevreleri daha karma (ülke ortalamasına yakın) olur.
const HOMOGENEOUS_SEATS_FROM := 6
const HOMOGENEOUS_SEATS_TO := 20
const HOMOGENEOUS_MIN_FACTOR := 0.6

static func is_group(group: String) -> bool:
	return GROUPS.has(group)

static func data(group: String) -> Dictionary:
	return L.tr_dict(GROUPS.get(group, {}))

static func title(group: String) -> String:
	return L.t(String(GROUPS.get(group, {}).get("title", group)))

static func color(group: String) -> Color:
	return GROUPS.get(group, {}).get("color", Color.GRAY)

static func icon(group: String) -> String:
	return String(GROUPS.get(group, {}).get("icon", ""))

static func opposite(group: String) -> String:
	return String(GROUPS.get(group, {}).get("opposite", ""))

static func pair_of(group: String) -> String:
	return String(GROUPS.get(group, {}).get("pair", ""))

static func issues_text(group: String) -> String:
	return ", ".join(PackedStringArray(data(group).get("issues", [])))

# --- İl profili --------------------------------------------------------------------------

## Grubun ildeki payı (0..1). profile: {çift_id: ilk grubun yüzdesi}.
static func share(profile: Dictionary, group: String) -> float:
	return float(percent(profile, group)) / 100.0

## Grubun ildeki yüzdesi (tam sayı). Profil yoksa 50.
static func percent(profile: Dictionary, group: String) -> int:
	var pair := pair_of(group)
	if pair == "":
		return 0
	var first := clampi(int(profile.get(pair, 50)), 0, 100)
	return first if PAIRS[pair][0] == group else 100 - first

## Grubun yüzdesini ayarlar; karşıt grup otomatik tamamlanır (toplam hep 100).
static func set_percent(profile: Dictionary, group: String, value: int) -> void:
	var pair := pair_of(group)
	if pair == "":
		return
	value = clampi(value, 0, 100)
	profile[pair] = value if PAIRS[pair][0] == group else 100 - value

## Profil geçerli mi? (4 çift, her biri 0..100 tam sayı.)
static func is_valid_profile(profile: Dictionary) -> bool:
	for pair in PAIR_IDS:
		if not profile.has(pair):
			return false
		var v = profile[pair]
		if not (v is int or v is float) or float(v) != floorf(float(v)) or int(v) < 0 or int(v) > 100:
			return false
	return true

## Bir ilde en kalabalık (çiftindeki payı en yüksek) grup.
static func dominant_group(profile: Dictionary) -> String:
	var best := ""
	var best_pct := -1
	for group in GROUP_IDS:
		var pct := percent(profile, group)
		if pct > best_pct:
			best_pct = pct
			best = group
	return best

## province_id -> Array[province_id] (altıgen haritadan).
static func neighbors() -> Dictionary:
	var map = Engine.get_main_loop().root.get_node_or_null("GameMap") if Engine.get_main_loop() is SceneTree else null
	return map.neighbors() if map != null else {}

## SENTETİK il profilleri (gerçek istatistik DEĞİL; oyun dengesi için):
##   1. Her çiftte her ile rastgele bir değer, birkaç bölgesel odakta güçlü itki.
##   2. Komşuluk grafiği üzerinde yumuşatma: yakın iller benzer (aynı değil).
##   3. Çiftin bu oyunluk ülke ortalaması etrafına yayılır; büyük seçim
##      çevreleri biraz daha karma kalır.
## seats: province_id -> vekil sayısı (verilmezse karmalık uygulanmaz).
static func generate_profiles(rng: RandomNumberGenerator, province_ids: Array, seats: Dictionary = {}, populations: Dictionary = {}) -> Dictionary:
	var ids: Array = province_ids.duplicate()
	ids.sort()  # aynı tohum her makinede aynı ülkeyi versin
	var result: Dictionary = {}
	for province_id in ids:
		result[province_id] = {}
	if ids.is_empty():
		return result
	var nb := neighbors()
	for pair in PAIR_IDS:
		var center := 50.0 + rng.randf_range(-PAIR_CENTER_JITTER, PAIR_CENTER_JITTER)
		var values: Dictionary = {}
		for province_id in ids:
			values[province_id] = rng.randf_range(-1.0, 1.0)
		for i in rng.randi_range(HOTSPOTS_MIN, HOTSPOTS_MAX):
			var spot = ids[rng.randi() % ids.size()]
			values[spot] = float(values[spot]) + HOTSPOT_STRENGTH * (1.0 if rng.randf() < 0.5 else -1.0)
		for pass_index in SMOOTHING_PASSES:
			var next: Dictionary = {}
			for province_id in ids:
				var around: Array = []
				for other in nb.get(province_id, []):
					if values.has(other):
						around.append(other)
				var own := float(values[province_id])
				if around.is_empty():
					next[province_id] = own
					continue
				var sum := 0.0
				for other in around:
					sum += float(values[other])
				next[province_id] = SELF_WEIGHT * own + (1.0 - SELF_WEIGHT) * sum / around.size()
			values = next
		var mean := 0.0
		for province_id in ids:
			mean += float(values[province_id])
		mean /= ids.size()
		var max_abs := 0.0001
		for province_id in ids:
			max_abs = maxf(max_abs, absf(float(values[province_id]) - mean))
		for province_id in ids:
			var v := (float(values[province_id]) - mean) / max_abs
			v = signf(v) * pow(absf(v), 0.55)
			var n := int(seats.get(province_id, 0))
			if populations.has(province_id):
				n = int(float(populations[province_id]) / 100000.0)
			if n > 0:
				var t := clampf(float(n - HOMOGENEOUS_SEATS_FROM) / float(HOMOGENEOUS_SEATS_TO - HOMOGENEOUS_SEATS_FROM), 0.0, 1.0)
				v *= lerpf(1.0, HOMOGENEOUS_MIN_FACTOR, t)
			result[province_id][pair] = clampi(int(round(center + PROFILE_SPREAD * v)), PROFILE_MIN, PROFILE_MAX)
	for province_id in ids:
		var electorate := int(populations.get(province_id, maxi(1, int(seats.get(province_id, 1))) * 100000))
		var counts := {}
		for pair in PAIR_IDS:
			var groups: Array = PAIRS[pair]
			var first := int(round(float(electorate) * float(result[province_id][pair]) / 100.0))
			counts[groups[0]] = first
			counts[groups[1]] = electorate - first
		result[province_id]["_electorate"] = electorate
		result[province_id]["_counts"] = counts
	return result

## Bir ildeki grubun seçmen sayısı (sayılar yoksa pay × il nüfusu).
static func group_count(profile: Dictionary, group: String) -> float:
	var counts: Dictionary = profile.get("_counts", {})
	if counts.has(group):
		return float(counts[group])
	return share(profile, group) * float(profile.get("_electorate", 100000))

## Ülke genelinde her grubun seçmen sayısı (il nüfuslarının toplamı).
static func national_counts(profiles: Dictionary) -> Dictionary:
	var result := {}
	for group in GROUP_IDS:
		result[group] = 0.0
	for province_id in profiles.keys():
		for group in GROUP_IDS:
			result[group] = float(result[group]) + group_count(profiles[province_id], group)
	return result

## Ülke geneli (vekil ağırlıklı) grup payı 0..1.
static func national_share(profiles: Dictionary, seats: Dictionary, group: String) -> float:
	var total := 0.0
	var sum := 0.0
	for province_id in profiles.keys():
		var n := float(profiles[province_id].get("_electorate", seats.get(province_id, 1)))
		if n <= 0.0:
			continue
		sum += share(profiles[province_id], group) * n
		total += n
	return sum / total if total > 0.0 else 0.5

# --- Parti yakınlığı ----------------------------------------------------------------------

static func neutral_affinities() -> Dictionary:
	var result := {}
	for group in GROUP_IDS:
		result[group] = AFFINITY_NEUTRAL
	return result

## Kuruluş: her grupta %0, çekirdek gruplarda CORE_START.
static func start_affinities(core: Array) -> Dictionary:
	var result := neutral_affinities()
	for group in core:
		if is_group(String(group)):
			result[group] = CORE_START
	return result

## Çekirdek seçimi geçerli mi? (CORE_COUNT farklı grup, ikisi aynı çiftten değil.)
static func is_valid_core(core: Array) -> bool:
	if core.size() != CORE_COUNT:
		return false
	var pairs := {}
	for group in core:
		if not is_group(String(group)):
			return false
		var pair := pair_of(String(group))
		if pairs.has(pair):
			return false
		pairs[pair] = true
	return true

## Botlar ve rastgele partiler için: farklı çiftlerden 2 çekirdek grup.
static func random_core(rng: RandomNumberGenerator = null) -> Array:
	var pairs: Array = PAIR_IDS.duplicate()
	var core: Array = []
	while core.size() < CORE_COUNT and not pairs.is_empty():
		var i := (rng.randi() if rng != null else randi()) % pairs.size()
		var pair: String = pairs[i]
		pairs.remove_at(i)
		var side := (rng.randi() if rng != null else randi()) % 2
		core.append(PAIRS[pair][side])
	return core

## Yakınlıkların en yüksek iki grubu (parti kartında "en güçlü" özeti için).
static func ranked_groups(affinities: Dictionary) -> Array:
	var ranked: Array = GROUP_IDS.duplicate()
	ranked.sort_custom(func(a, b): return float(affinities.get(a, AFFINITY_NEUTRAL)) > float(affinities.get(b, AFFINITY_NEUTRAL)))
	return ranked

## Kalıcı bir değişikliğin GERÇEKLEŞEN miktarı. Kazanç: çekirdek grupta
## CORE_GAIN_MULT katı, azalan getiriyle: kalan pay × (1 − e^(−kazanç/100)).
## Üstel biçim: aynı toplam kazanç bir kerede ya da parça parça verilse de
## sonuç birebir aynıdır (100 yerine 50 + 50). Kayıp: en çok mevcut hitap kadar.
static func effective_delta(affinities: Dictionary, group: String, amount: float, core: Array = []) -> float:
	var current := float(affinities.get(group, AFFINITY_NEUTRAL))
	if amount > 0.0:
		var mult := CORE_GAIN_MULT if core.has(group) else 1.0
		return maxf(0.0, AFFINITY_MAX - current) * (1.0 - exp(-amount * mult / AFFINITY_MAX))
	if amount < 0.0:
		return maxf(amount, AFFINITY_MIN - current)
	return 0.0

## affinities'i yerinde günceller; gerçekleşen değişimi döner.
static func apply_delta(affinities: Dictionary, group: String, amount: float, core: Array = []) -> float:
	if not is_group(group):
		return 0.0
	var delta := effective_delta(affinities, group, amount, core)
	affinities[group] = clampf(float(affinities.get(group, AFFINITY_NEUTRAL)) + delta, AFFINITY_MIN, AFFINITY_MAX)
	return delta

## Geçici bonuslar eklenmiş, 0..100'e sıkıştırılmış yakınlıklar.
static func with_bonus(affinities: Dictionary, bonus: Dictionary) -> Dictionary:
	if bonus.is_empty():
		return affinities
	var result := affinities.duplicate()
	for group in bonus.keys():
		result[group] = clampf(float(result.get(group, AFFINITY_NEUTRAL)) + float(bonus[group]), AFFINITY_MIN, AFFINITY_MAX)
	return result

## İL UYUMU (0..100): partinin yakınlıklarının ilin 4 çift dağılımıyla
## ağırlıklı ortalaması. 50 = ilde ne avantajlı ne dezavantajlı.
static func appeal(affinities: Dictionary, profile: Dictionary) -> float:
	var sum := 0.0
	for pair in PAIR_IDS:
		var groups: Array = PAIRS[pair]
		var s := share(profile, groups[0])
		sum += s * float(affinities.get(groups[0], AFFINITY_NEUTRAL)) \
			+ (1.0 - s) * float(affinities.get(groups[1], AFFINITY_NEUTRAL))
	return sum / PAIR_IDS.size()

## İl uyumunun oy ağırlığı (> 0). Uyum 50 → 1.
static func vote_weight(appeal_value: float) -> float:
	return exp(SHARPNESS * (appeal_value - AFFINITY_NEUTRAL))

## İki partinin yakınlık profilleri arasındaki mesafe (eski eşiklerle aynı ölçek).
static func party_distance(a: Dictionary, b: Dictionary) -> float:
	var sum_sq := 0.0
	for group in GROUP_IDS:
		var diff := float(a.get(group, AFFINITY_NEUTRAL)) - float(b.get(group, AFFINITY_NEUTRAL))
		sum_sq += diff * diff
	return sqrt(sum_sq) / DISTANCE_SCALE

## 1: aynı profil, 0: çok farklı.
static func party_closeness(a: Dictionary, b: Dictionary) -> float:
	return clampf(1.0 - party_distance(a, b) / MAX_DISTANCE, 0.0, 1.0)

## "%62" gibi gösterim.
static func percent_text(value: float) -> String:
	return L.pct(value, 0)
