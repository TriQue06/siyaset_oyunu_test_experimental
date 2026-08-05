extends Node
## Autoload. Siyasi kart katalogu: 6 kart tipi + kapalı (destesindeki) kart
## görseli. Bunlar normal PNG'ler (ham SVG gibi çalışma zamanı rasterize
## gerektirmiyor), Godot'un kendi import sistemi export'a otomatik dahil
## eder.

const CARD_TYPES: Array[String] = [
	"capitalist",
	"conservative",
	"federal",
	"progressive",
	"socialist",
	"unitary",
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

var _card_textures: Dictionary = {}
var _closed_texture: Texture2D

func _ready() -> void:
	for card_type in CARD_TYPES:
		var path := "res://assets/cards/politic_card_%s.png" % card_type
		_card_textures[card_type] = load(path)
	_closed_texture = load("res://assets/cards/closed_cards.png")

func get_card_texture(card_type: String) -> Texture2D:
	return _card_textures.get(card_type)

func get_closed_texture() -> Texture2D:
	return _closed_texture

func random_card_type() -> String:
	return CARD_TYPES[randi_range(0, CARD_TYPES.size() - 1)]

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
		_:
			return card_type
