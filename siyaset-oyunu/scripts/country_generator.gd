class_name CountryGenerator
extends RefCounted
## ÜLKE ÜRETİCİSİ (0.0.261): gerçek bir ülke haritası gibi, birbirine yapboz
## gibi oturan, şekli serbest iller.
##
## YÖNTEM (Azgaar tarzı):
##   1. Harita binlerce küçük hücreye bölünür: sarsılmış ızgara noktaları ve
##      onların Voronoi hücreleri (Delaunay üçgenlemesinin çevrel merkezleri).
##   2. Kara: gürültü (fbm) + eliptik düşüş + birkaç yarımada tümseği; eşik,
##      karanın payı LAND_FRACTION olacak şekilde seçilir. En büyük kara
##      parçası ve yeterince büyük adalar kalır, göller doldurulur.
##   3. İller: dengeli dağılmış tohum hücrelerden çok kaynaklı Dijkstra ile
##      büyür. Kenar maliyeti "sırt" gürültüsüyle artar: sınırlar dağ sırtı ve
##      vadi gibi doğal çizgilere oturur; her tohumun kendi hızı il boylarını
##      çeşitlendirir (büyükşehirler küçük, kırsal büyük).
##   4. Çizim (geometry): hücre köşelerinden sınırda olanlar, iki komşusunun
##      ortalamasına doğru birkaç kez çekilir (kavşaklar sabit). İki il AYNI
##      köşeleri paylaştığı için yumuşatılmış sınırlar yine kusursuz oturur.
##
## AĞDA GİDEN VERİ: noktalar (0,01'e yuvarlanmış), her noktanın ili (-1 deniz)
## ve il listesi. Üçgenleme ve yumuşatma herkesin cihazında aynı girdiden,
## aynı sonuçla yeniden hesaplanır (bkz. geometry).

const KIND := "country"
const WIDTH := 900.0
const HEIGHT := 410.0
## Küçük hücrelerin aralığı (harita birimi). Küçüldükçe sınırlar incelir ama
## üretim ve çizim yavaşlar.
const SPACING := 8.0
## Kenar payı: bu kadar hücre ülkeye ait olamaz (deniz çerçevesi).
const MARGIN_CELLS := 3
const LAND_FRACTION := 0.5
## Kırpılan haritada karanın çevresinde kalan deniz payı.
const CROP_PAD := SPACING * 2.5
## Varsayılan il sayısı (province_scale 1); eski altıgen haritayla aynı ölçek.
const PROVINCES := 46
const MIN_PROVINCE_CELLS := 12
const MIN_ISLAND_CELLS := 45
const METRO_COUNT := 5
const SMOOTH_ITERATIONS := 6
## Sınır kıvrımlarının genliği (harita birimi).
const WIGGLE := 3.2
const VOTERS_PER_SEAT := 100000

static func generate(seed_value: int, province_scale: float = 1.0, seat_total: int = 300) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points := _points(rng)
	var topo := topology(points)
	var land := _land(points, topo, rng)
	var count := maxi(6, int(roundf(PROVINCES / maxf(0.25, province_scale))))
	var labels := _grow(points, topo, land, count, rng)
	count = _compact(labels, points)
	var coastal := _coastal(labels, topo, count)
	var population := _population(points, topo, labels, count, rng)
	var seats := HexGridGenerator._allocate_seats(population, seat_total)
	var names := _names(points, labels, count, coastal, population, rng)
	var regions: Array = []
	for i in count:
		regions.append({"id": "b%02d" % (i + 1), "name": names[i], "seats": int(seats[i]), "coastal": bool(coastal[i]),
			"electorate": int(seats[i]) * VOTERS_PER_SEAT})
	# Harita karaya göre kırpılır: ülke çerçeveyi doldursun (etrafta ince deniz).
	var box := Rect2()
	var first := true
	for i in points.size():
		if labels[i] < 0:
			continue
		if first:
			box = Rect2(points[i], Vector2.ZERO)
			first = false
		else:
			box = box.expand(points[i])
	box = box.grow(CROP_PAD)
	var flat: Array = []
	for p in points:
		flat.append(snappedf(p.x - box.position.x, 0.01))
		flat.append(snappedf(p.y - box.position.y, 0.01))
	return {"kind": KIND, "seed": seed_value, "width": ceilf(box.size.x), "height": ceilf(box.size.y), "points": flat,
		"labels": Array(labels), "regions": regions}

