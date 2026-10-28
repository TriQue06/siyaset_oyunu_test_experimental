class_name InvestRequestMarkers
extends Node2D
## YATIRIM İSTEĞİ İŞARETİ (0.0.283, konsept "Pasta zamanlayıcı"): ProvinceMap'in
## çocuğu, vekil pullarının üstünde. İstek yapan ilin ortasında krem bir
## tabak; üstünde oynama sırasındaki oyuncu sayısı kadar dilim. Kalan sıralar
## teal, geçenler kum rengi; her sıra bitince bir dilim kalkar, son sırada
## dilimler kırmızı. Tabağın ortasında altın para, altında istenen tutar.
## Tabağın arkasından içi dolu, solarak büyüyen altın dalgalar yayılır (son
## sırada kırmızı ve hızlı). Yatırım yapılınca yeşil onay işareti zıplar,
## "yapıldı" yazar ve söner. Harita biriminde vektörle çizilir; yazılar
## ekranın o anki ölçeğinde (bulanıklaşmasın diye).

## Konsept pikseli -> harita birimi.
const K := 0.62
## Konseptteki pul yarıçapı (R) ve türetilen ölçüler.
const R := 17.0
const PLATE := R + 9.0
const WEDGE := R + 7.0
const COIN := R - 3.0
const WAVE_FROM := R + 8.0
const WAVE_TO := R + 36.0
const DONE_SECONDS := 2.0

const TEAL := Color("1F6E70")
const RED := Color("D93636")
const EMPTY := Color("EFE2C0")
const CREAM := Color("FFFAF0")
const LINE := Color("E3D5B0")
const PLATE_SHADOW := Color("8F744A")
const GOLD := Color("F2B632")
const GOLD_DIM := Color("B58312")
const GOLD_LIGHT := Color("FFE08A")
const COIN_INK := Color("4A3203")
const GREEN := Color("2FA866")
const GREEN_DARK := Color("14603A")
const GREEN_TEXT := Color("1F8A4C")
const INK := Color("2D2A26")

var _t := 0.0
## province_id -> yerel saat (yapıldı animasyonu ilk görüldüğü an).
var _done_at: Dictionary = {}

@onready var _province_map = get_parent()

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	if CardManager.has_approval() and not CardManager.invest_requests.is_empty():
		queue_redraw()
	elif not _done_at.is_empty():
		_done_at.clear()
		queue_redraw()

func _draw() -> void:
	if not CardManager.has_approval():
		return
	var turns := CardManager.request_turns()
	var left := turns.x
	var total := turns.y
	var screen_scale := get_global_transform_with_canvas().get_scale().x
	var isolated := String(_province_map.get("isolated_id")) if _province_map != null else ""
	for province_id in CardManager.invest_requests.keys():
		var id := String(province_id)
		if isolated != "" and isolated != id:
			continue
		var req: Dictionary = CardManager.invest_requests[province_id]
		var pos := GameMap.center_of(id)
		if bool(req.get("done", false)):
			if not _done_at.has(id):
				_done_at[id] = _t
			var dt := _t - float(_done_at[id])
			if dt < DONE_SECONDS:
				_draw_done(pos, dt, screen_scale)
			continue
		_draw_request(pos, float(req["amount"]), left, total, screen_scale)

func _draw_request(pos: Vector2, amount: float, left: int, total: int, screen_scale: float) -> void:
	var urgent := left <= 1
	# Dalgalar: iki katman, içi dolu, büyüdükçe solar.
	var period := 1.2 if urgent else 2.0
	var wave := RED if urgent else GOLD
	for i in 2:
		var f := fmod(_t / period + float(i) / 2.0, 1.0)
		draw_circle(pos, (WAVE_FROM + (WAVE_TO - WAVE_FROM) * f) * K, Color(wave, 0.5 * (1.0 - f) * (1.0 - f)), true, -1.0, true)
	# Tabak: altta koyu gölge, krem yüz ve ince çizgi.
	draw_circle(pos + Vector2(0, 2.5 * K), PLATE * K, PLATE_SHADOW, true, -1.0, true)
	draw_circle(pos, PLATE * K, CREAM, true, -1.0, true)
	draw_arc(pos, PLATE * K, 0.0, TAU, 48, LINE, 1.5 * K, true)
	# Dilimler: oyuncu sayısı kadar; kalanlar teal (sonda kırmızı), geçenler kum.
	var fill := RED if urgent else TEAL
	var step := TAU / float(total)
	for i in total:
		var a0 := -PI * 0.5 + float(i) * step
		var points := PackedVector2Array([pos])
		var seg := maxi(4, int(ceil(48.0 / float(total))))
		for k in seg + 1:
			var a := a0 + step * float(k) / float(seg)
			points.append(pos + Vector2(cos(a), sin(a)) * WEDGE * K)
		draw_colored_polygon(points, fill if i < left else EMPTY)
	if total > 1:
		for i in total:
			var a := -PI * 0.5 + float(i) * step
			draw_line(pos, pos + Vector2(cos(a), sin(a)) * WEDGE * K, CREAM, 2.0 * K, true)
	draw_arc(pos, WEDGE * K, 0.0, TAU, 48, CREAM, 2.0 * K, true)
	_draw_coin(pos, COIN * K)
	_draw_tag(pos + Vector2(0, (R + 14.0) * K), GameRules.amount(amount), INK, screen_scale)

