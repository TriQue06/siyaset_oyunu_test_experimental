extends Node2D
## İL HARİTASI — vektörel, düz (flat) stil: altıgen ızgara (Türkiye, eski
## kayıtlar) ya da serbest şekilli ÜLKE (CountryGenerator, 0.0.261). Veri GameMap'ten gelir; harita
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
## 0.0.265 masa oyunu: açık deniz yeşili deniz, krem il sınırları, koyu
## kahve kıyı; ülkenin altında karton kalınlığı (EXTRUDE).
const SEA_COLOR := Color("93D2D7")
const REGION_BORDER_COLOR := Color(1.0, 0.98, 0.94, 0.95)
## Açık zeminli katmanlarda (ör. teşkilat: seviye 0 = neredeyse beyaz) beyaz
## sınır kaybolur; o zaman koyu sınır kullanılır (bkz. set_dark_borders).
const REGION_BORDER_DARK := Color(0.10, 0.11, 0.18, 0.95)
const REGION_BORDER_WIDTH := 1.7
const COAST_COLOR := Color("4A3A26")
const COAST_WIDTH := 1.4
const HOVER_COLOR := Color(1, 1, 1, 0.85)
## ÜLKE haritasının çizgileri (referans: Türkiye / İspanya seçim haritaları).
const COUNTRY_BORDER_COLOR := Color("FFFAF0")
const COUNTRY_BORDER_WIDTH := 1.3
const COUNTRY_COAST_COLOR := Color("4A3A26")
const COUNTRY_COAST_WIDTH := 1.4
## Kıyının denize taşan açık halesi (konsept: #d9f1f2, 9 birim, %80).
const COAST_HALO_COLOR := Color("CBEBED")  # #d9f1f2 %80, denizle önceden karışık (üst üste binme koyulaşmasın)
const COAST_HALO_WIDTH := 9.0
## Karton kalınlığı: kara, bu kadar aşağı kaydırılmış koyu bir kopyanın üstünde
## durur (harita birimi); altında da yumuşak bir masa gölgesi.
const EXTRUDE_DEPTH := 6.3
const EXTRUDE_COLOR := Color("B08A5A")
const TABLE_SHADOW_DEPTH := 9.0
const TABLE_SHADOW_COLOR := Color(0.043, 0.227, 0.251, 0.3)

var grid_width: int = 0
var grid_height: int = 0
var ids: Array = []

var _colors: Dictionary = {}       # province_id -> Color
var _hovered_id: String = ""
var _land_mesh: ArrayMesh = null
var _border_mesh: ArrayMesh = null
var _land_vertices := PackedVector2Array()
var _land_vertex_region := PackedInt32Array()  # köşe -> bölge indeksi
var _land_attribute_data := PackedByteArray()
var _land_palette: Array = []
var _land_color_runs: Array = []
var _sea_mesh: ArrayMesh = null
## Oyun ekranı denizi kendisi (dalgalı zeminle) çizer; burada çizilmez.
var draw_sea := true
var _extrude_mesh: ArrayMesh = null
var _halo_mesh: ArrayMesh = null
var _coast_segments: Array = []
var _border_vertices := PackedVector2Array()
var _border_colors := PackedColorArray()
var _edges: Dictionary = {}        # province_id -> Array[[a, b]] (bölge dış sınırı)
## province_id -> PackedVector2Array: ilin üçgenleri (dolgu efektleri için).
var _region_tris: Dictionary = {}

var _colors_dirty := true
## Odak parıltısı: {"id", "color", "time", "duration", "icon"}; boşsa yok.
var _pulse: Dictionary = {}
var _dark_borders := false
var _white_borders := false

func _ready() -> void:
	for child in get_children():
		if child.name in ["Background", L.t("Overlay")]:
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
	_land_attribute_data.clear()
	_land_palette.clear()
	_land_color_runs.clear()
	_land_vertices = PackedVector2Array()
	_land_vertex_region = PackedInt32Array()
	_edges.clear()
	var sea_vertices := PackedVector2Array()
	var sea_colors := PackedColorArray()
	_border_vertices = PackedVector2Array()
	_border_colors = PackedColorArray()
	_region_tris.clear()
	for id in ids:
		_edges[id] = []
		_region_tris[id] = PackedVector2Array()
	if GameMap.is_country():
		var map_size := GameMap.map_size()
		sea_vertices.append_array([Vector2.ZERO, Vector2(map_size.x, 0), map_size, Vector2.ZERO, map_size, Vector2(0, map_size.y)])
		for _i in 6:
			sea_colors.append(SEA_COLOR)
		_build_country()
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
			_region_tris[ids[region]].append_array([center, inner[k], inner[(k + 1) % 6]])
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
			var color := Color.WHITE if _white_borders else (COAST_COLOR if other < 0 else (REGION_BORDER_DARK if _dark_borders else REGION_BORDER_COLOR))
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
	_build_extrude()
	if not _border_vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _border_vertices
		arrays[Mesh.ARRAY_COLOR] = _border_colors
		_border_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

