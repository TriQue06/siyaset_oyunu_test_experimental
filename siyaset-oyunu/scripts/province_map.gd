extends Node2D
## PIXEL-ART harita: artık vektör SVG/poligon YOK. Türkiye, elle çizilmiş
## düşük çözünürlüklü (data/province_pixel_map.json'daki "width"x"height",
## bkz. tools/pixel_art_province_colors.csv ile üretilen renk paleti) bir
## piksel ızgarası olarak temsil ediliyor: her piksel hangi ile aitse o ilin
## indeksini tutuyor (-1 = deniz/il dışı). Arka plan görseli
## (assets/maps/turkey_map_pixelart.png) NEAREST filtre ile büyütülüyor ki
## piksel blokları netliğini korusun, bulanıklaşmasın.
##
## Tıklama/hover algılama artık point-in-polygon DEĞİL, doğrudan ızgara
## lookup (O(1)); il boyama da polygon triangulation DEĞİL, ızgaraya göre
## piksel piksel yeniden boyanan bir ImageTexture (bkz. province_overlay.gd).

signal province_clicked(province_id: String)
signal province_hovered(province_id: String)  # "" = hover left every province

@export var pixel_map_path: String = "res://data/province_pixel_map.json"
@export var pixel_texture_path: String = "res://assets/maps/turkey_map.png"
## 1 piksel-ızgara hücresi = bu kadar "harita/local" birimi. Diğer tüm
## bileşenler (seat_markers.gd'deki dot_radius/dot_spacing, game_screen.gd'deki
## MAP_NATIVE_SIZE) bu birimle uyumlu olacak şekilde ayarlanmalı.
const MAP_UNIT_SCALE := 4.0

var grid_width: int = 0
var grid_height: int = 0
var ids: Array = []              # index -> province_id
var _id_to_index: Dictionary = {}  # province_id -> index
var _grid: PackedInt32Array = PackedInt32Array()  # index -> province index (-1 = deniz)
var _centers: Dictionary = {}    # province_id -> Vector2 (harita/local birimi)

var _hovered_id: String = ""

@onready var background: Sprite2D = $Background
@onready var overlay = $Overlay

func _ready() -> void:
	_load_pixel_map()
	_apply_background()
	overlay.setup(self)
	set_process_unhandled_input(true)

func _load_pixel_map() -> void:
	if not FileAccess.file_exists(pixel_map_path):
		push_warning("Pixel map data file not found: %s" % pixel_map_path)
		return
	var file := FileAccess.open(pixel_map_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_warning("Pixel map data could not be parsed: %s" % pixel_map_path)
		return

	grid_width = int(parsed["width"])
	grid_height = int(parsed["height"])
	ids = parsed["ids"]
	_id_to_index.clear()
	for i in ids.size():
		_id_to_index[ids[i]] = i

	var raw_grid: Array = parsed["grid"]
	_grid = PackedInt32Array()
	_grid.resize(raw_grid.size())
	for i in raw_grid.size():
		_grid[i] = int(raw_grid[i])

	var raw_centers: Dictionary = parsed["centers"]
	_centers.clear()
	for province_id in raw_centers.keys():
		var c: Array = raw_centers[province_id]
		# +0.5: piksel hücresinin KÖŞESİ değil MERKEZİ (dot layout/centroid
		# hesapları için daha doğru).
		_centers[province_id] = (Vector2(c[0], c[1]) + Vector2(0.5, 0.5)) * MAP_UNIT_SCALE

func _apply_background() -> void:
	if not background:
		return
	background.centered = false
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.texture = load(pixel_texture_path)
	background.scale = Vector2(MAP_UNIT_SCALE, MAP_UNIT_SCALE)

func get_province_centroid(province_id: String) -> Vector2:
	return _centers.get(province_id, Vector2.ZERO)

func get_all_province_ids() -> Array:
	return ids.duplicate()

## local_pos: bu Node2D'nin (Map'in) local koordinat uzayında bir nokta.
func get_province_id_at(local_pos: Vector2) -> String:
	if grid_width <= 0 or grid_height <= 0:
		return ""
	var px := int(floor(local_pos.x / MAP_UNIT_SCALE))
	var py := int(floor(local_pos.y / MAP_UNIT_SCALE))
	if px < 0 or py < 0 or px >= grid_width or py >= grid_height:
		return ""
	var idx: int = _grid[py * grid_width + px]
	if idx < 0 or idx >= ids.size():
		return ""
	return ids[idx]

func _unhandled_input(event: InputEvent) -> void:
	if ids.is_empty():
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
	overlay.mark_dirty()

## Paints several provinces at once and redraws only once (performance).
func set_province_colors(id_to_color: Dictionary) -> void:
	for province_id in id_to_color.keys():
		var color: Color = id_to_color[province_id]
		if color.a <= 0.0:
			overlay.colors.erase(province_id)
		else:
			overlay.colors[province_id] = color
	overlay.mark_dirty()

func clear_overlay() -> void:
	overlay.colors.clear()
	overlay.mark_dirty()
