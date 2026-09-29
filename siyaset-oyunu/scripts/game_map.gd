extends Node
## Autoload. OYUNUN HARİTASI: HexGridGenerator'ın ürettiği altıgen ülke.
## Host oyun başında yeni bir harita üretir ve tam durumla (CardManager)
## herkese gönderir; istemci aynı veriyi set_data() ile alır. Oyun yokken
## (menü, önizleme, testler) sabit tohumlu bir varsayılan harita durur.
##
## "province_id" oyunun her yerinde bir SEÇİM BÖLGESİ (il) kimliğidir: "b01"...

signal map_changed

const DEFAULT_SEED := 1950
## Bir altıgenin köşe yarıçapı (harita birimi). Harita sahnesi bu birimde çizilir.
const HEX_RADIUS := 10.0
const SQRT3 := 1.7320508

var data: Dictionary = {}
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

func _ready() -> void:
	set_data(HexGridGenerator.generate(DEFAULT_SEED))

## Host: yeni oyun için yeni harita.
func generate_new(seed_value: int) -> void:
	set_data(HexGridGenerator.generate(seed_value))

func set_data(new_data: Dictionary) -> void:
	if new_data.is_empty():
		return
	data = new_data
	cols = int(data["cols"])
	rows = int(data["rows"])
	cells = []
	for v in data["cells"]:
		cells.append(int(v))
	ids.clear()
	_index_of.clear()
	_names.clear()
	_seats.clear()
	_coastal.clear()
	var regions: Array = data["regions"]
	for i in regions.size():
		var region: Dictionary = regions[i]
		var id := String(region["id"])
		ids.append(id)
		_index_of[id] = i
		_names[id] = String(region["name"])
		_seats[id] = int(region["seats"])
		_coastal[id] = bool(region.get("coastal", false))
	_derive()
	map_changed.emit()

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
	return Vector2(SQRT3 * HEX_RADIUS * (cols + 0.5), 1.5 * HEX_RADIUS * (rows - 1) + 2.0 * HEX_RADIUS)

func cell_center(cell: int) -> Vector2:
	var col := cell % cols
	var row := cell / cols
	return Vector2(SQRT3 * HEX_RADIUS * (col + 0.5 * (row & 1) + 0.5), 1.5 * HEX_RADIUS * row + HEX_RADIUS)

## Altıgenin 6 köşesi (scale < 1 içe çeker: hücreler arası ince boşluk).
func cell_corners(cell: int, scale: float = 1.0) -> PackedVector2Array:
	var c := cell_center(cell)
	var points := PackedVector2Array()
	for k in 6:
		var angle := deg_to_rad(60.0 * k - 30.0)
		points.append(c + Vector2(cos(angle), sin(angle)) * HEX_RADIUS * scale)
	return points

## Harita birimindeki bir noktanın hücresi (-1: harita dışı).
func cell_at(point: Vector2) -> int:
	var px := point.x - SQRT3 * HEX_RADIUS * 0.5
	var py := point.y - HEX_RADIUS
	var q := (SQRT3 / 3.0 * px - py / 3.0) / HEX_RADIUS
	var r := (2.0 / 3.0 * py) / HEX_RADIUS
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
	return region_at_cell(cell_at(point))
