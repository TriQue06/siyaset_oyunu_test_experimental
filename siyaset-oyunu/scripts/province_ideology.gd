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
## Komşuluk altıgen haritadan gelir (GameMap): deniz ile ayrılan bölgeler
## komşu sayılmaz.

const SMOOTHING_PASSES := 3
## Yumuşatmada ilin kendi değerinin payı (kalanı komşuların ortalaması).
const SELF_WEIGHT := 0.4
## Yayma sonrası en uç ilin mutlak değeri (yuvarlamadan önce).
const SPREAD := 3.3


## province_id -> Array[province_id] (altıgen haritadan).
static func neighbors() -> Dictionary:
	var map = Engine.get_main_loop().root.get_node_or_null("GameMap") if Engine.get_main_loop() is SceneTree else null
	return map.neighbors() if map != null else {}

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
