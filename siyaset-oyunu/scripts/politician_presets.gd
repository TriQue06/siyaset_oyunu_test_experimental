class_name PoliticianPresets
extends RefCounted
## SİYASETÇİ PROFİLİ: oyun bir siyasetçinin parti kurmasıyla başlar. Parti
## kurulmadan önce her oyuncu siyasetçisini seçer (bkz. politician_setup.gd):
##   - MESLEK (0.0.229): 7 meslek; seçmen grubuna BAĞLI DEĞİL (çekirdek gruplar
##     parti kurulumunda seçilir). Her meslek EFFECTS çarpanları ve bazılarında
##     özel başlangıç (iş insanı parası, belediye başkanı teşkilatları) verir.
##     Kayıtta alan adı geriye uyum için "background".
##   - KİŞİLİK (0.0.229): TRAITS'ten biri; küçük çarpanlar. Yoksa rastgele.
##   - MEMLEKET: haritadan seçilen il. Oyuna orada 2. seviye teşkilatla
##     başlanır ve memlekette kalıcı "hemşehri" desteği vardır (il aktivitesi;
##     ilin seçmen profili değişmez). Komşu iller ETKİLENMEZ.
## ETKİ ANAHTARLARI (çarpan, yoksa 1):
##   HAMLEYİ YAPAN siyasetçiye bakar (effect): miting, speech (grup toplantısı),
##     law (grup yasası), propaganda_out (attığın karalama), reputation_out (attığın kaset).
##   PARTİYE bakar (party_effect, partinin herhangi bir üyesi): propaganda_in
##     (sana atılan karalama), turmoil_in (iç karışıklık), steal_in (senden
##     çalınan vekil), org (teşkilat gücü), tax_mood (vergiye seçmen tepkisi).
##   appeal: o gruplarda kazanç (yasa, toplantı, miting) APPEAL_MULT kat.
## ARAYÜZ METİNLERİ SAYI İÇERMEZ (özet anlatım); sayılar sadece burada.
## Veri PartyManager.politicians[peer] içinde durur (partiden bağımsız) =
##   {"gender", "first_name", "surname", "name" (ad + soyad), "background", "trait", "hometown"}
## İSİM TAMAMEN RASTGELE (elle yazılmaz): random_name(). SOYAD ileride çok
## yerde kullanılacak (bkz. surname_of). Soyadlar uydurma kök + ekten üretilir;
## gerçek siyasetçi soyadları BANNED_SURNAMES ile ayrıca engellenir.
## (bkz. PartyManager.set_my_politician).

## Meslek -> {title, blurb, perk, effects, appeal}. Sıra ekranda da bu sıra.
const BACKGROUNDS := {
	"sendikaci": {"title": "Sendikacı",
		"blurb": "Fabrika kapılarında büyüdün, grevleri sen örgütledin.",
		"perk": "Mitinglerin daha etkili; işçiler sana daha kolay ısınır.",
		"effects": {"miting": 1.25}, "appeal": ["isci"]},
	"is_insani": {"title": "İş İnsanı",
		"blurb": "Kendi şirketini kurdun, sermaye çevreleri seni tanır.",
		"perk": "Oyuna daha fazla parayla başlarsın, her tur ek gelirin olur.",
		"effects": {}, "appeal": []},
	"belediye_baskani": {"title": "Belediye Başkanı",
		"blurb": "Şehrini yıllarca yönettin, yerel ağları iyi bilirsin.",
		"perk": "Birkaç ilde hazır teşkilatla başlarsın; teşkilatların daha güçlü.",
		"effects": {"org": 1.1}, "appeal": []},
	"emekli_subay": {"title": "Emekli Subay",
		"blurb": "Disiplin ve birlik senin için her şeyden önce gelir.",
		"perk": "Partinde iç karışıklık ve sana atılan karalamalar daha az işler.",
		"effects": {"turmoil_in": 0.75, "propaganda_in": 0.75}, "appeal": []},
	"gazeteci": {"title": "Gazeteci",
		"blurb": "Yıllarca manşet attın; kimin dosyası nerede bilirsin.",
		"perk": "Rakiplere attığın kaset ve karalamalar daha sert vurur.",
		"effects": {"reputation_out": 1.25, "propaganda_out": 1.25}, "appeal": []},
	"hukukcu": {"title": "Hukukçu",
		"blurb": "Davaları kazandın, sözleşmelerin her satırını okursun.",
		"perk": "Partinden vekil koparmak daha zordur.",
		"effects": {"steal_in": 0.75}, "appeal": []},
	"aktivist": {"title": "Aktivist",
		"blurb": "Sokaktan geldin; eylemleri sen başlattın.",
		"perk": "Mitinglerin daha etkili, gençler ve ilericiler sana ısınır; yasa ve grup toplantıların daha zayıf.",
		"effects": {"miting": 1.25, "law": 0.75, "speech": 0.75}, "appeal": ["genc", "ilerici"]},
}
const BACKGROUND_ORDER := ["sendikaci", "is_insani", "belediye_baskani", "emekli_subay",
	"gazeteci", "hukukcu", "aktivist"]

