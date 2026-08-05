extends Node2D
## ProvinceMap'in ÇOCUĞU olarak eklenir (bkz. Map.tscn). İllerin üstüne, o
## ildeki milletvekili sandalyelerini noktalar halinde çizer.
##
## Noktalar bir raster texture (Sprite2D) yerine _draw()/draw_circle ile
## VEKTÖR olarak çiziliyor (antialiased) — harita hangi ölçekte gösterilirse
## gösterilsin (ne kadar büyütülürse büyütülsün) her zaman keskin/pürüzsüz
## kalır, pikselleşmez.
##
## Yerleşim algoritması, geliştiricinin "projeksiyon_hesaplayici" web
## uygulamasındaki getDotLayout() / çarpışma-önleyici fizik motorunun
## GDScript'e taşınmış halidir: her il bir "dot grubu" oluşturur (n sandalye
## için satır/sütun grid'i), komşu illerin dot grupları görsel olarak
## çakışıyorsa (özellikle küçük/bitişik illerde olur) birbirini yumuşakça iter.

@export var dot_radius: float = 5.5     # nokta yarıçapı (harita/viewBox birimi)
@export var dot_outline_width: float = 1.8  # siyah kontur kalınlığı
@export var dot_outline_color: Color = Color(0.11, 0.12, 0.13) # eksen_projeksiyon: #1c1e21
@export var dot_spacing: float = 1.5    # aynı gruptaki noktalar arası boşluk
@export var push_iterations: int = 20
@export var return_strength: float = 0.04   # orijinal merkeze çekilme hızı
@export var push_strength: float = 0.2      # çakışan gruplar arası itme hızı
## Çarpışma fiziğinde kullanılan "sanal" grup yarıçapı, gerçek ızgara
## yarıçapının bu katı kadar büyük tutulur — komşu illerin grupları arasında
## ekstra boşluk bırakır, kenar noktaları görsel olarak iç içe girmesin diye
## (eksen_projeksiyon'daki 10.5/7.25 = ~1.45 oranındaki fikrin genellemesi).
@export var collision_radius_factor: float = 1.6

# province_id -> Array[Color] (o ildeki her sandalye için bir renk, parti rengi)
var _seats: Dictionary = {}
# Array[{"pos": Vector2, "color": Color}] — _draw() bunu tek seferde çizer.
var _dots: Array = []

@onready var _province_map = get_parent()

## O ilin sandalye/renk listesini ayarlar ve tüm noktaları yeniden hesaplar.
## seat_colors: her eleman bir Color (o koltuktaki partinin rengi).
func set_seats(province_id: String, seat_colors: Array) -> void:
	_seats[province_id] = seat_colors
	_rebuild()

func clear_province(province_id: String) -> void:
	_seats.erase(province_id)
	_rebuild()

func clear_all() -> void:
	_seats.clear()
	_rebuild()

## Referans web uygulamasındaki getDotLayout(n) ile birebir aynı mantık:
## küçük n'ler için elle ayarlanmış, kompakt (kare-ye yakın) düzenler;
## büyük n'ler için sqrt tabanlı sütun sayısı + satırlara eşit dağıtım.
func _get_dot_layout(n: int) -> Array:
	if n <= 0:
		return []
	match n:
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [3, 2]
		6: return [3, 3]
		7: return [2, 3, 2]
		8: return [3, 3, 2]
		9: return [3, 3, 3]

	var cols: int
	if n > 20:
		cols = int(ceil(sqrt(n * 1.2)))
		cols = min(cols, 7)
	else:
		cols = int(ceil(sqrt(n * 1.5)))
		cols = min(cols, 8)

	var rows := int(ceil(float(n) / float(cols)))
	var layout: Array = []
	var remaining := n
	for i in rows:
		var r := int(ceil(float(remaining) / float(rows - i)))
		layout.append(r)
		remaining -= r
	return layout

func _rebuild() -> void:
	_dots.clear()

	if _province_map == null:
		queue_redraw()
		return

	var cell := dot_radius * 2.0 + dot_spacing
	var groups: Array = []
	for province_id in _seats.keys():
		var colors: Array = _seats[province_id]
		if colors.is_empty():
			continue
		var layout := _get_dot_layout(colors.size())
		var max_cols := 0
		for c in layout:
			max_cols = max(max_cols, c)
		var rows := layout.size()
		var grid_w := max_cols * cell
		var grid_h := rows * cell
		var radius := sqrt(pow(grid_w * 0.5, 2) + pow(grid_h * 0.5, 2)) * 0.95 * collision_radius_factor
		var center: Vector2 = _province_map.get_province_centroid(province_id)
		groups.append({
			"orig": center,
			"pos": center,
			"radius": radius,
			"layout": layout,
			"colors": colors,
		})

	# Çarpışma engelleyici fizik: gruplar orijinal merkeze doğru yumuşakça
	# çekilir, birbirine çok yakınsa (radius toplamından az mesafe) itilir.
	for _iter in push_iterations:
		for j in groups.size():
			var g = groups[j]
			g.pos += (g.orig - g.pos) * return_strength
			for k in range(j + 1, groups.size()):
				var g1 = groups[j]
				var g2 = groups[k]
				var delta: Vector2 = g1.pos - g2.pos
				var dist := delta.length()
				var min_dist: float = g1.radius + g2.radius
				if dist < min_dist and dist > 0.01:
					var overlap := min_dist - dist
					var push: Vector2 = (delta / dist) * overlap * push_strength
					g1.pos += push
					g2.pos -= push

	for g in groups:
		_spawn_group(g.pos, g.layout, g.colors, cell)

	queue_redraw()

func _spawn_group(center: Vector2, layout: Array, colors: Array, cell: float) -> void:
	var rows := layout.size()
	var total_h := rows * cell - dot_spacing
	var start_y := center.y - total_h * 0.5 + dot_radius
	var idx := 0
	for row in rows:
		var cols: int = layout[row]
		var total_w := cols * cell - dot_spacing
		var start_x := center.x - total_w * 0.5 + dot_radius
		for col in cols:
			var pos := Vector2(start_x + col * cell, start_y + row * cell)
			_dots.append({"pos": pos, "color": colors[idx]})
			idx += 1

func _draw() -> void:
	# Kontur efekti: önce biraz daha büyük siyah bir daire, üstüne parti
	# renginde asıl nokta (eksen_projeksiyon'daki stroke="#1c1e21" konturuna
	# karşılık gelir, Godot'ta draw_circle'ın outline parametresi olmadığı
	# için iki daire üst üste çizilerek taklit ediliyor).
	for dot in _dots:
		draw_circle(dot["pos"], dot_radius + dot_outline_width, dot_outline_color, true, -1.0, true)
	for dot in _dots:
		draw_circle(dot["pos"], dot_radius, dot["color"], true, -1.0, true)
