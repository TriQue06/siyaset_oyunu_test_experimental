class_name ApprovalGauge
extends Control
## HÜKÜMET ONAYI GÖSTERGESİ (0.0.282, konsept "İbre"): sağ sütunun Hükümet
## sekmesinde meclis diyagramının altında. Krem kart; solda kırmızı / kum /
## yeşil bantlı yarım kadran ve ibre, sağda "HÜKÜMET ONAYI", büyük yüzde ve
## son tur sonu değişiminin etiketi (yeşil yukarı / kırmızı aşağı üçgen).
## Hepsi vektörle çizilir. Onay tur sonunda değişince ibre yeni değere
## yaylanarak döner, etiket zıplar.

const H := 62.0
const PAD_X := 10.0
## Kadran (konseptteki 88 x 50 SVG): merkez (44, 44), yarıçap 34, bant 10.
const DIAL_W := 88.0
const DIAL_H := 50.0
const DIAL_R := 34.0
const BAND := 10.0
const NEEDLE := 30.0

const CARD := Color("FFFAF0")
const LINE := Color("E3D5B0")
const LIP := Color("C9B689")
const LOW := Color("EF9A8F")
const MID := Color("E3D5B0")
const HIGH := Color("8FD3A8")
const INK := Color("2D2A26")
const MUTED := Color("7A7166")
const TONE_LOW := Color("D93636")
const TONE_MID := Color("1F6E70")
const TONE_HIGH := Color("1F8A4C")
const UP := Color("1F8A4C")
const UP_LIP := Color("14603A")
const DOWN := Color("D93636")
const DOWN_LIP := Color("A12424")

var shown := 50.0:
	set(v):
		shown = v
		queue_redraw()
var chip_scale := 1.0:
	set(v):
		chip_scale = v
		queue_redraw()
var _target := -1.0
var _delta := 0.0
var _tween: Tween

func _init() -> void:
	custom_minimum_size = Vector2(0, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Değer değiştiyse ibre eski değerden yeniye döner (ilk gösterimde atlamaz).
func set_value(value: float, delta: float, animate: bool = true) -> void:
	if is_equal_approx(value, _target) and is_equal_approx(delta, _delta):
		return
	var first := _target < 0.0
	_target = value
	_delta = delta
	if _tween != null:
		_tween.kill()
	if first or not animate or not is_visible_in_tree():
		shown = value
		chip_scale = 1.0
		return
	shown = value - delta if absf(delta) > 0.01 else shown
	chip_scale = 0.6
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "shown", value, 1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)
	_tween.tween_property(self, "chip_scale", 1.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)

static func tone(v: float) -> Color:
	return TONE_LOW if v < 45.0 else (TONE_HIGH if v > 55.0 else TONE_MID)

func _draw() -> void:
	# Kart: 1,5 px iç çizgi, altta 3 px dudak.
	var card := StyleBoxFlat.new()
	card.bg_color = CARD
	card.set_corner_radius_all(11)
	card.border_color = LINE
	card.set_border_width_all(2)
	card.anti_aliasing = true
	var lip := card.duplicate() as StyleBoxFlat
	lip.bg_color = LIP
	lip.border_color = LIP
	draw_style_box(lip, Rect2(0, 3, size.x, H - 3))
	draw_style_box(card, Rect2(0, 0, size.x, H - 3))

	var top := (H - 3.0 - DIAL_H) * 0.5
	var c := Vector2(PAD_X + 44.0, top + 44.0)
	_band(c, 0.0, 0.4, LOW)
	_band(c, 0.4, 0.6, MID)
	_band(c, 0.6, 1.0, HIGH)
	draw_arc(c, DIAL_R, PI + 0.495 * PI, PI + 0.505 * PI, 4, INK, 12.0, true)
	var v := clampf(shown, -4.0, 104.0)
	var a := PI + v / 100.0 * PI
	var tip := c + Vector2(cos(a), sin(a)) * NEEDLE
	_needle(c + Vector2(0, 1.5), tip + Vector2(0, 1.5), 4.0, Color(0, 0, 0, 0.2))
	_needle(c, tip, 3.6, INK)
	var t := tone(clampf(shown, 0.0, 100.0))
	draw_circle(c, 6.5 + 1.0, CARD, true, -1.0, true)
	draw_circle(c, 6.5 - 1.0, t, true, -1.0, true)

	# Yazılar: etiket, yüzde ve değişim etiketi (kadranın sağında, dikeyde ortalı).
	var x := PAD_X + DIAL_W + 10.0
	var label_font := UiTheme.body_black()
	var value_font := UiTheme.mono(true)
	var label_size := 9
	var value_size := 24
	var block_h := 9.0 + 4.0 + 24.0
	var y0 := (H - 3.0 - block_h) * 0.5
	_spaced(label_font, Vector2(x, y0 + label_font.get_ascent(label_size)), L.t("HÜKÜMET ONAYI"), label_size, 0.7, MUTED)
	var text := L.t("%%%s") % str(int(roundf(clampf(_target if _target >= 0.0 else shown, 0.0, 100.0))))
	var vy := y0 + 9.0 + 4.0 + value_font.get_ascent(value_size) * 0.92
	draw_string(value_font, Vector2(x, vy), text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size, t)
	var step := int(roundf(absf(_delta)))
	if step > 0:
		var w := value_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size).x
		_chip(Vector2(x + w + 6.0, vy - value_font.get_ascent(value_size) * 0.5), _delta > 0.0, step)

func _band(c: Vector2, p0: float, p1: float, color: Color) -> void:
	draw_arc(c, DIAL_R, PI + p0 * PI, PI + p1 * PI, 24, color, BAND, true)

func _needle(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	draw_line(from, to, color, width, true)
	draw_circle(from, width * 0.5, color, true, -1.0, true)
	draw_circle(to, width * 0.5, color, true, -1.0, true)

## Harf aralıklı yazı (konseptte letter-spacing .08em).
func _spaced(font: Font, pos: Vector2, text: String, font_size: int, spacing: float, color: Color) -> void:
	for ch in text:
		draw_string(font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		pos.x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing

## Artış / azalış etiketi: renkli hap, beyaz üçgen ve sayı; altında koyu dudak.
## mid_left: hapın sol kenarının dikey ortası.
func _chip(mid_left: Vector2, up: bool, step: int) -> void:
	var font := UiTheme.mono(true)
	var fsize := 11
	var num := str(step)
	var tw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var w := 5.0 + 8.0 + 2.0 + tw + 5.0
	var h := 17.0
	var origin := mid_left + Vector2(0, -h * 0.5)
	draw_set_transform(origin + Vector2(w, h) * 0.5, 0.0, Vector2.ONE * chip_scale)
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(6)
	box.anti_aliasing = true
	box.bg_color = UP_LIP if up else DOWN_LIP
	draw_style_box(box, Rect2(r.position + Vector2(0, 2), r.size))
	box.bg_color = UP if up else DOWN
	draw_style_box(box, r)
	var tx := r.position.x + 5.0
	var cy := 0.0
	var tri := PackedVector2Array([Vector2(tx + 4.0, cy - 3.6), Vector2(tx + 7.6, cy + 3.0), Vector2(tx + 0.4, cy + 3.0)]) if up \
		else PackedVector2Array([Vector2(tx + 4.0, cy + 3.6), Vector2(tx + 7.6, cy - 3.0), Vector2(tx + 0.4, cy - 3.0)])
	draw_colored_polygon(tri, Color.WHITE)
	draw_string(font, Vector2(tx + 10.0, cy + font.get_ascent(fsize) * 0.38), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)
	draw_set_transform(Vector2.ZERO)
