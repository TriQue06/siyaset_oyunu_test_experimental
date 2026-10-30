class_name TurnSnake
extends Control
## SIRA VURGUSU (0.0.301, konsept B "Altın ve parti rengi, iki yılan", bkz.
## konseptler/il_menusu_ve_sira_konseptleri.html): sırası gelen partinin
## plaketinin çevresinde iki yılan aynı yönde kovalar — biri altın, biri parti
## renginde. (0.0.305: "SIRA" etiketi kaldırıldı.)
## Plaketin (PanelContainer) içine eklenir; çizim içerik payı kadar dışarı taşar
## (outset: sol, üst, sağ, alt). Faz saatten okunur: plaket yeniden kurulsa da
## yılanlar yerinden sıçramaz.

## Bir tam tur süresi (konsept: 2,6 sn).
const PERIOD := 2.6
## Çevrenin yüzdesi olarak yılan boyu ve aralık (konsept: dasharray 22 28).
const DASH := 0.22
const GAP := 0.28
## İkinci yılanın kayması (konsept: -25).
const OFFSET := 0.25
const WIDTH := 4.0
## Yılanlar plaketin kenarından bu kadar dışarıda (konsept: inset -5 px, rect 2,5).
const OUT := 2.5
const RADIUS := 16.0

var party_color := Color.WHITE
## Plaketin içerik payları (sol, üst, sağ, alt): çizim plaketin kenarına oturur.
var outset := Vector4.ZERO
var _path := PackedVector2Array()
var _lengths := PackedFloat32Array()
var _total := 0.0
var _path_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1

func _process(_delta: float) -> void:
	queue_redraw()

func _frame_rect() -> Rect2:
	var pos := Vector2(-outset.x, -outset.y) - Vector2(OUT, OUT)
	var end := size + Vector2(outset.z, outset.w) + Vector2(OUT, OUT)
	return Rect2(pos, end - pos)

## Yuvarlak köşeli dikdörtgenin çevresi: sol üst köşeden saat yönünde noktalar.
func _build_path() -> void:
	var rect := _frame_rect()
	_path_size = size
	_path = PackedVector2Array()
	var r := minf(RADIUS, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -PI * 0.5],
		[rect.end - Vector2(r, r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), PI * 0.5],
		[rect.position + Vector2(r, r), PI],
	]
	for corner in corners:
		for i in 9:
			var a: float = float(corner[1]) + PI * 0.5 * float(i) / 8.0
			_path.append((corner[0] as Vector2) + Vector2(cos(a), sin(a)) * r)
	_path.append(_path[0])
	_lengths = PackedFloat32Array([0.0])
	_total = 0.0
	for i in range(1, _path.size()):
		_total += _path[i].distance_to(_path[i - 1])
		_lengths.append(_total)

## Çevre üzerinde t (0..1) konumundaki nokta.
func _point_at(t: float) -> Vector2:
	var d := fposmod(t, 1.0) * _total
	var i := _lengths.bsearch(d)
	i = clampi(i, 1, _path.size() - 1)
	var seg := _lengths[i] - _lengths[i - 1]
	var k := 0.0 if seg <= 0.0 else (d - _lengths[i - 1]) / seg
	return _path[i - 1].lerp(_path[i], k)

func _draw_dash(start: float, length: float, color: Color) -> void:
	var points := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		points.append(_point_at(start + length * float(i) / float(steps)))
	draw_polyline(points, color, WIDTH, true)
	draw_circle(points[0], WIDTH * 0.5, color, true, -1.0, true)
	draw_circle(points[points.size() - 1], WIDTH * 0.5, color, true, -1.0, true)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _path.is_empty() or _path_size != size:
		_build_path()
	var phase := fposmod(float(Time.get_ticks_msec()) / 1000.0 / PERIOD, 1.0)
	# Desen çevre boyunca tekrar eder (22 + 28 = %50): her renkten iki yılan.
	for k in 2:
		var base := phase + float(k) * (DASH + GAP)
		_draw_dash(base, DASH, UiTheme.GOLD)
		_draw_dash(base + OFFSET, DASH, party_color)
	# 0.0.305: "SIRA" etiketi kalktı; yılan animasyonu yeterli.

## Sağ üstte altın "SIRA" etiketi (konsept .tag), kartın üst kenarında.
func _draw_tag() -> void:
	var font := UiTheme.mono(true)
	var font_size := 11
	var text := L.t("SIRA")
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box_size := text_size + Vector2(14, 8)
	var rect := _frame_rect()
	# Etiket kartın üst kenarına oturur (vekil sayısının üstüne binmez).
	var pos := Vector2(rect.end.x - box_size.x - 10.0, rect.position.y - box_size.y * 0.6)
	var lip := StyleBoxFlat.new()
	lip.bg_color = UiTheme.GOLD_DIM
	lip.set_corner_radius_all(7)
	draw_style_box(lip, Rect2(pos + Vector2(0, 2), box_size))
	var face := StyleBoxFlat.new()
	face.bg_color = UiTheme.GOLD
	face.set_corner_radius_all(7)
	draw_style_box(face, Rect2(pos, box_size))
	draw_string(font, pos + Vector2(7, 4 + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("4a3203"))
