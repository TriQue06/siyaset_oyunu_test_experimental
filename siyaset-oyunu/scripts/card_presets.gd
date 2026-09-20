extends Node
## Autoload. Kart ve hamle katalogu. Görseller normal PNG'ler (assets/cards/).
##
## KARTLAR: sırası gelen oyuncuya oyun bir kart verir; oynamanın bedeli CARD_MANA_COSTS.
## YATIRIM ve GENSORU da artık hamle (bkz. CardManager.invest / censure).
##   - POPÜLİZM BONUSU : POPULISM_ROUNDS tur kendi hamlelerinin iyi etkisi artar, kötüsü azalır.
##   - MANA BONUSU     : +MANA_BONUS_AMOUNT mana; kullanınca sıra devreder.
## GÖZCÜ (artık teşkilatın parçası) ve MİTİNG kart değil (bkz. CardManager);
## ANKET kaldırıldı (gözcü raporu anlık vekil tahmini gösterir). Türleri eski
## kayıtlar/görseller için duruyor, desteye girmez.
##   - MİTİNG    : seçilen ilde güç kazandırır; provokasyon riski var.
##   - YATIRIM   : sadece hükümet partilerine gelir; seçilen ile yatırım.
##   - ANKET     : bir ilin güncel oy tahmini (±%20 hata); sonucu sadece oynayan görür.
##   - KARALAMA  : bir ilde bir partiyi karalar: ona eksi, oynayana artı.
##   - VEKİL ÇALMA / GENSORU : koşullu özel kartlar.
## YASA bir kart DEĞİL, bir hamle türüdür (bkz. CardManager.propose_law): eksen
## ve yön seçilir. Meclis akışı metin tabanlı olduğu için yasa "law:eksen:yön"
## biçiminde bir metinle taşınır (bkz. law_type / law_data).
## Hangi kartın ne olasılıkla çekileceği CardManager._draw_weights'te.

## Bir başka partiden milletvekili çalar. Kullanılırken HEDEF parti seçilir.
const STEAL_WEAK_CARD_TYPE := "steal_weak"
const STEAL_STRONG_CARD_TYPE := "steal_strong"
const STEAL_CARD_TYPES: Array[String] = [
	STEAL_WEAK_CARD_TYPE,
	STEAL_STRONG_CARD_TYPE,
]

## Hedef PARTİ seçilen diğer saldırı kartları.
## Kaset: hedefin ulusal desteğini doğrudan düşürür.
## Parti içi isyan: hedef, sıradaki İLK yasa oylamasında çekimser kalmak zorunda.
const REPUTATION_CARD_TYPE := "kaset"
const REBELLION_CARD_TYPE := "isyan"

## Hükümeti düşürmek için meclise getirilen teklif.
const CENSURE_CARD_TYPE := "gensoru"
const MITING_CARD_TYPE := "miting"
const INVEST_CARD_TYPE := "yatirim"
const POLL_CARD_TYPE := "anket"
const SCOUT_CARD_TYPE := "gozcu"
const PROPAGANDA_CARD_TYPE := "karalama"
## Hedefsiz bonus kartlar: seçip tekrar dokununca (ya da yukarı sürükleyince) oynanır.
const POPULISM_CARD_TYPE := "populizm"
const MANA_BONUS_CARD_TYPE := "mana_bonusu"

