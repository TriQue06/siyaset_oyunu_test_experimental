extends Node
## Autoload. Üretilen ülkenin verisini, çizim geometrisini ve il sorgularını tutar.
## Host tam harita verisini gönderir; istemciler aynı veriyi set_data ile uygular.

signal map_changed

const DEFAULT_SEED := 1950
const BUCKET := CountryGenerator.SPACING * 1.5

var data: Dictionary = {}
var country: Dictionary = {}
var ids: Array = []
var _names: Dictionary = {}
var _seats: Dictionary = {}
var _neighbors: Dictionary = {}
var _centers: Dictionary = {}
var _coastal: Dictionary = {}
var _buckets: Dictionary = {}

func _ready() -> void:
	set_data(CountryGenerator.generate(DEFAULT_SEED))

func generate_new(seed_value: int) -> void:
	set_data(CountryGenerator.generate(seed_value, float(MultiplayerManager.world_settings["province_scale"]), int(MultiplayerManager.world_settings["province_seats"])))

## Geçersiz harita kayıtları yükleme başlamadan reddedilir.
static func supports_data(value: Variant) -> bool:
	return value is Dictionary and String(value.get("kind", "")) == CountryGenerator.KIND \
		and value.get("regions") is Array and not value["regions"].is_empty() \
		and value.get("points") is Array and value.get("labels") is Array \
		and float(value.get("width", 0.0)) > 0.0 and float(value.get("height", 0.0)) > 0.0

func set_data(new_data: Dictionary, prepared: Dictionary = {}) -> void:
	if new_data == data or new_data.is_empty():
		return
	if not supports_data(new_data):
		push_error("Desteklenmeyen harita verisi.")
		return
	data = new_data
	_buckets.clear()
	ids.clear()
	_names.clear()
	_seats.clear()
	_coastal.clear()
	for region in data["regions"]:
		var id := String(region["id"])
		ids.append(id)
		_names[id] = String(region["name"])
		_seats[id] = int(region["seats"])
		_coastal[id] = bool(region.get("coastal", false))
	_derive_country(data, prepared)
	map_changed.emit()

func _derive_country(full: Dictionary, prepared: Dictionary = {}) -> void:
	country = prepared if not prepared.is_empty() else CountryGenerator.geometry(full)
	_neighbors.clear()
	_centers.clear()
	for r in ids.size():
		var id: String = ids[r]
		var list: Array = []
		for o in country["neighbors"][r]:
			list.append(ids[int(o)])
		_neighbors[id] = list
		_centers[id] = country["centers"][r]
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

func center_of(province_id: String) -> Vector2:
	return _centers.get(province_id, Vector2.ZERO)

func map_size() -> Vector2:
	return Vector2(float(data["width"]), float(data["height"]))

func province_at(point: Vector2) -> String:
	return _country_province_at(point)

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
	for region in data.get("regions", []):
		result[String(region["id"])] = int(region.get("electorate", int(region["seats"]) * 100000))
	return result
