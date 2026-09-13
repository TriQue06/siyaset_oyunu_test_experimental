extends Node2D
## ProvinceMap'in ÇOCUĞU olarak eklenir (bkz. Map.tscn). İllerin üstüne, o
## ildeki milletvekili sandalyelerini noktalar halinde çizer.
##
## Noktalar bir raster texture (Sprite2D) yerine _draw()/draw_circle ile
## VEKTÖR olarak çiziliyor (antialiased) — harita hangi ölçekte gösterilirse
## gösterilsin (ne kadar büyütülürse büyütülsün) her zaman keskin/pürüzsüz
## kalır, pikselleşmez.
##
## Yerleşim algoritması, geliştiricinin "projeksiyon_hesaplayici" web
## uygulamasındaki getDotLayout()'un GDScript'e taşınmış halidir: her il bir
## "dot grubu" oluşturur (n sandalye için satır/sütun grid'i), grup HER ZAMAN
## tam olarak ilin (manuel override varsa onun, yoksa piksel-ızgaranın)
## merkezinde durur — dinamik çarpışma-önleyici fizik YOK (bkz. aşağıdaki not:
## kaldırıldı, çünkü tools/seat_marker_editor.html'de simüle edilemiyordu ve
## editör/oyun arasında sürekli tutarsızlığa yol açıyordu). Komşu illerin
## grupları görsel olarak çakışıyorsa, bunu tools/seat_marker_editor.html ile
## elle düzeltmek gerekir.

@export var dot_radius: float = 4.6     # nokta yarıçapı (harita/viewBox birimi)
@export var dot_outline_width: float = 2.0  # siyah kontur kalınlığı
@export var dot_outline_color: Color = Color(0.11, 0.12, 0.13) # eksen_projeksiyon: #1c1e21
@export var dot_spacing: float = 4.4    # aynı gruptaki noktalar arası boşluk
## Konturlu kareler arasında EKRANDA bırakılacak en az boşluk (piksel).
## dot_spacing "renkli kare kenarları arası" boşluğu tanımlıyor, ama kontur
## bunun içine taşıyor: varsayılan değerlerde konturlar arasında sadece
## 14.4 - 13.6 = 0.8 harita birimi kalıyor, bu da her ekran ölçeğinde 1
## pikselden AZ ediyor — kareler görsel olarak birbirine yapışıp tek bir
## bulanık lekeye dönüşüyordu. Bu değer, ne olursa olsun kareler arasında
## en az bu kadar gerçek piksel boşluk kalmasını garanti eder.
@export var min_screen_gap_px: int = 1

## Bu haritaya ÖZGÜ, STATİK milletvekili konum belgesi: il -> [x, y] MERKEZ
## noktası (province_pixel_map.json ile AYNI birim: ham piksel-ızgara
## koordinatı). Her ilin nokta grubu TAM OLARAK burada yazan merkeze çizilir;
## çalışma zamanında hiçbir otomatik kaydırma/çakışma çözme YOKTUR — böylece
## tools/seat_marker_editor.html'de gördüğünle oyunda gördüğün her zaman
## birebir aynıdır. Belge normalde illerin TAMAMINI içerir; bir il eksik
## kalırsa (ör. haritaya yeni il eklenip belge güncellenmediyse) o il için
## ilin piksel-merkezi yedek olarak kullanılır.
@export var seat_centers_path: String = "res://data/province_seat_centers.json"
var _seat_centers: Dictionary = {}  # province_id -> Vector2 (harita/local birimi)

# province_id -> Array[Color] (o ildeki her sandalye için bir renk, parti rengi)
var _seats: Dictionary = {}
## Array[{"anchor": Vector2, "layout": Array[int], "colors": Array[Color]}]
## _draw() bunları TAM SAYI PİKSEL ızgarasında çizer (bkz. _draw). Nokta
## konumları burada ÖNCEDEN hesaplanmıyor — çünkü doğru piksel hizalaması
## ancak çizim anındaki gerçek ekran ölçeği bilinerek yapılabilir.
var _groups: Array = []

@onready var _province_map = get_parent()

func _ready() -> void:
	_load_seat_centers()

