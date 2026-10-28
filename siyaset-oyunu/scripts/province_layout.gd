class_name ProvinceLayout
extends RefCounted
## İl adları ve nüfusa göre vekil dağılımı; harita geometrisinden bağımsızdır.

const PROVINCE_SEATS := 300
const MIN_SEATS := 3
const VOTERS_PER_SEAT := 100000

const ADJECTIVES := ["Taşlı", "Yeşil", "Kızıl", "Ak", "Kara", "Gök", "Sarı", "Ulu", "Derin", "Eski",
	"Yeni", "Kuru", "Serin", "Uzun", "Yüce", "Çamlı", "Kayalı", "Güneşli", "Rüzgârlı", "Sisli", "Karlı",
	"Söğütlü", "Kumlu", "Tuzlu", "Pınarlı", "Meşeli", "Bağlı", "Çorak", "Demirli", "Gümüşlü", "Ilık",
	"Dumanlı", "Kırlı", "Otlu", "Sessiz", "Geniş", "Bakır", "Mor", "Boz", "Ala", "Gürgenli", "Kekikli",
	"Çınarlı", "Kartallı", "Ceylanlı", "Dikenli", "Engin", "Issız", "Bereketli", "Yalın",
	"Ardıçlı", "Kestaneli", "Cevizli", "Zeytinli", "Narlı", "İncirli", "Mermerli", "Yıldızlı"]
const LAND_NOUNS := ["Plato", "Vadi", "Ova", "Yayla", "Tepe", "Bozkır", "Havza", "Düzlük", "Yamaç",
	"Kanyon", "Sırt", "Koru", "Göl", "Irmak", "Pınar", "Dağlar", "Geçit", "Boğaz", "Orman", "Bayır",
	"Çayır", "Yazı", "Kır", "Uçurum", "Mesire", "Bataklık", "Obruk"]
const COAST_NOUNS := ["Liman", "Kıyı", "Körfez", "Burun", "Koy", "Sahil", "Lagün", "Ada", "Sığlık", "İskele"]
## "Kuzey ___" kalıbı için iyelik ekli biçimler.
const POSSESSIVE := {
	"Plato": "Platosu", "Vadi": "Vadisi", "Ova": "Ovası", "Yayla": "Yaylası", "Tepe": "Tepesi",
	"Bozkır": "Bozkırı", "Havza": "Havzası", "Düzlük": "Düzlüğü", "Yamaç": "Yamacı",
	"Kanyon": "Kanyonu", "Sırt": "Sırtı", "Koru": "Korusu", "Göl": "Gölü", "Irmak": "Irmağı",
	"Pınar": "Pınarı", "Dağlar": "Dağları", "Liman": "Limanı", "Kıyı": "Kıyısı", "Körfez": "Körfezi",
	"Burun": "Burnu", "Koy": "Koyu", "Sahil": "Sahili", "Geçit": "Geçidi", "Boğaz": "Boğazı",
	"Orman": "Ormanı", "Bayır": "Bayırı", "Çayır": "Çayırı", "Yazı": "Yazısı", "Kır": "Kırı",
	"Uçurum": "Uçurumu", "Mesire": "Mesiresi", "Bataklık": "Bataklığı",
	"Obruk": "Obruğu", "Lagün": "Lagünü", "Ada": "Adası", "Sığlık": "Sığlığı", "İskele": "İskelesi",
}
const COMPOUND_HEADS := ["Ak", "Kara", "Sarı", "Yeşil", "Gök", "Kızıl", "Çam", "Taş", "Demir", "Kum",
	"Söğüt", "Meşe", "Bağ", "Göl", "Yeni", "Eski", "Ilıca", "Kaya", "Ulu", "Tuz", "Bakır", "Boz", "Çınar",
	"Ardıç", "Kestane", "Ceviz", "Zeytin", "Nar", "Elma", "Gül", "Lale", "Kartal", "Doğan", "Şahin",
	"Ceylan", "Geyik", "Kuzu", "Arı", "Bal", "Altın", "Gümüş", "Mermer", "Kireç", "Çakıl", "Dere", "Su",
	"Ilgın", "Kavak", "Çınarlı", "Yaban", "Erik", "Kiraz", "Yıldız", "Ay", "Gün"]
