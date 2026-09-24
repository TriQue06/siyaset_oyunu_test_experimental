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

## Her koltuk: koyu ince konturlu, kenarı yumuşatılmış (antialiased) daire.
## Konturun kalınlığı koltuk yarıçapına ORANLI tek bir değer — bütün koltuklarda
## birebir aynı. Toplam yarıçap (kontur dahil) komşu koltuk mesafesinin
## yarısından küçük tutulur, daireler hiçbir zaman iç içe geçmez.
@export var outline_ratio: float = 0.16
@export var outline_color: Color = Color(0.07, 0.08, 0.1)

var _dot_positions: Array = [] # Array[Vector2], normalize (x: 0..2, merkez=1 / y: 0..~1)
var _dot_colors: Array = []    # Array[Color], _dot_positions ile aynı sırada
var _seat_radius_norm: float = 0.0 # normalize koltuk yarıçapı (tüm noktalar için sabit)
## Levhanın taban çizgisine uzaklığı.
const BASELINE_GAP := 6.0
## Ortadaki toplam vekil sayısının yazı boyutu (diyagram boyutundan bağımsız).
## Yayın ortasındaki boşluğa sığsın diye küçük: 24 punto bazı koltukların
## üstüne biniyordu.
const COUNT_FONT_SIZE := 18
var _total_seats: int = 0
var _layout_total: int = -1
var _layout: Dictionary = {}
var _min_gap_norm: float = 0.0 # en yakın iki koltuk merkezi arası (normalize)
## Vekil sayısının oturduğu levha (kendi zemini olan ek katman).
var _count_plate: PanelContainer
var _count_label: Label

## entries: Array of {"seats": int, "color": Color} — sıra ÖNEMLİ, koltuklar
## bu sırayla soldan başlanarak dolduruluyor.
func set_results(entries: Array) -> void:
	var total := 0
	for e in entries:
		total += int(e["seats"])
	_total_seats = total

	# Yerleşim sadece toplam değişince hesaplanır (seçim gecesi her karede çağırır).
	if total != _layout_total:
		_layout_total = total
		_layout = _compute_seat_layout(total)
		_min_gap_norm = _nearest_distance(_layout["positions"])
	var positions: Array = _layout["positions"]
	_seat_radius_norm = _layout["seat_radius"]

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
	_refresh_count_plate()
	queue_redraw()

## Koltuklar arası en küçük mesafe (satırlar içinde ve komşu satırlarda).
static func _nearest_distance(positions: Array) -> float:
	var best := INF
	for i in positions.size():
		for j in range(i + 1, mini(positions.size(), i + 60)):
			best = minf(best, (positions[i] as Vector2).distance_to(positions[j]))
	return 0.0 if best == INF else best

func _ready() -> void:
	# Pencere ölçeği değişince kontrol boyutu aynı kalsa bile ekran piksel
	# ızgarası değişir; kareler yeniden hizalanmalı.
	get_viewport().size_changed.connect(queue_redraw)
	_build_count_plate()
	resized.connect(_place_count_plate)

## VEKİL SAYISI LEVHASI: yarım dairenin ORTASINDAKİ boş alanda duran, kendi
## zemini (ek UI katmanı) olan monospace bir sayı. Önce çıplak draw_string,
## sonra yayın ALTINDA bir levhaydı; altta hem yer yiyordu hem de diyagramı
## küçültüyordu.
func _build_count_plate() -> void:
	_count_plate = PanelContainer.new()
	_count_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiSkin.stylebox(UiSkin.SLOT)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_count_plate.add_theme_stylebox_override("panel", style)
	_count_label = Label.new()
	_count_label.add_theme_font_override("font", UiTheme.mono(true))
	_count_label.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	_count_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_plate.add_child(_count_label)
	add_child(_count_plate)
	_refresh_count_plate()

func _refresh_count_plate() -> void:
	if _count_plate == null:
		return
	_count_plate.visible = _total_seats > 0
	_count_label.text = str(_total_seats)
	_place_count_plate()

## Levha yayın merkezine, taban çizgisinin hemen üstüne oturur — en içteki
## koltuk sırasının içinde kalan boşluğa.
func _place_count_plate() -> void:
	if _count_plate == null:
		return
	var plate_size := _count_plate.get_combined_minimum_size()
	_count_plate.size = plate_size
	var origin := _arc_origin()
	_count_plate.position = Vector2(origin.x - plate_size.x * 0.5,
		origin.y - plate_size.y - BASELINE_GAP)

## Yayın taban çizgisinin orta noktası. _draw ve levha yerleşimi aynı yeri
## kullanmalı, yoksa sayı yayın ortasından kayar.
func _arc_origin() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.98)

func _draw() -> void:
	if _dot_positions.is_empty():
		return
	# x normalize [0,2] (merkez=1), y normalize [0,~1] — kontrol alanına sığdır.
	# Vekil sayısı levhası artık yayın İÇİNDE durduğu için altta yer ayrılmıyor;
	# diyagram kontrolün tamamını kullanıyor.
	var scale: float = minf(size.x * 0.5, size.y * 0.96)
	var origin := _arc_origin()

	# Daireler kesirli konumlarda antialiased çizilir: piksel ızgarasına yuvarlamak
	# eşit aralıkları bozuyordu. Yarıçap, en yakın komşu mesafesinin %45'i ile
	# sınırlı: kontur dahil hiçbir daire komşusuna değmez.
	var radius: float = _seat_radius_norm * scale
	if _min_gap_norm > 0.0:
		radius = minf(radius, _min_gap_norm * scale * 0.45)
	radius = maxf(1.5, radius)
	var inner: float = radius * (1.0 - outline_ratio)
	for i in _dot_positions.size():
		var p: Vector2 = _dot_positions[i]
		var center := origin + Vector2(p.x - 1.0, -p.y) * scale
		draw_circle(center, radius, outline_color, true, -1.0, true)
		draw_circle(center, inner, _dot_colors[i], true, -1.0, true)

	# Toplam vekil sayısı artık _count_plate levhasında (bkz. _build_count_plate).

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