func _load_seat_centers() -> void:
	_seat_centers.clear()
	if not FileAccess.file_exists(seat_centers_path):
		push_warning("Seat centers file not found: %s" % seat_centers_path)
		return
	var file := FileAccess.open(seat_centers_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_warning("Seat centers file could not be parsed: %s" % seat_centers_path)
		return
	var unit_scale: float = _province_map.MAP_UNIT_SCALE if _province_map != null else 4.0
	for province_id in parsed.keys():
		var p: Array = parsed[province_id]
		# editor, ham piksel-ızgara koordinatını yazıyor (province_pixel_map.json
		# "centers" ile birebir aynı birim/hizalama: +0.5 piksel merkezi, sonra
		# harita birimine çevirmek için MAP_UNIT_SCALE ile çarpılıyor).
		_seat_centers[province_id] = (Vector2(p[0], p[1]) + Vector2(0.5, 0.5)) * unit_scale

## O ilin sandalye/renk listesini ayarlar ve tüm noktaları yeniden hesaplar.
## seat_colors: her eleman bir Color (o koltuktaki partinin rengi).
func set_seats(province_id: String, seat_colors: Array) -> void:
	_seats[province_id] = seat_colors
	_rebuild()

func clear_province(province_id: String) -> void:
	_seats.erase(province_id)
	_rebuild()

func clear_all() -> void:
	_seats.clear()
	_rebuild()

## Referans web uygulamasındaki getDotLayout(n) ile birebir aynı mantık:
## küçük n'ler için elle ayarlanmış, kompakt (kare-ye yakın) düzenler;
## büyük n'ler için sqrt tabanlı sütun sayısı + satırlara eşit dağıtım.
func _get_dot_layout(n: int) -> Array:
	if n <= 0:
		return []
	match n:
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [3, 2]
		6: return [3, 3]
		7: return [2, 3, 2]
		8: return [3, 3, 2]
		9: return [3, 3, 3]

	var cols: int
	if n > 20:
		cols = int(ceil(sqrt(n * 1.2)))
		cols = min(cols, 7)
	else:
		cols = int(ceil(sqrt(n * 1.5)))
		cols = min(cols, 8)

	var rows := int(ceil(float(n) / float(cols)))
	var layout: Array = []
	var remaining := n
	for i in rows:
		var r := int(ceil(float(remaining) / float(rows - i)))
		layout.append(r)
		remaining -= r
	return layout

func _rebuild() -> void:
	_groups.clear()

	if _province_map == null:
		queue_redraw()
		return

	var cell := dot_radius * 2.0 + dot_spacing
	var groups: Array = []
	for province_id in _seats.keys():
		var colors: Array = _seats[province_id]
		if colors.is_empty():
			continue
		var layout := _get_dot_layout(colors.size())
		var max_cols := 0
		for c in layout:
			max_cols = max(max_cols, c)
		var rows := layout.size()
		var grid_w := max_cols * cell
		var grid_h := rows * cell
		var center: Vector2 = _seat_centers.get(province_id, _province_map.get_province_centroid(province_id))
		groups.append({
			"pos": center,
			"layout": layout,
			"colors": colors,
			"half_w": grid_w * 0.5,
			"half_h": grid_h * 0.5,
		})

	# ÖNEMLİ: Burada hiçbir otomatik yerleştirme/çakışma çözme YOK. Grup konumu
	# HER ZAMAN doğrudan seat_centers_path belgesindeki merkez. Vaktiyle burada
	# canlı bir çarpışma-önleyici fizik vardı; tools/seat_marker_editor.html
	# onu simüle edemediği için editörde "gayet güzel" görünen yerleşim oyunda
	# bambaşka çıkıyordu. Tek doğruluk kaynağı statik belge olunca editör ile
	# oyun matematiksel olarak birebir aynı sonucu veriyor. Çakışan/kötü duran
	# iller SADECE editörden elle düzeltilir.

	# Sınır kelepçesi: büyük illerde (ör. çok sandalyeli İstanbul) nokta
	# kümesi, ilin kendi küçük piksel alanına göre ÇOK daha büyük olabiliyor
	# — hele merkez haritanın kenarına yakınsa (İstanbul kuzeyde), fizik
	# kümeyi haritanın DIŞINA itebiliyordu ("neredeyse haritanın dışına
	# taşıyor" bug'ı). "locked" gruplar bile bundan muaf değil — kilit sadece
	# ÇAPA noktasını sabitliyor, kümenin kendisini harita sınırları içinde
	# TUTMUYORDU. Burada her grubun son konumu, kümenin TAMAMI harita
	# sınırları içinde kalacak şekilde clamp ediliyor.
	var map_size := Vector2.ZERO
	if _province_map != null and _province_map.grid_width > 0:
		map_size = Vector2(_province_map.grid_width, _province_map.grid_height) * _province_map.MAP_UNIT_SCALE
	for g in groups:
		if map_size.x > 0.0 and map_size.y > 0.0:
			if g.half_w * 2.0 <= map_size.x:
				g.pos.x = clampf(g.pos.x, g.half_w, map_size.x - g.half_w)
			if g.half_h * 2.0 <= map_size.y:
				g.pos.y = clampf(g.pos.y, g.half_h, map_size.y - g.half_h)
		_groups.append({
			"anchor": _centroid_anchor(g.pos, g.layout, cell),
			"layout": g.layout,
			"colors": g.colors,
		})

	queue_redraw()

## Grubun "çapası": öyle bir nokta ki, ızgara oradan kurulduğunda noktaların
## GERÇEK AĞIRLIK MERKEZİ tam olarak istenen `center`a düşsün. Son satır
## genelde eksik dolduğu için (bkz. _get_dot_layout) bounding-box merkezi ile
## ağırlık merkezi aynı değildir; kullanıcı isteği "konum her zaman tüm
## vekillerin tam ortası olsun" olduğu için farkı burada telafi ediyoruz.
func _centroid_anchor(center: Vector2, layout: Array, cell: float) -> Vector2:
	var rows := layout.size()
	var sum := Vector2.ZERO
	var total := 0
	for row in rows:
		var cols: int = layout[row]
		for col in cols:
			sum += Vector2(col - (cols - 1) * 0.5, row - (rows - 1) * 0.5) * cell
			total += 1
	if total == 0:
		return center
	return center - sum / float(total)

## Pixel-art haritayla tutarlı olsun diye YUVARLAK değil, keskin kenarlı KARE
## noktalar çiziliyor: önce biraz daha büyük koyu bir kare (kontur), üstüne
## parti renginde asıl kare (eksen_projeksiyon'daki stroke="#1c1e21" karşılığı).
##
## PİKSEL IZGARASI (bu fonksiyonun asıl işi): harita kesirli bir ölçekle
## (fit_scale, ör. 0.678) büyütülüyor. Nokta konumları harita biriminde
## hesaplanıp sonra tek tek ekran pikseline yuvarlanırsa, matematiksel olarak
## EŞİT aralıklı noktalar ekranda eşit aralıklı ÇIKMAZ (ör. adımlar
## 10,10,9,10,10 olur) — "bazı noktalar arası boşluk bir iki piksel farklı"
## şikayetinin sebebi buydu. Burada bunun yerine tüm ızgara doğrudan TAM SAYI
## piksel adımlarıyla kuruluyor: bir kez grup çapası yuvarlanıyor, sonra her
## satır/sütun sabit `step_px` tam sayı adımıyla ilerliyor. Böylece hem yatay
## hem dikey tüm boşluklar birbirinin AYNISI oluyor. Ayrıca `step_px`,
## konturlu kareler arasında en az `min_screen_gap_px` gerçek piksel boşluk
## kalacak şekilde taban değerle sınırlanıyor (bkz. min_screen_gap_px notu).
func _draw() -> void:
	if _groups.is_empty():
		return
	# GERÇEK ekran pikseli: düğümün kendi global dönüşümü, projenin
	# "canvas_items" esnetme ölçeğini İÇERMİYOR. Pencere temel çözünürlükten
	# farklı boyuttayken bu kesirli ölçek yüzünden "tam piksele hizalı" sanılan
	# kareler gerçekte piksel sınırlarına farklı düşüyor, bazı karelerin
	# konturu kalın bazılarınınki ince görünüyordu. Viewport'un nihai
	# (esnetme) dönüşümünü de katınca hizalama gerçek piksellerde yapılıyor.
	var xform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var scale: float = maxf(0.0001, xform.get_scale().x)
	var inv := xform.affine_inverse()

	var dot_half_px: int = maxi(1, int(roundf(dot_radius * scale)))
	# Kontur kalınlığı AYRI yuvarlanıyor: iki boyutu bağımsız yuvarlamak ölçeğe
	# göre konturu 1 piksel oynatabiliyordu.
	var outline_half_px: int = dot_half_px + maxi(1, int(roundf(dot_outline_width * scale)))
	var cell := dot_radius * 2.0 + dot_spacing
	var step_px: int = maxi(outline_half_px * 2 + min_screen_gap_px, int(roundf(cell * scale)))

	# Kontur ve renkli kareler AYRI geçişlerde çizilmeli ki bir noktanın
	# konturu komşu noktanın renkli karesinin ÜSTÜNE binmesin.
	for pass_index in 2:
		var half_px: int = outline_half_px if pass_index == 0 else dot_half_px
		for g in _groups:
			var layout: Array = g["layout"]
			var colors: Array = g["colors"]
			var rows: int = layout.size()
			var anchor_px: Vector2 = (xform * g["anchor"]).round()
			var first_row_dy: int = int(roundf(-(rows - 1) * 0.5 * cell * scale))
			var idx := 0
			for row in rows:
				var cols: int = layout[row]
				var y_px: float = anchor_px.y + first_row_dy + row * step_px
				var x0_px: float = anchor_px.x + roundf(-(cols - 1) * 0.5 * cell * scale)
				for col in cols:
					if idx >= colors.size():
						break
					var color: Color = dot_outline_color if pass_index == 0 else colors[idx]
					var center_px := Vector2(x0_px + col * step_px, y_px)
					_draw_rect_at_screen_px(inv, center_px, half_px, color)
					idx += 1

## Ekran (global) piksel uzayında verilen kare, local uzaya geri çevrilerek
## çiziliyor — böylece Node2D ölçeği ne olursa olsun kenarlar tam piksele
## oturur, yarım piksel bulanıklığı olmaz.
func _draw_rect_at_screen_px(inv: Transform2D, center_px: Vector2, half_px: int, color: Color) -> void:
	var top_left: Vector2 = inv * (center_px - Vector2(half_px, half_px))
	var bottom_right: Vector2 = inv * (center_px + Vector2(half_px, half_px))
	draw_rect(Rect2(top_left, bottom_right - top_left), color, true)