## Kişilik -> {title, blurb, perk, effects}. Sıra ekranda da bu sıra.
const TRAITS := {
	"hatip": {"title": "Hatip",
		"blurb": "Kürsüye çıktın mı salon susar.",
		"perk": "Mitinglerin biraz, grup toplantıların belirgin biçimde daha etkili.",
		"effects": {"miting": 1.1, "speech": 1.2}},
	"sert": {"title": "Sert",
		"blurb": "Lafını esirgemezsin, kavgadan kaçmazsın.",
		"perk": "Karalamaların daha sert, mitinglerin biraz daha etkili; ama sana atılan karalamalar da biraz daha işler.",
		"effects": {"miting": 1.05, "propaganda_out": 1.2, "propaganda_in": 1.05}},
	"teknokrat": {"title": "Teknokrat",
		"blurb": "Rakamlarla konuşursun, piyasa sana güvenir.",
		"perk": "Hükümetteyken vergilere seçmen tepkisi daha az olur.",
		"effects": {"tax_mood": 0.8}},
}
const TRAIT_ORDER := ["hatip", "sert", "teknokrat"]

## Mesleğin hitap ettiği gruplarda kazanç çarpanı.
const APPEAL_MULT := 1.1

# --- Meslek özel başlangıçları ------------------------------------------------
## İş insanı: ilk tur gelirinin (FUNDS_PER_ROUND) yarısı kadar ek başlangıç
## parası + her tur ek gelir (milyon ¤).
const BUSINESS_START_FUNDS := 15.0
const BUSINESS_TURN_INCOME := 2.5
## Belediye başkanı: il sayısının bu oranı kadar rastgele ilde (en az 1) teşkilat.
const MAYOR_ORG_SHARE := 0.1
const MAYOR_ORG_LEVEL := 1

# --- Memleket -----------------------------------------------------------------
## Oyun başında memlekette bedava kurulan teşkilat seviyesi.
const HOMETOWN_ORG_LEVEL := 2
## Kalıcı hemşehri desteği (aktivite puanı, sönmez): sadece memleket.
const HOMETOWN_ACTIVITY := 4.0

