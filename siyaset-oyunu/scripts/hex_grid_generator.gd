class_name HexGridGenerator
extends RefCounted
## RASTGELE ALTIGEN ÜLKE. Saf fonksiyon: aynı tohum aynı haritayı üretir,
## ama ağda tohum değil ÜRETİLMİŞ VERİ gönderilir (bkz. GameMap) — farklı
## platformlarda gürültü fonksiyonunun kayan nokta farkı haritayı
## değiştirmesin diye.
##
## ADIMLAR
##   1. Kara: gürültü + eliptik düşüş, en yüksek LAND_FRACTION hücre kara olur;
##      kenar halkası hep deniz (kıyı oluşsun), sadece en büyük kara parçası
##      kalır, küçük iç göller doldurulur.
##   2. Bölgeler (seçim bölgesi = il): kara üzerine birbirinden uzak tohumlar
##      atılır, her tohum komşu hücrelere büyür. Büyüme sırası bölgenin
##      "hedef ağırlığına" göre dengelenir: iller hep bitişik ve benzer ama
##      eşit olmayan büyüklükte olur.
##   3. Nüfus: her hücrenin yoğunluğu = taban + gürültü + kıyı bonusu +
##      birkaç BÜYÜKŞEHİR tepesi. Bölge nüfusu hücrelerinin toplamı.
##   4. Vekil: PROVINCE_SEATS vekil, bölgelere en az MIN_SEATS olmak üzere
##      nüfusla orantılı (en büyük kalan yöntemi) dağıtılır.
##   5. İsim: kıyıdaki bölgeye kıyı adları, iç bölgeye kara adları; yönlü
##      ("Kuzey Limanı"), sıfatlı ("Taşlı Plato") ya da bitişik ("Karaova").
##
## HÜCRE DİZİLİMİ: "odd-r" ofset, sivri tepeli altıgenler. Hücre indeksi =
## row * cols + col. Geometri GameMap'te.

const COLS := 44
const ROWS := 23
const LAND_FRACTION := 0.56
const HEXES_PER_REGION := 11.0
const MIN_REGION_HEXES := 4
const PROVINCE_SEATS := 300
const MIN_SEATS := 2
const METRO_COUNT := 5
## TIKIZ BÜYÜME: bölge her adımda birkaç aday hücreye bakar ve kendi
## hücreleriyle en çok komşu olanı alır (ince kollar/çıkıntılar oluşmasın).
const GROWTH_SAMPLES := 8
## TÖRPÜLEME: büyüme bitince, komşularının çoğu başka bir bölgede olan
## "çıkıntı" hücreler o bölgeye devredilir (bölgeler bitişik kalır).
const SMOOTH_PASSES := 4
const SMOOTH_MIN_FOREIGN := 4

const ADJECTIVES := ["Taşlı", "Yeşil", "Kızıl", "Ak", "Kara", "Gök", "Sarı", "Ulu", "Derin", "Eski",
	"Yeni", "Kuru", "Serin", "Uzun", "Yüce", "Çamlı", "Kayalı", "Güneşli", "Rüzgârlı", "Sisli", "Karlı",
	"Söğütlü", "Kumlu", "Tuzlu", "Pınarlı", "Meşeli", "Bağlı", "Çorak", "Demirli", "Gümüşlü", "Ilık",
	"Dumanlı", "Kırlı", "Otlu", "Sessiz", "Geniş"]
const LAND_NOUNS := ["Plato", "Vadi", "Ova", "Yayla", "Tepe", "Bozkır", "Havza", "Düzlük", "Yamaç",
	"Kanyon", "Sırt", "Koru", "Göl", "Irmak", "Pınar", "Dağlar"]
