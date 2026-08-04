class_name SvgRaster
extends RefCounted
## SVG dosyalarını ÇALIŞMA ZAMANINDA, istenen ölçekte rasterize eder.
##
## Godot'un normal import hattı bir SVG'yi SABİT bir çözünürlükte tek sefer
## rasterize edip PNG gibi saklar — o çözünürlüğün üstüne büyütülünce
## piksel/blok görünür (fontların aksine, ki onlar her boyut için yeniden
## çizilir). Bu yardımcı, kaynak SVG metnini Image.load_svg_from_string()
## ile İSTENEN ÖLÇEKTE anında rasterize ederek fontlarla aynı mantığı
## uygular: her zaman ihtiyaç duyulan çözünürlükte, matematiksel olarak
## keskin bir sonuç üretir.

## path: res:// yolu. scale: SVG'nin kendi birimine göre çarpan
## (örn. viewBox 24x24 olan bir ikon için scale=10 -> 240x240 piksel çıktı).
static func load_texture(path: String, scale: float) -> ImageTexture:
	var image := load_image(path, scale)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

static func load_image(path: String, scale: float) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SVG bulunamadı: %s" % path)
		return null
	var svg_text := file.get_as_text()
	var image := Image.new()
	var err := image.load_svg_from_string(svg_text, scale)
	if err != OK:
		push_warning("SVG rasterize edilemedi (%s), hata kodu: %d" % [path, err])
		return null
	return image
