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
const SEAT_RADIUS_FACTOR := 0.9  # orijinal JS: SRF

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
const BASELINE_GAP := 0.0
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

## KOLTUKLAR TEK MultiMesh İLE ÇİZİLİR (tek çizim çağrısı). Eskiden koltuk başına iki draw_circle vardı: 500 koltuk =
## ~2000 çizim çağrısı/kare. Masaüstünde native GL bunu yutuyordu ama WebGL2'de
## her çağrı tarayıcı katmanından geçtiği için seçim gecesi 1-2 FPS'e düşüyordu.
var _seat_mmi: MultiMeshInstance2D
## KOLTUK SHADER'I: doku yok. Her piksel daireye uzaklığını kendisi hesaplar,
## kenar ekranda tam 1 piksel yumuşatılır (fwidth): hangi ölçekte ve hangi
## kesirli konumda olursa olsun daire hem keskin hem pürüzsüz. Kontur aynı
## çizimde: iç dolgu instance rengi, dış halka outline_color.
## (Önceki iki deneme: büyük dokuyu küçültmek bulanık, piksel boyutunda doku
## + en yakın piksel ise tırtıklı ve düzensiz görünüyordu.)
const SEAT_SHADER := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.07, 0.08, 0.1, 1.0);
uniform float inner_ratio = 0.84;
void fragment() {
	// d: merkezden uzaklık (kenar = 1). px: bir ekran pikselinin d cinsinden boyu.
	float d = length(UV - vec2(0.5)) * 2.0;
	float px = max(fwidth(d), 0.0001);
	// Kenara piksel cinsinden uzaklık -> alan kaplaması (tam 1 piksellik geçiş).
	float inside = (1.0 - d) / px;
	float outer = clamp(inside + 0.5, 0.0, 1.0);
	// Kontur en az 1 piksel: küçük koltuklarda yumuşatmanın içinde kaybolmasın.
	float ring = max(1.0, (1.0 - inner_ratio) / px);
	float inner = clamp(inside - ring + 0.5, 0.0, 1.0);
	vec4 fill = COLOR;
	COLOR = vec4(mix(outline_color.rgb, fill.rgb, inner), outer * mix(outline_color.a, fill.a, inner));
}
"""
static var _seat_material: ShaderMaterial = null
static var _white_texture: Texture2D = null
## Yerleşim (konum/yarıçap) sadece boyut değişince kurulur; renkler her
## set_results'ta güncellenir.
var _instances_built_for := Vector2.ZERO

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
	# Konumlar sadece boyut ya da koltuk sayısı değişince yeniden kurulur;
	# seçim gecesinde her karede gelen çağrıda sadece renkler güncellenir.
	if _instances_built_for != size or _seat_mmi == null 			or _seat_mmi.multimesh == null or _seat_mmi.multimesh.instance_count != _dot_positions.size():
		_rebuild_instances()
	else:
		_update_instance_colors()

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
	get_viewport().size_changed.connect(_rebuild_instances)
	_build_count_plate()
	resized.connect(_place_count_plate)
	resized.connect(_rebuild_instances)
	_rebuild_instances()

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

## Koltuk yarıçapı (piksel). Yarıçap, en yakın komşu mesafesinin %48'i ile
## sınırlı: kontur dahil hiçbir daire komşusuna değmez.
func _seat_radius_px(scale: float) -> float:
	var radius: float = _seat_radius_norm * scale
	if _min_gap_norm > 0.0:
		radius = minf(radius, _min_gap_norm * scale * 0.48)
	return maxf(1.5, radius)

func _ensure_multimeshes() -> void:
	if _seat_mmi != null:
		return
	if _seat_material == null:
		var shader := Shader.new()
		shader.code = SEAT_SHADER
		_seat_material = ShaderMaterial.new()
		_seat_material.shader = shader
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(image)
	_seat_mmi = MultiMeshInstance2D.new()
	_seat_mmi.texture = _white_texture
	# Her diyagram kendi kontur ayarını taşısın: malzeme kopyalanır.
	_seat_mmi.material = _seat_material.duplicate()
	add_child(_seat_mmi)

## Koltuk konumları ve yarıçapları — sadece kontrol boyutu değişince.
func _rebuild_instances() -> void:
	_ensure_multimeshes()
	var count := _dot_positions.size()
	if _seat_mmi.multimesh == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mm.mesh = quad
		_seat_mmi.multimesh = mm
	_seat_mmi.multimesh.instance_count = count
	_seat_mmi.visible = count > 0
	if count == 0:
		return
	var scale: float = minf(size.x * 0.5, size.y * 0.96)
	var origin := _arc_origin()
	var radius := _seat_radius_px(scale)
	var material := _seat_mmi.material as ShaderMaterial
	material.set_shader_parameter("outline_color", outline_color)
	material.set_shader_parameter("inner_ratio", 1.0 - outline_ratio)
	for i in count:
		var p: Vector2 = _dot_positions[i]
		var center := origin + Vector2(p.x - 1.0, -p.y) * scale
		_seat_mmi.multimesh.set_instance_transform_2d(i,
			Transform2D(0.0, Vector2(radius * 2.0, radius * 2.0), 0.0, center))
	_instances_built_for = size
	_update_instance_colors()

## Parti renkleri — her set_results'ta (seçim gecesinde sık sık) çağrılır.
func _update_instance_colors() -> void:
	if _seat_mmi == null or _seat_mmi.multimesh == null:
		return
	var count: int = mini(_dot_colors.size(), _seat_mmi.multimesh.instance_count)
	for i in count:
		_seat_mmi.multimesh.set_instance_color(i, _dot_colors[i])

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