# --- Rastgele isim ----------------------------------------------------------------
## CİNSİYET oyuncu tarafından seçilir ("m" erkek / "f" kadın); ad o cinsiyetin
## listesinden + iki cinsiyette de kullanılan UNISEX_NAMES'ten gelir. Botların
## cinsiyeti %75 erkek, %25 kadın (MALE_NAME_CHANCE).
const MALE_NAME_CHANCE := 0.75
const GENDERS := ["m", "f"]
const MALE_NAMES := [
	"Özgür", "Ümit",
	"Ahmet", "Aras", "Barlas", "Berk", "Cihan", "Doruk", "Emre", "Ferit", "Gökay", "Hakan", "Kaan",
	"Kerem", "Levent", "Mert", "Nevzat", "Oktay", "Orhun", "Serdar", "Tamer", "Tuncay", "Ufuk",
	"Vedat", "Yekta", "Zafer", "Arda", "Erkin", "Onur", "Alper", "Atilla", "Bora", "Burak", "Cem",
	"Cengiz", "Coşkun", "Erhan", "Erol", "Ersin", "Eren", "Fikret", "Halil", "Haluk", "Hasan",
	"Hüseyin", "İbrahim", "İsmail", "Kemal", "Koray", "Kudret", "Metin", "Murat", "Mustafa", "Necati",
	"Nihat", "Oğuz", "Orhan", "Osman", "Özcan", "Rıza", "Sadık", "Salih", "Selim", "Sinan", "Suat",
	"Şükrü", "Tarık", "Tayfun", "Turgut", "Volkan", "Yavuz", "Yusuf", "Zeki", "Bülent", "Cahit",
	"Ergün", "Faruk", "Gürkan", "Hikmet", "İlhan", "Kenan", "Mahir", "Necip", "Nurettin", "Rahmi",
	"Recai", "Sabri", "Şahin", "Recep", "Devlet", "Alparslan", "Müsavat", "Fatih", "Mesut",
	"Necmettin", "Abdullah", "Süleyman", "Celal", "Adnan", "Hüsamettin", "Ekrem", "Mansur",
	"Selahattin", "Ali", "Gültekin", "Tunç", "Cemil", "Mehmet", "Tolga", "Cemal", "İsmet", "Fahri",
	"Cevdet", "Necdet",
]
const FEMALE_NAMES := [
	"Ayla", "Bahar", "Belgin", "Cansu", "Cemre", "Defne", "Ece", "Eylül", "Figen", "Gaye", "Gülay",
	"Hülya", "Ilgın", "İpek", "Lale", "Melis", "Nazlı", "Nilgün", "Özge", "Pelin", "Rüya", "Selin",
	"Sevgi", "Sinem", "Şebnem", "Tuba", "Ülkü", "Yasemin", "Zeynep", "Burcu", "Ceyda", "Gizem",
	"Aslı", "Derya", "Elif", "Esra", "Filiz", "Gönül", "Handan", "Leyla", "Meltem", "Nermin",
	"Nesrin", "Oya", "Serpil", "Sevim", "Songül", "Şule", "Türkan", "Zerrin", "Tansu", "Meral",
]
const UNISEX_NAMES := [
	"Deniz", "İlkay",
]
## Soyad = kök + ek ("Gök" + "yelken" = "Gökyelken"). Yaygın siyasetçi
## soyadı kalıpları (-oğlu, -doğan, -demir, -kaya, -han) bilerek yok; -soy,
## -ay, -ok, -yol, -gül, -yıldız, -bulut var ama bunlardan çıkan bilinen
## siyasetçi soyadları (Aksoy, Günay, Altınok, Akyol, Akbulut...) yasaklı.
const SURNAME_ROOTS := ["Ak", "Kara", "Gök", "Yel", "Dağ", "Çam", "Ay", "Gün", "Tan", "Bal",
	"Kır", "Ulu", "Boz", "Sarı", "Alp", "Çağ", "Al", "Ilık", "Sis", "Ilgaz",
	"Yaz", "Kış", "Göl", "Su", "Kum", "Yıldız", "Bulut", "Çiy", "Tuz", "Ilgın",
	"Kızıl", "Mavi", "Yeşil", "Ala", "Gümüş", "Altın", "Bakır", "Pamuk", "İpek", "Kuş",
	"Turna", "Ceylan", "Şahin", "Kartal", "Atmaca", "Güz", "Bahar", "Sabah", "Akşam", "Kervan",
	"Deniz", "Orman", "Bayır", "Eğin", "Erik", "Elma", "Ceviz", "Sedir", "Kekik", "Nar"]
const SURNAME_ENDS := ["söğüt", "yelken", "pınar", "yamaç", "çınar", "ırmak", "doruk", "koru",
	"yaprak", "kumsal", "dere", "yayla", "gölge", "rüzgâr", "fidan", "kuşak", "sırt",
	"meşe", "ılgın", "serçe", "kıyı", "çiçek", "ova",
	"bağ", "bahçe", "çayır", "çeşme", "köprü", "geçit", "vadi", "boyu", "yaka", "kanat",
	"dal", "kök", "tohum", "başak", "lale", "sümbül", "kavak", "ardıç", "selvi",
	"çam", "kozan", "tarla", "harman", "değirmen", "kuyu", "kaynak", "göl", "ada", "liman",
	"kapı", "evli", "yurdu", "türkü", "ezgi", "ışın", "şafak",
	"tepe", "yazı", "örs", "kalem", "dokuma", "keman", "yüce", "yay",
	"sazlı", "kamış", "çalı", "fındık", "kiraz", "kayın", "palamut", "yonca", "kestane", "defne",
	"soy", "ay", "ok", "yol", "gül", "yıldız", "bulut"]
