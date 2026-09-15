class_name ElectionNightSim
extends RefCounted
## Seçim gecesi CANLI SAYIM simülasyonu — sadece GÖRSEL. Seçimin kesin sonucu
## host'ta zaten hesaplanmış durumda (CardManager.last_*); bu sınıf o sonuca
## "gitgelli" bir yoldan varan ara kareler üretir:
##   - İller sırayla açılır (küçük iller önce, büyükler genelde sonda).
##   - Açılan bir ilin sayımı hemen bitmez: her ilin kendi sayım oranı (0..1)
##     vardır. Oran 1'e ulaşana kadar o ilin oy payları kesin sonucun etrafında
##     dalgalanır ve ilk sandıkların yanlılığını taşır; oran arttıkça sapma
##     söner, 1'de pay tam olarak kesin sonuçtur. Yani yeni iller açılırken
##     önceden açılmış iller de değişmeye devam eder.
##   - Ulusal oran, açılan sandıkların (vekil sayısı × sayım oranı) ağırlıklı
##     ortalamasıdır; baraj ve D'Hondt her karede o anki oranlarla uygulanır
##     (baraj gerilimi ve sandalye kaymaları buradan doğar).
##   - Tüm iller süresinin SETTLE oranında %100 olur; son karede sonuç kesin
##     sonuçla birebir aynıdır.
## Aynı tohum her istemcide aynı geceyi üretir (deterministik).

const OPEN_START := 0.02
const OPEN_END := 0.72
const COUNT_MIN := 0.14
const COUNT_MAX := 0.26
const SETTLE := 0.95
## Sayım başında payların oransal dalgalanma ve ilk-sandık yanlılığı genliği.
const WOBBLE := 0.28
const BIAS := 0.32

const PROVINCE_NAMES := {
	"adana": "Adana", "adiyaman": "Adıyaman", "afyonkarahisar": "Afyonkarahisar", "agri": "Ağrı",
	"amasya": "Amasya", "ankara": "Ankara", "antalya": "Antalya", "artvin": "Artvin", "aydin": "Aydın",
	"balikesir": "Balıkesir", "bilecik": "Bilecik", "bingol": "Bingöl", "bitlis": "Bitlis", "bolu": "Bolu",
	"burdur": "Burdur", "bursa": "Bursa", "canakkale": "Çanakkale", "cankiri": "Çankırı", "corum": "Çorum",
	"denizli": "Denizli", "diyarbakir": "Diyarbakır", "edirne": "Edirne", "elazig": "Elazığ",
	"erzincan": "Erzincan", "erzurum": "Erzurum", "eskisehir": "Eskişehir", "gaziantep": "Gaziantep",
	"giresun": "Giresun", "gumushane": "Gümüşhane", "hakkari": "Hakkari", "hatay": "Hatay",
	"isparta": "Isparta", "istanbul": "İstanbul", "izmir": "İzmir", "kahramanmaras": "Kahramanmaraş",
	"kars": "Kars", "kastamonu": "Kastamonu", "kayseri": "Kayseri", "kirklareli": "Kırklareli",
	"kirsehir": "Kırşehir", "kocaeli": "Kocaeli", "konya": "Konya", "kutahya": "Kütahya",
	"malatya": "Malatya", "manisa": "Manisa", "mardin": "Mardin", "mersin": "Mersin", "mugla": "Muğla",
	"mus": "Muş", "nevsehir": "Nevşehir", "nigde": "Niğde", "ordu": "Ordu", "rize": "Rize",
	"sakarya": "Sakarya", "samsun": "Samsun", "sanliurfa": "Şanlıurfa", "siirt": "Siirt", "sinop": "Sinop",
	"sivas": "Sivas", "tekirdag": "Tekirdağ", "tokat": "Tokat", "trabzon": "Trabzon", "tunceli": "Tunceli",
	"usak": "Uşak", "van": "Van", "yozgat": "Yozgat", "zonguldak": "Zonguldak",
}