const COAST_NOUNS := ["Liman", "Kıyı", "Körfez", "Burun", "Koy", "Sahil"]
## "Kuzey ___" kalıbı için iyelik ekli biçimler.
const POSSESSIVE := {
	"Plato": "Platosu", "Vadi": "Vadisi", "Ova": "Ovası", "Yayla": "Yaylası", "Tepe": "Tepesi",
	"Bozkır": "Bozkırı", "Havza": "Havzası", "Düzlük": "Düzlüğü", "Yamaç": "Yamacı",
	"Kanyon": "Kanyonu", "Sırt": "Sırtı", "Koru": "Korusu", "Göl": "Gölü", "Irmak": "Irmağı",
	"Pınar": "Pınarı", "Dağlar": "Dağları", "Liman": "Limanı", "Kıyı": "Kıyısı", "Körfez": "Körfezi",
	"Burun": "Burnu", "Koy": "Koyu", "Sahil": "Sahili",
}
const COMPOUND_HEADS := ["Ak", "Kara", "Sarı", "Yeşil", "Gök", "Kızıl", "Çam", "Taş", "Demir", "Kum",
	"Söğüt", "Meşe", "Bağ", "Göl", "Yeni", "Eski", "Ilıca", "Kaya", "Ulu", "Tuz"]
const COMPOUND_TAILS := ["ova", "pınar", "yayla", "dere", "tepe", "vadi", "yurt", "alan", "bük", "kaya",
	"su", "hisar", "kale", "yazı", "köprü", "çay"]
const COAST_TAILS := ["liman", "kıyı", "koy", "burun"]
const METRO_TAILS := ["kent", "şehir"]

const EVEN_ROW_NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(0, 1), Vector2i(-1, 1)]
const ODD_ROW_NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(0, 1)]