## TEK PARÇA soyadlar: soyad her zaman kök + ek olmak zorunda değil;
## STANDALONE_SURNAME_CHANCE olasılıkla bu listeden biri gelir.
const STANDALONE_SURNAMES := ["Yılmaz", "Bulut", "Yaprak", "Çınar", "Doruk", "Pınar", "Kartal",
	"Ceylan", "Deniz", "Güneş", "Erdem", "Çetin", "Duman", "Ateş", "Sönmez", "Akın", "Tuna",
	"Toprak", "Kaptan", "Ilgaz", "Ergin", "Yazgan", "Sevinç", "Kuzey", "Ozan", "Irmak", "Serin",
	"Sarp", "Yalın", "Önder", "Oral", "Tümer", "Uyar", "Gürsoy", "Bilgin", "Tezcan", "Varol",
	"Erkan", "Atay", "Sağlam", "Ekinci", "Bakırcı", "Kalender", "Demirci", "Yörük", "Bulgurcu",
	"Pekmez", "Kuru", "Tatlı", "Çakır", "Kekeç", "Şen", "Ilıcalı", "Turhan", "Yeter", "Koral"]
const STANDALONE_SURNAME_CHANCE := 0.35
## Gerçek (Türk) siyasetçi soyadları: üretici bunları ASLA vermez.
const BANNED_SURNAMES := ["Erdoğan", "Kılıçdaroğlu", "Bahçeli", "Akşener", "İnce", "Demirtaş",
	"Davutoğlu", "Babacan", "Özel", "İmamoğlu", "Yavaş", "Özal", "Demirel", "Ecevit", "Erbakan",
	"İnönü", "Atatürk", "Menderes", "Türkeş", "Baykal", "Çiller", "Bayar", "Gül",
	"Sezer", "Soylu", "Karamollaoğlu", "Perinçek", "Oğan", "Dervişoğlu", "Bakırhan", "Kurtulmuş",
	"Yıldırım", "Arınç", "Akdoğan", "Uysal", "Altan", "Sancar", "Koç", "Aydın", "Ağıralioğlu",
	"Akpınar", "Gökçek", "Ağar", "Karayalçın", "Talabani", "Günaydın", "Kaya", "Demir",
	"Çağlayan", "Bozdağ", "Albayrak", "Tanal", "Altay", "Akar", "Ulusoy", "Sarıgül", "Alpay", "Altınok", "Akyol", "Gökçe", "Akgül", "Tanyol", "Karabağ",
	"Akbulut", "Aksoy", "Akay", "Altınay", "Ayyıldız", "Akyıldız", "Günay", "Altınsoy",
	"Ceylanpınar", "Kızılay", "Bilgiç", "Ünal", "Çelik", "Kurt", "Doğan", "Şimşek", "Polat", "Kalkan",
	"Elitaş", "Ağbal", "Bostancı", "Tüfenkci", "Zeybekci", "Fidan", "Bayraktar", "Kacır", "Göktaş"]

## İSİM DİLİ (0.0.222): siyasetçi kurulumundaki dil düğmesi ad ve soyadı bu
## dillerden birinin havuzundan üretir; sıra NAME_LANGS sırası. Düğmede dil
## kendi dilinde yazar (oyun dilinden bağımsız).
const NAME_LANGS := ["tr", "en"]
const NAME_LANG_TITLES := {"tr": "Türkçe", "en": "English"}
const EN_MALE_NAMES := ["James", "John", "Robert", "Michael", "William", "David", "Richard", "Thomas",
	"Charles", "Daniel", "Matthew", "Anthony", "Mark", "Steven", "Andrew", "Paul", "Edward", "George",
	"Henry", "Oliver", "Jack", "Harry", "Samuel", "Benjamin", "Peter", "Arthur", "Frank", "Walter",
	"Leonard", "Victor", "Graham", "Simon", "Nathan", "Owen", "Patrick", "Raymond", "Hugh", "Martin"]
