extends Node
## Autoload. Parti kurulum ekranındaki ikon ve renk katalogları.
##
## İkonlar Google Material Symbols SVG'leri (24dp viewBox). Godot'un sabit
## çözünürlüklü import'una güvenmek yerine SvgRaster ile ÇALIŞMA ZAMANINDA,
## her kullanım yerinin gerçekten ihtiyaç duyduğu piksel boyutunda rasterize
## ediyoruz (küçük ızgara ikonu ile ekranı kaplayan kocaman önizleme farklı
## çözünürlük ister) — böylece hiçbir yerde piksel/blok görünmez.

const ICONS_DIR := "res://assets/icons"
const ICON_NATIVE_SIZE := 24.0  # kaynak SVG'lerin viewBox boyutu (24dp)

# Parti (arka plan) renkleri. İkon rengi her zaman beyazdır.
const COLORS: Array[Color] = [
	Color("F2132A"), # kırmızı
	Color("FA6E66"), # somon kırmızısı
	Color("F27E1F"), # turuncu
	Color("F0A824"), # sarı-turuncu
	Color("FAD028"), # sarı
	Color("9DC94B"), # limon sarısı
	Color("31C440"), # yeşil
	Color("3FB586"), # su yeşili
	Color("27DBDB"), # turkuaz
	Color("83B7EB"), # açık mavi
	Color("22A9D6"), # mavi
	Color("2569CF"), # koyu mavi
	Color("244FB3"), # lacivert
	Color("7647CC"), # indigo
	Color("AB39DB"), # mor
	Color("E041D8"), # eflatun
	Color("F04391"), # fuşya
	Color("A6325A"), # bordo
]

## İkon dosyaları DÜZ .svg: her görüntüleyici/editör açabilsin diye. Godot
## bunları dokuya çevirmesin diye her birinin .import dosyası importer="keep"
## ("olduğu gibi dışa aktar") — oyun onları çalışma anında SvgRaster ile
## ihtiyaç duyulan boyutta kendisi rasterize ediyor.
const ICON_EXTENSION := "svg"

var icon_paths: Array[String] = []
# "<index>_<pixel_size>" -> ImageTexture (aynı boyut tekrar istenirse yeniden
# rasterize etmeyelim diye önbellek).
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_scan_icons()

func _scan_icons() -> void:
	icon_paths.clear()
	_texture_cache.clear()
	var dir := DirAccess.open(ICONS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			# Sadece icon_NN.svg: klasördeki başka SVG'ler (ör. para.svg) parti
			# logosu olarak listelenmesin.
			if not dir.current_is_dir() and file_name.begins_with("icon_") \
					and file_name.get_extension().to_lower() == ICON_EXTENSION:
				icon_paths.append(ICONS_DIR.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()
		icon_paths.sort()

	if icon_paths.is_empty():
		# Bazı export ayarlarında dizin taraması (DirAccess) paketlenmiş
		# kaynaklarda güvenilmez olabiliyor; dosya adları icon_01..icon_NN
		# şeklinde sıralı olduğu için, tarama boş dönerse dosyaların
		# gerçekten var olup olmadığını deneyerek (FileAccess.file_exists)
		# bir yedek liste oluşturuyoruz.
		var i := 1
		while true:
			var candidate := ICONS_DIR.path_join("icon_%02d.%s" % [i, ICON_EXTENSION])
			if not FileAccess.file_exists(candidate):
				break
			icon_paths.append(candidate)
			i += 1
		if not icon_paths.is_empty():
			push_warning("İkon dizini taranamadı, %d ikon yedek listeyle bulundu." % icon_paths.size())
		else:
			push_warning("İkon klasörü bulunamadı: %s" % ICONS_DIR)
	# Mod logoları yerleşiklerin ARKASINA eklenir: yerleşik indeksler değişmez
	# (lobide herkes aynı modlara sahip; bkz. ContentPacks).
	for path in ContentPacks.extra_icon_paths():
		icon_paths.append(String(path))

func icon_count() -> int:
	return icon_paths.size()

## target_pixel_size: bu ikonun EKRANDA gösterileceği piksel boyutu (kare).
## Küçük bir ızgara ikonu için ~64-96, kocaman bir önizleme için ~400-600
## gibi kullanım yerine göre farklı değerler verilmeli — her biri kendi
## çözünürlüğünde rasterize edilir, tek bir dokuyu büyütüp bulanıklaştırmayız.
## BAĞIMSIZ SİYASETÇİ simgesi (gri zeminde kullanıcı): parti ikonu değil,
## özel indeks. Bağımsızlar bloğu da aynı simgeyi kullanır.
const USER_ICON_INDEX := -10
const USER_ICON_PATH := "res://assets/ui/independent_user.svg"
const INDEPENDENT_COLOR := Color("6E6A80")

func get_icon_texture(index: int, target_pixel_size: int = 128) -> Texture2D:
	if index == USER_ICON_INDEX:
		var user_key := "user_%d" % target_pixel_size
		if not _texture_cache.has(user_key):
			_texture_cache[user_key] = SvgRaster.load_texture(USER_ICON_PATH, target_pixel_size / ICON_NATIVE_SIZE)
		return _texture_cache[user_key]
	if index < 0 or index >= icon_paths.size():
		return null
	var key := "%d_%d" % [index, target_pixel_size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var scale := target_pixel_size / ICON_NATIVE_SIZE
	var tex: Texture2D = SvgRaster.load_texture(icon_paths[index], scale) 		if icon_paths[index].get_extension().to_lower() == ICON_EXTENSION else _load_bitmap_icon(icon_paths[index])
	if tex != null:
		_texture_cache[key] = tex
	return tex

## Mod logosu (PNG): dosyadan okunur, boyutu kullanım yerinde sığdırılır.
func _load_bitmap_icon(path: String) -> Texture2D:
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

## Kalıcı logo kimliği ("base:icon_05", "<mod>:<dosya>"): ayar paketleri ve
## kayıtlar indeks yerine bunu saklayabilir (mod sırası değişse de bozulmaz).
func icon_id(index: int) -> String:
	if index < 0 or index >= icon_paths.size():
		return ""
	var path := icon_paths[index]
	if path.begins_with(ICONS_DIR):
		return "%s:%s" % [ContentPacks.BASE, path.get_file().get_basename()]
	return ContentPacks.icon_id_for_path(path)

func icon_index_of(id: String) -> int:
	for i in icon_paths.size():
		if icon_id(i) == id:
			return i
	return -1

func random_icon_index() -> int:
	return randi_range(0, maxi(0, icon_paths.size() - 1))

## Geçersiz (ör. eski sürümde kaydedilmiş, artık olmayan) ikon indeksini ilk ikona çeker.
func clamp_icon_index(index: int) -> int:
	return index if index >= 0 and index < icon_paths.size() else 0

func random_color() -> Color:
	return COLORS[randi_range(0, COLORS.size() - 1)]