## Dönüş (ağ üzerinden gönderilebilir, sadece temel tipler):
##   {"seed", "cols", "rows", "cells": Array[int] (bölge indeksi, -1 deniz),
##    "regions": Array[{"id", "name", "seats", "coastal"}]}
static func generate(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var land := _make_land(rng)
	var cells := _grow_regions(land, rng)
	var region_count := 0
	for v in cells:
		region_count = maxi(region_count, int(v) + 1)
	var coastal := _coastal_regions(cells, region_count)
	var population := _population(cells, region_count, coastal, rng)
	var seats := _allocate_seats(population)
	var names := _names(cells, region_count, coastal, population, rng)
	var regions: Array = []
	for i in region_count:
		regions.append({"id": "b%02d" % (i + 1), "name": names[i], "seats": int(seats[i]), "coastal": bool(coastal[i])})
	return {"seed": seed_value, "cols": COLS, "rows": ROWS, "cells": cells, "regions": regions}

# --- Yardımcılar -------------------------------------------------------------

static func neighbor_cells(index: int, cols: int = COLS, rows: int = ROWS) -> Array:
	var col := index % cols
	var row := index / cols
	var offsets: Array = ODD_ROW_NEIGHBORS if row % 2 == 1 else EVEN_ROW_NEIGHBORS
	var result: Array = []
	for o in offsets:
		var c: int = col + o.x
		var r: int = row + o.y
		if c >= 0 and c < cols and r >= 0 and r < rows:
			result.append(r * cols + c)
	return result

static func _cube(index: int, cols: int = COLS) -> Vector3i:
	var col := index % cols
	var row := index / cols
	var q := col - (row - (row & 1)) / 2
	return Vector3i(q, row, -q - row)

static func hex_distance(a: int, b: int, cols: int = COLS) -> int:
	var ca := _cube(a, cols)
	var cb := _cube(b, cols)
	return (absi(ca.x - cb.x) + absi(ca.y - cb.y) + absi(ca.z - cb.z)) / 2

# --- 1. Kara -------------------------------------------------------------------

static func _make_land(rng: RandomNumberGenerator) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.075
	noise.fractal_octaves = 3
	var count := COLS * ROWS
	var values: Array = []
	values.resize(count)
	var ratio := float(COLS) / float(ROWS)
	for i in count:
		var col := i % COLS
		var row := i / COLS
		var nx := (float(col) + 0.5) / COLS * 2.0 - 1.0
		var ny := (float(row) + 0.5) / ROWS * 2.0 - 1.0
		var falloff := 1.0 - (nx * nx + ny * ny * 0.9)
		values[i] = noise.get_noise_2d(col * 1.0, row * ratio * 0.5) * 0.9 + falloff
		if col == 0 or row == 0 or col == COLS - 1 or row == ROWS - 1:
			values[i] = -INF
	var sorted := values.duplicate()
	sorted.sort()
	var cut: float = sorted[int(count * (1.0 - LAND_FRACTION))]
	var land: Array = []
	land.resize(count)
	for i in count:
		land[i] = float(values[i]) >= cut and values[i] != -INF
	# Sadece en büyük kara parçası.
	var best: Array = []
	var seen := {}
	for i in count:
		if not land[i] or seen.has(i):
			continue
		var comp := _flood(i, func(j): return land[j], seen)
		if comp.size() > best.size():
			best = comp
	var result: Array = []
	result.resize(count)
	result.fill(false)
	for i in best:
		result[i] = true
	# Küçük iç göller doldurulur (denize açılmayan 5 hücreden küçük su).
	var water_seen := {}
	for i in count:
		if result[i] or water_seen.has(i):
			continue
		var comp := _flood(i, func(j): return not result[j], water_seen)
		var touches_edge := false
		for j in comp:
			var c: int = j % COLS
			var r: int = j / COLS
			if c == 0 or r == 0 or c == COLS - 1 or r == ROWS - 1:
				touches_edge = true
				break
		if not touches_edge and comp.size() < 5:
			for j in comp:
				result[j] = true
	return result

static func _flood(start: int, accept: Callable, seen: Dictionary) -> Array:
	var comp: Array = [start]
	seen[start] = true
	var head := 0
	while head < comp.size():
		var cur: int = comp[head]
		head += 1
		for n in neighbor_cells(cur):
			if not seen.has(n) and accept.call(n):
				seen[n] = true
				comp.append(n)
	return comp

# --- 2. Bölgeler ---------------------------------------------------------------

static func _grow_regions(land: Array, rng: RandomNumberGenerator) -> Array:
	var land_cells: Array = []
	for i in land.size():
		if land[i]:
			land_cells.append(i)
	var target := maxi(8, int(round(land_cells.size() / HEXES_PER_REGION)))
	# Birbirinden uzak tohumlar: önce geniş aralık, yetmezse daralt.
	var seeds: Array = []
	var shuffled := land_cells.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var min_dist := 5
	while seeds.size() < target and min_dist >= 1:
		for cell in shuffled:
			if seeds.size() >= target:
				break
			if seeds.has(cell):
				continue
			var ok := true
			for s in seeds:
				if hex_distance(cell, s) < min_dist:
					ok = false
					break
			if ok:
				seeds.append(cell)
		min_dist -= 1
	var cells: Array = []
	cells.resize(land.size())
	cells.fill(-1)
	var sizes: Array = []
	var weights: Array = []
	var frontiers: Array = []
	for r in seeds.size():
		cells[seeds[r]] = r
		sizes.append(1)
		weights.append(rng.randf_range(0.55, 1.6))
		frontiers.append([seeds[r]])
	var remaining := land_cells.size() - seeds.size()
	while remaining > 0:
		# En "aç" bölge (büyüklük / ağırlık en düşük) büyür.
		var pick := -1
		var pick_score := INF
		for r in seeds.size():
			if (frontiers[r] as Array).is_empty():
				continue
			var score: float = float(sizes[r]) / float(weights[r]) + rng.randf() * 0.8
			if score < pick_score:
				pick_score = score
				pick = r
		if pick == -1:
			break
		var frontier: Array = frontiers[pick]
		var cell := -1
		var cell_score := -INF
		var tries := 0
		while not frontier.is_empty() and tries < GROWTH_SAMPLES:
			var k := rng.randi_range(0, frontier.size() - 1)
			var from: int = frontier[k]
			var options: Array = []
			for n in neighbor_cells(from):
				if land[n] and int(cells[n]) == -1:
					options.append(n)
			if options.is_empty():
				frontier.remove_at(k)
				continue
			tries += 1
			var candidate: int = options[rng.randi_range(0, options.size() - 1)]
			var own := 0
			for n in neighbor_cells(candidate):
				if int(cells[n]) == pick:
					own += 1
			var score := own + rng.randf() * 0.9
			if score > cell_score:
				cell_score = score
				cell = candidate
		var grown := cell != -1
		if grown:
			cells[cell] = pick
			sizes[pick] = int(sizes[pick]) + 1
			frontier.append(cell)
			remaining -= 1
	_smooth_regions(cells)
	_merge_tiny(cells, seeds.size())
	return cells

## Çıkıntı törpüleme: bir hücrenin en az SMOOTH_MIN_FOREIGN komşusu aynı başka
## bölgedeyse hücre o bölgeye geçer — ama sadece kendi bölgesi bölünmüyorsa ve
## küçülüp MIN_REGION_HEXES'in altına inmiyorsa.
static func _smooth_regions(cells: Array) -> void:
	for _pass in SMOOTH_PASSES:
		var changed := false
		var sizes := {}
		for v in cells:
			if int(v) >= 0:
				sizes[int(v)] = int(sizes.get(int(v), 0)) + 1
		for i in cells.size():
			var own := int(cells[i])
			if own < 0 or int(sizes[own]) <= MIN_REGION_HEXES:
				continue
			var counts := {}
			for n in neighbor_cells(i):
				var o := int(cells[n])
				if o >= 0 and o != own:
					counts[o] = int(counts.get(o, 0)) + 1
			var target := -1
			for o in counts.keys():
				if int(counts[o]) >= SMOOTH_MIN_FOREIGN and (target == -1 or int(counts[o]) > int(counts[target])):
					target = o
			if target == -1:
				continue
			cells[i] = target
			if not _region_connected(cells, own):
				cells[i] = own
				continue
			sizes[own] = int(sizes[own]) - 1
			sizes[target] = int(sizes[target]) + 1
			changed = true
		if not changed:
			break

static func _region_connected(cells: Array, region: int) -> bool:
	var start := -1
	var total := 0
	for i in cells.size():
		if int(cells[i]) == region:
			total += 1
			if start == -1:
				start = i
	if start == -1:
		return true
	var seen := {}
	return _flood(start, func(j): return int(cells[j]) == region, seen).size() == total

## MIN_REGION_HEXES'ten küçük bölgeler en çok sınır paylaştıkları komşuya katılır,
## sonra indeksler 0..n-1 olacak şekilde sıkıştırılır.
static func _merge_tiny(cells: Array, count: int) -> void:
	for _pass in 3:
		var sizes := {}
		for v in cells:
			if int(v) >= 0:
				sizes[int(v)] = int(sizes.get(int(v), 0)) + 1
		var changed := false
		for r in sizes.keys():
			if int(sizes[r]) >= MIN_REGION_HEXES:
				continue
			var shared := {}
			for i in cells.size():
				if int(cells[i]) != r:
					continue
				for n in neighbor_cells(i):
					var o := int(cells[n])
					if o >= 0 and o != r:
						shared[o] = int(shared.get(o, 0)) + 1
			var best := -1
			for o in shared.keys():
				if best == -1 or int(shared[o]) > int(shared[best]):
					best = o
			if best == -1:
				continue
			for i in cells.size():
				if int(cells[i]) == r:
					cells[i] = best
			changed = true
		if not changed:
			break
	var remap := {}
	for i in cells.size():
		var v := int(cells[i])
		if v < 0:
			continue
		if not remap.has(v):
			remap[v] = remap.size()
		cells[i] = remap[v]

static func _coastal_regions(cells: Array, count: int) -> Array:
	var coastal: Array = []
	coastal.resize(count)
	coastal.fill(false)
	for i in cells.size():
		var r := int(cells[i])
		if r < 0 or coastal[r]:
			continue
		for n in neighbor_cells(i):
			if int(cells[n]) == -1:
				coastal[r] = true
				break
	return coastal

# --- 3. Nüfus ------------------------------------------------------------------

static func _population(cells: Array, count: int, coastal: Array, rng: RandomNumberGenerator) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.12
	var land_cells: Array = []
	for i in cells.size():
		if int(cells[i]) >= 0:
			land_cells.append(i)
	var metros: Array = []
	for m in METRO_COUNT:
		metros.append({"cell": land_cells[rng.randi_range(0, land_cells.size() - 1)],
			"amp": rng.randf_range(2.5, 7.0) if m > 0 else 9.0})
	var pop: Array = []
	pop.resize(count)
	pop.fill(0.0)
	for i in land_cells:
		var density := 0.6 + (noise.get_noise_2d(i % COLS, i / COLS) + 1.0) * 0.4
		var shore := false
		for n in neighbor_cells(i):
			if int(cells[n]) == -1:
				shore = true
				break
		if shore:
			density += 0.35
		for m in metros:
			var d := float(hex_distance(i, int(m["cell"])))
			density += float(m["amp"]) * exp(-(d * d) / (2.0 * 1.8 * 1.8))
		pop[int(cells[i])] = float(pop[int(cells[i])]) + density
	return pop

# --- 4. Vekiller -----------------------------------------------------------------

static func _allocate_seats(population: Array) -> Array:
	var count := population.size()
	var seats: Array = []
	seats.resize(count)
	seats.fill(MIN_SEATS)
	var left := PROVINCE_SEATS - MIN_SEATS * count
	var total := 0.0
	for p in population:
		total += float(p)
	var remainders: Array = []
	var given := 0
	for i in count:
		var exact := float(population[i]) / maxf(total, 0.0001) * left
		var whole := int(floor(exact))
		seats[i] = int(seats[i]) + whole
		given += whole
		remainders.append([exact - whole, i])
	remainders.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var k := 0
	while given < left:
		seats[remainders[k % count][1]] = int(seats[remainders[k % count][1]]) + 1
		given += 1
		k += 1
	return seats

# --- 5. İsimler ------------------------------------------------------------------

static func _names(cells: Array, count: int, coastal: Array, population: Array, rng: RandomNumberGenerator) -> Array:
	# Bölge merkezleri (yön seçimi için, hücre koordinatında).
	var sums: Array = []
	var sizes: Array = []
	for r in count:
		sums.append(Vector2.ZERO)
		sizes.append(0)
	for i in cells.size():
		var r := int(cells[i])
		if r >= 0:
			sums[r] += Vector2(i % COLS, i / COLS)
			sizes[r] += 1
	var order: Array = range(count)
	order.sort_custom(func(a, b): return float(population[a]) > float(population[b]))
	var metros := {}
	for k in mini(3, count):
		metros[order[k]] = true
	var used := {}
	var names: Array = []
	names.resize(count)
	for r in count:
		var center: Vector2 = sums[r] / maxf(1.0, float(sizes[r]))
		var name := ""
		for _try in 40:
			name = _make_name(rng, bool(coastal[r]), metros.has(r), center)
			if not used.has(name):
				break
		if used.has(name):
			name = "%s %d" % [name, r + 1]
		used[name] = true
		names[r] = name
	return names

static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	return String(list[rng.randi_range(0, list.size() - 1)])

static func _make_name(rng: RandomNumberGenerator, coastal: bool, metro: bool, center: Vector2) -> String:
	if metro:
		var tail := _pick(rng, METRO_TAILS)
		return _pick(rng, COMPOUND_HEADS) + tail if rng.randf() < 0.6 else ("Yeni" + tail if tail == "şehir" else "Büyük" + tail)
	var roll := rng.randf()
	var nouns: Array = COAST_NOUNS if coastal and rng.randf() < 0.7 else LAND_NOUNS
	if roll < 0.25:
		var dx := center.x / COLS - 0.5
		var dy := center.y / ROWS - 0.5
		var direction := ("Doğu" if dx > 0.0 else "Batı") if absf(dx) * 0.9 > absf(dy) else ("Güney" if dy > 0.0 else "Kuzey")
		var noun := _pick(rng, nouns)
		return "%s %s" % [direction, POSSESSIVE.get(noun, noun)]
	if roll < 0.62:
		return "%s %s" % [_pick(rng, ADJECTIVES), _pick(rng, nouns)]
	var tails: Array = COAST_TAILS if coastal and rng.randf() < 0.5 else COMPOUND_TAILS
	return _pick(rng, COMPOUND_HEADS) + _pick(rng, tails)