# --- 1. Noktalar ve üçgenleme ------------------------------------------------------

## Sarsılmış, satırları kaydırılmış ızgara (Voronoi hücreleri altıgene yakın ama
## düzensiz). Haritanın dışında da bir halka nokta vardır: kenar hücreleri kapanır.
static func _points(rng: RandomNumberGenerator) -> PackedVector2Array:
	var out := PackedVector2Array()
	var row_h := SPACING * 0.866
	var rows := int(ceil(HEIGHT / row_h)) + 4
	var cols := int(ceil(WIDTH / SPACING)) + 4
	for r in rows:
		for c in cols:
			var x := (c - 2 + (0.5 if r % 2 == 1 else 0.0)) * SPACING + rng.randf_range(-0.38, 0.38) * SPACING
			var y := (r - 2) * row_h + rng.randf_range(-0.38, 0.38) * row_h
			out.append(Vector2(snappedf(x, 0.01), snappedf(y, 0.01)))
	return out

## Delaunay üçgenlemesi ve Voronoi köşeleri.
##   tris     : PackedInt32Array (üçlüler)
##   centers  : PackedVector2Array, üçgen -> çevrel merkez (Voronoi köşesi)
##   adj      : Array[PackedInt32Array], nokta -> komşu noktalar
##   ptris    : Array[PackedInt32Array], nokta -> üçgenler (açıya göre sıralı)
##   edge_tris: Dictionary, a * n + b (a < b) -> Vector2i(t1, t2) (t2 = -1: dış kenar)
static func topology(points: PackedVector2Array) -> Dictionary:
	var n := points.size()
	var tris := Geometry2D.triangulate_delaunay(points)
	var tcount := tris.size() / 3
	var centers := PackedVector2Array()
	centers.resize(tcount)
	var adj_sets: Array = []
	var ptris: Array = []
	for i in n:
		adj_sets.append({})
		ptris.append([])
	var edge_tris := {}
	for t in tcount:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		# Neredeyse çember üstündeki üçgenlerin çevrel merkezi uzağa düşer ve
		# hücreyi büker: o zaman ağırlık merkezi kullanılır.
		var mid := (points[a] + points[b] + points[c]) / 3.0
		var cc := _circumcenter(points[a], points[b], points[c])
		centers[t] = cc if cc.distance_to(mid) < SPACING * 0.75 else mid
		for pair in [[a, b], [b, c], [c, a]]:
			var u: int = mini(pair[0], pair[1])
			var v: int = maxi(pair[0], pair[1])
			adj_sets[u][v] = true
			adj_sets[v][u] = true
			var key := u * n + v
			if edge_tris.has(key):
				var e: Vector2i = edge_tris[key]
				edge_tris[key] = Vector2i(e.x, t)
			else:
				edge_tris[key] = Vector2i(t, -1)
		for p in [a, b, c]:
			(ptris[p] as Array).append(t)
	var adj: Array = []
	for i in n:
		adj.append(PackedInt32Array((adj_sets[i] as Dictionary).keys()))
		# Halka sırası üçgenlerin AĞIRLIK merkezinin açısıyla (çevrel merkez
		# üçgenin dışına düşebilir ve sırayı bozar; ağırlık merkezi bozmaz).
		var origin := points[i]
		var sorted: Array = ptris[i]
		sorted.sort_custom(func(x, y): return (_centroid(points, tris, x) - origin).angle() < (_centroid(points, tris, y) - origin).angle())
		ptris[i] = PackedInt32Array(sorted)
	return {"tris": tris, "centers": centers, "adj": adj, "ptris": ptris, "edge_tris": edge_tris, "n": n}