## GÜNDEMLER: her eksenin her ucu için bir sıcak konu (bkz. GameRules gündem
## takvimi). Artık kart değil; oyun takvime göre kendisi seçer.
const AGENDAS := {
	"gundem_economic_n": {"axis": "economic", "dir": -1, "title": "Hayat Pahalılığı",
		"text": "Fiyatlar uçtu, seçmen devletten koruma bekliyor."},
	"gundem_economic_p": {"axis": "economic", "dir": 1, "title": "Vergi ve Bürokrasi Yükü",
		"text": "Esnaf ve sanayici vergi ve kırtasiyeden bunaldı."},
	"gundem_social_n": {"axis": "social", "dir": -1, "title": "Özgürlükler Tartışması",
		"text": "İfade ve yaşam tarzı özgürlüğü ülkenin gündeminde."},
	"gundem_social_p": {"axis": "social", "dir": 1, "title": "Aile ve Değerler",
		"text": "Aile ve gelenekler ülkenin en çok konuşulan konusu."},
	"gundem_administrative_n": {"axis": "administrative", "dir": -1, "title": "Yerelden Yönetim Talebi",
		"text": "Şehirler kendi kararlarını kendileri vermek istiyor."},
	"gundem_administrative_p": {"axis": "administrative", "dir": 1, "title": "Güvenlik ve Birlik",
		"text": "Güvenlik kaygısı güçlü bir merkez talebini büyüttü."},
}

const CARD_TYPES: Array[String] = [
	"steal_weak",
	"steal_strong",
	"kaset",
	"isyan",
	"gensoru",
	"miting",
	"yatirim",
	"anket",
	"gozcu",
	"karalama",
	"populizm",
	"mana_bonusu",
]

const AXIS_TITLES := {
	"economic": {"title": "Ekonomi", "neg": "Devletçi", "pos": "Piyasacı"},
	"social": {"title": "Toplum", "neg": "İlerici", "pos": "Muhafazakâr"},
	"administrative": {"title": "İdare", "neg": "Federal", "pos": "Üniter"},
}

## Yasa hamlesinin 6 seçeneği: eksen -> yön -> başlık.
const LAW_TITLES := {
	"economic": {-1: "Kamu Ekonomisi Yasası", 1: "Serbest Piyasa Yasası"},
	"social": {-1: "Özgürlükler Yasası", 1: "Aile ve Gelenek Yasası"},
	"administrative": {-1: "Yerel Yönetim Yasası", 1: "Güçlü Merkez Yasası"},
}
const LAW_PREFIX := "law:"

const CARD_NATIVE_SIZE := Vector2(72, 96)

## Vekil çalma kartlarının çaldığı milletvekili aralığı (her değer eşit olası).
const STEAL_RANGES := {
	"steal_weak": {"min": 2, "max": 4},
	"steal_strong": {"min": 10, "max": 16},
}

## İdeolojik yakınlığa göre aralık: yukarıdaki STEAL_RANGES NÖTR hâl (orta
## yakınlık); ideolojiler birebir aynıysa STEAL_RANGES_CLOSE (2 kat), iki parti
## zıt radikal uçlardaysa STEAL_RANGES_FAR. Arası doğrusal (bkz. steal_range).
const STEAL_RANGES_CLOSE := {
	"steal_weak": {"min": 4, "max": 8},
	"steal_strong": {"min": 20, "max": 32},
}
const STEAL_RANGES_FAR := {
	"steal_weak": {"min": 1, "max": 2},
	"steal_strong": {"min": 6, "max": 9},
}

## closeness: 0 (en uzak) .. 0.5 (nötr) .. 1 (aynı ideoloji) -> {"min", "max"}.
func steal_range(card_type: String, closeness: float) -> Dictionary:
	var mid: Dictionary = STEAL_RANGES.get(card_type, {})
	if mid.is_empty():
		return {}
	var other: Dictionary = STEAL_RANGES_CLOSE[card_type] if closeness >= 0.5 else STEAL_RANGES_FAR[card_type]
	var t: float = absf(closeness - 0.5) * 2.0
	return {"min": int(round(lerpf(float(mid["min"]), float(other["min"]), t))),
		"max": int(round(lerpf(float(mid["max"]), float(other["max"]), t)))}

## Kartın elden oynanma bedeli (mana).
const CARD_MANA_COSTS := {
	"karalama": 1,
	"populizm": 1,
	"mana_bonusu": 0,
	"gundem_economic_n": 1,
	"gundem_economic_p": 1,
	"gundem_social_n": 1,
	"gundem_social_p": 1,
	"gundem_administrative_n": 1,
	"gundem_administrative_p": 1,
	"steal_weak": 1,
	"steal_strong": 3,
	"kaset": 2,
	"isyan": 1,
}

