extends Node
## Autoload. Constants and helpers for the party ideology system.
##
## Three axes, each ranging from AXIS_MIN to AXIS_MAX:
##   economic       : -3 statist/collectivist  <-> +3 market/capitalist
##   social         : -3 progressive           <-> +3 conservative
##   administrative : -3 federal/pluralist     <-> +3 unitary/nationalist
##
## BAŞLANGIÇ: parti kurulurken her eksende iki uçtan biri seçilir
## (−START_MAGNITUDE ya da +START_MAGNITUDE). OYUNCU SAYILARI ASLA GÖRMEZ:
## arayüz her yerde position_text() ile kelime gösterir ("Ilımlı Devletçi").
## Değerler STEP (0.5) adımlıdır. Yasa sunmak partiyi yasanın yönünde
## LAW_PROPOSE_SHIFT, yasaya EVET yasanın yönünde / HAYIR ters yönde
## LAW_VOTE_SHIFT kaydırır; çekimser kaydırmaz. İllerin görüşü aynı
## eksenlerde bkz. ProvinceIdeology.

const AXES := ["economic", "social", "administrative"]
const AXIS_MIN := -3
const AXIS_MAX := 3
const START_MAGNITUDE := 1.5
const ALLOWED_START_VALUES := [-START_MAGNITUDE, START_MAGNITUDE]
## Eksen uçlarının oyuncuya görünen adları (sayı yerine her yerde bunlar).
const AXIS_SIDES := {
	"economic": {"title": "Ekonomi", "neg": "Devletçi", "pos": "Piyasacı"},
	"social": {"title": "Toplum", "neg": "İlerici", "pos": "Muhafazakâr"},
	"administrative": {"title": "İdare", "neg": "Federal", "pos": "Üniter"},
}
const STEP := 0.5
const LAW_PROPOSE_SHIFT := 1.0
const LAW_VOTE_SHIFT := 0.5

static func default_values() -> Dictionary:
	var v := {}
	for axis in AXES:
		v[axis] = 0
	return v

static func is_valid_start_value(value) -> bool:
	for allowed in ALLOWED_START_VALUES:
		if is_equal_approx(float(value), float(allowed)):
			return true
	return false

static func is_valid_start_ideology(values: Dictionary) -> bool:
	for axis in AXES:
		if not values.has(axis) or not is_valid_start_value(values[axis]):
			return false
	return true

## Botlar ve yeni kurulan partiler için: her eksende rastgele bir uç.
static func random_start_ideology() -> Dictionary:
	var v := {}
	for axis in AXES:
		v[axis] = START_MAGNITUDE if randf() < 0.5 else -START_MAGNITUDE
	return v

## Bir eksendeki konumun OYUNCUYA görünen adı (sayı asla gösterilmez):
## "Merkez", "Ilımlı Piyasacı", "Piyasacı", "Radikal Piyasacı".
static func position_text(axis: String, value: float) -> String:
	var info: Dictionary = AXIS_SIDES.get(axis, {"neg": "-", "pos": "+"})
	var magnitude := absf(value)
	if magnitude < 0.25:
		return "Merkez"
	var side: String = info["pos"] if value > 0.0 else info["neg"]
	if magnitude <= 1.0:
		return "Ilımlı " + side
	if magnitude <= 2.0:
		return side
	return "Radikal " + side

## Eksenin sadece hangi uçta olduğu ("Piyasacı" / "Devletçi" / "Merkez").
static func side_text(axis: String, value: float) -> String:
	var info: Dictionary = AXIS_SIDES.get(axis, {"neg": "-", "pos": "+"})
	if absf(value) < 0.25:
		return "Merkez"
	return info["pos"] if value > 0.0 else info["neg"]

## Oyun ortası güncelleme: STEP'e yuvarlanır ve [-3, 3] aralığına sıkıştırılır.
static func clamp_value(value: float) -> float:
	return clampf(snappedf(value, STEP), AXIS_MIN, AXIS_MAX)

## "+1.5", "−2", "0" gibi kısa gösterim.
static func format_value(value: float) -> String:
	if is_zero_approx(value):
		return "0"
	var text := ("%+.1f" % value) if not is_equal_approx(value, roundf(value)) else ("%+d" % int(roundf(value)))
	return text

## İki ideoloji vektörü arasındaki Öklid mesafesi (eksen sayısına göre genel).
static func distance(a: Dictionary, b: Dictionary) -> float:
	var sum_sq := 0.0
	for axis in AXES:
		var diff: float = a.get(axis, 0) - b.get(axis, 0)
		sum_sq += diff * diff
	return sqrt(sum_sq)

static func max_distance() -> float:
	return sqrt(AXES.size() * pow(AXIS_MAX - AXIS_MIN, 2))