static func _centroid(points: PackedVector2Array, tris: PackedInt32Array, t: int) -> Vector2:
	return (points[tris[t * 3]] + points[tris[t * 3 + 1]] + points[tris[t * 3 + 2]]) / 3.0

static func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.000001:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2((a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)

static func _inside(p: Vector2) -> bool:
	var m := SPACING * MARGIN_CELLS
	return p.x > m and p.y > m and p.x < WIDTH - m and p.y < HEIGHT - m

# --- 2. Kara ----------------------------------------------------------------------

static func _land(points: PackedVector2Array, topo: Dictionary, rng: RandomNumberGenerator) -> PackedByteArray:
	var n := points.size()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.0055
	var warp := FastNoiseLite.new()
	warp.seed = rng.randi()
	warp.frequency = 0.004
	var center := Vector2(WIDTH * rng.randf_range(0.45, 0.55), HEIGHT * rng.randf_range(0.45, 0.55))
	var radius := Vector2(WIDTH * rng.randf_range(0.36, 0.44), HEIGHT * rng.randf_range(0.34, 0.42))
	# Yarımada ve körfez tümsekleri: kıyı çizgisini çeşitlendirir.
	var bumps: Array = []
	for k in rng.randi_range(3, 6):
		var angle := rng.randf() * TAU
		var at := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y) * rng.randf_range(0.6, 1.05)
		bumps.append([at, rng.randf_range(40.0, 90.0), rng.randf_range(-0.45, 0.55)])
	var height := PackedFloat32Array()
	height.resize(n)
	var inside_values: Array = []
	for i in n:
		var p := points[i]
		if not _inside(p):
			height[i] = -9.0
			continue
		var q := p + Vector2(warp.get_noise_2d(p.x, p.y), warp.get_noise_2d(p.x + 913.0, p.y - 377.0)) * 60.0
		var d := ((q - center) / radius).length()
		var h := (1.0 - d) + noise.get_noise_2d(p.x, p.y) * 0.75
		for bump in bumps:
			var dist: float = (p - (bump[0] as Vector2)).length()
			h += float(bump[2]) * exp(-(dist * dist) / (2.0 * float(bump[1]) * float(bump[1])))
		# Kenara yaklaştıkça deniz: çerçeveye değen kara kalmasın.
		var edge := minf(minf(p.x, WIDTH - p.x) / WIDTH, minf(p.y, HEIGHT - p.y) / HEIGHT)
		h -= maxf(0.0, 0.09 - edge) * 6.0
		height[i] = h
		inside_values.append(h)
	inside_values.sort()
	var threshold: float = inside_values[int((1.0 - LAND_FRACTION) * (inside_values.size() - 1))]
	var land := PackedByteArray()
	land.resize(n)
	for i in n:
		land[i] = 1 if height[i] > threshold else 0
	# Kara parçaları: en büyüğü ve büyük adalar kalır.
	var comps := _components(land, 1, topo)
	comps.sort_custom(func(a, b): return a.size() > b.size())
	for k in comps.size():
		if k > 0 and (comps[k] as Array).size() < MIN_ISLAND_CELLS:
			for i in comps[k]:
				land[i] = 0
	# Göller: dış denize bağlı olmayan su doldurulur.
	for comp in _components(land, 0, topo):
		var open := false
		for i in comp:
			if not _inside(points[i]):
				open = true
				break
		if not open:
			for i in comp:
				land[i] = 1
	return land

static func _components(land: PackedByteArray, value: int, topo: Dictionary) -> Array:
	var seen := PackedByteArray()
	seen.resize(land.size())
	var out: Array = []
	for start in land.size():
		if land[start] != value or seen[start] == 1:
			continue
		var comp: Array = [start]
		seen[start] = 1
		var head := 0
		while head < comp.size():
			var cur: int = comp[head]
			head += 1
			for nb in (topo["adj"][cur] as PackedInt32Array):
				if land[nb] == value and seen[nb] == 0:
					seen[nb] = 1
					comp.append(nb)
		out.append(comp)
	return out

