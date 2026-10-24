class_name MoneyIcon
## PARA SİMGESİ (0.0.239): para birimi karakteri yok; para her yerde bu
## simgeyle gösterilir (Material "paid" simgesi, dairede dolar işareti).
##   - Yazının içinde: kaynak metinlerdeki "¤" yer tutucusu L.t() çıkışında
##     GLYPH'e çevrilir; GLYPH, oyunun bütün yazı tiplerine YEDEK yazı tipi
##     olarak eklenen küçük bir simge yazı tipinde çizilir (yazının renginde).
##   - Tek başına (kasa levhası vb.): texture() / CoinIcon.

## Yazı içi simge karakteri (Unicode özel kullanım alanı; hiçbir yazı tipinde yok).
const GLYPH := "\uE000"
const PLACEHOLDER := "¤"
## Simgenin vektörü (beyaz: yazı rengiyle ya da modulate ile boyanır).
const SVG := '<svg xmlns="http://www.w3.org/2000/svg" height="96" width="96" viewBox="0 -960 960 960" fill="#ffffff"><path d="M444-200h70v-50q50-9 86-39t36-89q0-42-24-77t-96-61q-60-20-83-35t-23-41q0-26 18.5-41t53.5-15q32 0 50 15.5t26 38.5l64-26q-11-35-40.5-61T516-710v-50h-70v50q-50 11-78 44t-28 74q0 47 27.5 76t86.5 50q63 23 87.5 41t24.5 47q0 33-23.5 48.5T486-314q-33 0-58.5-20.5T390-396l-66 26q14 48 43.5 77.5T444-252v52Zm36 120q-83 0-156-31.5T197-197q-54-54-85.5-127T80-480q0-83 31.5-156T197-763q54-54 127-85.5T480-880q83 0 156 31.5T763-763q54 54 85.5 127T880-480q0 83-31.5 156T763-197q-54 54-127 85.5T480-80Zm0-80q134 0 227-93t93-227q0-134-93-227t-227-93q-134 0-227 93t-93 227q0 134 93 227t227 93Zm0-320Z"/></svg>'
## Simge yazı tipinin çizim boyu (piksel; her puntoya ölçeklenir).
const FONT_SIZE := 96
const FONTS := ["res://assets/fonts/IBMPlexMono-Regular.ttf", "res://assets/fonts/IBMPlexMono-Medium.ttf",
	"res://assets/fonts/IBMPlexMono-SemiBold.ttf", "res://assets/fonts/IBMPlexMono-Bold.ttf"]

static var _texture: ImageTexture
static var _font: FontFile
static var _installed := false

static func _image() -> Image:
	var image := Image.new()
	image.load_svg_from_string(SVG, 1.0)
	return image

## Tek başına kullanılan simge dokusu (beyaz; modulate ile renklendirilir).
static func texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image())
	return _texture

## GLYPH'i taşıyan bitmap yazı tipi: simge yazı satırına oturur, puntoya göre ölçeklenir.
static func font() -> FontFile:
	if _font != null:
		return _font
	var image := _image()
	image.convert(Image.FORMAT_LA8)  # gri tonlu: yazının rengiyle boyanır
	var f := FontFile.new()
	f.fixed_size = FONT_SIZE
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var cache := Vector2i(FONT_SIZE, 0)
	var s := float(FONT_SIZE)
	f.set_cache_ascent(0, FONT_SIZE, s * 0.8)
	f.set_cache_descent(0, FONT_SIZE, s * 0.2)
	f.set_texture_image(0, cache, 0, image)
	var glyph := GLYPH.unicode_at(0)
	var side := s * 0.92
	f.set_glyph_texture_idx(0, cache, glyph, 0)
	f.set_glyph_uv_rect(0, cache, glyph, Rect2(0, 0, image.get_width(), image.get_height()))
	f.set_glyph_size(0, cache, glyph, Vector2(side, side))
	# Rakamların boyunda, satırın ortasında dursun.
	f.set_glyph_offset(0, cache, glyph, Vector2(s * 0.04, -s * 0.78))
	f.set_glyph_advance(0, FONT_SIZE, glyph, Vector2(s, 0))
	_font = f
	return f

## Simge yazı tipini oyunun bütün yazı tiplerine yedek olarak ekler (bir kez).
static func install() -> void:
	if _installed:
		return
	_installed = true
	var icon := font()
	var targets: Array = []
	for path in FONTS:
		if ResourceLoader.exists(path):
			targets.append(load(path))
	targets.append(ThemeDB.fallback_font)
	for target in targets:
		var base := target as Font
		if base == null:
			continue
		var list: Array[Font] = base.fallbacks.duplicate()
		if not list.has(icon):
			list.append(icon)
			base.fallbacks = list

## Metindeki "¤" yer tutucularını simge karakterine çevirir.
static func apply(text: String) -> String:
	return text.replace(PLACEHOLDER, GLYPH) if text.contains(PLACEHOLDER) else text
