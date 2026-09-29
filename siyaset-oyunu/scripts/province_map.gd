extends Node2D
## ALTIGEN HARİTA — vektörel, düz (flat) stil. Veri GameMap'ten gelir; harita
## değişince (yeni oyun) kendini yeniden kurar.
##
## ÇİZİM MALİYETİ: yüzlerce altıgen tek tek draw_polygon ile çizilmez (web'de
## çağrı başına maliyet yüksek). Kara altıgenleri tek bir ArrayMesh (köşe
## renkli), sınırlar ikinci bir ArrayMesh; renk değişince sadece renk dizisi
## yeniden yazılır. Hover ve odak parıltısı küçük ek çizimlerdir.
##
## Arayüz eski piksel haritayla aynıdır (grid_width/grid_height × MAP_UNIT_SCALE
## = harita boyutu, get_province_id_at, set_province_colors ...), böylece oyun
## ekranı ve seçim gecesi değişmeden kullanır.

signal province_clicked(province_id: String)
signal province_hovered(province_id: String)  # "" = hiçbir il

const MAP_UNIT_SCALE := 1.0
## 1 = altıgenler arası boşluk yok: sadece il sınırları görünür.
const CELL_INSET := 1.0
const LAND_COLOR := Color(0.27, 0.30, 0.40)
const SEA_COLOR := Color(0.14, 0.17, 0.27, 0.55)
const REGION_BORDER_COLOR := Color(0.94, 0.95, 0.98, 0.9)
## Açık zeminli katmanlarda (ör. teşkilat: seviye 0 = neredeyse beyaz) beyaz
## sınır kaybolur; o zaman koyu sınır kullanılır (bkz. set_dark_borders).
const REGION_BORDER_DARK := Color(0.10, 0.11, 0.18, 0.95)
const REGION_BORDER_WIDTH := 1.7
const COAST_COLOR := Color(0.62, 0.72, 0.92, 0.8)
const COAST_WIDTH := 1.4
const HOVER_COLOR := Color(1, 1, 1, 0.85)

var grid_width: int = 0
var grid_height: int = 0
var ids: Array = []

var _colors: Dictionary = {}       # province_id -> Color
var _hovered_id: String = ""
var _land_mesh: ArrayMesh = null
var _border_mesh: ArrayMesh = null
var _land_vertices := PackedVector2Array()
var _land_vertex_region := PackedInt32Array()  # köşe -> bölge indeksi
var _sea_mesh: ArrayMesh = null
var _border_vertices := PackedVector2Array()
var _border_colors := PackedColorArray()
var _edges: Dictionary = {}        # province_id -> Array[[a, b]] (bölge dış sınırı)
var _colors_dirty := true
## Odak parıltısı: {"id", "color", "time", "duration", "icon"}; boşsa yok.
var _pulse: Dictionary = {}
## Siyasi kaleler: province_id -> sahibinin rengi.
var _strongholds: Dictionary = {}
var _dark_borders := false

func _ready() -> void:
	for child in get_children():
		if child.name in ["Background", "Overlay"]:
			child.queue_free()
	GameMap.map_changed.connect(_rebuild)
	_rebuild()
	set_process_unhandled_input(true)
	set_process(false)

func _rebuild() -> void:
	ids = GameMap.province_ids()
	var size := GameMap.map_size()
	grid_width = int(ceil(size.x))
	grid_height = int(ceil(size.y))
	_build_geometry()
	_colors_dirty = true
	queue_redraw()
	var markers := get_node_or_null("SeatMarkers")
	if markers != null and markers.has_method("clear_all"):
		markers.clear_all()

