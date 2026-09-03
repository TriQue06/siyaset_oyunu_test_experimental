extends Node
## Autoload. Siyasi kart katalogu. Görseller normal PNG'ler (assets/cards/),
## Godot'un kendi import sistemi export'a otomatik dahil eder.
##
## Kartlar iki gruba ayrılır:
##   - İDEOLOJİ kartları: partinin eksenini ±1 kaydırır. Her zaman destededir.
##   - ÖZEL kartlar: hedef seçmek (vekil çalma) ya da meclise teklif getirmek
##     (gensoru) gibi ek etkileri vardır ve ancak KOŞULLARI oluşunca desteye
##     girerler (bkz. CardManager._draw_pool).

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
]

const CARD_NATIVE_SIZE := Vector2(72, 96)

## Her kart oynanınca ilgili partinin ideoloji eksenini bu yönde 1 birim
## kaydırır (bkz. ideology_axes.gd: economic -3 statist/collectivist <-> +3
## market/capitalist; social -3 progressive <-> +3 conservative;
## administrative -3 federal <-> +3 unitary).
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
	return _card_textures.get(card_type)

func get_closed_texture() -> Texture2D:
	return _closed_texture

func is_ideology_card(card_type: String) -> bool:
	return CARD_EFFECTS.has(card_type)

## Bu kart oynanırken hedef parti seçilmesi gerekiyor mu?
func needs_target(card_type: String) -> bool:
	return STEAL_CARD_TYPES.has(card_type)

func is_censure_card(card_type: String) -> bool:
	return card_type == CENSURE_CARD_TYPE

func random_from(pool: Array) -> String:
	if pool.is_empty():
		return IDEOLOGY_CARD_TYPES[randi_range(0, IDEOLOGY_CARD_TYPES.size() - 1)]
	return pool[randi_range(0, pool.size() - 1)]

func card_title(card_type: String) -> String:
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
		_:
			return card_type
