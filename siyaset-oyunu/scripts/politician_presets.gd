class_name PoliticianPresets
extends RefCounted
## SİYASETÇİ PROFİLİ: oyun bir siyasetçinin parti kurmasıyla başlar. Parti
## kurulmadan önce her oyuncu siyasetçisini seçer (bkz. politician_setup.gd):
##   - GEÇMİŞ: 6 meslek, her biri bir siyasi eksenin bir ucuyla uyumlu. Görüş
##     parti kurulumunda serbestçe seçilir; oyun başlarken geçmişin ekseni o
##     uca BACKGROUND_SHIFT kadar daha kayar (iş insanı + Devletçi seçim:
##     −1,5 yerine −1). Geçmişin kalıcı bir oyun avantajı da vardır (perk).
##   - MEMLEKET: haritadan seçilen il. Oyuna orada 2. seviye teşkilatla
##     başlanır, il seçmeni partinin görüşüne çekilir ve memlekette kalıcı
##     "hemşehri" desteği vardır. Komşu iller ETKİLENMEZ.
## ARAYÜZ METİNLERİ SAYI İÇERMEZ (özet anlatım); sayılar sadece burada.
## Veri PartyManager.politicians[peer] içinde durur (partiden bağımsız) =
##   {"gender", "first_name", "surname", "name" (ad + soyad), "background", "hometown"}
## İSİM TAMAMEN RASTGELE (elle yazılmaz): random_name(). SOYAD ileride çok
## yerde kullanılacak (bkz. surname_of). Soyadlar uydurma kök + ekten üretilir;
## gerçek siyasetçi soyadları BANNED_SURNAMES ile ayrıca engellenir.
## (bkz. PartyManager.set_my_politician). Kişisel özellikler sonra eklenecek.

## Geçmiş -> {title, axis, dir, blurb, perk}. Sıra ekranda da bu sıra.
const BACKGROUNDS := {
	"sendikaci": {"title": "Sendikacı", "axis": "economic", "dir": -1,
		"blurb": "Fabrika kapılarında büyüdün, grevleri sen örgütledin.",
		"perk": "Mitinglerin daha güçlü yankı bulur."},
	"is_insani": {"title": "İş İnsanı", "axis": "economic", "dir": 1,
		"blurb": "Kendi şirketini kurdun, sermaye çevreleri seni tanır.",
		"perk": "Oyuna daha fazla kaynakla başlarsın."},
	"akademisyen": {"title": "Akademisyen", "axis": "social", "dir": -1,
		"blurb": "Kürsüden siyasete indin; fikirlerin tartışma başlatır.",
		"perk": "Sunduğun yasalar illerde daha çok ses getirir."},
	"ilahiyatci": {"title": "İlahiyatçı", "axis": "social", "dir": 1,
		"blurb": "Cemaatin saygın bir siması; sözüne güvenilir.",
		"perk": "Karalama ve kasetler sana daha az işler."},
	"belediye_baskani": {"title": "Belediye Başkanı", "axis": "administrative", "dir": -1,
		"blurb": "Şehrini yıllarca yönettin, yerel ağları iyi bilirsin.",
		"perk": "Teşkilatların daha çok oy getirir."},
	"emekli_subay": {"title": "Emekli Subay", "axis": "administrative", "dir": 1,
		"blurb": "Disiplin ve birlik senin için her şeyden önce gelir.",
		"perk": "Partinde iç karışıklık daha zor büyür."},
}
const BACKGROUND_ORDER := ["sendikaci", "is_insani", "akademisyen", "ilahiyatci",
	"belediye_baskani", "emekli_subay"]

# --- Geçmiş avantajları -------------------------------------------------------------
const UNION_MITING_MULT := 1.25
const BUSINESS_START_MANA := 20
const ACADEMIC_LAW_MULT := 1.3
const CLERIC_DAMAGE_MULT := 0.7
const MAYOR_ORG_MULT := 1.25
const OFFICER_TURMOIL_MULT := 0.6

# --- Memleket -----------------------------------------------------------------
## Oyun başında memlekette bedava kurulan teşkilat seviyesi.
const HOMETOWN_ORG_LEVEL := 2
## Kalıcı hemşehri desteği (aktivite puanı, sönmez): sadece memleket.
const HOMETOWN_ACTIVITY := 4.0
## Geçmişin ekseninde oyun başında ek kayma (o ucun yönünde).
const BACKGROUND_SHIFT := 0.5
## Oyun başında memleket seçmeninin görüşü partiye bu oranda çekilir (kalıcı:
## ilin "kökeni" de çekilir, zamanla geri dönmez).
const HOMETOWN_PULL := 0.4

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

const NAME_MAX_LENGTH := 40

