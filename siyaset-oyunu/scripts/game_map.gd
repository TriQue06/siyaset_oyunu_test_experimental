extends Node
## Autoload. OYUNUN HARİTASI: HexGridGenerator'ın ürettiği altıgen ülke.
## Host oyun başında yeni bir harita üretir ve tam durumla (CardManager)
## herkese gönderir; istemci aynı veriyi set_data() ile alır. Oyun yokken
## (menü, önizleme, testler) sabit tohumlu bir varsayılan harita durur.
##
## "province_id" oyunun her yerinde bir SEÇİM BÖLGESİ (il) kimliğidir: "b01"...
##
## HARİTA TÜRÜ (lobi ayarı world_settings["map_mode"], 0.0.219):
##   random          rastgele ÜLKE (0.0.261: CountryGenerator; serbest şekilli,
##                   yapboz gibi oturan iller). Eski kayıtlardaki altıgen
##                   ülke (HexGridGenerator, "cells") hâlâ okunur.
##   turkiye_altigen Türkiye'nin 81 ili, 80 sütunluk altıgen ızgara
## Türkiye verisi data/*.json (tools/harita/turkiye_harita_uret.py üretir). Ağda
## yalnız {"preset", "seed"} gider; herkes aynı dosyayı yerelden okur.

signal map_changed

const DEFAULT_SEED := 1950
## Bir altıgenin köşe yarıçapı (harita birimi). Harita sahnesi bu birimde çizilir.
## Türkiye haritalarında daha küçüktür (harita genişliği aynı kalsın): hex_radius.
const HEX_RADIUS := 10.0
const MAP_MODES := ["random", "turkiye_altigen"]
const PRESET_FILES := {"turkiye_altigen": "res://data/turkiye_altigen.json"}
const SQRT3 := 1.7320508

## Ağda giden veri (Türkiye haritasında yalnız preset + seed).
var data: Dictionary = {}
## Tam harita verisi (rastgele haritada data ile aynı).
var _full: Dictionary = {}
var hex_radius: float = HEX_RADIUS
static var _preset_cache: Dictionary = {}
var cols: int = 0
var rows: int = 0
## Array[int]: hücre -> bölge indeksi (-1 = deniz)
var cells: Array = []
var ids: Array = []
var _index_of: Dictionary = {}     # province_id -> bölge indeksi
var _names: Dictionary = {}        # province_id -> ad
var _seats: Dictionary = {}        # province_id -> vekil
var _neighbors: Dictionary = {}    # province_id -> Array[province_id]
var _region_cells: Dictionary = {} # province_id -> Array[hücre]
var _centers: Dictionary = {}      # province_id -> Vector2 (etiket/nokta merkezi)
var _coastal: Dictionary = {}
## ÜLKE haritası (CountryGenerator.geometry); altıgen haritada boş.
var country: Dictionary = {}
var _buckets: Dictionary = {}  # Vector2i -> Array[nokta] (il sorgusu)
const BUCKET := CountryGenerator.SPACING * 1.5

func _ready() -> void:
	set_data(CountryGenerator.generate(DEFAULT_SEED))

## Host: yeni oyun için yeni harita.
func generate_new(seed_value: int) -> void:
	var mode := String(MultiplayerManager.world_settings.get("map_mode", "random"))
	if PRESET_FILES.has(mode):
		set_data({"preset": mode, "seed": seed_value})
		return
	set_data(CountryGenerator.generate(seed_value, float(MultiplayerManager.world_settings["province_scale"]), int(MultiplayerManager.world_settings["province_seats"])))

## Türkiye haritası dosyası (bir kez okunur).
static func load_preset(preset: String) -> Dictionary:
	if not _preset_cache.has(preset):
		var text := FileAccess.get_file_as_string(String(PRESET_FILES.get(preset, "")))
		var parsed = JSON.parse_string(text) if text != "" else null
		_preset_cache[preset] = parsed if parsed is Dictionary else {}
	return _preset_cache[preset]

## Türkiye haritasının toplam il milletvekili (lobide gösterilir).
static func preset_seat_total(preset: String) -> int:
	var total := 0
	for region in load_preset(preset).get("regions", []):
		total += int(region["seats"])
	return total

func is_country() -> bool:
	return not country.is_empty()

func is_turkey() -> bool:
	return PRESET_FILES.has(String(data.get("preset", "")))

