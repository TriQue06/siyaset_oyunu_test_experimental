class_name ProvinceIdeology
extends RefCounted
## İLLERİN GÖRÜŞÜ: her oyunun başında host üretir, oyun boyunca değişmez.
## Her il 3 eksende -3..+3 arası tam sayı bir noktadır. KOMŞU iller birbirine
## yakın görüşte olur:
##   1. Her ile her eksende rastgele bir değer verilir.
##   2. Değerler komşuluk grafiği üzerinde birkaç kez yumuşatılır (her il,
##      komşularının ortalamasına yaklaşır).
##   3. Yumuşatma değerleri merkeze topladığı için her eksen yeniden -3..+3
##      aralığına yayılır ve tam sayıya yuvarlanır.
## Komşuluk, piksel haritasında (data/province_pixel_map.json) birbirine
## NEIGHBOR_RADIUS pikselden yakın duran farklı illerin piksellerinden
## çıkarılır — deniz ile ayrılan iller komşu sayılmaz.

const PIXEL_MAP_PATH := "res://data/province_pixel_map.json"
const SMOOTHING_PASSES := 3
## Yumuşatmada ilin kendi değerinin payı (kalanı komşuların ortalaması).
const SELF_WEIGHT := 0.4
## Yayma sonrası en uç ilin mutlak değeri (yuvarlamadan önce).
const SPREAD := 3.3
## Komşuluk ararken bakılan piksel yarıçapı (il sınırlarındaki kontur kalınlığı).
const NEIGHBOR_RADIUS := 2

static var _neighbors_cache: Dictionary = {}

## province_id -> Array[province_id]
static func neighbors() -> Dictionary:
	if not _neighbors_cache.is_empty():
		return _neighbors_cache
	if not FileAccess.file_exists(PIXEL_MAP_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PIXEL_MAP_PATH))
	if not (parsed is Dictionary):
		return {}
	var width: int = int(parsed["width"])
	var height: int = int(parsed["height"])
	var ids: Array = parsed["ids"]
	var grid: Array = parsed["grid"]
	var sets: Dictionary = {}
	for province_id in ids:
		sets[province_id] = {}
	# İller arasında ince kontur pikselleri (-1) olduğu için doğrudan yan
	# piksel yetmez: NEIGHBOR_RADIUS içindeki pikseller de taranır (her çift
	# bir kez: sağ ve aşağı yarı-pencere).
	for y in height:
		for x in width:
			var a: int = int(grid[y * width + x])
			if a < 0:
				continue
			for dy in range(0, NEIGHBOR_RADIUS + 1):
				for dx in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
					if dy == 0 and dx <= 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or nx >= width or ny >= height:
						continue
					_link(sets, ids, a, int(grid[ny * width + nx]))
	for province_id in sets.keys():
		_neighbors_cache[province_id] = (sets[province_id] as Dictionary).keys()
	return _neighbors_cache

static func _link(sets: Dictionary, ids: Array, a: int, b: int) -> void:
	if b < 0 or b == a or a >= ids.size() or b >= ids.size():
		return
	sets[ids[a]][ids[b]] = true
	sets[ids[b]][ids[a]] = true

## province_id -> {"economic": int, "social": int, "administrative": int}
static func generate(rng: RandomNumberGenerator, province_ids: Array) -> Dictionary:
	var ids: Array = province_ids.duplicate()
	ids.sort()  # aynı tohum her makinede aynı haritayı versin
	var nb := neighbors()
	var values: Dictionary = {}
	for province_id in ids:
		var point := {}
		for axis in IdeologyAxes.AXES:
			point[axis] = rng.randf_range(-3.0, 3.0)
		values[province_id] = point

	for pass_index in SMOOTHING_PASSES:
		var next: Dictionary = {}
		for province_id in ids:
			var around: Array = []
			for other in nb.get(province_id, []):
				if values.has(other):
					around.append(other)
			var point := {}
			for axis in IdeologyAxes.AXES:
				var own: float = float(values[province_id][axis])
				if around.is_empty():
					point[axis] = own
					continue
				var sum := 0.0
				for other in around:
					sum += float(values[other][axis])
				point[axis] = SELF_WEIGHT * own + (1.0 - SELF_WEIGHT) * sum / around.size()
			next[province_id] = point
		values = next

	var result: Dictionary = {}
	for province_id in ids:
		result[province_id] = {}
	for axis in IdeologyAxes.AXES:
		var max_abs := 0.0001
		for province_id in ids:
			max_abs = maxf(max_abs, absf(float(values[province_id][axis])))
		var scale := SPREAD / max_abs
		for province_id in ids:
			result[province_id][axis] = clampi(roundi(float(values[province_id][axis]) * scale),
				IdeologyAxes.AXIS_MIN, IdeologyAxes.AXIS_MAX)
	return result
