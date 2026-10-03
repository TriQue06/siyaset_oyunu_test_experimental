class_name PoliticianPresets
extends RefCounted
## SİYASETÇİ PROFİLİ: oyun bir siyasetçinin parti kurmasıyla başlar. Parti
## kurulmadan önce her oyuncu siyasetçisini seçer (bkz. politician_setup.gd):
##   - GEÇMİŞ: 6 meslek, her biri bir siyasi eksenin bir ucuyla uyumlu. Parti
##     o eksende o uçtan başlar (kurulumda değiştirilemez) ve geçmişin kalıcı
##     bir oyun avantajı vardır (bkz. BACKGROUNDS[..]["perk"]).
##   - MEMLEKET: haritadan seçilen il. Oyuna orada 2. seviye teşkilatla
##     başlanır, il seçmeni partinin görüşüne çekilir ve hem memlekette hem
##     komşularında kalıcı "hemşehri" desteği vardır.
## Veri parti sözlüğünde durur: parties[peer]["politician"] =
##   {"first_name", "surname", "name" (ad + soyad), "background", "hometown"}
## İSİM TAMAMEN RASTGELE (elle yazılmaz): random_name(). SOYAD ileride çok
## yerde kullanılacak (bkz. surname_of). Soyadlar uydurma kök + ekten üretilir;
## gerçek siyasetçi soyadları BANNED_SURNAMES ile ayrıca engellenir.
## (bkz. PartyManager.set_my_politician). Kişisel özellikler sonra eklenecek.

## Geçmiş -> {title, axis, dir, blurb, perk}. Sıra ekranda da bu sıra.
const BACKGROUNDS := {
	"sendikaci": {"title": "Sendikacı", "axis": "economic", "dir": -1,
		"blurb": "Fabrika kapılarında büyüdün, grevleri sen örgütledin.",
		"perk": "Mitinglerin %25 daha güçlü."},
	"is_insani": {"title": "İş İnsanı", "axis": "economic", "dir": 1,
		"blurb": "Kendi şirketini kurdun, sermaye çevreleri seni tanır.",
		"perk": "Oyuna +2 mana ile başlarsın."},
	"akademisyen": {"title": "Akademisyen", "axis": "social", "dir": -1,
		"blurb": "Kürsüden siyasete indin; fikirlerin tartışma başlatır.",
		"perk": "Sunduğun yasaların il etkisi %30 daha güçlü."},
	"ilahiyatci": {"title": "İlahiyatçı", "axis": "social", "dir": 1,
		"blurb": "Cemaatin saygın bir siması; sözüne güvenilir.",
		"perk": "Karalama ve kasetlerden %30 daha az zarar görürsün."},
	"belediye_baskani": {"title": "Belediye Başkanı", "axis": "administrative", "dir": -1,
		"blurb": "Şehrini yıllarca yönettin, yerel ağları iyi bilirsin.",
		"perk": "Teşkilatlarının kalıcı oy bonusu %25 fazla."},
	"emekli_subay": {"title": "Emekli Subay", "axis": "administrative", "dir": 1,
		"blurb": "Disiplin ve birlik senin için her şeyden önce gelir.",
		"perk": "Partinde iç karışıklık %40 daha az birikir."},
}
const BACKGROUND_ORDER := ["sendikaci", "is_insani", "akademisyen", "ilahiyatci",
	"belediye_baskani", "emekli_subay"]

# --- Geçmiş avantajları -------------------------------------------------------------
const UNION_MITING_MULT := 1.25
const BUSINESS_START_MANA := 2
const ACADEMIC_LAW_MULT := 1.3
const CLERIC_DAMAGE_MULT := 0.7
const MAYOR_ORG_MULT := 1.25
const OFFICER_TURMOIL_MULT := 0.6

# --- Memleket -----------------------------------------------------------------
## Oyun başında memlekette bedava kurulan teşkilat seviyesi.
const HOMETOWN_ORG_LEVEL := 2
## Kalıcı hemşehri desteği (aktivite puanı, sönmez): memleket ve komşuları.
const HOMETOWN_ACTIVITY := 4.0
const NEIGHBOR_ACTIVITY := 1.5
## Oyun başında memleket seçmeninin görüşü partiye bu oranda çekilir (kalıcı:
## ilin "kökeni" de çekilir, zamanla geri dönmez).
const HOMETOWN_PULL := 0.4

# --- Rastgele isim ----------------------------------------------------------------
const FIRST_NAMES := [
	"Ahmet", "Ayla", "Aras", "Bahar", "Barlas", "Belgin", "Berk", "Cansu", "Cemre", "Cihan",
	"Defne", "Doruk", "Ece", "Emre", "Eylül", "Ferit", "Figen", "Gaye", "Gökay", "Gülay",
	"Hakan", "Hülya", "Ilgın", "İlkay", "İpek", "Kaan", "Kerem", "Lale", "Levent", "Melis",
	"Mert", "Nazlı", "Nevzat", "Nilgün", "Oktay", "Orhun", "Özge", "Pelin", "Rüya", "Selin",
	"Serdar", "Sevgi", "Sinem", "Şebnem", "Tamer", "Tuba", "Tuncay", "Ufuk", "Ülkü", "Vedat",
	"Yasemin", "Yekta", "Zafer", "Zeynep", "Arda", "Burcu", "Ceyda", "Erkin", "Gizem", "Onur",
]
## Soyad = kök + ek ("Gök" + "yelken" = "Gökyelken"). Yaygın siyasetçi
## soyadı kalıpları (-oğlu, -doğan, -demir, -kaya, -han ...) bilerek yok.
const SURNAME_ROOTS := ["Ak", "Kara", "Gök", "Yel", "Dağ", "Çam", "Ay", "Gün", "Tan", "Bal",
	"Kır", "Ulu", "Boz", "Sarı", "Alp", "Çağ", "Al", "Ilık", "Sis", "Ilgaz"]
