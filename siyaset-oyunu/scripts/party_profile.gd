class_name PartyProfile
extends RefCounted
## Bir partinin ideoloji profilini gösteren pixel-art kartı üretir.
##
## Kart, assets/ui/politic_profile.png'in üstüne üç eksen görselinin
## (assets/ui/<eksen>_<deger>.png) yapıştırılmasıyla oluşur.
##
## EKSEN GÖRSELLERİ NEREYE KONUYOR? politic_profile.png'in içinde, her eksen
## için bir tane olmak üzere ÜÇ İŞARETÇİ PİKSEL var (bkz. AXIS_MARKER_COLORS).
## Bu pikseller ilgili eksen görselinin MERKEZİNİ tanımlıyor. Konumları koda
## GÖMÜLMÜYOR, çalışma zamanında PNG taranarak bulunuyor — böylece profil
## görselini yeniden çizip işaretçileri oynatsan bile kod değişmeden doğru
## çalışmaya devam eder. İşaretçi pikselin kendisi, üstüne yapıştırılan eksen
## görseli tarafından zaten kapatılıyor.

const PROFILE_PATH := "res://assets/ui/politic_profile.png"

## İşaretçi piksel rengi -> IdeologyAxes.AXES içindeki eksen adı.
##
## ÖNEMLİ: Bu renkler profil görselinde SADECE işaretçi olarak, HER BİRİ TEK
## PİKSEL şeklinde kullanılmalı. Profilin kendi süslemesinde (eksen etiketleri,
## oklar vb.) aynı renk kullanılırsa tarama yanlış konumu işaretçi sanar.
## Görselde şu an bunlara YAKIN ama farklı tonlar var (#e67324, #70ec98,
## #aa67f4) — onlar dekoratif, kasıtlı olarak listeye alınmadı.
const AXIS_MARKER_COLORS := {
	"ff6800": "economic",
	"00ff52": "social",
	"a000ff": "administrative",
}

## Eksen adı -> dosya adı öneki. Görsel dosyaları "administrative" yerine
## kısaca "admin" kullanıyor.
const AXIS_FILE_PREFIX := {
	"economic": "economic",
	"social": "social",
	"administrative": "admin",
}

# İlk kullanımda doldurulur; her hover'da PNG'yi yeniden taramamak için.
static var _marker_positions: Dictionary = {}  # axis -> Vector2i (merkez piksel)
static var _profile_image: Image = null
static var _scanned: bool = false
# ideoloji imzası -> ImageTexture (aynı profil tekrar tekrar üretilmesin)
static var _texture_cache: Dictionary = {}

## Verilen ideolojiye göre profil kartının dokusunu döndürür.
## ideology: {"economic": int, "social": int, "administrative": int}
static func build_texture(ideology: Dictionary) -> Texture2D:
	_ensure_scanned()
	if _profile_image == null:
		return null

	var key := ""
	for axis in IdeologyAxes.AXES:
		key += "%d," % int(ideology.get(axis, 0))
	if _texture_cache.has(key):
		return _texture_cache[key]

	var canvas := _profile_image.duplicate()
	for axis in IdeologyAxes.AXES:
		if not _marker_positions.has(axis):
			continue
		var value: int = IdeologyAxes.clamp_value(int(ideology.get(axis, 0)))
		var axis_image := _load_axis_image(axis, value)
		if axis_image == null:
			continue
		var marker: Vector2i = _marker_positions[axis]
		# İşaretçi piksel, eksen görselinin MERKEZ pikseli olacak şekilde
		# hizala. Tek sayı genişlik/yükseklikte merkez piksel (n-1)/2
		# indeksindedir, o yüzden sol-üst köşe = işaretçi - (boyut-1)/2.
		var top_left := marker - (axis_image.get_size() - Vector2i.ONE) / 2
		canvas.blend_rect(axis_image, Rect2i(Vector2i.ZERO, axis_image.get_size()), top_left)

	var texture := ImageTexture.create_from_image(canvas)
	_texture_cache[key] = texture
	return texture

## Kartın piksel boyutu (ölçeklenmemiş). Ölçekli gösterim yapan taraf, tam
## sayı katlarla büyütmeli ki pixel-art keskin kalsın.
static func get_native_size() -> Vector2i:
	_ensure_scanned()
	if _profile_image == null:
		return Vector2i.ZERO
	return _profile_image.get_size()

static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true

	var profile_texture: Texture2D = load(PROFILE_PATH)
	if profile_texture == null:
		push_warning("Party profile image not found: %s" % PROFILE_PATH)
		return
	var image := profile_texture.get_image()
	if image == null:
		push_warning("Party profile image could not be read: %s" % PROFILE_PATH)
		return
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	_profile_image = image

	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5:
				continue
			var hex := pixel.to_html(false).to_lower()
			if AXIS_MARKER_COLORS.has(hex):
				_marker_positions[AXIS_MARKER_COLORS[hex]] = Vector2i(x, y)

	for axis in IdeologyAxes.AXES:
		if not _marker_positions.has(axis):
			push_warning("Party profile: '%s' ekseni icin isaretci piksel bulunamadi (%s icinde)." % [axis, PROFILE_PATH])

static func _load_axis_image(axis: String, value: int) -> Image:
	var prefix: String = AXIS_FILE_PREFIX.get(axis, axis)
	# Dosya adlarında pozitif değerler ARTI işaretli: economic_+2.png,
	# negatifler eksi işaretli: economic_-2.png, nötr sade: economic_0.png.
	var suffix := "0" if value == 0 else ("+%d" % value if value > 0 else str(value))
	var path := "res://assets/ui/%s_%s.png" % [prefix, suffix]
	var texture: Texture2D = load(path)
	if texture == null:
		push_warning("Axis image not found: %s" % path)
		return null
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image