## KARTON KALINLIĞI: kara üçgenlerinin aşağı kaydırılmış iki kopyası (önce
## yumuşak masa gölgesi, sonra koyu karton kenarı); kara bunların üstüne çizilir.
func _build_extrude() -> void:
	_extrude_mesh = ArrayMesh.new()
	if _land_vertices.is_empty():
		return
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	for layer in [[TABLE_SHADOW_DEPTH, TABLE_SHADOW_COLOR], [EXTRUDE_DEPTH, EXTRUDE_COLOR]]:
		var offset := Vector2(0, float(layer[0]))
		var start := vertices.size()
		vertices.append_array(_land_vertices)
		for i in range(start, vertices.size()):
			vertices[i] += offset
		var tint := PackedColorArray()
		tint.resize(_land_vertices.size())
		tint.fill(layer[1])
		colors.append_array(tint)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	_extrude_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Kıyı halesi: kıyı çizgisi boyunca denize taşan açık şerit (yuvarlak uçlu).
	_halo_mesh = ArrayMesh.new()
	if _coast_segments.is_empty():
		return
	var hv := PackedVector2Array()
	var w := COAST_HALO_WIDTH * 0.5
	for seg in _coast_segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var dir := (b - a).normalized()
		var n := Vector2(-dir.y, dir.x) * w
		hv.append_array([a + n, b + n, b - n, a + n, b - n, a - n])
		for k in 8:
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			hv.append_array([b, b + Vector2(cos(a0), sin(a0)) * w, b + Vector2(cos(a1), sin(a1)) * w])
	var hc := PackedColorArray()
	hc.resize(hv.size())
	hc.fill(Color(COAST_HALO_COLOR, 1.0))
	var harrays := []
	harrays.resize(Mesh.ARRAY_MAX)
	harrays[Mesh.ARRAY_VERTEX] = hv
	harrays[Mesh.ARRAY_COLOR] = hc
	_halo_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, harrays)

## ÜLKE HARİTASI (0.0.261): deniz tek dikdörtgen; iller hücre üçgenlerinden;
## sınırlar CountryGenerator'ın yumuşatılmış ortak kenarları (her biri bir kez).
func _build_country() -> void:
	_coast_segments.clear()
	var geo: Dictionary = GameMap.country
	for r in ids.size():
		var tris: PackedVector2Array = geo["tris"][r]
		_region_tris[ids[r]] = tris
		_land_vertices.append_array(tris)
		var marks := PackedInt32Array()
		marks.resize(tris.size())
		marks.fill(r)
		_land_vertex_region.append_array(marks)
	for seg in geo["segments"]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ra: int = seg[2]
		var rb: int = seg[3]
		_edges[ids[ra]].append([a, b])
		if rb >= 0:
			_edges[ids[rb]].append([a, b])
		# Seçim haritaları gibi (0.0.262): il sınırı ince beyaz, kıyı ince koyu.
		var coast := rb < 0
		if coast:
			_coast_segments.append([a, b])
		var width := COUNTRY_COAST_WIDTH if coast else COUNTRY_BORDER_WIDTH
		var color := COUNTRY_COAST_COLOR if coast else (REGION_BORDER_DARK if _dark_borders else COUNTRY_BORDER_COLOR)
		_append_segment(a, b, width, color)

## İlin tamamını tek çağrıda boyar (afet / odak parıltısı).
func _fill_region(province_id: String, color: Color) -> void:
	var tris: PackedVector2Array = _region_tris.get(province_id, PackedVector2Array())
	if tris.is_empty():
		return
	var indices := PackedInt32Array()
	indices.resize(tris.size())
	for i in tris.size():
		indices[i] = i
	var colors := PackedColorArray()
	colors.resize(tris.size())
	colors.fill(color)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, tris, colors)

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
	if palette == _land_palette and _land_mesh.get_surface_count() > 0:
		return
	_land_palette = palette.duplicate()
	# Geometry is immutable between map rebuilds. Update only the RGBA8
	# attribute buffer, using exactly the truncation used by ArrayMesh import.
	if _land_mesh.get_surface_count() > 0 and RenderingServer.mesh_surface_get_format_attribute_stride(_land_mesh.surface_get_format(0), _land_vertices.size()) == 4:
		var packed_palette := []
		for color: Color in palette:
			packed_palette.append(_pack_land_color(color))
		if _land_color_runs.is_empty():
			for region in _land_vertex_region:
				if _land_color_runs.is_empty() or _land_color_runs[-1][0] != region:
					_land_color_runs.append([region, 1])
				else:
					_land_color_runs[-1][1] += 1
		_land_attribute_data.clear()
		for run in _land_color_runs:
			var pixels := PackedInt32Array()
			pixels.resize(run[1])
			pixels.fill(packed_palette[run[0]])
			_land_attribute_data.append_array(pixels.to_byte_array())
		_land_mesh.surface_update_attribute_region(0, 0, _land_attribute_data)
		return
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

