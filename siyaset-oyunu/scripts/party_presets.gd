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

# 20 renk + siyah + beyaz = 22 preset. Hem ikon rengi hem arka plan rengi
# seçimi bu paletten yapılır.
const COLORS: Array[Color] = [
	Color("F20C1F"),
	Color("F26C0C"),
	Color("F2920C"),
	Color("FABD05"),
	Color("D4E619"),
	Color("90C91C"),
	Color("59BD28"),
	Color("29A33D"),
	Color("1FAD66"),
	Color("17CFA1"),
	Color("11D4C3"),
	Color("13DBED"),
	Color("1791CF"),
	Color("1C48C9"),
	Color("261C99"),
	Color("5A1FAD"),
	Color("8C21C2"),
	Color("BB27D9"),
	Color("D927CA"),
	Color("ED2B7C"),
	Color("000000"), # siyah
	Color("FFFFFF"), # beyaz
]

var icon_paths: Array[String] = []
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

func random_icon_index() -> int:
	return randi_range(0, icon_paths.size() - 1)

func random_color() -> Color:
	return COLORS[randi_range(0, COLORS.size() - 1)]
