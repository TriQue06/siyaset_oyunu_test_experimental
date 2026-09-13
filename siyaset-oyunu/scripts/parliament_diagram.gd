class_name ParliamentDiagram
extends Control
## Yarım daire (hemicycle) şeklinde parlamento koltuk diyagramı.
##
## Algoritma, eksen_projeksiyon/index.html içindeki createParliamentArch(seatsObj, total)
## fonksiyonunun (satır ~3457) BİREBİR GDScript portu: koltuklar satır satır
## (row) diziliyor, her satırın kapasitesi o satırın yay uzunluğuna göre
## hesaplanıyor, satır içindeki koltuklar asin tabanlı açı marjıyla eşit
## aralıklarla yerleştiriliyor, tüm noktalar açıya göre soldan-sağa
## sıralanıp partilere sırayla (verilen sırayla) paylaştırılıyor. Tüm
## koltuklar TEK BİR sabit yarıçapta (SEAT_RADIUS_FACTOR * satır_kalınlığı)
## çiziliyor — orijinal JS ile aynı.

const SPAN := 180.0          # yay açısı (derece) — orijinal JS: SPAN
const SEAT_RADIUS_FACTOR := 0.8  # orijinal JS: SRF

## Türkiye haritasındaki kalın beyaz kontur ile aynı görsel dilde, koltuk
## noktalarının HER BİRİNİN arkasına biraz daha büyük beyaz bir daire
## çizilir; koltuklar birbirine yakın olduğu için bitişik beyaz daireler
## görsel olarak birleşip tüm diyagramın etrafında tek parça, kalın beyaz
## bir kontur izlenimi yaratır.
@export var outline_width: float = 3.2
@export var outline_color: Color = Color(1, 1, 1, 0.95)

var _dot_positions: Array = [] # Array[Vector2], normalize (x: 0..2, merkez=1 / y: 0..~1)
var _dot_colors: Array = []    # Array[Color], _dot_positions ile aynı sırada
var _seat_radius_norm: float = 0.0 # normalize koltuk yarıçapı (tüm noktalar için sabit)
var _total_seats: int = 0

## entries: Array of {"seats": int, "color": Color} — sıra ÖNEMLİ, koltuklar
## bu sırayla soldan başlanarak dolduruluyor.
func set_results(entries: Array) -> void:
	var total := 0
	for e in entries:
		total += int(e["seats"])
	_total_seats = total

	var layout := _compute_seat_layout(total)
	var positions: Array = layout["positions"]
	_seat_radius_norm = layout["seat_radius"]

	_dot_positions.clear()
	_dot_colors.clear()
	var idx := 0
	for e in entries:
		var seats: int = e["seats"]
		var color: Color = e["color"]
		for i in seats:
			if idx >= positions.size():
				break
			_dot_positions.append(positions[idx])
			_dot_colors.append(color)
			idx += 1
	queue_redraw()

func _ready() -> void:
	# Pencere ölçeği değişince kontrol boyutu aynı kalsa bile ekran piksel
	# ızgarası değişir; kareler yeniden hizalanmalı.
	get_viewport().size_changed.connect(queue_redraw)

