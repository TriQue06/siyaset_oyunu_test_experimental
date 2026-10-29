class_name ElectionNightSim
extends RefCounted
## Yalnız görsel sayım: bütün iller aynı anda başlar; küçük iller erken biter.
## Hızlı sandık dalgaları arasında yaklaşık üç saniyelik sakin bölümler vardır.
## Meclis ilk kareden itibaren tam dağıtılır; kesin host sonucu değiştirilmez.
const SETTLE := 18.0 / 19.5
const WOBBLE := 0.8
const BIAS := 1.0
const COUNT_KEYS := [Vector2(0, 0), Vector2(0.48, 0.15), Vector2(3, 0.17), Vector2(3.48, 0.40), Vector2(6, 0.43), Vector2(6.48, 0.65), Vector2(9, 0.68), Vector2(9.48, 0.84), Vector2(12, 0.87), Vector2(12.48, 0.97), Vector2(15, 0.98), Vector2(18, 1)]
var _progress_time := -1.0
var _progress_cache: Dictionary = {}
var _party_phase: Dictionary = {}

var duration: float = 45.0
var threshold: float = 0.0
var peer_ids: Array = []
## Açılış sırasına göre.
var province_ids: Array = []
var province_seats: Dictionary = {}
var total_seats: int = 0
## İllerden gelen vekil toplamı (ulusal liste hariç; sayım yüzdesi buna göre).
var _province_total: int = 0
## peer_id -> ulusal listeden kazanılan vekil (bütün iller sayılınca eklenir).
var _list_seats: Dictionary = {}

var _results: Dictionary = {}
var _final_shares: Dictionary = {}
var _final_seats: Dictionary = {}
var _final_eligible: Array = []
var _window: Dictionary = {}  # province_id -> Vector2(açılış, bitiş) (süre oranı)
var _bias: Dictionary = {}    # province_id -> {peer_id: -1..1}
var _wave: Dictionary = {}    # province_id -> {peer_id: [frekans1, faz1, frekans2, faz2]}
var _allocation_cache: Dictionary = {}

static func province_name(province_id: String) -> String:
	var map = Engine.get_main_loop().root.get_node_or_null("GameMap") if Engine.get_main_loop() is SceneTree else null
	return map.name_of(province_id) if map != null else province_id

## alliances: party -> ittifak kimliği. İttifak üyeleri barajı ORTAK oyla geçer.
var alliances: Dictionary = {}

func setup(province_results: Dictionary, vote_shares: Dictionary, seats: Dictionary, passed: Array,
		threshold_percent: float, seed_value: int, duration_seconds: float, alliance_membership: Dictionary = {}) -> void:
	_allocation_cache.clear()
	_window.clear()
	_bias.clear()
	_wave.clear()
	_progress_time = -1.0
	_progress_cache.clear()
	_party_phase.clear()
	alliances = alliance_membership
	duration = maxf(1.0, duration_seconds)
	threshold = threshold_percent
	_results = province_results
	_final_shares = vote_shares
	_final_seats = seats
	_final_eligible = passed.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var ids := {}
	for peer_id in vote_shares.keys():
		ids[peer_id] = true
	province_seats.clear()
	total_seats = 0
	for province_id in province_results.keys():
		var entry: Dictionary = province_results[province_id]
		var n := 0
		for peer_id in entry.keys():
			ids[peer_id] = true
			n += int(entry[peer_id]["seats"])
		province_seats[province_id] = n
		total_seats += n
	_province_total = total_seats
	# Ulusal liste = kesin vekil − illerden gelen vekil.
	_list_seats.clear()
	for peer_id in ids.keys():
		var from_provinces := 0
		for province_id in province_results.keys():
			from_provinces += int(province_results[province_id].get(peer_id, {}).get("seats", 0))
		_list_seats[peer_id] = maxi(0, int(seats.get(peer_id, 0)) - from_provinces)
	# Ulusal liste sayımın sonunda dağıtılır (kesin sonuçta görünür).
	if not province_results.is_empty():
		total_seats += int(_list_seats.values().reduce(func(a, b): return int(a) + int(b), 0))
	peer_ids = ids.keys()
	peer_ids.sort()

	var keys: Array = province_results.keys()
	keys.sort()  # rastgele sayılar her istemcide aynı ile denk gelsin
	var weight := {}
	for province_id in keys:
		weight[province_id] = float(province_seats[province_id]) + rng.randf_range(0.0, 7.0)
	keys.sort_custom(func(a, b): return float(weight[a]) < float(weight[b]))
	province_ids = keys

	for peer_id in peer_ids:
		_party_phase[peer_id] = rng.randf_range(0.0, TAU)
	var count := province_ids.size()
	for i in count:
		var province_id: String = province_ids[i]
		_window[province_id] = Vector2(0, SETTLE)
		var bias := {}
		var wave := {}
		for peer_id in peer_ids:
			bias[peer_id] = rng.randf_range(-1.0, 1.0)
			wave[peer_id] = [rng.randf_range(0.5, 1.3), rng.randf_range(0.0, TAU),
				rng.randf_range(1.6, 2.8), rng.randf_range(0.0, TAU)]
		_bias[province_id] = bias
		_wave[province_id] = wave