# --- 3. İller ---------------------------------------------------------------------

static func _grow(points: PackedVector2Array, topo: Dictionary, land: PackedByteArray, count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var n := points.size()
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var land_cells: Array = []
	for i in n:
		if land[i] == 1:
			land_cells.append(i)
	# Her kara parçasına (ada) en az bir tohum; kalanlar en iyi aday yöntemiyle
	# (rastgele adaylardan mevcut tohumlara en uzak olanı) dengeli dağılır.
	var seeds: Array = []
	var comps := _components(land, 1, topo)
	comps.sort_custom(func(a, b): return a.size() > b.size())
	for comp in comps:
		var arr: Array = comp
		var share := maxi(1, int(roundf(float(count) * arr.size() / land_cells.size())))
		for k in share:
			seeds.append(_best_candidate(arr, seeds, points, rng))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 3
	noise.frequency = 0.012
	var speed: Array = []
	for k in seeds.size():
		speed.append(rng.randf_range(0.75, 1.35))
	for k in mini(3, seeds.size()):
		speed[rng.randi_range(0, seeds.size() - 1)] = 0.6  # büyükşehir: küçük il
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var heap := _Heap.new()
	for k in seeds.size():
		var s: int = seeds[k]
		dist[s] = 0.0
		labels[s] = k
		heap.push(0.0, s)
	while not heap.empty():
		var top := heap.pop()
		var cost: float = top[0]
		var cur: int = top[1]
		if cost > dist[cur]:
			continue
		var lab := labels[cur]
		for nb in (topo["adj"][cur] as PackedInt32Array):
			if land[nb] == 0:
				continue
			var mid := (points[cur] + points[nb]) * 0.5
			var ridge := (noise.get_noise_2d(mid.x, mid.y) + 1.0) * 0.5
			var step := points[cur].distance_to(points[nb]) * (0.55 + 2.2 * ridge * ridge) / float(speed[lab])
			if cost + step < dist[nb]:
				dist[nb] = cost + step
				labels[nb] = lab
				heap.push(cost + step, nb)
	_merge_small(labels, topo)
	return labels

static func _best_candidate(cells: Array, seeds: Array, points: PackedVector2Array, rng: RandomNumberGenerator) -> int:
	var best: int = cells[rng.randi_range(0, cells.size() - 1)]
	if seeds.is_empty():
		return best
	var best_d := -1.0
	for _k in 14:
		var c: int = cells[rng.randi_range(0, cells.size() - 1)]
		var d := INF
		for s in seeds:
			d = minf(d, points[c].distance_squared_to(points[int(s)]))
		if d > best_d:
			best_d = d
			best = c
	return best

## Çok küçük iller en çok sınır paylaştıkları komşuya katılır.
static func _merge_small(labels: PackedInt32Array, topo: Dictionary) -> void:
	for _pass in 4:
		var sizes := {}
		for v in labels:
			if v >= 0:
				sizes[v] = int(sizes.get(v, 0)) + 1
		var changed := false
		for lab in sizes.keys():
			if int(sizes[lab]) >= MIN_PROVINCE_CELLS:
				continue
			var votes := {}
			for i in labels.size():
				if labels[i] != lab:
					continue
				for nb in (topo["adj"][i] as PackedInt32Array):
					var o := labels[nb]
					if o >= 0 and o != lab:
						votes[o] = int(votes.get(o, 0)) + 1
			if votes.is_empty():
				continue  # tek hücreli ada: kalsın
			var target: int = votes.keys()[0]
			for o in votes.keys():
				if int(votes[o]) > int(votes[target]):
					target = o
			for i in labels.size():
				if labels[i] == lab:
					labels[i] = target
			changed = true
		if not changed:
			return

## İl numaraları 0..k-1, batıdan doğuya sıralı. Dönüş: il sayısı.
static func _compact(labels: PackedInt32Array, points: PackedVector2Array) -> int:
	var sums := {}
	var counts := {}
	for i in labels.size():
		var v := labels[i]
		if v < 0:
			continue
		sums[v] = sums.get(v, Vector2.ZERO) + points[i]
		counts[v] = int(counts.get(v, 0)) + 1
	var order: Array = sums.keys()
	order.sort_custom(func(a, b):
		var ca: Vector2 = sums[a] / float(counts[a])
		var cb: Vector2 = sums[b] / float(counts[b])
		return ca.x + ca.y * 0.15 < cb.x + cb.y * 0.15)
	var remap := {}
	for k in order.size():
		remap[order[k]] = k
	for i in labels.size():
		if labels[i] >= 0:
			labels[i] = int(remap[labels[i]])
	return order.size()

static func _coastal(labels: PackedInt32Array, topo: Dictionary, count: int) -> Array:
	var out: Array = []
	out.resize(count)
	out.fill(false)
	for i in labels.size():
		var v := labels[i]
		if v < 0 or out[v]:
			continue
		for nb in (topo["adj"][i] as PackedInt32Array):
			if labels[nb] < 0:
				out[v] = true
				break
	return out

# --- 4. Nüfus ve adlar ------------------------------------------------------------------

static func _population(points: PackedVector2Array, topo: Dictionary, labels: PackedInt32Array, count: int, rng: RandomNumberGenerator) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.01
	var land_cells: Array = []
	for i in labels.size():
		if labels[i] >= 0:
			land_cells.append(i)
	var metros: Array = []
	for m in METRO_COUNT:
		metros.append({"at": points[int(land_cells[rng.randi_range(0, land_cells.size() - 1)])],
			"amp": rng.randf_range(2.5, 7.0) if m > 0 else 9.0})
	var sigma := SPACING * 3.6
	var pop: Array = []
	pop.resize(count)
	pop.fill(0.0)
	for i in land_cells:
		var p := points[i]
		# Hücre alanı eski altıgen hücreden küçük: yoğunluk hücre başına ölçeklenir.
		var density := 0.6 + (noise.get_noise_2d(p.x, p.y) + 1.0) * 0.4
		for nb in (topo["adj"][i] as PackedInt32Array):
			if labels[nb] < 0:
				density += 0.35
				break
		for m in metros:
			var d: float = p.distance_to(m["at"])
			density += float(m["amp"]) * exp(-(d * d) / (2.0 * sigma * sigma))
		pop[labels[i]] = float(pop[labels[i]]) + density
	return pop

static func _names(points: PackedVector2Array, labels: PackedInt32Array, count: int, coastal: Array, population: Array, rng: RandomNumberGenerator) -> Array:
	var sums: Array = []
	var sizes: Array = []
	for r in count:
		sums.append(Vector2.ZERO)
		sizes.append(0)
	for i in labels.size():
		var r := labels[i]
		if r >= 0:
			sums[r] += points[i]
			sizes[r] += 1
	var order: Array = range(count)
	order.sort_custom(func(a, b): return float(population[a]) > float(population[b]))
	var metros := {}
	for k in mini(3, count):
		metros[order[k]] = true
	var used := {}
	var used_parts := {}
	var names: Array = []
	names.resize(count)
	for r in count:
		# Yön adı (Kuzey/Güney...) için eski ızgara ölçeğine çevrilir.
		var c: Vector2 = sums[r] / maxf(1.0, float(sizes[r]))
		var center := Vector2(c.x / WIDTH * HexGridGenerator.COLS, c.y / HEIGHT * HexGridGenerator.ROWS)
		var best := {}
		var best_overlap := 999
		for _try in 60:
			var candidate := HexGridGenerator._make_name(rng, bool(coastal[r]), metros.has(r), center)
			if used.has(candidate["name"]):
				continue
			var overlap := 0
			for part in candidate["parts"]:
				if used_parts.has(part):
					overlap += 1
			if overlap < best_overlap:
				best_overlap = overlap
				best = candidate
			if overlap == 0:
				break
		var name := String(best.get("name", ""))
		if name == "" or used.has(name):
			name = "%s %d" % [HexGridGenerator._pick(rng, HexGridGenerator.STANDALONE), r + 1]
		used[name] = true
		for part in best.get("parts", []):
			used_parts[part] = true
		names[r] = name
	return names

# --- 5. Çizim geometrisi (herkes kendi cihazında hesaplar) ------------------------------

## Ağdan gelen veriden çizim ve sorgu geometrisi:
##   tris     : Array[PackedVector2Array] il -> dolgu üçgenleri
##   segments : Array[[Vector2, Vector2, il_a, il_b]] (il_b -1 = kıyı); her sınır bir kez
##   neighbors: Array[Array] il -> komşu iller
##   centers  : Array[Vector2] il -> en geniş yerin ortası (vekil noktaları)
##   points, labels, cell_tris: nokta sorgusu için (bkz. GameMap.province_at)
static func geometry(map_data: Dictionary) -> Dictionary:
	var flat: Array = map_data["points"]
	var points := PackedVector2Array()
	points.resize(flat.size() / 2)
	for i in points.size():
		points[i] = Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]))
	var labels := PackedInt32Array(map_data["labels"])
	var count: int = (map_data["regions"] as Array).size()
	var topo := topology(points)
	var n := points.size()
	var tris: PackedInt32Array = topo["tris"]
	var centers: PackedVector2Array = (topo["centers"] as PackedVector2Array).duplicate()
	var edge_tris: Dictionary = topo["edge_tris"]
	var tcount := centers.size()
	# Sınır köşeleri ve sınır boyunca iki komşusu.
	var chain := {}  # üçgen -> [komşu üçgen, komşu üçgen]
	var fixed := {}
	for t in tcount:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var la := labels[a]
		var lb := labels[b]
		var lc := labels[c]
		if la == lb and lb == lc:
			continue
		if la != lb and lb != lc and la != lc:
			fixed[t] = true
			continue
		var around: Array = []
		for pair in [[a, b], [b, c], [c, a]]:
			if labels[pair[0]] == labels[pair[1]]:
				continue
			var u: int = mini(pair[0], pair[1])
			var v: int = maxi(pair[0], pair[1])
			var e: Vector2i = edge_tris[u * n + v]
			var other := e.y if e.x == t else e.x
			if other >= 0:
				around.append(other)
		if around.size() == 2:
			chain[t] = around
		else:
			fixed[t] = true
	for _it in SMOOTH_ITERATIONS:
		var moved := {}
		for t in chain.keys():
			var nb: Array = chain[t]
			moved[t] = centers[t] * 0.5 + (centers[int(nb[0])] + centers[int(nb[1])]) * 0.25
		for t in moved.keys():
			centers[t] = moved[t]
	# İnce kıvrımlar: yumuşatılmış sınır köşeleri gürültüyle hafifçe oynar (nehir
	# ve sırt kıvrımı gibi). Köşe iki ilde ortak olduğu için yapboz bozulmaz.
	var wiggle := FastNoiseLite.new()
	wiggle.seed = int(map_data.get("seed", 0))
	wiggle.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wiggle.fractal_type = FastNoiseLite.FRACTAL_FBM
	wiggle.fractal_octaves = 2
	wiggle.frequency = 0.05
	for t in chain.keys():
		var c := centers[t]
		centers[t] = c + Vector2(wiggle.get_noise_2d(c.x, c.y), wiggle.get_noise_2d(c.x + 517.0, c.y - 311.0)) * WIGGLE
	# Dolgu: her kara hücresinin çokgeni üçgenlenir (köşeler oynadığı için hücre
	# içbükey olabilir; yelpaze taşıp boşluk bırakırdı).
	var fills: Array = []
	var cell_tris := {}  # kara noktası -> hücresinin üçgenleri (tam il sorgusu)
	for r in count:
		fills.append([])
	var ptris: Array = topo["ptris"]
	for i in n:
		var r := labels[i]
		if r < 0:
			continue
		var ring: Array = ptris[i]
		var poly := PackedVector2Array()
		for t in ring:
			poly.append(centers[int(t)])
		var idx := Geometry2D.triangulate_polygon(poly)
		var out: Array = fills[r]
		var start := out.size()
		if idx.is_empty():
			var mid := Vector2.ZERO
			for v in poly:
				mid += v
			mid /= float(poly.size())
			for k in poly.size():
				out.append_array([mid, poly[k], poly[(k + 1) % poly.size()]])
		else:
			for k in idx:
				out.append(poly[k])
		cell_tris[i] = PackedVector2Array(out.slice(start))
	var region_tris: Array = []
	for r in count:
		region_tris.append(PackedVector2Array(fills[r]))
	# Sınır parçaları ve komşuluk.
	var segments: Array = []
	var neighbor_sets: Array = []
	for r in count:
		neighbor_sets.append({})
	for key in edge_tris.keys():
		var u: int = int(key) / n
		var v: int = int(key) % n
		var lu := labels[u]
		var lv := labels[v]
		if lu == lv:
			continue
		var e: Vector2i = edge_tris[key]
		if e.y < 0:
			continue
		var ra := maxi(lu, lv)
		var rb := mini(lu, lv)
		segments.append([centers[e.x], centers[e.y], ra, rb])
		if rb >= 0:
			neighbor_sets[ra][rb] = true
			neighbor_sets[rb][ra] = true
	var neighbors: Array = []
	for r in count:
		neighbors.append((neighbor_sets[r] as Dictionary).keys())
	return {"points": points, "labels": labels, "tris": region_tris, "cell_tris": cell_tris, "segments": segments, "neighbors": neighbors,
		"centers": _centers(points, labels, topo, count)}