func _build_geometry() -> void:
	_land_vertices = PackedVector2Array()
	_land_vertex_region = PackedInt32Array()
	_edges.clear()
	var sea_vertices := PackedVector2Array()
	var sea_colors := PackedColorArray()
	_border_vertices = PackedVector2Array()
	_border_colors = PackedColorArray()
	for id in ids:
		_edges[id] = []
	for cell in GameMap.cells.size():
		var region: int = GameMap.cells[cell]
		var inner := GameMap.cell_corners(cell, CELL_INSET)
		if region < 0:
			var sea_center := GameMap.cell_center(cell)
			for k in 6:
				sea_vertices.append_array([sea_center, inner[k], inner[(k + 1) % 6]])
				sea_colors.append_array([SEA_COLOR, SEA_COLOR, SEA_COLOR])
			continue
		var center := GameMap.cell_center(cell)
		for k in 6:
			_land_vertices.append_array([center, inner[k], inner[(k + 1) % 6]])
			_land_vertex_region.append_array([region, region, region])
		# Kenarlar: komşu başka bölgeyse bölge sınırı, denizse kıyı.
		var outer := GameMap.cell_corners(cell, 1.0)
		for k in 6:
			var n := _neighbor_in_direction(cell, k)
			var other: int = GameMap.cells[n] if n >= 0 else -1
			if other == region:
				continue
			var a: Vector2 = outer[k]
			var b: Vector2 = outer[(k + 1) % 6]
			_edges[ids[region]].append([a, b])
			if other >= 0 and other < region:
				continue  # ortak sınırı bir kez çiz
			var width := COAST_WIDTH if other < 0 else REGION_BORDER_WIDTH
			var color := COAST_COLOR if other < 0 else (REGION_BORDER_DARK if _dark_borders else REGION_BORDER_COLOR)
			_append_segment(a, b, width, color)
	_land_mesh = ArrayMesh.new()
	_border_mesh = ArrayMesh.new()
	_sea_mesh = ArrayMesh.new()
	if not sea_vertices.is_empty():
		var sea_arrays := []
		sea_arrays.resize(Mesh.ARRAY_MAX)
		sea_arrays[Mesh.ARRAY_VERTEX] = sea_vertices
		sea_arrays[Mesh.ARRAY_COLOR] = sea_colors
		_sea_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sea_arrays)
	if not _border_vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _border_vertices
		arrays[Mesh.ARRAY_COLOR] = _border_colors
		_border_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

## Kenar k: köşe k ile k+1 arası; yönü 60k derece (0 = doğu, saat yönünde).
func _neighbor_in_direction(cell: int, k: int) -> int:
	var col := cell % GameMap.cols
	var row := cell / GameMap.cols
	var even := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
	var odd := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
	var o: Vector2i = (odd if row % 2 == 1 else even)[k]
	var c: int = col + o.x
	var r: int = row + o.y
	if c < 0 or r < 0 or c >= GameMap.cols or r >= GameMap.rows:
		return -1
	return r * GameMap.cols + c

