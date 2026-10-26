@tool
class_name BoardBox
extends StyleBox
## MASA OYUNU YÜZEYİ (0.0.266): HTML konseptindeki çok katmanlı CSS
## box-shadow'u birebir çizen vektör StyleBox. Katmanlar (alttan üste):
##   1. yumuşak gölge (shadow_*),
##   2. kalınlık şeritleri (lips: [[y kayması, renk], ...] — CSS "0 6px 0 #renk"),
##   3. dolgu (fill; fill_bottom verilirse dikey geçişli),
##      iç üst parlama (highlight_*) ve iç alt koyuluk (shade_*),
##   4. iç halkalar (rings: [[içeri pay, kalınlık, renk], ...] — CSS "inset 0 0 0 Npx"),
##   5. köşe noktası (dot_*: basılı oyun tahtasındaki küçük işaret).
## offset_y bütün yüzeyi kaydırır (üstüne gelince kalkma, basınca gömülme).

@export var fill := Color.WHITE
@export var fill_bottom := Color(0, 0, 0, 0)
@export var radius_tl := 8.0
@export var radius_tr := 8.0
@export var radius_br := 8.0
@export var radius_bl := 8.0
@export var lips: Array = []
@export var rings: Array = []
@export var highlight_size := 0.0
@export var highlight_color := Color(1, 1, 1, 0.35)
@export var shade_size := 0.0
@export var shade_color := Color(0, 0, 0, 0.12)
@export var shadow_color := Color(0, 0, 0, 0)
@export var shadow_offset := Vector2.ZERO
@export var shadow_size := 0.0
@export var offset_y := 0.0
@export var dot_radius := 0.0
@export var dot_pos := Vector2.ZERO
@export var dot_color := Color.BLACK
## Noktanın altındaki sert gölge (konsept .sech::before: 0 2px 0 #b58312).
@export var dot_lip := 0.0
@export var dot_lip_color := Color.BLACK
## Dolgu hiç çizilmesin (yalnız nokta / halka).
@export var draw_fill := true

const DETAIL := 8

## StyleBoxFlat ile aynı adlar (eski çağrılar için): dolgu ve ilk halkanın rengi.
var bg_color: Color:
	get: return fill
	set(v): fill = v
var border_color: Color:
	get: return (rings[0][2] as Color) if not rings.is_empty() else Color(0, 0, 0, 0)
	set(v):
		if rings.is_empty():
			rings.append([0.0, UiTheme.d(2.0), v])
		else:
			rings[0][2] = v

func set_corner_radius_all(r: float) -> void:
	set_radius(r)

func set_radius(r: float) -> BoardBox:
	radius_tl = r
	radius_tr = r
	radius_br = r
	radius_bl = r
	return self

## Katmanların yaptığı kopya (durumlar arası küçük farklar için).
func copy() -> BoardBox:
	var b := duplicate() as BoardBox
	b.lips = lips.duplicate(true)
	b.rings = rings.duplicate(true)
	return b

func _draw(ci: RID, rect: Rect2) -> void:
	var r := rect
	r.position.y += offset_y
	if shadow_color.a > 0.0 and shadow_size > 0.0:
		var sh := StyleBoxFlat.new()
		sh.bg_color = Color(0, 0, 0, 0)
		sh.shadow_color = shadow_color
		sh.shadow_size = int(ceil(shadow_size))
		sh.shadow_offset = shadow_offset
		_radii(sh, 0.0)
		sh.anti_aliasing = true
		sh.draw(ci, r)
	var ordered := lips.duplicate()
	ordered.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for lip in ordered:
		_poly(ci, Rect2(r.position + Vector2(0, float(lip[0])), r.size), lip[1], lip[1], 0.0)
	# Dolgu: alt koyuluk + üst parlama + gövde.
	var top := fill
	if not draw_fill:
		top = Color(0, 0, 0, 0)
	var bottom := fill_bottom if fill_bottom.a > 0.0 else fill
	if shade_size > 0.0:
		_poly(ci, r, _over(bottom, shade_color), _over(bottom, shade_color), 0.0)
	var body := r
	if shade_size > 0.0:
		body.size.y -= shade_size
	if highlight_size > 0.0:
		_poly(ci, body, _over(top, highlight_color), _over(top, highlight_color), 0.0)
		body.position.y += highlight_size
		body.size.y -= highlight_size
	if draw_fill:
		_poly(ci, body, top, bottom, highlight_size)
	for ring in rings:
		var inset := float(ring[0])
		var fb := StyleBoxFlat.new()
		fb.draw_center = false
		fb.border_color = ring[2]
		fb.set_border_width_all(maxi(1, int(round(float(ring[1])))))
		_radii(fb, inset)
		fb.anti_aliasing = true
		fb.anti_aliasing_size = 0.5
		fb.corner_detail = DETAIL
		var rr := r.grow(-inset)
		if float(ring[1]) < 1.0:
			# İnce çizgi: kalınlık 1 piksel, rengi kalınlıkla seyreltilir.
			fb.border_color = Color(ring[2], (ring[2] as Color).a * float(ring[1]))
		fb.draw(ci, rr)
	if dot_radius > 0.0:
		if dot_lip > 0.0:
			RenderingServer.canvas_item_add_circle(ci, r.position + dot_pos + Vector2(0, dot_lip), dot_radius, dot_lip_color, true)
		RenderingServer.canvas_item_add_circle(ci, r.position + dot_pos, dot_radius, dot_color, true)

static func _over(base: Color, layer: Color) -> Color:
	return base.lerp(Color(layer.r, layer.g, layer.b, 1.0), layer.a)

func _radii(sb: StyleBoxFlat, inset: float) -> void:
	sb.corner_radius_top_left = int(maxf(0.0, radius_tl - inset))
	sb.corner_radius_top_right = int(maxf(0.0, radius_tr - inset))
	sb.corner_radius_bottom_right = int(maxf(0.0, radius_br - inset))
	sb.corner_radius_bottom_left = int(maxf(0.0, radius_bl - inset))
	sb.corner_detail = DETAIL

## Yuvarlak köşeli dikdörtgen çokgeni; renk yukarıdan aşağı top→bottom geçer.
## top_cut: üstteki parlama payı (köşe yarıçapı bu kadar küçülür).
func _poly(ci: RID, rect: Rect2, top: Color, bottom: Color, top_cut: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var h := minf(rect.size.x, rect.size.y) * 0.5
	var rtl := clampf(radius_tl - top_cut, 0.0, h)
	var rtr := clampf(radius_tr - top_cut, 0.0, h)
	var rbr := clampf(radius_br, 0.0, h)
	var rbl := clampf(radius_bl, 0.0, h)
	var pts := PackedVector2Array()
	_arc(pts, rect.position + Vector2(rtl, rtl), rtl, PI, PI * 1.5)
	_arc(pts, Vector2(rect.end.x - rtr, rect.position.y + rtr), rtr, PI * 1.5, TAU)
	_arc(pts, rect.end - Vector2(rbr, rbr), rbr, 0.0, PI * 0.5)
	_arc(pts, Vector2(rect.position.x + rbl, rect.end.y - rbl), rbl, PI * 0.5, PI)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		cols[i] = top.lerp(bottom, clampf((pts[i].y - rect.position.y) / rect.size.y, 0.0, 1.0))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)

static func _arc(pts: PackedVector2Array, c: Vector2, r: float, a0: float, a1: float) -> void:
	if r <= 0.01:
		pts.append(c)
		return
	for i in DETAIL + 1:
		var a := lerpf(a0, a1, float(i) / DETAIL)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