static func _pack_land_color(color: Color) -> int:
	return int(clampf(color.r * 255.0, 0.0, 255.0)) \
		| (int(clampf(color.g * 255.0, 0.0, 255.0)) << 8) \
		| (int(clampf(color.b * 255.0, 0.0, 255.0)) << 16) \
		| (int(clampf(color.a * 255.0, 0.0, 255.0)) << 24)

## İl paneli açıkken haritada yalnız bu il çizilir (bkz. game_screen _open_province_actions).
var isolated_id := ""

func set_isolated(province_id: String) -> void:
	isolated_id = province_id
	# Vekil noktaları yalnız bu ilinkileri çizer (görünürlüğü katman belirler);
	# diğer üst katmanlar (etiketler vb.) inceleme sırasında gizlenir.
	for child in get_children():
		if child.has_method("set_only_province"):
			child.set_only_province(province_id)
		elif child is CanvasItem:
			child.visible = province_id == ""
	queue_redraw()

## İlin harita koordinatlarındaki sınır kutusu.
func region_bounds(province_id: String) -> Rect2:
	var tris: PackedVector2Array = _region_tris.get(province_id, PackedVector2Array())
	if tris.is_empty():
		return Rect2(GameMap.center_of(province_id), Vector2.ZERO)
	var box := Rect2(tris[0], Vector2.ZERO)
	for point in tris:
		box = box.expand(point)
	return box

func _draw() -> void:
	if _colors_dirty:
		_update_land_colors()
	if isolated_id != "":
		_fill_region(isolated_id, LAND_COLOR)
		_fill_region(isolated_id, _colors.get(isolated_id, LAND_COLOR))
		# Büyütülmüş çizimde yumuşatılmış çizgi bulanıklaşır: kalınlık ekran
		# pikseline göre, yumuşatmasız çizilir.
		var px := 1.0 / maxf(0.0001, (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().x)
		var border := REGION_BORDER_DARK if _dark_borders else REGION_BORDER_COLOR
		for edge in _edges.get(isolated_id, []):
			draw_line(edge[0], edge[1], border, 2.0 * px, false)
		if isolated_id in _disaster_ids:
			for edge in _edges.get(isolated_id, []):
				draw_line(edge[0], edge[1], Color(UiTheme.RED, 0.9), 4.0 * px, false)
		return
	if draw_sea and _sea_mesh != null and _sea_mesh.get_surface_count() > 0:
		draw_mesh(_sea_mesh, null)
	if _halo_mesh != null and _halo_mesh.get_surface_count() > 0:
		draw_mesh(_halo_mesh, null)
	if _extrude_mesh != null and _extrude_mesh.get_surface_count() > 0:
		draw_mesh(_extrude_mesh, null)
	if _land_mesh != null and _land_mesh.get_surface_count() > 0:
		draw_mesh(_land_mesh, null)
	if _border_mesh != null and _border_mesh.get_surface_count() > 0:
		draw_mesh(_border_mesh, null)
	if _hovered_id != "":
		_draw_region_outline(_hovered_id, HOVER_COLOR, 1.8)
	if not _disaster_ids.is_empty():
		_draw_disaster()
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

# --- Odak parıltısı (olay logundaki 🎯 düğmesi) -----------------------------------

## Bölgeyi duration saniye boyunca verilen renkte parlatır; icon (bkz.
## _draw_micro_icon) bölgenin üstünde yükselir.
func pulse_province(province_id: String, color: Color, icon: String = "", duration: float = 0.9) -> void:
	if not GameMap.ids.has(province_id):
		return
	_pulse = {"id": province_id, "color": color, "time": 0.0, "duration": duration, "icon": icon}
	set_process(true)
	queue_redraw()

## Animasyonlu çizimler (afet nabzı) saniyede en çok bu kadar yeniden çizilir:
## haritanın tamamı her karede baştan çizilmesin (performans).
const FX_REDRAW_INTERVAL := 1.0 / 30.0
var _fx_redraw_wait := 0.0

func _process(delta: float) -> void:
	_disaster_t += delta
	if _pulse.is_empty():
		if _disaster_ids.is_empty():
			set_process(false)
			queue_redraw()
			return
		_fx_redraw_wait -= delta
		if _fx_redraw_wait <= 0.0:
			_fx_redraw_wait = FX_REDRAW_INTERVAL
			queue_redraw()
		return
	_pulse["time"] = float(_pulse["time"]) + delta
	if float(_pulse["time"]) >= float(_pulse["duration"]):
		_pulse = {}
		if _disaster_ids.is_empty():
			set_process(false)
	queue_redraw()

# --- AFET BÖLGESİ (0.0.181) ---------------------------------------------------------
## Afet sürdüğü tur boyunca etkilenen iller çizgili örtü + nabız gibi atan
## kalın sınırla işaretlenir; bölgenin ortasında afet simgesi.
var _disaster_ids: Array = []
var _disaster_kind := ""
var _disaster_t := 0.0

func set_disaster(ids: Array, kind: String) -> void:
	if ids == _disaster_ids and kind == _disaster_kind:
		return
	_disaster_ids = ids.duplicate()
	_disaster_kind = kind
	set_process(not _disaster_ids.is_empty() or not _pulse.is_empty())
	queue_redraw()

func _draw_disaster() -> void:
	var color := Disaster.color(_disaster_kind)
	var glow: float = sin(_disaster_t * 3.2) * 0.5 + 0.5
	var fill := Color(color, 0.18 + 0.14 * glow)
	var center := Vector2.ZERO
	for id in _disaster_ids:
		_fill_region(String(id), fill)
	for id in _disaster_ids:
		center += GameMap.center_of(String(id))
	# Koyu alt çizgi + afet renginde nabız: her il renginin üstünde okunur.
	for id in _disaster_ids:
		_draw_region_outline(String(id), Color(UiTheme.INK, 0.85), 5.0)
	for id in _disaster_ids:
		_draw_region_outline(String(id), Color(color.lightened(0.25), 0.75 + 0.25 * glow), 2.4 + 1.6 * glow)
	center /= float(_disaster_ids.size())
	# Büyük uyarı rozeti: koyu daire, afet renginde üçgen, ünlem.
	var pos := center - Vector2(0, 6.0 + 4.0 * glow)
	draw_circle(pos, 15.0, Color(UiTheme.INK, 0.92))
	draw_arc(pos, 15.0, 0.0, TAU, 32, color.lightened(0.3), 2.0, true)
	draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -10), pos + Vector2(10, 8), pos + Vector2(-10, 8)]), color)
	draw_line(pos + Vector2(0, -4), pos + Vector2(0, 2.5), UiTheme.INK, 2.4)
	draw_circle(pos + Vector2(0, 5.2), 1.4, UiTheme.INK)