## İlin t anındaki sayım oranı: 0 = açılmadı, 1 = sandıkların tamamı açıldı.
func progress(province_id: String, t: float) -> float:
	if t != _progress_time:
		_progress_time = t
		_progress_cache.clear()
		var clock := clampf(t / (duration * SETTLE), 0.0, 1.0) * 18.0
		var opened := 1.0
		for i in range(1, COUNT_KEYS.size()):
			if clock <= COUNT_KEYS[i].x:
				var a: Vector2 = COUNT_KEYS[i - 1]
				var b: Vector2 = COUNT_KEYS[i]
				opened = lerpf(a.y, b.y, (clock - a.x) / (b.x - a.x))
				break
		var lo := 0.0
		var hi := 7.0
		for step in 30:
			var mid := (lo + hi) * 0.5
			var total := 0.0
			for id in province_ids:
				var n := float(province_seats[id])
				total += minf(1.0, mid * (0.15 + 12.0 / pow(maxf(1, n), 1.2))) * n
			if total / maxf(1, _province_total) < opened:
				lo = mid
			else:
				hi = mid
		for id in province_ids:
			var n := float(province_seats[id])
			_progress_cache[id] = 1.0 if clock >= 18 else (0.0 if clock <= 0 else minf(1, (lo + hi) * 0.5 * (0.15 + 12.0 / pow(maxf(1, n), 1.2))))
	return float(_progress_cache.get(province_id, 0.0))

## İlin t anındaki oy payları (peer_id -> yüzde, toplam 100).
func province_shares(province_id: String, t: float, c: float) -> Dictionary:
	var entry: Dictionary = _results.get(province_id, {})
	var out := {}
	if c >= 1.0:
		for peer_id in peer_ids:
			out[peer_id] = _final_percent(entry, peer_id)
		return out
	var k := 1.0 - c
	var bias: Dictionary = _bias[province_id]
	var wave: Dictionary = _wave[province_id]
	var total := 0.0
	for peer_id in peer_ids:
		var p: Array = wave[peer_id]
		var phase := float(_party_phase[peer_id])
		var clock := t / (duration * SETTLE) * 18.0
		var w: float = sin(c * 8.0 + phase) + 0.25 * sin(clock * 0.55 + float(p[1]))
		var v: float = _final_percent(entry, peer_id) * exp(k * (BIAS * float(bias[peer_id]) + WOBBLE * w))
		out[peer_id] = v
		total += v
	if total > 0.0:
		for peer_id in peer_ids:
			out[peer_id] = float(out[peer_id]) / total * 100.0
	return out

func _final_percent(entry: Dictionary, peer_id) -> float:
	var e: Dictionary = entry.get(peer_id, {})
	return float(e.get("percent", 0.0))