func set_data(new_data: Dictionary) -> void:
	if new_data.is_empty():
		return
	var full := new_data
	if new_data.has("preset") and not new_data.has("cells"):
		full = load_preset(String(new_data["preset"])).duplicate()
		if full.is_empty():
			push_error("Harita dosyası okunamadı: %s" % new_data["preset"])
			return
		full["seed"] = new_data.get("seed", 0)
		data = {"preset": new_data["preset"], "seed": new_data.get("seed", 0)}
	else:
		data = new_data
	_full = full
	country = {}
	_buckets.clear()
	hex_radius = float(full.get("hex_radius", HEX_RADIUS))
	var is_country_map := String(full.get("kind", "")) == CountryGenerator.KIND
	cols = 0 if is_country_map else int(full["cols"])
	rows = 0 if is_country_map else int(full["rows"])
	cells = []
	if not is_country_map:
		for v in full["cells"]:
			cells.append(int(v))
	ids.clear()
	_index_of.clear()
	_names.clear()
	_seats.clear()
	_coastal.clear()
	var regions: Array = full["regions"]
	for i in regions.size():
		var region: Dictionary = regions[i]
		var id := String(region["id"])
		ids.append(id)
		_index_of[id] = i
		_names[id] = String(region["name"])
		_seats[id] = int(region["seats"])
		_coastal[id] = bool(region.get("coastal", false))
	if is_country_map:
		_derive_country(full)
	else:
		_derive()
	map_changed.emit()

## Ülke haritası: çizim geometrisi, komşuluk, merkezler ve il sorgusu kovaları.
func _derive_country(full: Dictionary) -> void:
	country = CountryGenerator.geometry(full)
	_neighbors.clear()
	_region_cells.clear()
	_centers.clear()
	for r in ids.size():
		var id: String = ids[r]
		var list: Array = []
		for o in country["neighbors"][r]:
			list.append(ids[int(o)])
		_neighbors[id] = list
		_centers[id] = country["centers"][r]
		_region_cells[id] = []
	var points: PackedVector2Array = country["points"]
	var labels: PackedInt32Array = country["labels"]
	for i in points.size():
		if labels[i] < 0:
			continue
		var key := Vector2i(floori(points[i].x / BUCKET), floori(points[i].y / BUCKET))
		if not _buckets.has(key):
			_buckets[key] = []
		(_buckets[key] as Array).append(i)

func seed_value() -> int:
	return int(data.get("seed", 0))

## Komşuluklar, bölge hücreleri ve merkezler hücrelerden türetilir (ağda gitmez).
func _derive() -> void:
	_neighbors.clear()
	_region_cells.clear()
	_centers.clear()
	var sets := {}
	for id in ids:
		sets[id] = {}
		_region_cells[id] = []
	for i in cells.size():
		var r: int = cells[i]
		if r < 0:
			continue
		var id: String = ids[r]
		_region_cells[id].append(i)
		for n in HexGridGenerator.neighbor_cells(i, cols, rows):
			var o: int = cells[n]
			if o >= 0 and o != r:
				sets[id][ids[o]] = true
	for id in ids:
		_neighbors[id] = (sets[id] as Dictionary).keys()
		_centers[id] = _widest_center(id)

## VEKİL NOKTALARININ YERİ: ilin EN GENİŞ ve en merkezi yeri. Her hücrenin
## "derinliği" (il sınırına kaç hücre uzak) ölçülür; en derin hücreler ilin
## en geniş kısmıdır. Bunlar arasından ilin ağırlık merkezine en yakın olan
## seçilir; en derin hücreler bitişikse noktalar onların ortasına oturur.
func _widest_center(id: String) -> Vector2:
	var region_cells: Array = _region_cells[id]
	if region_cells.is_empty():
		return Vector2.ZERO
	var r: int = _index_of[id]
	var depth := {}
	var queue: Array = []
	for c in region_cells:
		var around := HexGridGenerator.neighbor_cells(c, cols, rows)
		var edge := around.size() < 6
		for n in around:
			if cells[n] != r:
				edge = true
				break
		if edge:
			depth[c] = 0
			queue.append(c)
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for n in HexGridGenerator.neighbor_cells(cur, cols, rows):
			if cells[n] == r and not depth.has(n):
				depth[n] = int(depth[cur]) + 1
				queue.append(n)
	var max_depth := 0
	var sum := Vector2.ZERO
	for c in region_cells:
		max_depth = maxi(max_depth, int(depth.get(c, 0)))
		sum += cell_center(c)
	var mean := sum / float(region_cells.size())
	var deepest: Array = []
	for c in region_cells:
		if int(depth.get(c, 0)) == max_depth:
			deepest.append(c)
	# En derin hücrelerden merkeze en yakını.
	var best: int = deepest[0]
	for c in deepest:
		if cell_center(c).distance_squared_to(mean) < cell_center(best).distance_squared_to(mean):
			best = c
	# Birbirine komşu en derin hücreler varsa ortalarına (hâlâ il içinde kalır).
	var cluster: Array = [best]
	for c in deepest:
		if c != best and HexGridGenerator.hex_distance(c, best, cols) == 1:
			cluster.append(c)
	var point := Vector2.ZERO
	for c in cluster:
		point += cell_center(c)
	point /= float(cluster.size())
	return point if province_at(point) == id else cell_center(best)