func _draw_pulse() -> void:
	var t: float = clampf(float(_pulse["time"]) / float(_pulse["duration"]), 0.0, 1.0)
	var glow: float = sin(t * PI * 3.0) * 0.5 + 0.5  # 1,5 nabız
	var fade: float = 1.0 - smoothstep(0.75, 1.0, t)
	var color: Color = _pulse["color"]
	var id: String = _pulse["id"]
	var fill := color
	fill.a = 0.45 * glow * fade
	_fill_region(id, fill)
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
		"alert":
			# Uyarı üçgeni (afet)
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -6), pos + Vector2(6, 5), pos + Vector2(-6, 5)]), fg)
			draw_line(pos + Vector2(0, -2), pos + Vector2(0, 1.5), Color(color.darkened(0.4), alpha), 1.6)
			draw_circle(pos + Vector2(0, 3.3), 0.9, Color(color.darkened(0.4), alpha))
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
		if isolated_id != "" and id != isolated_id:
			id = ""
		if id != _hovered_id:
			_hovered_id = id
			province_hovered.emit(id)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := get_province_id_at(to_local(event.global_position))
		if id != "" and (isolated_id == "" or id == isolated_id):
			province_clicked.emit(id)

func set_province_color(province_id: String, color: Color) -> void:
	if _colors.get(province_id, Color.TRANSPARENT) == color:
		return
	if color.a <= 0.0:
		_colors.erase(province_id)
	else:
		_colors[province_id] = color
	_colors_dirty = true
	queue_redraw()

func set_province_colors(id_to_color: Dictionary) -> void:
	var changed := false
	for province_id in id_to_color.keys():
		var color: Color = id_to_color[province_id]
		if _colors.get(province_id, Color.TRANSPARENT) == color:
			continue
		changed = true
		if color.a <= 0.0:
			_colors.erase(province_id)
		else:
			_colors[province_id] = color
	if changed:
		_colors_dirty = true
		queue_redraw()

func clear_overlay() -> void:
	if _colors.is_empty():
		return
	_colors.clear()
	_colors_dirty = true
	queue_redraw()

## Replace a layer atomically, so unchanged colors do not rebuild the mesh.
func replace_province_colors(colors: Dictionary) -> void:
	if _colors == colors:
		return
	_colors = colors.duplicate()
	_colors_dirty = true
	queue_redraw()

func set_white_borders(enabled: bool) -> void:
	if enabled == _white_borders:
		return
	_white_borders = enabled
	_build_geometry()
	queue_redraw()