## t anındaki tüm sayım durumu:
##   "counted":   açılan sandık yüzdesi (0..100)
##   "national":  peer_id -> ulusal oy yüzdesi (henüz sandık yoksa hepsi 0)
##   "eligible":  o anki oranlarla barajı geçenler
##   "seats":     peer_id -> açılan illerden kazanılan vekil
##   "provinces": province_id -> {"c", "shares", "seats"}
func sample(t: float) -> Dictionary:
	if t >= duration * SETTLE or province_ids.is_empty():
		return final_sample()
	var national := {}
	for peer_id in peer_ids:
		national[peer_id] = 0.0
	var provinces := {}
	var weight := 0.0
	for province_id in province_ids:
		var c := progress(province_id, t)
		var shares := province_shares(province_id, t, c)
		var w: float = float(province_seats[province_id]) * maxf(0.000001, c)
		weight += w
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) + float(shares[peer_id]) * w
		provinces[province_id] = {"c": c, "shares": shares, "seats": {}}
	var eligible: Array = []
	if weight > 0.0:
		var totals := {}
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) / weight
			var settle := clampf((weight / maxf(1, _province_total) - 0.85) / 0.15, 0, 1)
			national[peer_id] = lerpf(float(national[peer_id]), float(_final_shares.get(peer_id, 0)), settle)
			var aid := int(alliances.get(peer_id, 0))
			if aid != 0:
				totals[aid] = float(totals.get(aid, 0.0)) + float(national[peer_id])
		for peer_id in peer_ids:
			var aid := int(alliances.get(peer_id, 0))
			var share: float = float(totals[aid]) if aid != 0 else float(national[peer_id])
			if share >= threshold:
				eligible.append(peer_id)
		if eligible.is_empty():
			eligible = peer_ids.duplicate()
	var seats := {}
	for peer_id in peer_ids:
		seats[peer_id] = 0
	for province_id in province_ids:
		var p: Dictionary = provinces[province_id]
		var alloc: Dictionary
		var cached: Dictionary = _allocation_cache.get(province_id, {})
		if not cached.is_empty() and cached["method"] == ElectionModel.seat_method and cached["count"] == province_seats[province_id] and cached["eligible"] == eligible and cached["shares"] == p["shares"]:
			alloc = (cached["seats"] as Dictionary).duplicate()
		else:
			alloc = ElectionModel.allocate(p["shares"], eligible, int(province_seats[province_id]))
			_allocation_cache[province_id] = {"method": ElectionModel.seat_method, "count": province_seats[province_id], "eligible": eligible.duplicate(),
				"shares": (p["shares"] as Dictionary).duplicate(), "seats": alloc.duplicate()}
		p["seats"] = alloc
		for peer_id in alloc.keys():
			seats[peer_id] = int(seats[peer_id]) + int(alloc[peer_id])
	var list_total := 0
	for n in _list_seats.values():
		list_total += int(n)
	var live_list := ElectionModel.allocate(national, eligible, list_total)
	for peer_id in live_list:
		seats[peer_id] = int(seats.get(peer_id, 0)) + int(live_list[peer_id])
	return {
		"counted": 0.0 if t <= 0 else weight / float(maxi(1, _province_total)) * 100.0,
		"national": national, "eligible": eligible, "seats": seats, "provinces": provinces,
	}

## Sayımın sonu: kesin sonucun kendisi.
func final_sample() -> Dictionary:
	var provinces := {}
	for province_id in province_ids:
		var entry: Dictionary = _results[province_id]
		var shares := {}
		var seats := {}
		for peer_id in peer_ids:
			var e: Dictionary = entry.get(peer_id, {})
			shares[peer_id] = float(e.get("percent", 0.0))
			seats[peer_id] = int(e.get("seats", 0))
		provinces[province_id] = {"c": 1.0, "shares": shares, "seats": seats}
	var national := {}
	var seats_total := {}
	for peer_id in peer_ids:
		national[peer_id] = float(_final_shares.get(peer_id, 0.0))
		seats_total[peer_id] = int(_final_seats.get(peer_id, 0))
	return {
		"counted": 100.0, "national": national, "eligible": _final_eligible.duplicate(),
		"seats": seats_total, "provinces": provinces,
	}
