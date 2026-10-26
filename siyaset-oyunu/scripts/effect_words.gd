class_name EffectWords
## OYUNCUYA NİTEL DİL: simülasyon kesin sayılarla hesaplar, arayüz etkinin
## BÜYÜKLÜĞÜNÜ kelimeyle söyler ("hafif destek kaybı", "güçlü yerel etki").
## Bütün eşikler TEK YERDE (bu dosya); başka betikler kendi eşiğini yazmaz.
## Eşikler oyuncuya hiçbir zaman gösterilmez.
##
## Ölçekler (etkinin hangi değere uygulandığı):
##   "national": ulusal destek (kamuoyu) puanı; sınırı ±PublicOpinion.LIMIT.
##   "group"   : seçmen grubu yakınlığı (0–100) değişimi.
##   "local"   : bir ildeki yerel güç değişimi.

## Beş basamak: 0 çok az, 1 hafif, 2 orta, 3 belirgin, 4 güçlü / ağır.
const SCALES := {
	"national": [0.3, 0.8, 1.6, 3.0],
	"group": [1.5, 4.0, 8.0, 14.0],
	"local": [1.0, 2.5, 5.0, 8.0],
}
const GOOD := ["çok az", "hafif", "orta", "belirgin", "güçlü"]
const BAD := ["çok az", "hafif", "orta", "belirgin", "ağır"]
## Bundan küçük değerler "etkisiz" sayılır (yuvarlama gürültüsü).
const NEGLIGIBLE := 0.05

## Değerin büyüklük basamağı (0..4).
static func level(value: float, scale: String = "national") -> int:
	var steps: Array = SCALES.get(scale, SCALES["national"])
	var a := absf(value)
	var result := 0
	for i in steps.size():
		if a >= float(steps[i]):
			result = i + 1
	return result

## Sıfat: "hafif", "belirgin", "ağır"... (işarete göre).
static func adjective(value: float, scale: String = "national") -> String:
	var i := level(value, scale)
	return L.t(String(GOOD[i] if value >= 0.0 else BAD[i]))

## Değişim ifadesi: "hafif destek artışı", "ağır destek kaybı".
## noun: neyin değiştiği ("destek", "yerel güç"...).
static func change(value: float, scale: String = "national", noun: String = "destek") -> String:
	if absf(value) < NEGLIGIBLE:
		return L.t("belirgin bir etki yok")
	return "%s %s %s" % [adjective(value, scale), L.t(noun), L.t("artışı") if value > 0.0 else L.t("kaybı")]

## Aynı ifadenin cümle başı hali ("Hafif destek artışı").
static func change_cap(value: float, scale: String = "national", noun: String = "destek") -> String:
	var text := change(value, scale, noun)
	return text.substr(0, 1).to_upper() + text.substr(1)

## Durum (değişim değil): ulusal kamuoyu gibi bir seviye için kısa etiket.
static func standing(value: float, scale: String = "national") -> String:
	if level(value, scale) == 0:
		return L.t("nötr")
	return "%s %s" % [adjective(value, scale), L.t("olumlu") if value > 0.0 else L.t("olumsuz")]

## Gidişat: "güçleniyor" / "durağan" / "zayıflıyor".
static func trend(delta: float, scale: String = "national") -> String:
	if level(delta, scale) == 0:
		return L.t("durağan")
	return L.t("güçleniyor") if delta > 0.0 else L.t("zayıflıyor")

## Olasılık (0..1) için risk sözcüğü.
static func risk(probability: float) -> String:
	if probability <= 0.001:
		return L.t("risk yok")
	if probability < 0.12:
		return L.t("düşük risk")
	if probability < 0.25:
		return L.t("orta risk")
	if probability < 0.4:
		return L.t("yüksek risk")
	return L.t("çok yüksek risk")

## Çarpan (1 = normal) için etkinlik sözcüğü.
static func multiplier(mult: float) -> String:
	if mult >= 1.6:
		return L.t("çok etkili")
	if mult >= 1.15:
		return "etkili"
	if mult > 0.85:
		return L.t("olağan")
	if mult > 0.5:
		return L.t("zayıf")
	return L.t("çok zayıf")

## Dar tablo hücreleri için: ▲ / ▲▲ / ▲▲▲ (▼ olumsuz), etkisizse "·".
static func arrows(value: float, scale: String = "national") -> String:
	var i := level(value, scale)
	if i == 0:
		return "·"
	var count := 1 if i <= 1 else (2 if i <= 2 else 3)
	return ("+" if value > 0.0 else "−").repeat(count)

## 0–100 arası bir güç / uyum değeri için kısa sözcük.
static func strength(value: float) -> String:
	if value >= 75.0:
		return L.t("çok güçlü")
	if value >= 55.0:
		return L.t("güçlü")
	if value >= 35.0:
		return L.t("orta")
	if value >= 15.0:
		return L.t("zayıf")
	return L.t("çok zayıf")

## Bir MİKTARIN (değişim değil) sözcüğü: "düşük", "orta", "yüksek"...
## Olumsuz değerde "olumsuz" eklenir.
const AMOUNT := ["çok düşük", "düşük", "orta", "yüksek", "çok yüksek"]
static func amount(value: float, scale: String = "local") -> String:
	var text := L.t(String(AMOUNT[level(value, scale)]))
	return text if value >= 0.0 else L.t("olumsuz (%s)") % text