const EN_FEMALE_NAMES := ["Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Susan", "Margaret",
	"Sarah", "Karen", "Emily", "Emma", "Olivia", "Charlotte", "Amelia", "Grace", "Alice", "Helen",
	"Catherine", "Rachel", "Laura", "Hannah", "Lucy", "Rose", "Claire", "Victoria", "Eleanor",
	"Abigail", "Julia", "Diana", "Fiona", "Megan", "Natalie"]
const EN_UNISEX_NAMES := ["Jordan", "Taylor", "Morgan", "Casey", "Alex", "Jamie", "Robin", "Riley"]
const EN_SURNAMES := ["Smith", "Taylor", "Wilson", "Evans", "Thomas", "Roberts", "Walker",
	"Wright", "Robinson", "Thompson", "White", "Hughes", "Edwards", "Green", "Hall", "Wood",
	"Lewis", "Martin", "Jackson", "Clarke", "Turner", "Hill", "Scott", "Cooper", "Morris", "Ward",
	"Moore", "King", "Watson", "Baker", "Harrison", "Morgan", "Patel", "Young", "Allen", "Mitchell",
	"Anderson", "Lee", "Bell", "Parker", "Davies", "Miller", "Shaw", "Bennett", "Fletcher",
	"Hayes", "Murray", "Palmer", "Porter", "Reed", "Russell", "Spencer", "Stone", "Webb", "Wells",
	"Fisher", "Gray", "Holmes", "Hunter", "Lawson", "Marsh", "Nolan", "Pearce", "Quinn", "Rhodes"]
## Gerçek (yabancı) siyasetçi soyadları: rastgele üretici bunları vermez.
const EN_BANNED_SURNAMES := ["Trump", "Biden", "Obama", "Clinton", "Bush", "Reagan", "Nixon", "Kennedy",
	"Carter", "Harris", "Pence", "Sanders", "Blair", "Thatcher", "Churchill", "Cameron", "Starmer",
	"Sunak", "Truss", "Johnson", "May", "Brown", "Major", "Corbyn", "Farage", "Merkel", "Macron", "Putin",
	"Vance", "Walz", "Pelosi", "Lincoln", "Roosevelt", "Truman", "Eisenhower"]

static func next_name_lang(lang: String) -> String:
	return String(NAME_LANGS[(NAME_LANGS.find(lang) + 1) % NAME_LANGS.size()])

static func name_lang_title(lang: String) -> String:
	return String(NAME_LANG_TITLES.get(lang, lang))

const NAME_MAX_LENGTH := 40

static func is_valid_background(id: String) -> bool:
	return BACKGROUNDS.has(id)

static func background(id: String) -> Dictionary:
	return L.tr_dict(BACKGROUNDS.get(id, {}))

static func title(id: String) -> String:
	return L.t(String(BACKGROUNDS.get(id, {}).get("title", "")))

static func is_valid_trait(id: String) -> bool:
	return TRAITS.has(id)

static func trait_info(id: String) -> Dictionary:
	return L.tr_dict(TRAITS.get(id, {}))

static func trait_title(id: String) -> String:
	return L.t(String(TRAITS.get(id, {}).get("title", "")))

static func random_trait(rng: RandomNumberGenerator = null) -> String:
	var index := (rng.randi() if rng != null else randi()) % TRAIT_ORDER.size()
	return String(TRAIT_ORDER[index])

static func random_background(rng: RandomNumberGenerator = null) -> String:
	var index := (rng.randi() if rng != null else randi()) % BACKGROUND_ORDER.size()
	return String(BACKGROUND_ORDER[index])

## trait_id boş ya da geçersizse rastgele bir kişilik verilir (botlar, eski kayıtlar).
static func make(first_name: String, surname: String, background_id: String, hometown: String,
		gender: String = "m", trait_id: String = "") -> Dictionary:
	first_name = first_name.strip_edges()
	surname = surname.strip_edges()
	return {"gender": gender if GENDERS.has(gender) else "m", "first_name": first_name, "surname": surname,
		"name": ("%s %s" % [first_name, surname]).left(NAME_MAX_LENGTH),
		"background": background_id, "trait": trait_id if is_valid_trait(trait_id) else random_trait(),
		"hometown": hometown}