## (Packed diziler GDScript'te değerle geçer: parametreye eklemek kaybolur,
## bu yüzden üye dizilere yazılır.)
func _append_segment(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var dir := (b - a).normalized()
	var normal := Vector2(-dir.y, dir.x) * width * 0.5
	# Uçları biraz uzat: köşelerde boşluk kalmasın.
	var a2 := a - dir * width * 0.35
	var b2 := b + dir * width * 0.35
	_border_vertices.append_array([a2 + normal, b2 + normal, b2 - normal, a2 + normal, b2 - normal, a2 - normal])
	for _i in 6:
		_border_colors.append(color)

func _update_land_colors() -> void:
	_colors_dirty = false
	if _land_vertices.is_empty():
		return
	var palette: Array = []
	for id in ids:
		palette.append(_colors.get(id, LAND_COLOR))
	var colors := PackedColorArray()
	colors.resize(_land_vertices.size())
	for i in _land_vertices.size():
		colors[i] = palette[_land_vertex_region[i]]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _land_vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	_land_mesh.clear_surfaces()
	_land_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _draw() -> void:
	if _colors_dirty:
		_update_land_colors()
	if _sea_mesh != null and _sea_mesh.get_surface_count() > 0:
		draw_mesh(_sea_mesh, null)
	if _land_mesh != null and _land_mesh.get_surface_count() > 0:
		draw_mesh(_land_mesh, null)
	if _border_mesh != null and _border_mesh.get_surface_count() > 0:
		draw_mesh(_border_mesh, null)
	for province_id in _strongholds.keys():
		_draw_castle(_castle_anchor(province_id), _strongholds[province_id])
	if _hovered_id != "":
		_draw_region_outline(_hovered_id, HOVER_COLOR, 1.8)
	if not _pulse.is_empty():
		_draw_pulse()

func _draw_region_outline(province_id: String, color: Color, width: float) -> void:
	for edge in _edges.get(province_id, []):
		draw_line(edge[0], edge[1], color, width, true)

## Açık renkli katmanlar için koyu il sınırları (geometri bir kez yeniden kurulur).
func set_dark_borders(dark: bool) -> void:
	if dark == _dark_borders:
		return
	_dark_borders = dark
	_build_geometry()
	_colors_dirty = true
	queue_redraw()

# --- Siyasi kale simgesi ----------------------------------------------------------

func set_strongholds(marks: Dictionary) -> void:
	if marks.hash() == _strongholds.hash():
		return
	_strongholds = marks.duplicate()
	queue_redraw()

## Simge bölgenin en üstteki hücresine oturur (merkezdeki vekil noktalarına binmesin).
func _castle_anchor(province_id: String) -> Vector2:
	var best := GameMap.center_of(province_id)
	var best_y := INF
	for cell in GameMap.region_cells(province_id):
		var c := GameMap.cell_center(cell)
		if c.y < best_y - 0.1 or (absf(c.y - best_y) <= 0.1 and absf(c.x - GameMap.center_of(province_id).x) < absf(best.x - GameMap.center_of(province_id).x)):
			best_y = c.y
			best = c
	return best

func _draw_castle(pos: Vector2, color: Color) -> void:
	var ink := Color(0.06, 0.06, 0.1, 0.95)
	var body := PackedVector2Array([
		pos + Vector2(-5.5, 5), pos + Vector2(-5.5, -4), pos + Vector2(-3.5, -4), pos + Vector2(-3.5, -2),
		pos + Vector2(-1, -2), pos + Vector2(-1, -4), pos + Vector2(1, -4), pos + Vector2(1, -2),
		pos + Vector2(3.5, -2), pos + Vector2(3.5, -4), pos + Vector2(5.5, -4), pos + Vector2(5.5, 5)])
	var outline := body.duplicate()
	outline.append(body[0])
	draw_colored_polygon(body, color.lightened(0.15))
	draw_polyline(outline, ink, 1.2, true)
	draw_rect(Rect2(pos + Vector2(-1.2, 1.5), Vector2(2.4, 3.5)), ink)

# --- Odak parıltısı (olay logundaki 🎯 düğmesi) -----------------------------------

## Bölgeyi duration saniye boyunca verilen renkte parlatır; icon (bkz.
## _draw_micro_icon) bölgenin üstünde yükselir.
func pulse_province(province_id: String, color: Color, icon: String = "", duration: float = 0.9) -> void:
	if not GameMap.ids.has(province_id):
		return
	_pulse = {"id": province_id, "color": color, "time": 0.0, "duration": duration, "icon": icon}
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if _pulse.is_empty():
		set_process(false)
		return
	_pulse["time"] = float(_pulse["time"]) + delta
	if float(_pulse["time"]) >= float(_pulse["duration"]):
		_pulse = {}
		set_process(false)
	queue_redraw()

func _draw_pulse() -> void:
	var t: float = clampf(float(_pulse["time"]) / float(_pulse["duration"]), 0.0, 1.0)
	var glow: float = sin(t * PI * 3.0) * 0.5 + 0.5  # 1,5 nabız
	var fade: float = 1.0 - smoothstep(0.75, 1.0, t)
	var color: Color = _pulse["color"]
	var id: String = _pulse["id"]
	var fill := color
	fill.a = 0.45 * glow * fade
	for cell in GameMap.region_cells(id):
		draw_colored_polygon(GameMap.cell_corners(cell, CELL_INSET), fill)
	var outline := color.lightened(0.35)
	outline.a = (0.55 + 0.45 * glow) * fade
	_draw_region_outline(id, outline, 2.4 + 1.6 * glow)
	var icon: String = _pulse["icon"]
	if icon != "":
		var rise := 10.0 * smoothstep(0.0, 0.6, t)
		var pos := GameMap.center_of(id) - Vector2(0.0, 12.0 + rise)
		_draw_micro_icon(icon, pos, color, fade)

## Olay türüne göre küçük vektör simge (yazı tipi emojisine güvenmez):
## mic 🎤 miting, megaphone 📢 karalama, tape 📼 kaset, factory 🏭 yatırım,
## flag teşkilat, pin diğerleri.
func _draw_micro_icon(icon: String, pos: Vector2, color: Color, alpha: float) -> void:
	var bg := Color(UiTheme.INK, 0.85 * alpha)
	var fg := Color(1, 1, 1, alpha)
	draw_circle(pos, 9.0, bg)
	draw_arc(pos, 9.0, 0.0, TAU, 24, Color(color.lightened(0.3), alpha), 1.5, true)
	match icon:
		"mic":
			draw_rect(Rect2(pos + Vector2(-2.0, -6.0), Vector2(4.0, 7.0)), fg)
			draw_arc(pos + Vector2(0, -1.0), 4.0, 0.0, PI, 10, fg, 1.2, true)
			draw_line(pos + Vector2(0, 3.0), pos + Vector2(0, 6.0), fg, 1.2)
			draw_line(pos + Vector2(-3, 6.0), pos + Vector2(3, 6.0), fg, 1.2)
		"megaphone":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-5, -2), pos + Vector2(4, -6), pos + Vector2(4, 6), pos + Vector2(-5, 2)]), fg)
			draw_rect(Rect2(pos + Vector2(-7, -2), Vector2(2, 4)), fg)
		"tape":
			draw_rect(Rect2(pos + Vector2(-6, -4), Vector2(12, 8)), fg, false, 1.2)
			draw_circle(pos + Vector2(-2.5, 0), 1.6, fg)
			draw_circle(pos + Vector2(2.5, 0), 1.6, fg)
		"factory":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-6, 6), pos + Vector2(-6, -1), pos + Vector2(-2, 1),
				pos + Vector2(-2, -1), pos + Vector2(2, 1), pos + Vector2(2, -6), pos + Vector2(5, -6), pos + Vector2(5, 6)]), fg)
		"flag":
			draw_line(pos + Vector2(-4, -6), pos + Vector2(-4, 6), fg, 1.4)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-4, -6), pos + Vector2(5, -3), pos + Vector2(-4, 0)]), fg)
		_:
			draw_circle(pos + Vector2(0, -1.5), 3.5, fg)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(-3, 0), pos + Vector2(3, 0), pos + Vector2(0, 6)]), fg)

# --- Eski arayüz ----------------------------------------------------------------

func get_province_centroid(province_id: String) -> Vector2:
	return GameMap.center_of(province_id)

func get_all_province_ids() -> Array:
	return ids.duplicate()

func get_province_id_at(local_pos: Vector2) -> String:
	return GameMap.province_at(local_pos)

func _unhandled_input(event: InputEvent) -> void:
	if ids.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var id := get_province_id_at(to_local(event.global_position))
		if id != _hovered_id:
			_hovered_id = id
			province_hovered.emit(id)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := get_province_id_at(to_local(event.global_position))
		if id != "":
			province_clicked.emit(id)

func set_province_color(province_id: String, color: Color) -> void:
	if color.a <= 0.0:
		_colors.erase(province_id)
	else:
		_colors[province_id] = color
	_colors_dirty = true
	queue_redraw()

func set_province_colors(id_to_color: Dictionary) -> void:
	for province_id in id_to_color.keys():
		var color: Color = id_to_color[province_id]
		if color.a <= 0.0:
			_colors.erase(province_id)
		else:
			_colors[province_id] = color
	_colors_dirty = true
	queue_redraw()

func clear_overlay() -> void:
	_colors.clear()
	_colors_dirty = true
	queue_redraw()
