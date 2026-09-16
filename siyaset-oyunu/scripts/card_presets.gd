extends Node
## Autoload. Kart ve hamle katalogu. Görseller normal PNG'ler (assets/cards/).
##
## DESTE KARTLARI (çekmek GameRules.DRAW_MANA_COST; oynamanın bedeli CARD_MANA_COSTS).
## GÖZCÜ ve MİTİNG artık kart değil hamle (bkz. CardManager.scout / miting);
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
const STEAL_CARD_TYPES: Array[String] = [
	"steal_weak",
	"steal_medium",
	"steal_strong",
]

## Hükümeti düşürmek için meclise getirilen teklif.
const CENSURE_CARD_TYPE := "gensoru"
const MITING_CARD_TYPE := "miting"
const INVEST_CARD_TYPE := "yatirim"
const POLL_CARD_TYPE := "anket"
const SCOUT_CARD_TYPE := "gozcu"
const PROPAGANDA_CARD_TYPE := "karalama"

const CARD_TYPES: Array[String] = [
	"steal_weak",
	"steal_medium",
	"steal_strong",
	"gensoru",
	"miting",
	"yatirim",
	"anket",
	"gozcu",
	"karalama",
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
	"steal_weak": {"min": 1, "max": 4},
	"steal_medium": {"min": 5, "max": 8},
	"steal_strong": {"min": 9, "max": 12},
}

## Kartın elden oynanma bedeli (mana). Değerler henüz belirlenmedi: hepsi 0.
const CARD_MANA_COSTS := {
	"yatirim": 0,
	"anket": 0,
	"karalama": 2,
	"steal_weak": 2,
	"steal_medium": 3,
	"steal_strong": 4,
	"gensoru": 0,
}

var _card_textures: Dictionary = {}
var _closed_texture: Texture2D

func _ready() -> void:
	for card_type in CARD_TYPES:
		var path := "res://assets/cards/politic_card_%s.png" % card_type
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

## Bu kart oynanırken haritadan İL seçilmesi gerekiyor mu? (Karalamada ilden
## sonra hedef parti de seçilir.)
func needs_province_target(card_type: String) -> bool:
	return card_type in [MITING_CARD_TYPE, INVEST_CARD_TYPE, POLL_CARD_TYPE, SCOUT_CARD_TYPE, PROPAGANDA_CARD_TYPE]

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
		"steal_weak":
			return "VEKİL ÇALMA\nZAYIF"
		"steal_medium":
			return "VEKİL ÇALMA\nORTA"
		"steal_strong":
			return "VEKİL ÇALMA\nGÜÇLÜ"
	return card_title(card_type).to_upper()

func card_title(card_type: String) -> String:
	if is_law_card(card_type):
		return String(law_data(card_type)["title"])
	match card_type:
		"steal_weak":
			return "Vekil Çalma (Zayıf)"
		"steal_medium":
			return "Vekil Çalma (Orta)"
		"steal_strong":
			return "Vekil Çalma (Güçlü)"
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
		return "Seçtiğin partiden %d-%d vekil çal.\nSağdaki bir parti kartına sürükle." % [int(r["min"]), int(r["max"])]
	match card_type:
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
	return ""
