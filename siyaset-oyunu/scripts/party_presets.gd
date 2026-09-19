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
	Color("B141E0"), # mor
	Color("AB39DB"), # eflatun
	Color("F04391"), # fuşya
	Color("A6325A"), # bordo
]

## İKON KATEGORİLERİ: 0 kurgusal (assets/icons/*.svgdata), 1 Türkiye
## (assets/icons/turkiye/, gerçek parti amblemleri). icon_index tek bir
## listede: önce kurgusallar, sonra Türkiye ikonları.
const CATEGORY_FICTIONAL := 0
const CATEGORY_TURKIYE := 1
const CATEGORY_TITLES := ["Kurgusal", "Türkiye"]
const TURKIYE_DIR := "res://assets/icons/turkiye"
## Dizin taraması paketli oyunda güvenilmez olabildiği için dosya adları sabit.
const TURKIYE_ICONS := ["a_parti", "ak_parti", "anap", "ap", "btp", "buyuk_birlik", "chp", "dem_parti",
	"deva_partisi", "dp", "dsp", "gelecek_partisi", "genc_parti", "hdp", "huda_par", "iyi_parti", "ldp",
	"memleket", "mhp", "saadet", "sol_parti", "tip", "tkp", "yeni_parti", "yeni_yol", "yeniden_refah",
	"zafer_partisi"]

var icon_paths: Array[String] = []
## Kurgusal ikon sayısı (bu indeksten sonrası Türkiye kategorisi).
var fictional_count: int = 0
# "<index>_<pixel_size>" -> ImageTexture (aynı boyut tekrar istenirse yeniden
# rasterize etmeyelim diye önbellek).
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_scan_icons()

func _scan_icons() -> void:
	icon_paths.clear()
	var dir := DirAccess.open(ICONS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.get_extension().to_lower() == "svgdata":
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
			var candidate := ICONS_DIR.path_join("icon_%02d.svgdata" % i)
			if not FileAccess.file_exists(candidate):
				break
			icon_paths.append(candidate)
			i += 1
		if not icon_paths.is_empty():
			push_warning("İkon dizini taranamadı, %d ikon yedek listeyle bulundu." % icon_paths.size())
		else:
			push_warning("İkon klasörü bulunamadı: %s" % ICONS_DIR)
	fictional_count = icon_paths.size()
	for icon_name in TURKIYE_ICONS:
		var path := TURKIYE_DIR.path_join("%s.svgdata" % icon_name)
		if FileAccess.file_exists(path):
			icon_paths.append(path)

func icon_category(index: int) -> int:
	return CATEGORY_TURKIYE if index >= fictional_count else CATEGORY_FICTIONAL

## Bir kategorideki ikonların indeksleri.
func icon_indices(category: int) -> Array:
	return range(fictional_count, icon_paths.size()) if category == CATEGORY_TURKIYE else range(0, fictional_count)

func icon_count() -> int:
	return icon_paths.size()

## target_pixel_size: bu ikonun EKRANDA gösterileceği piksel boyutu (kare).
## Küçük bir ızgara ikonu için ~64-96, kocaman bir önizleme için ~400-600
## gibi kullanım yerine göre farklı değerler verilmeli — her biri kendi
## çözünürlüğünde rasterize edilir, tek bir dokuyu büyütüp bulanıklaştırmayız.
func get_icon_texture(index: int, target_pixel_size: int = 128) -> Texture2D:
	if index < 0 or index >= icon_paths.size():
		return null
	var key := "%d_%d" % [index, target_pixel_size]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var scale := target_pixel_size / ICON_NATIVE_SIZE
	var tex := SvgRaster.load_texture(icon_paths[index], scale)
	if tex != null:
		_texture_cache[key] = tex
	return tex

## Botlar ve rastgele parti kurgusal ikonlardan seçer.
func random_icon_index() -> int:
	return randi_range(0, maxi(0, fictional_count - 1))

func random_color() -> Color:
	return COLORS[randi_range(0, COLORS.size() - 1)]
