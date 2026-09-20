extends SceneTree
## Görseli henüz çizilmemiş kartlar için PLACEHOLDER kart PNG'leri üretir:
## politic_card_gensoru.png'in çerçevesi alınır; kırmızı başlık ve iç çerçeve
## kategori rengine boyanır, gövdedeki ok simgesi silinir. Kart adı oyunda
## kartın üstüne yazıyla basılır (bkz. CardPresets.has_baked_title). Gerçek
## çizimler hazır olunca aynı adla dosyanın üstüne yazmak yeterli.
##   godot --headless --script res://tools/make_card_art.gd

const BASE := "res://assets/cards/politic_card_gensoru.png"
const OUT_DIR := "res://assets/cards/"
## Gövde bölgesi (başlık bandının altı, iç çerçevenin içi).
const BODY_RECT := Rect2i(4, 33, 64, 59)
const CARDS := {
	"miting": Color("E8702A"),
	"yatirim": Color("3FA34D"),
	"anket": Color("2F7FD1"),
	"gozcu": Color("5A6B7D"),
	"karalama": Color("A12B3A"),
	"populizm": Color("C0409A"),
	"mana_bonusu": Color("2A8FE0"),
	"gundem_economic_n": Color("B8862B"),
	"gundem_economic_p": Color("D9A93A"),
	"gundem_social_n": Color("7A4FC4"),
	"gundem_social_p": Color("9A6FDF"),
	"gundem_administrative_n": Color("1F8F8A"),
	"gundem_administrative_p": Color("35B3AD"),
}

func _initialize() -> void:
	var base: Image = (load(BASE) as Texture2D).get_image()
	if base.is_compressed():
		base.decompress()
	base.convert(Image.FORMAT_RGBA8)
	var border: Color = base.get_pixel(0, 0)
	var body: Color = base.get_pixel(1, 1)
	var accent: Color = base.get_pixel(3, 3)
	for card_type in CARDS.keys():
		var img: Image = base.duplicate()
		for y in img.get_height():
			for x in img.get_width():
				var p: Color = img.get_pixel(x, y)
				if p.is_equal_approx(accent):
					img.set_pixel(x, y, CARDS[card_type])
				elif p.is_equal_approx(border) and BODY_RECT.has_point(Vector2i(x, y)):
					img.set_pixel(x, y, body)
		var path: String = OUT_DIR + "politic_card_%s.png" % card_type
		img.save_png(ProjectSettings.globalize_path(path))
		print("yazildi ", path)
	quit()
