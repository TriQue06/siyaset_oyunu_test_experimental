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
##   {"name": String, "background": String, "hometown": String}
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

const NAME_MAX_LENGTH := 20

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

static func make(politician_name: String, background_id: String, hometown: String) -> Dictionary:
	return {"name": politician_name.strip_edges().left(NAME_MAX_LENGTH),
		"background": background_id, "hometown": hometown}

static func is_valid(data: Dictionary) -> bool:
	return is_valid_background(String(data.get("background", ""))) \
		and String(data.get("name", "")).strip_edges() != ""

# --- Partiye göre sorgular (PartyManager.parties üzerinden) ------------------------------

static func of(peer_id: int) -> Dictionary:
	return PartyManager.parties.get(peer_id, {}).get("politician", {})

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
