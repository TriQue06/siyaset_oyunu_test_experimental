class_name ProvinceIdeology
extends RefCounted
## İLLERİN DOĞAL GÖRÜŞÜ: her oyunun başında host üretir. İller NÖTRE YAKIN
## başlar: her eksende −MAX_START..+MAX_START (en fazla ±1). Oyun boyunca
## partiler teşkilat, miting ve yatırımla illeri kendilerine çeker (bkz.
## CardManager._pull_province). KOMŞU iller birbirine yakın görüşte olur:
##   1. Her ile her eksende rastgele bir değer verilir.
##   2. Değerler komşuluk grafiği üzerinde birkaç kez yumuşatılır (her il,
##      komşularının ortalamasına yaklaşır).
##   3. Yumuşatma değerleri merkeze topladığı için her eksen yeniden
##      −MAX_START..+MAX_START aralığına yayılır (0,1 adımlı).
## Komşuluk altıgen haritadan gelir (GameMap): deniz ile ayrılan bölgeler
## komşu sayılmaz.

const SMOOTHING_PASSES := 3
## Yumuşatmada ilin kendi değerinin payı (kalanı komşuların ortalaması).
const SELF_WEIGHT := 0.4
## Oyun başında bir ilin bir eksende en uç değeri.
const MAX_START := 1.0


## province_id -> Array[province_id] (altıgen haritadan).
static func neighbors() -> Dictionary:
	var map = Engine.get_main_loop().root.get_node_or_null("GameMap") if Engine.get_main_loop() is SceneTree else null
	return map.neighbors() if map != null else {}

## province_id -> {"economic": float, "social": float, "administrative": float}
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
		var scale := MAX_START / max_abs
		for province_id in ids:
			result[province_id][axis] = clampf(snappedf(float(values[province_id][axis]) * scale, 0.1),
				-MAX_START, MAX_START)
	return result