## Kendi görseli olmayan kartlar geçici olarak başka bir kartın görselini kullanır.
const CARD_ART_ALIAS := {
	"kaset": "steal_medium",
	"isyan": "gensoru",
}

var _card_textures: Dictionary = {}
var _closed_texture: Texture2D

func _ready() -> void:
	for card_type in CARD_TYPES:
		var path := "res://assets/cards/politic_card_%s.png" % String(CARD_ART_ALIAS.get(card_type, card_type))
		if ResourceLoader.exists(path):
			_card_textures[card_type] = load(path)
		else:
			push_warning("Kart görseli bulunamadı: %s" % path)
	_closed_texture = load("res://assets/cards/closed_cards.png")

func get_card_texture(card_type: String) -> Texture2D:
	return _card_textures.get(card_type, _card_textures.get(MITING_CARD_TYPE))

func get_closed_texture() -> Texture2D:
	return _closed_texture

## Bu kart oynanırken hedef PARTİ seçilmesi gerekiyor mu? (vekil çalma)
func needs_target(card_type: String) -> bool:
	return STEAL_CARD_TYPES.has(card_type)

## Hedef parti seçilen TÜM kartlar: vekil çalma + kaset + parti içi isyan.
func needs_party_target(card_type: String) -> bool:
	return needs_target(card_type) or card_type in [REPUTATION_CARD_TYPE, REBELLION_CARD_TYPE]

## Bu kart oynanırken haritadan İL seçilmesi gerekiyor mu? (Karalamada ilden
## sonra hedef parti de seçilir.)
func needs_province_target(card_type: String) -> bool:
	return card_type in [MITING_CARD_TYPE, INVEST_CARD_TYPE, POLL_CARD_TYPE, SCOUT_CARD_TYPE, PROPAGANDA_CARD_TYPE]

## Hedef gerektirmeyen bonus kart mı? (popülizm, mana bonusu)
func is_self_card(card_type: String) -> bool:
	return card_type in [POPULISM_CARD_TYPE, MANA_BONUS_CARD_TYPE] or is_agenda_card(card_type)

func is_agenda_card(card_type: String) -> bool:
	return AGENDAS.has(card_type)

## {"axis", "dir", "title", "text", "side"} ya da boş sözlük.
func agenda_data(card_type: String) -> Dictionary:
	if not AGENDAS.has(card_type):
		return {}
	var data: Dictionary = AGENDAS[card_type].duplicate()
	var info: Dictionary = AXIS_TITLES[data["axis"]]
	data["side"] = info["pos"] if int(data["dir"]) > 0 else info["neg"]
	data["axis_title"] = info["title"]
	return data

## Gündemin yasalar üzerindeki etkisini anlatan kısa metin.
func agenda_effect_text(card_type: String) -> String:
	var data := agenda_data(card_type)
	if data.is_empty():
		return ""
	return "sadece %s ekseninde yasa sunulabilir (%s ya da %s)" % [data["axis_title"], data["side"],
		String(AXIS_TITLES[data["axis"]]["pos" if int(data["dir"]) < 0 else "neg"])]

func is_censure_card(card_type: String) -> bool:
	return card_type == CENSURE_CARD_TYPE

## Yasa hamlesinin türü: "law:economic:1".
func law_type(axis: String, dir: int) -> String:
	return "%s%s:%d" % [LAW_PREFIX, axis, 1 if dir > 0 else -1]

func is_law_card(card_type: String) -> bool:
	return not law_data(card_type).is_empty()

