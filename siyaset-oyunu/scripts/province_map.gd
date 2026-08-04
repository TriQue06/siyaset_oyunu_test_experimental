extends Node2D
## Vector election map: draws the SVG background, loads province polygon/
## center data (precomputed offline from the SVG's <path> elements, see
## tools/svg_to_provinces.py), and provides click/hover detection plus
## per-province coloring — all in the SVG's own coordinate space (viewBox
## units), so everything (background, polygons, seat markers) stays aligned
## without any manual scale bookkeeping.
##
## Province ids are the SVG path ids (lowercase, no diacritics, e.g. "adana").

signal province_clicked(province_id: String)
signal province_hovered(province_id: String)  # "" = hover left every province

## Godot'un sabit çözünürlüklü SVG import'una GÜVENMİYORUZ — kaynak SVG'yi
## çalışma zamanında (SvgRaster ile) rasterize ediyoruz, tıpkı fontların her
## boyut için yeniden çizilmesi gibi. Böylece harita ne kadar büyütülürse
## büyütülsün piksel/blok görünmez; gerekirse refresh_background() ile daha
## yüksek çözünürlükte yeniden üretilebilir (örn. ileride zoom eklenince).
@export var svg_path: String = "res://assets/maps/turkey_map.svg"
# Rasterin hedef piksel genişliği. Ne kadar büyükse o kadar keskin ama o
# kadar bellek/yükleme süresi — ekranda ne kadar büyük gösterileceğine göre
# ayarlanmalı.
@export var target_pixel_width: float = 2400.0

@export var data_path: String = "res://data/provinces.json"
# SVG'nin viewBox boyutu (turkey_map.svg: viewBox="0 0 1024 500"). Polygon
# verisi bu birimlerde; raster çözünürlüğü ne olursa olsun background
# sprite'ı hep bu boyuta sığdırırız ki poligonlarla piksel-hizalı kalsın.
@export var svg_viewbox_size: Vector2 = Vector2(1024, 500)

# province_id -> {"polygons": Array[PackedVector2Array], "center": Vector2}
var provinces: Dictionary = {}
var _hovered_id: String = ""

@onready var background: Sprite2D = $Background
@onready var overlay = $Overlay

func _ready() -> void:
	_apply_background()
	_load_province_data()
	set_process_unhandled_input(true)

func _apply_background() -> void:
	if not background:
		return
	background.centered = false
	# Proje genelinde pixel-art haritalar için varsayılan filtre "Nearest";
	# bu SVG kaynaklı vektör harita için burada "Linear" ile eziyoruz.
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	refresh_background(target_pixel_width)

## SVG'yi verilen hedef piksel genişliğinde YENİDEN rasterize eder ve
## background'a uygular. Harita çok daha büyük gösterilecekse (zoom vb.)
## daha yüksek bir target_pixel_width ile tekrar çağrılabilir.
func refresh_background(new_target_pixel_width: float) -> void:
	target_pixel_width = new_target_pixel_width
	var scale := target_pixel_width / svg_viewbox_size.x
	var tex := SvgRaster.load_texture(svg_path, scale)
	if tex == null:
		return
	background.texture = tex
	var tex_size := tex.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		background.scale = Vector2(svg_viewbox_size.x / tex_size.x, svg_viewbox_size.y / tex_size.y)

func _load_province_data() -> void:
	provinces.clear()
	if not FileAccess.file_exists(data_path):
		push_warning("Province data file not found: %s" % data_path)
		return
	var file := FileAccess.open(data_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_warning("Province data could not be parsed: %s" % data_path)
		return

	var polygons_for_overlay: Dictionary = {}
	for province_id in parsed.keys():
		var entry: Dictionary = parsed[province_id]
		var polygons: Array = []
		for raw_points in entry["polygons"]:
			var packed := PackedVector2Array()
			for p in raw_points:
				packed.append(Vector2(p[0], p[1]))
			polygons.append(packed)
		var center_arr: Array = entry["center"]
		provinces[province_id] = {
			"polygons": polygons,
			"center": Vector2(center_arr[0], center_arr[1]),
		}
		polygons_for_overlay[province_id] = polygons

	overlay.polygons_by_province = polygons_for_overlay

func get_province_centroid(province_id: String) -> Vector2:
	if provinces.has(province_id):
		return provinces[province_id]["center"]
	return Vector2.ZERO

func get_all_province_ids() -> Array:
	return provinces.keys()

func get_province_id_at(local_pos: Vector2) -> String:
	for province_id in provinces.keys():
		for polygon in provinces[province_id]["polygons"]:
			if Geometry2D.is_point_in_polygon(local_pos, polygon):
				return province_id
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if provinces.is_empty():
		return
	if event is InputEventMouseMotion:
		var local := to_local(event.global_position)
		var id := get_province_id_at(local)
		if id != _hovered_id:
			_hovered_id = id
			province_hovered.emit(id)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := to_local(event.global_position)
		var id := get_province_id_at(local)
		if id != "":
			province_clicked.emit(id)

## Paints a single province. Pass an alpha-0 color (or call clear) to unpaint it.
func set_province_color(province_id: String, color: Color) -> void:
	if color.a <= 0.0:
		overlay.colors.erase(province_id)
	else:
		overlay.colors[province_id] = color
	overlay.queue_redraw()

## Paints several provinces at once and redraws only once (performance).
func set_province_colors(id_to_color: Dictionary) -> void:
	for province_id in id_to_color.keys():
		var color: Color = id_to_color[province_id]
		if color.a <= 0.0:
			overlay.colors.erase(province_id)
		else:
			overlay.colors[province_id] = color
	overlay.queue_redraw()

func clear_overlay() -> void:
	overlay.colors.clear()
	overlay.queue_redraw()
