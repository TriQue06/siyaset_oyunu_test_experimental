extends Node2D
## ProvinceMap'in ÇOCUĞU olarak eklenir (bkz. Map.tscn). İllerin üstüne, o
## ildeki milletvekili sandalyelerini pm_circle.png noktaları halinde çizer.
##
## Yerleşim algoritması, geliştiricinin "projeksiyon_hesaplayici" web
## uygulamasındaki getDotLayout() / çarpışma-önleyici fizik motorunun
## GDScript'e taşınmış halidir: her il bir "dot grubu" oluşturur (n sandalye
## için satır/sütun grid'i), komşu illerin dot grupları görsel olarak
## çakışıyorsa (özellikle küçük/bitişik illerde olur) birbirini yumuşakça iter.

@export var dot_texture: Texture2D
@export var dot_radius: float = 4.0     # pm_circle.png yarıçapı (harita/viewBox birimi)
@export var dot_spacing: float = 1.0    # aynı gruptaki noktalar arası boşluk
@export var push_iterations: int = 20
@export var return_strength: float = 0.04   # orijinal merkeze çekilme hızı
@export var push_strength: float = 0.2      # çakışan gruplar arası itme hızı

# province_id -> Array[Color] (o ildeki her sandalye için bir renk, parti rengi)
var _seats: Dictionary = {}
var _sprite_pool: Array = []

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
	for s in _sprite_pool:
		s.queue_free()
	_sprite_pool.clear()

	if _province_map == null or dot_texture == null:
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
		var radius := sqrt(pow(grid_w * 0.5, 2) + pow(grid_h * 0.5, 2)) * 0.95
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
			var spr := Sprite2D.new()
			spr.texture = dot_texture
			spr.centered = true
			spr.position = pos
			spr.modulate = colors[idx]
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(spr)
			_sprite_pool.append(spr)
			idx += 1