## Altın para: koyu alt kenar, iç halka, para simgesi ve parlaklık.
func _draw_coin(pos: Vector2, r: float) -> void:
	draw_circle(pos + Vector2(0, r * 0.2), r, GOLD_DIM, true, -1.0, true)
	draw_circle(pos, r, GOLD, true, -1.0, true)
	draw_arc(pos, r * 0.72, 0.0, TAU, 32, GOLD_LIGHT, r * 0.13, true)
	var s := r / 17.0
	draw_arc(pos, 5.2 * s, 0.0, TAU, 24, COIN_INK, 2.2 * s, true)
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		draw_line(pos + d * 7.0 * s, pos + d * 3.6 * s, COIN_INK, 2.2 * s, true)
	# Parlaklık: sol üstte eğik küçük elips.
	var hl := pos + Vector2(-r * 0.38, -r * 0.42)
	var ellipse := PackedVector2Array()
	var rot := deg_to_rad(-35.0)
	for k in 16:
		var a := TAU * float(k) / 16.0
		ellipse.append(hl + Vector2(cos(a) * r * 0.22, sin(a) * r * 0.12).rotated(rot))
	draw_colored_polygon(ellipse, Color(1, 1, 1, 0.55))

## Tutar etiketi: krem hap, ince çizgi, altında gölge; yazı ekran ölçeğinde.
## top_center: etiketin üst kenarının ortası (harita birimi).
func _draw_tag(top_center: Vector2, text: String, color: Color, screen_scale: float, alpha: float = 1.0) -> void:
	var font := UiTheme.mono(true)
	var px := maxi(1, int(roundf(12.0 * K * screen_scale)))
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / screen_scale
	var w := text_w + 16.0 * K
	var h := 18.0 * K
	var rect := Rect2(top_center - Vector2(w * 0.5, 0), Vector2(w, h))
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(roundf(6.0 * K)))
	box.anti_aliasing = true
	box.bg_color = Color(0, 0, 0, 0.18 * alpha)
	draw_style_box(box, Rect2(rect.position + Vector2(0, 2.0 * K), rect.size))
	box.bg_color = Color(CREAM, alpha)
	box.border_color = Color(LINE, alpha)
	box.set_border_width_all(1)
	draw_style_box(box, rect)
	var baseline := top_center + Vector2(-text_w * 0.5, h * 0.5 + font.get_ascent(px) * 0.36 / screen_scale)
	draw_set_transform(baseline, 0.0, Vector2.ONE / screen_scale)
	draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(color, color.a * alpha))
	draw_set_transform(Vector2.ZERO)

## Yatırım yapıldı: yeşil parıltı, zıplayan onay pulu, "yapıldı" etiketi; sonra söner.
func _draw_done(pos: Vector2, dt: float, screen_scale: float) -> void:
	var fade := 1.0 - clampf((dt - 1.4) / 0.6, 0.0, 1.0)
	var r := R * K
	var glow := (R + 10.0) * K * minf(1.0, dt / 0.4) * 2.0
	draw_circle(pos, glow, Color(GREEN, 0.4 * (1.0 - clampf(dt / 0.6, 0.0, 1.0)) * fade), true, -1.0, true)
	var k := _back(dt / 0.5)
	draw_set_transform(pos, 0.0, Vector2.ONE * maxf(k, 0.001))
	draw_circle(Vector2(0, 3.0 * K), r, Color(GREEN_DARK, fade), true, -1.0, true)
	draw_circle(Vector2.ZERO, r, Color(GREEN, fade), true, -1.0, true)
	draw_polyline(PackedVector2Array([Vector2(-7, 0) * K, Vector2(-2, 5) * K, Vector2(7, -5) * K]), Color(1, 1, 1, fade), 3.5 * K, true)
	draw_circle(Vector2(-7, 0) * K, 1.75 * K, Color(1, 1, 1, fade), true, -1.0, true)
	draw_circle(Vector2(7, -5) * K, 1.75 * K, Color(1, 1, 1, fade), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	if fade > 0.0:
		_draw_tag(pos + Vector2(0, (R + 12.0) * K), L.t("yapıldı"), GREEN_TEXT, screen_scale, fade)

static func _back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 + 3.0 * pow(x - 1.0, 3.0) + 2.0 * pow(x - 1.0, 2.0)
