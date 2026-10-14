class_name L
extends RefCounted
## YERELLEŞTİRME YARDIMCISI. Kaynak dil Türkçedir ve ÇEVİRİ ANAHTARI Türkçe
## metnin kendisidir (localization/en.po: msgid Türkçe, msgstr İngilizce).
## Çevirisi olmayan metin anahtar olarak, yani Türkçe görünür: oyuncu hiçbir
## zaman ham anahtar görmez.
##
## Kullanım: sabit metin L.t("Kapat"); biçimli cümlede ŞABLON çevrilir:
## L.t("%s milyon ¤") % tutar  (İngilizce şablon "¤%s million" olabilir).
## Sayılar: L.pct(12.3) → "%12,3" / "12.3%", L.dec(2.5) → "2,5" / "2.5",
## L.thousands(1240) → "1.240" / "1,240". Parti, siyasetçi ve il adları
## çevrilmez (özel ad).

const LOCALES := ["tr", "en"]
const LOCALE_NAMES := {"tr": "Türkçe", "en": "English"}

static func t(text: String) -> String:
	return String(TranslationServer.translate(text))

static func is_en() -> bool:
	return TranslationServer.get_locale().begins_with("en")

## Sabit veri sözlüğünün (grup, gündem, makam ...) metin değerlerini çevirir.
## Kimlik değerleri ("isci" gibi) çeviri dosyasında olmadığı için aynen kalır.
static func tr_dict(data: Dictionary) -> Dictionary:
	if not is_en():
		return data
	var out := {}
	for key in data.keys():
		var value: Variant = data[key]
		if value is String:
			out[key] = t(value)
		elif value is Array:
			var arr: Array = []
			for item in value:
				arr.append(t(item) if item is String else item)
			out[key] = arr
		else:
			out[key] = value
	return out

## Ondalık sayı (digits basamak; tam sayıysa ondalık basılmaz).
static func dec(value: float, digits: int = 1) -> String:
	var text := String.num(snappedf(value, pow(10.0, -digits)), digits) if not is_equal_approx(value, roundf(value)) \
		else str(int(roundf(value)))
	return text if is_en() else text.replace(".", ",")

## Yüzde: Türkçede işaret önde ("%12,3"), İngilizcede sonda ("12.3%").
static func pct(value: float, digits: int = 1) -> String:
	var text := String.num(value, digits)
	if digits == 0:
		text = str(int(roundf(value)))
	return (text + "%") if is_en() else ("%" + text.replace(".", ","))

## Binlik ayraçlı tam sayı: TR "1.240", EN "1,240".
static func thousands(value: float) -> String:
	var negative := value < 0.0
	var digits := str(int(round(absf(value))))
	var sep := "," if is_en() else "."
	var out := ""
	while digits.length() > 3:
		out = sep + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("−" if negative else "") + digits + out