var duration: float = 45.0
var threshold: float = 0.0
var peer_ids: Array = []
## Açılış sırasına göre.
var province_ids: Array = []
var province_seats: Dictionary = {}
var total_seats: int = 0

var _results: Dictionary = {}
var _final_shares: Dictionary = {}
var _final_seats: Dictionary = {}
var _final_eligible: Array = []
var _window: Dictionary = {}  # province_id -> Vector2(açılış, bitiş) (süre oranı)
var _bias: Dictionary = {}    # province_id -> {peer_id: -1..1}
var _wave: Dictionary = {}    # province_id -> {peer_id: [frekans1, faz1, frekans2, faz2]}

static func province_name(province_id: String) -> String:
	return String(PROVINCE_NAMES.get(province_id, province_id.capitalize()))

func setup(province_results: Dictionary, vote_shares: Dictionary, seats: Dictionary, passed: Array,
		threshold_percent: float, seed_value: int, duration_seconds: float) -> void:
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
	peer_ids = ids.keys()
	peer_ids.sort()

	var keys: Array = province_results.keys()
	keys.sort()  # rastgele sayılar her istemcide aynı ile denk gelsin
	var weight := {}
	for province_id in keys:
		weight[province_id] = float(province_seats[province_id]) + rng.randf_range(0.0, 7.0)
	keys.sort_custom(func(a, b): return float(weight[a]) < float(weight[b]))
	province_ids = keys

	var count := province_ids.size()
	for i in count:
		var province_id: String = province_ids[i]
		var start: float = OPEN_START + (OPEN_END - OPEN_START) * (float(i) / float(maxi(1, count - 1)))
		start = clampf(start + rng.randf_range(-0.015, 0.015), 0.0, OPEN_END)
		var length: float = rng.randf_range(COUNT_MIN, COUNT_MAX) + float(province_seats[province_id]) / 24.0 * 0.06
		_window[province_id] = Vector2(start, minf(start + length, SETTLE))
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
	var w: Vector2 = _window.get(province_id, Vector2.ZERO)
	var r := t / duration
	if r >= w.y:
		return 1.0
	if r <= w.x:
		return 0.0
	var u := (r - w.x) / maxf(0.0001, w.y - w.x)
	return 1.0 - pow(1.0 - u, 2.2)  # önce hızlı, sona doğru yavaş

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
		var w: float = 0.6 * sin(t * float(p[0]) + float(p[1])) + 0.4 * sin(t * float(p[2]) + float(p[3]))
		var v: float = _final_percent(entry, peer_id) * maxf(0.05, 1.0 + k * (BIAS * float(bias[peer_id]) + WOBBLE * w))
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
	if t >= duration:
		return final_sample()
	var national := {}
	for peer_id in peer_ids:
		national[peer_id] = 0.0
	var provinces := {}
	var weight := 0.0
	for province_id in province_ids:
		var c := progress(province_id, t)
		if c <= 0.0:
			provinces[province_id] = {"c": 0.0, "shares": {}, "seats": {}}
			continue
		var shares := province_shares(province_id, t, c)
		var w: float = float(province_seats[province_id]) * c
		weight += w
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) + float(shares[peer_id]) * w
		provinces[province_id] = {"c": c, "shares": shares, "seats": {}}
	var eligible: Array = []
	if weight > 0.0:
		for peer_id in peer_ids:
			national[peer_id] = float(national[peer_id]) / weight
			if float(national[peer_id]) >= threshold:
				eligible.append(peer_id)
		if eligible.is_empty():
			eligible = peer_ids.duplicate()
	var seats := {}
	for peer_id in peer_ids:
		seats[peer_id] = 0
	for province_id in province_ids:
		var p: Dictionary = provinces[province_id]
		if float(p["c"]) <= 0.0:
			continue
		var alloc := ElectionModel.dhondt(p["shares"], eligible, int(province_seats[province_id]))
		p["seats"] = alloc
		for peer_id in alloc.keys():
			seats[peer_id] = int(seats[peer_id]) + int(alloc[peer_id])
	return {
		"counted": weight / float(maxi(1, total_seats)) * 100.0,
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
