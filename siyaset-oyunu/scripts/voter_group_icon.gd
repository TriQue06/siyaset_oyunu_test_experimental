class_name VoterGroupIcon
extends Control
## Seçmen grubunun simgesi: grubun renginde karo + üstünde grubun Material
## simgesi (GroupIconSvg; dosyaya bağlı değil). Simge adı ve renk VoterGroups'tan.

var group: String = ""
## Rozet yerine sadece sembol (renkli) çizilsin mi?
var bare: bool = false

static func make(group_id: String, size_px: float = 22.0, bare_icon: bool = false) -> VoterGroupIcon:
	var icon := VoterGroupIcon.new()
	icon.group = group_id
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.bare = bare_icon
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func set_group(group_id: String) -> void:
	group = group_id
	queue_redraw()

func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 0.0 or group == "":
		return
	var c := Vector2(size.x * 0.5, size.y * 0.5)
	var r := side * 0.5
	var ink := Color.WHITE
	if bare:
		ink = VoterGroups.color(group)
		draw_symbol(self, VoterGroups.icon(group), c, r * 0.9, ink)
		return
	# KESKİN KARO (0.0.186): köşeli, grubun renginde; sembol karonun çoğunu kaplar.
	var inner := draw_tile(self, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), VoterGroups.color(group))
	draw_symbol(self, VoterGroups.icon(group), c - Vector2(0, inner * 0.06), inner * 0.78, ink)

## PUL (0.0.265): grubun renginde yuvarlak, konturs dolgu. Sembolün ölçeği
## için yarıçap döner.
static func draw_tile(canvas: CanvasItem, rect: Rect2, color: Color) -> float:
	var r := minf(rect.size.x, rect.size.y) * 0.5
	canvas.draw_circle(rect.get_center(), r, color, true, -1.0, true)
	return r * 0.92

## MADALYON (eski, harita lejantı gibi yerler için): grubun renginde dolu daire, koyu kontur, dışta grubun renginde
## yarı saydam hale (16 px ve üstünde) ve üstte hafif parlama. İç dairenin
## yarıçapını döndürür (sembol buna göre ölçeklenir).
static func draw_medallion(canvas: CanvasItem, c: Vector2, r: float, color: Color) -> float:
	var body := r
	if r * 2.0 >= 16.0:
		var halo := maxf(1.5, r * 0.12)
		canvas.draw_arc(c, r - halo * 0.5, 0.0, TAU, 40, Color(color, 0.45), halo, true)
		body = r - halo - 1.0
	# 0.0.265: kontursuz yuvarlak pul.
	canvas.draw_circle(c, body, color, true, -1.0, true)
	return body

## Sembolü başka bir CanvasItem'a da çizebilmek için (harita lejantı vb.).
## 0.0.243: semboller Material simgeleri (GroupIconSvg); c merkezli, yarı
## genişliği s olan kareye ink renginde çizilir.
static func draw_symbol(canvas: CanvasItem, icon_name: String, c: Vector2, s: float, ink: Color) -> void:
	# Ekrandaki gerçek piksel boyu (pencere ölçeği dahil): simge o boyda rasterleşir.
	var xform := canvas.get_viewport().get_final_transform() * canvas.get_global_transform_with_canvas()
	var px := int(ceil(s * 2.0 * maxf(0.01, xform.get_scale().x)))
	var tex := GroupIconSvg.texture_px(icon_name, px)
	if tex == null:
		return
	canvas.draw_texture_rect(tex, Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), false, ink)