const COMPOUND_TAILS := ["ova", "pınar", "yayla", "dere", "tepe", "vadi", "yurt", "alan", "bük", "kaya",
	"su", "hisar", "kale", "yazı", "köprü", "çay", "köy", "ören", "bel", "yaka", "ağıl", "oba", "pazarı",
	"durak", "beli", "gediği", "yatağı", "ılgaz", "kuyu", "konak"]
const COAST_TAILS := ["liman", "kıyı", "koy", "burun", "ada", "iskele", "kum"]
const METRO_TAILS := ["kent", "şehir"]
## Tek kelimelik, köklü yer adları (kalıplardan bağımsız; çeşitlilik için).
const STANDALONE := ["Erenler", "Yalıntaş", "Çınarcık", "Gediz", "Akyazı", "Kemerli", "Saraylı",
	"Ilgaz", "Pertek", "Ortaca", "Datça", "Karacabey", "Oltu", "Kiğı", "Hınıs", "Ahlat", "Keban",
	"Yeşilyurt", "Kumru", "Görele", "Ulubey", "Sason", "Suruç", "Kavak", "Ilıca", "Hamur",
	"Çayeli", "Pazar", "Dikmen", "Sarıkaya", "Kemah", "Boyabat", "Taşova", "Ulus", "Gebiz", "Elmalı",
	"Kınık", "Yatağan", "Bozdoğan", "Emet", "Şaphane", "Çivril", "Senirkent", "Ardanuç", "Şavşat"]

static func allocate_seats(population: Array, seat_total: int = 300) -> Array:
	var count := population.size()
	var seats: Array = []
	seats.resize(count)
	seats.fill(MIN_SEATS)
	var left := maxi(0, seat_total - MIN_SEATS * count)
	var total := 0.0
	for p in population:
		total += float(p)
	var remainders: Array = []
	var given := 0
	for i in count:
		var exact := float(population[i]) / maxf(total, 0.0001) * left
		var whole := int(floor(exact))
		seats[i] = int(seats[i]) + whole
		given += whole
		remainders.append([exact - whole, i])
	remainders.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var k := 0
	while given < left:
		seats[remainders[k % count][1]] = int(seats[remainders[k % count][1]]) + 1
		given += 1
		k += 1
	return seats

static func pick(rng: RandomNumberGenerator, list: Array) -> String:
	return String(list[rng.randi_range(0, list.size() - 1)])

## Dönüş: {"name": ad, "parts": benzerlik denetimi için kök kelimeler (küçük harf)}.

static func make_name(rng: RandomNumberGenerator, coastal: bool, metro: bool, center: Vector2) -> Dictionary:
	if metro:
		var tail := pick(rng, METRO_TAILS)
		var head := pick(rng, COMPOUND_HEADS)
		if rng.randf() < 0.7:
			return {"name": head + tail, "parts": [head.to_lower(), tail]}
		var prefix := "Yeni" if rng.randf() < 0.5 else "Büyük"
		return {"name": prefix + tail, "parts": [prefix.to_lower(), tail]}
	var roll := rng.randf()
	var nouns: Array = COAST_NOUNS if coastal and rng.randf() < 0.7 else LAND_NOUNS
	if roll < 0.18:
		var dx := center.x - 0.5
		var dy := center.y - 0.5
		var direction := ("Doğu" if dx > 0.0 else "Batı") if absf(dx) * 0.9 > absf(dy) else ("Güney" if dy > 0.0 else "Kuzey")
		var noun := pick(rng, nouns)
		return {"name": "%s %s" % [direction, POSSESSIVE.get(noun, noun)], "parts": [direction.to_lower(), noun.to_lower()]}
	if roll < 0.48:
		var adjective := pick(rng, ADJECTIVES)
		var noun := pick(rng, nouns)
		return {"name": "%s %s" % [adjective, noun], "parts": [adjective.to_lower(), noun.to_lower()]}
	if roll < 0.62:
		var place := pick(rng, STANDALONE)
		return {"name": place, "parts": [place.to_lower()]}
	var tails: Array = COAST_TAILS if coastal and rng.randf() < 0.5 else COMPOUND_TAILS
	var head := pick(rng, COMPOUND_HEADS)
	var tail := pick(rng, tails)
	return {"name": head + tail, "parts": [head.to_lower(), tail]}