## {"axis", "dir", "title", "side"} ya da (yasa değilse) boş sözlük.
func law_data(card_type: String) -> Dictionary:
	if not card_type.begins_with(LAW_PREFIX):
		return {}
	var parts := card_type.substr(LAW_PREFIX.length()).split(":")
	if parts.size() != 2 or not LAW_TITLES.has(parts[0]):
		return {}
	var axis: String = parts[0]
	var dir := 1 if int(parts[1]) > 0 else -1
	var info: Dictionary = AXIS_TITLES[axis]
	return {"axis": axis, "dir": dir, "title": LAW_TITLES[axis][dir], "side": info["pos"] if dir > 0 else info["neg"]}

func card_cost(card_type: String) -> int:
	return int(CARD_MANA_COSTS.get(card_type, 0))

## weights: card_type -> ağırlık (>0). Ağırlıkla orantılı rastgele seçim.
func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for card_type in weights.keys():
		total += maxf(0.0, float(weights[card_type]))
	if total <= 0.0:
		return MITING_CARD_TYPE
	var roll := rng.randf() * total
	for card_type in weights.keys():
		roll -= maxf(0.0, float(weights[card_type]))
		if roll <= 0.0:
			return card_type
	return weights.keys().back()

## Kartın görselinin üstüne yazılan kısa başlık (her kartta).
func card_short_title(card_type: String) -> String:
	match card_type:
		"populizm":
			return "POPÜLİZM\nBONUSU"
		"mana_bonusu":
			return "MANA\nBONUSU"
		"steal_weak":
			return "VEKİL ÇALMA\nZAYIF"
		"steal_medium":
			return "VEKİL ÇALMA\nORTA"
		"steal_strong":
			return "VEKİL ÇALMA\nGÜÇLÜ"
	if is_agenda_card(card_type):
		return "GÜNDEM\n" + String(agenda_data(card_type)["title"]).to_upper()
	return card_title(card_type).to_upper()

func card_title(card_type: String) -> String:
	if is_law_card(card_type):
		return String(law_data(card_type)["title"])
	if is_agenda_card(card_type):
		return "Gündem: " + String(agenda_data(card_type)["title"])
	match card_type:
		"steal_weak":
			return "Vekil Çalma"
		"steal_strong":
			return "Vekil Çalma (Güçlü)"
		"kaset":
			return "Kaset / İtibar Suikastı"
		"isyan":
			return "Parti İçi İsyan"
		"gensoru":
			return "Gensoru"
		"miting":
			return "Miting"
		"yatirim":
			return "Yatırım"
		"anket":
			return "Anket"
		"gozcu":
			return "Gözcü"
		"karalama":
			return "Karalama"
		"populizm":
			return "Popülizm Bonusu"
		"mana_bonusu":
			return "Mana Bonusu"
	return card_type

## Yasanın yönünü okunur yazar: "Ekonomi → Piyasacı".
func law_direction_text(card_type: String) -> String:
	var law := law_data(card_type)
	if law.is_empty():
		return ""
	return "%s → %s" % [AXIS_TITLES[law["axis"]]["title"], law["side"]]

## Gözcü bilgisi: "Ekonomi: Devletçi" / "Ekonomi: Orta".
func leaning_text(axis: String, value: int) -> String:
	var info: Dictionary = AXIS_TITLES.get(axis, {"title": axis, "neg": "-", "pos": "+"})
	var side: String = "Orta"
	if value < 0:
		side = info["neg"]
	elif value > 0:
		side = info["pos"]
	return "%s: %s" % [info["title"], side]

## Yasa dairesinin üstüne gelince gösterilen kısa açıklama.
func law_description(card_type: String) -> String:
	var law := law_data(card_type)
	if law.is_empty():
		return ""
	return "Bu görüşe yakın illerde güç kazanırsın, zıt illerde kaybedersin.\nKabul edilirse etkisi 2 katı. Partin %s yönüne 1 adım kayar;
EVET diyenler bu yöne, HAYIR diyenler ters yöne yarım adım kayar." % law["side"]