func _is_interior(cell: int) -> bool:
	var r: int = cells[cell]
	var around := HexGridGenerator.neighbor_cells(cell, cols, rows)
	if around.size() < 6:
		return false
	for n in around:
		if cells[n] != r:
			return false
	return true

# --- Sorgular -------------------------------------------------------------------

func province_ids() -> Array:
	return ids.duplicate()

func name_of(province_id: String) -> String:
	return String(_names.get(province_id, province_id))

func seats_of(province_id: String) -> int:
	return int(_seats.get(province_id, 0))

## province_id -> vekil sayısı
func seat_counts() -> Dictionary:
	return _seats.duplicate()

func neighbors() -> Dictionary:
	return _neighbors

func is_coastal(province_id: String) -> bool:
	return bool(_coastal.get(province_id, false))

func region_cells(province_id: String) -> Array:
	return _region_cells.get(province_id, [])

func center_of(province_id: String) -> Vector2:
	return _centers.get(province_id, Vector2.ZERO)

func region_at_cell(cell: int) -> String:
	if cell < 0 or cell >= cells.size() or cells[cell] < 0:
		return ""
	return ids[cells[cell]]

# --- Geometri (sivri tepeli, odd-r) ----------------------------------------------

func map_size() -> Vector2:
	if is_country():
		return Vector2(float(_full["width"]), float(_full["height"]))
	return Vector2(SQRT3 * hex_radius * (cols + 0.5), 1.5 * hex_radius * (rows - 1) + 2.0 * hex_radius)

func cell_center(cell: int) -> Vector2:
	var col := cell % cols
	var row := cell / cols
	return Vector2(SQRT3 * hex_radius * (col + 0.5 * (row & 1) + 0.5), 1.5 * hex_radius * row + hex_radius)

## Altıgenin 6 köşesi (scale < 1 içe çeker: hücreler arası ince boşluk).
func cell_corners(cell: int, scale: float = 1.0) -> PackedVector2Array:
	var c := cell_center(cell)
	var points := PackedVector2Array()
	for k in 6:
		var angle := deg_to_rad(60.0 * k - 30.0)
		points.append(c + Vector2(cos(angle), sin(angle)) * hex_radius * scale)
	return points

## Harita birimindeki bir noktanın hücresi (-1: harita dışı).
func cell_at(point: Vector2) -> int:
	var px := point.x - SQRT3 * hex_radius * 0.5
	var py := point.y - hex_radius
	var q := (SQRT3 / 3.0 * px - py / 3.0) / hex_radius
	var r := (2.0 / 3.0 * py) / hex_radius
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	var row := int(rz)
	var col := int(rx) + (row - (row & 1)) / 2
	if col < 0 or row < 0 or col >= cols or row >= rows:
		return -1
	return row * cols + col

func province_at(point: Vector2) -> String:
	if is_country():
		return _country_province_at(point)
	return region_at_cell(cell_at(point))

## Ülke haritasında nokta sorgusu: yakındaki hücrelerin üçgenleri denenir
## (çizilen yumuşatılmış sınırla birebir aynı).
func _country_province_at(point: Vector2) -> String:
	var base := Vector2i(floori(point.x / BUCKET), floori(point.y / BUCKET))
	var cell_tris: Dictionary = country["cell_tris"]
	var labels: PackedInt32Array = country["labels"]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for i in _buckets.get(base + Vector2i(dx, dy), []):
				var tris: PackedVector2Array = cell_tris.get(i, PackedVector2Array())
				for k in range(0, tris.size(), 3):
					if Geometry2D.point_is_inside_triangle(point, tris[k], tris[k + 1], tris[k + 2]):
						return ids[labels[i]]
	return ""

func electorate_counts() -> Dictionary:
	var result := {}
	for region in _full.get("regions", []):
		result[String(region["id"])] = int(region.get("electorate", int(region["seats"]) * 100000))
	return result