func _draw() -> void:
	if _dot_positions.is_empty():
		return
	# x normalize [0,2] (merkez=1), y normalize [0,~1] — kontrol alanına sığdır.
	var scale: float = minf(size.x * 0.5, size.y * 0.96)
	var origin := Vector2(size.x * 0.5, size.y * 0.98)

	# Keskin kenarlı KARE koltuklar, GERÇEK EKRAN PİKSELİNE hizalı çiziliyor.
	# Proje "canvas_items" esnetme modunda: pencere boyutu temel çözünürlükten
	# farklıyken arada kesirli bir ölçek var. Kareler bu ölçek hesaba katılmadan
	# çizilince kontur kenarları piksel sınırlarına farklı düşüyor, bazı
	# karelerin konturu kalın bazılarınınki ince görünüyordu. Burada merkezler
	# ve boyutlar ekran pikselinde TAM SAYIYA yuvarlanıp yerel uzaya geri
	# çevriliyor; kontur kalınlığı da tek başına yuvarlanıyor, böylece her
	# karede birebir aynı.
	var to_screen := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var from_screen := to_screen.affine_inverse()
	var screen_scale: float = maxf(0.0001, to_screen.get_scale().x)
	var dot_half_px: int = maxi(1, int(roundf(maxf(2.5, _seat_radius_norm * scale) * screen_scale)))
	var outline_px: int = maxi(1, int(roundf(outline_width * screen_scale)))
	var centers_px: Array = []
	for p in _dot_positions:
		centers_px.append((to_screen * (origin + Vector2(p.x - 1.0, -p.y) * scale)).round())
	for center_px in centers_px:
		_draw_screen_square(from_screen, center_px, dot_half_px + outline_px, outline_color)
	for i in centers_px.size():
		_draw_screen_square(from_screen, centers_px[i], dot_half_px, _dot_colors[i])

	# eksen_projeksiyon'daki gibi, yayın altında ortalanmış toplam sandalye
	# sayısı (createParliamentArch'taki <text>{total}</text> karşılığı).
	if _total_seats > 0:
		var font := get_theme_default_font()
		var font_size: int = int(round(size.x * 0.06))
		var text := str(_total_seats)
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(size.x * 0.5 - text_width * 0.5, size.y - 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.9))

func _draw_screen_square(from_screen: Transform2D, center_px: Vector2, half_px: int, color: Color) -> void:
	var top_left: Vector2 = from_screen * (center_px - Vector2(half_px, half_px))
	var bottom_right: Vector2 = from_screen * (center_px + Vector2(half_px, half_px))
	draw_rect(Rect2(top_left, bottom_right - top_left), color, true)

# --- Koltuk yerleşim algoritması (createParliamentArch'ın birebir portu) ---

static func _thicc(n: int) -> float:
	return 1.0 / (4.0 * n - 2.0)

static func _row_caps(n: int) -> Array:
	var r := _thicc(n)
	var rs := PI * SPAN / 180.0
	var caps: Array = []
	for i in n:
		caps.append(int(floor(rs * (0.5 + 2.0 * i * r) / (2.0 * r))))
	return caps

static func _sum_caps(n: int) -> int:
	var total := 0
	for c in _row_caps(n):
		total += c
	return total

static func _get_nrows(total_seats: int) -> int:
	var n := 1
	while _sum_caps(n) < total_seats:
		n += 1
	return n

## {"positions": Array[{"x":float,"y":float,"angle":float}] (soldan sağa
## sıralı), "seat_radius": float (normalize, tüm koltuklar için sabit)}.
static func _compute_seat_layout(total_seats: int) -> Dictionary:
	if total_seats <= 0:
		return {"positions": [], "seat_radius": 0.0}

	var nrows := _get_nrows(total_seats)
	var t := _thicc(nrows)
	var caps := _row_caps(nrows)
	var caps_sum := 0
	for c in caps:
		caps_sum += c
	var fill_ratio: float = float(total_seats) / float(maxi(1, caps_sum))

	var raw: Array = [] # {"pos": Vector2, "angle": float}
	for r in nrows:
		var n: int
		if r == nrows - 1:
			n = total_seats - raw.size()
		else:
			n = int(round(fill_ratio * caps[r]))
		if n <= 0:
			continue
		var rr := 0.5 + 2.0 * r * t
		if n == 1:
			raw.append({"pos": Vector2(1.0, rr), "angle": PI / 2.0})
		else:
			var am := asin(clampf(t / rr, -1.0, 1.0))
			var ai := (PI - 2.0 * am) / float(n - 1)
			for s in n:
				var a: float = am + s * ai
				raw.append({"pos": Vector2(rr * cos(a) + 1.0, rr * sin(a)), "angle": a})

	# Yuvarlama artıklarıyla total_seats'i aşmış olabilir; garanti altına al.
	if raw.size() > total_seats:
		raw = raw.slice(0, total_seats)

	raw.sort_custom(func(a, b): return a["angle"] > b["angle"]) # sol -> sağ

	var positions: Array = []
	for e in raw:
		positions.append(e["pos"])

	var seat_radius: float = SEAT_RADIUS_FACTOR * t
	return {"positions": positions, "seat_radius": seat_radius}
