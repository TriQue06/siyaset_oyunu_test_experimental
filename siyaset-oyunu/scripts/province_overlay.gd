extends Node2D
## ProvinceMap'in çocuğu. Draws filled polygons per province on top of the
## SVG background, so parties can be shown "painted" over a province without
## touching the underlying vector artwork.
##
## Sınır çizgisi (stroke_color/width), eksen_projeksiyon'daki
## `#svgMapWrapper path { stroke: var(--map-stroke); stroke-width: 1px; }`
## kuralının GDScript karşılığı — boyalı iller arasında net bir ayrım çizgisi
## bırakır.

var polygons_by_province: Dictionary = {}  # province_id -> Array[PackedVector2Array]
var colors: Dictionary = {}                # province_id -> Color

@export var stroke_color: Color = Color(1, 1, 1, 0.55)
@export var stroke_width: float = 0.9

func _draw() -> void:
	for province_id in colors.keys():
		if not polygons_by_province.has(province_id):
			continue
		var color: Color = colors[province_id]
		for polygon in polygons_by_province[province_id]:
			draw_colored_polygon(polygon, color)
			if polygon.size() > 1:
				var closed := PackedVector2Array(polygon)
				closed.append(polygon[0])
				draw_polyline(closed, stroke_color, stroke_width, true)
