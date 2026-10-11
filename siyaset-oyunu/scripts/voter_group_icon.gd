class_name VoterGroupIcon
extends Control
## Seçmen grubunun simgesi: grubun renginde yuvarlak rozet + üstünde basit,
## vektörle çizilen bir sembol (yazı tipine/ikon kütüphanesine bağlı değil,
## boş kare çıkmaz). Simge adı ve renk VoterGroups'tan gelir.

var group: String = ""
## Rozet yerine sadece sembol (renkli) çizilsin mi?
var bare: bool = false

static func make(group_id: String, size_px: float = 22.0, bare_icon: bool = false) -> VoterGroupIcon:
	var icon := VoterGroupIcon.new()
	icon.group = group_id
	icon.bare = bare_icon
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.tooltip_text = VoterGroups.title(group_id)
	return icon

func set_group(group_id: String) -> void:
	group = group_id
	tooltip_text = VoterGroups.title(group_id)
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
	else:
		draw_circle(c, r, VoterGroups.color(group))
		draw_arc(c, r - 0.5, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 1.0, true)
	draw_symbol(self, VoterGroups.icon(group), c, r * (0.62 if not bare else 0.9), ink)

## Sembolü başka bir CanvasItem'a da çizebilmek için (harita lejantı vb.).
static func draw_symbol(canvas: CanvasItem, icon_name: String, c: Vector2, s: float, ink: Color) -> void:
	var w := maxf(1.2, s * 0.16)
	match icon_name:
		"hardhat":
			# Baret: yarım kubbe + siperlik.
			canvas.draw_arc(c + Vector2(0, s * 0.15), s * 0.62, PI, TAU, 16, ink, w * 1.6, true)
			var pts := PackedVector2Array()
			for i in 17:
				var a := PI + PI * float(i) / 16.0
				pts.append(c + Vector2(0, s * 0.15) + Vector2(cos(a), sin(a)) * s * 0.62)
			canvas.draw_colored_polygon(pts, ink)
			canvas.draw_line(c + Vector2(-s * 0.9, s * 0.2), c + Vector2(s * 0.9, s * 0.2), ink, w * 1.6, true)
			canvas.draw_line(c + Vector2(0, -s * 0.47), c + Vector2(0, s * 0.1), Color(0, 0, 0, 0.35), w, true)
		"briefcase":
			var body := Rect2(c + Vector2(-s * 0.8, -s * 0.35), Vector2(s * 1.6, s * 1.0))
			canvas.draw_rect(body, ink, true)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.62), Vector2(s * 0.64, s * 0.3)), ink, false, w)
			canvas.draw_line(c + Vector2(-s * 0.8, s * 0.05), c + Vector2(s * 0.8, s * 0.05), Color(0, 0, 0, 0.35), w, true)
		"gradcap":
			var top := PackedVector2Array([c + Vector2(0, -s * 0.7), c + Vector2(s * 0.95, -s * 0.2),
				c + Vector2(0, s * 0.3), c + Vector2(-s * 0.95, -s * 0.2)])
			canvas.draw_colored_polygon(top, ink)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.5, -s * 0.05), Vector2(s * 1.0, s * 0.55)), ink, true)
			canvas.draw_line(c + Vector2(s * 0.75, -s * 0.25), c + Vector2(s * 0.75, s * 0.55), ink, w, true)
		"heart":
			canvas.draw_circle(c + Vector2(-s * 0.36, -s * 0.2), s * 0.4, ink)
			canvas.draw_circle(c + Vector2(s * 0.36, -s * 0.2), s * 0.4, ink)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.74, -s * 0.08),
				c + Vector2(s * 0.74, -s * 0.08), c + Vector2(0, s * 0.8)]), ink)
		"dome":
			# Nötr bir ibadet yapısı silueti: kubbe + gövde + tepe.
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.7, s * 0.05), Vector2(s * 1.4, s * 0.65)), ink, true)
			var pts := PackedVector2Array()
			for i in 17:
				var a := PI + PI * float(i) / 16.0
				pts.append(c + Vector2(0, s * 0.08) + Vector2(cos(a) * s * 0.58, sin(a) * s * 0.6))
			canvas.draw_colored_polygon(pts, ink)
			canvas.draw_line(c + Vector2(0, -s * 0.52), c + Vector2(0, -s * 0.9), ink, w, true)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.16, s * 0.3), Vector2(s * 0.32, s * 0.4)), Color(0, 0, 0, 0.35), true)
		"rainbow":
			var bands := [Color("#ff5a5a"), Color("#ffb03a"), Color("#ffe14d"), Color("#4fd27a"), Color("#4aa8ff"), Color("#a46bff")]
			var inner := ink == Color.WHITE
			for i in bands.size():
				var rr := s * (0.92 - 0.11 * i)
				canvas.draw_arc(c + Vector2(0, s * 0.35), rr, PI, TAU, 18, ink if inner else bands[i], w * 0.75, true)
			if inner:
				canvas.draw_arc(c + Vector2(0, s * 0.35), s * 0.6, PI, TAU, 18, Color(1, 1, 1, 0.9), w * 2.4, true)
		"pin":
			canvas.draw_circle(c + Vector2(0, -s * 0.22), s * 0.5, ink)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.45, -s * 0.02),
				c + Vector2(s * 0.45, -s * 0.02), c + Vector2(0, s * 0.85)]), ink)
			canvas.draw_circle(c + Vector2(0, -s * 0.22), s * 0.2, Color(0, 0, 0, 0.35))
		"flag":
			canvas.draw_line(c + Vector2(-s * 0.62, -s * 0.85), c + Vector2(-s * 0.62, s * 0.85), ink, w * 1.2, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.8),
				c + Vector2(s * 0.8, -s * 0.55), c + Vector2(s * 0.45, -s * 0.25),
				c + Vector2(s * 0.8, s * 0.05), c + Vector2(-s * 0.55, s * 0.05)]), ink)
		_:
			canvas.draw_circle(c, s * 0.4, ink)
