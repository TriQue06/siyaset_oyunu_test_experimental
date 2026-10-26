class_name TableSurface
extends RefCounted
## MASA YÜZEYLERİ (0.0.266): HTML konseptindeki yeşil çuha zemin ve ahşap
## bant / masa. Hepsi çizimle (geçiş, çizgi); boyuttan bağımsız keskin.

## Ekranı kaplayan yeşil çuha (en alta eklenir).
static func felt() -> Control:
	var c := Felt.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Ahşap şerit. kind: "band" (üst bant) | "desk" (alt masa).
static func wood(kind: String) -> Control:
	var c := Wood.new()
	c.kind = kind
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func _radial(stops: Array, from: Vector2, to: Vector2) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 512
	tex.height = 512
	return tex

static func _linear(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	return tex

## Yeşil çuha: radyal geçiş (50%, 40%), ince keçe dokusu, kenar kararması.
class Felt extends Control:
	static var _base: GradientTexture2D
	static var _vignette: GradientTexture2D
	static var _grain: NoiseTexture2D

	func _ready() -> void:
		resized.connect(queue_redraw)
		if _base == null:
			_base = TableSurface._radial([[0.0, Color("2E7A55")], [0.55, Color("1D5A3D")], [1.0, Color("0F3524")]],
				Vector2(0.5, 0.4), Vector2(1.28, 0.4))
			_vignette = TableSurface._radial([[0.0, Color(0, 0, 0, 0)], [0.5, Color(0, 0, 0, 0)], [1.0, Color(0, 0, 0, 0.45)]],
				Vector2(0.5, 0.45), Vector2(1.24, 0.45))
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
			noise.frequency = 0.35
			noise.fractal_octaves = 3
			_grain = NoiseTexture2D.new()
			_grain.noise = noise
			_grain.width = 256
			_grain.height = 256
			_grain.seamless = true

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_texture_rect(_base, r, false)
		draw_texture_rect(_grain, r, true, Color(1, 1, 1, 0.07))
		draw_texture_rect(_vignette, r, false)

## Ahşap: dikey geçiş, dikey damar çizgileri, üst parlama, alt koyuluk, gölge.
class Wood extends Control:
	var kind := "band"
	static var _band: GradientTexture2D
	static var _desk: GradientTexture2D
	static var _drop: GradientTexture2D

	func _ready() -> void:
		resized.connect(queue_redraw)
		if _band == null:
			_band = TableSurface._linear([[0.0, Color("C88A4D")], [0.4, Color("A8693A")], [1.0, Color("8A5129")]])
			_desk = TableSurface._linear([[0.0, Color("C88A4D")], [0.06, Color("A8693A")], [1.0, Color("8A5129")]])
			_drop = TableSurface._linear([[0.0, Color(0, 0, 0, 0.42)], [1.0, Color(0, 0, 0, 0)]])

	func _draw() -> void:
		var d := UiTheme.d(1.0)
		var r := Rect2(Vector2.ZERO, size)
		# Gölge: bandın altına, masanın üstüne düşer.
		var drop := 20.0 * d
		if kind == "band":
			draw_texture_rect(_drop, Rect2(0, size.y, size.x, drop), false)
		else:
			draw_texture_rect(_drop, Rect2(0, 0, size.x, -drop), false)
		draw_texture_rect(_band if kind == "band" else _desk, r, false)
		# Damar: 25 px'de bir açık (6 px) ve koyu (3 px) dikey çizgi.
		var step := 25.0 * d
		var x := 0.0
		while x < size.x:
			draw_rect(Rect2(x, 0, 6.0 * d, size.y), Color(1, 1, 1, 0.04))
			draw_rect(Rect2(x + 22.0 * d, 0, 3.0 * d, size.y), Color(0, 0, 0, 0.05))
			x += step
		draw_rect(Rect2(0, 0, size.x, (2.0 if kind == "band" else 3.0) * d), Color(1.0, 0.86, 0.67, 0.5))
		if kind == "band":
			draw_rect(Rect2(0, size.y - 3.0 * d, size.x, 3.0 * d), Color(0, 0, 0, 0.25))

## Haritanın denizi (konsept: #93d2d7 ve beyazımsı dalga deseni; kenarda
## deniz yeşili çizgi). Kendi zemini ve dalgaları; harita bunun üstüne oturur.
static func sea() -> Panel:
	var p := Sea.new()
	var b := BoardBox.new()
	b.fill = Color("93D2D7")
	b.set_radius(UiTheme.d(12))
	b.highlight_size = UiTheme.d(4)
	b.highlight_color = Color(0, 0, 0, 0.08)
	b.rings = [[0.0, UiTheme.d(3), UiTheme.TEAL]]
	p.add_theme_stylebox_override("panel", b)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

class Sea extends Panel:
	func _ready() -> void:
		resized.connect(queue_redraw)
		clip_contents = true

	func _draw() -> void:
		# Desen hücresi 26x12 (harita birimi, ≈1,29 ölçek) -> tasarım birimi.
		var k := 1.29 / 1.5
		var cw := 26.0 * k
		var ch := 12.0 * k
		var inset := UiTheme.d(3)
		var pts := PackedVector2Array()
		var y := inset + ch * 0.5
		while y < size.y - inset:
			var x := inset
			while x < size.x - inset:
				var prev := Vector2.ZERO
				for i in 9:
					var u := float(i) / 8.0
					var px := x + (2.0 + 16.0 * u) * k
					var py := y + (7.0 - 6.0 - 2.0 * sin(u * TAU)) * k
					var pt := Vector2(px, py)
					if i > 0 and px < size.x - inset:
						pts.append(prev)
						pts.append(pt)
					prev = pt
				x += cw
			y += ch
		draw_multiline(pts, Color(0.9, 0.965, 0.97, 0.6), maxf(1.0, k), true)

## Sahnenin düz renkli "Background" zeminini çuhayla değiştirir (en arkaya).
static func cover(root: Control) -> void:
	var old := root.get_node_or_null("Background") as CanvasItem
	if old != null:
		old.visible = false
	var f := felt()
	root.add_child(f)
	root.move_child(f, 0)
