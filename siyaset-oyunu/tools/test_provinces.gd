class_name TestProvinces
extends RefCounted
## Testler ve önizlemeler için: eski Türkiye il adlarını (ör. "ankara") altıgen
## haritanın bölgelerine eşler. Eşleme vekil sayısına göre sabittir: en çok
## vekilli bölge "istanbul", ikincisi "ankara"... Harita değişirse eşleme de
## yeni haritaya göre yeniden kurulur.

const LEGACY_ORDER := ["istanbul", "ankara", "izmir", "konya", "bursa", "antalya", "adana", "sivas",
	"samsun", "trabzon", "van", "erzurum", "kayseri", "mersin", "diyarbakir", "gaziantep"]

static func id(legacy_name: String) -> String:
	var map = Engine.get_main_loop().root.get_node("GameMap")
	var ids: Array = map.province_ids()
	ids.sort_custom(func(a, b):
		var sa: int = map.seats_of(a)
		var sb: int = map.seats_of(b)
		return sa > sb or (sa == sb and String(a) < String(b)))
	var k := LEGACY_ORDER.find(legacy_name)
	if k == -1:
		k = absi(legacy_name.hash()) % ids.size()
	return String(ids[k % ids.size()])
