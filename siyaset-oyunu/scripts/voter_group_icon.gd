class_name VoterGroupIcon
extends Control
## Seçmen grubunun simgesi: grubun renginde karo + üstünde grubun Material
## simgesi (GroupIconSvg; dosyaya bağlı değil). Simge adı ve renk VoterGroups'tan.

var group: String = ""
## Rozet yerine sadece sembol (renkli) çizilsin mi?
var bare: bool = false
## Pul ve sembol rengi değiştirilebilir (bantta kriz: koyu pul, hardal sembol).
var tile_override := Color(0, 0, 0, 0)
var ink_override := Color(0, 0, 0, 0)

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
	if ink_override.a > 0.0:
		ink = ink_override
	var tile := tile_override if tile_override.a > 0.0 else VoterGroups.color(group)
	# 0.0.268: PARTİ LOGOSU GİBİ 3B PUL (PartyBadge ile aynı katmanlar).
	draw_style_box(pawn_style(tile, side), Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	draw_symbol(self, VoterGroups.icon(group), c - Vector2(0, side * 0.03), r * 0.58, ink)

## Parti logosunun pulu (PartyBadge.build ile birebir): tepesi açık renge
## geçen dolgu, altta iç koyuluk, koyu kalınlık ve yumuşak gölge.
static func pawn_style(color: Color, side: float) -> BoardBox:
	var style := BoardBox.new()
	style.fill = color.lerp(Color.WHITE, 0.4)
	style.fill_bottom = color
	style.set_radius(side * 0.5)
	style.shade_size = side * 0.087
	style.shade_color = Color(0, 0, 0, 0.22)
	style.lips = [[side * 0.087, color.lerp(Color.BLACK, 0.45)]]
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_offset = Vector2(0, side * 0.13)
	style.shadow_size = side * 0.09
	return style

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