## Kara liste (BANNED_SURNAMES) yalnız RASTGELE üretimde uygulanır (0.0.223):
## oyuncu elle istediği adı yazabilir, kendisi ya da botlar için.
static func is_valid(data: Dictionary) -> bool:
	var trait_id := String(data.get("trait", ""))
	return is_valid_background(String(data.get("background", ""))) and (trait_id == "" or is_valid_trait(trait_id)) \
		and String(data.get("first_name", "")) != "" and String(data.get("surname", "")) != ""

## ELLE YAZILAN İSİM: her kelimenin baş harfi büyük, gerisi küçük (Türkçe
## i/İ, ı/I kuralıyla). Harf, boşluk, kesme ve tire dışındakiler atılır.
const PART_MAX_LENGTH := 20
static func normalize_name(text: String) -> String:
	var cleaned := ""
	for ch in text:
		if ch == " " or ch == "'" or ch == "-" or ch.to_upper() != ch.to_lower() or L.t("çğıöşüÇĞİÖŞÜ").contains(ch):
			cleaned += ch
	while cleaned.contains("  "):
		cleaned = cleaned.replace("  ", " ")
	cleaned = cleaned.lstrip(" ").left(PART_MAX_LENGTH)
	var result := ""
	var start := true
	for ch in cleaned:
		if ch == " " or ch == "-" or ch == "'":
			result += ch
			start = ch != "'"
			continue
		result += _upper_tr(ch) if start else _lower_tr(ch)
		start = false
	return result

static func _upper_tr(ch: String) -> String:
	match ch:
		"i": return "İ"
		"ı": return "I"
	return ch.to_upper()

static func _lower_tr(ch: String) -> String:
	match ch:
		"I": return "ı"
		"İ": return "i"
	return ch.to_lower()

static func is_banned_surname(surname: String) -> bool:
	var key := surname.strip_edges().to_lower()
	for banned in BANNED_SURNAMES + EN_BANNED_SURNAMES:
		if String(banned).to_lower() == key:
			return true
	return false

static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return String(list[(rng.randi() if rng != null else randi()) % list.size()])

## "Ayay", "Gölgöl" gibi kökü ile eki aynı olan soyadlar elenir.
static func _is_doubled(surname: String) -> bool:
	var low := surname.to_lower()
	var half := low.length() / 2
	return low.length() % 2 == 0 and low.left(half) == low.substr(half)

## Rastgele soyad; avoid'deki (oyunda kullanılan) soyadları ve yasaklıları vermez.
static func random_surname(avoid: Array = [], rng: RandomNumberGenerator = null, lang: String = "tr") -> String:
	var surname := ""
	for attempt in 200:
		var roll := rng.randf() if rng != null else randf()
		if lang == "en":
			surname = _pick(EN_SURNAMES, rng)
		elif roll < STANDALONE_SURNAME_CHANCE:
			surname = _pick(STANDALONE_SURNAMES, rng)
		else:
			surname = _pick(SURNAME_ROOTS, rng) + _pick(SURNAME_ENDS, rng)
		if not is_banned_surname(surname) and not avoid.has(surname) and not _is_doubled(surname):
			return surname
	return surname

static func random_gender(rng: RandomNumberGenerator = null) -> String:
	var roll := rng.randf() if rng != null else randf()
	return "m" if roll < MALE_NAME_CHANCE else "f"

## Bu cinsiyetin adları (o cinsiyete özgü + unisex).
static func names_for(gender: String, lang: String = "tr") -> Array:
	if lang == "en":
		return (EN_FEMALE_NAMES if gender == "f" else EN_MALE_NAMES) + EN_UNISEX_NAMES
	return (FEMALE_NAMES if gender == "f" else MALE_NAMES) + UNISEX_NAMES

## Rastgele ad; avoid verilirse o ad tekrar gelmez.
static func random_first_name(gender: String, avoid: String = "", rng: RandomNumberGenerator = null, lang: String = "tr") -> String:
	var pool := names_for(gender, lang)
	var first := avoid
	for attempt in 20:
		first = _pick(pool, rng)
		if first != avoid:
			break
	return first