## Karta dokununca gösterilen açıklama (kısa ve somut) + mana bedeli.
func card_description(card_type: String) -> String:
	var text := _card_effect_text(card_type)
	var cost := card_cost(card_type)
	if cost > 0 and not is_law_card(card_type):
		text += "\nBedel: %d mana" % cost
	return text

func _card_effect_text(card_type: String) -> String:
	if is_law_card(card_type):
		return law_description(card_type)
	if needs_target(card_type):
		var r: Dictionary = STEAL_RANGES[card_type]
		var close: Dictionary = STEAL_RANGES_CLOSE[card_type]
		var far: Dictionary = STEAL_RANGES_FAR[card_type]
		return "Seçtiğin partiden vekil çal: %d-%d; görüşü sana yakınsa %d-%d'e kadar, zıt uçtaysa %d-%d.\nMeşru görünmez: ulusal desteğin biraz düşer, çalınan partininki artar.\nSağdaki bir parti kartına sürükle." % [
			int(r["min"]), int(r["max"]), int(close["min"]), int(close["max"]), int(far["min"]), int(far["max"])]
	if is_agenda_card(card_type):
		var agenda := agenda_data(card_type)
		return "%s\n%d dönem boyunca gündem bu: %s.\nDokun, tekrar dokun: kullan." % [agenda["text"], GameRules.AGENDA_ROUNDS,
			agenda_effect_text(card_type)]
	match card_type:
		REPUTATION_CARD_TYPE:
			return ("Seçtiğin partinin itibarını sarsan bir kaset sızar:" + "\n"
				+ "ulusal desteği %.1f puan düşer." + "\n"
				+ "Sağdaki bir parti kartına sürükle.") % PublicOpinion.REPUTATION_NATIONAL_DAMAGE
		REBELLION_CARD_TYPE:
			return ("Seçtiğin partide isyan çıkar: sıradaki İLK yasa" + "\n"
				+ "oylamasında çekimser kalmak zorunda kalır." + "\n"
				+ "Sağdaki bir parti kartına sürükle.")
		CENSURE_CARD_TYPE:
			return "Hükümeti düşürmek için gensoru ver.\nMeclis diyagramına sürükle."
		MITING_CARD_TYPE:
			return "Seçtiğin ilde güç kazan (+%.0f).\nİl sana uzaksa provokasyon riski var." % PublicOpinion.MITING_LOCAL
		INVEST_CARD_TYPE:
			return "Hükümet: seçtiğin ile yatırım.\nSen +%.0f, ortakların +%.1f güç kazanır." % [PublicOpinion.INVEST_LOCAL, PublicOpinion.INVEST_PARTNER_LOCAL]
		POLL_CARD_TYPE:
			return "Anket artık gözcü raporunun parçası."
		SCOUT_CARD_TYPE:
			return "Bir ilin görüşünü öğren: her eksende hangi uçta.\nSadece sen görürsün, kalıcıdır."
		PROPAGANDA_CARD_TYPE:
			return "Bir ilde bir partiyi karala: ona eksi, sana artı.\nİlde güçlü olan partiye az işler."
		POPULISM_CARD_TYPE:
			return "%d dönem boyunca her şey güçlenir: miting, yasa, karalama\nhasarı ve teşkilat bonusu %d kat, vekil çalma %.1f kat; kötü sonuçlar\n%%%d azalır; bu sürede seçim olursa ulusal +%.1f. Dokun, tekrar dokun: kullan." % [
				GameRules.POPULISM_ROUNDS, int(PublicOpinion.POPULISM_GOOD_MULT), PublicOpinion.POPULISM_STEAL_MULT,
				int(round((1.0 - PublicOpinion.POPULISM_BAD_MULT) * 100)), PublicOpinion.POPULISM_ELECTION_NATIONAL]
		MANA_BONUS_CARD_TYPE:
			return "+%d mana kazan.\nSeçmek için dokun, tekrar dokun: kullan." % GameRules.MANA_BONUS_AMOUNT
	return ""
