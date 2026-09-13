extends Node
## Autoload. Siyasi kart katalogu. Görseller normal PNG'ler (assets/cards/),
## Godot'un kendi import sistemi export'a otomatik dahil eder.
##
## Kart grupları:
##   - İDEOLOJİ : kartı oynayan partinin kendi eksenini ±1 kaydırır.
##   - MİTİNG   : seçilen ilde kamuoyu kazandırır; provokasyon riski var.
##   - YASA     : meclise bir yasa teklifi getirir (ekseni ve yönü var).
##   - YATIRIM  : sadece hükümet partilerine gelir; seçilen ile yatırım.
##   - VEKİL ÇALMA / GENSORU : koşullu özel kartlar.
## Hangi kartın ne olasılıkla çekileceği CardManager._draw_weights'te.

const IDEOLOGY_CARD_TYPES: Array[String] = [
	"capitalist",
	"conservative",
	"federal",
	"progressive",
	"socialist",
	"unitary",
]

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

## Yasa kartları: eksen, yön (+1: eksenin + ucu, -1: - ucu), başlık, açıklama.
## ideology_axes.gd: economic -3 devletçi <-> +3 piyasacı; social -3 ilerici
## <-> +3 muhafazakâr; administrative -3 federal <-> +3 üniter.
const LAWS := {
	"law_privatization": {"axis": "economic", "dir": 1, "title": "Özelleştirme Yasası",
		"desc": "Kamu işletmelerini özelleştirir."},
	"law_nationalization": {"axis": "economic", "dir": -1, "title": "Kamulaştırma Yasası",
		"desc": "Stratejik sektörleri devletleştirir."},
	"law_family": {"axis": "social", "dir": 1, "title": "Aileyi Koruma Yasası",
		"desc": "Geleneksel aile yapısını destekler."},
	"law_civil_rights": {"axis": "social", "dir": -1, "title": "Sivil Haklar Yasası",
		"desc": "Bireysel hak ve özgürlükleri genişletir."},
	"law_centralization": {"axis": "administrative", "dir": 1, "title": "Merkezi Yönetim Yasası",
		"desc": "Yetkileri merkezi hükümette toplar."},
	"law_local_government": {"axis": "administrative", "dir": -1, "title": "Yerel Yönetimler Yasası",
		"desc": "Yetkileri il ve belediyelere devreder."},
}

const LAW_CARD_TYPES: Array[String] = [
	"law_privatization",
	"law_nationalization",
	"law_family",
	"law_civil_rights",
	"law_centralization",
	"law_local_government",
]

const CARD_TYPES: Array[String] = [
	"capitalist",
	"conservative",
	"federal",
	"progressive",
	"socialist",
	"unitary",
	"steal_weak",
	"steal_medium",
	"steal_strong",
	"gensoru",
	"miting",
	"yatirim",
	"law_privatization",
	"law_nationalization",
	"law_family",
	"law_civil_rights",
	"law_centralization",
	"law_local_government",
]

const AXIS_TITLES := {
	"economic": {"title": "Ekonomi", "neg": "Devletçi", "pos": "Piyasacı"},
	"social": {"title": "Toplum", "neg": "İlerici", "pos": "Muhafazakâr"},
	"administrative": {"title": "İdare", "neg": "Federal", "pos": "Üniter"},
}

const CARD_NATIVE_SIZE := Vector2(72, 96)

## Her kart oynanınca ilgili partinin ideoloji eksenini bu yönde 1 birim kaydırır.
const CARD_EFFECTS := {
	"capitalist": {"axis": "economic", "delta": 1},
	"socialist": {"axis": "economic", "delta": -1},
	"conservative": {"axis": "social", "delta": 1},
	"progressive": {"axis": "social", "delta": -1},
	"unitary": {"axis": "administrative", "delta": 1},
	"federal": {"axis": "administrative", "delta": -1},
}

## Vekil çalma kartlarının çaldığı milletvekili aralığı (her değer eşit olası).
const STEAL_RANGES := {
	"steal_weak": {"min": 1, "max": 4},
	"steal_medium": {"min": 5, "max": 8},
	"steal_strong": {"min": 9, "max": 12},
}

## Görseli yazısıyla birlikte çizilmiş kartlar. Diğerlerinin (placeholder
## görselli yeni kartlar) adı oyunda kartın üstüne yazılır.
const BAKED_TITLE_TYPES: Array[String] = [
	"capitalist", "conservative", "federal", "progressive", "socialist", "unitary",
	"steal_weak", "steal_medium", "steal_strong", "gensoru",
]

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
	return _card_textures.get(card_type, _card_textures.get(CENSURE_CARD_TYPE))

func get_closed_texture() -> Texture2D:
	return _closed_texture

func is_ideology_card(card_type: String) -> bool:
	return CARD_EFFECTS.has(card_type)

## Bu kart oynanırken hedef PARTİ seçilmesi gerekiyor mu?
func needs_target(card_type: String) -> bool:
	return STEAL_CARD_TYPES.has(card_type)

