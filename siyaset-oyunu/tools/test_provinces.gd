class_name TestProvinces
extends RefCounted
## Testlerdeki sabit takma adları, üretilen ülkenin illerine vekil sırasıyla eşler.

const FIXTURE_ORDER := ["istanbul", "ankara", "izmir", "konya", "bursa", "antalya", "adana", "sivas",
	"samsun", "trabzon", "van", "erzurum", "kayseri", "mersin", "diyarbakir", "gaziantep"]

static func id(fixture_name: String) -> String:
	var map = Engine.get_main_loop().root.get_node("GameMap")
	var ids: Array = map.province_ids()
	ids.sort_custom(func(a, b):
		var sa: int = map.seats_of(a)
		var sb: int = map.seats_of(b)
		return sa > sb or (sa == sb and String(a) < String(b)))
	var k := FIXTURE_ORDER.find(fixture_name)
	if k == -1:
		k = absi(fixture_name.hash()) % ids.size()
	return String(ids[k % ids.size()])