## İlin EN GENİŞ yeri: sınıra en uzak hücreler (BFS derinliği), aralarından
## ağırlık merkezine en yakını.
static func _centers(points: PackedVector2Array, labels: PackedInt32Array, topo: Dictionary, count: int) -> Array:
	var depth := PackedInt32Array()
	depth.resize(points.size())
	depth.fill(-1)
	var queue: Array = []
	var sums: Array = []
	var sizes: Array = []
	for r in count:
		sums.append(Vector2.ZERO)
		sizes.append(0)
	for i in points.size():
		var r := labels[i]
		if r < 0:
			continue
		sums[r] += points[i]
		sizes[r] += 1
		for nb in (topo["adj"][i] as PackedInt32Array):
			if labels[nb] != r:
				depth[i] = 0
				queue.append(i)
				break
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in (topo["adj"][cur] as PackedInt32Array):
			if labels[nb] == labels[cur] and depth[nb] < 0:
				depth[nb] = depth[cur] + 1
				queue.append(nb)
	var best: Array = []
	best.resize(count)
	best.fill(-1)
	for i in points.size():
		var r := labels[i]
		if r < 0:
			continue
		var mean: Vector2 = sums[r] / maxf(1.0, float(sizes[r]))
		var b: int = best[r]
		if b < 0 or depth[i] > depth[b] or (depth[i] == depth[b] and points[i].distance_squared_to(mean) < points[b].distance_squared_to(mean)):
			best[r] = i
	var out: Array = []
	for r in count:
		out.append(points[int(best[r])] if int(best[r]) >= 0 else Vector2.ZERO)
	return out

## Küçük ikili yığın (Dijkstra için): [maliyet, düğüm].
class _Heap:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()

	func empty() -> bool:
		return keys.is_empty()

	func push(key: float, value: int) -> void:
		keys.append(key)
		vals.append(value)
		var i := keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if keys[parent] <= keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Array:
		var out := [keys[0], vals[0]]
		var last := keys.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return out

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var v := vals[a]
		vals[a] = vals[b]
		vals[b] = v