static func is_valid_background(id: String) -> bool:
	return BACKGROUNDS.has(id)

static func background(id: String) -> Dictionary:
	return BACKGROUNDS.get(id, {})

static func title(id: String) -> String:
	return String(BACKGROUNDS.get(id, {}).get("title", ""))

## Geçmişin eksen ucunun adı ("Devletçi").
static func side_text(id: String) -> String:
	var info: Dictionary = BACKGROUNDS.get(id, {})
	if info.is_empty():
		return ""
	var sides: Dictionary = IdeologyAxes.AXIS_SIDES[info["axis"]]
	return String(sides["pos"] if int(info["dir"]) > 0 else sides["neg"])

## Geçmişin oyun başında görüşe kattığı kayma: {"axis", "delta"} ya da boş.
static func ideology_shift(id: String) -> Dictionary:
	var info: Dictionary = BACKGROUNDS.get(id, {})
	if info.is_empty():
		return {}
	return {"axis": String(info["axis"]), "delta": BACKGROUND_SHIFT * int(info["dir"])}

## Görüşe geçmiş kaymasını uygulanmış hâliyle döndürür (önizleme/test için).
static func shifted_ideology(id: String, ideology: Dictionary) -> Dictionary:
	var result := ideology.duplicate()
	var shift := ideology_shift(id)
	if not shift.is_empty():
		result[shift["axis"]] = IdeologyAxes.clamp_value(float(result.get(shift["axis"], 0.0)) + float(shift["delta"]))
	return result

static func random_background(rng: RandomNumberGenerator = null) -> String:
	var index := (rng.randi() if rng != null else randi()) % BACKGROUND_ORDER.size()
	return String(BACKGROUND_ORDER[index])

static func make(first_name: String, surname: String, background_id: String, hometown: String,
		gender: String = "m") -> Dictionary:
	first_name = first_name.strip_edges()
	surname = surname.strip_edges()
	return {"gender": gender if GENDERS.has(gender) else "m", "first_name": first_name, "surname": surname,
		"name": ("%s %s" % [first_name, surname]).left(NAME_MAX_LENGTH),
		"background": background_id, "hometown": hometown}

static func is_valid(data: Dictionary) -> bool:
	return is_valid_background(String(data.get("background", ""))) \
		and String(data.get("first_name", "")) != "" and String(data.get("surname", "")) != "" \
		and not is_banned_surname(String(data.get("surname", "")))

## ELLE YAZILAN İSİM: her kelimenin baş harfi büyük, gerisi küçük (Türkçe
## i/İ, ı/I kuralıyla). Harf, boşluk, kesme ve tire dışındakiler atılır.
const PART_MAX_LENGTH := 20
static func normalize_name(text: String) -> String:
	var cleaned := ""
	for ch in text:
		if ch == " " or ch == "'" or ch == "-" or ch.to_upper() != ch.to_lower() or "çğıöşüÇĞİÖŞÜ".contains(ch):
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
	for banned in BANNED_SURNAMES:
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
static func random_surname(avoid: Array = [], rng: RandomNumberGenerator = null) -> String:
	var surname := ""
	for attempt in 200:
		var roll := rng.randf() if rng != null else randf()
		if roll < STANDALONE_SURNAME_CHANCE:
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
static func names_for(gender: String) -> Array:
	return (FEMALE_NAMES if gender == "f" else MALE_NAMES) + UNISEX_NAMES

## Rastgele ad; avoid verilirse o ad tekrar gelmez.
static func random_first_name(gender: String, avoid: String = "", rng: RandomNumberGenerator = null) -> String:
	var pool := names_for(gender)
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

static func has_background(peer_id: int, id: String) -> bool:
	return background_of(peer_id) == id

## PARTİ DÜZEYİ geçmiş avantajı: partinin herhangi bir üyesinde bu geçmiş var mı?
## (Teşkilat bonusu, karalamaya dayanıklılık, iç karışıklık gibi partiye ait
## etkiler; miting/yasa gibi hamle etkileri hamleyi yapan siyasetçiye bakar.)
static func party_has_background(party_or_peer: int, id: String) -> bool:
	for member in PartyManager.members_of(PartyManager.party_of(party_or_peer)):
		if has_background(int(member), id):
			return true
	return false

## Hemşehri desteği: sadece memleket (komşu iller etkilenmez). Partide iki
## siyasetçi varsa ikisinin memleketi de sayılır.
static func hometown_activity(province_id: String, party_or_peer: int) -> float:
	for member in PartyManager.members_of(PartyManager.party_of(party_or_peer)):
		var home := hometown_of(int(member))
		if home != "" and home == province_id:
			return HOMETOWN_ACTIVITY
	return 0.0