const SURNAME_ENDS := ["söğüt", "yelken", "pınar", "yamaç", "çınar", "ırmak", "doruk", "koru",
	"bulut", "yaprak", "kumsal", "dere", "yayla", "gölge", "rüzgâr", "fidan", "kuşak", "sırt",
	"meşe", "ılgın", "serçe", "kıyı", "çiçek", "ova"]
## Gerçek (Türk) siyasetçi soyadları: üretici bunları ASLA vermez.
const BANNED_SURNAMES := ["Erdoğan", "Kılıçdaroğlu", "Bahçeli", "Akşener", "İnce", "Demirtaş",
	"Davutoğlu", "Babacan", "Özel", "İmamoğlu", "Yavaş", "Özal", "Demirel", "Ecevit", "Erbakan",
	"İnönü", "Atatürk", "Menderes", "Türkeş", "Baykal", "Çiller", "Yılmaz", "Bayar", "Gül",
	"Sezer", "Soylu", "Karamollaoğlu", "Perinçek", "Oğan", "Dervişoğlu", "Bakırhan", "Kurtulmuş",
	"Yıldırım", "Arınç", "Akdoğan", "Uysal", "Altan", "Sancar", "Koç", "Aydın", "Ağıralioğlu",
	"Akpınar", "Gökçek", "Ağar", "Karayalçın", "Talabani", "Günaydın", "Kaya", "Demir",
	"Çağlayan", "Bozdağ", "Albayrak", "Tanal", "Altay", "Akar", "Ulusoy", "Sarıgül", "Alpay"]

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

## Partinin başlangıç görüşünü geçmişe uydurur (geçmişin ekseni sabitlenir).
static func apply_to_ideology(id: String, ideology: Dictionary) -> Dictionary:
	var result := ideology.duplicate()
	var info: Dictionary = BACKGROUNDS.get(id, {})
	if not info.is_empty():
		result[info["axis"]] = IdeologyAxes.START_MAGNITUDE * int(info["dir"])
	return result

static func random_background(rng: RandomNumberGenerator = null) -> String:
	var index := (rng.randi() if rng != null else randi()) % BACKGROUND_ORDER.size()
	return String(BACKGROUND_ORDER[index])

static func make(first_name: String, surname: String, background_id: String, hometown: String) -> Dictionary:
	first_name = first_name.strip_edges()
	surname = surname.strip_edges()
	return {"first_name": first_name, "surname": surname,
		"name": ("%s %s" % [first_name, surname]).left(NAME_MAX_LENGTH),
		"background": background_id, "hometown": hometown}

static func is_valid(data: Dictionary) -> bool:
	return is_valid_background(String(data.get("background", ""))) \
		and String(data.get("first_name", "")) != "" and String(data.get("surname", "")) != "" \
		and not is_banned_surname(String(data.get("surname", "")))

static func is_banned_surname(surname: String) -> bool:
	var key := surname.strip_edges().to_lower()
	for banned in BANNED_SURNAMES:
		if String(banned).to_lower() == key:
			return true
	return false

static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return String(list[(rng.randi() if rng != null else randi()) % list.size()])

## Rastgele soyad; avoid'deki (oyunda kullanılan) soyadları ve yasaklıları vermez.
static func random_surname(avoid: Array = [], rng: RandomNumberGenerator = null) -> String:
	var surname := ""
	for attempt in 200:
		surname = _pick(SURNAME_ROOTS, rng) + _pick(SURNAME_ENDS, rng)
		if not is_banned_surname(surname) and not avoid.has(surname):
			return surname
	return surname

## {"first_name", "surname"}: sınırsız yeniden üretilebilir.
static func random_name(avoid_surnames: Array = [], rng: RandomNumberGenerator = null) -> Dictionary:
	return {"first_name": _pick(FIRST_NAMES, rng), "surname": random_surname(avoid_surnames, rng)}

## Oyunda (diğer partilerde) kullanılan soyadları.
static func used_surnames(except_peer: int = 0) -> Array:
	var used: Array = []
	for peer_id in PartyManager.parties.keys():
		if int(peer_id) != except_peer:
			var surname := String(PartyManager.parties[peer_id].get("politician", {}).get("surname", ""))
			if surname != "":
				used.append(surname)
	return used

# --- Partiye göre sorgular (PartyManager.parties üzerinden) ------------------------------

static func of(peer_id: int) -> Dictionary:
	return PartyManager.parties.get(peer_id, {}).get("politician", {})

## Genel başkanın soyadı (ileride olaylarda/metinlerde kullanılacak).
static func surname_of(peer_id: int) -> String:
	return String(of(peer_id).get("surname", ""))

static func full_name_of(peer_id: int) -> String:
	return String(of(peer_id).get("name", ""))

static func background_of(peer_id: int) -> String:
	return String(of(peer_id).get("background", ""))

static func hometown_of(peer_id: int) -> String:
	return String(of(peer_id).get("hometown", ""))

static func has_background(peer_id: int, id: String) -> bool:
	return background_of(peer_id) == id

## Hemşehri desteği: memleket HOMETOWN_ACTIVITY, komşu il NEIGHBOR_ACTIVITY.
static func hometown_activity(province_id: String, peer_id: int) -> float:
	var home := hometown_of(peer_id)
	if home == "":
		return 0.0
	if home == province_id:
		return HOMETOWN_ACTIVITY
	if GameMap.neighbors().get(home, []).has(province_id):
		return NEIGHBOR_ACTIVITY
	return 0.0