## {"gender", "first_name", "surname"}: sınırsız yeniden üretilebilir.
## gender boşsa %75 erkek / %25 kadın seçilir (botlar).
static func random_name(avoid_surnames: Array = [], rng: RandomNumberGenerator = null, gender: String = "") -> Dictionary:
	if not GENDERS.has(gender):
		gender = random_gender(rng)
	return {"gender": gender, "first_name": random_first_name(gender, "", rng),
		"surname": random_surname(avoid_surnames, rng)}

## Oyunda (diğer partilerde) kullanılan soyadları.
static func used_surnames(except_peer: int = 0) -> Array:
	var used: Array = []
	for peer_id in PartyManager.politicians.keys():
		if int(peer_id) != except_peer:
			var surname := String(PartyManager.politicians[peer_id].get("surname", ""))
			if surname != "":
				used.append(surname)
	return used

# --- Partiye göre sorgular (PartyManager.parties üzerinden) ------------------------------

static func of(peer_id: int) -> Dictionary:
	return PartyManager.politicians.get(peer_id, {})

## Genel başkanın soyadı (ileride olaylarda/metinlerde kullanılacak).
static func surname_of(peer_id: int) -> String:
	return String(of(peer_id).get("surname", ""))

static func full_name_of(peer_id: int) -> String:
	return String(of(peer_id).get("name", ""))

## Ekranlarda partinin başındaki kişi: siyasetçinin adı-soyadı; siyasetçisi
## yoksa (eski kayıt, bölünen parti) oyuncu adı.
static func display_name(peer_id: int) -> String:
	var full := full_name_of(peer_id)
	if full != "":
		return full
	return String(MultiplayerManager.players.get(peer_id, {}).get("name", "?"))

static func background_of(peer_id: int) -> String:
	return String(of(peer_id).get("background", ""))

static func hometown_of(peer_id: int) -> String:
	return String(of(peer_id).get("hometown", ""))

static func trait_of(peer_id: int) -> String:
	return String(of(peer_id).get("trait", ""))

static func has_background(peer_id: int, id: String) -> bool:
	return background_of(peer_id) == id

## PARTİ DÜZEYİ meslek: partinin herhangi bir üyesinde bu meslek var mı?
static func party_has_background(party_or_peer: int, id: String) -> bool:
	for member in PartyManager.members_of(PartyManager.party_of(party_or_peer)):
		if has_background(int(member), id):
			return true
	return false

## HAMLEYİ YAPAN siyasetçinin meslek × kişilik çarpanı (bkz. etki anahtarları).
static func effect(peer_id: int, key: String) -> float:
	return float(BACKGROUNDS.get(background_of(peer_id), {}).get("effects", {}).get(key, 1.0)) \
		* float(TRAITS.get(trait_of(peer_id), {}).get("effects", {}).get(key, 1.0))

## PARTİNİN çarpanı: üyelerdeki her farklı meslek ve kişilik bir kez sayılır.
static func party_effect(party_or_peer: int, key: String) -> float:
	var backgrounds := {}
	var traits := {}
	for member in PartyManager.members_of(PartyManager.party_of(party_or_peer)):
		backgrounds[background_of(int(member))] = true
		traits[trait_of(int(member))] = true
	var mult := 1.0
	for id in backgrounds.keys():
		mult *= float(BACKGROUNDS.get(id, {}).get("effects", {}).get(key, 1.0))
	for id in traits.keys():
		mult *= float(TRAITS.get(id, {}).get("effects", {}).get(key, 1.0))
	return mult

## Partinin bu gruba hitap çarpanı (bir üyenin mesleği o gruba hitap ediyorsa).
static func group_appeal(party_or_peer: int, group: String) -> float:
	for member in PartyManager.members_of(PartyManager.party_of(party_or_peer)):
		if (BACKGROUNDS.get(background_of(int(member)), {}).get("appeal", []) as Array).has(group):
			return APPEAL_MULT
	return 1.0

## Hemşehri desteği: sadece memleket (komşu iller etkilenmez). Partide iki
## siyasetçi varsa ikisinin memleketi de sayılır.
static func hometown_activity(province_id: String, party_or_peer: int) -> float:
	for member in PartyManager.members_of(PartyManager.party_of(party_or_peer)):
		var home := hometown_of(int(member))
		if home != "" and home == province_id:
			return HOMETOWN_ACTIVITY
	return 0.0