## Bu kart oynanırken haritadan İL seçilmesi gerekiyor mu?
func needs_province_target(card_type: String) -> bool:
	return card_type == MITING_CARD_TYPE or card_type == INVEST_CARD_TYPE

func is_censure_card(card_type: String) -> bool:
	return card_type == CENSURE_CARD_TYPE

func is_law_card(card_type: String) -> bool:
	return LAWS.has(card_type)

func has_baked_title(card_type: String) -> bool:
	return BAKED_TITLE_TYPES.has(card_type)

func random_from(pool: Array) -> String:
	if pool.is_empty():
		return IDEOLOGY_CARD_TYPES[randi_range(0, IDEOLOGY_CARD_TYPES.size() - 1)]
	return pool[randi_range(0, pool.size() - 1)]

## weights: card_type -> ağırlık (>0). Ağırlıkla orantılı rastgele seçim.
func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for card_type in weights.keys():
		total += maxf(0.0, float(weights[card_type]))
	if total <= 0.0:
		return random_from([])
	var roll := rng.randf() * total
	for card_type in weights.keys():
		roll -= maxf(0.0, float(weights[card_type]))
		if roll <= 0.0:
			return card_type
	return weights.keys().back()

## Kartın üstüne basılacak kısa başlık (placeholder görselli kartlar için).
func card_short_title(card_type: String) -> String:
	if is_law_card(card_type):
		return "YASA\n" + String(LAWS[card_type]["title"]).replace(" Yasası", "")
	match card_type:
		MITING_CARD_TYPE:
			return "MİTİNG"
		INVEST_CARD_TYPE:
			return "YATIRIM"
	return card_title(card_type).to_upper()

func card_title(card_type: String) -> String:
	if is_law_card(card_type):
		return LAWS[card_type]["title"]
	match card_type:
		"capitalist":
			return "Kapitalist"
		"conservative":
			return "Muhafazakar"
		"federal":
			return "Federal"
		"progressive":
			return "İlerici"
		"socialist":
			return "Sosyalist"
		"unitary":
			return "Üniter"
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
		_:
			return card_type

## Yasanın yönünü okunur yazar: "Ekonomi → Piyasacı".
func law_direction_text(card_type: String) -> String:
	var law: Dictionary = LAWS.get(card_type, {})
	if law.is_empty():
		return ""
	var info: Dictionary = AXIS_TITLES[law["axis"]]
	return "%s → %s" % [info["title"], info["pos"] if int(law["dir"]) > 0 else info["neg"]]

## Kart üstüne gelince gösterilen açıklama.
func card_description(card_type: String) -> String:
	if is_law_card(card_type):
		var law: Dictionary = LAWS[card_type]
		return "%s (%s)\nMeclise getirilir, herkes oylar. Geçerse getiren parti kamuoyu kazanır — muhalefetten geliyorsa çok daha fazla. Tabanına ters oy veren kamuoyu kaybeder." % [
			law["desc"], law_direction_text(card_type)]
	if is_ideology_card(card_type):
		var effect: Dictionary = CARD_EFFECTS[card_type]
		var info: Dictionary = AXIS_TITLES[effect["axis"]]
		return "%s eksenini 1 birim %s yönüne kaydırır.\nTıkla: partinin ekseni kayar (sadece kendi partine oynanır)." % [
			info["title"], info["pos"] if int(effect["delta"]) > 0 else info["neg"]]
	if needs_target(card_type):
		var r: Dictionary = STEAL_RANGES[card_type]
		return "Seçtiğin partiden %d-%d milletvekili çalar (hedef en az 1 vekille kalır).\nSağdaki bir partinin logosuna sürükle." % [int(r["min"]), int(r["max"])]
	match card_type:
		CENSURE_CARD_TYPE:
			return "Hükümeti düşürmek için meclise gensoru önergesi verir. Azınlık hükümeti varken desteye girer.
Parlamento diyagramına sürükle."
		MITING_CARD_TYPE:
			return "Seçtiğin ilde miting: il kamuoyun +%.1f, ulusal +%.1f.\nİlin siyasi dengesine uzaksan PROVOKASYON riski artar (en fazla %%%d): il %.1f, ulusal %.1f.\nHaritada bir ilin üstüne sürükle." % [
				PublicOpinion.MITING_LOCAL, PublicOpinion.MITING_NATIONAL, int(PublicOpinion.PROVOCATION_MAX_RISK * 100),
				PublicOpinion.PROVOCATION_LOCAL, PublicOpinion.PROVOCATION_NATIONAL]
		INVEST_CARD_TYPE:
			return "Sadece hükümet partileri. Seçtiğin ile yatırım: sana il +%.1f ve ulusal +%.1f, hükümet ortaklarına il +%.1f. Herkes görür.\nHaritada bir ilin üstüne sürükle." % [
				PublicOpinion.INVEST_LOCAL, PublicOpinion.INVEST_NATIONAL, PublicOpinion.INVEST_PARTNER_LOCAL]
	return ""
